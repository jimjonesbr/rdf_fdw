
/*---------------------------------------------------------------------
 *
 * rdf_utils.c
 *   Utility functions for RDF data manipulation and validation.
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

#include "lib/stringinfo.h"
#include "utils/builtins.h"
#if PG_VERSION_NUM >= 100000
#include "utils/varlena.h"
#endif
#include "access/htup_details.h"
#include "catalog/pg_type.h"
#include "mb/pg_wchar.h"
#include "nodes/makefuncs.h"
#include <regex.h>
#include <string.h>
#include <ctype.h>

/* Type mapping table for PostgreSQL types to XSD datatypes */
static const TypeXSDMap type_map[] = {
	{INT2OID, "integer"},
	{INT4OID, "integer"},
	{INT8OID, "integer"},
	{NUMERICOID, "decimal"},
	{FLOAT8OID, "double"},
	{FLOAT4OID, "float"},
	{BOOLOID, "boolean"},
	{TIMESTAMPOID, "dateTime"},
	{DATEOID, "date"},
	{TIMEOID, "time"},
	{TEXTOID, "string"},
	{NAMEOID, "string"},
	{TIMESTAMPTZOID, "dateTime"},
	{InvalidOid, NULL}
};

/*
 * ContainsWhitespaces
 * ---------------
 * Checks if a string contains whitespaces
 *
 * str: string to be evaluated
 *
 * returns true if the string contains whitespaces or false otherwise
 */
bool ContainsWhitespaces(char *str)
{
	elog(DEBUG3, "%s called: str='%s'", __func__, str);

	for (int i = 0; str[i] != '\0'; i++)
		if (isspace((unsigned char)str[i]))
		{
			elog(DEBUG3, "%s exit: returning 'true'", __func__);
			return true;
		}

	elog(DEBUG3, "%s exit: returning 'false'", __func__);
	return false;
}

/*
 * is_valid_language_tag
 * ----------------------
 * Validates language tags according to the pattern: [a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*
 * Examples: "en", "en-US", "de-DE"
 */
bool is_valid_language_tag(const char *lan)
{
	regex_t regex;
	int reti;
	bool is_valid = false;
	const char *pattern = "^[a-zA-Z]{1,8}(-[a-zA-Z0-9]{1,8})*$";

	reti = regcomp(&regex, pattern, REG_EXTENDED);

	if (reti)
		ereport(ERROR, (errmsg("could not compile regex for language tag")));

	reti = regexec(&regex, lan, 0, NULL, 0);

	if (reti == 0)
		is_valid = true;

	regfree(&regex);
	return is_valid;
}
/*
 * isPlainLiteral
 * --------------
 * Checks if a literal is a plain literal (no language tag or datatype).
 */
bool isPlainLiteral(char *literal)
{
	if (strlen(lang(literal)) != 0 || strlen(datatype(literal)) != 0)
		return false;

	return true;
}

/*
 * LiteralsCompatible
 * ------------------
 *
 * Determines if two RDF literals are compatible according to SPARQL rules.
 * Compatibility is based on language tags and datatypes: literals are compatible
 * if they are both simple literals or xsd:string, or if they have identical
 * language tags, or if one has a language tag and the other is a simple literal
 * or xsd:string. Incompatible cases (e.g., one with a datatype and the other
 * with a language tag) return false.
 *
 * literal1: Null-terminated C string representing an RDF literal (e.g., "abc"@en, "123"^^xsd:integer)
 * literal2: Null-terminated C string representing an RDF literal (e.g., "def", "456"^^xsd:string)
 *
 * returns: C boolean (true if literals are compatible, false otherwise)
 */
bool LiteralsCompatible(char *literal1, char *literal2)
{
	char *lang1;
	char *lang2;
	char *dt1;
	char *dt2;

	elog(DEBUG3, "%s called: literal1='%s', literal2='%s'", __func__, literal1, literal2);

	lang1 = lang(literal1);
	lang2 = lang(literal2);
	dt1 = datatype(literal1);
	dt2 = datatype(literal2);

	if (!literal1 || !literal2)
	{
		elog(DEBUG3, "%s exit: returning 'false' (one of the arguments is NULL)", __func__);
		return false;
	}

	/*TODO: check if RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED is needed, as the prefix is expaded elsewhere */

	/* both simple literals or xsd:string */
	if (strlen(lang1) == 0 && strlen(lang2) == 0 &&
		(strlen(dt1) == 0 || strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE) == 0) &&
		(strlen(dt2) == 0 || strcmp(dt2, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt2, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
	{
		elog(DEBUG3, "%s exit: returning 'true' (both simple literals or xsd:string)", __func__);
		return true;
	}

	/* both plain literals with identical language tags */
	if (strlen(lang1) > 0 && strlen(lang2) > 0 && strcmp(lang1, lang2) == 0)
	{
		elog(DEBUG3, "%s exit: returning 'true' (both plain literals with identical language tags)", __func__);
		return true;
	}

	/* arg1 has language tag, arg2 is simple or xsd:string */
	if (strlen(lang1) > 0 && strlen(lang2) == 0 &&
		(strlen(dt2) == 0 || strcmp(dt2, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt2, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
	{
		elog(DEBUG3, "%s exit: returning 'true' (arg1 has language tag, arg2 is simple or xsd:string)", __func__);
		return true;
	}

	/* incompatible otherwise (e.g., arg1 xsd:string, arg2 language-tagged) */
	elog(DEBUG3, "%s exit: returning 'false' (incompatible)", __func__);
	return false;
}

/*
 * cstring_to_rdfliteral
 * ---------------------
 *
 * Converts a raw string input into a valid RDF literal by adding quotes and escaping
 * internal quotes as needed. If the input is already a complete RDF literal (i.e.,
 * quoted with a language tag or datatype), it is returned unchanged.
 *
 * input: the raw string or partial literal to convert (e.g., "abc", "abc"@en, "ab\"c")
 *
 * returns: a string representing the RDF literal (e.g., "\"abc\"", "\"ab\\\"c\"")
 *          or the input as-is if already a complete literal.
 */
char *cstring_to_rdfliteral(char *input)
{
	StringInfoData buf;
	const char *start;
	const char *end;
	int len;

	elog(DEBUG3, "%s called: input='%s'", __func__, input);

	/* return the string as-is if the input is an IRI */
	if (isIRI(input))
		return input;

	if (!input || strlen(input) == 0)
	{
		elog(DEBUG3, "%s exit: returning empty literal '\"\"'", __func__);
		return "\"\""; /* empty input becomes empty literal */
	}

	start = input;
	len = strlen(start);

	initStringInfo(&buf);

	/* check if it's already a complete RDF literal */
	if (*start == '"')
	{
		end = start + len - 1; /* last character */
		if (end > start)
		{
			const char *tag = strstr(start, "@");
			if (!tag)
				tag = strstr(start, "^^");

			if (tag && tag > start + 1 && *(tag - 1) == '"')
			{
				elog(DEBUG3, "%s exit: returning => '%s'", __func__, input);
				/* complete literal with lang or type, return as-is */
				return input;
			}
		}
	}

	/* not a complete literal, treat as raw content */
	end = start + len;

	/* add opening quote */
	appendStringInfoChar(&buf, '"');

	/* process the content, escaping all quotes */
	while (start < end)
	{
		if (*start == '"')
		{
			/* escape unless already escaped */
			if (start == input || *(start - 1) != '\\')
			{
				appendStringInfoChar(&buf, '\\');
			}
			appendStringInfoChar(&buf, '"');
		}
		else
		{
			appendStringInfoChar(&buf, *start);
		}
		start++;
	}

	/* add closing quote */
	appendStringInfoChar(&buf, '"');

	elog(DEBUG3, "%s exit: returning => '%s'", __func__, buf.data);
	return buf.data;
}

/*
 * ExpandDatatypePrefix
 * --------------------
 *
 * Expands a datatype prefix (e.g., "xsd:") to its full URI form if recognized.
 * Strips angle brackets (< >) from input before processing. Supports "xsd:" mapped
 * to "http://www.w3.org/2001/XMLSchema#". Returns the input as-is (without < >)
 * for other prefixed or bare datatypes, assuming prefix resolution elsewhere.
 *
 * str: Null-terminated C string representing a datatype (e.g., "xsd:string", "<foo:bar>")
 *
 * returns: Null-terminated C string, expanded for "xsd:" or stripped/as-is otherwise
 */
char *ExpandDatatypePrefix(char *str)
{
	StringInfoData buf;
	const char *xsd_prefix = "xsd:";
	char *stripped_str = str;
	size_t len;

	elog(DEBUG3, "%s called: str='%s'", __func__, str);

	if (!str || strlen(str) == 0)
		return ""; /* Empty input returns empty string */

	len = strlen(str);
	/* Strip < > if present */
	if (str[0] == '<' && str[len - 1] == '>')
	{
		stripped_str = palloc(len - 1); /* allocate space for stripped string (len - 2 + null terminator) */
		strncpy(stripped_str, str + 1, len - 2);
		stripped_str[len - 2] = '\0'; /* NULL-terminate */
	}

	/* Check for 'xsd:' prefix and expand it */
	if (strncmp(stripped_str, xsd_prefix, strlen(xsd_prefix)) == 0 && strlen(stripped_str) > strlen(xsd_prefix))
	{
		const char *suffix = stripped_str + strlen(xsd_prefix); /* get part after "xsd:" */
		initStringInfo(&buf);
		appendStringInfoChar(&buf, '<');	   /* open bracket */
		appendStringInfoString(&buf, RDF_XSD_BASE_URI); /* add XSD URI */
		appendStringInfoString(&buf, suffix);  /* add suffix */
		appendStringInfoChar(&buf, '>');	   /* close bracket */

		if (stripped_str != str)
			pfree(stripped_str);

		elog(DEBUG3, "%s exit: returning '%s'", __func__, buf.data);

		return buf.data;
	}

	/* return stripped string (or original if no stripping) without < > */
	if (stripped_str != str)
	{
		initStringInfo(&buf);
		appendStringInfoString(&buf, stripped_str);
		pfree(stripped_str);

		elog(DEBUG3, "%s exit: returning '%s'", __func__, buf.data);

		return buf.data;
	}

	elog(DEBUG3, "%s exit: returning '%s'", __func__, str);

	return str;
}

/*
 * MapSPARQLDatatype
 * -----------------
 * Maps PostgreSQL type OIDs to their corresponding XSD datatype strings.
 */
char *MapSPARQLDatatype(Oid pgtype)
{
	elog(DEBUG3, "%s called: input='%u'", __func__, pgtype);

	for (int i = 0; type_map[i].type_oid != InvalidOid; i++)
	{
		if (pgtype == type_map[i].type_oid)
		{
			elog(DEBUG3, "%s exit: returning => '%s'", __func__, (char *)type_map[i].xsd_datatype);
			return (char *)type_map[i].xsd_datatype;
		}
	}

	elog(DEBUG3, "%s exit: returning NULL (unsupported type)", __func__);
	return NULL;
}

#if PG_VERSION_NUM < 130000
void pg_unicode_to_server(pg_wchar c, unsigned char *utf8)
{
	unsigned char utf8buf[8]; /* Large enough for UTF-8 encoding */
	int len;
	unsigned char *converted;

	/* Convert Unicode code point to UTF-8 */
	if (unicode_to_utf8(c, utf8buf) == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_CHARACTER_NOT_IN_REPERTOIRE),
				 errmsg("invalid Unicode code point: 0x%04x", c)));

	len = pg_utf_mblen(utf8buf); /* Get the length of the encoded UTF-8 character */

	if (GetDatabaseEncoding() == PG_UTF8)
	{
		memcpy(utf8, utf8buf, len);
	}
	else
	{
		converted = pg_do_encoding_conversion(utf8buf, len,
											  PG_UTF8, GetDatabaseEncoding());

		if (converted == NULL)
			ereport(ERROR,
					(errcode(ERRCODE_CHARACTER_NOT_IN_REPERTOIRE),
					 errmsg("Unicode character 0x%04x cannot be converted to server encoding \"%s\"",
							c, GetDatabaseEncodingName())));

		memcpy(utf8, converted, strlen((const char *)converted));
	}

	utf8[len] = '\0'; /* Null-terminate (safe if utf8 has size ≥ 5) */
}
#endif

char *unescape_unicode(const char *input)
{
	StringInfoData buf;
	initStringInfo(&buf);

	elog(DEBUG2, "%s: Input='%s'", __func__, input);

	for (const char *p = input; *p;)
	{
		if (p[0] == '\\' && p[1] == 'u')
		{
			/* \uXXXX (exactly 4 hex digits) */
			if (p[2] && p[3] && p[4] && p[5] &&
				isxdigit(p[2]) && isxdigit(p[3]) && isxdigit(p[4]) && isxdigit(p[5]) &&
				(!p[6] || !isxdigit(p[6])))
			{
				uint16_t codeunit;
				char hex[5];
				unsigned char utf8[5];
				int len;

				memcpy(hex, p + 2, 4);
				hex[4] = '\0';
				sscanf(hex, "%hx", &codeunit);
				elog(DEBUG2, "%s: Parsed \\u%s to codeunit U+%04X", __func__, hex, codeunit);

				/* Check for high surrogate */
				if (codeunit >= 0xD800 && codeunit <= 0xDBFF &&
					p[6] == '\\' && p[7] == 'u' &&
					p[8] && p[9] && p[10] && p[11] &&
					isxdigit(p[8]) && isxdigit(p[9]) && isxdigit(p[10]) && isxdigit(p[11]) &&
					(!p[12] || !isxdigit(p[12])))
				{
					uint16_t low;
					char lowhex[5];
					uint32_t full;

					memcpy(lowhex, p + 8, 4);
					lowhex[4] = '\0';
					sscanf(lowhex, "%hx", &low);

					if (low >= 0xDC00 && low <= 0xDFFF)
					{
						full = 0x10000 + (((codeunit - 0xD800) << 10) | (low - 0xDC00));
						elog(DEBUG2, "%s: Surrogate pair U+%04X U+%04X -> U+%X", __func__, codeunit, low, full);
						memset(utf8, 0, sizeof(utf8));
						pg_unicode_to_server(full, (unsigned char *)utf8);
						len = pg_utf_mblen((const unsigned char *)utf8);
						appendBinaryStringInfo(&buf, (const char *)utf8, len);
						p += 12;
						continue;
					}
				}

				if (codeunit >= 0xD800 && codeunit <= 0xDFFF)
				{
					elog(DEBUG2, "%s: Lone surrogate U+%04X -> U+FFFD", __func__, codeunit);
					pg_unicode_to_server(0xFFFD, (unsigned char *)utf8);
					len = pg_utf_mblen(utf8);
					appendBinaryStringInfo(&buf, (const char *)utf8, len);
					p += 6;
					continue;
				}

				memset(utf8, 0, sizeof(utf8));
				pg_unicode_to_server(codeunit, (unsigned char *)utf8);
				len = pg_utf_mblen(utf8);
				appendBinaryStringInfo(&buf, (const char *)utf8, len);
				p += 6;
				continue;
			}
			else
			{
				elog(DEBUG2, "%s: Invalid \\u sequence at '%s' -> literal", __func__, p);
				appendStringInfoString(&buf, "\\u");
				p += 2;
				for (int i = 0; i < 4 && p[0] && isxdigit(p[0]); i++)
					appendStringInfoChar(&buf, *p++);
				continue;
			}
		}
		else if (p[0] == '\\' && p[1] == 'U')
		{
			/* \UXXXXXXXX (exactly 8 hex digits) */
			if (p[2] && p[3] && p[4] && p[5] && p[6] && p[7] && p[8] && p[9] &&
				isxdigit(p[2]) && isxdigit(p[3]) && isxdigit(p[4]) && isxdigit(p[5]) &&
				isxdigit(p[6]) && isxdigit(p[7]) && isxdigit(p[8]) && isxdigit(p[9]) &&
				(!p[10] || !isxdigit(p[10])))
			{
				char hex[9];
				uint32_t codepoint;
				unsigned char utf8[5];
				int len;

				memcpy(hex, p + 2, 8);
				hex[8] = '\0';
				sscanf(hex, "%x", &codepoint);
				elog(DEBUG2, "%s: Parsed \\U%s to codepoint U+%X", __func__, hex, codepoint);

				if (codepoint > 0x10FFFF || (codepoint >= 0xD800 && codepoint <= 0xDFFF))
				{
					elog(DEBUG2, "%s: Invalid codepoint U+%X -> U+FFFD", __func__, codepoint);
					codepoint = 0xFFFD;
				}

				memset(utf8, 0, sizeof(utf8));
				pg_unicode_to_server(codepoint, utf8);
				len = pg_utf_mblen(utf8);
				appendBinaryStringInfo(&buf, (const char *)utf8, len);
				p += 10;
				continue;
			}
			else
			{
				elog(DEBUG2, "%s: Invalid \\U sequence at '%s' -> literal", __func__, p);
				appendStringInfoString(&buf, "\\U");
				p += 2;
				for (int i = 0; i < 8 && p[0] && isxdigit(p[0]); i++)
					appendStringInfoChar(&buf, *p++);
				continue;
			}
		}
		else
		{
			/* Preserve all other characters, including \t, \n, \", etc. */
			appendStringInfoChar(&buf, *p++);
		}
	}

	elog(DEBUG2, "%s: Output='%s'", __func__, buf.data);
	return buf.data;
}

/*
 * IsFunctionPushable
 * ---------------
 * Check if a PostgreSQL function can be pushed down.
 *
 * funcname: name of the PostgreSQL function
 *
 * returns true if the function can be pushed down or false otherwise
 */
bool IsFunctionPushable(char *funcname)
{
	bool result;

	elog(DEBUG3, "%s called: funcname='%s'", __func__, funcname);

	result = strcmp(funcname, "abs") == 0 ||
			 strcmp(funcname, "ceil") == 0 ||
			 strcmp(funcname, "floor") == 0 ||
			 strcmp(funcname, "round") == 0 ||
			 strcmp(funcname, "upper") == 0 ||
			 strcmp(funcname, "lower") == 0 ||
			 strcmp(funcname, "length") == 0 ||
			 strcmp(funcname, "md5") == 0 ||
			 strcmp(funcname, "starts_with") == 0 ||
			 strcmp(funcname, "strstarts") == 0 ||
			 strcmp(funcname, "strends") == 0 ||
			 strcmp(funcname, "strbefore") == 0 ||
			 strcmp(funcname, "strafter") == 0 ||
			 strcmp(funcname, "strlang") == 0 ||
			 strcmp(funcname, "langmatches") == 0 ||
			 strcmp(funcname, "strdt") == 0 ||
			 strcmp(funcname, "str") == 0 ||
			 strcmp(funcname, "iri") == 0 ||
			 strcmp(funcname, "isiri") == 0 ||
			 strcmp(funcname, "lang") == 0 ||
			 strcmp(funcname, "datatype") == 0 ||
			 strcmp(funcname, "contains") == 0 ||
			 strcmp(funcname, "extract") == 0 ||
			 strcmp(funcname, "encode_for_uri") == 0 ||
			 strcmp(funcname, "isblank") == 0 ||
			 strcmp(funcname, "isnumeric") == 0 ||
			 strcmp(funcname, "isliteral") == 0 ||
			 strcmp(funcname, "bnode") == 0 ||
			 strcmp(funcname, "lcase") == 0 ||
			 strcmp(funcname, "ucase") == 0 ||
			 strcmp(funcname, "strlen") == 0 ||
			 strcmp(funcname, "substr") == 0 ||
			 strcmp(funcname, "concat") == 0 ||
			 strcmp(funcname, "replace") == 0 ||
			 strcmp(funcname, "regex") == 0 ||
			 strcmp(funcname, "year") == 0 ||
			 strcmp(funcname, "month") == 0 ||
			 strcmp(funcname, "day") == 0 ||
			 strcmp(funcname, "hours") == 0 ||
			 strcmp(funcname, "minutes") == 0 ||
			 strcmp(funcname, "seconds") == 0 ||
			 strcmp(funcname, "timezone") == 0 ||
			 strcmp(funcname, "tz") == 0 ||
			 strcmp(funcname, "bound") == 0 ||
			 strcmp(funcname, "sameterm") == 0 ||
			 strcmp(funcname, "coalesce") == 0 ||
			 strcmp(funcname, "substring") == 0 ||
			 strcmp(funcname, "rdfnode_to_time") == 0 ||
			 strcmp(funcname, "rdfnode_to_timetz") == 0 ||
			 strcmp(funcname, "rdfnode_to_timestamp") == 0 ||
			 strcmp(funcname, "rdfnode_to_timestamptz") == 0 ||
			 strcmp(funcname, "rdfnode_to_boolean") == 0 ||
			 strcmp(funcname, "boolean_to_rdfnode") == 0;

	elog(DEBUG3, "%s exit: returning '%s'", __func__, !result ? "false" : "true");

	return result;
}


/*
 * IsRDFStringLiteral
 * ------------------
 *
 * Checks if an RDF term is a string literal (simple, xsd:string, or language-tagged).
 * Follows SPARQL 1.1 requirements for string literal inputs (e.g., LCASE, UCASE).
 * Returns 1 for valid string literals, 0 otherwise. Logs unexpected datatypes for
 * debugging, as derived string types (e.g., xsd:token) may appear in some datasets.
 *
 * str_datatype: Null-terminated C string from datatype() (e.g., "", "http://www.w3.org/2001/XMLSchema#string")
 * str_language: Null-terminated C string from lang() (e.g., "", "en")
 */
bool IsRDFStringLiteral(char *str)
{
	elog(DEBUG3, "%s called: str='%s'", __func__, str);

	if (str == NULL)
	{
		elog(DEBUG3, "%s exit: returning 'false' (NULL argument)", __func__);
		return false;
	}

	if (strcmp(str, "") == 0 ||
		strcmp(str, RDF_SIMPLE_LITERAL_DATATYPE) == 0 ||
		strcmp(str, RDF_LANGUAGE_LITERAL_DATATYPE) == 0)
	{
		elog(DEBUG3, "%s exit: returning 'true'", __func__);
		return true;
	}

	elog(DEBUG3, "%s exit: returning 'false' (unsupported datatype '%s')", __func__, str);
	return false;
}


/*
 * CreateRegexString
 * ---------------
 * Escapes regex wildcards into normal characters by adding \\ to them
 *
 * str: string to be converted
 *
 * returns str with the regex wildcards escaped.
 */
char *CreateRegexString(char *str)
{
	StringInfoData res;
	initStringInfo(&res);

	elog(DEBUG3, "%s called: str='%s'", __func__, str);

	if (!str)
		return NULL;

	for (int i = 0; str[i] != '\0'; i++)
	{
		char c = str[i];

		if (i == 0 && c != '%' && c != '_' && c != '^')
			appendStringInfo(&res, "^");

		if (strchr("/:=#@^()[]{}+-*$.?|", c) != NULL)
			appendStringInfo(&res, "\\\\%c", c);
		else if (c == '%')
			appendStringInfo(&res, ".*");
		else if (c == '_')
			appendStringInfo(&res, ".");
		else if (c == '"')
			appendStringInfo(&res, "\\\"");
		else
			appendStringInfo(&res, "%c", c);

		if (i == strlen(str) - 1 && c != '%' && c != '_')
			appendStringInfo(&res, "$");

		elog(DEBUG2, "%s loop => %c res => %s", __func__, str[i], NameStr(res));
	}

	elog(DEBUG3, "%s exit: returning '%s'", __func__, NameStr(res));

	return NameStr(res);
}

/*
 * FormatSQLExtractField
 * ---------------
 * The fields "years", "months" and "days" (plural) and "hour", "minute",
 * "second" (singular) are note supported in SPARQL, but PostgreSQL can
 * handle both. So here we convert the parameters to a form that correspond
 * to a SPARQL function.
 *
 * field: EXTRACT or DATE_PART field parameter
 *
 * returns formated field parameter (uppercase)
 */
char *FormatSQLExtractField(char *field)
{
	char *res;

	elog(DEBUG3, "%s called: field='%s'", __func__, field);

	if (strcasecmp(field, "year") == 0 || strcasecmp(field, "years") == 0)
		res = "YEAR";
	else if (strcasecmp(field, "month") == 0 || strcasecmp(field, "months") == 0)
		res = "MONTH";
	else if (strcasecmp(field, "day") == 0 || strcasecmp(field, "days") == 0)
		res = "DAY";
	else if (strcasecmp(field, "hour") == 0 || strcasecmp(field, "hours") == 0)
		res = "HOURS";
	else if (strcasecmp(field, "minute") == 0 || strcasecmp(field, "minutes") == 0)
		res = "MINUTES";
	else if (strcasecmp(field, "second") == 0 || strcasecmp(field, "seconds") == 0)
		res = "SECONDS";
	else
	{
		elog(DEBUG3, "%s exit: returning NULL (field unknown)", __func__);
		return NULL;
	}

	elog(DEBUG3, "%s exit: returning '%s'", __func__, res);
	return res;
}

/*
 * ConstToCString
 * -----------------
 * Extracts a string from a Const
 *
 * returns a palloc'ed copy.
 */
char *ConstToCString(Const *constant)
{
	if (constant->constisnull)
		return NULL;
	else
		return text_to_cstring(DatumGetTextP(constant->constvalue));
}

/*
 * CStringToConst
 * -----------------
 * Extracts a Const from a char*
 *
 * returns Const from given string.
 */
Const *CStringToConst(const char *str)
{
	if (str == NULL)
		return makeNullConst(TEXTOID, -1, InvalidOid);
	else
		return makeConst(TEXTOID, -1, InvalidOid, -1, PointerGetDatum(cstring_to_text(str)), false, false);
}


char *rdfnode_to_cstring(rdfnode *node)
{
	/* Get a pointer to the actual data and its length */
	char *data = VARDATA_ANY(node);
	int len = VARSIZE_ANY_EXHDR(node);

	/* Allocate a null-terminated C string */
	char *result = palloc(len + 1);
	memcpy(result, data, len);
	result[len] = '\0';

	return result;
}

/*
 * IsStringDataType
 * ---------------
 * Determines if a PostgreSQL data type is string or numeric type
 * so that we can know when to wrap the value with single quotes
 * or leave it as-is.
 *
 * type: PostgreSQL data type
 *
 * returns true if the data type needs to be wrapped with quotes
 *         or false otherwise.
 */
bool IsStringDataType(Oid type)
{
	bool result;

	if (type == RDFNODEOID)
		elog(DEBUG3, "%s called: type='(RDFNODEOID)'", __func__);
	else
		elog(DEBUG3, "%s called: type='%u'", __func__, type);

	result = type == TEXTOID ||
			 type == VARCHAROID ||
			 type == CHAROID ||
			 type == NAMEOID ||
			 type == DATEOID ||
			 type == TIMESTAMPOID ||
			 type == TIMESTAMPTZOID ||
			 type == NAMEOID ||
			 type == RDFNODEOID;

	elog(DEBUG3, "%s exit: returning '%s'", __func__, !result ? "false" : "true");
	return result;
}

bool is_valid_xsd_double(const char *lexical)
{
	regex_t regex;
	int reti;
	bool is_valid = false;
	const char *pattern = "^[-+]?[0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?$";

	if (pg_strcasecmp(lexical, "NaN") == 0 || pg_strcasecmp(lexical, "INF") == 0 || pg_strcasecmp(lexical, "-INF") == 0)
		return true;

	reti = regcomp(&regex, pattern, REG_EXTENDED);

	if (reti)
		ereport(ERROR, (errmsg("could not compile regex for xsd:double")));

	reti = regexec(&regex, lexical, 0, NULL, 0);

	if (reti == 0)
		is_valid = true;

	regfree(&regex);
	return is_valid;
}

bool is_valid_xsd_int(const char *lexical)
{
	regex_t regex;
	int reti;
	bool is_valid = false;
	const char *pattern = "^-?[0-9]+$";

	reti = regcomp(&regex, pattern, REG_EXTENDED);

	if (reti)
		ereport(ERROR, (errmsg("could not compile regex for xsd:int")));

	reti = regexec(&regex, lexical, 0, NULL, 0);
	if (reti == 0)
		is_valid = true;

	regfree(&regex);
	return is_valid;
}

bool is_valid_xsd_dateTime(const char *lexical)
{
	const char *p = lexical;
	int i;

	if (!lexical)
		return false;

	/* Parse year (4 digits) */
	for (i = 0; i < 4; i++)
	{
		if (!isdigit((unsigned char)*p))
			return false;
		p++;
	}

	/* Expect '-' */
	if (*p != '-')
		return false;
	p++;

	/* Parse month (2 digits) */
	for (i = 0; i < 2; i++)
	{
		if (!isdigit((unsigned char)*p))
			return false;
		p++;
	}

	/* Expect '-' */
	if (*p != '-')
		return false;
	p++;

	/* Parse day (2 digits) */
	for (i = 0; i < 2; i++)
	{
		if (!isdigit((unsigned char)*p))
			return false;
		p++;
	}

	/* Expect 'T' */
	if (*p != 'T')
		return false;
	p++;

	/* Parse hour (2 digits) */
	for (i = 0; i < 2; i++)
	{
		if (!isdigit((unsigned char)*p))
			return false;
		p++;
	}

	/* Expect ':' */
	if (*p != ':')
		return false;
	p++;

	/* Parse minute (2 digits) */
	for (i = 0; i < 2; i++)
	{
		if (!isdigit((unsigned char)*p))
			return false;
		p++;
	}

	/* Expect ':' */
	if (*p != ':')
		return false;
	p++;

	/* Parse second (2 digits) */
	for (i = 0; i < 2; i++)
	{
		if (!isdigit((unsigned char)*p))
			return false;
		p++;
	}

	/* Optional: fractional seconds */
	if (*p == '.')
	{
		p++;
		/* Must have at least one digit after decimal point */
		if (!isdigit((unsigned char)*p))
			return false;
		/* Continue reading all fractional digits */
		while (isdigit((unsigned char)*p))
			p++;
	}

	/* Optional: timezone */
	if (*p == 'Z')
	{
		p++;
	}
	else if (*p == '+' || *p == '-')
	{
		p++;
		/* Timezone hour (2 digits) */
		for (i = 0; i < 2; i++)
		{
			if (!isdigit((unsigned char)*p))
				return false;
			p++;
		}
		/* Expect ':' */
		if (*p != ':')
			return false;
		p++;
		/* Timezone minute (2 digits) */
		for (i = 0; i < 2; i++)
		{
			if (!isdigit((unsigned char)*p))
				return false;
			p++;
		}
	}

	/* Must be at end of string */
	if (*p != '\0')
		return false;

	return true;
}

bool is_valid_xsd_time(const char *lexical)
{
	regex_t regex;
	int reti;
	bool is_valid = false;
	const char *pattern = "^([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]+)?([+-][0-9]{2}:[0-9]{2}|Z)?$";

	reti = regcomp(&regex, pattern, REG_EXTENDED);

	if (reti)
		ereport(ERROR, (errmsg("could not compile regex for xsd:time")));

	reti = regexec(&regex, lexical, 0, NULL, 0);

	if (reti == 0)
		is_valid = true;

	regfree(&regex);
	return is_valid;
}

bool is_valid_xsd_date(const char *lexical)
{
	regex_t regex;
	int reti;
	bool is_valid = false;
	const char *pattern = "^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])([+-][0-9]{2}:[0-9]{2}|Z)?$";

	reti = regcomp(&regex, pattern, REG_EXTENDED);

	if (reti)
		ereport(ERROR, (errmsg("could not compile regex for xsd:date")));

	reti = regexec(&regex, lexical, 0, NULL, 0);

	if (reti == 0)
		is_valid = true;

	regfree(&regex);
	return is_valid;
}

/*
 * IsSPARQLVariableValid
 * ---------------
 * A query variable is marked by the use of either "?" or "$"; the "?" or
 * "$" is not part of the variable name. Valid characters for the name
 * are [a-z], [A-Z], [0-9]
 *
 * str: string to be evaluated
 *
 * returns true if the variable is valid or false otherwise
 */
bool IsSPARQLVariableValid(const char *str)
{
	elog(DEBUG3, "%s called: str='%s'", __func__, str);

	if (str[0] != '?' && str[0] != '$')
	{
		elog(DEBUG3, "%s exit: returning 'false' (str does not start with '?' or '$')", __func__);
		return false;
	}

	for (int i = 1; str[i] != '\0'; i++)
		if (!isalnum(str[i]) && str[i] != '_')
		{
			elog(DEBUG3, "%s exit: returning 'false' (invalid variable name)", __func__);
			return false;
		}

	elog(DEBUG3, "%s exit: returning 'true'", __func__);
	return true;
}

/*
 * IsSPARQLParsable
 * ------------------
 * Checks if a SPARQL query can be parsed and modified to accommodate possible
 * pusdhown instructions. If it returns false it does not mean that the query
 * is invalid. It just means that it contains unsupported clauses and it cannot
 * be modifed.
 *
 * state: SPARQL, SERVER and FOREIGN TABLE info
 *
 * returns 'true' if the SPARQL query is safe to be parsed or 'false' otherwise
 */
bool IsSPARQLParsable(struct RDFfdwState *state)
{
	int keyword_count = 0;
	bool result;
	elog(DEBUG3, "%s called", __func__);
	/*
	 * SPARQL Queries containing SUB SELECTS are not supported. So, if any number
	 * other than 1 is returned from LocateKeyword, this query cannot be parsed.
	 */
	LocateKeyword(state->raw_sparql, "{\n\t> ", RDF_SPARQL_KEYWORD_SELECT, " *?\n\t", &keyword_count, 0);

	elog(DEBUG2, "%s: SPARQL contains '%d' SELECT clauses.", __func__, keyword_count);

	result = LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_GROUPBY, " \n\t?", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_ORDERBY, " \n\t?DA", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_LIMIT, " \n\t", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_MINUS, " \n\t{", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_UNION, " \n\t{", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(state->raw_sparql, " \n\t", RDF_SPARQL_KEYWORD_HAVING, " \n\t(", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 keyword_count == 1;

	elog(DEBUG3, "%s exit: returning '%s'", __func__, !result ? "false" : "true");
	return result;
}

/*
 * IsExpressionPushable
 * ------------
 * Checks if an expression attached to a column can be pushed down, in case it
 * is used in a condition in the SQL WHERE clause.
 *
 * state: SPARQL, SERVER and FOREIGN TABLE info
 *
 * returns 'true' if the expression can be pushed down or 'false' otherwise
 */
bool IsExpressionPushable(char *expression)
{
	char *open = " \n(";
	char *close = " \n(";
	bool result;

	elog(DEBUG3, "%s called: expression='%s'", __func__, expression);

	result = LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_COUNT, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_SUM, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_AVG, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_MIN, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_MAX, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_SAMPLE, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_GROUPCONCAT, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND;

	elog(DEBUG3, "%s exit: returning '%s'", __func__, !result ? "false" : "true");
	return result;
}

/*
 * LocateKeyword
 * -----------
 * This function locates the first occurrence of given 'keyword' within 'str'. The keywords
 * must be wrapped with one of the characters given in 'start_chars' and end_chars'. If
 * the parameter '*count' is used, this function will be called recursively to count how
 * many times the searched 'keyword' can be found in 'str'
 *
 * str             : string where 'keyword' will be searched
 * start_chars     : all possible chars that can preceed the searched 'keyword'
 * keyword         : the searched keyword (case insensitive)
 * end_chars       : all possible chars that can be found after the 'keyword'
 * count           : how many times 'keyword' was found in 'str' (nullable)
 * start_position  : position in 'str' where the function has to start looking for
 *                   'keyword'. Set it to '0' if the whole 'str' must be considered.
 *
 * returns         : position where 'keyword' was found, or RDF_KEYWORD_NOT_FOUND otherwise.
 */
int LocateKeyword(char *str, char *start_chars, char *keyword, char *end_chars, int *count, int start_position)
{
	int keyword_position = RDF_KEYWORD_NOT_FOUND;
	StringInfoData idt;
	initStringInfo(&idt);

	if (count)
	{
		for (size_t i = 0; i < *count; i++)
		{
			appendStringInfo(&idt, "  ");
		}

		if (*count > 0)
			appendStringInfo(&idt, "├─ ");
	}

	elog(DEBUG2, "%s%s called: searching '%s' in start_position %d", NameStr(idt), __func__, keyword, start_position);

	if (start_position < 0)
		elog(ERROR, "%s%s: start_position cannot be negative.", NameStr(idt), __func__);

	/*
	 * Some SPARQL keywords can be placed in the very beginning of a query, so they not always
	 * have a preceeding character. So here we first check if the searched keyword exists
	 * in the beginning of the string.
	 */
	if (((strcasecmp(keyword, RDF_SPARQL_KEYWORD_SELECT) == 0 && strncasecmp(str, RDF_SPARQL_KEYWORD_SELECT, strlen(RDF_SPARQL_KEYWORD_SELECT)) == 0) ||
		 (strcasecmp(keyword, RDF_SPARQL_KEYWORD_PREFIX) == 0 && strncasecmp(str, RDF_SPARQL_KEYWORD_PREFIX, strlen(RDF_SPARQL_KEYWORD_PREFIX)) == 0) ||
		 (strcasecmp(keyword, RDF_SPARQL_KEYWORD_DESCRIBE) == 0 && strncasecmp(str, RDF_SPARQL_KEYWORD_DESCRIBE, strlen(RDF_SPARQL_KEYWORD_DESCRIBE)) == 0)) &&
		start_position == 0)
	{
		elog(DEBUG2, "%s%s: nothing before SELECT. Setting keyword_position to 0.", NameStr(idt), __func__);
		keyword_position = 0;
	}
	else
	{

		for (int i = 0; i < strlen(start_chars); i++)
		{

			for (int j = 0; j < strlen(end_chars); j++)
			{
				char *el;
				StringInfoData eval_token;
				initStringInfo(&eval_token);

				appendStringInfo(&eval_token, "%c%s%c", start_chars[i], keyword, end_chars[j]);

				el = strcasestr(str + start_position, eval_token.data);

				if (el != NULL)
				{
					int nquotes = 0;

					for (int k = 0; k <= (el - str); k++)
					{
						if (str[k] == '\"')
							nquotes++;
					}

					/*
					 * If the keyword is located after an opening double-quote it is a literal and should
					 * not be considered as a keyword.
					 */
					if (nquotes % 2 != 1)
						keyword_position = el - str;

					if (keyword_position != RDF_KEYWORD_NOT_FOUND)
						break;
				}
			}
		}
	}

	if ((count) && keyword_position != RDF_KEYWORD_NOT_FOUND)
	{
		(*count)++;
		elog(DEBUG2, "%s%s (%d): keyword '%s' found in position %d. Recalling %s ... ", NameStr(idt), __func__, *count, keyword, keyword_position, __func__);
		LocateKeyword(str, start_chars, keyword, end_chars, count, keyword_position + 1);

		elog(DEBUG2, "%s%s: '%s' search returning postition %d for start position %d", NameStr(idt), __func__, keyword, keyword_position, start_position);
	}

	elog(DEBUG2, "%s exit: returning '%d' (keyword_position)", __func__, keyword_position);
	return keyword_position;
}

/*
 * CheckURL
 * --------
 * CheckS if an URL is valid.
 *
 * url: URL to be validated.
 *
 * returns REQUEST_SUCCESS or REQUEST_FAIL
 */
int CheckURL(char *url)
{
	CURLUcode code;
	CURLU *handler = curl_url();

	elog(DEBUG3, "%s called: '%s'", __func__, url);

	code = curl_url_set(handler, CURLUPART_URL, url, 0);

	curl_url_cleanup(handler);

	elog(DEBUG2, "  %s handler return code: %u", __func__, code);

	if (code != 0)
	{
		elog(DEBUG2, "%s: invalid URL (%u) > '%s'", __func__, code, url);
		return code;
	}

	elog(DEBUG3, "%s exit: returning '%d' (REQUEST_SUCCESS)", __func__, REQUEST_SUCCESS);
	return REQUEST_SUCCESS;
}

/*
 * ValidateSPARQLUpdatePattern
 * ----------------------------
 *
 * Validates the sparql_update_pattern to ensure it is suitable
 * for INSERT operations:
 * 1. Contains at least one valid triple pattern (subject, predicate,
 *    and object)
 * 2. All SPARQL variables have corresponding table columns with
 *    matching variable options
 *
 * This prevents empty or invalid patterns from generating malformed
 * SPARQL UPDATE statements.
 *
 * Throws an ERROR if:
 * - The pattern is empty or contains no valid triple patterns
 * - A variable in the pattern has no matching column
 */
void ValidateSPARQLUpdatePattern(RDFfdwState *state)
{
	const char *pos;
	const char *pattern = state->sparql_update_pattern;
	bool has_triple = false;

	/* Check for at least one valid triple pattern (must have at least 3 components) */
	{
		const char *p = pattern;
		int component_count = 0;
		bool in_uri = false;
		bool in_literal = false;
		bool in_var = false;

		while (*p)
		{
			/* Skip whitespace between components */
			if (isspace((unsigned char)*p))
			{
				if (in_var)
				{
					component_count++;
					in_var = false;
				}
				p++;
				continue;
			}

			/* Handle URIs <...> */
			if (*p == '<')
			{
				in_uri = true;
				p++;
				continue;
			}
			if (in_uri && *p == '>')
			{
				in_uri = false;
				component_count++;
				p++;
				continue;
			}
			if (in_uri)
			{
				p++;
				continue;
			}

			/* Handle literals "..." */
			if (*p == '"' && !in_literal)
			{
				in_literal = true;
				p++;
				continue;
			}
			if (*p == '"' && in_literal && (p == pattern || *(p - 1) != '\\'))
			{
				in_literal = false;
				component_count++;
				/* Skip language tags or datatypes */
				p++;
				if (*p == '@' || (*p == '^' && *(p + 1) == '^'))
				{
					while (*p && !isspace((unsigned char)*p) && *p != '.')
						p++;
				}
				continue;
			}
			if (in_literal)
			{
				p++;
				continue;
			}

			/* Handle variables ?var or $var */
			if ((*p == '?' || *p == '$') && !in_var)
			{
				in_var = true;
				p++;
				continue;
			}
			if (in_var)
			{
				if (!isalnum((unsigned char)*p) && *p != '_')
				{
					component_count++;
					in_var = false;
					/* Don't increment p, re-process this character */
					continue;
				}
				p++;
				continue;
			}

			/* Handle triple terminator */
			if (*p == '.')
			{
				if (in_var)
				{
					component_count++;
					in_var = false;
				}
				if (component_count >= 3)
				{
					has_triple = true;
					break;
				}
				/* Reset for next potential triple */
				component_count = 0;
				p++;
				continue;
			}

			/* Other characters (bare words, prefixed names like ex:Thing) */
			if (isalnum((unsigned char)*p) || *p == ':' || *p == '_')
			{
				/* Scan to end of token */
				while (*p && (isalnum((unsigned char)*p) || *p == ':' || *p == '_' || *p == '-'))
					p++;
				component_count++;
				continue;
			}

			/* Unknown character, skip */
			p++;
		}

		/* Check if we ended with a variable */
		if (in_var)
			component_count++;

		/* Final check: did we accumulate at least 3 components? */
		if (component_count >= 3)
			has_triple = true;
	}

	if (!has_triple)
	{
		ereport(ERROR,
				(errcode(ERRCODE_FDW_UNABLE_TO_CREATE_EXECUTION),
				 errmsg("'%s' contains no valid triple patterns",
						RDF_TABLE_OPTION_SPARQL_UPDATE_PATTERN),
				 errhint("A triple pattern requires at least three components (subject, predicate, object), e.g., '?s ?p ?o .'")));
	}

	/* Check that all variables in template have corresponding columns */
	pos = pattern;
	while ((pos = strchr(pos, '?')) != NULL)
	{
		StringInfoData var_name;
		bool found = false;
		int j = 0;

		/* Extract variable name (alphanumeric after ?) */
		initStringInfo(&var_name);
		pos++; /* Skip the ? */
		while (isalnum((unsigned char)pos[j]) || pos[j] == '_')
		{
			appendStringInfoChar(&var_name, pos[j]);
			j++;
		}

		if (var_name.len > 0)
		{
			/* Check if a column maps to this variable */
			for (int k = 0; k < state->numcols; k++)
			{
				if (state->rdfTable->cols[k]->sparqlvar)
				{
					/* Build the full variable name with ? prefix for comparison */
					StringInfoData full_var;
					initStringInfo(&full_var);
					appendStringInfoString(&full_var, "?");
					appendStringInfoString(&full_var, var_name.data);

					if (strcmp(state->rdfTable->cols[k]->sparqlvar, full_var.data) == 0)
					{
						found = true;
						pfree(full_var.data);
						break;
					}
					pfree(full_var.data);
				}
			}

			/* Report error immediately if variable not found */
			if (!found)
			{
				ereport(ERROR,
						(errcode(ERRCODE_FDW_UNABLE_TO_CREATE_EXECUTION),
						 errmsg("SPARQL variable '?%s' in '%s' is not mapped to any table column",
								var_name.data, RDF_TABLE_OPTION_SPARQL_UPDATE_PATTERN)));
			}
		}

		pfree(var_name.data);
		pos += j;
	}
}

/*
 * str_replace
 * -----------
 * Replace all occurrences of 'search' with 'replace' in 'source'.
 * Returns a newly allocated string.
 *
 * source  : the original string
 * search  : the substring to search for
 * replace : the replacement string
 *
 * returns a new string with replacements made
 */
char *str_replace(const char *source, const char *search, const char *replace)
{
	StringInfoData result;
	const char *pos = source;
	const char *found;
	size_t search_len = strlen(search);
	size_t replace_len = strlen(replace);

	initStringInfo(&result);

	while ((found = strstr(pos, search)) != NULL)
	{
		/* Append everything before the match */
		appendBinaryStringInfo(&result, pos, found - pos);

		/* Append the replacement */
		appendBinaryStringInfo(&result, replace, replace_len);

		/* Move past the match */
		pos = found + search_len;
	}

	/* Append any remaining text */
	appendStringInfoString(&result, pos);

	return result.data;
}
/*
 * EscapeSPARQLLiteral
 * -------------------
 *
 * Escapes special characters in an RDF literal for use in SPARQL UPDATE operations.
 * Handles newlines, carriage returns, and tabs that are stored as actual bytes in
 * PostgreSQL but must be represented as escape sequences in SPARQL.
 *
 * This function is specifically for INSERT/DELETE operations where the rdfnode
 * output may contain actual newline bytes (0x0A) that need to be converted to
 * the SPARQL escape sequence "\n".
 *
 * input: RDF literal string (e.g., "Line1\nLine2"@en where \n is byte 0x0A)
 *
 * returns: SPARQL-safe literal (e.g., "Line1\\nLine2"@en where \\n is two chars)
 */
char *EscapeSPARQLLiteral(const char *input)
{
StringInfoData result;
const char *ptr;
const char *closing_quote = NULL;
const char *lang_or_type = NULL;

if (!input || strlen(input) == 0)
return (char *)input;

/* Check if this is an IRI - no escaping needed */
if (input[0] == '<')
return (char *)input;

/* Check if this is a quoted literal */
if (input[0] != '"')
return (char *)input;

initStringInfo(&result);

/* Find the closing quote (not preceded by backslash) */
ptr = input + 1; /* skip opening quote */
while (*ptr != '\0')
{
if (*ptr == '"' && (ptr == input + 1 || *(ptr - 1) != '\\'))
{
closing_quote = ptr;
/* Check what follows the closing quote */
if (ptr[1] == '@' || (ptr[1] == '^' && ptr[2] == '^') || ptr[1] == '\0')
{
lang_or_type = ptr + 1; /* Point to @lang or ^^type or end of string */
break;
}
}
ptr++;
}

if (!closing_quote)
{
/* Malformed literal - return as-is */
return (char *)input;
}

/* Escape the content between quotes */
appendStringInfoChar(&result, '"'); /* opening quote */
ptr = input + 1; /* reset to start of content */

while (ptr < closing_quote)
{
switch (*ptr)
{
case '\n':
appendStringInfoString(&result, "\\n");
break;
case '\r':
appendStringInfoString(&result, "\\r");
break;
case '\t':
appendStringInfoString(&result, "\\t");
break;
default:
appendStringInfoChar(&result, *ptr);
break;
}
ptr++;
}

/* Add closing quote */
appendStringInfoChar(&result, '"');

/* Add language tag or datatype if present */
if (lang_or_type && *lang_or_type != '\0')
{
appendStringInfoString(&result, lang_or_type);
}

return result.data;
}
