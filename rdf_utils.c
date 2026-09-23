
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
	{InvalidOid, NULL}};

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
	Assert(str != NULL);

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

	Assert(lan != NULL);

	reti = regcomp(&regex, pattern, REG_EXTENDED);

	if (reti)
		ereport(ERROR,
			(errcode(ERRCODE_INTERNAL_ERROR),
			 errmsg("could not compile regex for language tag")));

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
	Assert(literal != NULL);

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

	Assert(literal1 != NULL);
	Assert(literal2 != NULL);

	elog(DEBUG3, "%s called: literal1='%s', literal2='%s'", __func__, literal1, literal2);

	if (isIRI(literal1) || isIRI(literal2) || isBlank(literal1) || isBlank(literal2))
		return false;

	lang1 = lang(literal1);
	lang2 = lang(literal2);
	dt1 = datatype(literal1);
	dt2 = datatype(literal2);

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
	if (strlen(lang1) > 0 && strlen(lang2) > 0 && pg_strcasecmp(lang1, lang2) == 0)
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
 * FindLiteralClosingQuote
 * -----------------------
 *
 * Given a string whose first character is '"', scans forward honoring
 * backslash-escape semantics (a backslash escapes exactly the character
 * that immediately follows it, so runs of backslashes are consumed two
 * at a time) and returns a pointer to the first *unescaped* '"' that
 * closes the literal, or NULL if the string ends before such a quote is
 * found.
 *
 * This deliberately replaces two previous ad-hoc heuristics (a substring
 * search for '@'/'^^' in cstring_to_rdfliteral(), and a single-character
 * lookbehind in EscapeSPARQLLiteral()) that could both be confused by a
 * lexical value containing a run of backslashes of the "wrong" parity,
 * causing a quote to be mis-classified as escaped/unescaped and letting
 * attacker-controlled content break out of the intended SPARQL string
 * literal once the value was serialized into a request. Walking forward
 * and consuming escape pairs as they're found is unambiguous regardless
 * of how many backslashes precede a quote.
 *
 * input: pointer to the opening '"' of a candidate literal
 *
 * returns: pointer to the matching closing '"', or NULL if none exists
 */
static const char *
FindLiteralClosingQuote(const char *input)
{
	const char *p = input + 1; /* skip opening quote */

	while (*p)
	{
		if (*p == '\\' && *(p + 1))
		{
			p += 2; /* skip the escaped character, whatever it is */
			continue;
		}
		if (*p == '"')
			return p; /* unescaped closing quote */
		p++;
	}

	return NULL;
}

/*
 * IsValidLiteralSuffix
 * ---------------------
 *
 * Validates that 'suffix' is either empty, or consists *entirely* of a
 * well-formed SPARQL/Turtle language tag ("@lang") or datatype
 * annotation ("^^prefix:name" or "^^<iri>"). Trailing bytes that don't
 * fit this grammar are rejected rather than being passed through
 * unexamined -- this is what closes off the trailing-content injection
 * vector where an attacker appends syntax after what looks like a
 * plausible "@lang" or "^^type" tag.
 *
 * suffix: pointer to the byte immediately following a literal's closing
 *         quote (may point to the string terminator)
 *
 * returns: true if 'suffix' is empty or a complete, valid tag/datatype
 *          with nothing left over; false otherwise
 */
static bool
IsValidLiteralSuffix(const char *suffix)
{
	const char *p = suffix;

	if (*p == '\0')
		return true; /* no suffix at all is fine */

	if (*p == '@')
	{
		p++;
		if (!isalpha((unsigned char) *p))
			return false;
		while (isalnum((unsigned char) *p) || *p == '-')
			p++;
		return (*p == '\0');
	}

	if (p[0] == '^' && p[1] == '^')
	{
		p += 2;
		if (*p == '<')
		{
			p++;
			while (*p && *p != '>' && *p != '<' && *p != '"' &&
				   *p != ' ' && *p != '\t' && *p != '\n' && *p != '\r')
				p++;
			return (*p == '>' && *(p + 1) == '\0');
		}
		else
		{
			if (!isalpha((unsigned char) *p) && *p != '_')
				return false;
			while (isalnum((unsigned char) *p) || *p == '_' ||
				   *p == ':' || *p == '-' || *p == '.')
				p++;
			return (*p == '\0');
		}
	}

	return false;
}

/*
 * AppendQuoteEscapedContent
 * --------------------------
 *
 * Appends [from, to) to buf, adding a backslash before any '"' that
 * isn't already protected by one, while leaving every other byte --
 * including any backslashes already present in the input -- completely
 * untouched. This preserves the original cstring_to_rdfliteral()
 * contract (raw content may already contain legitimate escape sequences
 * such as \", \n, \uXXXX that must survive unchanged; only unescaped
 * quotes need a new backslash), while fixing how "already protected" is
 * determined.
 */
static void
AppendQuoteEscapedContent(StringInfoData *buf, const char *from, const char *to)
{
	const char *p;

	for (p = from; p < to; p++)
	{
		if (*p == '"')
		{
			const char *q = p - 1;
			int			nbackslash = 0;

			while (q >= from && *q == '\\')
			{
				nbackslash++;
				q--;
			}

			/* Even count (including zero): not yet escaped -- add one. */
			if (nbackslash % 2 == 0)
				appendStringInfoChar(buf, '\\');
		}
		appendStringInfoChar(buf, *p);
	}
}

/*
 * QuoteRDFLiteral
 * ---------------
 *
 * Wraps lexical content in quotes to form a simple literal, escaping any
 * unescaped '"' and leaving every other byte as it stands -- content arriving
 * from lex() already carries RDF escape sequences such as \n or \uXXXX, and
 * re-escaping them would change the value.
 *
 * Content ending in an odd number of backslashes needs one more, or the last
 * of them would escape the closing quote and the literal would not terminate
 * where it appears to.
 *
 * input: lexical content, not an annotated term
 *
 * returns: a palloc'd simple literal
 */
char *QuoteRDFLiteral(const char *input)
{
	StringInfoData buf;
	const char *end = input + strlen(input);
	const char *p = end;

	Assert(input != NULL);

	initStringInfo(&buf);
	appendStringInfoChar(&buf, '"');
	AppendQuoteEscapedContent(&buf, input, end);

	while (p > input && *(p - 1) == '\\')
		p--;

	if ((end - p) % 2 != 0)
		appendStringInfoChar(&buf, '\\');

	appendStringInfoChar(&buf, '"');

	return buf.data;
}

/*
 * EscapeSPARQLStringContent
 * -------------------------
 *
 * Escapes a lexical value so that it can stand inside a SPARQL string
 * literal. SPARQL 1.1 rule [156] STRING_LITERAL2 excludes the double quote,
 * the backslash and the two line-break characters from the body of a literal,
 * and rule [160] ECHAR gives the escapes written here. The quotes themselves
 * are not added: the caller decides whether the result becomes a plain
 * literal, a language-tagged one or the argument of IRI().
 *
 * escape_backslash says whether the value carries escapes already. A native
 * PostgreSQL datum carries none -- a backslash in it is a backslash and a
 * quote is a quote, and both have to be written out -- while an rdfnode's
 * lexical form carries them, since rdfnode_in() escapes a quote and leaves a
 * sequence such as \n or \uXXXX as it was written. Escaping those a second
 * time would change the value. A raw line break is in neither form and is
 * escaped for both.
 *
 * This is why QuoteRDFLiteral() cannot serve here: it is written for the
 * second kind of input, so it leaves a backslash where it stands and escapes
 * only a quote that is not already protected, and it passes a raw line break
 * through into the middle of a literal, which no endpoint parses.
 *
 * str             : the lexical value
 * escape_backslash: true when the value carries no escapes of its own
 *
 * returns a palloc'd copy, ready to be wrapped in quotes
 */
char *
EscapeSPARQLStringContent(const char *str, bool escape_backslash)
{
	StringInfoData buf;
	const char *p;

	Assert(str != NULL);

	initStringInfo(&buf);

	for (p = str; *p; p++)
	{
		switch (*p)
		{
			case '\\':
				if (escape_backslash)
					appendStringInfoString(&buf, "\\\\");
				else
					appendStringInfoChar(&buf, *p);
				break;
			case '"':
				if (escape_backslash)
					appendStringInfoString(&buf, "\\\"");
				else
					appendStringInfoChar(&buf, *p);
				break;
			case '\n':
				appendStringInfoString(&buf, "\\n");
				break;
			case '\r':
				appendStringInfoString(&buf, "\\r");
				break;
			case '\t':
				appendStringInfoString(&buf, "\\t");
				break;
			default:
				appendStringInfoChar(&buf, *p);
				break;
		}
	}

	return buf.data;
}

/*
 * cstring_to_rdfliteral
 * ---------------------
 *
 * Converts a raw string input into a valid RDF literal by adding quotes and escaping
 * internal quotes as needed. If the input is already a complete, unambiguously
 * escaped RDF literal (i.e., quoted, with a well-formed language tag or datatype
 * suffix), it is returned unchanged.
 *
 * input: the raw string or partial literal to convert (e.g., "abc", "abc"@en, "ab\"c")
 *
 * returns: a palloc'd string representing the RDF literal (e.g., "\"abc\"",
 *          "\"ab\\\"c\""), or a palloc'd copy of the input if it already is a
 *          complete, validly-escaped literal.
 *
 * The result is always freshly allocated and owned by the caller. Returning
 * either the argument itself or a string constant used to be possible, and
 * callers that pfree() the buffer they passed in -- concat(), lcase(),
 * ucase(), substr() and strafter() all do -- then freed the value they were
 * about to return, or handed pfree() the address of a .rodata constant.
 */
char *cstring_to_rdfliteral(char *input)
{
	const char *start;
	const char *end;
	char *result;
	int len;

	elog(DEBUG3, "%s called: input='%s'", __func__, input);

	if (!input || strlen(input) == 0)
	{
		elog(DEBUG3, "%s exit: returning empty literal '\"\"'", __func__);
		return pstrdup("\"\""); /* empty input becomes empty literal */
	}

	start = input;
	len = strlen(start);

	/*
	 * Check if it's already a complete RDF literal. Several call
	 * sites (in particular rdfnode_in()'s own literal parser) rely
	 * on its existing, deliberately permissive behavior to let a later
	 * call to lang()/datatype() perform proper validation (e.g. to
	 * reject an empty language tag or a malformed datatype IRI) on
	 * whatever follows the quote -- tightening this check here would
	 * silently change those validation/error paths instead of fixing the
	 * actual bug, which is in the escaping loop below.
	 */
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
				/* complete literal with lang or type, return a copy */
				return pstrdup(input);
			}
		}
	}

	/*
	 * Not recognized as a complete literal: treat the *entire* input
	 * (including any leading/trailing quote bytes it happens to contain)
	 * as raw content and quote it from scratch.
	 */
	result = QuoteRDFLiteral(start);

	elog(DEBUG3, "%s exit: returning => '%s'", __func__, result);
	return result;
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
		appendStringInfoChar(&buf, '<');				/* open bracket */
		appendStringInfoString(&buf, RDF_XSD_BASE_URI); /* add XSD URI */
		appendStringInfoString(&buf, suffix);			/* add suffix */
		appendStringInfoChar(&buf, '>');				/* close bracket */

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
/*
 * MAX_UNICODE_EQUIVALENT_STRING arrived in PostgreSQL 13 together with
 * pg_unicode_to_server(), so it has to be supplied here for the older
 * releases the shim below exists for. The value is the one core uses: a
 * 4-byte UTF-8 character expanded by MAX_CONVERSION_GROWTH.
 */
#ifndef MAX_UNICODE_EQUIVALENT_STRING
#define MAX_UNICODE_EQUIVALENT_STRING 16
#endif

/*
 * Convert a single Unicode code point into a string in the server encoding.
 *
 * Compatibility shim for servers predating PostgreSQL 13, which did not
 * export pg_unicode_to_server().  It follows the same contract as the core
 * function: the caller must supply a buffer of at least
 * MAX_UNICODE_EQUIVALENT_STRING + 1 bytes, and the result is NUL-terminated.
 */
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
		int converted_len;

		converted = pg_do_encoding_conversion(utf8buf, len,
											  PG_UTF8, GetDatabaseEncoding());

		if (converted == NULL)
			ereport(ERROR,
					(errcode(ERRCODE_CHARACTER_NOT_IN_REPERTOIRE),
					 errmsg("Unicode character 0x%04x cannot be converted to server encoding \"%s\"",
							c, GetDatabaseEncodingName())));

		/*
		 * The converted string is in the server encoding and may well be
		 * longer than the UTF-8 form, so it must be measured on its own
		 * rather than reusing the UTF-8 length computed above.
		 */
		converted_len = strlen((const char *)converted);

		if (converted_len > MAX_UNICODE_EQUIVALENT_STRING)
			ereport(ERROR,
					(errcode(ERRCODE_CHARACTER_NOT_IN_REPERTOIRE),
					 errmsg("Unicode character 0x%04x expands to %d bytes in server encoding \"%s\", exceeding the maximum of %d",
							c, converted_len, GetDatabaseEncodingName(),
							MAX_UNICODE_EQUIVALENT_STRING)));

		memcpy(utf8, converted, converted_len);
		len = converted_len;
	}

	utf8[len] = '\0';
}
#endif

/*
 * unescape_unicode
 * ----------------
 * Converts \uXXXX and \UXXXXXXXX Unicode escape sequences in a string to
 * their UTF-8 byte representations. Surrogate pairs are combined into a
 * single codepoint. Lone surrogates and malformed sequences are substituted
 * with U+FFFD. All other characters pass through unchanged.
 *
 * input: null-terminated string that may contain Unicode escape sequences
 *
 * returns a palloc'd string with all Unicode escapes resolved
 */
char *unescape_unicode(const char *input)
{
	StringInfoData buf;

	Assert(input != NULL);

	initStringInfo(&buf);

	elog(DEBUG2, "%s: Input='%s'", __func__, input);

	for (const char *p = input; *p;)
	{
		if (p[0] == '\\' && p[1] == '\\')
		{
			appendBinaryStringInfo(&buf, p, 2);
			p += 2;
			continue;
		}
		if (p[0] == '\\' && p[1] == 'u')
		{
			/* \uXXXX (exactly 4 hex digits) */
			if (p[2] && p[3] && p[4] && p[5] &&
				isxdigit(p[2]) && isxdigit(p[3]) && isxdigit(p[4]) && isxdigit(p[5]))
			{
				uint16_t codeunit;
				char hex[5];
				unsigned char utf8[MAX_UNICODE_EQUIVALENT_STRING + 1];
				int len;

				memcpy(hex, p + 2, 4);
				hex[4] = '\0';
				sscanf(hex, "%hx", &codeunit);
				elog(DEBUG2, "%s: Parsed \\u%s to codeunit U+%04X", __func__, hex, codeunit);

				/* Check for high surrogate */
				if (codeunit >= 0xD800 && codeunit <= 0xDBFF &&
					p[6] == '\\' && p[7] == 'u' &&
					p[8] && p[9] && p[10] && p[11] &&
					isxdigit(p[8]) && isxdigit(p[9]) && isxdigit(p[10]) && isxdigit(p[11]))
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
						len = strlen((const char *)utf8);
						appendBinaryStringInfo(&buf, (const char *)utf8, len);
						p += 12;
						continue;
					}
				}

				if (codeunit >= 0xD800 && codeunit <= 0xDFFF)
				{
					elog(DEBUG2, "%s: Lone surrogate U+%04X -> U+FFFD", __func__, codeunit);
					memset(utf8, 0, sizeof(utf8));
					pg_unicode_to_server(0xFFFD, (unsigned char *)utf8);
					len = strlen((const char *)utf8);
					appendBinaryStringInfo(&buf, (const char *)utf8, len);
					p += 6;
					continue;
				}

				memset(utf8, 0, sizeof(utf8));
				pg_unicode_to_server(codeunit, (unsigned char *)utf8);
				len = strlen((const char *)utf8);
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
				isxdigit(p[6]) && isxdigit(p[7]) && isxdigit(p[8]) && isxdigit(p[9]))
			{
				char hex[9];
				uint32_t codepoint;
				unsigned char utf8[MAX_UNICODE_EQUIVALENT_STRING + 1];
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
				len = strlen((const char *)utf8);
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

	Assert(funcname != NULL);

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
 * Checks if an RDF literal is a string literal (simple, xsd:string, or language-tagged).
 * Follows SPARQL 1.1 requirements for string literal inputs (e.g., LCASE, UCASE).
 * Returns false for any other datatype, including derived string types (e.g., xsd:token).
 *
 * str: the full RDF literal string to check
 *
 * returns true if the literal is simple, xsd:string, or language-tagged; false otherwise
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
 * -----------------
 * Converts a SQL LIKE pattern into a POSIX extended regex. SQL wildcards
 * % and _ are mapped to .* and . respectively; regex metacharacters
 * elsewhere in the pattern are escaped with \\.
 *
 * str: SQL LIKE pattern to convert
 *
 * returns a palloc'd POSIX regex string
 */
char *CreateRegexString(char *str)
{
	StringInfoData res;
	initStringInfo(&res);

	elog(DEBUG3, "%s called: str='%s'", __func__, str);

	if (!str)
		return NULL;

	appendStringInfoChar(&res, '^');
	for (int i = 0; str[i] != '\0'; i++)
	{
		char c = str[i];
		bool escaped = false;

		if (c == '\\')
		{
			if (str[i + 1] == '\0')
				ereport(ERROR,
						(errcode(ERRCODE_INVALID_ESCAPE_SEQUENCE),
						 errmsg("LIKE pattern must not end with escape character")));
			c = str[++i];
			escaped = true;
		}

		if (!escaped && c == '%')
			appendStringInfoString(&res, ".*");
		else if (!escaped && c == '_')
			appendStringInfoChar(&res, '.');
		else if (c == '\\')
			appendStringInfoString(&res, "\\\\\\\\");
		else if (strchr("^()[]{}+*$.?|", c) != NULL)
			appendStringInfo(&res, "\\\\%c", c);
		else if (c == '"')
			appendStringInfoString(&res, "\\\"");
		else if (c == '\n')
			appendStringInfoString(&res, "\\n");
		else if (c == '\r')
			appendStringInfoString(&res, "\\r");
		else if (c == '\t')
			appendStringInfoString(&res, "\\t");
		else
			appendStringInfoChar(&res, c);
	}
	appendStringInfoChar(&res, '$');

	elog(DEBUG3, "%s exit: returning '%s'", __func__, NameStr(res));

	return NameStr(res);
}

/*
 * FormatSQLExtractField
 * ---------------
 * The fields "years", "months" and "days" (plural) and "hour", "minute",
 * "second" (singular) are not supported in SPARQL, but PostgreSQL can
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

	Assert(field != NULL);

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
 * constant: the Const node to extract from
 *
 * returns a palloc'ed copy.
 */
char *ConstToCString(Const *constant)
{
	Assert(constant != NULL);

	if (constant->constisnull)
		return NULL;
	else
		return text_to_cstring(DatumGetTextP(constant->constvalue));
}

/*
 * CStringToConst
 * -----------------
 * Wraps a C string in a Const node
 *
 * str: the C string to wrap (NULL produces a null Const)
 *
 * returns a Const node wrapping the given string
 */
Const *CStringToConst(const char *str)
{
	if (str == NULL)
		return makeNullConst(TEXTOID, -1, InvalidOid);
	else
		return makeConst(TEXTOID, -1, InvalidOid, -1, PointerGetDatum(cstring_to_text(str)), false, false);
}

/*
 * rdfnode_to_cstring
 * ------------------
 * Copies the raw content of an rdfnode varlena into a new null-terminated
 * C string.
 *
 * node: the rdfnode to extract from
 *
 * returns a palloc'd null-terminated C string
 */
char *rdfnode_to_cstring(rdfnode *node)
{
	char *data;
	int len;
	char *result;
	Assert(node != NULL);

	/* Get a pointer to the actual data and its length */
	data = VARDATA_ANY(node);
	len = VARSIZE_ANY_EXHDR(node);

	/* Allocate a null-terminated C string */
	result = palloc(len + 1);
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
	Assert(str != NULL);

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
 * pushdown instructions. If it returns false it does not mean that the query
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
	const char *projection;
	const char *end;
	int select_position;
	List *variables = NIL;
	bool wildcard = false;

	Assert(state != NULL);
	Assert(state->raw_sparql != NULL);

	elog(DEBUG3, "%s called", __func__);

	select_position = LocateKeyword(state->raw_sparql, "{\n\t> ", "SELECT",
									 " *?$\n\t", NULL, 0);
	if (select_position == RDF_KEYWORD_NOT_FOUND)
		return false;
	projection = state->raw_sparql + select_position;
	if (pg_strncasecmp(projection, "SELECT", 6) != 0)
		projection++;
	projection += 6;
	end = strrchr(projection, '}');
	if (end == NULL)
		return false;
	for (end++; *end; end++)
		if (!isspace((unsigned char)*end))
			return false;

	/* Replacing anything except a plain variable projection changes the query. */
	while (*projection)
	{
		const char *start;

		while (isspace((unsigned char)*projection))
			projection++;
		if (*projection == '*')
		{
			wildcard = true;
			projection++;
		}
		else if (*projection == '?' || *projection == '$')
		{
			start = ++projection;
			while (isalnum((unsigned char)*projection) || *projection == '_' ||
				   (unsigned char)*projection >= 0x80)
				projection++;
			variables = lappend(variables, pnstrdup(start, projection - start));
		}
		else if (*projection == '{' ||
				 pg_strncasecmp(projection, "WHERE", 5) == 0 ||
				 pg_strncasecmp(projection, "FROM", 4) == 0)
			break;
		else
			return false;
	}

	if (!wildcard)
	{
		for (int i = 0; i < state->numcols; i++)
		{
			ListCell *cell;
			bool found = false;
			char *variable = state->rdfTable->cols[i]->sparqlvar;

			if (variable == NULL)
				continue;
			foreach (cell, variables)
				if (strcmp(variable + 1, (char *)lfirst(cell)) == 0)
					found = true;
			if (!found)
				return false;
		}
	}

	projection = state->raw_sparql;
	while (isspace((unsigned char)*projection))
		projection++;
	if (pg_strncasecmp(projection, "BASE", 4) == 0 ||
		LocateKeyword(state->raw_sparql, " \n\t>", "BASE", " \n\t<", NULL, 0) != RDF_KEYWORD_NOT_FOUND)
		return false;
	/*
	 * SPARQL Queries containing SUB SELECTS are not supported. So, if any number
	 * other than 1 is returned from LocateKeyword, this query cannot be parsed.
	 */
	LocateKeyword(state->raw_sparql, "{\n\t> ", RDF_SPARQL_KEYWORD_SELECT, " *?$\n\t", &keyword_count, 0);

	elog(DEBUG2, "%s: SPARQL contains '%d' SELECT clauses.", __func__, keyword_count);

	/*
	 * A VALUES clause is refused for a reason the other keywords here do not
	 * share. SPARQL 1.1 rule [7] puts it after the solution modifiers, and a
	 * data block ends in '}', so the trailing-content check above -- which
	 * measures from the last '}' in the query -- does not see it, and the
	 * query is declared parsable. DeparseSPARQLWhereGraphPattern() then reads
	 * the graph pattern up to that same last '}', taking the VALUES clause
	 * into it, and CreateSPARQL() appends the pushed-down FILTER after that,
	 * inside the data block. The result is not a SPARQL query, and the scan
	 * fails outright.
	 *
	 * This also turns off pushdown for a VALUES used as inline data inside
	 * the graph pattern, where the rewrite is in fact sound. LocateKeyword()
	 * matches a keyword by its delimiters and cannot tell the two positions
	 * apart, and a table that loses a FILTER still answers correctly.
	 */
	result = LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_VALUES, " \n\t?$", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_GROUPBY, " \n\t?", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
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
 * --------------------
 * Checks if an expression attached to a column can be pushed down, in case it
 * is used in a condition in the SQL WHERE clause.
 *
 * expression: SPARQL expression string from the column's 'expression' option
 *
 * returns 'true' if the expression can be pushed down or 'false' otherwise
 */
bool IsExpressionPushable(char *expression)
{
	char *open = " \n(";
	char *close = " \n(";
	bool result;

	Assert(expression != NULL);

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
 * SkipSPARQLQuoted
 * ----------------
 *
 * Steps over one SPARQL construct whose contents are not query text: a
 * comment, an IRI, or a string literal in any of its four quotings. A caller
 * walking a query token by token uses this to avoid reading what is inside
 * them, where a '?' begins no variable and a keyword names nothing.
 *
 * A literal ends at the first quote that is neither escaped nor, for the
 * triple-quoted forms, short of the closing three. An IRI that runs to
 * whitespace or to the end of the string was never an IRI, so the caller is
 * left where it started rather than being carried past text it should read.
 *
 * p: the character to examine
 *
 * returns the first character after the construct, or p if none starts here
 */
static const char *
SkipSPARQLQuoted(const char *p)
{
	const char *end;

	if (*p == '#')
		return p + strcspn(p, "\r\n");

	if (*p == '<')
	{
		end = p + 1;
		while (*end && *end != '>' && !isspace((unsigned char)*end))
			end++;
		return *end == '>' ? end + 1 : p;
	}

	if (*p == '"' || *p == '\'')
	{
		char quote = *p;
		bool long_quote = p[1] == quote && p[2] == quote;

		end = p + (long_quote ? 3 : 1);
		while (*end)
		{
			if (*end == '\\' && end[1])
				end += 2;
			else if (*end == quote &&
					 (!long_quote || (end[1] == quote && end[2] == quote)))
				return end + (long_quote ? 3 : 1);
			else
				end++;
		}
		return end;
	}

	return p;
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
	const char *p = str;
	int first = RDF_KEYWORD_NOT_FOUND;

	elog(DEBUG2, "%s called: searching '%s' from position %d", __func__, keyword, start_position);

	if (start_position < 0)
		elog(ERROR, "%s: start_position cannot be negative.", __func__);

	if (count)
		*count = 0;

	/*
	 * The string is read once, from the left, so the first keyword found is
	 * the first one there is. Looking for each spelling of the delimiters in
	 * turn instead would find them in the order the caller happened to list
	 * its delimiters, which says nothing about where they occur: given
	 * "FROM<g1> FROM <g2>", " FROM " is found before " FROM<".
	 *
	 * Whatever is not query text is stepped over rather than searched, so a
	 * keyword written inside a literal, an IRI or a comment is not one. It
	 * also does not hide a real keyword after it, which is why the scan
	 * continues past it rather than giving up.
	 */
	while (*p)
	{
		const char *next = SkipSPARQLQuoted(p);
		const char *q = p;
		const char *k = keyword;
		int position = p == str ? 0 : p - str - 1;

		if (next != p)
		{
			p = next;
			continue;
		}

		/*
		 * A keyword is preceded by one of the delimiters the caller accepts,
		 * except at the very start of the string, where a query may open with
		 * SELECT, PREFIX or DESCRIBE and there is nothing to precede it.
		 */
		if (position < start_position ||
			(p != str && strchr(start_chars, p[-1]) == NULL))
		{
			p++;
			continue;
		}

		/* a space in the keyword stands for any run of whitespace */
		while (*k && *q)
		{
			if (isspace((unsigned char)*k) && isspace((unsigned char)*q))
			{
				while (isspace((unsigned char)*k))
					k++;
				while (isspace((unsigned char)*q))
					q++;
			}
			else if (pg_tolower((unsigned char)*k) == pg_tolower((unsigned char)*q))
			{
				k++;
				q++;
			}
			else
				break;
		}

		if (*k == '\0' && (*q == '\0' || strchr(end_chars, *q)))
		{
			if (first == RDF_KEYWORD_NOT_FOUND)
				first = position;
			if (!count)
			{
				elog(DEBUG2, "%s exit: '%s' found at position %d", __func__, keyword, first);
				return first;
			}
			(*count)++;
			p = q;
		}
		else
			p++;
	}

	elog(DEBUG2, "%s exit: returning '%d' (keyword_position)", __func__, first);
	return first;
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

	Assert(url != NULL);

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
 * NextSPARQLVariable
 * ------------------
 *
 * Finds the next variable in a SPARQL string, skipping whatever is not query
 * text on the way: comments, IRIs and string literals, where a '?' or a '$'
 * introduces nothing. A variable is a sigil followed by at least one name
 * character, and the whole name is returned, so a caller cannot mistake the
 * start of one variable for the whole of a shorter one.
 *
 * source : where to start looking
 * end    : set to the first character after the variable that is returned
 *
 * returns the sigil of the next variable, or NULL if there is none
 */
static const char *
NextSPARQLVariable(const char *source, const char **end)
{
	const char *p = source;

	while (*p)
	{
		const char *next = SkipSPARQLQuoted(p);

		if (next != p)
		{
			p = next;
			continue;
		}
		if (*p == '?' || *p == '$')
		{
			next = p + 1;
			while (isalnum((unsigned char)*next) || *next == '_' ||
				   (unsigned char)*next >= 0x80)
				next++;
			if (next > p + 1)
			{
				*end = next;
				return p;
			}
		}
		p++;
	}
	return NULL;
}

/*
 * SPARQLHasVariable
 * -----------------
 *
 * Reports whether a SPARQL string uses a given variable. The whole name has
 * to match: "?s" is not found in "?subject", and neither is found inside a
 * literal or a comment. The sigil is not compared, so "?s" and "$s" are one
 * variable, as SPARQL defines them to be.
 *
 * source   : the SPARQL string to search
 * variable : the variable to look for, sigil included
 *
 * returns true if the variable occurs as a variable
 */
bool SPARQLHasVariable(const char *source, const char *variable)
{
	const char *found;
	const char *end;
	size_t len = strlen(variable);

	while ((found = NextSPARQLVariable(source, &end)) != NULL)
	{
		if (end - found == len && memcmp(found + 1, variable + 1, len - 1) == 0)
			return true;
		source = end;
	}
	return false;
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
	const char *pattern;
	const char *end;
	bool has_triple = false;

	Assert(state != NULL);
	Assert(state->sparql_update_pattern != NULL);

	pattern = state->sparql_update_pattern;

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
				(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
				 errmsg("'%s' contains no valid triple patterns",
						RDF_TABLE_OPTION_SPARQL_UPDATE_PATTERN),
				 errhint("A triple pattern requires at least three components (subject, predicate, object), e.g., '?s ?p ?o .'.")));
	}

	/* Check that all variables in template have corresponding columns */
	pos = pattern;
	while ((pos = NextSPARQLVariable(pos, &end)) != NULL)
	{
		bool found = false;

		for (int k = 0; k < state->numcols; k++)
		{
			const char *variable = state->rdfTable->cols[k]->sparqlvar;

			if (variable && strlen(variable) == end - pos &&
				memcmp(variable + 1, pos + 1, end - pos - 1) == 0)
			{
				found = true;
				break;
			}
		}
		if (!found)
			ereport(ERROR,
					(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
					 errmsg("SPARQL variable '%.*s' in '%s' is not mapped to any table column",
							(int)(end - pos), pos, RDF_TABLE_OPTION_SPARQL_UPDATE_PATTERN)));
		pos = end;
	}
}

/*
 * ReplaceSPARQLVariable
 * ---------------------
 *
 * Substitutes a value for every occurrence of a variable, matching the whole
 * name and only where a variable can stand: not inside a literal, an IRI or a
 * comment. What has already been substituted is not searched again, so a value
 * that happens to contain a sigil is left as the caller wrote it.
 *
 * source  : the SPARQL string to substitute into
 * search  : the variable to replace, sigil included
 * replace : the text to put in its place
 *
 * returns a newly allocated string with every occurrence replaced
 */
char *ReplaceSPARQLVariable(const char *source, const char *search, const char *replace)
{
	StringInfoData result;
	const char *pos = source;
	const char *found;
	const char *scan = source;
	const char *end;
	size_t search_len;
	size_t replace_len;

	Assert(source != NULL);
	Assert(search != NULL);
	Assert(replace != NULL);

	search_len = strlen(search);
	replace_len = strlen(replace);

	initStringInfo(&result);

	while ((found = NextSPARQLVariable(scan, &end)) != NULL)
	{
		if (end - found == search_len &&
			memcmp(found + 1, search + 1, search_len - 1) == 0)
		{
			appendBinaryStringInfo(&result, pos, found - pos);
			appendBinaryStringInfo(&result, replace, replace_len);
			pos = end;
		}
		scan = end;
	}

	/* Append any remaining text */
	appendStringInfoString(&result, pos);

	return result.data;
}
/*
 * AppendControlEscapedLiteralContent
 * -----------------------------------
 *
 * Appends [from, to) to buf, converting raw control-character bytes
 * (newline, carriage return, tab) into their SPARQL/Turtle escape
 * sequences, while copying any *existing* two-byte escape sequence
 * (e.g. \" or \\ already produced by cstring_to_rdfliteral()/rdfnode_in)
 * through verbatim rather than reinterpreting or double-escaping it.
 */
static void
AppendControlEscapedLiteralContent(StringInfoData *buf, const char *from, const char *to)
{
	const char *p = from;

	while (p < to)
	{
		if (*p == '\\' && p + 1 < to)
		{
			/* Pre-existing escape sequence: copy verbatim. */
			appendStringInfoChar(buf, *p);
			appendStringInfoChar(buf, *(p + 1));
			p += 2;
			continue;
		}

		switch (*p)
		{
			case '\n':
				appendStringInfoString(buf, "\\n");
				break;
			case '\r':
				appendStringInfoString(buf, "\\r");
				break;
			case '\t':
				appendStringInfoString(buf, "\\t");
				break;
			default:
				appendStringInfoChar(buf, *p);
				break;
		}
		p++;
	}
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
	const char *closing_quote;

	if (!input || strlen(input) == 0)
		return (char *)input;

	/* Check if this is an IRI - no escaping needed */
	if (input[0] == '<')
		return (char *)input;

	/* Check if this is a quoted literal */
	if (input[0] != '"')
		return (char *)input;

	/*
	 * Locate the true closing quote by walking forward and consuming
	 * escape pairs as they're found (see FindLiteralClosingQuote()),
	 * rather than a single-character lookbehind, which can misjudge the
	 * boundary when the content contains a run of backslashes.
	 */
	closing_quote = FindLiteralClosingQuote(input);

	if (!closing_quote || !IsValidLiteralSuffix(closing_quote + 1))
	{
		/*
		 * Either there's no unambiguous closing quote, or what follows
		 * it isn't a well-formed @lang/^^datatype suffix. Don't guess
		 * or pass anything through unexamined -- re-escape the entire
		 * input as raw content instead, exactly as cstring_to_rdfliteral()
		 * does in the equivalent situation.
		 */
		initStringInfo(&result);
		appendStringInfoChar(&result, '"');
		AppendQuoteEscapedContent(&result, input, input + strlen(input));
		appendStringInfoChar(&result, '"');
		return result.data;
	}

	initStringInfo(&result);

	/* Escape the content between quotes */
	appendStringInfoChar(&result, '"'); /* opening quote */
	AppendControlEscapedLiteralContent(&result, input + 1, closing_quote);

	/* Add closing quote */
	appendStringInfoChar(&result, '"');

	/* Add language tag or datatype if present (already validated above) */
	if (*(closing_quote + 1) != '\0')
		appendStringInfoString(&result, closing_quote + 1);

	return result.data;
}
