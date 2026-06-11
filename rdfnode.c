
/*---------------------------------------------------------------------
 *
 * rdfnode.c
 *   rdfnode comparison operators, type ordering, and literal parsing.
 *
 * Copyright (C) 2022-2026 Jim Jones <jim.jones@uni-muenster.de>
 *
 *---------------------------------------------------------------------
 */

#include "postgres.h"
#include "rdf_fdw.h"
#include "rdf_utils.h"
#include "rdfnode.h"
#include "sparql.h"

#include "utils/builtins.h"
#if PG_VERSION_NUM >= 190000
#include "varatt.h"
#endif
#include "utils/date.h"
#include "utils/numeric.h"
#include "utils/timestamp.h"
#include "utils/datetime.h"
#if PG_VERSION_NUM >= 100000
#include "utils/varlena.h"
#endif
#include "catalog/pg_collation.h"
#include "nodes/makefuncs.h"
#include <string.h>

/*
 * datetime_has_tz
 * ---------------
 * Returns true if the XSD dateTime lexical form contains a timezone designator
 * (Z, +HH:MM, or -HH:MM). The search is restricted to the portion of the
 * string after the 'T' (or space) date/time separator so that the '-'
 * characters in the date portion (e.g. 2025-04-25) are not mistaken for
 * a timezone offset.
 */
static bool
datetime_has_tz(const char *lex)
{
	const char *sep = strchr(lex, 'T');

	if (sep == NULL)
		sep = strchr(lex, ' ');   /* accept space-separated variant */
	if (sep == NULL)
		return false;

	/* After the separator the time part uses only digits and ':', so any
	 * 'Z', '+', or '-' that follows must be a timezone designator. */
	return strchr(sep, 'Z') != NULL ||
		   strchr(sep, '+') != NULL ||
		   strchr(sep, '-') != NULL;
}

/*
 * rdfnode_eq
 * ----------
 * Returns true if two rdfnode values are SPARQL-equal.
 *
 * Implements RDF 1.1 / SPARQL 1.1 equality semantics:
 *   - Term equality fast path: byte-identical normalized forms are equal,
 *     even if the lexical is ill-typed (SPARQL §17.4.1.7).
 *   - IRIs and blank nodes compare by raw string.
 *   - Plain literals and xsd:string compare by codepoint.
 *   - Numeric, date, time, dateTime, and duration delegate to PostgreSQL's
 *     value-space comparators.
 *   - Falls back to lexical comparison for unrecognised datatypes.
 *
 * n1, n2: the rdfnode operands
 *
 * returns true if n1 = n2 under SPARQL 1.1 semantics
 */
bool rdfnode_eq(rdfnode *n1, rdfnode *n2)
{
	rdfnode_info a, b;

	elog(DEBUG3, "%s called", __func__);

	/*
	 * === RDF 1.1 term-equality fast path ===
	 *
	 * Two RDF terms are equal if their normalized lexical form, datatype
	 * IRI, and language tag are identical. rdfnode_in() stores literals
	 * in canonical form (datatype IRIs always expanded to <full-iri>),
	 * so byte-identical varlena payloads imply identical RDF terms.
	 *
	 * This MUST short-circuit before any value-space comparison: SPARQL
	 * §17.4.1.7 (RDFterm-equal) requires identical ill-typed literals to
	 * compare equal rather than raise a type error. Without this,
	 *     '"invalid"^^xsd:dateTime' = '"invalid"^^xsd:dateTime'
	 * would call timestamptz_in("invalid") and ERROR instead of returning
	 * TRUE.
	 *
	 * It's also a performance win for the common case of comparing a
	 * literal to itself or to its own canonicalized form.
	 */
	if (VARSIZE_ANY_EXHDR(n1) == VARSIZE_ANY_EXHDR(n2) &&
		memcmp(VARDATA_ANY(n1), VARDATA_ANY(n2), VARSIZE_ANY_EXHDR(n1)) == 0)
		return true;

	a = parse_rdfnode(n1);
	b = parse_rdfnode(n2);

	elog(DEBUG4, "%s: a.lex='%s', a.dtype='%s', a.lang='%s', a.isNumeric='%d'", __func__,
		 a.lex, a.dtype ? a.dtype : "(null)", a.lang ? a.lang : "(null)", a.isNumeric);
	elog(DEBUG4, "%s: b.lex='%s', b.dtype='%s', b.lang='%s', b.isNumeric='%d'", __func__,
		 b.lex, b.dtype ? b.dtype : "(null)", b.lang ? b.lang : "(null)", b.isNumeric);

	if (a.isIRI && b.isIRI)
		return strcmp(a.raw, b.raw) == 0;

	/*
	 * Plain literals (no language or datatype) and xsd:string literals are
	 * value-equal per RDF 1.1, so compare their lexical forms directly.
	 */
	if ((a.isPlainLiteral || a.isString) && (b.isPlainLiteral || b.isString))
		return strcmp(a.lex, b.lex) == 0;

	/*
	 * A plain literal can only compare equal to another plain literal or
	 * an xsd:string. Anything else is inequal.
	 */
	if ((a.isPlainLiteral && !b.isPlainLiteral && !b.isString) ||
		(b.isPlainLiteral && !a.isPlainLiteral && !a.isString))
		return false;

	/* If one has a language tag, both must. */
	if ((strlen(a.lang) != 0) != (strlen(b.lang) != 0))
		return false;

	/* Language tags must match (case-insensitive per BCP 47). */
	if (strlen(a.lang) != 0 && pg_strcasecmp(a.lang, b.lang) != 0)
		return false;

	/* Numeric and non-numeric literals cannot be compared. */
	if (a.isNumeric != b.isNumeric)
		return false;

	/*
	 * For non-numeric datatyped literals, datatypes must match. (Numeric
	 * subtypes such as xsd:int / xsd:short / xsd:integer are interchangeable.)
	 */
	if (!a.isNumeric && !b.isNumeric &&
		strlen(a.dtype) != 0 && strlen(b.dtype) != 0 &&
		strcmp(a.dtype, b.dtype) != 0)
		return false;

	/* === Value-space comparisons === */
	if (a.isNumeric && b.isNumeric)
	{
		Datum a_val, b_val;

		/*
		 * SPARQL 1.1 (via IEEE 754) requires false for comparisons involving NaN,
		 * as stated at 4.3.1 "If $arg1 or $arg2 is NaN, the function returns false."
		 * 
		 * 4.3.1 op:numeric-equal
		 * https://www.w3.org/TR/xpath-functions/#func-numeric-equal
		 */
		if ((a.isNumeric && pg_strcasecmp(a.lex, "NaN") == 0) ||
			(b.isNumeric && pg_strcasecmp(b.lex, "NaN") == 0))
			return false;

		if (strcmp(a.dtype, RDF_XSD_DOUBLE) == 0 ||
			strcmp(b.dtype, RDF_XSD_DOUBLE) == 0 ||
			strcmp(a.dtype, RDF_XSD_FLOAT) == 0 ||
			strcmp(b.dtype, RDF_XSD_FLOAT) == 0)
		{
			a_val = DirectFunctionCall1(float8in, CStringGetDatum(a.lex));
			b_val = DirectFunctionCall1(float8in, CStringGetDatum(b.lex));
			return DatumGetBool(DirectFunctionCall2(float8eq, a_val, b_val));
		}
		else
		{
			a_val = DirectFunctionCall3(numeric_in, CStringGetDatum(a.lex),
										ObjectIdGetDatum(InvalidOid),
										Int32GetDatum(-1));
			b_val = DirectFunctionCall3(numeric_in, CStringGetDatum(b.lex),
										ObjectIdGetDatum(InvalidOid),
										Int32GetDatum(-1));
			return DatumGetBool(DirectFunctionCall2(numeric_eq, a_val, b_val));
		}
	}

	if (a.isDate && b.isDate)
	{
		Datum a_val = DirectFunctionCall1(date_in, CStringGetDatum(a.lex));
		Datum b_val = DirectFunctionCall1(date_in, CStringGetDatum(b.lex));
		return DatumGetBool(DirectFunctionCall2(date_eq, a_val, b_val));
	}

	if (a.isDateTime && b.isDateTime)
	{
		bool a_has_tz = datetime_has_tz(a.lex);
		bool b_has_tz = datetime_has_tz(b.lex);

		/*
		 * Per XSD §3.2.7.4 / SPARQL 1.1 §17.3: a timezone-aware dateTime and
		 * a timezone-naive one are not equal (incomparable value spaces).
		 */
		if (a_has_tz != b_has_tz)
			return false;

		if (a_has_tz)
		{
			/* Both timezone-aware: normalise to UTC and compare. */
			Datum a_val = DirectFunctionCall3(timestamptz_in, CStringGetDatum(a.lex),
											  ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			Datum b_val = DirectFunctionCall3(timestamptz_in, CStringGetDatum(b.lex),
											  ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			return timestamptz_cmp_internal(DatumGetTimestampTz(a_val),
											DatumGetTimestampTz(b_val)) == 0;
		}
		else
		{
			/* Both timezone-naive: compare without any TZ conversion. */
			Datum a_val = DirectFunctionCall3(timestamp_in, CStringGetDatum(a.lex),
											  ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			Datum b_val = DirectFunctionCall3(timestamp_in, CStringGetDatum(b.lex),
											  ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			return DatumGetBool(DirectFunctionCall2(timestamp_eq, a_val, b_val));
		}
	}

	if (a.isBoolean && b.isBoolean)
	{
		Datum a_val = DirectFunctionCall1(boolin, CStringGetDatum(a.lex));
		Datum b_val = DirectFunctionCall1(boolin, CStringGetDatum(b.lex));
		return DatumGetBool(DirectFunctionCall2(booleq, a_val, b_val));
	}

	if (a.isDuration && b.isDuration)
	{
		Datum a_val, b_val;
		bool a_neg = (a.lex[0] == '-');
		bool b_neg = (b.lex[0] == '-');

		a_val = DirectFunctionCall3(interval_in,
									CStringGetDatum(a_neg ? a.lex + 1 : a.lex),
									ObjectIdGetDatum(InvalidOid),
									Int32GetDatum(-1));
		b_val = DirectFunctionCall3(interval_in,
									CStringGetDatum(b_neg ? b.lex + 1 : b.lex),
									ObjectIdGetDatum(InvalidOid),
									Int32GetDatum(-1));

		if (a_neg)
			a_val = DirectFunctionCall1(interval_um, a_val);
		if (b_neg)
			b_val = DirectFunctionCall1(interval_um, b_val);

		return DatumGetBool(DirectFunctionCall2(interval_eq, a_val, b_val));
	}

	elog(DEBUG4, "%s: fallback lexical comparison", __func__);
	return strcmp(a.lex, b.lex) == 0;
}

/*
 * rdfnode_ge
 * ----------
 * Returns true if n1 >= n2 under SPARQL 1.1 comparison semantics.
 * Per IEEE 754 / SPARQL 1.1 §17.3, any comparison involving NaN returns false.
 * dateTime literals that lack a timezone offset are treated as incomparable.
 *
 * n1, n2: the rdfnode operands
 *
 * returns true if n1 >= n2
 */
bool rdfnode_ge(rdfnode *n1, rdfnode *n2)
{
	Datum arg1, arg2;
	rdfnode_info rdfnode1 = parse_rdfnode(n1);
	rdfnode_info rdfnode2 = parse_rdfnode(n2);

	if (!LiteralsComparable(n1, n2))
		return false; /* unreachable due to error in LiteralsComparable, but kept for safety */

	/* string and plain literals */
	if ((rdfnode1.isString || rdfnode1.isPlainLiteral) && (rdfnode2.isString || rdfnode2.isPlainLiteral))
		return strcmp(rdfnode1.lex, rdfnode2.lex) >= 0; /* unicode codepoint order */

	/* numeric literals */
	if (rdfnode1.isNumeric && rdfnode2.isNumeric)
	{
		/*
		 * SPARQL 1.1 (via IEEE 754) requires false for comparisons involving NaN,
		 * as stated at 4.3.3 "The function call op:numeric-greater-than($A, $B)
		 * is defined to return the same result as op:numeric-less-than($B, $A)",
		 * which says "If $arg1 or $arg2 is NaN, the function returns false." --
		 * equally stated at 4.3.1.
		 *
		 * 4.3.3 op:numeric-greater-than
		 * https://www.w3.org/TR/xpath-functions/#func-numeric-greater-than
		 * 4.3.2 op:numeric-less-than
		 * https://www.w3.org/TR/xpath-functions/#func-numeric-less-than
		 * 4.3.1 op:numeric-equal
		 * https://www.w3.org/TR/xpath-functions/#func-numeric-equal
		 */
		if ((rdfnode1.isNumeric && pg_strcasecmp(rdfnode1.lex, "NaN") == 0) ||
			(rdfnode2.isNumeric && pg_strcasecmp(rdfnode2.lex, "NaN") == 0))
			return false;

		if (strcmp(rdfnode1.dtype, RDF_XSD_DOUBLE) == 0)
		{
			arg1 = DirectFunctionCall1(float8in, CStringGetDatum(rdfnode1.lex));
			arg2 = DirectFunctionCall1(float8in, CStringGetDatum(rdfnode2.lex));

			return DatumGetBool(DirectFunctionCall2(float8ge, arg1, arg2));
		}
		else
		{
			arg1 = DirectFunctionCall3(numeric_in,
									   CStringGetDatum(rdfnode1.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));
			arg2 = DirectFunctionCall3(numeric_in,
									   CStringGetDatum(rdfnode2.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));

			return DatumGetBool(DirectFunctionCall2(numeric_ge, arg1, arg2));
		}
	}

	/* xsd:date literals */
	if (rdfnode1.isDate && rdfnode2.isDate)
	{
		arg1 = DirectFunctionCall1(date_in, CStringGetDatum(rdfnode1.lex));
		arg2 = DirectFunctionCall1(date_in, CStringGetDatum(rdfnode2.lex));
		return DatumGetBool(DirectFunctionCall2(date_ge, arg1, arg2));
	}

	if (rdfnode1.isDateTime && rdfnode2.isDateTime)
	{
		bool has_tz1 = datetime_has_tz(rdfnode1.lex);
		bool has_tz2 = datetime_has_tz(rdfnode2.lex);

		/* Mixed timezone: per SPARQL 1.1 §17.3, incomparable. */
		if (has_tz1 != has_tz2)
			return false;

		if (has_tz1)
		{
			arg1 = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
														   CStringGetDatum(rdfnode1.lex),
														   ObjectIdGetDatum(InvalidOid),
														   Int32GetDatum(-1)));
			arg2 = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
														   CStringGetDatum(rdfnode2.lex),
														   ObjectIdGetDatum(InvalidOid),
														   Int32GetDatum(-1)));
			return timestamptz_cmp_internal(arg1, arg2) >= 0;
		}
		else
		{
			arg1 = DirectFunctionCall3(timestamp_in, CStringGetDatum(rdfnode1.lex),
									   ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			arg2 = DirectFunctionCall3(timestamp_in, CStringGetDatum(rdfnode2.lex),
									   ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			return DatumGetBool(DirectFunctionCall2(timestamp_ge, arg1, arg2));
		}
	}

	/* xsd:time literals */
	if (rdfnode1.isTime && rdfnode2.isTime)
	{
		arg1 = DirectFunctionCall3(time_in,
								   CStringGetDatum(rdfnode1.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		arg2 = DirectFunctionCall3(time_in,
								   CStringGetDatum(rdfnode2.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		return DatumGetBool(DirectFunctionCall2(time_ge, arg1, arg2));
	}

	/* xsd:boolean literals */
	if (rdfnode1.isBoolean && rdfnode2.isBoolean)
	{
		arg1 = DirectFunctionCall1(boolin, CStringGetDatum(rdfnode1.lex));
		arg2 = DirectFunctionCall1(boolin, CStringGetDatum(rdfnode2.lex));
		return DatumGetBool(DirectFunctionCall2(boolge, arg1, arg2));
	}

	/* xsd:duration literals */
	if (rdfnode1.isDuration && rdfnode2.isDuration)
	{
		arg1 = DirectFunctionCall3(interval_in,
								   CStringGetDatum(rdfnode1.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		arg2 = DirectFunctionCall3(interval_in,
								   CStringGetDatum(rdfnode2.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));

		return DatumGetBool(DirectFunctionCall2(interval_ge, arg1, arg2));
	}

	return false;
}

/*
 * rdfnode_le
 * ----------
 * Returns true if n1 <= n2 under SPARQL 1.1 comparison semantics.
 * Per IEEE 754 / SPARQL 1.1 §17.3, any comparison involving NaN returns false.
 * dateTime literals that lack a timezone offset are treated as incomparable.
 *
 * n1, n2: the rdfnode operands
 *
 * returns true if n1 <= n2
 */
bool rdfnode_le(rdfnode *n1, rdfnode *n2)
{
	Datum arg1, arg2;
	rdfnode_info rdfnode1 = parse_rdfnode(n1);
	rdfnode_info rdfnode2 = parse_rdfnode(n2);

	if (!LiteralsComparable(n1, n2))
		return false; /* unreachable due to error in LiteralsComparable, but kept for safety */

	/* string and plain literals */
	if ((rdfnode1.isString || rdfnode1.isPlainLiteral) && (rdfnode2.isString || rdfnode2.isPlainLiteral))
	{
		return strcmp(rdfnode1.lex, rdfnode2.lex) <= 0; /* unicode codepoint order */
	}

	/* numeric literals */
	if (rdfnode1.isNumeric && rdfnode2.isNumeric)
	{
		/*
		 * SPARQL 1.1 (via IEEE 754) requires false for comparisons involving NaN,
		 * as stated at 4.3.1 "If $arg1 or $arg2 is NaN, the function returns false."
		 *
		 * 4.3.2 op:numeric-less-than
		 * https://www.w3.org/TR/xpath-functions/#func-numeric-less-than
		 * 4.3.1 op:numeric-equal
		 * https://www.w3.org/TR/xpath-functions/#func-numeric-equal
		 */
		if ((rdfnode1.isNumeric && pg_strcasecmp(rdfnode1.lex, "NaN") == 0) ||
			(rdfnode2.isNumeric && pg_strcasecmp(rdfnode2.lex, "NaN") == 0))
			return false;

		if (strcmp(rdfnode1.dtype, RDF_XSD_DOUBLE) == 0)
		{
			arg1 = DirectFunctionCall1(float8in, CStringGetDatum(rdfnode1.lex));
			arg2 = DirectFunctionCall1(float8in, CStringGetDatum(rdfnode2.lex));

			return DatumGetBool(DirectFunctionCall2(float8le, arg1, arg2));
		}
		else
		{
			arg1 = DirectFunctionCall3(numeric_in,
									   CStringGetDatum(rdfnode1.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));
			arg2 = DirectFunctionCall3(numeric_in,
									   CStringGetDatum(rdfnode2.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));

			return DatumGetBool(DirectFunctionCall2(numeric_le, arg1, arg2));
		}
	}

	/* xsd:date literals */
	if (rdfnode1.isDate && rdfnode2.isDate)
	{
		arg1 = DirectFunctionCall1(date_in, CStringGetDatum(rdfnode1.lex));
		arg2 = DirectFunctionCall1(date_in, CStringGetDatum(rdfnode2.lex));
		return DatumGetBool(DirectFunctionCall2(date_le, arg1, arg2));
	}

	if (rdfnode1.isDateTime && rdfnode2.isDateTime)
	{
		bool has_tz1 = datetime_has_tz(rdfnode1.lex);
		bool has_tz2 = datetime_has_tz(rdfnode2.lex);

		/* Mixed timezone: per SPARQL 1.1 §17.3, incomparable. */
		if (has_tz1 != has_tz2)
			return false;

		if (has_tz1)
		{
			arg1 = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
														   CStringGetDatum(rdfnode1.lex),
														   ObjectIdGetDatum(InvalidOid),
														   Int32GetDatum(-1)));
			arg2 = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
														   CStringGetDatum(rdfnode2.lex),
														   ObjectIdGetDatum(InvalidOid),
														   Int32GetDatum(-1)));
			return timestamptz_cmp_internal(arg1, arg2) <= 0;
		}
		else
		{
			arg1 = DirectFunctionCall3(timestamp_in, CStringGetDatum(rdfnode1.lex),
									   ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			arg2 = DirectFunctionCall3(timestamp_in, CStringGetDatum(rdfnode2.lex),
									   ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			return DatumGetBool(DirectFunctionCall2(timestamp_le, arg1, arg2));
		}
	}

	/* xsd:time literals */
	if (rdfnode1.isTime && rdfnode2.isTime)
	{
		arg1 = DirectFunctionCall3(time_in,
								   CStringGetDatum(rdfnode1.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		arg2 = DirectFunctionCall3(time_in,
								   CStringGetDatum(rdfnode2.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		return DatumGetBool(DirectFunctionCall2(time_le, arg1, arg2));
	}

	/* xsd:boolean literals */
	if (rdfnode1.isBoolean && rdfnode2.isBoolean)
	{
		arg1 = DirectFunctionCall1(boolin, CStringGetDatum(rdfnode1.lex));
		arg2 = DirectFunctionCall1(boolin, CStringGetDatum(rdfnode2.lex));
		return DatumGetBool(DirectFunctionCall2(boolle, arg1, arg2));
	}

	/* xsd:duration literals */
	if (rdfnode1.isDuration && rdfnode2.isDuration)
	{
		arg1 = DirectFunctionCall3(interval_in,
								   CStringGetDatum(rdfnode1.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		arg2 = DirectFunctionCall3(interval_in,
								   CStringGetDatum(rdfnode2.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));

		return DatumGetBool(DirectFunctionCall2(interval_le, arg1, arg2));
	}

	return false;
}

/*
 * rdfnode_gt
 * ----------
 * Returns true if n1 > n2 under SPARQL 1.1 comparison semantics.
 * Per IEEE 754 / SPARQL 1.1 §17.3, any comparison involving NaN returns false.
 * dateTime literals that lack a timezone offset are treated as incomparable.
 *
 * n1, n2: the rdfnode operands
 *
 * returns true if n1 > n2
 */
bool rdfnode_gt(rdfnode *n1, rdfnode *n2)
{
	Datum arg1, arg2;
	rdfnode_info rdfnode1 = parse_rdfnode(n1);
	rdfnode_info rdfnode2 = parse_rdfnode(n2);

	if (!LiteralsComparable(n1, n2))
		return false; /* unreachable due to error in LiteralsComparable, but kept for safety */

	/* string and plain literals */
	if ((rdfnode1.isString || rdfnode1.isPlainLiteral) && (rdfnode2.isString || rdfnode2.isPlainLiteral))
	{
		return strcmp(rdfnode1.lex, rdfnode2.lex) > 0; /* unicode codepoint order */
	}
	/* numeric literals */
	if (rdfnode1.isNumeric && rdfnode2.isNumeric)
	{
		/*
		 * SPARQL 1.1 (via IEEE 754) requires false for comparisons involving NaN,
		 * as stated at 4.3.3 "The function call op:numeric-greater-than($A, $B)
		 * is defined to return the same result as op:numeric-less-than($B, $A)",
		 * which says "If $arg1 or $arg2 is NaN, the function returns false."
		 *
		 * 4.3.3 op:numeric-greater-than
		 * https://www.w3.org/TR/xpath-functions/#func-numeric-greater-than
		 * 4.3.2 op:numeric-less-than
		 * https://www.w3.org/TR/xpath-functions/#func-numeric-less-than
		 */
		if ((rdfnode1.isNumeric && pg_strcasecmp(rdfnode1.lex, "NaN") == 0) ||
			(rdfnode2.isNumeric && pg_strcasecmp(rdfnode2.lex, "NaN") == 0))
			return false;

		if (strcmp(rdfnode1.dtype, RDF_XSD_DOUBLE) == 0)
		{
			arg1 = DirectFunctionCall1(float8in, CStringGetDatum(rdfnode1.lex));
			arg2 = DirectFunctionCall1(float8in, CStringGetDatum(rdfnode2.lex));

			return DatumGetBool(DirectFunctionCall2(float8gt, arg1, arg2));
		}
		else
		{
			arg1 = DirectFunctionCall3(numeric_in,
									   CStringGetDatum(rdfnode1.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));
			arg2 = DirectFunctionCall3(numeric_in,
									   CStringGetDatum(rdfnode2.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));

			return DatumGetBool(DirectFunctionCall2(numeric_gt, arg1, arg2));
		}
	}

	/* xsd:date literals */
	if (rdfnode1.isDate && rdfnode2.isDate)
	{
		arg1 = DirectFunctionCall1(date_in, CStringGetDatum(rdfnode1.lex));
		arg2 = DirectFunctionCall1(date_in, CStringGetDatum(rdfnode2.lex));
		return DatumGetBool(DirectFunctionCall2(date_gt, arg1, arg2));
	}

	/* xsd:dateTime literals */
	if (rdfnode1.isDateTime && rdfnode2.isDateTime)
	{
		bool has_tz1 = datetime_has_tz(rdfnode1.lex);
		bool has_tz2 = datetime_has_tz(rdfnode2.lex);

		/* Mixed timezone: per SPARQL 1.1 §17.3, incomparable. */
		if (has_tz1 != has_tz2)
			return false;

		if (has_tz1)
		{
			arg1 = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
														   CStringGetDatum(rdfnode1.lex),
														   ObjectIdGetDatum(InvalidOid),
														   Int32GetDatum(-1)));
			arg2 = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
														   CStringGetDatum(rdfnode2.lex),
														   ObjectIdGetDatum(InvalidOid),
														   Int32GetDatum(-1)));
			return timestamptz_cmp_internal(arg1, arg2) > 0;
		}
		else
		{
			arg1 = DirectFunctionCall3(timestamp_in, CStringGetDatum(rdfnode1.lex),
									   ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			arg2 = DirectFunctionCall3(timestamp_in, CStringGetDatum(rdfnode2.lex),
									   ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			return DatumGetBool(DirectFunctionCall2(timestamp_gt, arg1, arg2));
		}
	}

	/* xsd:time literals */
	if (rdfnode1.isTime && rdfnode2.isTime)
	{
		arg1 = DirectFunctionCall3(time_in,
								   CStringGetDatum(rdfnode1.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		arg2 = DirectFunctionCall3(time_in,
								   CStringGetDatum(rdfnode2.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		return DatumGetBool(DirectFunctionCall2(time_gt, arg1, arg2));
	}

	/* xsd:boolean literals */
	if (rdfnode1.isBoolean && rdfnode2.isBoolean)
	{
		arg1 = DirectFunctionCall1(boolin, CStringGetDatum(rdfnode1.lex));
		arg2 = DirectFunctionCall1(boolin, CStringGetDatum(rdfnode2.lex));
		return DatumGetBool(DirectFunctionCall2(boolgt, arg1, arg2));
	}

	/* xsd:duration literals */
	if (rdfnode1.isDuration && rdfnode2.isDuration)
	{
		arg1 = DirectFunctionCall3(interval_in,
								   CStringGetDatum(rdfnode1.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		arg2 = DirectFunctionCall3(interval_in,
								   CStringGetDatum(rdfnode2.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));

		return DatumGetBool(DirectFunctionCall2(interval_gt, arg1, arg2));
	}

	return false;
}

/*
 * rdfnode_lt
 * ----------
 * Returns true if n1 < n2 under SPARQL 1.1 comparison semantics.
 * Per IEEE 754 / SPARQL 1.1 §17.3, any comparison involving NaN returns false.
 * dateTime literals that lack a timezone offset are treated as incomparable.
 *
 * n1, n2: the rdfnode operands
 *
 * returns true if n1 < n2
 */
bool rdfnode_lt(rdfnode *n1, rdfnode *n2)
{
	Datum arg1, arg2;
	rdfnode_info rdfnode1 = parse_rdfnode(n1);
	rdfnode_info rdfnode2 = parse_rdfnode(n2);

	if (!LiteralsComparable(n1, n2))
		return false; /* unreachable due to error in LiteralsComparable, but kept for safety */

	/* string and plain literals */
	if ((rdfnode1.isString || rdfnode1.isPlainLiteral) && (rdfnode2.isString || rdfnode2.isPlainLiteral))
	{
		return strcmp(rdfnode1.lex, rdfnode2.lex) < 0; /* unicode codepoint order */
	}

	/* numeric literals */
	if (rdfnode1.isNumeric && rdfnode2.isNumeric)
	{
		/*
		 * SPARQL 1.1 (via IEEE 754) requires false for comparisons involving NaN,
		 * as stated at 4.3.2 "If $arg1 or $arg2 is NaN, the function returns false."
		 *
		 * 4.3.2 op:numeric-less-than
		 * https://www.w3.org/TR/xpath-functions/#func-numeric-less-than
		 */
		if ((rdfnode1.isNumeric && pg_strcasecmp(rdfnode1.lex, "NaN") == 0) ||
			(rdfnode2.isNumeric && pg_strcasecmp(rdfnode2.lex, "NaN") == 0))
			return false;

		if (strcmp(rdfnode1.dtype, RDF_XSD_DOUBLE) == 0)
		{
			arg1 = DirectFunctionCall1(float8in, CStringGetDatum(rdfnode1.lex));
			arg2 = DirectFunctionCall1(float8in, CStringGetDatum(rdfnode2.lex));

			return DatumGetBool(DirectFunctionCall2(float8lt, arg1, arg2));
		}
		else
		{
			arg1 = DirectFunctionCall3(numeric_in,
									   CStringGetDatum(rdfnode1.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));
			arg2 = DirectFunctionCall3(numeric_in,
									   CStringGetDatum(rdfnode2.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));

			return DatumGetBool(DirectFunctionCall2(numeric_lt, arg1, arg2));
		}
	}

	/* xsd:date literals */
	if (rdfnode1.isDate && rdfnode2.isDate)
	{
		arg1 = DirectFunctionCall1(date_in, CStringGetDatum(rdfnode1.lex));
		arg2 = DirectFunctionCall1(date_in, CStringGetDatum(rdfnode2.lex));
		return DatumGetBool(DirectFunctionCall2(date_lt, arg1, arg2));
	}

	/* xsd:dateTime literals */
	if (rdfnode1.isDateTime && rdfnode2.isDateTime)
	{
		bool has_tz1 = datetime_has_tz(rdfnode1.lex);
		bool has_tz2 = datetime_has_tz(rdfnode2.lex);

		/* Mixed timezone: per SPARQL 1.1 §17.3, incomparable. */
		if (has_tz1 != has_tz2)
			return false;

		if (has_tz1)
		{
			arg1 = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
														   CStringGetDatum(rdfnode1.lex),
														   ObjectIdGetDatum(InvalidOid),
														   Int32GetDatum(-1)));
			arg2 = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
														   CStringGetDatum(rdfnode2.lex),
														   ObjectIdGetDatum(InvalidOid),
														   Int32GetDatum(-1)));
			return timestamptz_cmp_internal(arg1, arg2) < 0;
		}
		else
		{
			arg1 = DirectFunctionCall3(timestamp_in, CStringGetDatum(rdfnode1.lex),
									   ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			arg2 = DirectFunctionCall3(timestamp_in, CStringGetDatum(rdfnode2.lex),
									   ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			return DatumGetBool(DirectFunctionCall2(timestamp_lt, arg1, arg2));
		}
	}

	/* xsd:time literals */
	if (rdfnode1.isTime && rdfnode2.isTime)
	{
		arg1 = DirectFunctionCall3(time_in,
								   CStringGetDatum(rdfnode1.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		arg2 = DirectFunctionCall3(time_in,
								   CStringGetDatum(rdfnode2.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		return DatumGetBool(DirectFunctionCall2(time_lt, arg1, arg2));
	}

	/* xsd:boolean literals */
	if (rdfnode1.isBoolean && rdfnode2.isBoolean)
	{
		arg1 = DirectFunctionCall1(boolin, CStringGetDatum(rdfnode1.lex));
		arg2 = DirectFunctionCall1(boolin, CStringGetDatum(rdfnode2.lex));
		return DatumGetBool(DirectFunctionCall2(boollt, arg1, arg2));
	}

	/* xsd:duration literals */
	if (rdfnode1.isDuration && rdfnode2.isDuration)
	{
		arg1 = DirectFunctionCall3(interval_in,
								   CStringGetDatum(rdfnode1.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		arg2 = DirectFunctionCall3(interval_in,
								   CStringGetDatum(rdfnode2.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));

		return DatumGetBool(DirectFunctionCall2(interval_lt, arg1, arg2));
	}

	return false;
}

/*
 * getSparqlTermOrder
 *
 * Helper function for SPARQL 1.1 term ordering (Section 15.1).
 *
 * Returns an integer representing the RDF term's position in SPARQL
 * ordering. Lower values come first in MIN and ORDER BY ASC, later in
 * MAX and ORDER BY DESC.
 *
 * SPARQL 1.1 Query Language Recommendation (21 March 2013)
 * https://www.w3.org/TR/sparql11-query/#modOrderBy
 *
 * Section 15.1 ORDER BY states:
 * "SPARQL also fixes an order between some kinds of RDF terms that
 *  would not otherwise be ordered:
 *  1. (Lowest) no value assigned to the variable or expression in
 *     this solution.
 *  2. Blank nodes
 *  3. IRIs
 *  4. RDF literals"
 *
 * For literals, the spec further states:
 * "A plain literal is lower than an RDF literal with type xsd:string
 *  of the same lexical form."
 *
 * The relative ordering of different typed literals is
 * implementation-dependent but must be consistent. This implementation
 * orders typed literals by their datatype semantics for practical
 * query results:
 *   - Numerics before temporal types before strings
 *   - Within temporal types: dateTime < date < time < duration
 *
 * This ordering ensures that MIN/MAX aggregates produce intuitive
 * results when mixing datatypes, e.g.:
 *   MIN(42, "hello") returns 42 (numeric < string, so 42 is minimum)
 *   MAX(42, "hello") returns "hello" (string > numeric, so "hello" is
 *   maximum)
 */
static int getSparqlTermOrder(rdfnode_info *node)
{
	if (node->isIRI)
		return 0; /* IRIs (SPARQL 1.1 Section 15.1 #3) */
	if (strlen(node->lang) > 0)
		return 1; /* Language-tagged literals (part of RDF literals) */
	if (node->isPlainLiteral)
		return 2; /* Simple literals (SPARQL 1.1: lower than xsd:string) */
	if (node->isNumeric)
		return 3; /* Numeric types (implementation choice: before temporal) */
	if (node->isDateTime)
		return 4; /* xsd:dateTime (implementation choice: within temporal) */
	if (node->isDate)
		return 5; /* xsd:date (implementation choice: within temporal) */
	if (node->isTime)
		return 6; /* xsd:time (implementation choice: within temporal) */
	if (node->isDuration)
		return 7; /* xsd:duration (implementation choice: within temporal) */
	if (node->isString)
		return 8; /* xsd:string (SPARQL 1.1: higher than plain literals) */
	return 9;	  /* Other typed literals (implementation choice: last) */
}

/*
 * rdfnode_cmp_for_aggregate
 *
 * Comparison function for SPARQL aggregates (MIN/MAX) that implements
 * SPARQL term ordering, allowing comparison across different
 * datatypes.
 *
 * Returns: -1 if n1 < n2, 0 if n1 == n2, 1 if n1 > n2
 *
 * SPARQL 1.1 term ordering (Section 17.3.1):
 * 1. IRIs < Blank Nodes < Literals
 * 2. Within literals:
 *    - Language-tagged literals < Simple literals < Typed literals
 *    - Typed literals ordered by: boolean < numeric < datetime <
 *      date < time < duration < string < other
 * 3. Within same type: use type-specific comparison
 *
 * Note: This comparator defines a consistent cross-type order only.
 * Aggregate functions MIN/MAX may apply additional mixed-type policies
 * (e.g., Fuseki-style: MIN prefers non-numeric when mixed; MAX prefers
 * numeric when mixed). Within a chosen category, this comparator is
 * still used to compare values.
 */
int rdfnode_cmp_for_aggregate(rdfnode *n1, rdfnode *n2)
{
	rdfnode_info rdfnode1 = parse_rdfnode(n1);
	rdfnode_info rdfnode2 = parse_rdfnode(n2);
	Datum arg1, arg2;
	int typeOrder1, typeOrder2;

	elog(DEBUG3, "%s called", __func__);
	elog(DEBUG4, "%s: n1='%s', n2='%s'", __func__, rdfnode1.raw, rdfnode2.raw);

	/* Get SPARQL term order for both nodes */
	typeOrder1 = getSparqlTermOrder(&rdfnode1);
	typeOrder2 = getSparqlTermOrder(&rdfnode2);

	/* Different type categories: compare by SPARQL term order */
	if (typeOrder1 != typeOrder2)
		return (typeOrder1 < typeOrder2) ? -1 : 1;

	/* Same type category: use type-specific comparison */

	/* IRIs: lexical comparison */
	if (rdfnode1.isIRI && rdfnode2.isIRI)
		return strcmp(rdfnode1.raw, rdfnode2.raw);

	/* Language-tagged literals: compare by lang tag, then by lexical value */
	if (strlen(rdfnode1.lang) > 0 && strlen(rdfnode2.lang) > 0)
	{
		int langCmp = pg_strcasecmp(rdfnode1.lang, rdfnode2.lang);
		if (langCmp != 0)
			return langCmp;
		return strcmp(rdfnode1.lex, rdfnode2.lex); /* unicode codepoint order */
	}

	/* Simple literals and xsd:string: lexical comparison */
	if ((rdfnode1.isPlainLiteral || rdfnode1.isString) &&
		(rdfnode2.isPlainLiteral || rdfnode2.isString))
		return strcmp(rdfnode1.lex, rdfnode2.lex); /* unicode codepoint order */

	/* Numeric literals: use numeric comparison */
	if (rdfnode1.isNumeric && rdfnode2.isNumeric)
	{
		Numeric num1, num2;
		double d1, d2;
		float f1, f2;

		if (strcmp(rdfnode1.dtype, RDF_XSD_DOUBLE) == 0 && strcmp(rdfnode2.dtype, RDF_XSD_DOUBLE) == 0)
		{
			arg1 = DirectFunctionCall1(float8in, CStringGetDatum(rdfnode1.lex));
			arg2 = DirectFunctionCall1(float8in, CStringGetDatum(rdfnode2.lex));
			d1 = DatumGetFloat8(arg1);
			d2 = DatumGetFloat8(arg2);
			return (d1 < d2) ? -1 : (d1 > d2) ? 1
											  : 0;
		}
		else if (strcmp(rdfnode1.dtype, RDF_XSD_FLOAT) == 0 && strcmp(rdfnode2.dtype, RDF_XSD_FLOAT) == 0)
		{
			arg1 = DirectFunctionCall1(float4in, CStringGetDatum(rdfnode1.lex));
			arg2 = DirectFunctionCall1(float4in, CStringGetDatum(rdfnode2.lex));
			f1 = DatumGetFloat4(arg1);
			f2 = DatumGetFloat4(arg2);
			return (f1 < f2) ? -1 : (f1 > f2) ? 1
											  : 0;
		}
		else
		{
			num1 = DatumGetNumeric(DirectFunctionCall3(numeric_in,
													   CStringGetDatum(rdfnode1.lex),
													   ObjectIdGetDatum(InvalidOid),
													   Int32GetDatum(-1)));
			num2 = DatumGetNumeric(DirectFunctionCall3(numeric_in,
													   CStringGetDatum(rdfnode2.lex),
													   ObjectIdGetDatum(InvalidOid),
													   Int32GetDatum(-1)));
			return DatumGetInt32(DirectFunctionCall2(numeric_cmp,
													 NumericGetDatum(num1),
													 NumericGetDatum(num2)));
		}
	}

	/* xsd:date literals */
	if (rdfnode1.isDate && rdfnode2.isDate)
	{
		DateADT date1, date2;

		arg1 = DirectFunctionCall1(date_in, CStringGetDatum(rdfnode1.lex));
		arg2 = DirectFunctionCall1(date_in, CStringGetDatum(rdfnode2.lex));
		date1 = DatumGetDateADT(arg1);
		date2 = DatumGetDateADT(arg2);
		return (date1 < date2) ? -1 : (date1 > date2) ? 1
													  : 0;
	}

	/* xsd:dateTime literals */
	if (rdfnode1.isDateTime && rdfnode2.isDateTime)
	{
		bool has_tz1 = datetime_has_tz(rdfnode1.lex);
		bool has_tz2 = datetime_has_tz(rdfnode2.lex);

		if (has_tz1 && has_tz2)
		{
			TimestampTz ts1 = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
												  CStringGetDatum(rdfnode1.lex),
												  ObjectIdGetDatum(InvalidOid),
												  Int32GetDatum(-1)));
			TimestampTz ts2 = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
												  CStringGetDatum(rdfnode2.lex),
												  ObjectIdGetDatum(InvalidOid),
												  Int32GetDatum(-1)));
			return timestamptz_cmp_internal(ts1, ts2);
		}
		else if (!has_tz1 && !has_tz2)
		{
			Datum d1 = DirectFunctionCall3(timestamp_in, CStringGetDatum(rdfnode1.lex),
										   ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			Datum d2 = DirectFunctionCall3(timestamp_in, CStringGetDatum(rdfnode2.lex),
										   ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
			return DatumGetInt32(DirectFunctionCall2(timestamp_cmp, d1, d2));
		}
		else
		{
			/* Mixed: timezone-aware sorts after timezone-naive for a stable order. */
			return has_tz1 ? 1 : -1;
		}
	}

	/* xsd:time literals */
	if (rdfnode1.isTime && rdfnode2.isTime)
	{
		TimeADT time1, time2;

		arg1 = DirectFunctionCall3(time_in,
								   CStringGetDatum(rdfnode1.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		arg2 = DirectFunctionCall3(time_in,
								   CStringGetDatum(rdfnode2.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		time1 = DatumGetTimeADT(arg1);
		time2 = DatumGetTimeADT(arg2);
		return (time1 < time2) ? -1 : (time1 > time2) ? 1
													  : 0;
	}

	/* xsd:duration literals */
	if (rdfnode1.isDuration && rdfnode2.isDuration)
	{
		arg1 = DirectFunctionCall3(interval_in,
								   CStringGetDatum(rdfnode1.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		arg2 = DirectFunctionCall3(interval_in,
								   CStringGetDatum(rdfnode2.lex),
								   ObjectIdGetDatum(InvalidOid),
								   Int32GetDatum(-1));
		return DatumGetInt32(DirectFunctionCall2(interval_cmp, arg1, arg2));
	}

	/* Other typed literals: lexical comparison as fallback */
	return strcmp(rdfnode1.lex, rdfnode2.lex);
}

/*
 * LiteralsComparable
 * ------------------
 * Checks whether two rdfnode values can be ordered with relational operators
 * (<, <=, >=, >) under SPARQL 1.1 rules. Language-tagged literals are never
 * comparable. All other pairs must share the same type category (both numeric,
 * both temporal, etc.).
 *
 * Raises an ERROR rather than returning false when operands are incompatible,
 * matching SPARQL semantics (a type error, not a NULL result).
 *
 * n1, n2: the rdfnode operands to check
 *
 * returns true if the values can be ordered; raises ERROR otherwise
 */
bool LiteralsComparable(rdfnode *n1, rdfnode *n2)
{
	rdfnode_info rdfnode1 = parse_rdfnode(n1);
	rdfnode_info rdfnode2 = parse_rdfnode(n2);
	/* identify the shared type category between the two literals */
	bool bothNumeric = rdfnode1.isNumeric && rdfnode2.isNumeric;
	bool bothDate = rdfnode1.isDate && rdfnode2.isDate;
	bool bothDateTime = rdfnode1.isDateTime && rdfnode2.isDateTime;
	bool bothTime = rdfnode1.isTime && rdfnode2.isTime;
	bool bothDuration = rdfnode1.isDuration && rdfnode2.isDuration;
	bool bothString = (rdfnode1.isString || rdfnode1.isPlainLiteral) &&
					  (rdfnode2.isString || rdfnode2.isPlainLiteral);
	bool bothBoolean = rdfnode1.isBoolean && rdfnode2.isBoolean;

	/* check for language-tagged literals (not comparable) */
	if (strlen(rdfnode1.lang) != 0 || strlen(rdfnode2.lang) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("cannot compare language-tagged literals")));

	/*
	 * literals are comparable only if both are of the same comparable category:
	 * numeric, date, dateTime, or duration
	 */
	if (bothNumeric || bothDate || bothDateTime || bothDuration || bothString || bothTime || bothBoolean)
		return true;

	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("cannot compare literals of different datatypes")));
}

/*
 * parse_rdfnode
 * -------------
 * Decodes a raw rdfnode varlena value into an rdfnode_info struct, extracting
 * the lexical value (with Unicode escapes resolved), datatype URI, language tag,
 * and setting the type-classification flags used by all comparison and aggregate
 * functions.
 *
 * node: the rdfnode value to parse
 *
 * returns a populated rdfnode_info; all flag fields reflect the node's datatype
 */
rdfnode_info parse_rdfnode(rdfnode *node)
{
	rdfnode_info result = {NULL, NULL, NULL, false};
	char *raw = rdfnode_to_cstring(node);
	char *lexical = lex(raw);
	elog(DEBUG3, "%s called: input='%s'", __func__, raw);

	result.raw = raw;
	result.lex = unescape_unicode(lexical);
	result.dtype = datatype(raw);
	result.lang = lang(raw);
	/* initialize all flags */
	result.isPlainLiteral = false;
	result.isDate = false;
	result.isDateTime = false;
	result.isString = false;
	result.isNumeric = false;
	result.isDuration = false;
	result.isTime = false;
	result.isIRI = false;
	result.isBoolean = false;

	/* flag the literal as simple if there is no language or data type*/
	if (strlen(result.dtype) == 0 && strlen(result.lang) == 0)
		result.isPlainLiteral = true;

	if (isIRI(raw))
		result.isIRI = true;
	else if (strcmp(result.dtype, RDF_XSD_STRING) == 0)
		result.isString = true;
	else if ((result.isNumeric = isNumeric(raw)))
		elog(DEBUG4, "literal '%s' is numeric ", result.raw);
	else if (strcmp(result.dtype, RDF_XSD_DATE) == 0)
		result.isDate = true;
	else if (strcmp(result.dtype, RDF_XSD_DATETIME) == 0)
		result.isDateTime = true;
	else if (strcmp(result.dtype, RDF_XSD_DURATION) == 0)
		result.isDuration = true;
	else if (strcmp(result.dtype, RDF_XSD_TIME) == 0)
		result.isTime = true;
	else if (strcmp(result.dtype, RDF_XSD_BOOLEAN) == 0)
		result.isBoolean = true;
	/*
	 * allow lexicographic comparison for xsd:anyURI literals, aligning with
	 * SPARQL 1.1’s treatment of xsd:anyURI as xsd:string.
	 */
	else if (strcmp(result.dtype, RDF_XSD_ANYURI) == 0)
		result.isPlainLiteral = true;

	elog(DEBUG4, "literal '%s' is %s ", result.raw, result.dtype);

	elog(DEBUG3, "%s exit", __func__);
	return result;
}
