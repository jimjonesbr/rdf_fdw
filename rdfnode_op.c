/*---------------------------------------------------------------------
 *
 * rdfnode_op.c
 *
 * SQL-callable functions of the rdfnode data type: input and output,
 * the comparison and arithmetic operators, and the casts to and from
 * PostgreSQL types. The RDF semantics they rely on are in rdfnode.c.
 *
 * Copyright (C) 2022-2026 Jim Jones <jim.jones@uni-muenster.de>
 *
 *---------------------------------------------------------------------
 */
#include "postgres.h"

#include "rdf_fdw.h"
#include "rdf_utils.h"
#include "rdfnode.h"
#include "rdfnode_op.h"
#include "sparql.h"

#include "fmgr.h"
#include "utils/builtins.h"
/* the VARSIZE/VARDATA macros, which before v16 come with postgres.h */
#if PG_VERSION_NUM >= 160000
#include "varatt.h"
#endif
#include "utils/date.h"
#include "utils/datetime.h"
#include "utils/numeric.h"
#include "utils/timestamp.h"
#include <math.h>

/* rdfnode (custom data type) */
PG_FUNCTION_INFO_V1(rdfnode_in);
PG_FUNCTION_INFO_V1(rdfnode_out);
PG_FUNCTION_INFO_V1(rdfnode_to_text);
PG_FUNCTION_INFO_V1(rdfnode_cmp);
PG_FUNCTION_INFO_V1(rdfnode_storage_lt);
PG_FUNCTION_INFO_V1(rdfnode_storage_le);
PG_FUNCTION_INFO_V1(rdfnode_storage_eq);
PG_FUNCTION_INFO_V1(rdfnode_storage_ge);
PG_FUNCTION_INFO_V1(rdfnode_storage_gt);
PG_FUNCTION_INFO_V1(rdfnode_add_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_sub_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_mul_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_div_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_eq_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_neq_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_lt_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_gt_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_le_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_ge_rdfnode);

/* numeric data type */
PG_FUNCTION_INFO_V1(rdfnode_to_numeric);
PG_FUNCTION_INFO_V1(rdfnode_eq_numeric);
PG_FUNCTION_INFO_V1(rdfnode_neq_numeric);
PG_FUNCTION_INFO_V1(rdfnode_lt_numeric);
PG_FUNCTION_INFO_V1(rdfnode_gt_numeric);
PG_FUNCTION_INFO_V1(rdfnode_le_numeric);
PG_FUNCTION_INFO_V1(rdfnode_ge_numeric);
PG_FUNCTION_INFO_V1(numeric_to_rdfnode);
PG_FUNCTION_INFO_V1(numeric_eq_rdfnode);
PG_FUNCTION_INFO_V1(numeric_neq_rdfnode);
PG_FUNCTION_INFO_V1(numeric_lt_rdfnode);
PG_FUNCTION_INFO_V1(numeric_gt_rdfnode);
PG_FUNCTION_INFO_V1(numeric_le_rdfnode);
PG_FUNCTION_INFO_V1(numeric_ge_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_add_numeric);
PG_FUNCTION_INFO_V1(rdfnode_sub_numeric);
PG_FUNCTION_INFO_V1(rdfnode_mul_numeric);
PG_FUNCTION_INFO_V1(rdfnode_div_numeric);
PG_FUNCTION_INFO_V1(numeric_add_rdfnode);
PG_FUNCTION_INFO_V1(numeric_sub_rdfnode);
PG_FUNCTION_INFO_V1(numeric_mul_rdfnode);
PG_FUNCTION_INFO_V1(numeric_div_rdfnode);

/* float8 (double precision) data type */
PG_FUNCTION_INFO_V1(rdfnode_neq_float8);
PG_FUNCTION_INFO_V1(rdfnode_eq_float8);
PG_FUNCTION_INFO_V1(rdfnode_lt_float8);
PG_FUNCTION_INFO_V1(rdfnode_gt_float8);
PG_FUNCTION_INFO_V1(rdfnode_le_float8);
PG_FUNCTION_INFO_V1(rdfnode_ge_float8);
PG_FUNCTION_INFO_V1(rdfnode_to_float8);
PG_FUNCTION_INFO_V1(float8_eq_rdfnode);
PG_FUNCTION_INFO_V1(float8_neq_rdfnode);
PG_FUNCTION_INFO_V1(float8_lt_rdfnode);
PG_FUNCTION_INFO_V1(float8_gt_rdfnode);
PG_FUNCTION_INFO_V1(float8_le_rdfnode);
PG_FUNCTION_INFO_V1(float8_ge_rdfnode);
PG_FUNCTION_INFO_V1(float8_to_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_add_float8);
PG_FUNCTION_INFO_V1(rdfnode_sub_float8);
PG_FUNCTION_INFO_V1(rdfnode_mul_float8);
PG_FUNCTION_INFO_V1(rdfnode_div_float8);
PG_FUNCTION_INFO_V1(float8_add_rdfnode);
PG_FUNCTION_INFO_V1(float8_sub_rdfnode);
PG_FUNCTION_INFO_V1(float8_mul_rdfnode);
PG_FUNCTION_INFO_V1(float8_div_rdfnode);

/* float4 (real) data type */
PG_FUNCTION_INFO_V1(rdfnode_to_float4);
PG_FUNCTION_INFO_V1(rdfnode_eq_float4);
PG_FUNCTION_INFO_V1(rdfnode_neq_float4);
PG_FUNCTION_INFO_V1(rdfnode_lt_float4);
PG_FUNCTION_INFO_V1(rdfnode_gt_float4);
PG_FUNCTION_INFO_V1(rdfnode_le_float4);
PG_FUNCTION_INFO_V1(rdfnode_ge_float4);
PG_FUNCTION_INFO_V1(float4_to_rdfnode);
PG_FUNCTION_INFO_V1(float4_eq_rdfnode);
PG_FUNCTION_INFO_V1(float4_neq_rdfnode);
PG_FUNCTION_INFO_V1(float4_lt_rdfnode);
PG_FUNCTION_INFO_V1(float4_gt_rdfnode);
PG_FUNCTION_INFO_V1(float4_le_rdfnode);
PG_FUNCTION_INFO_V1(float4_ge_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_add_float4);
PG_FUNCTION_INFO_V1(rdfnode_sub_float4);
PG_FUNCTION_INFO_V1(rdfnode_mul_float4);
PG_FUNCTION_INFO_V1(rdfnode_div_float4);
PG_FUNCTION_INFO_V1(float4_add_rdfnode);
PG_FUNCTION_INFO_V1(float4_sub_rdfnode);
PG_FUNCTION_INFO_V1(float4_mul_rdfnode);
PG_FUNCTION_INFO_V1(float4_div_rdfnode);

/* int8 (bigint) data type */
PG_FUNCTION_INFO_V1(rdfnode_to_int8);
PG_FUNCTION_INFO_V1(rdfnode_eq_int8);
PG_FUNCTION_INFO_V1(rdfnode_neq_int8);
PG_FUNCTION_INFO_V1(rdfnode_lt_int8);
PG_FUNCTION_INFO_V1(rdfnode_gt_int8);
PG_FUNCTION_INFO_V1(rdfnode_le_int8);
PG_FUNCTION_INFO_V1(rdfnode_ge_int8);
PG_FUNCTION_INFO_V1(int8_to_rdfnode);
PG_FUNCTION_INFO_V1(int8_eq_rdfnode);
PG_FUNCTION_INFO_V1(int8_neq_rdfnode);
PG_FUNCTION_INFO_V1(int8_lt_rdfnode);
PG_FUNCTION_INFO_V1(int8_gt_rdfnode);
PG_FUNCTION_INFO_V1(int8_le_rdfnode);
PG_FUNCTION_INFO_V1(int8_ge_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_add_int8);
PG_FUNCTION_INFO_V1(rdfnode_sub_int8);
PG_FUNCTION_INFO_V1(rdfnode_mul_int8);
PG_FUNCTION_INFO_V1(rdfnode_div_int8);
PG_FUNCTION_INFO_V1(int8_add_rdfnode);
PG_FUNCTION_INFO_V1(int8_sub_rdfnode);
PG_FUNCTION_INFO_V1(int8_mul_rdfnode);
PG_FUNCTION_INFO_V1(int8_div_rdfnode);

/* int4 (int) data type */
PG_FUNCTION_INFO_V1(rdfnode_to_int4);
PG_FUNCTION_INFO_V1(rdfnode_eq_int4);
PG_FUNCTION_INFO_V1(rdfnode_neq_int4);
PG_FUNCTION_INFO_V1(rdfnode_lt_int4);
PG_FUNCTION_INFO_V1(rdfnode_gt_int4);
PG_FUNCTION_INFO_V1(rdfnode_le_int4);
PG_FUNCTION_INFO_V1(rdfnode_ge_int4);
PG_FUNCTION_INFO_V1(int4_to_rdfnode);
PG_FUNCTION_INFO_V1(int4_eq_rdfnode);
PG_FUNCTION_INFO_V1(int4_neq_rdfnode);
PG_FUNCTION_INFO_V1(int4_lt_rdfnode);
PG_FUNCTION_INFO_V1(int4_gt_rdfnode);
PG_FUNCTION_INFO_V1(int4_le_rdfnode);
PG_FUNCTION_INFO_V1(int4_ge_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_add_int4);
PG_FUNCTION_INFO_V1(rdfnode_sub_int4);
PG_FUNCTION_INFO_V1(rdfnode_mul_int4);
PG_FUNCTION_INFO_V1(rdfnode_div_int4);
PG_FUNCTION_INFO_V1(int4_add_rdfnode);
PG_FUNCTION_INFO_V1(int4_sub_rdfnode);
PG_FUNCTION_INFO_V1(int4_mul_rdfnode);
PG_FUNCTION_INFO_V1(int4_div_rdfnode);

/* int2 (smallint) data type */
PG_FUNCTION_INFO_V1(rdfnode_to_int2);
PG_FUNCTION_INFO_V1(rdfnode_eq_int2);
PG_FUNCTION_INFO_V1(rdfnode_neq_int2);
PG_FUNCTION_INFO_V1(rdfnode_lt_int2);
PG_FUNCTION_INFO_V1(rdfnode_gt_int2);
PG_FUNCTION_INFO_V1(rdfnode_le_int2);
PG_FUNCTION_INFO_V1(rdfnode_ge_int2);
PG_FUNCTION_INFO_V1(int2_to_rdfnode);
PG_FUNCTION_INFO_V1(int2_eq_rdfnode);
PG_FUNCTION_INFO_V1(int2_neq_rdfnode);
PG_FUNCTION_INFO_V1(int2_lt_rdfnode);
PG_FUNCTION_INFO_V1(int2_gt_rdfnode);
PG_FUNCTION_INFO_V1(int2_le_rdfnode);
PG_FUNCTION_INFO_V1(int2_ge_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_add_int2);
PG_FUNCTION_INFO_V1(rdfnode_sub_int2);
PG_FUNCTION_INFO_V1(rdfnode_mul_int2);
PG_FUNCTION_INFO_V1(rdfnode_div_int2);
PG_FUNCTION_INFO_V1(int2_add_rdfnode);
PG_FUNCTION_INFO_V1(int2_sub_rdfnode);
PG_FUNCTION_INFO_V1(int2_mul_rdfnode);
PG_FUNCTION_INFO_V1(int2_div_rdfnode);

/* timestamptz (timestamp with time zone) */
PG_FUNCTION_INFO_V1(timestamptz_to_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_to_timestamptz);
PG_FUNCTION_INFO_V1(rdfnode_eq_timestamptz);
PG_FUNCTION_INFO_V1(timestamptz_eq_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_neq_timestamptz);
PG_FUNCTION_INFO_V1(timestamptz_neq_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_lt_timestamptz);
PG_FUNCTION_INFO_V1(timestamptz_lt_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_gt_timestamptz);
PG_FUNCTION_INFO_V1(timestamptz_gt_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_le_timestamptz);
PG_FUNCTION_INFO_V1(timestamptz_le_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_ge_timestamptz);
PG_FUNCTION_INFO_V1(timestamptz_ge_rdfnode);

/* timestamp (timestamp without time zone) */
PG_FUNCTION_INFO_V1(rdfnode_to_timestamp);
PG_FUNCTION_INFO_V1(rdfnode_eq_timestamp);
PG_FUNCTION_INFO_V1(rdfnode_neq_timestamp);
PG_FUNCTION_INFO_V1(rdfnode_lt_timestamp);
PG_FUNCTION_INFO_V1(rdfnode_gt_timestamp);
PG_FUNCTION_INFO_V1(rdfnode_le_timestamp);
PG_FUNCTION_INFO_V1(rdfnode_ge_timestamp);
PG_FUNCTION_INFO_V1(timestamp_to_rdfnode);
PG_FUNCTION_INFO_V1(timestamp_eq_rdfnode);
PG_FUNCTION_INFO_V1(timestamp_neq_rdfnode);
PG_FUNCTION_INFO_V1(timestamp_lt_rdfnode);
PG_FUNCTION_INFO_V1(timestamp_gt_rdfnode);
PG_FUNCTION_INFO_V1(timestamp_le_rdfnode);
PG_FUNCTION_INFO_V1(timestamp_ge_rdfnode);

/* date */
PG_FUNCTION_INFO_V1(rdfnode_to_date);
PG_FUNCTION_INFO_V1(rdfnode_eq_date);
PG_FUNCTION_INFO_V1(rdfnode_neq_date);
PG_FUNCTION_INFO_V1(rdfnode_lt_date);
PG_FUNCTION_INFO_V1(rdfnode_gt_date);
PG_FUNCTION_INFO_V1(rdfnode_le_date);
PG_FUNCTION_INFO_V1(rdfnode_ge_date);
PG_FUNCTION_INFO_V1(date_to_rdfnode);
PG_FUNCTION_INFO_V1(date_eq_rdfnode);
PG_FUNCTION_INFO_V1(date_neq_rdfnode);
PG_FUNCTION_INFO_V1(date_lt_rdfnode);
PG_FUNCTION_INFO_V1(date_gt_rdfnode);
PG_FUNCTION_INFO_V1(date_le_rdfnode);
PG_FUNCTION_INFO_V1(date_ge_rdfnode);

/* time (time without time zone) */
PG_FUNCTION_INFO_V1(rdfnode_to_time);
PG_FUNCTION_INFO_V1(rdfnode_eq_time);
PG_FUNCTION_INFO_V1(rdfnode_neq_time);
PG_FUNCTION_INFO_V1(rdfnode_lt_time);
PG_FUNCTION_INFO_V1(rdfnode_gt_time);
PG_FUNCTION_INFO_V1(rdfnode_le_time);
PG_FUNCTION_INFO_V1(rdfnode_ge_time);
PG_FUNCTION_INFO_V1(time_to_rdfnode);
PG_FUNCTION_INFO_V1(time_eq_rdfnode);
PG_FUNCTION_INFO_V1(time_neq_rdfnode);
PG_FUNCTION_INFO_V1(time_lt_rdfnode);
PG_FUNCTION_INFO_V1(time_gt_rdfnode);
PG_FUNCTION_INFO_V1(time_le_rdfnode);
PG_FUNCTION_INFO_V1(time_ge_rdfnode);

/* timetz (time with time zone) */
PG_FUNCTION_INFO_V1(rdfnode_to_timetz);
PG_FUNCTION_INFO_V1(rdfnode_eq_timetz);
PG_FUNCTION_INFO_V1(rdfnode_neq_timetz);
PG_FUNCTION_INFO_V1(rdfnode_lt_timetz);
PG_FUNCTION_INFO_V1(rdfnode_gt_timetz);
PG_FUNCTION_INFO_V1(rdfnode_le_timetz);
PG_FUNCTION_INFO_V1(rdfnode_ge_timetz);
PG_FUNCTION_INFO_V1(timetz_to_rdfnode);
PG_FUNCTION_INFO_V1(timetz_eq_rdfnode);
PG_FUNCTION_INFO_V1(timetz_neq_rdfnode);
PG_FUNCTION_INFO_V1(timetz_lt_rdfnode);
PG_FUNCTION_INFO_V1(timetz_gt_rdfnode);
PG_FUNCTION_INFO_V1(timetz_le_rdfnode);
PG_FUNCTION_INFO_V1(timetz_ge_rdfnode);

/* boolean */
PG_FUNCTION_INFO_V1(rdfnode_to_boolean);
PG_FUNCTION_INFO_V1(rdfnode_eq_boolean);
PG_FUNCTION_INFO_V1(rdfnode_neq_boolean);
PG_FUNCTION_INFO_V1(boolean_to_rdfnode);
PG_FUNCTION_INFO_V1(boolean_eq_rdfnode);
PG_FUNCTION_INFO_V1(boolean_neq_rdfnode);

/* interval */
PG_FUNCTION_INFO_V1(rdfnode_to_interval);
PG_FUNCTION_INFO_V1(rdfnode_eq_interval);
PG_FUNCTION_INFO_V1(rdfnode_neq_interval);
PG_FUNCTION_INFO_V1(rdfnode_lt_interval);
PG_FUNCTION_INFO_V1(rdfnode_gt_interval);
PG_FUNCTION_INFO_V1(rdfnode_le_interval);
PG_FUNCTION_INFO_V1(rdfnode_ge_interval);
PG_FUNCTION_INFO_V1(interval_to_rdfnode);
PG_FUNCTION_INFO_V1(interval_eq_rdfnode);
PG_FUNCTION_INFO_V1(interval_neq_rdfnode);
PG_FUNCTION_INFO_V1(interval_lt_rdfnode);
PG_FUNCTION_INFO_V1(interval_gt_rdfnode);
PG_FUNCTION_INFO_V1(interval_le_rdfnode);
PG_FUNCTION_INFO_V1(interval_ge_rdfnode);

Datum rdfnode_in(PG_FUNCTION_ARGS)
{
	char *str_in = PG_GETARG_CSTRING(0);
	char *lexical;
	char *lan;
	char *dtype;

	rdfnode *result;
	size_t len;
	StringInfoData r;

	initStringInfo(&r);

	if (strlen(str_in) == 0)
	{
		appendStringInfoString(&r, "\"\"");
	}
	else if (isLiteral(str_in))
	{
		/*
		 * A typed/language-tagged RDF literal must begin with '"'. If the
		 * input does not start with a quote, it cannot legally carry a
		 * language tag or datatype, so the entire string is treated as the
		 * lexical form of a plain string literal (escaped + quoted).
		 *
		 * NOTE: this guard must wrap the whole parse path — not just the
		 * trailing-content check — otherwise inputs like '  "foo"@en  '
		 * get silently mis-parsed and truncated.
		 */
		if (*str_in == '"')
		{
			char *node;
			const char *p = str_in + 1;

			/* Reject trailing content after a quoted RDF literal boundary. */
			while (*p)
			{
				if (*p == '"')
				{
					if (*(p + 1) == '"') /* "" escape */
					{
						p += 2;
						continue;
					}
					{
						const char *q = p;
						int backslashes = 0;
						while (q > str_in + 1 && *(q - 1) == '\\')
						{
							backslashes++;
							q--;
						}
						if (backslashes % 2 == 1)
						{
							p++;
							continue;
						}
					}
					break; /* unescaped closing '"' */
				}
				p++;
			}

			if (*p == '"')
			{
				p++; /* skip closing '"' */

				if (*p == '@')
				{
					p++;
					while (*p && (isalnum((unsigned char)*p) || *p == '-'))
						p++;
				}
				else if (p[0] == '^' && p[1] == '^')
				{
					p += 2;
					if (*p == '<')
					{
						p++;
						while (*p && *p != '>')
							p++;
						if (*p == '>')
							p++;
						else
							ereport(ERROR,
									(errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
									 errmsg("invalid input syntax for type rdfnode: \"%s\"",
											str_in),
									 errdetail("Unterminated IRI in datatype annotation: "
											   "missing closing '>'.")));
					}
					else
					{
						while (*p && (isalnum((unsigned char)*p) ||
									  *p == ':' || *p == '_' ||
									  *p == '-' || *p == '.'))
							p++;
					}
				}

				if (*p != '\0')
					ereport(ERROR,
							(errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
							 errmsg("invalid input syntax for type rdfnode: \"%s\"",
									str_in),
							 errdetail("Trailing content after RDF literal.")));
			}

			node = cstring_to_rdfliteral(str_in);
			lexical = lex(node);
			lan = lang(node);
			dtype = datatype(node);

			if (strlen(lan) != 0)
			{
				if (!is_valid_language_tag(lan))
					ereport(ERROR,
							(errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
							 errmsg("invalid language tag: \"%s\"", lan)));

				appendStringInfoString(&r, strlang(unescape_unicode(lexical), lan));
			}
			else if (strlen(dtype) != 0)
			{
				appendStringInfoString(&r, strdt(unescape_unicode(lexical), dtype));
			}
			else
			{
				appendStringInfoString(&r, str(unescape_unicode(str_in)));
			}
		}
		else
		{
			/*
			* No leading quote: not RDF literal syntax, so the whole input is
			* the (already-escaped) lexical form of a plain string literal.
			* We call cstring_to_rdfliteral() directly rather than str(), because
			* str() runs lex() first, which re-extracts an embedded quoted region
			* and truncates inputs like '  "foo"@en  '.
			*/
			appendStringInfoString(&r, cstring_to_rdfliteral(unescape_unicode(str_in)));
		}
	}
	else if (isIRI(str_in) || isBlank(str_in))
	{
		appendStringInfoString(&r, str_in);
	}
	else
	{
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
				 errmsg("invalid input syntax for type rdfnode: \"%s\"",
						str_in)));
	}

	len = strlen(r.data);
	result = (rdfnode *)palloc0(VARHDRSZ + len);
	SET_VARSIZE(result, VARHDRSZ + len);
	memcpy(result->vl_data, r.data, len);

	PG_RETURN_POINTER(result);
}

Datum rdfnode_out(PG_FUNCTION_ARGS)
{
	text *lit = PG_GETARG_TEXT_PP(0); /* handles detoasting */
	int len = VARSIZE_ANY_EXHDR(lit); /* get payload length safely */
	char *out = (char *)palloc(len + 1);

	memcpy(out, VARDATA_ANY(lit), len);
	out[len] = '\0';

	PG_RETURN_CSTRING(out);
}

/*
 * rdfnode_storage_cmp
 * -------------------
 *
 * Orders two terms by how they are written, which is the order the rdfnode
 * B-tree operator class is built on. Both terms are stored as text, so this
 * is the comparison text itself uses in the C locale: the common prefix
 * decides, and where one term is a prefix of the other the shorter one comes
 * first.
 *
 * This is deliberately not the RDF value comparison the =, <, <=, >= and >
 * operators implement. A B-tree needs a total order over every pair of
 * values and an equality that is reflexive, symmetric and transitive; RDF
 * value comparison leaves terms of unlike kinds unordered, does not hold
 * between NaN and itself, and is not transitive across numeric datatypes of
 * different precision.
 *
 * ta, tb: the terms to compare
 *
 * returns a negative value, zero or a positive value as ta sorts before, with
 * or after tb
 */
static int
rdfnode_storage_cmp(text *ta, text *tb)
{
	int len1 = VARSIZE_ANY_EXHDR(ta);
	int len2 = VARSIZE_ANY_EXHDR(tb);
	int result = memcmp(VARDATA_ANY(ta), VARDATA_ANY(tb), Min(len1, len2));

	if (result == 0)
		result = (len1 > len2) - (len1 < len2);

	return result;
}

/*
 * rdfnode_cmp
 * -----------
 *
 * Support function 1 of the rdfnode B-tree operator class, and what decides
 * the order of an rdfnode column in ORDER BY, in a sort-based GROUP BY or
 * DISTINCT, and in an index.
 *
 * returns -1, 0 or 1
 */
Datum rdfnode_cmp(PG_FUNCTION_ARGS)
{
	text *ta = PG_GETARG_TEXT_PP(0);
	text *tb = PG_GETARG_TEXT_PP(1);
	int result = rdfnode_storage_cmp(ta, tb);

	PG_FREE_IF_COPY(ta, 0);
	PG_FREE_IF_COPY(tb, 1);

	if (result < 0)
		PG_RETURN_INT32(-1);
	else if (result > 0)
		PG_RETURN_INT32(1);
	else
		PG_RETURN_INT32(0);
}

/*
 * rdfnode_storage_lt / le / eq / ge / gt
 * --------------------------------------
 *
 * The operators ~<~, ~<=~, ~=, ~>=~ and ~>~, which are strategies 1 to 5 of
 * the rdfnode B-tree operator class. They ask whether one term sorts before
 * or after another, or is written the same way -- not whether the two denote
 * the same RDF value, which is what =, <, <=, >= and > answer.
 *
 * An index search condition has to be one of these. The value operators are
 * still usable anywhere, but as a filter over the rows a scan returns rather
 * than as a bound on which rows it visits, because the index is ordered by
 * rdfnode_cmp and the value operators do not agree with that order.
 *
 * returns whether the comparison holds
 */
Datum rdfnode_storage_lt(PG_FUNCTION_ARGS)
{
	text *ta = PG_GETARG_TEXT_PP(0);
	text *tb = PG_GETARG_TEXT_PP(1);
	bool result = rdfnode_storage_cmp(ta, tb) < 0;

	PG_FREE_IF_COPY(ta, 0);
	PG_FREE_IF_COPY(tb, 1);
	PG_RETURN_BOOL(result);
}

Datum rdfnode_storage_le(PG_FUNCTION_ARGS)
{
	text *ta = PG_GETARG_TEXT_PP(0);
	text *tb = PG_GETARG_TEXT_PP(1);
	bool result = rdfnode_storage_cmp(ta, tb) <= 0;

	PG_FREE_IF_COPY(ta, 0);
	PG_FREE_IF_COPY(tb, 1);
	PG_RETURN_BOOL(result);
}

Datum rdfnode_storage_eq(PG_FUNCTION_ARGS)
{
	text *ta = PG_GETARG_TEXT_PP(0);
	text *tb = PG_GETARG_TEXT_PP(1);
	int len1 = VARSIZE_ANY_EXHDR(ta);
	int len2 = VARSIZE_ANY_EXHDR(tb);
	/* two terms written the same way are the same length, so checking that
	 * first settles most unequal pairs without reading either term */
	bool result = len1 == len2 &&
				  memcmp(VARDATA_ANY(ta), VARDATA_ANY(tb), len1) == 0;

	PG_FREE_IF_COPY(ta, 0);
	PG_FREE_IF_COPY(tb, 1);
	PG_RETURN_BOOL(result);
}

Datum rdfnode_storage_ge(PG_FUNCTION_ARGS)
{
	text *ta = PG_GETARG_TEXT_PP(0);
	text *tb = PG_GETARG_TEXT_PP(1);
	bool result = rdfnode_storage_cmp(ta, tb) >= 0;

	PG_FREE_IF_COPY(ta, 0);
	PG_FREE_IF_COPY(tb, 1);
	PG_RETURN_BOOL(result);
}

Datum rdfnode_storage_gt(PG_FUNCTION_ARGS)
{
	text *ta = PG_GETARG_TEXT_PP(0);
	text *tb = PG_GETARG_TEXT_PP(1);
	bool result = rdfnode_storage_cmp(ta, tb) > 0;

	PG_FREE_IF_COPY(ta, 0);
	PG_FREE_IF_COPY(tb, 1);
	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_rdfnode(PG_FUNCTION_ARGS)
{
	text *node1 = PG_GETARG_TEXT_PP(0);
	text *node2 = PG_GETARG_TEXT_PP(1);

	PG_RETURN_BOOL(!rdfnode_eq((rdfnode *)node1, (rdfnode *)node2));
}

Datum rdfnode_add_rdfnode(PG_FUNCTION_ARGS)
{
	text *node1 = PG_GETARG_TEXT_PP(0);
	text *node2 = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(cstring_to_text(rdfnode_arith((rdfnode *)node1, (rdfnode *)node2, '+')));
}

Datum rdfnode_sub_rdfnode(PG_FUNCTION_ARGS)
{
	text *node1 = PG_GETARG_TEXT_PP(0);
	text *node2 = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(cstring_to_text(rdfnode_arith((rdfnode *)node1, (rdfnode *)node2, '-')));
}

Datum rdfnode_mul_rdfnode(PG_FUNCTION_ARGS)
{
	text *node1 = PG_GETARG_TEXT_PP(0);
	text *node2 = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(cstring_to_text(rdfnode_arith((rdfnode *)node1, (rdfnode *)node2, '*')));
}

Datum rdfnode_div_rdfnode(PG_FUNCTION_ARGS)
{
	text *node1 = PG_GETARG_TEXT_PP(0);
	text *node2 = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(cstring_to_text(rdfnode_arith((rdfnode *)node1, (rdfnode *)node2, '/')));
}

/*
 * rdfnode_arith_pg
 * ----------------
 *
 * Shared body of the arithmetic operators that take an rdfnode on one side and
 * a PostgreSQL number on the other.
 *
 * The PostgreSQL operand is first turned into the term it stands for, by the
 * very function that implements its cast to rdfnode -- an int4 arrives as an
 * xsd:int, a numeric as an xsd:decimal, a float8 as an xsd:double -- and the
 * pair is then combined by rdfnode_arith(). Neither the XPath promotion nor the
 * datatype of the result is decided here: both follow from the two terms, so
 * these operators cannot drift from the (rdfnode, rdfnode) ones.
 *
 * node      : the rdfnode operand
 * value     : the PostgreSQL operand, as its own type's Datum
 * to_rdfnode: the function implementing that type's cast to rdfnode
 * op        : one of '+', '-', '*', '/'
 * node_first: true when the rdfnode was written on the left
 *
 * returns the resulting term
 */
static text *
rdfnode_arith_pg(text *node, Datum value, PGFunction to_rdfnode, char op, bool node_first)
{
	text *term = DatumGetTextP(DirectFunctionCall1(to_rdfnode, value));

	/* subtraction and division are not commutative, so the operands go to
	 * rdfnode_arith() in the order they were written */
	return cstring_to_text(node_first
						   ? rdfnode_arith((rdfnode *) node, (rdfnode *) term, op)
						   : rdfnode_arith((rdfnode *) term, (rdfnode *) node, op));
}

/* numeric */
Datum rdfnode_add_numeric(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), numeric_to_rdfnode, '+', true));
}

Datum rdfnode_sub_numeric(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), numeric_to_rdfnode, '-', true));
}

Datum rdfnode_mul_numeric(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), numeric_to_rdfnode, '*', true));
}

Datum rdfnode_div_numeric(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), numeric_to_rdfnode, '/', true));
}

Datum numeric_add_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), numeric_to_rdfnode, '+', false));
}

Datum numeric_sub_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), numeric_to_rdfnode, '-', false));
}

Datum numeric_mul_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), numeric_to_rdfnode, '*', false));
}

Datum numeric_div_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), numeric_to_rdfnode, '/', false));
}

/* float8 (double precision) */
Datum rdfnode_add_float8(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), float8_to_rdfnode, '+', true));
}

Datum rdfnode_sub_float8(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), float8_to_rdfnode, '-', true));
}

Datum rdfnode_mul_float8(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), float8_to_rdfnode, '*', true));
}

Datum rdfnode_div_float8(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), float8_to_rdfnode, '/', true));
}

Datum float8_add_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), float8_to_rdfnode, '+', false));
}

Datum float8_sub_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), float8_to_rdfnode, '-', false));
}

Datum float8_mul_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), float8_to_rdfnode, '*', false));
}

Datum float8_div_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), float8_to_rdfnode, '/', false));
}

/* float4 (real) */
Datum rdfnode_add_float4(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), float4_to_rdfnode, '+', true));
}

Datum rdfnode_sub_float4(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), float4_to_rdfnode, '-', true));
}

Datum rdfnode_mul_float4(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), float4_to_rdfnode, '*', true));
}

Datum rdfnode_div_float4(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), float4_to_rdfnode, '/', true));
}

Datum float4_add_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), float4_to_rdfnode, '+', false));
}

Datum float4_sub_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), float4_to_rdfnode, '-', false));
}

Datum float4_mul_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), float4_to_rdfnode, '*', false));
}

Datum float4_div_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), float4_to_rdfnode, '/', false));
}

/* int8 (bigint) */
Datum rdfnode_add_int8(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), int8_to_rdfnode, '+', true));
}

Datum rdfnode_sub_int8(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), int8_to_rdfnode, '-', true));
}

Datum rdfnode_mul_int8(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), int8_to_rdfnode, '*', true));
}

Datum rdfnode_div_int8(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), int8_to_rdfnode, '/', true));
}

Datum int8_add_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), int8_to_rdfnode, '+', false));
}

Datum int8_sub_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), int8_to_rdfnode, '-', false));
}

Datum int8_mul_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), int8_to_rdfnode, '*', false));
}

Datum int8_div_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), int8_to_rdfnode, '/', false));
}

/* int4 (int) */
Datum rdfnode_add_int4(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), int4_to_rdfnode, '+', true));
}

Datum rdfnode_sub_int4(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), int4_to_rdfnode, '-', true));
}

Datum rdfnode_mul_int4(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), int4_to_rdfnode, '*', true));
}

Datum rdfnode_div_int4(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), int4_to_rdfnode, '/', true));
}

Datum int4_add_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), int4_to_rdfnode, '+', false));
}

Datum int4_sub_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), int4_to_rdfnode, '-', false));
}

Datum int4_mul_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), int4_to_rdfnode, '*', false));
}

Datum int4_div_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), int4_to_rdfnode, '/', false));
}

/* int2 (smallint) */
Datum rdfnode_add_int2(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), int2_to_rdfnode, '+', true));
}

Datum rdfnode_sub_int2(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), int2_to_rdfnode, '-', true));
}

Datum rdfnode_mul_int2(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), int2_to_rdfnode, '*', true));
}

Datum rdfnode_div_int2(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(0);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(1), int2_to_rdfnode, '/', true));
}

Datum int2_add_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), int2_to_rdfnode, '+', false));
}

Datum int2_sub_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), int2_to_rdfnode, '-', false));
}

Datum int2_mul_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), int2_to_rdfnode, '*', false));
}

Datum int2_div_rdfnode(PG_FUNCTION_ARGS)
{
	text *node = PG_GETARG_TEXT_PP(1);

	PG_RETURN_TEXT_P(rdfnode_arith_pg(node, PG_GETARG_DATUM(0), int2_to_rdfnode, '/', false));
}

Datum rdfnode_eq_rdfnode(PG_FUNCTION_ARGS)
{
	text *node1 = PG_GETARG_TEXT_PP(0);
	text *node2 = PG_GETARG_TEXT_PP(1);

	PG_RETURN_BOOL(rdfnode_eq((rdfnode *)node1, (rdfnode *)node2));
}

Datum rdfnode_lt_rdfnode(PG_FUNCTION_ARGS)
{
	text *node1 = PG_GETARG_TEXT_PP(0);
	text *node2 = PG_GETARG_TEXT_PP(1);

	PG_RETURN_BOOL(rdfnode_lt((rdfnode *)node1, (rdfnode *)node2));
}

Datum rdfnode_gt_rdfnode(PG_FUNCTION_ARGS)
{
	text *node1 = PG_GETARG_TEXT_PP(0);
	text *node2 = PG_GETARG_TEXT_PP(1);

	PG_RETURN_BOOL(rdfnode_gt((rdfnode *)node1, (rdfnode *)node2));
}

Datum rdfnode_le_rdfnode(PG_FUNCTION_ARGS)
{
	text *node1 = PG_GETARG_TEXT_PP(0);
	text *node2 = PG_GETARG_TEXT_PP(1);

	PG_RETURN_BOOL(rdfnode_le((rdfnode *)node1, (rdfnode *)node2));
}

Datum rdfnode_ge_rdfnode(PG_FUNCTION_ARGS)
{
	text *node1 = PG_GETARG_TEXT_PP(0);
	text *node2 = PG_GETARG_TEXT_PP(1);

	PG_RETURN_BOOL(rdfnode_ge((rdfnode *)node1, (rdfnode *)node2));
}

Datum rdfnode_to_text(PG_FUNCTION_ARGS)
{
	text *lit = PG_GETARG_TEXT_PP(0); /* safe detoasting */
	int len = VARSIZE_ANY_EXHDR(lit); /* length of the actual data */
	text *result = (text *)palloc(VARHDRSZ + len);

	SET_VARSIZE(result, VARHDRSZ + len);
	memcpy(VARDATA(result), VARDATA_ANY(lit), len);

	PG_RETURN_TEXT_P(result);
}

/* numeric */
Datum rdfnode_to_numeric(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	if (!p.isNumeric)
		ereport(ERROR,
				(errcode(ERRCODE_CANNOT_COERCE),
				 errmsg("cannot cast non-numeric RDF literal to numeric")));

	PG_RETURN_DATUM(DirectFunctionCall3(numeric_in,
										CStringGetDatum(p.lex),
										ObjectIdGetDatum(InvalidOid),
										Int32GetDatum(-1)));
}

Datum rdfnode_eq_numeric(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Numeric num = PG_GETARG_NUMERIC(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_num;
	bool result;

	rdf_num = DirectFunctionCall3(numeric_in,
								  CStringGetDatum(p.lex),
								  ObjectIdGetDatum(InvalidOid),
								  Int32GetDatum(-1));
	result = DatumGetBool(DirectFunctionCall2(numeric_eq, rdf_num, NumericGetDatum(num)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_numeric(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Numeric num = PG_GETARG_NUMERIC(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_num;
	bool result;

	rdf_num = DirectFunctionCall3(numeric_in,
								  CStringGetDatum(p.lex),
								  ObjectIdGetDatum(InvalidOid),
								  Int32GetDatum(-1));
	result = DatumGetBool(DirectFunctionCall2(numeric_ne, rdf_num, NumericGetDatum(num)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_lt_numeric(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Numeric num = PG_GETARG_NUMERIC(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_num;
	bool result;

	rdf_num = DirectFunctionCall3(numeric_in,
								  CStringGetDatum(p.lex),
								  ObjectIdGetDatum(InvalidOid),
								  Int32GetDatum(-1));
	result = DatumGetBool(DirectFunctionCall2(numeric_lt, rdf_num, NumericGetDatum(num)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_numeric(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Numeric num = PG_GETARG_NUMERIC(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_num;
	bool result;

	rdf_num = DirectFunctionCall3(numeric_in,
								  CStringGetDatum(p.lex),
								  ObjectIdGetDatum(InvalidOid),
								  Int32GetDatum(-1));
	result = DatumGetBool(DirectFunctionCall2(numeric_gt, rdf_num, NumericGetDatum(num)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_numeric(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Numeric num = PG_GETARG_NUMERIC(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_num;
	bool result;

	rdf_num = DirectFunctionCall3(numeric_in,
								  CStringGetDatum(p.lex),
								  ObjectIdGetDatum(InvalidOid),
								  Int32GetDatum(-1));
	result = DatumGetBool(DirectFunctionCall2(numeric_le, rdf_num, NumericGetDatum(num)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_numeric(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Numeric num = PG_GETARG_NUMERIC(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_num;
	bool result;

	rdf_num = DirectFunctionCall3(numeric_in,
								  CStringGetDatum(p.lex),
								  ObjectIdGetDatum(InvalidOid),
								  Int32GetDatum(-1));
	result = DatumGetBool(DirectFunctionCall2(numeric_ge, rdf_num, NumericGetDatum(num)));

	PG_RETURN_BOOL(result);
}

Datum numeric_eq_rdfnode(PG_FUNCTION_ARGS)
{
	Numeric num = PG_GETARG_NUMERIC(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_num;
	bool result;

	rdf_num = DirectFunctionCall3(numeric_in,
								  CStringGetDatum(p.lex),
								  ObjectIdGetDatum(InvalidOid),
								  Int32GetDatum(-1));

	result = DatumGetBool(DirectFunctionCall2(numeric_eq, rdf_num, NumericGetDatum(num)));

	PG_RETURN_BOOL(result);
}

Datum numeric_neq_rdfnode(PG_FUNCTION_ARGS)
{
	Numeric num = PG_GETARG_NUMERIC(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_num;
	bool result;

	rdf_num = DirectFunctionCall3(numeric_in,
								  CStringGetDatum(p.lex),
								  ObjectIdGetDatum(InvalidOid),
								  Int32GetDatum(-1));
	result = DatumGetBool(DirectFunctionCall2(numeric_ne, rdf_num, NumericGetDatum(num)));

	PG_RETURN_BOOL(result);
}

Datum numeric_lt_rdfnode(PG_FUNCTION_ARGS)
{
	Numeric num = PG_GETARG_NUMERIC(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_num;
	bool result;

	rdf_num = DirectFunctionCall3(numeric_in,
								  CStringGetDatum(p.lex),
								  ObjectIdGetDatum(InvalidOid),
								  Int32GetDatum(-1));
	result = DatumGetBool(DirectFunctionCall2(numeric_lt, NumericGetDatum(num), rdf_num));

	PG_RETURN_BOOL(result);
}

Datum numeric_gt_rdfnode(PG_FUNCTION_ARGS)
{
	Numeric num = PG_GETARG_NUMERIC(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_num;
	bool result;

	rdf_num = DirectFunctionCall3(numeric_in,
								  CStringGetDatum(p.lex),
								  ObjectIdGetDatum(InvalidOid),
								  Int32GetDatum(-1));
	result = DatumGetBool(DirectFunctionCall2(numeric_gt, NumericGetDatum(num), rdf_num));

	PG_RETURN_BOOL(result);
}

Datum numeric_le_rdfnode(PG_FUNCTION_ARGS)
{
	Numeric num = PG_GETARG_NUMERIC(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_num;
	bool result;

	rdf_num = DirectFunctionCall3(numeric_in,
								  CStringGetDatum(p.lex),
								  ObjectIdGetDatum(InvalidOid),
								  Int32GetDatum(-1));
	result = DatumGetBool(DirectFunctionCall2(numeric_le, NumericGetDatum(num), rdf_num));

	PG_RETURN_BOOL(result);
}

Datum numeric_ge_rdfnode(PG_FUNCTION_ARGS)
{
	Numeric num = PG_GETARG_NUMERIC(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_num;
	bool result;

	rdf_num = DirectFunctionCall3(numeric_in,
								  CStringGetDatum(p.lex),
								  ObjectIdGetDatum(InvalidOid),
								  Int32GetDatum(-1));
	result = DatumGetBool(DirectFunctionCall2(numeric_ge, NumericGetDatum(num), rdf_num));

	PG_RETURN_BOOL(result);
}

Datum numeric_to_rdfnode(PG_FUNCTION_ARGS)
{
	Numeric val = PG_GETARG_NUMERIC(0);
	char *val_str = DatumGetCString(DirectFunctionCall1(numeric_out, NumericGetDatum(val)));
	StringInfoData buf;
	initStringInfo(&buf);

	if (numeric_is_nan(val))
		appendStringInfo(&buf, "\"NaN\"^^%s", RDF_XSD_DOUBLE);
	else if (strcmp(val_str, "Infinity") == 0)
		appendStringInfo(&buf, "\"INF\"^^%s", RDF_XSD_DOUBLE);
	else if (strcmp(val_str, "-Infinity") == 0)
		appendStringInfo(&buf, "\"-INF\"^^%s", RDF_XSD_DOUBLE);
	else
		appendStringInfo(&buf, "\"%s\"^^%s", val_str, RDF_XSD_DECIMAL);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

/* float8 */
Datum rdfnode_eq_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float8 f = PG_GETARG_FLOAT8(1);
	float8 rdf_float;
	Datum rdf_float_datum;
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	rdf_float_datum = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	rdf_float = DatumGetFloat8(rdf_float_datum);

	PG_RETURN_BOOL(rdf_float == f);
}

Datum rdfnode_neq_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float8 f = PG_GETARG_FLOAT8(1);
	float8 rdf_float;
	Datum rdf_float_datum;
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	rdf_float_datum = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	rdf_float = DatumGetFloat8(rdf_float_datum);

	PG_RETURN_BOOL(rdf_float != f);
}

Datum rdfnode_lt_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float8 f = PG_GETARG_FLOAT8(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8lt, rdf_float, Float8GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float8 f = PG_GETARG_FLOAT8(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8gt, rdf_float, Float8GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float8 f = PG_GETARG_FLOAT8(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8le, rdf_float, Float8GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float8 f = PG_GETARG_FLOAT8(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8ge, rdf_float, Float8GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_to_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	if (!p.isNumeric)
		ereport(ERROR,
				(errcode(ERRCODE_CANNOT_COERCE),
				 errmsg("cannot cast non-numeric RDF literal to double precision")));

	PG_RETURN_DATUM(DirectFunctionCall1(float8in, CStringGetDatum(p.lex)));
}

Datum float8_eq_rdfnode(PG_FUNCTION_ARGS)
{
	float8 f = PG_GETARG_FLOAT8(0);
	text *t = PG_GETARG_TEXT_PP(1);
	float8 rdf_float;
	Datum rdf_float_datum;
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	rdf_float_datum = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	rdf_float = DatumGetFloat8(rdf_float_datum);

	PG_RETURN_BOOL(f == rdf_float);
}

Datum float8_neq_rdfnode(PG_FUNCTION_ARGS)
{
	float8 f = PG_GETARG_FLOAT8(0);
	text *t = PG_GETARG_TEXT_PP(1);
	float8 rdf_float;
	Datum rdf_float_datum;
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	rdf_float_datum = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	rdf_float = DatumGetFloat8(rdf_float_datum);

	PG_RETURN_BOOL(f != rdf_float);
}

Datum float8_lt_rdfnode(PG_FUNCTION_ARGS)
{
	float8 f = PG_GETARG_FLOAT8(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8lt, Float8GetDatum(f), rdf_float));
	PG_RETURN_BOOL(result);
}

Datum float8_gt_rdfnode(PG_FUNCTION_ARGS)
{
	float8 f = PG_GETARG_FLOAT8(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8gt, Float8GetDatum(f), rdf_float));
	PG_RETURN_BOOL(result);
}

Datum float8_le_rdfnode(PG_FUNCTION_ARGS)
{
	float8 f = PG_GETARG_FLOAT8(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8le, Float8GetDatum(f), rdf_float));
	PG_RETURN_BOOL(result);
}

Datum float8_ge_rdfnode(PG_FUNCTION_ARGS)
{
	float8 f = PG_GETARG_FLOAT8(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8ge, Float8GetDatum(f), rdf_float));
	PG_RETURN_BOOL(result);
}

Datum float8_to_rdfnode(PG_FUNCTION_ARGS)
{
	float8 val = PG_GETARG_FLOAT8(0);
	StringInfoData buf;
	initStringInfo(&buf);

	/* Normalize PostgreSQL float output to XSD lexical forms.
	 * XSD 1.1 Part 2 §3.3.5 defines INF/-INF/NaN as the valid lexical
	 * representations for IEEE 754 special values; "Infinity"/"-Infinity"
	 * are not valid XSD lexical forms.
	 */
	if (isnan(val))
		appendStringInfo(&buf, "\"NaN\"^^%s", RDF_XSD_DOUBLE);
	else if (isinf(val))
		appendStringInfo(&buf, val < 0 ? "\"-INF\"^^%s" : "\"INF\"^^%s", RDF_XSD_DOUBLE);
	else
	{
		char *valstr = DatumGetCString(DirectFunctionCall1(float8out, Float8GetDatum(val)));
		appendStringInfo(&buf, "\"%s\"^^%s", valstr, RDF_XSD_DOUBLE);
	}

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

/* float4 (real) */
Datum rdfnode_to_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	if (!p.isNumeric)
		ereport(ERROR,
				(errcode(ERRCODE_CANNOT_COERCE),
				 errmsg("cannot cast non-numeric RDF literal to real")));

	PG_RETURN_DATUM(DirectFunctionCall1(float4in, CStringGetDatum(p.lex)));
}

Datum rdfnode_eq_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float4 f = PG_GETARG_FLOAT4(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4eq, rdf_float4, Float4GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float4 f = PG_GETARG_FLOAT4(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4ne, rdf_float4, Float4GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float4 f = PG_GETARG_FLOAT4(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4gt, rdf_float4, Float4GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_lt_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float4 f = PG_GETARG_FLOAT4(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4lt, rdf_float4, Float4GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float4 f = PG_GETARG_FLOAT4(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4ge, rdf_float4, Float4GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float4 f = PG_GETARG_FLOAT4(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4le, rdf_float4, Float4GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum float4_to_rdfnode(PG_FUNCTION_ARGS)
{
	float4 val = PG_GETARG_FLOAT4(0);
	StringInfoData buf;
	initStringInfo(&buf);

	/* Normalize PostgreSQL float output to XSD lexical forms.
	 * XSD 1.1 Part 2 §3.3.5 defines INF/-INF/NaN as the valid lexical
	 * representations for IEEE 754 special values; "Infinity"/"-Infinity"
	 * are not valid XSD lexical forms.
	 */	
	if (isnan(val))
		appendStringInfo(&buf, "\"NaN\"^^%s", RDF_XSD_FLOAT);
	else if (isinf(val))
		appendStringInfo(&buf, val < 0 ? "\"-INF\"^^%s" : "\"INF\"^^%s", RDF_XSD_FLOAT);
	else
	{
		char *valstr = DatumGetCString(DirectFunctionCall1(float4out, Float4GetDatum(val)));
		appendStringInfo(&buf, "\"%s\"^^%s", valstr, RDF_XSD_FLOAT);
	}

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum float4_eq_rdfnode(PG_FUNCTION_ARGS)
{
	float4 f = PG_GETARG_FLOAT4(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4eq, Float4GetDatum(f), rdf_float4));

	PG_RETURN_BOOL(result);
}

Datum float4_neq_rdfnode(PG_FUNCTION_ARGS)
{
	float4 f = PG_GETARG_FLOAT4(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4ne, Float4GetDatum(f), rdf_float4));

	PG_RETURN_BOOL(result);
}

Datum float4_lt_rdfnode(PG_FUNCTION_ARGS)
{
	float4 f = PG_GETARG_FLOAT4(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4lt, Float4GetDatum(f), rdf_float4));

	PG_RETURN_BOOL(result);
}

Datum float4_gt_rdfnode(PG_FUNCTION_ARGS)
{
	float4 f = PG_GETARG_FLOAT4(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4gt, Float4GetDatum(f), rdf_float4));

	PG_RETURN_BOOL(result);
}

Datum float4_le_rdfnode(PG_FUNCTION_ARGS)
{
	float4 f = PG_GETARG_FLOAT4(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4le, Float4GetDatum(f), rdf_float4));

	PG_RETURN_BOOL(result);
}

Datum float4_ge_rdfnode(PG_FUNCTION_ARGS)
{
	float4 f = PG_GETARG_FLOAT4(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4ge, Float4GetDatum(f), rdf_float4));

	PG_RETURN_BOOL(result);
}

/* bigint (int8) */
Datum rdfnode_to_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
#if PG_VERSION_NUM >= 100000
	int64 result = DatumGetInt64(DirectFunctionCall1(int8in, CStringGetDatum(p.lex)));
#else
	int64 result = DatumGetInt64(OidFunctionCall1(F_INT8IN, CStringGetDatum(p.lex)));
#endif

	PG_RETURN_INT64(result);
}

Datum rdfnode_lt_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int64 val = PG_GETARG_INT64(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int8_numeric, Int64GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_lt, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int64 val = PG_GETARG_INT64(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int8_numeric, Int64GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_le, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int64 val = PG_GETARG_INT64(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int8_numeric, Int64GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_gt, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int64 val = PG_GETARG_INT64(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int8_numeric, Int64GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_ge, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_eq_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int64 val = PG_GETARG_INT64(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int8_numeric, Int64GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_eq, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int64 val = PG_GETARG_INT64(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int8_numeric, Int64GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_ne, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum int8_to_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	StringInfoData buf;
	initStringInfo(&buf);
	/*
	 * INT64_FORMAT, not %ld: long is 32 bits where int64 is 64, so %ld reads
	 * half the argument and every conversion after it takes the wrong one --
	 * the datatype IRI below came out as (null) on such a build.
	 */
	appendStringInfo(&buf, "\"" INT64_FORMAT "\"^^%s", val, RDF_XSD_LONG);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum int8_lt_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int8_numeric, Int64GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_lt, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int8_le_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int8_numeric, Int64GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_le, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int8_gt_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int8_numeric, Int64GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_gt, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int8_ge_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int8_numeric, Int64GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_ge, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int8_eq_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int8_numeric, Int64GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_eq, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int8_neq_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int8_numeric, Int64GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_ne, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

/* int (int4) */
Datum rdfnode_to_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	int32 result = DatumGetInt32(DirectFunctionCall1(int4in, CStringGetDatum(p.lex)));

	PG_RETURN_INT32(result);
}

Datum rdfnode_lt_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int32 val = PG_GETARG_INT32(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int4_numeric, Int32GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_lt, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int32 val = PG_GETARG_INT32(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int4_numeric, Int32GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_le, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int32 val = PG_GETARG_INT32(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int4_numeric, Int32GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_gt, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int32 val = PG_GETARG_INT32(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int4_numeric, Int32GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_ge, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_eq_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int32 val = PG_GETARG_INT32(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int4_numeric, Int32GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_eq, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int32 val = PG_GETARG_INT32(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int4_numeric, Int32GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_ne, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum int4_to_rdfnode(PG_FUNCTION_ARGS)
{
	int32 val = PG_GETARG_INT32(0);
	StringInfoData buf;
	initStringInfo(&buf);
	appendStringInfo(&buf, "\"%d\"^^%s", val, RDF_XSD_INT);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum int4_lt_rdfnode(PG_FUNCTION_ARGS)
{
	int32 val = PG_GETARG_INT32(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int4_numeric, Int32GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_lt, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int4_le_rdfnode(PG_FUNCTION_ARGS)
{
	int32 val = PG_GETARG_INT32(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int4_numeric, Int32GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_le, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int4_gt_rdfnode(PG_FUNCTION_ARGS)
{
	int32 val = PG_GETARG_INT32(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int4_numeric, Int32GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_gt, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int4_ge_rdfnode(PG_FUNCTION_ARGS)
{
	int32 val = PG_GETARG_INT32(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int4_numeric, Int32GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_ge, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int4_eq_rdfnode(PG_FUNCTION_ARGS)
{
	int32 val = PG_GETARG_INT32(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int4_numeric, Int32GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_eq, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int4_neq_rdfnode(PG_FUNCTION_ARGS)
{
	int32 val = PG_GETARG_INT32(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int4_numeric, Int32GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_ne, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

/* smallint (int2) */
Datum rdfnode_to_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	int16 result = DatumGetInt16(DirectFunctionCall1(int2in, CStringGetDatum(p.lex)));

	PG_RETURN_INT16(result);
}

Datum rdfnode_lt_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int16 val = PG_GETARG_INT16(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int2_numeric, Int16GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_lt, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int16 val = PG_GETARG_INT16(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int2_numeric, Int16GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_le, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int16 val = PG_GETARG_INT16(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int2_numeric, Int16GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_gt, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int16 val = PG_GETARG_INT16(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int2_numeric, Int16GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_ge, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_eq_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int16 val = PG_GETARG_INT16(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int2_numeric, Int16GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_eq, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int16 val = PG_GETARG_INT16(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int2_numeric, Int16GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_ne, rdf_numeric, val_numeric));

	PG_RETURN_BOOL(result);
}

Datum int2_to_rdfnode(PG_FUNCTION_ARGS)
{
	int16 val = PG_GETARG_INT16(0);
	StringInfoData buf;
	initStringInfo(&buf);
	appendStringInfo(&buf, "\"%d\"^^%s", val, RDF_XSD_SHORT);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum int2_lt_rdfnode(PG_FUNCTION_ARGS)
{
	int16 val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int2_numeric, Int16GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_lt, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int2_le_rdfnode(PG_FUNCTION_ARGS)
{
	int16 val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int2_numeric, Int16GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_le, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int2_gt_rdfnode(PG_FUNCTION_ARGS)
{
	int16 val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int2_numeric, Int16GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_gt, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int2_ge_rdfnode(PG_FUNCTION_ARGS)
{
	int16 val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int2_numeric, Int16GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_ge, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int2_eq_rdfnode(PG_FUNCTION_ARGS)
{
	int16 val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int2_numeric, Int16GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_eq, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

Datum int2_neq_rdfnode(PG_FUNCTION_ARGS)
{
	int16 val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum rdf_numeric = DirectFunctionCall3(numeric_in,
											CStringGetDatum(p.lex),
											ObjectIdGetDatum(InvalidOid),
											Int32GetDatum(-1));

	Datum val_numeric = DirectFunctionCall1(int2_numeric, Int16GetDatum(val));

	bool result = DatumGetBool(DirectFunctionCall2(numeric_ne, val_numeric, rdf_numeric));

	PG_RETURN_BOOL(result);
}

/* timestamp with time zone (timestamptz) */
Datum timestamptz_to_rdfnode(PG_FUNCTION_ARGS)
{
	TimestampTz ts = PG_GETARG_TIMESTAMPTZ(0);
	struct pg_tm tm;
	fsec_t fsec;
	StringInfoData buf;

	if (timestamp2tm(ts, NULL, &tm, &fsec, NULL, NULL) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("invalid timestamp")));

	initStringInfo(&buf);

	/* necessary for BCE timestamptz values */
	if (tm.tm_year < 0)
		appendStringInfo(&buf, "\"-%04d", -tm.tm_year);
	else
		appendStringInfo(&buf, "\"%04d", tm.tm_year);

	appendStringInfo(&buf,
					 "-%02d-%02dT%02d:%02d:%02d",
					 tm.tm_mon, tm.tm_mday,
					 tm.tm_hour, tm.tm_min, tm.tm_sec);

	if (fsec != 0)
		appendStringInfo(&buf, ".%06d", (int)fsec);

	appendStringInfo(&buf, "Z\"^^%s", RDF_XSD_DATETIME);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum rdfnode_to_timestamptz(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	StringInfoData buf;
	Datum result;

	if (!p.isDateTime && !p.isDate)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("cannot cast RDF literal: %s", text_to_cstring(t))));

	initStringInfo(&buf);

	/*
	 * XSD astronomical year:
	 *
	 *   0001 = 1 AD
	 *   0000 = 1 BC
	 *  -0001 = 2 BC
	 *  -0002 = 3 BC
	 *  ...
	 */
	if (*p.lex == '-')
	{
		char *rest;
		int year = strtol(p.lex + 1, &rest, 10);
		appendStringInfo(&buf, "%04d%s BC", year + 1, rest);
	}
	else if (strncmp(p.lex, "0000-", 5) == 0)
		appendStringInfo(&buf, "0001%s BC", p.lex + 4);
	else
		appendStringInfoString(&buf, p.lex);

	result = DirectFunctionCall3(timestamptz_in,
								 CStringGetDatum(buf.data),
								 ObjectIdGetDatum(InvalidOid),
								 Int32GetDatum(-1));

	PG_RETURN_DATUM(result);
}

/* timestamp */
Datum rdfnode_to_timestamp(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	StringInfoData buf;
	Datum result;

	if (!p.isDateTime && !p.isDate)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("cannot cast RDF literal: %s", text_to_cstring(t))));

	initStringInfo(&buf);

	/*
	 * XSD astronomical year:
	 *
	 *   0001 = 1 AD
	 *   0000 = 1 BC
	 *  -0001 = 2 BC
	 *  -0002 = 3 BC
	 *  ...
	 */
	if (*p.lex == '-')
	{
		char *rest;
		int year = strtol(p.lex + 1, &rest, 10);
		appendStringInfo(&buf, "%04d%s BC", year + 1, rest);
	}
	else if (strncmp(p.lex, "0000-", 5) == 0)
		appendStringInfo(&buf, "0001%s BC", p.lex + 4);
	else
		appendStringInfoString(&buf, p.lex);

	result = DirectFunctionCall3(timestamp_in,
								 CStringGetDatum(buf.data),
								 ObjectIdGetDatum(InvalidOid),
								 Int32GetDatum(-1));

	PG_RETURN_DATUM(result);
}

/* Which XSD datatypes a PostgreSQL temporal type can represent. */
#define RDF_TEMPORAL_DATE     (1 << 0)
#define RDF_TEMPORAL_TIME     (1 << 1)
#define RDF_TEMPORAL_DATETIME (1 << 2)

/*
 * RDFNodeToTemporal
 * -----------------
 *
 * Converts the lexical form of an RDF term into a PostgreSQL temporal value,
 * reporting whether the term belongs in that type's value space at all.
 *
 * A term carrying a datatype the target type cannot represent has no position
 * in its ordering, and neither has one whose lexical form the input function
 * rejects. Either way the caller answers without comparing instead of raising.
 * An ordinary filter over a graph is the reason: a predicate rarely carries a
 * single datatype throughout, so a comparison that raises on the first term of
 * another kind makes the whole query fail rather than return the rows that do
 * match. A plain literal carries no datatype to judge, so it is offered to the
 * input function and accepted if it parses.
 *
 * The input function is called with its full three-argument contract. Called
 * with one argument it reads an uninitialised typmod, which for these types
 * selects a fractional-digit precision and can silently truncate the value.
 *
 * t       : the RDF term
 * accepts : the datatypes the target type can represent
 * inputfn : the target type's input function
 * result  : the converted value, set only when the term is convertible
 *
 * returns true when the term was converted
 */
static bool
RDFNodeToTemporal(text *t, int accepts, PGFunction inputfn, Datum *result)
{
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	MemoryContext oldcontext = CurrentMemoryContext;
	volatile bool converted = false;

	if (!(p.isPlainLiteral ||
		  ((accepts & RDF_TEMPORAL_DATE) && p.isDate) ||
		  ((accepts & RDF_TEMPORAL_TIME) && p.isTime) ||
		  ((accepts & RDF_TEMPORAL_DATETIME) && p.isDateTime)))
		return false;

	PG_TRY();
	{
		*result = DirectFunctionCall3(inputfn,
									  CStringGetDatum(p.lex),
									  ObjectIdGetDatum(InvalidOid),
									  Int32GetDatum(-1));
		converted = true;
	}
	PG_CATCH();
	{
		ErrorData *edata;

		/*
		 * The handler runs in the error context, which is reset on the way
		 * out, so switch back before copying anything that has to outlive it.
		 */
		MemoryContextSwitchTo(oldcontext);
		edata = CopyErrorData();
		FlushErrorState();

		/*
		 * Only a complaint about the lexical form means the term is outside
		 * the type's value space. Anything else -- a statement timeout or an
		 * interrupt raised while parsing, say -- has nothing to do with the
		 * term, and reporting it as a non-matching row would hide it.
		 */
		if (edata->sqlerrcode != ERRCODE_INVALID_DATETIME_FORMAT &&
			edata->sqlerrcode != ERRCODE_DATETIME_FIELD_OVERFLOW &&
			edata->sqlerrcode != ERRCODE_DATETIME_VALUE_OUT_OF_RANGE &&
			edata->sqlerrcode != ERRCODE_INVALID_TEXT_REPRESENTATION)
			ReThrowError(edata);

		FreeErrorData(edata);
	}
	PG_END_TRY();

	return converted;
}

Datum rdfnode_eq_timestamp(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamp_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_eq,
													rdf_val, TimestampGetDatum(PG_GETARG_TIMESTAMP(1)))));
}

Datum rdfnode_neq_timestamp(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamp_in, &rdf_val))
		PG_RETURN_BOOL(true);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_ne,
													rdf_val, TimestampGetDatum(PG_GETARG_TIMESTAMP(1)))));
}

Datum rdfnode_lt_timestamp(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamp_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_lt,
													rdf_val, TimestampGetDatum(PG_GETARG_TIMESTAMP(1)))));
}

Datum rdfnode_gt_timestamp(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamp_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_gt,
													rdf_val, TimestampGetDatum(PG_GETARG_TIMESTAMP(1)))));
}

Datum rdfnode_le_timestamp(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamp_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_le,
													rdf_val, TimestampGetDatum(PG_GETARG_TIMESTAMP(1)))));
}

Datum rdfnode_ge_timestamp(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamp_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_ge,
													rdf_val, TimestampGetDatum(PG_GETARG_TIMESTAMP(1)))));
}

Datum timestamp_to_rdfnode(PG_FUNCTION_ARGS)
{
	Timestamp ts = PG_GETARG_TIMESTAMP(0);
	struct pg_tm tm;
	fsec_t fsec;
	StringInfoData buf;

	if (timestamp2tm(ts, NULL, &tm, &fsec, NULL, NULL) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("invalid timestamp")));

	initStringInfo(&buf);

	/* necessary for BCE timestamp values */
	if (tm.tm_year < 0)
		appendStringInfo(&buf, "\"-%04d", -tm.tm_year);
	else
		appendStringInfo(&buf, "\"%04d", tm.tm_year);

	appendStringInfo(&buf,
					 "-%02d-%02dT%02d:%02d:%02d",
					 tm.tm_mon, tm.tm_mday,
					 tm.tm_hour, tm.tm_min, tm.tm_sec);

	if (fsec != 0)
		appendStringInfo(&buf, ".%06d", (int)fsec);

	appendStringInfo(&buf, "\"^^%s", RDF_XSD_DATETIME);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum timestamp_eq_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamp_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_eq,
													TimestampGetDatum(PG_GETARG_TIMESTAMP(0)), rdf_val)));
}

Datum timestamp_neq_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamp_in, &rdf_val))
		PG_RETURN_BOOL(true);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_ne,
													TimestampGetDatum(PG_GETARG_TIMESTAMP(0)), rdf_val)));
}

Datum timestamp_lt_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamp_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_lt,
													TimestampGetDatum(PG_GETARG_TIMESTAMP(0)), rdf_val)));
}

Datum timestamp_gt_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamp_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_gt,
													TimestampGetDatum(PG_GETARG_TIMESTAMP(0)), rdf_val)));
}

Datum timestamp_le_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamp_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_le,
													TimestampGetDatum(PG_GETARG_TIMESTAMP(0)), rdf_val)));
}

Datum timestamp_ge_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamp_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_ge,
													TimestampGetDatum(PG_GETARG_TIMESTAMP(0)), rdf_val)));
}

/* date */
Datum rdfnode_eq_timestamptz(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamptz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_eq,
													rdf_val, TimestampTzGetDatum(PG_GETARG_TIMESTAMPTZ(1)))));
}

Datum timestamptz_eq_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamptz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_eq,
													TimestampTzGetDatum(PG_GETARG_TIMESTAMPTZ(0)), rdf_val)));
}

Datum rdfnode_neq_timestamptz(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamptz_in, &rdf_val))
		PG_RETURN_BOOL(true);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_ne,
													rdf_val, TimestampTzGetDatum(PG_GETARG_TIMESTAMPTZ(1)))));
}

Datum timestamptz_neq_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamptz_in, &rdf_val))
		PG_RETURN_BOOL(true);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_ne,
													TimestampTzGetDatum(PG_GETARG_TIMESTAMPTZ(0)), rdf_val)));
}

Datum rdfnode_lt_timestamptz(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamptz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_lt,
													rdf_val, TimestampTzGetDatum(PG_GETARG_TIMESTAMPTZ(1)))));
}

Datum timestamptz_lt_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamptz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_lt,
													TimestampTzGetDatum(PG_GETARG_TIMESTAMPTZ(0)), rdf_val)));
}

Datum rdfnode_gt_timestamptz(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamptz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_gt,
													rdf_val, TimestampTzGetDatum(PG_GETARG_TIMESTAMPTZ(1)))));
}

Datum timestamptz_gt_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamptz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_gt,
													TimestampTzGetDatum(PG_GETARG_TIMESTAMPTZ(0)), rdf_val)));
}

Datum rdfnode_le_timestamptz(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamptz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_le,
													rdf_val, TimestampTzGetDatum(PG_GETARG_TIMESTAMPTZ(1)))));
}

Datum timestamptz_le_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamptz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_le,
													TimestampTzGetDatum(PG_GETARG_TIMESTAMPTZ(0)), rdf_val)));
}

Datum rdfnode_ge_timestamptz(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamptz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_ge,
													rdf_val, TimestampTzGetDatum(PG_GETARG_TIMESTAMPTZ(1)))));
}

Datum timestamptz_ge_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   timestamptz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timestamp_ge,
													TimestampTzGetDatum(PG_GETARG_TIMESTAMPTZ(0)), rdf_val)));
}
Datum rdfnode_to_date(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	StringInfoData buf;
	Datum result;

	if (!p.isDateTime && !p.isDate)
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				errmsg("cannot cast RDF literal: %s", text_to_cstring(t))));

	initStringInfo(&buf);

	/*
	 * XSD astronomical year:
	 *
	 *   0001 = 1 AD
	 *   0000 = 1 BC
	 *  -0001 = 2 BC
	 *  -0002 = 3 BC
	 *  ...
	 */
	if (*p.lex == '-')
	{
		char *rest;
		int year = strtol(p.lex + 1, &rest, 10);
		appendStringInfo(&buf, "%04d%s BC", year + 1, rest);
	}
	else if (strncmp(p.lex, "0000-", 5) == 0)
		appendStringInfo(&buf, "0001%s BC", p.lex + 4);
	else
		appendStringInfoString(&buf, p.lex);

	result = DirectFunctionCall3(date_in,
								CStringGetDatum(buf.data),
								ObjectIdGetDatum(InvalidOid),
								Int32GetDatum(-1));

	PG_RETURN_DATEADT(DatumGetDateADT(result));
}

Datum rdfnode_lt_date(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   date_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(date_lt,
													rdf_val, DateADTGetDatum(PG_GETARG_DATEADT(1)))));
}

Datum rdfnode_le_date(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   date_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(date_le,
													rdf_val, DateADTGetDatum(PG_GETARG_DATEADT(1)))));
}

Datum rdfnode_gt_date(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   date_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(date_gt,
													rdf_val, DateADTGetDatum(PG_GETARG_DATEADT(1)))));
}

Datum rdfnode_ge_date(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   date_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(date_ge,
													rdf_val, DateADTGetDatum(PG_GETARG_DATEADT(1)))));
}

Datum rdfnode_eq_date(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   date_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(date_eq,
													rdf_val, DateADTGetDatum(PG_GETARG_DATEADT(1)))));
}

Datum rdfnode_neq_date(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   date_in, &rdf_val))
		PG_RETURN_BOOL(true);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(date_ne,
													rdf_val, DateADTGetDatum(PG_GETARG_DATEADT(1)))));
}

Datum date_to_rdfnode(PG_FUNCTION_ARGS)
{
	DateADT d = PG_GETARG_DATEADT(0);
	StringInfoData buf;
	int year, month, day;

	j2date(d + POSTGRES_EPOCH_JDATE, &year, &month, &day);

	initStringInfo(&buf);

	/* necessary for BCE date values */
	if (year < 0)
		appendStringInfo(&buf, "\"-%04d", -year);
	else
		appendStringInfo(&buf, "\"%04d", year);

	appendStringInfo(&buf, "-%02d-%02d\"^^%s", month, day, RDF_XSD_DATE);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum date_lt_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   date_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(date_lt,
													DateADTGetDatum(PG_GETARG_DATEADT(0)), rdf_val)));
}

Datum date_le_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   date_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(date_le,
													DateADTGetDatum(PG_GETARG_DATEADT(0)), rdf_val)));
}

Datum date_gt_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   date_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(date_gt,
													DateADTGetDatum(PG_GETARG_DATEADT(0)), rdf_val)));
}

Datum date_ge_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   date_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(date_ge,
													DateADTGetDatum(PG_GETARG_DATEADT(0)), rdf_val)));
}

Datum date_eq_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   date_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(date_eq,
													DateADTGetDatum(PG_GETARG_DATEADT(0)), rdf_val)));
}

Datum date_neq_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_DATE | RDF_TEMPORAL_DATETIME,
						   date_in, &rdf_val))
		PG_RETURN_BOOL(true);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(date_ne,
													DateADTGetDatum(PG_GETARG_DATEADT(0)), rdf_val)));
}

/* time (without time zone) */
Datum rdfnode_to_time(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	Datum result = DirectFunctionCall3(time_in,
									   CStringGetDatum(p.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));

	PG_RETURN_TIMEADT(DatumGetTimeADT(result));
}

Datum rdfnode_lt_time(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_TIME,
						   time_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(time_lt,
													rdf_val, TimeADTGetDatum(PG_GETARG_TIMEADT(1)))));
}

Datum rdfnode_le_time(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_TIME,
						   time_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(time_le,
													rdf_val, TimeADTGetDatum(PG_GETARG_TIMEADT(1)))));
}

Datum rdfnode_gt_time(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_TIME,
						   time_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(time_gt,
													rdf_val, TimeADTGetDatum(PG_GETARG_TIMEADT(1)))));
}

Datum rdfnode_ge_time(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_TIME,
						   time_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(time_ge,
													rdf_val, TimeADTGetDatum(PG_GETARG_TIMEADT(1)))));
}

Datum rdfnode_eq_time(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_TIME,
						   time_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(time_eq,
													rdf_val, TimeADTGetDatum(PG_GETARG_TIMEADT(1)))));
}

Datum rdfnode_neq_time(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_TIME,
						   time_in, &rdf_val))
		PG_RETURN_BOOL(true);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(time_ne,
													rdf_val, TimeADTGetDatum(PG_GETARG_TIMEADT(1)))));
}

Datum time_to_rdfnode(PG_FUNCTION_ARGS)
{
	TimeADT t = PG_GETARG_TIMEADT(0);
	char *valstr;
	StringInfoData buf;

	valstr = DatumGetCString(DirectFunctionCall1(time_out, TimeADTGetDatum(t)));
	initStringInfo(&buf);
	appendStringInfo(&buf, "\"%s\"^^%s", valstr, RDF_XSD_TIME);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum time_lt_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_TIME,
						   time_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(time_lt,
													TimeADTGetDatum(PG_GETARG_TIMEADT(0)), rdf_val)));
}

Datum time_le_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_TIME,
						   time_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(time_le,
													TimeADTGetDatum(PG_GETARG_TIMEADT(0)), rdf_val)));
}

Datum time_gt_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_TIME,
						   time_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(time_gt,
													TimeADTGetDatum(PG_GETARG_TIMEADT(0)), rdf_val)));
}

Datum time_ge_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_TIME,
						   time_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(time_ge,
													TimeADTGetDatum(PG_GETARG_TIMEADT(0)), rdf_val)));
}

Datum time_eq_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_TIME,
						   time_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(time_eq,
													TimeADTGetDatum(PG_GETARG_TIMEADT(0)), rdf_val)));
}

Datum time_neq_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_TIME,
						   time_in, &rdf_val))
		PG_RETURN_BOOL(true);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(time_ne,
													TimeADTGetDatum(PG_GETARG_TIMEADT(0)), rdf_val)));
}

/*  time with time zone (timetz) */
Datum rdfnode_to_timetz(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum result = DirectFunctionCall3(timetz_in,
									   CStringGetDatum(p.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));

	PG_RETURN_TIMETZADT_P(DatumGetTimeTzADTP(result));
}

Datum rdfnode_lt_timetz(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_TIME,
						   timetz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timetz_lt,
													rdf_val, TimeTzADTPGetDatum(PG_GETARG_TIMETZADT_P(1)))));
}

Datum rdfnode_le_timetz(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_TIME,
						   timetz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timetz_le,
													rdf_val, TimeTzADTPGetDatum(PG_GETARG_TIMETZADT_P(1)))));
}

Datum rdfnode_gt_timetz(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_TIME,
						   timetz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timetz_gt,
													rdf_val, TimeTzADTPGetDatum(PG_GETARG_TIMETZADT_P(1)))));
}

Datum rdfnode_ge_timetz(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_TIME,
						   timetz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timetz_ge,
													rdf_val, TimeTzADTPGetDatum(PG_GETARG_TIMETZADT_P(1)))));
}

Datum rdfnode_eq_timetz(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_TIME,
						   timetz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timetz_eq,
													rdf_val, TimeTzADTPGetDatum(PG_GETARG_TIMETZADT_P(1)))));
}

Datum rdfnode_neq_timetz(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(0), RDF_TEMPORAL_TIME,
						   timetz_in, &rdf_val))
		PG_RETURN_BOOL(true);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timetz_ne,
													rdf_val, TimeTzADTPGetDatum(PG_GETARG_TIMETZADT_P(1)))));
}

Datum timetz_to_rdfnode(PG_FUNCTION_ARGS)
{
	TimeTzADT *t = PG_GETARG_TIMETZADT_P(0);
	struct pg_tm tm;
	fsec_t fsec;
	int tz, tz_hours, tz_mins;
	StringInfoData buf;

#if PG_VERSION_NUM >= 110000
    if (timetz2tm(t, &tm, &fsec, &tz) != 0)
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("invalid time with time zone")));
#else
    /* TimeTzADT is {TimeADT time; int32 zone;} in older PG */
    tz = t->zone;
    {
        TimeADT time = t->time;
        tm.tm_hour = (int)(time / USECS_PER_HOUR);
        time -= (TimeADT)tm.tm_hour * USECS_PER_HOUR;
        tm.tm_min = (int)(time / USECS_PER_MINUTE);
        time -= (TimeADT)tm.tm_min * USECS_PER_MINUTE;
        tm.tm_sec = (int)(time / USECS_PER_SEC);
        fsec = (fsec_t)(time - (TimeADT)tm.tm_sec * USECS_PER_SEC);
    }
#endif

	initStringInfo(&buf);

	tz_hours = abs(tz) / 3600;
	tz_mins  = (abs(tz) % 3600) / 60;

	if (fsec != 0)
	{
		char frac[8];
		int flen;

		snprintf(frac, sizeof(frac), "%06d", (int)fsec);
		flen = 6;
		while (flen > 1 && frac[flen - 1] == '0')
			flen--;
		frac[flen] = '\0';

		if (tz == 0)
			appendStringInfo(&buf,
							"\"%02d:%02d:%02d.%s+00:00\"^^%s",
							tm.tm_hour, tm.tm_min, tm.tm_sec,
							frac, RDF_XSD_TIME);
		else
			appendStringInfo(&buf,
							"\"%02d:%02d:%02d.%s%c%02d:%02d\"^^%s",
							tm.tm_hour, tm.tm_min, tm.tm_sec,
							frac,
							tz < 0 ? '+' : '-',
							tz_hours, tz_mins,
							RDF_XSD_TIME);
	}
	else
	{
		if (tz == 0)
			appendStringInfo(&buf,
							"\"%02d:%02d:%02d+00:00\"^^%s",
							tm.tm_hour, tm.tm_min, tm.tm_sec,
							RDF_XSD_TIME);
		else
			appendStringInfo(&buf,
							"\"%02d:%02d:%02d%c%02d:%02d\"^^%s",
							tm.tm_hour, tm.tm_min, tm.tm_sec,
							tz < 0 ? '+' : '-',
							tz_hours, tz_mins,
							RDF_XSD_TIME);
	}

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum timetz_lt_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_TIME,
						   timetz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timetz_lt,
													TimeTzADTPGetDatum(PG_GETARG_TIMETZADT_P(0)), rdf_val)));
}

Datum timetz_le_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_TIME,
						   timetz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timetz_le,
													TimeTzADTPGetDatum(PG_GETARG_TIMETZADT_P(0)), rdf_val)));
}

Datum timetz_gt_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_TIME,
						   timetz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timetz_gt,
													TimeTzADTPGetDatum(PG_GETARG_TIMETZADT_P(0)), rdf_val)));
}

Datum timetz_ge_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_TIME,
						   timetz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timetz_ge,
													TimeTzADTPGetDatum(PG_GETARG_TIMETZADT_P(0)), rdf_val)));
}

Datum timetz_eq_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_TIME,
						   timetz_in, &rdf_val))
		PG_RETURN_BOOL(false);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timetz_eq,
													TimeTzADTPGetDatum(PG_GETARG_TIMETZADT_P(0)), rdf_val)));
}

Datum timetz_neq_rdfnode(PG_FUNCTION_ARGS)
{
	Datum rdf_val;

	if (!RDFNodeToTemporal(PG_GETARG_TEXT_PP(1), RDF_TEMPORAL_TIME,
						   timetz_in, &rdf_val))
		PG_RETURN_BOOL(true);

	PG_RETURN_BOOL(DatumGetBool(DirectFunctionCall2(timetz_ne,
													TimeTzADTPGetDatum(PG_GETARG_TIMETZADT_P(0)), rdf_val)));
}

/* boolean */
Datum rdfnode_to_boolean(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	bool result;

	if (strcmp(p.dtype, RDF_XSD_BOOLEAN) != 0 && strcmp(p.dtype, RDF_XSD_INTEGER) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_CANNOT_COERCE),
				 errmsg("cannot cast RDF literal: %s to boolean", p.raw)));

	if (pg_strcasecmp(p.lex, "true") == 0 || strcmp(p.lex, "1") == 0)
		result = true;
	else if (pg_strcasecmp(p.lex, "false") == 0 || strcmp(p.lex, "0") == 0)
		result = false;
	else
		ereport(ERROR,
				(errcode(ERRCODE_CANNOT_COERCE),
				 errmsg("cannot cast RDF literal: %s to boolean", p.raw),
				 errdetail("Expected values for xsd:boolean are \"true\" or \"false\".")));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_eq_boolean(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	bool val = PG_GETARG_BOOL(1);
	char *literal = text_to_cstring(t);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	if (strcmp(p.dtype, RDF_XSD_BOOLEAN) != 0 && strcmp(p.dtype, RDF_XSD_INTEGER) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_CANNOT_COERCE),
				 errmsg("cannot cast RDF literal: %s to boolean", literal)));

	if ((pg_strcasecmp(p.lex, "true") == 0 || strcmp(p.lex, "1") == 0) && val)
		PG_RETURN_BOOL(true);
	else if ((pg_strcasecmp(p.lex, "false") == 0 || strcmp(p.lex, "0") == 0) && !val)
		PG_RETURN_BOOL(true);
	else
		PG_RETURN_BOOL(false);
}

Datum rdfnode_neq_boolean(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	bool val = PG_GETARG_BOOL(1);
	char *literal = text_to_cstring(t);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	if (strcmp(p.dtype, RDF_XSD_BOOLEAN) != 0 && strcmp(p.dtype, RDF_XSD_INTEGER) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_CANNOT_COERCE),
				 errmsg("cannot cast RDF literal: %s to boolean", literal)));

	if ((pg_strcasecmp(p.lex, "true") == 0 || strcmp(p.lex, "1") == 0) && !val)
		PG_RETURN_BOOL(true);
	else if ((pg_strcasecmp(p.lex, "false") == 0 || strcmp(p.lex, "0") == 0) && val)
		PG_RETURN_BOOL(true);
	else
		PG_RETURN_BOOL(false);
}

Datum boolean_to_rdfnode(PG_FUNCTION_ARGS)
{
	bool val = PG_GETARG_BOOL(0);
	StringInfoData buf;
	initStringInfo(&buf);

	if (val)
		appendStringInfo(&buf, "\"true\"^^%s", RDF_XSD_BOOLEAN);
	else
		appendStringInfo(&buf, "\"false\"^^%s", RDF_XSD_BOOLEAN);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum boolean_eq_rdfnode(PG_FUNCTION_ARGS)
{
	bool val = PG_GETARG_BOOL(0);
	text *t = PG_GETARG_TEXT_PP(1);
	char *literal = text_to_cstring(t);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	if (strcmp(p.dtype, RDF_XSD_BOOLEAN) != 0 && strcmp(p.dtype, RDF_XSD_INTEGER) != 0)
		ereport(ERROR,
			(errcode(ERRCODE_CANNOT_COERCE),
			 errmsg("cannot cast RDF literal: %s to boolean", literal)));

	if ((pg_strcasecmp(p.lex, "true") == 0 || strcmp(p.lex, "1") == 0) && val)
		PG_RETURN_BOOL(true);
	else if ((pg_strcasecmp(p.lex, "false") == 0 || strcmp(p.lex, "0") == 0) && !val)
		PG_RETURN_BOOL(true);
	else
		PG_RETURN_BOOL(false);
}

Datum boolean_neq_rdfnode(PG_FUNCTION_ARGS)
{
	bool val = PG_GETARG_BOOL(0);
	text *t = PG_GETARG_TEXT_PP(1);
	char *literal = text_to_cstring(t);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	if (strcmp(p.dtype, RDF_XSD_BOOLEAN) != 0 && strcmp(p.dtype, RDF_XSD_INTEGER) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_CANNOT_COERCE),
				 errmsg("cannot cast RDF literal: %s to boolean", literal)));

	if ((pg_strcasecmp(p.lex, "true") == 0 || strcmp(p.lex, "1") == 0) && !val)
		PG_RETURN_BOOL(true);
	else if ((pg_strcasecmp(p.lex, "false") == 0 || strcmp(p.lex, "0") == 0) && val)
		PG_RETURN_BOOL(true);
	else
		PG_RETURN_BOOL(false);
}

/*
 * xsd_duration_to_pg_interval
 * ----------------------------
 * Converts an XSD duration lexical form to a PostgreSQL Interval Datum.
 *
 * XSD uses a leading '-' before 'P' to denote negative durations (e.g.
 * "-P1Y2M"), but PostgreSQL's interval_in() only accepts the ISO 8601
 * element-level form.  Strip the leading '-', parse the positive form, and
 * negate the result with interval_um().
 *
 * lex: the bare lexical value extracted from the rdfnode (e.g. "P1DT4H" or
 *      "-P1Y2M")
 *
 * returns a Datum holding the PostgreSQL Interval
 */
static Datum
xsd_duration_to_pg_interval(const char *lex)
{
	Datum result = DirectFunctionCall3(interval_in,
									   CStringGetDatum(lex[0] == '-' ? lex + 1 : lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));

	if (lex[0] == '-')
		result = DirectFunctionCall1(interval_um, result);

	return result;
}

/* interval */
Datum rdfnode_to_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);

	if (strcmp(p.dtype, RDF_XSD_DURATION) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_CANNOT_COERCE),
				 errmsg("cannot cast RDF literal: %s to interval", p.raw),
				 errdetail("Expected xsd:duration.")));

	PG_RETURN_DATUM(xsd_duration_to_pg_interval(p.lex));
}

Datum rdfnode_eq_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Interval *val = PG_GETARG_INTERVAL_P(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_interval = xsd_duration_to_pg_interval(p.lex);
	bool result = DatumGetBool(DirectFunctionCall2(interval_eq,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Interval *val = PG_GETARG_INTERVAL_P(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_interval = xsd_duration_to_pg_interval(p.lex);
	bool result = DatumGetBool(DirectFunctionCall2(interval_ne,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_lt_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Interval *val = PG_GETARG_INTERVAL_P(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_interval = xsd_duration_to_pg_interval(p.lex);
	bool result = DatumGetBool(DirectFunctionCall2(interval_lt,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Interval *val = PG_GETARG_INTERVAL_P(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_interval = xsd_duration_to_pg_interval(p.lex);
	bool result = DatumGetBool(DirectFunctionCall2(interval_le,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Interval *val = PG_GETARG_INTERVAL_P(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_interval = xsd_duration_to_pg_interval(p.lex);
	bool result = DatumGetBool(DirectFunctionCall2(interval_gt,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Interval *val = PG_GETARG_INTERVAL_P(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_interval = xsd_duration_to_pg_interval(p.lex);
	bool result = DatumGetBool(DirectFunctionCall2(interval_ge,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum interval_to_rdfnode(PG_FUNCTION_ARGS)
{
	Interval *iv = PG_GETARG_INTERVAL_P(0);
	StringInfoData buf;
	bool is_negative = false;
	int years, months, days, hours, mins, secs, usecs;
	bool is_zero;
	bool has_positive = (iv->month > 0 || iv->day > 0 || iv->time > 0);
	bool has_negative = (iv->month < 0 || iv->day < 0 || iv->time < 0);

	initStringInfo(&buf);

	if (has_negative && !has_positive)
		is_negative = true;

	years = iv->month / 12;
	months = iv->month % 12;
	days = iv->day;
	hours = (iv->time / USECS_PER_HOUR);
	mins = (iv->time % USECS_PER_HOUR) / USECS_PER_MINUTE;
	secs = (iv->time % USECS_PER_MINUTE) / USECS_PER_SEC;
	usecs = iv->time % USECS_PER_SEC;

	/* check for zero duration */
	is_zero = (years == 0 && months == 0 && days == 0 &&
			   hours == 0 && mins == 0 && secs == 0 && usecs == 0);

	appendStringInfoChar(&buf, '\"');

	if (is_zero)
	{
		/* use PT0S for zero durations */
		appendStringInfo(&buf, "PT0S");
	}
	else
	{
		/* andle negative interval */
		if (is_negative)
			appendStringInfoChar(&buf, '-');

		appendStringInfoChar(&buf, 'P');

		/* add years, months, and days */
		if (years != 0)
			appendStringInfo(&buf, "%dY", is_negative ? abs(years) : years);
		if (months != 0)
			appendStringInfo(&buf, "%dM", is_negative ? abs(months) : months);
		if (days != 0)
			appendStringInfo(&buf, "%dD", is_negative ? abs(days) : days);

		/* add time portion (hours, minutes, seconds, microseconds) */
		if (hours != 0 || mins != 0 || secs != 0 || usecs != 0)
		{
			appendStringInfoChar(&buf, 'T');

			if (hours != 0)
				appendStringInfo(&buf, "%dH", is_negative ? abs(hours) : hours);
			if (mins != 0)
				appendStringInfo(&buf, "%dM", is_negative ? abs(mins) : mins);

			if (usecs != 0)
			{
				int64 total_usecs = (int64)secs * USECS_PER_SEC + usecs;  /* preserves combined sign */
				int abs_secs = (int)(labs(total_usecs) / USECS_PER_SEC);
				int abs_usecs = (int)(labs(total_usecs) % USECS_PER_SEC);
				char frac[8];
				int flen;

				snprintf(frac, sizeof(frac), "%06d", abs_usecs);
				flen = 6;
				while (flen > 1 && frac[flen - 1] == '0')
					flen--;
				frac[flen] = '\0';

				if (is_negative)
					appendStringInfo(&buf, "%d.%sS", abs_secs, frac);
				else
					appendStringInfo(&buf, "%s%d.%sS", total_usecs < 0 ? "-" : "", abs_secs, frac);
			}
			else if (secs != 0)
				appendStringInfo(&buf, "%dS", is_negative ? abs(secs) : secs);
		}
	}

	/* close the literal and add the RDF type */
	appendStringInfo(&buf, "\"^^%s", RDF_XSD_DURATION);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum interval_eq_rdfnode(PG_FUNCTION_ARGS)
{
	Interval *val = PG_GETARG_INTERVAL_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_interval = xsd_duration_to_pg_interval(p.lex);
	bool result = DatumGetBool(DirectFunctionCall2(interval_eq,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum interval_neq_rdfnode(PG_FUNCTION_ARGS)
{
	Interval *val = PG_GETARG_INTERVAL_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_interval = xsd_duration_to_pg_interval(p.lex);
	bool result = DatumGetBool(DirectFunctionCall2(interval_ne,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum interval_lt_rdfnode(PG_FUNCTION_ARGS)
{
	Interval *val = PG_GETARG_INTERVAL_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_interval = xsd_duration_to_pg_interval(p.lex);
	bool result = DatumGetBool(DirectFunctionCall2(interval_lt,
												   IntervalPGetDatum(val),
												   rdf_interval));

	PG_RETURN_BOOL(result);
}

Datum interval_le_rdfnode(PG_FUNCTION_ARGS)
{
	Interval *val = PG_GETARG_INTERVAL_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_interval = xsd_duration_to_pg_interval(p.lex);
	bool result = DatumGetBool(DirectFunctionCall2(interval_le,
												   IntervalPGetDatum(val),
												   rdf_interval));

	PG_RETURN_BOOL(result);
}

Datum interval_gt_rdfnode(PG_FUNCTION_ARGS)
{
	Interval *val = PG_GETARG_INTERVAL_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_interval = xsd_duration_to_pg_interval(p.lex);
	bool result = DatumGetBool(DirectFunctionCall2(interval_gt,
												   IntervalPGetDatum(val),
												   rdf_interval));

	PG_RETURN_BOOL(result);
}

Datum interval_ge_rdfnode(PG_FUNCTION_ARGS)
{
	Interval *val = PG_GETARG_INTERVAL_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	rdfnode_info p = parse_rdfnode((rdfnode *)t);
	Datum rdf_interval = xsd_duration_to_pg_interval(p.lex);
	bool result = DatumGetBool(DirectFunctionCall2(interval_ge,
												   IntervalPGetDatum(val),
												   rdf_interval));

	PG_RETURN_BOOL(result);
}
