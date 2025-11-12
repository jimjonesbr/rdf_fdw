
/*---------------------------------------------------------------------
 *
 * rdf_utils.c
 *   Functions for rdfnode comparison.
 *
 * Copyright (C) 2022-2025 University of Münster, Germany
 * 
 *---------------------------------------------------------------------
 */

#include "postgres.h"
#include "rdf_fdw.h"
#include "rdf_utils.h"
#include "rdfnode.h"
#include "sparql.h"

#include "utils/builtins.h"
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

bool rdfnode_eq(rdfnode *n1, rdfnode *n2)
{
	rdfnode_info a = parse_rdfnode(n1);
	rdfnode_info b = parse_rdfnode(n2);

	elog(DEBUG1, "%s called", __func__);
	elog(DEBUG2, "%s: a.lex='%s', a.dtype='%s', a.lang='%s', a.isNumeric='%d'", __func__,
		 a.lex, a.dtype ? a.dtype : "(null)", a.lang ? a.lang : "(null)", a.isNumeric);
	elog(DEBUG2, "%s: b.lex='%s', b.dtype='%s', b.lang='%s', b.isNumeric='%d'", __func__,
		 b.lex, b.dtype ? b.dtype : "(null)", b.lang ? b.lang : "(null)", b.isNumeric);

	if (a.isIRI && b.isIRI)
		return strcmp(a.raw, b.raw) == 0;
	/*
	 * plain (no language or data type) and xsd:string literals
	 * are considered the same, so we only compare their contents
	 * directly.
	 */
	if ((a.isPlainLiteral && b.isPlainLiteral) ||
		(a.isPlainLiteral && b.isString) ||
		(a.isString && b.isPlainLiteral) ||
		(a.isString && b.isString))
		return varstr_cmp(a.lex, strlen(a.lex),
						  b.lex, strlen(b.lex),
						  DEFAULT_COLLATION_OID) == 0;

	/*
	 * plain literals (no language or data type) can only be compared
	 * to xsd:string or other plain literals.
	 */
	if ((!a.isPlainLiteral && !a.isString && b.isPlainLiteral) ||
		(!b.isPlainLiteral && !b.isString && a.isPlainLiteral))
		return false;

	/* if one literal has a language tag, the other must have one as well */
	if ((strlen(a.lang) != 0 && strlen(b.lang) == 0) ||
		(strlen(a.lang) == 0 && strlen(b.lang) != 0))
		return false;

	/* both literals must share the same language tag, if any */
	if ((strlen(a.lang) != 0 && strlen(b.lang) != 0) &&
		pg_strcasecmp(a.lang, b.lang) != 0)
		return false;

	/* numeric and non-numeric literals cannot be compared */
	if ((a.isNumeric && !b.isNumeric) ||
		(!a.isNumeric && b.isNumeric))
		return false;
	/*
	 * both literals must share the data type tag, except
	 * numeric data types, as "1"^^xsd:int and "1"^xsd:short
	 * are the same.
	 */
	if ((strlen(a.dtype) != 0 && strlen(b.dtype) != 0) &&
		(!a.isNumeric && !b.isNumeric) &&
		strcmp(a.dtype, b.dtype) != 0)
		return false;

	if (a.isNumeric && b.isNumeric)
	{

		Datum a_val;
		Datum b_val;

		if (strcmp(a.dtype, RDF_XSD_DOUBLE) == 0)
		{
			a_val = DirectFunctionCall1(float8in, CStringGetDatum(a.lex));
			b_val = DirectFunctionCall1(float8in, CStringGetDatum(b.lex));

			return DatumGetBool(DirectFunctionCall2(float8eq, a_val, b_val));
		}
		else
		{
			a_val = DirectFunctionCall3(numeric_in,
										CStringGetDatum(a.lex),
										ObjectIdGetDatum(InvalidOid),
										Int32GetDatum(-1));
			b_val = DirectFunctionCall3(numeric_in,
										CStringGetDatum(b.lex),
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
		Datum a_val = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
															  CStringGetDatum(a.lex),
															  ObjectIdGetDatum(InvalidOid),
															  Int32GetDatum(-1)));
		Datum b_val = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
															  CStringGetDatum(b.lex),
															  ObjectIdGetDatum(InvalidOid),
															  Int32GetDatum(-1)));
		TimestampTz a_ts = DatumGetTimestampTz(a_val);
		TimestampTz b_ts = DatumGetTimestampTz(b_val);

		return timestamptz_cmp_internal(a_ts, b_ts) == 0;
	}

	if (a.isDuration && b.isDuration)
	{
		Datum a_val = DirectFunctionCall3(interval_in,
										  CStringGetDatum(a.lex),
										  ObjectIdGetDatum(InvalidOid),
										  Int32GetDatum(-1));
		Datum b_val = DirectFunctionCall3(interval_in,
										  CStringGetDatum(b.lex),
										  ObjectIdGetDatum(InvalidOid),
										  Int32GetDatum(-1));

		return DatumGetBool(DirectFunctionCall2(interval_eq, a_val, b_val));
	}

	elog(DEBUG2, "%s: fallback lexical comparison", __func__);
	return strcmp(a.lex, b.lex) == 0;
}

bool rdfnode_ge(rdfnode *n1, rdfnode *n2)
{
	Datum arg1, arg2;
	rdfnode_info rdfnode1 = parse_rdfnode(n1);
	rdfnode_info rdfnode2 = parse_rdfnode(n2);

	if (!LiteralsComparable(n1, n2))
		return false; /* unreachable due to error in LiteralsComparable, but kept for safety */

	/* SPARQL 1.1 (via IEEE 754) requires false for comparisons involving NaN. */
	if ((rdfnode1.isNumeric && pg_strcasecmp(rdfnode1.lex, "NaN") == 0) ||
		(rdfnode2.isNumeric && pg_strcasecmp(rdfnode2.lex, "NaN") == 0))
		return false;

	/* string and plain literals */
	if ((rdfnode1.isString || rdfnode1.isPlainLiteral) && (rdfnode2.isString || rdfnode2.isPlainLiteral))
	{
		return strcmp(rdfnode1.lex, rdfnode2.lex) >= 0; /* unicode codepoint order */
	}

	/* numeric literals */
	if (rdfnode1.isNumeric && rdfnode2.isNumeric)
	{
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
		/* Check if either literal lacks a timezone */
		bool has_timezone1 = (strstr(rdfnode1.lex, "Z") != NULL ||
							  strpbrk(rdfnode1.lex, "+-") != NULL);
		bool has_timezone2 = (strstr(rdfnode2.lex, "Z") != NULL ||
							  strpbrk(rdfnode2.lex, "+-") != NULL);

		/* If either literal lacks a timezone, they are incomparable */
		if (!has_timezone1 || !has_timezone2)
			return false;

		/* Proceed with timestamp comparison */
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

bool rdfnode_le(rdfnode *n1, rdfnode *n2)
{
	Datum arg1, arg2;
	rdfnode_info rdfnode1 = parse_rdfnode(n1);
	rdfnode_info rdfnode2 = parse_rdfnode(n2);

	if (!LiteralsComparable(n1, n2))
		return false; /* unreachable due to error in LiteralsComparable, but kept for safety */

	/* SPARQL 1.1 (via IEEE 754) requires false for comparisons involving NaN. */
	if ((rdfnode1.isNumeric && pg_strcasecmp(rdfnode1.lex, "NaN") == 0) ||
		(rdfnode2.isNumeric && pg_strcasecmp(rdfnode2.lex, "NaN") == 0))
		return false;

	/* string and plain literals */
	if ((rdfnode1.isString || rdfnode1.isPlainLiteral) && (rdfnode2.isString || rdfnode2.isPlainLiteral))
	{
		return strcmp(rdfnode1.lex, rdfnode2.lex) <= 0; /* unicode codepoint order */
	}

	/* numeric literals */
	if (rdfnode1.isNumeric && rdfnode2.isNumeric)
	{
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
		/* Check if either literal lacks a timezone */
		bool has_timezone1 = (strstr(rdfnode1.lex, "Z") != NULL ||
							  strpbrk(rdfnode1.lex, "+-") != NULL);
		bool has_timezone2 = (strstr(rdfnode2.lex, "Z") != NULL ||
							  strpbrk(rdfnode2.lex, "+-") != NULL);

		/* If either literal lacks a timezone, they are incomparable */
		if (!has_timezone1 || !has_timezone2)
			return false;

		/* Proceed with timestamp comparison */
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

bool rdfnode_gt(rdfnode *n1, rdfnode *n2)
{
	Datum arg1, arg2;
	rdfnode_info rdfnode1 = parse_rdfnode(n1);
	rdfnode_info rdfnode2 = parse_rdfnode(n2);

	if (!LiteralsComparable(n1, n2))
		return false; /* unreachable due to error in LiteralsComparable, but kept for safety */

	/* SPARQL 1.1 (via IEEE 754) requires false for comparisons involving NaN. */
	if ((rdfnode1.isNumeric && pg_strcasecmp(rdfnode1.lex, "NaN") == 0) ||
		(rdfnode2.isNumeric && pg_strcasecmp(rdfnode2.lex, "NaN") == 0))
		return false;

	/* string and plain literals */
	if ((rdfnode1.isString || rdfnode1.isPlainLiteral) && (rdfnode2.isString || rdfnode2.isPlainLiteral))
	{
		return strcmp(rdfnode1.lex, rdfnode2.lex) > 0; /* unicode codepoint order */
	}
	/* numeric literals */
	if (rdfnode1.isNumeric && rdfnode2.isNumeric)
	{
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
		/* Check if either literal lacks a timezone */
		bool has_timezone1 = (strstr(rdfnode1.lex, "Z") != NULL ||
							  strpbrk(rdfnode1.lex, "+-") != NULL);
		bool has_timezone2 = (strstr(rdfnode2.lex, "Z") != NULL ||
							  strpbrk(rdfnode2.lex, "+-") != NULL);

		/* If either literal lacks a timezone, they are incomparable */
		if (!has_timezone1 || !has_timezone2)
			return false;

		/* Proceed with timestamp comparison */
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

bool rdfnode_lt(rdfnode *n1, rdfnode *n2)
{
	Datum arg1, arg2;
	rdfnode_info rdfnode1 = parse_rdfnode(n1);
	rdfnode_info rdfnode2 = parse_rdfnode(n2);

	if (!LiteralsComparable(n1, n2))
		return false; /* unreachable due to error in LiteralsComparable, but kept for safety */

	/* SPARQL 1.1 (via IEEE 754) requires false for comparisons involving NaN. */
	if ((rdfnode1.isNumeric && pg_strcasecmp(rdfnode1.lex, "NaN") == 0) ||
		(rdfnode2.isNumeric && pg_strcasecmp(rdfnode2.lex, "NaN") == 0))
		return false;

	/* string and plain literals */
	if ((rdfnode1.isString || rdfnode1.isPlainLiteral) && (rdfnode2.isString || rdfnode2.isPlainLiteral))
	{
		return strcmp(rdfnode1.lex, rdfnode2.lex) < 0; /* unicode codepoint order */
	}

	/* numeric literals */
	if (rdfnode1.isNumeric && rdfnode2.isNumeric)
	{
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
		/* Check if either literal lacks a timezone */
		bool has_timezone1 = (strstr(rdfnode1.lex, "Z") != NULL ||
							  strpbrk(rdfnode1.lex, "+-") != NULL);
		bool has_timezone2 = (strstr(rdfnode2.lex, "Z") != NULL ||
							  strpbrk(rdfnode2.lex, "+-") != NULL);

		/* If either literal lacks a timezone, they are incomparable */
		if (!has_timezone1 || !has_timezone2)
			return false;

		/* Proceed with timestamp comparison */
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

	/* check for language-tagged literals (not comparable) */
	if (strlen(rdfnode1.lang) != 0 || strlen(rdfnode2.lang) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("cannot compare language-tagged literals")));

	/*
	 * literals are comparable only if both are of the same comparable category:
	 * numeric, date, dateTime, or duration
	 */
	if (bothNumeric || bothDate || bothDateTime || bothDuration || bothString || bothTime)
		return true;

	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
			 errmsg("cannot compare literals of different datatypes")));
}

rdfnode_info parse_rdfnode(rdfnode *node)
{
	rdfnode_info result = {NULL, NULL, NULL, false};
	char *raw = rdfnode_to_cstring(node);
	char *lexical = lex(raw);
	elog(DEBUG1, "%s called: input='%s'", __func__, raw);

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

	/* flag the literal as simple if there is no language or data type*/
	if (strlen(result.dtype) == 0 && strlen(result.lang) == 0)
		result.isPlainLiteral = true;

	if (isIRI(raw))
		result.isIRI = true;
	else if (strcmp(result.dtype, RDF_XSD_STRING) == 0)
	{
		result.isString = true;
		elog(DEBUG2, "literal '%s' is %s ", result.raw, RDF_XSD_STRING);
	}
	else if ((result.isNumeric = isNumeric(raw)))
	{
		elog(DEBUG2, "literal '%s' is numeric ", result.raw);
	}
	else if (strcmp(result.dtype, RDF_XSD_DATE) == 0)
	{
		result.isDate = true;
		elog(DEBUG2, "literal '%s' is %s ", result.raw, RDF_XSD_DATE);
	}
	else if (strcmp(result.dtype, RDF_XSD_DATETIME) == 0)
	{
		result.isDateTime = true;
		elog(DEBUG2, "literal '%s' is %s ", result.raw, RDF_XSD_DATETIME);
	}
	else if (strcmp(result.dtype, RDF_XSD_DURATION) == 0)
	{
		result.isDuration = true;
		elog(DEBUG2, "literal '%s' is %s ", result.raw, RDF_XSD_DURATION);
	}
	else if (strcmp(result.dtype, RDF_XSD_TIME) == 0)
	{
		result.isTime = true;
		elog(DEBUG2, "literal '%s' is %s ", result.raw, RDF_XSD_TIME);
	}
	/*
	 * allow lexicographic comparison for xsd:anyURI literals, aligning with
	 * SPARQL 1.1’s treatment of xsd:anyURI as xsd:string.
	 */
	else if (strcmp(result.dtype, RDF_XSD_ANYURI) == 0)
	{
		result.isPlainLiteral = true;
	}

	elog(DEBUG1, "%s exit", __func__);
	return result;
}
