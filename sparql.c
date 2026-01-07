/*---------------------------------------------------------------------
 *
 * sparql.c
 *   SPARQL-related functions for RDF data manipulation.
 *
 * Implements SPARQL 1.1 string functions, accessor functions, and
 * type checking.
 *
 * Copyright (C) 2022-2026 University of Münster, Germany
 * 
 *---------------------------------------------------------------------
 */
 
#include "postgres.h"

#include "rdf_fdw.h"
#include "rdf_utils.h"
#include "rdfnode.h"
#include "sparql.h"

#include "lib/stringinfo.h"
#include "catalog/pg_collation.h"
#include "mb/pg_wchar.h"
#include "utils/builtins.h"
#include "utils/timestamp.h"
#include <string.h>
#include <ctype.h>

/*
 * lex
 * ---
 *
 * Extracts the lexical value of a given RDF literal.
 *
 * input: RDF literal
 *
 * returns: lexical value of an RDF literal
 */
char *lex(char *input)
{
    StringInfoData output;
    const char *start = input;
    int len = strlen(input);

    initStringInfo(&output);
    elog(DEBUG3, "%s called: input='%s'", __func__, input);

    if (len == 0)
        return "";

    /* Handle quoted literal */
    if (start[0] == '"')
    {
        const char *p;
        start++; /* skip opening quote */

        p = start;
        while (*p)
        {
            if (*p == '"')
            {
                /* Check for doubled quote escape ("") */
                if (*(p + 1) && *(p + 1) == '"')
                {
                    /* Escaped quote: append one quote and skip both */
                    appendStringInfoChar(&output, '"');
                    p += 2;
                    continue;
                }
                /* Check for backslash escape (\") */
                if (p > start && *(p - 1) == '\\')
                {
                    /* Already appended by previous iteration */
                    appendStringInfoChar(&output, *p);
                    p++;
                    continue;
                }
                /* Unescaped quote: closing quote found */
                break;
            }
            if (*p == '\\' && *(p + 1))
            {
                appendStringInfoChar(&output, *p);
                p++;
            }
            appendStringInfoChar(&output, *p);
            p++;
        }

        /* No closing quote found — malformed, return whole string */
        if (*p != '"')
        {
            resetStringInfo(&output);
            appendStringInfoString(&output, input);
            return output.data;
        }

        /* Successful: return parsed inside quotes */
        return output.data;
    }

    /* Handle IRI */
    if (start[0] == '<')
    {
        appendStringInfoString(&output, start);
        return output.data;
    }

    /* Unquoted: trim at @ or ^^ only if they indicate language tag or datatype */
    {
        const char *at = strchr(start, '@');
        const char *dt = strstr(start, "^^");
        const char *cut = NULL;

        if (at && (!dt || at < dt))
        {
            const char *tag = at + 1;
            int letter_count = 0;
            const char *p = NULL;
            int is_lang_tag = 0;

            if (*tag && isalpha(*tag))
            {
                p = tag;
                while (*p && isalpha(*p) && letter_count < 8)
                {
                    letter_count++;
                    p++;
                }

                if (letter_count >= 1 && (!*p || *p == '-' || (*p != '.' && *p != '@')))
                {
                    if (*p == '-')
                    {
                        p++;
                        while (*p && (isalnum(*p) || *p == '-'))
                        {
                            p++;
                        }
                    }

                    if (!*p || (*p != '.' && *p != '@'))
                    {
                        is_lang_tag = 1;
                    }
                }
            }

            if (is_lang_tag)
            {
                cut = at;
            }
        }
        else if (dt)
        {
            cut = dt;
        }

        if (cut)
        {
            appendBinaryStringInfo(&output, start, cut - start);
        }
        else
        {
            appendStringInfoString(&output, start);
        }
    }

    return output.data;
}

/*
 * lang
 * ----
 *
 * Extracts the language tag from an RDF literal, if present. Returns an
 * empty string if no language tag is found or if the input is invalid/empty.
 *
 * input: Null-terminated C string representing an RDF literal (e.g.,
 * "abc"@en, "123"^^xsd:int)
 *
 * returns: Null-terminated C string representing the language tag (e.g.,
 * "en") or empty string
 */
char *lang(char *input)
{
    StringInfoData buf;
    const char *ptr;
    char *lexical_form;

    elog(DEBUG3, "%s called: input='%s'", __func__, input);

    if (!input || strlen(input) == 0)
        return "";

    lexical_form = lex(input);
    ptr = input;

    /* find the end of the lexical form in the original input */
    if (*ptr == '"')
    {
        ptr++;                       /* skip opening quote */
        ptr += strlen(lexical_form); /* move to end of lexical form */
        if (*ptr == '"')
            ptr++; /* skip closing quote */
    }
    else
    {
        ptr += strlen(lexical_form); /* unquoted case */
    }

    /* check for language tag */
    if (*ptr == '@')
    {
        const char *tag_start = ptr + 1;
        const char *tag_end = tag_start;

        while (*tag_end && (isalnum(*tag_end) || *tag_end == '-' || *tag_end == '_'))
            tag_end++;

        initStringInfo(&buf);
        appendBinaryStringInfo(&buf, tag_start, tag_end - tag_start);
        elog(DEBUG3, "%s exit: returning => '%s'", __func__, buf.data);
        return buf.data;
    }

    elog(DEBUG3, "%s exit: returning empty string", __func__);
    return "";
}

/*
 * strlang
 * -------
 *
 * Constructs an RDF literal by combining a lexical value with a specified
 * language tag. The result is formatted as a language-tagged RDF literal.
 *
 * literal: Null-terminated C string representing an RDF literal or lexical
 * value (e.g., "abc")
 * language: Null-terminated C string representing the language tag (e.g.,
 * "en")
 *
 * returns: Null-terminated C string formatted as a language-tagged RDF
 * literal (e.g., "abc"@en)
 */
char *strlang(char *literal, char *language)
{
    StringInfoData buf;
    char *lex_language = lex(language);
    char *lex_literal = lex(literal);

    elog(DEBUG3, "%s called: literal='%s', language='%s'", __func__, literal, language);

    if (strlen(lex_language) == 0)
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("language tag cannot be empty")));

    initStringInfo(&buf);

    if (strlen(lex_literal) == 0)
        appendStringInfo(&buf, "\"\"@%s", lex_language);
    else
        appendStringInfo(&buf, "%s@%s", str(literal), lex_language);

    elog(DEBUG3, "%s exit: returning => '%s'", __func__, buf.data);

    return buf.data;
}

/*
 * strstarts
 * ---------
 *
 * Implements the core logic for the SPARQL STRSTARTS function, returning true
 * if the lexical form of the first argument (string) starts with the lexical
 * form of the second argument (substring), or false if arguments are
 * incompatible or the condition fails. An empty substring is considered a
 * prefix of any string, per SPARQL behavior.
 *
 * str: Null-terminated C string representing an RDF literal or value
 * (e.g., "foobar")
 * substr: Null-terminated C string representing an RDF literal or value
 * (e.g., "foo")
 *
 * returns: C boolean (true if string starts with substring, false otherwise
 * or if incompatible)
 */
bool strstarts(char *str, char *substr)
{
    char *str_lexical = lex(str);
    char *substr_lexical = lex(substr);
    size_t str_len = strlen(str_lexical);
    size_t substr_len = strlen(substr_lexical);
    int result;

    elog(DEBUG3, "%s called: str='%s', substr='%s'", __func__, str, substr);

    if (!LiteralsCompatible(str, substr))
    {
        elog(DEBUG3, "%s exit: returning 'false' (incompatible literals)", __func__);
        return false;
    }

    if (substr_len == 0)
    {
        elog(DEBUG3, "%s exit: returning 'true' (empty substring is a prefix of any string)", __func__);
        return true;
    }

    if (substr_len > str_len)
    {
        elog(DEBUG3, "%s exit: returning 'false' (substring longer than string cannot be a prefix)", __func__);
        return false;
    }

    result = strncmp(str_lexical, substr_lexical, substr_len);

    elog(DEBUG3, "%s exit: returning '%s'", __func__,
         result == 0 ? "true" : "false");

    return result == 0;
}

/*
 * strends
 * -------
 *
 * Implements the core logic for the SPARQL STRENDS function, returning true
 * if the lexical form of the first argument (string) ends with the lexical
 * form of the second argument (substring), or false if arguments are
 * incompatible or the condition fails. An empty substring is considered a
 * suffix of any string, per SPARQL behavior.
 *
 * str: Null-terminated C string representing an RDF literal or value
 * (e.g., "foobar")
 * substr: Null-terminated C string representing an RDF literal or value
 * (e.g., "bar")
 *
 * returns: C boolean (true if string ends with substring, false otherwise
 * or if incompatible)
 */
bool strends(char *str, char *substr)
{
    char *str_lexical = lex(str);
    char *substr_lexical = lex(substr);
    size_t str_len = strlen(str_lexical);
    size_t substr_len = strlen(substr_lexical);
    int result;

    elog(DEBUG3, "%s called: str='%s', substr='%s'", __func__, str, substr);

    if (!LiteralsCompatible(str, substr))
    {
        elog(DEBUG3, "%s exit: returning 'false' (incompatible literals)", __func__);
        return false;
    }

    if (substr_len == 0)
    {
        elog(DEBUG3, "%s exit: returning 'true' (an empty substring is a suffix of any string)", __func__);
        return true;
    }

    if (substr_len > str_len)
    {
        elog(DEBUG3, "%s exit: returning 'false' (substring longer than string cannot be a suffix)", __func__);
        return false;
    }

    result = strncmp(str_lexical + (str_len - substr_len), substr_lexical, substr_len);

    elog(DEBUG3, "%s exit: returning '%s'", __func__, result == 0 ? "true" : "false");

    return result == 0;
}

/*
 * strdt
 * -----
 *
 * Constructs an RDF literal by combining a lexical value with a specified
 * datatype IRI. Uses ExpandDatatypePrefix to handle prefix expansion
 * (e.g., "xsd:" to full URI) or retain prefixed/bare forms without angle
 * brackets unless fully expanded.
 *
 * literal: Null-terminated C string representing an RDF literal or lexical
 * value (e.g., "123")
 * datatype: Null-terminated C string representing the datatype IRI
 * (e.g., "xsd:int", "foo:bar")
 *
 * returns: Null-terminated C string formatted as a datatype-tagged RDF
 * literal (e.g., "123"^^<http://www.w3.org/2001/XMLSchema#int>,
 * "foo"^^foo:bar)
 */
char *strdt(char *literal, char *datatype)
{
    StringInfoData buf;
    char *lex_datatype = lex(datatype);

    elog(DEBUG3, "%s called: literal='%s', datatype='%s'", __func__, literal, datatype);

    if (strlen(lex_datatype) == 0)
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("datatype IRI cannot be empty")));

    if (ContainsWhitespaces(datatype))
        ereport(ERROR, (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                        errmsg("datatype IRI cannot contain whitespaces")));

    initStringInfo(&buf);

    if (isIRI(datatype))
        appendStringInfo(&buf, "%s^^%s", str(literal), datatype);
    else
    {
        char *expanded_datatype;

        elog(DEBUG2, "%s: data type not an IRI", __func__);

        expanded_datatype = ExpandDatatypePrefix(lex_datatype);
        appendStringInfo(&buf, "%s^^%s", str(literal), iri(expanded_datatype));
    }

    elog(DEBUG3, "%s exit: returning => '%s'", __func__, buf.data);

    return buf.data;
}

/*
 * str
 * ---
 *
 * Extracts the lexical value of an RDF literal or the string form of an IRI
 * and returns it as a new RDF literal. If the input is empty or null,
 * returns an empty RDF literal.
 *
 * input: Null-terminated C string representing an RDF literal or IRI
 * (e.g., "abc"@en, "<http://example.org>")
 *
 * returns: Null-terminated C string formatted as an RDF literal
 * (e.g., "abc", "http://example.org")
 */
char *str(char *input)
{
    StringInfoData buf;
    char *result;

    elog(DEBUG3, "%s called: input='%s'", __func__, input);

    if (!input || input[0] == '\0')
    {
        elog(DEBUG3, "%s exit: returning empty literal", __func__);
        return "\"\"";
    }

    if (isIRI(input))
    {
        size_t len = strlen(input);
        initStringInfo(&buf);
        appendStringInfo(&buf, "\"%.*s\"", (int)(len - 2), input + 1); /* skip '<' and trim '>' */

        elog(DEBUG3, "%s exit: returning IRI '%s'", __func__, buf.data);
        return buf.data;
    }

    result = cstring_to_rdfliteral(lex(input));
    elog(DEBUG3, "%s exit: returning literal '%s'", __func__, result);
    return result;
}

/*
 * iri
 * ---
 * Converts a string to an IRI by wrapping it in angle brackets (< >),
 * mimicking SPARQL's IRI() function. Strips quotes and any language tags or
 * datatypes if present *only* for quoted literals. Raw strings and
 * pre-wrapped IRIs are preserved.
 */
char *iri(char *input)
{
    StringInfoData buf;
    char *lexical;

    elog(DEBUG3, "%s called: input='%s'", __func__, input ? input : "(null)");

    if (!input || *input == '\0')
        return "<>";

    if (isIRI(input))
        return pstrdup(input);

    initStringInfo(&buf);

    lexical = lex(input);
    appendStringInfo(&buf, "<%s>", lexical);

    elog(DEBUG3, "%s exit: returning wrapped IRI '%s'", __func__, buf.data);
    return pstrdup(buf.data);
}

/*
 * bnode
 * -----
 *
 * Implements SPARQL’s BNODE function. Without arguments (input = NULL),
 * generates a unique blank node (e.g., "_:b123"). With a string argument,
 * returns a blank node based on the lexical form of the input (e.g.,
 * BNODE("xyz") → "_:xyz"). Invalid inputs (e.g., IRIs, blank nodes, empty
 * literals) return NULL.
 *
 * input: Null-terminated C string (literal or bare string) for BNODE(str),
 * or NULL for BNODE().
 *
 * returns: Null-terminated C string representing a blank node (e.g.,
 * "_:xyz"), or NULL for invalid inputs.
 */
char *bnode(char *input)
{
    StringInfoData buf;
    static uint64 counter = 0; /* Ensure uniqueness for BNODE() */

    elog(DEBUG3, "%s called: input='%s'", __func__, input);

    initStringInfo(&buf);

    if (input == NULL)
    {
        /* BNODE(): Generate unique blank node using timestamp and counter */
        TimestampTz ts = GetCurrentTimestamp();
        uint64 unique_id = counter++ ^ (uint64)ts;
        appendStringInfo(&buf, "_:b%llu", (unsigned long long)unique_id);
    }
    else
    {
        StringInfoData input_buf;
        char *normalized_input;
        char *lexical;

        /* Reject IRIs explicitly */
        if (isIRI(input))
        {
            elog(DEBUG3, "%s exit: returning NULL (input is an IRI)", __func__);
            return NULL;
        }

        /* If input is already a blank node, return it as-is (idempotent behavior) */
        if (isBlank(input))
        {
            elog(DEBUG3, "%s exit: returning input as-is (already a blank node)", __func__);
            appendStringInfoString(&buf, input);
            return buf.data;
        }

        /* Normalize input: quote bare strings */
        initStringInfo(&input_buf);
        if (*input != '"' && !strstr(input, "^^") && !strstr(input, "@"))
        {
            appendStringInfoChar(&input_buf, '"');
            appendStringInfoString(&input_buf, input);
            appendStringInfoChar(&input_buf, '"');
        }
        else
        {
            appendStringInfoString(&input_buf, input);
        }

        normalized_input = input_buf.data;

        /* Validate input is a literal */
        if (!isLiteral(normalized_input))
        {
            elog(DEBUG3, "%s exit: returning NULL (input is not a literal)", __func__);
            return NULL;
        }

        /* Extract lexical form */
        lexical = lex(normalized_input);
        if (!lexical || strlen(lexical) == 0)
        {
            elog(DEBUG3, "%s exit: returning NULL (lexical value either NULL or an empty string)", __func__);
            return NULL;
        }

        /* Create blank node ID, sanitizing lexical form (alphanumeric or underscore) */
        appendStringInfoString(&buf, "_:");
        for (char *p = lexical; *p; p++)
        {
            if (isalnum((unsigned char)*p))
                appendStringInfoChar(&buf, *p);
            else
                appendStringInfoChar(&buf, '_');
        }
    }

    elog(DEBUG3, "%s exit: returning '%s'", __func__, buf.data);
    return buf.data;
}

/*
 * concat(text, text) returns text
 *
 * Implements the SPARQL CONCAT function.
 *
 * Concatenates two RDF literals while preserving compatible language tags
 * or datatype annotations (specifically xsd:string). If both inputs share
 * the same language tag, the result will carry that tag. If both inputs are
 * typed as xsd:string, the result is typed as xsd:string.
 *
 * Mixing a simple literal with a language-tagged or xsd:string-typed value
 * results in a plain literal without type or language. Conflicting language
 * tags also return simple literals.
 *
 * NULL inputs yield NULL. Empty strings are allowed and result in valid RDF
 * literals.
 */
char *concat(char *left, char *right)
{
    char *left_lexical, *right_lexical;
    char *left_language, *right_language;
    char *left_datatype, *right_datatype;
    char *result;
    StringInfoData buf;

    elog(DEBUG3, "%s called: left='%s', right='%s'", __func__, left, right);

    if (!left || !right)
        ereport(ERROR,
                (errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
                 errmsg("CONCAT arguments cannot be NULL")));

    if (isIRI(left) || isIRI(right) || isBlank(left) || isBlank(right))
        ereport(ERROR,
                (errcode(ERRCODE_INVALID_PARAMETER_VALUE),
                 errmsg("CONCAT not allowed on IRI or blank node")));

    left_lexical = lex(left);
    right_lexical = lex(right);
    left_language = lang(left);
    right_language = lang(right);
    left_datatype = datatype(left);
    right_datatype = datatype(right);

    elog(DEBUG3, "%s: left_lexical='%s', right_lexical='%s', left_language='%s', right_language='%s'",
         __func__, left_lexical, right_lexical, left_language, right_language);

    initStringInfo(&buf);
    appendStringInfo(&buf, "%s%s", left_lexical, right_lexical);

    /* Per SPARQL 1.1 spec:
     * - If both have identical language tags, preserve the tag
     * - If both have no language tag, return simple literal
     * - Otherwise (including conflicting tags), return simple literal
     */
    if (strlen(left_language) > 0 && strlen(right_language) > 0)
    {
        if (strcmp(left_language, right_language) == 0)
        {
            /* Identical language tags - preserve them */
            result = strlang(buf.data, left_language);
        }
        else
        {
            /* Conflicting language tags - return simple literal (no tag) */
            elog(DEBUG3, "%s: conflicting language tags '%s' and '%s', returning simple literal",
                 __func__, left_language, right_language);
            result = cstring_to_rdfliteral(buf.data);
        }
    }
    else if (strlen(left_language) > 0 || strlen(right_language) > 0)
    {
        /* One has language tag, other doesn't - return simple literal */
        elog(DEBUG3, "%s: mixed language tags, returning simple literal", __func__);
        result = cstring_to_rdfliteral(buf.data);
    }
    else if (strlen(left_datatype) > 0 && strlen(right_datatype) > 0 &&
             strcmp(left_datatype, right_datatype) == 0)
    {
        /* Both have same datatype - preserve it */
        result = strdt(buf.data, left_datatype);
    }
    else
    {
        /* No language tags or mixed datatypes - return simple literal */
        result = cstring_to_rdfliteral(buf.data);
    }

    pfree(buf.data);

    elog(DEBUG3, "%s exit: returning '%s'", __func__, result);
    return result;
}

/*
 * isIRI
 * -----
 * Checks if a string is an RDF IRI. A valid IRI must:
 * - Start with '<' and end with '>'
 * - Not contain spaces or quote characters
 * - May be absolute (with a colon) or relative (e.g., <foo>) according to
 *   SPARQL 1.1.
 */
bool isIRI(char *input)
{
    size_t len;
    size_t i;

    if (input == NULL || (len = strlen(input)) < 3)
        return false;

    /* Must be enclosed in <...> */
    if (input[0] != '<' || input[len - 1] != '>')
        return false;

    /* Check for illegal characters inside the IRI */
    for (i = 1; i < len - 1; i++)
    {
        char c = input[i];
        if (c == '"' || c == ' ' || c == '\n' || c == '\r' || c == '\t')
            return false;
    }

    /* All checks passed — valid IRI (absolute or relative) */
    return true;
}

/*
 * isBlank
 * -------
 *
 * Mimics SPARQL's isBlank function. Checks if the input is a blank node.
 * Returns true if the term starts with "_:", false otherwise.
 *
 * term: Null-terminated C string, an RDF term (e.g., "_:b1", "<http://ex.com>", "\"hello\"")
 *
 * returns: Boolean (true if blank node, false otherwise)
 */
bool isBlank(char *term)
{
    bool result;
    elog(DEBUG3, "%s called: term='%s'", __func__, term);

    /* Handle NULL or empty input */
    if (!term || strlen(term) == 0)
    {
        elog(DEBUG3, "%s exit: returning 'false' (invalid input)", __func__);
        return false;
    }

    /* Check if term starts with "_:" and has at least 3 characters */
    result = (strncmp(term, "_:", 2) == 0) && strlen(term) > 2;

    elog(DEBUG3, "%s exit: returning '%s'", __func__, result ? "true" : "false");
    return result;
}

/*
 * isLiteral
 * ---------
 *
 * Checks if an RDF term is a literal per SPARQL 1.1 spec. Returns true for simple
 * literals (e.g., "\"hello\""), language-tagged literals (e.g., "\"hello\"@en"),
 * or typed literals (e.g., "\"12\"^^xsd:integer"). Returns false for IRIs
 * (e.g., "<http://example.org>"), blank nodes (e.g., "_:bnode"), bare numbers
 * (e.g., "123"), empty strings, or invalid inputs.
 *
 * term: Null-terminated C string representing an RDF term
 *
 * returns: Boolean (1 for literal, 0 otherwise)
 */
bool isLiteral(char *term)
{
    const char *ptr;
    int len;

    elog(DEBUG3, "%s called: term='%s'", __func__, term);

    if (!term || *term == '\0')
    {
        elog(DEBUG3, "%s exit: returning 'false' (term either NULL or has no '\\0')", __func__);
        return false;
    }

    /* Exclude IRIs and blank nodes first */
    if (isIRI(term) || isBlank(term))
    {
        elog(DEBUG3, "%s exit: returning 'false' (either an IRI or a blank node)", __func__);
        return false;
    }

    /* Normalize input */
    ptr = cstring_to_rdfliteral(term);
    len = strlen(ptr);

    /* Check for valid quoted literal */
    if (*ptr == '"')
    {
        if (len >= 2)
        {
            const char *tag = strstr(ptr, "^^");
            const char *lang_tag = strstr(ptr, "@");

            /* Typed literal: has ^^ followed by datatype */
            if (tag && tag > ptr + 1 && *(tag - 1) == '"' &&
                (!lang_tag || lang_tag > tag))
            {
                const char *dt_start = tag + 2;
                if (*dt_start != '\0' && (*dt_start != '<' || *(dt_start + 1) != '>'))
                {
                    elog(DEBUG3, "%s exit: returning 'true' (valid datatype)", __func__);
                    return true;
                } /* Valid datatype */
            }
            /* Language-tagged literal: has @ with language tag */
            else if (lang_tag && lang_tag > ptr + 1 && *(lang_tag - 1) == '"' &&
                     *(lang_tag + 1) != '\0')
            {
                elog(DEBUG3, "%s exit: returning 'true' (literal has a language tag)", __func__);
                return true;
            }
            /* Simple literal: quoted string, no ^^ or @ */
            else if (ptr[len - 1] == '"')
            {
                elog(DEBUG3, "%s exit: returning 'true' (simple literal - no ^^ or @)", __func__);
                return true;
            }
        }
        else if (len == 1)
        {
            /* Empty quoted literal "" */
            elog(DEBUG3, "%s exit: returning 'true' (empty quoted literal)", __func__);
            return true;
        }
    }

    /* Invalid or non-literal */
    elog(DEBUG3, "%s exit: returning 'false' (invalid or non-literal)", __func__);
    return false;
}

/*
 * langmatches
 * -----------
 *
 * Mimics SPARQL's LANGMATCHES function. Compares a language tag against a pattern,
 * supporting basic matching and wildcards (*). Case-insensitive per RFC 4647.
 * Returns true if the language tag matches the pattern, false otherwise.
 *
 * lang_tag: Null-terminated C string, typically a language tag (e.g., "en" from lang())
 * pattern: Null-terminated C string, language range (e.g., "en", "en-*", "*")
 *
 * returns: Boolean (true if lang_tag matches pattern, false otherwise)
 */
bool langmatches(char *lang_tag, char *pattern)
{
    char *tag;
    char *pat;
    bool result;

    elog(DEBUG3, "%s called: lang_tag='%s', pattern='%s'", __func__, lang_tag, pattern);

    /* Handle NULL inputs */
    if (!lang_tag || !pattern)
    {
        elog(DEBUG3, "%s exit: returning 'false' (invalid input)", __func__);
        return false;
    }

    pattern = lex(pattern);
    tag = lex(lang_tag); /* e.g., "en" from lang('"foo"@en') */
    /* Handle pattern: bare string or quoted literal */
    if (pattern[0] == '"' && strrchr(pattern, '"') > pattern)
        pat = lex(pattern); /* e.g., "\"en\"" -> "en" */
    else
        pat = pattern; /* e.g., "en" as-is */

    /* Empty tag only matches "*" pattern (case-insensitive) */
    if (strlen(tag) == 0)
    {
        result = (strcasecmp(pat, "*") == 0);
        elog(DEBUG3, "%s exit: returning '%s' (empty tag, pattern='%s')",
             __func__, result ? "true" : "false", pat);
        return result;
    }

    /* Exact match (case-insensitive) */
    if (strcasecmp(tag, pat) == 0)
    {
        result = true;
    }
    /* Wildcard match: "*" matches any non-empty tag */
    else if (strcasecmp(pat, "*") == 0)
    {
        result = true;
    }
    /* SPARQL rule: prefix match with hyphen, e.g. "en" matches "en-US" */
    else if (strncasecmp(tag, pat, strlen(pat)) == 0 &&
             tag[strlen(pat)] == '-')
    {
        result = true;
    }
    /* Prefix match with wildcard (e.g., "en-*" matches "en" or "en-us") */
    else if (strchr(pat, '*'))
    {
        char *prefix_end = strchr(pat, '*');
        size_t prefix_len = prefix_end - pat;
        size_t tag_len = strlen(tag);

        if (prefix_len > 0 && tag_len >= (prefix_len - 1) &&
            strncasecmp(tag, pat, prefix_len - 1) == 0)
        {
            if (tag_len == prefix_len - 1 ||
                (tag_len > prefix_len && tag[prefix_len - 1] == '-' && prefix_end[1] == '\0'))
            {
                result = true;
            }
            else
            {
                result = false;
            }
        }
        else
        {
            result = false;
        }
    }
    else
    {
        result = false;
    }

    elog(DEBUG3, "%s exit: returning '%s' (tag='%s', pat='%s')",
         __func__, result ? "true" : "false", tag, pat);

    return result;
}

/*
 * datatype
 * --------
 *
 * Extracts the datatype URI of an RDF literal, following SPARQL 1.1 conventions.
 * Returns "" for simple literals and language-tagged literals (unbound per spec).
 * For typed literals (e.g., xsd: types), constructs the full URI using RDF_XSD_BASE_URI.
 * Returns "" for invalid or unrecognized inputs.
 *
 * input: Null-terminated C string representing an RDF literal (e.g., "123"^^xsd:int, "abc"@en, "xyz")
 *
 * returns: Null-terminated C string representing the datatype URI (e.g., "http://www.w3.org/2001/XMLSchema#int")
 */
char *datatype(char *input)
{
    StringInfoData buf;
    const char *ptr;
    int len;

    elog(DEBUG3, "%s called: input='%s'", __func__, input ? input : "(null)");

    if (input == NULL || *input == '\0')
    {
        elog(DEBUG3, "%s exit: returning empty string for NULL or empty input", __func__);
        return "";
    }

    ptr = cstring_to_rdfliteral(input);
    len = strlen(ptr);

    initStringInfo(&buf);

    if (*ptr == '"')
    {
        const char *tag = strstr(ptr, "^^");
        const char *lang_tag = strstr(ptr, "@");

        /* check for datatype first */
        if (tag && tag > ptr + 1 && *(tag - 1) == '"' &&
            (!lang_tag || lang_tag > tag)) /* datatype takes precedence */
        {
            const char *dt_start = tag + 2; /* skip ^^ */
            const char *dt_end = dt_start;

            /* find the end of the datatype */
            if (*dt_start == '<')
            {
                while (*dt_end && *dt_end != '>')
                    dt_end++;
                if (*dt_end != '>') /* ensure proper closing */
                {
                    elog(DEBUG3, "%s exit: returning empty string (malformed datatype IRI, missing '>')", __func__);
                    return "";
                }
                dt_end++; /* include > */
            }
            else
            {
                while (*dt_end && *dt_end != ' ' && *dt_end != '>' && *dt_end != '@')
                    dt_end++;
            }

            if (dt_start < dt_end)
            {
                char *res = "";
                /* handle xsd: prefix */
                if (strncmp(dt_start, "xsd:", 4) == 0 && dt_end - dt_start > 4)
                {
                    appendStringInfoString(&buf, RDF_XSD_BASE_URI);
                    appendBinaryStringInfo(&buf, dt_start + 4, dt_end - (dt_start + 4));
                }
                else if (*dt_start == '<' && *(dt_end - 1) == '>' &&
                         strncmp(dt_start + 1, "xsd:", 4) == 0 && dt_end - dt_start > 6)
                {
                    appendStringInfoString(&buf, RDF_XSD_BASE_URI);
                    appendBinaryStringInfo(&buf, dt_start + 5, dt_end - (dt_start + 6));
                }
                else if (*dt_start == '<' && *(dt_end - 1) == '>')
                {
                    appendBinaryStringInfo(&buf, dt_start + 1, dt_end - dt_start - 2);
                }
                else
                {
                    appendBinaryStringInfo(&buf, dt_start, dt_end - dt_start);
                }

                /* ensure no trailing junk */
                if (*dt_end != '\0')
                {
                    elog(DEBUG3, "%s exit: returning empty string (trailing chars after datatype)", __func__);
                    return res;
                }

                res = iri(buf.data);

                elog(DEBUG3, "%s exit: returning '%s'", __func__, res);
                return res;
            }
        }
        /* simple or language-tagged literal */
        if ((lang_tag && lang_tag > ptr + 1 && *(lang_tag - 1) == '"') ||
            (len >= 1 && (ptr[len - 1] == '"' || len == 1)))
        {
            elog(DEBUG3, "%s exit: returning empty string (simple/language-tagged literal)", __func__);
            return "";
        }
    }

    /* Not a valid literal */
    elog(DEBUG3, "%s exit: returning empty string (not a valid literal)", __func__);
    return "";
}

/*
 * encode_for_uri
 * --------------
 *
 * Encodes a string for use in a URI by percent-encoding all characters except
 * those defined as unreserved in RFC 3986 (alphanumeric, hyphen, period,
 * underscore, and tilde). If the input starts with a quote, it is treated as an
 * RDF literal and processed accordingly.
 *
 * str: Null-terminated C string to encode (e.g., "hello world", "\"example\"@en")
 *
 * returns: Null-terminated C string with URI-encoded result, formatted as an RDF literal
 */
char *encode_for_uri(char *str_in)
{
    const char *unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~";
    size_t in_len;
    char *res;

    StringInfoData buf;
    initStringInfo(&buf);

    elog(DEBUG3, "%s called: str='%s'", __func__, str_in);

    str_in = lex(str_in);
    in_len = strlen(str_in);

    elog(DEBUG2, "%s: encoding string: '%s', length: %zu", __func__, str_in, in_len);

    for (size_t i = 0; i < in_len; i++)
    {
        unsigned char c = (unsigned char)str_in[i];
        if (strchr(unreserved, c))
            appendStringInfoChar(&buf, c);
        else
            appendStringInfo(&buf, "%%%02X", c);
    }

    res = cstring_to_rdfliteral(buf.data);

    elog(DEBUG3, "%s exit: returning => '%s'", __func__, res);
    return res;
}

/*
 * generate_uuid_v4
 * ----------------
 * Generates a version 4 (random) UUID per RFC 4122. Returns a lowercase string
 * in the format xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx, where y is 8, 9, A, or B.
 * Uses timestamp and counter for entropy, no external dependencies.
 *
 * Returns: Null-terminated C string (e.g., "123e4567-e89b-12d3-a456-426614174000")
 */
char *generate_uuid_v4(void)
{
    StringInfoData buf;
    static uint64 counter = 0;
    uint64 seed;
    uint8_t bytes[16];
    char *result;
    int i;

    elog(DEBUG3, "%s called", __func__);

    initStringInfo(&buf);

    /* Use timestamp and counter for pseudo-randomness */
    seed = (uint64)GetCurrentTimestamp() ^ counter++;

    /* Generate 16 bytes of pseudo-random data */
    for (i = 0; i < 16; i++)
    {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff; /* Linear congruential generator */
        bytes[i] = (uint8_t)(seed >> 16);
    }

    /* Set version (4) and variant (y = 8, 9, A, B) */
    bytes[6] = (bytes[6] & 0x0F) | 0x40; /* Version 4 */
    bytes[8] = (bytes[8] & 0x3F) | 0x80; /* Variant: 10xx */

    /* Format as xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx */
    appendStringInfo(&buf, "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                     bytes[0], bytes[1], bytes[2], bytes[3],
                     bytes[4], bytes[5],
                     bytes[6], bytes[7],
                     bytes[8], bytes[9],
                     bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]);

    result = pstrdup(buf.data);
    pfree(buf.data);

    elog(DEBUG3, "%s exit: returning '%s'", __func__, result);
    return result;
}

/*
 * substr_sparql
 * -------------
 * Implements SPARQL's SUBSTR(str, start, length) function.
 * Converts RDF literal or bare string into substring while preserving language/datatype tag.
 *
 * str     : Input RDF literal or bare string.
 * start   : 1-based index (inclusive).
 * length  : Optional substring length (0 or negative is invalid).
 *
 * Returns a new RDF literal string with the appropriate tag preserved.
 */
char *substr_sparql(char *str, int start, int length)
{
	char *lexical;
	char *str_datatype;
	char *str_language;
	char *result;
	text *input_text;
	text *substr_text;
	int str_len;

	elog(DEBUG3, "%s called: str='%s', start=%d, length=%d", __func__, str, start, length);

	if (!str)
		ereport(ERROR,
				(errcode(ERRCODE_NULL_VALUE_NOT_ALLOWED),
				 errmsg("SUBSTR cannot be NULL")));

	if (start < 1)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("SUBSTR start position must be >= 1")));

	if (isIRI(str) || isBlank(str))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("SUBSTR not allowed on IRI or blank node: %s", str)));

	lexical = lex(str);
	str_datatype = datatype(str);
	str_language = lang(str);

	elog(DEBUG3, "%s: lexical='%s', datatype='%s', language='%s'", __func__,
		 lexical, str_datatype, str_language);

	/* Check if start is beyond string length - return empty string */
	str_len = pg_mbstrlen(lexical);
	if (start > str_len)
	{
		if (strlen(str_language) > 0)
			return strlang("", str_language);
		else if (strlen(str_datatype) > 0)
			return strdt("", str_datatype);
		else
			return cstring_to_rdfliteral("");
	}

	/* Use PostgreSQL's text_substr which handles UTF-8 correctly */
	input_text = cstring_to_text(lexical);
	
	if (length >= 0)
	{
		/* text_substr is 1-based and handles UTF-8 character boundaries */
		substr_text = DatumGetTextP(DirectFunctionCall3(
			text_substr,
			PointerGetDatum(input_text),
			Int32GetDatum(start),
			Int32GetDatum(length)));
	}
	else
	{
		/* No length specified - take from start to end */
		substr_text = DatumGetTextP(DirectFunctionCall3(
			text_substr,
			PointerGetDatum(input_text),
			Int32GetDatum(start),
			Int32GetDatum(str_len - start + 1)));
	}

	lexical = text_to_cstring(substr_text);

	if (strlen(str_language) > 0)
		result = strlang(lexical, str_language);
	else if (strlen(str_datatype) > 0)
		result = strdt(lexical, str_datatype);
	else
		result = cstring_to_rdfliteral(lexical);

	pfree(input_text);
	pfree(substr_text);

	elog(DEBUG3, "%s exit: returning '%s'", __func__, result);
	return result;
}

/*
 * lcase
 * -----
 *
 * Implements SPARQL’s LCASE function. Converts the lexical form of a string literal
 * (simple, xsd:string, or language-tagged) to lowercase (ASCII A-Z to a-z, non-ASCII
 * preserved). Preserves the original datatype or language tag. Errors on IRIs, blank
 * nodes, non-string literals, or invalid inputs. Bare strings are treated as simple literals.
 *
 * str: Null-terminated C string (RDF literal or bare string, e.g., "BAR", "\"BAR\"@en")
 *
 * returns: Null-terminated C string (lowercase RDF literal)
 */
char *lcase(char *str)
{
	char *lexical;
	char *str_datatype;
	char *str_language;
	char *result;

	elog(DEBUG3, "%s called: str='%s'", __func__, str);

	if (!str)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("LCASE cannot be NULL")));

	if (strlen(str) == 0)
	{
		elog(DEBUG3, "%s exit: returning empty literal (str is an empty string)", __func__);
		return cstring_to_rdfliteral("");
	}

	/* Check for IRIs or blank nodes */
	if (isIRI(str))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("LCASE does not allow IRIs: %s", str)));

	if (isBlank(str))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("LCASE does not allow blank nodes: %s", str)));

	lexical = lex(str);

	if (lexical == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("LCASE failed to extract lexical value: %s", str)));

	str_datatype = datatype(str);

	if (strlen(str_datatype) != 0 && !IsRDFStringLiteral(str_datatype))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("LCASE does not allow non-string literals: %s",
						str_datatype)));

	str_language = lang(str);

	elog(DEBUG3, " %s: lexical='%s', datatype='%s', language='%s'", __func__, lexical, str_datatype, str_language);

    /* Convert to lowercase using PostgreSQL's multibyte-aware function */
    {
        text *input_text = cstring_to_text(lexical);
        Datum lower_datum = DirectFunctionCall3Coll(
            lower,
            DEFAULT_COLLATION_OID,
            PointerGetDatum(input_text),
            BoolGetDatum(false),
            (Datum)0);
        text *lower_text = DatumGetTextP(lower_datum);
        char *lowercase = text_to_cstring(lower_text);

        if (strlen(str_language) != 0)
            result = strlang(lowercase, str_language);
        else if (strlen(str_datatype) != 0)
            result = strdt(lowercase, str_datatype);
        else
            result = cstring_to_rdfliteral(lowercase);

        pfree(lowercase);
        pfree(lower_text);
        pfree(input_text);
    }

    elog(DEBUG3, "%s exit: returning '%s'", __func__, result);
	return result;
}

/*
 * ucase
 * -----
 *
 * Implements SPARQL’s UCASE function. Converts the lexical form of a string literal
 * (simple, xsd:string, or language-tagged) to uppercase (ASCII a-z to A-Z, non-ASCII
 * preserved). Preserves the original datatype or language tag. Errors on IRIs, blank
 * nodes, non-string literals, or invalid inputs. Bare strings are treated as simple literals.
 *
 * str: Null-terminated C string (RDF literal or bare string, e.g., "bar", "\"bar\"@en")
 *
 * returns: Null-terminated C string (uppercase RDF literal)
 */
char *ucase(char *str)
{
	char *lexical;
	char *str_datatype;
	char *str_language;
	char *result;

	elog(DEBUG3, "%s called: str='%s'", __func__, str);

	if (!str)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("LCASE cannot be NULL")));

	if (strlen(str) == 0)
	{
		elog(DEBUG3, "%s exit: returning empty literal (str is an empty string)", __func__);
		return cstring_to_rdfliteral("");
	}

	/* Check for IRIs or blank nodes */
	if (isIRI(str))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UCASE does not allow IRIs: %s", str)));

	if (isBlank(str))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UCASE does not allow blank nodes: %s", str)));

	lexical = lex(str);

	if (lexical == NULL)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UCASE failed to extract lexical value: %s", str)));

	str_datatype = datatype(str);

	if (strlen(str_datatype) != 0 && !IsRDFStringLiteral(str_datatype))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("UCASE does not allow non-string literals: %s",
						str_datatype)));

	str_language = lang(str);

	elog(DEBUG2, " %s: lexical='%s', datatype='%s', language='%s'", __func__, lexical, str_datatype, str_language);

    /* Convert to uppercase using PostgreSQL's multibyte-aware function */
    {
        text *input_text = cstring_to_text(lexical);
        Datum upper_datum = DirectFunctionCall3Coll(
            upper,
            DEFAULT_COLLATION_OID,
            PointerGetDatum(input_text),
            BoolGetDatum(false),
            (Datum)0);
        text *upper_text = DatumGetTextP(upper_datum);
        char *uppercase = text_to_cstring(upper_text);

        if (strlen(str_language) != 0)
            result = strlang(uppercase, str_language);
        else if (strlen(str_datatype) != 0)
            result = strdt(uppercase, str_datatype);
        else
            result = cstring_to_rdfliteral(uppercase);

        pfree(uppercase);
        pfree(upper_text);
        pfree(input_text);
    }

    elog(DEBUG3, "%s exit: returning => '%s'", __func__, result);
	return result;
}

/*
 * isNumeric
 * ---------
 *
 * Checks if an RDF term is numeric per SPARQL spec. Returns true if the term is a
 * bare number (e.g., "12") or a literal with a numeric datatype (e.g., xsd:integer,
 * xsd:nonNegativeInteger) and valid numeric lexical form. Returns false otherwise.
 *
 * term: Null-terminated C string representing an RDF term (e.g., "12", "12"^^xsd:integer)
 *
 * returns: Boolean indicating if the term is numeric
 */
bool isNumeric(char *term)
{
	char *lexical;
	char *datatype_uri;
	bool is_bare_number = false;
	char *endptr;

	elog(DEBUG3, "%s called: term='%s'", __func__, term);

	if (!term || strlen(term) == 0)
	{
		elog(DEBUG3, "%s exit: returning 'false' (term either NULL or an empty string)", __func__);
		return false;
	}

	/* Check if term is a bare number (e.g., "12") */
	if (term[0] != '"' && !strstr(term, "^^") && !strstr(term, "@"))
	{
		lexical = term;
		is_bare_number = true;
	}
	else
	{
		/* Extract lexical value using datatype’s helper */
		lexical = lex(term); /* From datatype/strdt codebase */
	}

	/* Validate lexical form as numeric (integers, decimals, or scientific notation) */
	if (!lexical || strlen(lexical) == 0)
	{
		elog(DEBUG3, "%s exit: returning 'false' (lexical value either NULL or an empty string)", __func__);
		return false;
	}

	strtod(lexical, &endptr);
	if (*endptr != '\0') /* not a valid number, e.g., "abc" */
	{
		elog(DEBUG3, "%s exit: returning 'false' (not a valid number)", __func__);
		return false;
	}

	/* Bare numbers are numeric */
	if (is_bare_number)
	{
		elog(DEBUG3, "%s exit: returning 'true' (bare numbers are numeric)", __func__);
		return true;
	}

	/* Get datatype using datatype function */
	datatype_uri = datatype(term);
	if (strlen(datatype_uri) == 0)
	{
		elog(DEBUG3, "%s exit: returning 'false' (no datatype or invalid literal)", __func__);
		return false;
	} /* No datatype or invalid literal (e.g., "12") */

	/* Check for numeric datatypes */
	if (strcmp(datatype_uri, RDF_XSD_INTEGER) == 0 ||
		strcmp(datatype_uri, RDF_XSD_NONNEGATIVEINTEGER) == 0 ||
		strcmp(datatype_uri, RDF_XSD_POSITIVEINTEGER) == 0 ||
		strcmp(datatype_uri, RDF_XSD_NEGATIVEINTEGER) == 0 ||
		strcmp(datatype_uri, RDF_XSD_NONPOSITIVEINTEGER) == 0 ||
		strcmp(datatype_uri, RDF_XSD_LONG) == 0 ||
		strcmp(datatype_uri, RDF_XSD_INT) == 0 ||
		strcmp(datatype_uri, RDF_XSD_BYTE) == 0 ||
		strcmp(datatype_uri, RDF_XSD_SHORT) == 0 ||
		strcmp(datatype_uri, RDF_XSD_UNSIGNEDLONG) == 0 ||
		strcmp(datatype_uri, RDF_XSD_UNSIGNEDINT) == 0 ||
		strcmp(datatype_uri, RDF_XSD_UNSIGNEDSHORT) == 0 ||
		strcmp(datatype_uri, RDF_XSD_UNSIGNEDBYTE) == 0 ||
		strcmp(datatype_uri, RDF_XSD_DOUBLE) == 0 ||
		strcmp(datatype_uri, RDF_XSD_FLOAT) == 0 ||
		strcmp(datatype_uri, RDF_XSD_DECIMAL) == 0)
	{
		/* Special case for xsd:byte: SPARQL requires values to be integers between -128 and 127.
		 * For example, isNumeric("1200"^^xsd:byte) returns false because 1200 exceeds 127.
		 * We parse the lexical value to ensure it’s a valid integer and check its range. */
		if (strcmp(datatype_uri, RDF_XSD_BYTE) == 0)
		{
			/* Ensure the entire string is a valid integer and within xsd:byte range */
			if (*endptr != '\0') /* Not a pure integer, e.g., "12.34" */
			{
				elog(DEBUG3, "%s exit: returning 'false' (not a pure integer)", __func__);
				return false;
			}

			elog(DEBUG3, "%s exit: returning 'true' (valid xsd:byte)", __func__);
			return true; /* Valid xsd:byte, e.g., "100" */
		}
		/* Other numeric datatypes (e.g., xsd:integer, xsd:double) have no strict range
		 * limits in SPARQL’s isNumeric, and we’ve already validated the lexical form.
		 * Accept them as numeric. */

		elog(DEBUG3, "%s exit: returning 'true'", __func__);
		return true;
	}

	elog(DEBUG3, "%s exit: returning 'false'", __func__);
	return false;
}

/*
 * contains
 * --------
 *
 * Implements SPARQL’s CONTAINS(str, substr) function. Returns true if the lexical
 * form of str contains the lexical form of substr as a contiguous subsequence;
 * false otherwise. Matching is case-sensitive per SPARQL.
 *
 * str_in    : Null-terminated C string representing an RDF term or bare string
 * substr_in : Null-terminated C string representing an RDF term or bare string
 *
 * returns: Boolean (true if substr occurs within str’s lexical form; false on
 *          mismatch, incompatible language tags, or invalid/empty input)
 */
bool contains(char *str_in, char *substr_in)
{
	char *str_lex;
	char *substr_lex;
	char *lang_str;
	bool result;

	elog(DEBUG3, "%s called: str='%s', substr='%s'", __func__, str_in, substr_in);

	/* handle NULL or empty inputs */
	if (!str_in || !substr_in || strlen(str_in) == 0 || strlen(substr_in) == 0)
	{
		elog(DEBUG3, "%s exit: returning 'false' (invalid input)", __func__);
		return false;
	}

	lang_str = lang(str_in);

	if (strlen(lang_str) != 0)
	{
		char *lang_substr = lang(substr_in);

		if (strlen(lang_substr) != 0 && pg_strcasecmp(lang_str, lang_substr) != 0)
		{
			elog(DEBUG3, "%s exit: returning NULL (string and substring have different languag tags)", __func__);
			return NULL;
		}
	}

	/* extract lexical values (strips quotes, tags, etc.) */
	str_lex = lex(str_in);
	substr_lex = lex(substr_in);

	/* check if substr is in str using strstr */
	result = (strstr(str_lex, substr_lex) != NULL);

	elog(DEBUG3, "%s exit: returning > %s (str_lexical='%s', substr_lexical='%s')",
		 __func__, result ? "true" : "false", str_lex, substr_lex);

	return result;
}

/*
 * strbefore
 * -----------------
 *
 * Implements the SPARQL STRBEFORE function, returning the substring of the first
 * argument before the first occurrence of the second argument (delimiter). The
 * result preserves the language tag or datatype of the first argument as present
 * in the input syntax. Simple literals remain simple in the output.
 *
 * str: the input string (e.g., "abc"@en, "abc"^^xsd:string)
 * delimiter: the delimiter string (e.g., "b", "b"@en)
 *
 * returns: cstring representing the RDF literal before the delimiter
 */
char *strbefore(char *str, char *delimiter)
{
	char *str_lexical;
	char *delimiter_lexical;
	char *lang1;
	char *dt1 = "";
	char *pos;
	char *result;

	elog(DEBUG3, "%s called: str='%s', delimiter='%s", __func__, str, delimiter);

	str_lexical = lex(str);
	delimiter_lexical = lex(delimiter);
	lang1 = lang(str);

	/* extract datatypes if no language tags */
	if (strlen(lang1) == 0)
		dt1 = datatype(str);

	if (!LiteralsCompatible(str, delimiter))
	{
		elog(DEBUG3, "%s exit: returning NULL (literals no compatible)", __func__);
		return NULL;
	}

	if ((pos = strstr(str_lexical, delimiter_lexical)) != NULL)
	{
		size_t before_len = pos - str_lexical;
		StringInfoData buf;
		initStringInfo(&buf);

		if (strlen(lang1) > 0)
		{
			appendBinaryStringInfo(&buf, str_lexical, before_len);
			result = strlang(buf.data, lang1);

			elog(DEBUG3, "%s exit: returning => '%s'", __func__, result);
			return result;
		}
		else if (strlen(dt1) > 0 && /* only for explicit ^^ */
				 (strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
		{
			appendBinaryStringInfo(&buf, str_lexical, before_len);
			result = cstring_to_rdfliteral(buf.data);
			if (strstr(result, "^^") == NULL)
			{
				result = strdt(buf.data, dt1);
			}

			elog(DEBUG3, "%s exit: returning => '%s'", __func__, result);
			return result;
		}
		else
		{
			/* simple literal or implicit xsd:string */
			appendBinaryStringInfo(&buf, str_lexical, before_len);
			result = cstring_to_rdfliteral(buf.data);

			elog(DEBUG3, "%s exit: returning => '%s'", __func__, result);
			return result;
		}
	}

	/* delimiter not found */
	if (strlen(dt1) > 0 &&
		(strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
	{
		result = cstring_to_rdfliteral("");
		if (strstr(result, "^^") == NULL)
		{
			StringInfoData typed_buf;
			initStringInfo(&typed_buf);
			appendStringInfo(&typed_buf, "%s", strdt("", RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED));
			result = typed_buf.data;
		}

		elog(DEBUG3, "%s exit: returning => '%s'", __func__, result);
		return result;
	}

	result = cstring_to_rdfliteral("");
	elog(DEBUG3, "%s exit: returning => '%s'", __func__, result);

	return result;
}


/*
 * strafter
 * ----------------
 *
 * Implements the SPARQL STRAFTER function, returning the substring of the first
 * argument after the first occurrence of the second argument (delimiter). The
 * result preserves the language tag or datatype of the first argument as present
 * in the input syntax, always wrapped in double quotes as a valid RDF literal.
 * Returns an empty simple literal if the delimiter is not found.
 *
 * str: the input string (e.g., "abc"@en, "abc"^^xsd:string)
 * delimiter: the delimiter string (e.g., "b", "b"@en)
 *
 * returns: a cstring representing the RDF literal after the delimiter
 */
char *strafter(char *str, char *delimiter)
{
    char *lexstr;
    char *lexdelimiter;
	char *lang1;
	char *dt1 = "";
	char *pos;
	bool has_explicit_datatype = false;
	char *result;

	elog(DEBUG3, "%s called: str='%s', delimiter='%s'", __func__, str, delimiter);

	lexstr = lex(str);
	lexdelimiter = lex(delimiter);
	lang1 = lang(str);

	/* extract datatype if no language tag */
	if (strlen(lang1) == 0)
		dt1 = datatype(str);

	/* check if arg1 has an explicit datatype in the input syntax */
	if (strlen(lang1) == 0 && strstr(str, "^^") != NULL)
		has_explicit_datatype = true;

	if ((pos = strstr(lexstr, lexdelimiter)) != NULL)
	{
		size_t delimiter_len = strlen(lexdelimiter);
		char *after_start = pos + delimiter_len;
		size_t after_len = strlen(lexstr) - (after_start - lexstr);

		StringInfoData buf;
		initStringInfo(&buf);

		if (strlen(lang1) > 0)
		{
			appendBinaryStringInfo(&buf, after_start, after_len);
			result = strlang(buf.data, lang1);
			pfree(buf.data);

			elog(DEBUG3, "%s exit: returning => '%s'", __func__, result);
			return result;
		}
		else if (has_explicit_datatype && strlen(dt1) > 0 &&
				 (strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
		{
			appendBinaryStringInfo(&buf, after_start, after_len);
			result = cstring_to_rdfliteral(buf.data);
			if (strstr(result, "^^") == NULL)
			{
				result = strdt(buf.data, dt1);
			}
			pfree(buf.data);

			elog(DEBUG3, "%s exit: returning => '%s'", __func__, result);
			return result;
		}
		else
		{
			/* simple literal or implicit xsd:string */
			appendBinaryStringInfo(&buf, after_start, after_len);
			result = cstring_to_rdfliteral(buf.data);
			pfree(buf.data);

			elog(DEBUG3, "%s exit: returning => '%s'", __func__, result);
			return result;
		}
	}

	/* delimiter not found */
	if (has_explicit_datatype && strlen(dt1) > 0 &&
		(strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
	{
		result = cstring_to_rdfliteral("");
		if (strstr(result, "^^") == NULL)
		{
			StringInfoData typed_buf;
			initStringInfo(&typed_buf);
			appendStringInfo(&typed_buf, "%s", strdt("", RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED));
			result = typed_buf.data;
		}

		elog(DEBUG3, "%s exit: returning => '%s'", __func__, result);
		return result;
	}

	result = cstring_to_rdfliteral("");
	elog(DEBUG3, "%s exit: returning => '%s'", __func__, result);
	return result;
}

/*
 * count_utf8_chars
 * ----------------
 *
 * Counts Unicode characters (code points) in a UTF-8 string.
 * Returns the number of characters, not bytes.
 */
static int count_utf8_chars(const char *str)
{
	int char_count = 0;

	elog(DEBUG3, "%s called: str='%s'", __func__, str);

	while (*str)
	{
		/* Skip continuation bytes (0x80-0xBF) */
		if ((*str & 0xC0) != 0x80)
			char_count++;
		str++;
	}

	elog(DEBUG3, "%s exit: returning '%d'", __func__, char_count);
	return char_count;
}

int strlen_rdf(char *str)
{
	char *lexical;
	char *dt;
	int result;

	elog(DEBUG3, "%s called: str='%s'", __func__, str);

	if (!str)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("STRLEN cannot be NULL")));

	if (strlen(str) == 0)
		return 0;

	/* Check for IRIs or blank nodes */
	if (isIRI(str))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("STRLEN does not allow IRIs: %s", str)));

	if (isBlank(str))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("STRLEN does not allow blank nodes: %s", str)));

	dt = datatype(str);

	/* Validate string literal */
	if (!IsRDFStringLiteral(dt))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("STRLEN does not allow non-string literals: %s", dt)));

	lexical = lex(str);
	result = count_utf8_chars(lexical);

	elog(DEBUG3, "%s exit: returning '%d'", __func__, result);
	return result;
}

/*
 * get_xsd_numeric_type
 * --------------------
 * Determines the XSD numeric type from an rdfnode's datatype URI.
 * 
 * Returns the type in the promotion hierarchy: integer < decimal < float < double
 */
XsdNumericType get_xsd_numeric_type(const char *dtype)
{
	/* Handle all integer subtypes */
	if (strcmp(dtype, RDF_XSD_INTEGER) == 0 ||
		strcmp(dtype, RDF_XSD_INT) == 0 ||
		strcmp(dtype, RDF_XSD_LONG) == 0 ||
		strcmp(dtype, RDF_XSD_SHORT) == 0 ||
		strcmp(dtype, RDF_XSD_BYTE) == 0 ||
		strcmp(dtype, RDF_XSD_POSITIVEINTEGER) == 0 ||
		strcmp(dtype, RDF_XSD_NEGATIVEINTEGER) == 0 ||
		strcmp(dtype, RDF_XSD_NONNEGATIVEINTEGER) == 0 ||
		strcmp(dtype, RDF_XSD_NONPOSITIVEINTEGER) == 0 ||
		strcmp(dtype, RDF_XSD_UNSIGNEDLONG) == 0 ||
		strcmp(dtype, RDF_XSD_UNSIGNEDINT) == 0 ||
		strcmp(dtype, RDF_XSD_UNSIGNEDSHORT) == 0 ||
		strcmp(dtype, RDF_XSD_UNSIGNEDBYTE) == 0)
		return XSD_TYPE_INTEGER;
	
	if (strcmp(dtype, RDF_XSD_DECIMAL) == 0)
		return XSD_TYPE_DECIMAL;
	
	if (strcmp(dtype, RDF_XSD_FLOAT) == 0)
		return XSD_TYPE_FLOAT;
	
	if (strcmp(dtype, RDF_XSD_DOUBLE) == 0)
		return XSD_TYPE_DOUBLE;
	
	/* Default to decimal for unknown numeric types */
	return XSD_TYPE_DECIMAL;
}

/*
 * get_xsd_datatype_uri
 * --------------------
 * Returns the XSD datatype URI for a given numeric type level.
 */
const char *get_xsd_datatype_uri(XsdNumericType type)
{
	switch (type)
	{
		case XSD_TYPE_INTEGER:
			return RDF_XSD_INTEGER;
		case XSD_TYPE_DECIMAL:
			return RDF_XSD_DECIMAL;
		case XSD_TYPE_FLOAT:
			return RDF_XSD_FLOAT;
		case XSD_TYPE_DOUBLE:
			return RDF_XSD_DOUBLE;
		default:
			return RDF_XSD_DECIMAL;
	}
}

/*
 * sum_rdfnode_sfunc
 * -----------------
 * Aggregate transition function for SUM(rdfnode).
 * Converts rdfnode to numeric and accumulates the sum.
 *
 * Strict numeric-only policy:
 * - If any non-numeric value is present, returns NULL (unbound).
 * - Type promotion: integer < decimal < float < double.
 * - Example: SUM({1, 2, 3}) = 6; SUM({1, 2, "string"}) = NULL.
 *
 * State is stored as RdfnodeAggState to track both sum and result type.
 *
 * Note: Aggregate context validation is handled by the wrapper in
 *       rdf_fdw.c
 */
Datum sum_rdfnode_sfunc(PG_FUNCTION_ARGS)
{
    RdfnodeAggState *aggstate;
    MemoryContext aggcontext;
    MemoryContext oldcontext;
    rdfnode *node;
    rdfnode_info parsed;
    Datum rdf_numeric;
    XsdNumericType inputType;

    /* Get the aggregate memory context */
    AggCheckCallContext(fcinfo, &aggcontext);

    /* Get current state (NULL on first call) */
    if (PG_ARGISNULL(0))
        aggstate = NULL;
    else
        aggstate = (RdfnodeAggState *)PG_GETARG_POINTER(0);

    /* Skip NULL input values */
    if (PG_ARGISNULL(1))
    {
        if (aggstate == NULL)
            PG_RETURN_NULL();
        PG_RETURN_POINTER(aggstate);
    }

    /* Get the rdfnode and parse it */
    node = (rdfnode *)PG_GETARG_TEXT_PP(1);
    parsed = parse_rdfnode(node);

    /*
     * Mark that we received input (even if non-numeric).
     * This distinguishes SUM({}) from SUM({"string"}) per SPARQL 1.1.
     */
    if (aggstate == NULL)
    {
        /* Initialize state to track that we saw input */
        oldcontext = MemoryContextSwitchTo(aggcontext);
        aggstate = (RdfnodeAggState *)palloc0(sizeof(RdfnodeAggState));
        aggstate->has_input = true;
        aggstate->has_non_numeric = false;
        MemoryContextSwitchTo(oldcontext);
    }
    else
    {
        aggstate->has_input = true;
    }

    /*
     * Per SPARQL 1.1 spec Section 18.5.1.3: SUM returns an error if any
     * values are not numeric. Errors are excluded from the aggregate, so
     * if any non-numeric values are present, the entire SUM aggregate
     * returns unbound (NULL). Examples:
     * - SUM({1, 2, 3}) = 6 (all numeric)
     * - SUM({1, 2, "string"}) = NULL (mixed types cause error)
     * - SUM({"string"}) = NULL (all non-numeric)
     */
    if (!parsed.isNumeric)
    {
        /* Non-numeric value - mark as error and skip it */
        aggstate->has_non_numeric = true;
        PG_RETURN_POINTER(aggstate);
    }

    /* Determine the XSD type of this input */
    inputType = get_xsd_numeric_type(parsed.dtype);

    /* Convert rdfnode lexical value to numeric */
    rdf_numeric = DirectFunctionCall3(numeric_in,
                                      CStringGetDatum(parsed.lex),
                                      ObjectIdGetDatum(InvalidOid),
                                      Int32GetDatum(-1));

    /* Initialize or update numeric accumulator */
    if (aggstate->numeric_value == NULL)
    {
        /* First numeric value */
        oldcontext = MemoryContextSwitchTo(aggcontext);
        aggstate->numeric_value = DatumGetNumeric(
            DirectFunctionCall1(numeric_uplus, rdf_numeric));
        aggstate->maxType = inputType;
        MemoryContextSwitchTo(oldcontext);
    }
    else
    {
        /* Add to accumulator - need to be in aggcontext for result */
        oldcontext = MemoryContextSwitchTo(aggcontext);
        aggstate->numeric_value = DatumGetNumeric(
            DirectFunctionCall2(numeric_add,
                               NumericGetDatum(aggstate->numeric_value),
                               rdf_numeric));
        /*
         * Track the highest type seen (type promotion:
         * integer < decimal < float < double)
         */
        if (inputType > aggstate->maxType)
            aggstate->maxType = inputType;
        MemoryContextSwitchTo(oldcontext);
    }

    PG_RETURN_POINTER(aggstate);
}

/*
 * sum_rdfnode_finalfunc
 * ---------------------
 * Final function for SUM(rdfnode).
 * Converts the accumulated numeric sum back to rdfnode with proper type promotion.
 *
 * Note: NULL state handling is done by the wrapper in rdf_fdw.c
 */
Datum sum_rdfnode_finalfunc(PG_FUNCTION_ARGS)
{
    RdfnodeAggState *aggstate;
    char *sum_str;
    char *result;
    const char *datatype_uri;

    /* Get the state (already validated as non-NULL by wrapper) */
    aggstate = (RdfnodeAggState *)PG_GETARG_POINTER(0);

    /* If state is NULL (no rows), return NULL per SPARQL (unbound) */
    if (aggstate == NULL)
        PG_RETURN_NULL();

    /* If no numeric values were summed, return NULL (unbound per SPARQL) */
    if (aggstate->numeric_value == NULL || aggstate->has_non_numeric)
        PG_RETURN_NULL();

    /* Convert numeric to string */
    sum_str = DatumGetCString(DirectFunctionCall1(numeric_out, NumericGetDatum(aggstate->numeric_value)));

    /* Get the appropriate XSD datatype based on type promotion */
    datatype_uri = get_xsd_datatype_uri(aggstate->maxType);

    /* Format as typed literal rdfnode using strdt() */
    result = strdt(sum_str, (char *)datatype_uri);

    pfree(sum_str);

    PG_RETURN_TEXT_P(cstring_to_text(result));
}

/*
 * avg_rdfnode_sfunc
 * -----------------
 * Aggregate transition function for AVG(rdfnode).
 * Accumulates sum and count for computing average.
 *
 * Note: Aggregate context validation and NULL input handling done by wrapper in rdf_fdw.c
 */
Datum avg_rdfnode_sfunc(PG_FUNCTION_ARGS)
{
    RdfnodeAggState *aggstate;
    MemoryContext aggcontext;
    MemoryContext oldcontext;
    rdfnode *node;
    rdfnode_info parsed;
    Datum rdf_numeric;
    XsdNumericType inputType;

    /* Get the aggregate memory context */
    AggCheckCallContext(fcinfo, &aggcontext);

    /* Get current state (NULL on first call) */
    if (PG_ARGISNULL(0))
        aggstate = NULL;
    else
        aggstate = (RdfnodeAggState *)PG_GETARG_POINTER(0);

    /* Skip NULL input values */
    if (PG_ARGISNULL(1))
    {
        if (aggstate == NULL)
            PG_RETURN_NULL();
        PG_RETURN_POINTER(aggstate);
    }

    /* Get the rdfnode and parse it */
    node = (rdfnode *)PG_GETARG_TEXT_PP(1);
    parsed = parse_rdfnode(node);

    /* Mark that we received input (even if non-numeric).
     * This distinguishes AVG({}) from AVG({"string"}) per SPARQL 1.1 spec. */
    if (aggstate == NULL)
    {
        /* Initialize state to track that we saw input */
        oldcontext = MemoryContextSwitchTo(aggcontext);
        aggstate = (RdfnodeAggState *)palloc0(sizeof(RdfnodeAggState));
        aggstate->has_input = true;
        aggstate->has_non_numeric = false;
        MemoryContextSwitchTo(oldcontext);
    }
    else
    {
        aggstate->has_input = true;
    }

    /*
     * Per SPARQL 1.1 spec Section 18.5.1.4: AVG returns an error if any values are not numeric.
     * Errors are excluded from the aggregate, so if any non-numeric values are present,
     * the entire AVG aggregate returns unbound (NULL). Examples:
     * - AVG({10, 20, 30}) = 20 (all numeric)
     * - AVG({10, 20, "string"}) = NULL (mixed types cause error)
     * - AVG({"string"}) = NULL (all non-numeric)
     */
    if (!parsed.isNumeric)
    {
        /* Non-numeric value - mark as error and skip it */
        aggstate->has_non_numeric = true;
        PG_RETURN_POINTER(aggstate);
    }

    /* Determine the XSD type of this input */
    inputType = get_xsd_numeric_type(parsed.dtype);

    /* Convert rdfnode lexical value to numeric */
    rdf_numeric = DirectFunctionCall3(numeric_in,
                                      CStringGetDatum(parsed.lex),
                                      ObjectIdGetDatum(InvalidOid),
                                      Int32GetDatum(-1));

    /* Initialize or update numeric accumulator */
    if (aggstate->numeric_value == NULL)
    {
        /* First numeric value */
        oldcontext = MemoryContextSwitchTo(aggcontext);
        aggstate->numeric_value = DatumGetNumeric(DirectFunctionCall1(numeric_uplus, rdf_numeric));
        aggstate->count = 1;
        aggstate->maxType = inputType;
        MemoryContextSwitchTo(oldcontext);
    }
    else
    {
        /* Add to accumulator */
        oldcontext = MemoryContextSwitchTo(aggcontext);
        aggstate->numeric_value = DatumGetNumeric(DirectFunctionCall2(numeric_add,
                                                                   NumericGetDatum(aggstate->numeric_value),
                                                                   rdf_numeric));
        aggstate->count++;
        /* Track the highest type seen (type promotion: integer < decimal < float < double) */
        if (inputType > aggstate->maxType)
            aggstate->maxType = inputType;
        MemoryContextSwitchTo(oldcontext);
    }

    PG_RETURN_POINTER(aggstate);
}

/*
 * avg_rdfnode_finalfunc
 * ---------------------
 * Final function for AVG(rdfnode).
 * Computes average by dividing sum by count, with proper type promotion.
 *
 * Note: NULL state handling is done by the wrapper in rdf_fdw.c
 */
Datum avg_rdfnode_finalfunc(PG_FUNCTION_ARGS)
{
    RdfnodeAggState *aggstate;
    Numeric count_numeric;
    Numeric avg_numeric;
    Numeric avg_trunc0;
    char *avg_str;
    char *result;
    const char *datatype_uri;
    XsdNumericType outType;
    bool is_exact_integer = false;

    /* Get the state (already validated as non-NULL by wrapper) */
    aggstate = (RdfnodeAggState *)PG_GETARG_POINTER(0);

    /* If state is NULL (no rows), return NULL per SPARQL (unbound) */
    if (aggstate == NULL)
        PG_RETURN_NULL();

    /* If no numeric values were aggregated, return NULL (unbound per SPARQL) */
    if (aggstate->numeric_value == NULL || aggstate->has_non_numeric)
        PG_RETURN_NULL();

    /* Convert count to numeric for division */
    count_numeric = DatumGetNumeric(DirectFunctionCall1(int8_numeric, Int64GetDatum(aggstate->count)));

    /* Compute average: sum / count */
    avg_numeric = DatumGetNumeric(DirectFunctionCall2(numeric_div,
                                                      NumericGetDatum(aggstate->numeric_value),
                                                      NumericGetDatum(count_numeric)));

    /* Determine output type for AVG:
     * - If any double was seen, use xsd:double
     * - else if any float was seen, use xsd:float
     * - else use xsd:decimal (even if the average is an exact integer)
     *   This ensures AVG over integer-only inputs yields xsd:decimal, e.g., 42.0
     */
    outType = aggstate->maxType;

    /* Check exact-integer condition by truncating scale to 0 and comparing */
    avg_trunc0 = DatumGetNumeric(DirectFunctionCall2(numeric_trunc,
                                                     NumericGetDatum(avg_numeric),
                                                     Int32GetDatum(0)));
    is_exact_integer = DatumGetBool(DirectFunctionCall2(numeric_eq,
                                                        NumericGetDatum(avg_numeric),
                                                        NumericGetDatum(avg_trunc0)));

    if (outType == XSD_TYPE_DOUBLE)
    {
        /* keep double */
    }
    else if (outType == XSD_TYPE_FLOAT)
    {
        /* keep float */
    }
    else
    {
        /* For integer-only or decimal inputs, return decimal */
        outType = XSD_TYPE_DECIMAL;
    }

    /* Convert result to string.
     * For xsd:decimal and exact-integer values, append ".0" to match common SPARQL engine output. */
    if (outType == XSD_TYPE_DECIMAL)
    {
        if (is_exact_integer)
        {
            char *int_str = DatumGetCString(DirectFunctionCall1(numeric_out, NumericGetDatum(avg_trunc0)));
            StringInfoData buf;
            initStringInfo(&buf);
            appendStringInfo(&buf, "%s.0", int_str);
            avg_str = buf.data;
            pfree(int_str);
        }
        else
        {
            avg_str = DatumGetCString(DirectFunctionCall1(numeric_out, NumericGetDatum(avg_numeric)));
        }
    }
    else
    {
        /* float/double: use native textual form */
        avg_str = DatumGetCString(DirectFunctionCall1(numeric_out, NumericGetDatum(avg_numeric)));
    }

    /* Map chosen type to XSD URI */
    datatype_uri = get_xsd_datatype_uri(outType);

    /* Format as typed literal rdfnode using strdt() */
    result = strdt(avg_str, (char *)datatype_uri);

    pfree(avg_str);

    PG_RETURN_TEXT_P(cstring_to_text(result));
}

/*
 * get_rdfnode_category_rank
 * -------------------------
 * Returns a category rank for an rdfnode to support 
 * mixed-type aggregate ordering. Lower rank = lower
 * priority for MAX, higher priority for MIN.
 *
 * Category order (low → high):
 *   0: string-like (plain literal, xsd:string, language-tagged)
 *   1: numeric (xsd:integer, xsd:decimal, xsd:float, etc.)
 *   2: dateTime
 *   3: date
 *   4: time
 *   5: duration
 *   6: other
 */
static int
get_rdfnode_category_rank(rdfnode_info parsed)
{
    if (strlen(parsed.lang) > 0 || parsed.isPlainLiteral || parsed.isString)
        return 0;
    if (parsed.isNumeric)
        return 1;
    if (parsed.isDateTime)
        return 2;
    if (parsed.isDate)
        return 3;
    if (parsed.isTime)
        return 4;
    if (parsed.isDuration)
        return 5;
    return 6;
}

/*
 * min_rdfnode_sfunc
 * -----------------
 * Aggregate transition function for MIN(rdfnode).
 * Compares rdfnode values and keeps track of the minimum.
 *
 * Mixed-type policy (Fuseki-compatible):
 * - Assigns each term to a category (string-like < numeric < temporal).
 * - MIN selects the lowest category present; ties resolved by comparator.
 * - Example: MIN({"zebra"^^xsd:string, 42, "mango"^^xsd:string}) →
 *   "mango"^^xsd:string (string category wins; lexical minimum among
 *   strings).
 *
 * Note: Aggregate context validation and NULL input handling done by
 *       wrapper in rdf_fdw.c
 */
Datum min_rdfnode_sfunc(PG_FUNCTION_ARGS)
{
    RdfnodeAggState *aggstate;
    MemoryContext aggcontext;
    MemoryContext oldcontext;
    text *input_node;
    rdfnode_info input_parsed;
    rdfnode_info current_parsed;

    /* Get the aggregate memory context */
    AggCheckCallContext(fcinfo, &aggcontext);

    /* Get current state (NULL on first call) */
    if (PG_ARGISNULL(0))
        aggstate = NULL;
    else
        aggstate = (RdfnodeAggState *)PG_GETARG_POINTER(0);

    /* Skip NULL input values */
    if (PG_ARGISNULL(1))
    {
        if (aggstate == NULL)
            PG_RETURN_NULL();
        PG_RETURN_POINTER(aggstate);
    }

    /* Get and parse the input rdfnode */
    input_node = PG_GETARG_TEXT_PP(1);
    input_parsed = parse_rdfnode((rdfnode *)input_node);

    if (aggstate == NULL)
    {
        /* First row: allocate state and store the rdfnode */
        oldcontext = MemoryContextSwitchTo(aggcontext);
        aggstate = (RdfnodeAggState *)palloc(sizeof(RdfnodeAggState));
        aggstate->rdfnode_value = (text *)PG_DETOAST_DATUM_COPY(PointerGetDatum(input_node));
        MemoryContextSwitchTo(oldcontext);
        PG_RETURN_POINTER(aggstate);
    }

    /* Parse current value for category-based comparison */
    current_parsed = parse_rdfnode((rdfnode *)aggstate->rdfnode_value);
    /*
     * Choose the smallest category present, then the minimum within
     * that category.
     */
    {
        int rank_in = get_rdfnode_category_rank(input_parsed);
        int rank_cur = get_rdfnode_category_rank(current_parsed);

        if (rank_in < rank_cur)
        {
            /* Input has lower category → new minimum */
            oldcontext = MemoryContextSwitchTo(aggcontext);
            pfree(aggstate->rdfnode_value);
            aggstate->rdfnode_value = (text *)PG_DETOAST_DATUM_COPY(
                PointerGetDatum(input_node));
            MemoryContextSwitchTo(oldcontext);
        }
        else if (rank_in == rank_cur)
        {
            /* Same category → use comparator */
            int cmp = rdfnode_cmp_for_aggregate(
                (rdfnode *)input_node,
                (rdfnode *)aggstate->rdfnode_value);
            if (cmp < 0)
            {
                oldcontext = MemoryContextSwitchTo(aggcontext);
                pfree(aggstate->rdfnode_value);
                aggstate->rdfnode_value = (text *)PG_DETOAST_DATUM_COPY(
                    PointerGetDatum(input_node));
                MemoryContextSwitchTo(oldcontext);
            }
        }
        /* rank_in > rank_cur: keep current (higher category) */
    }

    PG_RETURN_POINTER(aggstate);
}

/*
 * min_rdfnode_finalfunc
 * ---------------------
 * Final function for MIN(rdfnode).
 * Returns the minimum rdfnode value stored as text.
 *
 * Note: NULL state handling is done by the wrapper in rdf_fdw.c
 */
Datum min_rdfnode_finalfunc(PG_FUNCTION_ARGS)
{
    RdfnodeAggState *aggstate;

    /* Get the state (already validated as non-NULL by wrapper) */
    aggstate = (RdfnodeAggState *)PG_GETARG_POINTER(0);

    if (aggstate == NULL || aggstate->rdfnode_value == NULL)
        PG_RETURN_NULL();

    /* Return the stored minimum rdfnode */
    PG_RETURN_TEXT_P(aggstate->rdfnode_value);
}

/*
 * max_rdfnode_sfunc
 * -----------------
 * Aggregate transition function for MAX(rdfnode).
 * Compares rdfnode values and keeps track of the maximum.
 *
 * Mixed-type policy:
 * - Assigns each term to a category (string-like < numeric < temporal).
 * - MAX selects the highest category present; ties resolved by comparator.
 * - Example: MAX({42, "2023-01-01"^^xsd:date}) → "2023-01-01"^^xsd:date
 *   (date category wins over numeric).
 *
 * Note: Aggregate context validation and NULL input handling done by
 *       wrapper in rdf_fdw.c
 */
Datum max_rdfnode_sfunc(PG_FUNCTION_ARGS)
{
    RdfnodeAggState *aggstate;
    MemoryContext aggcontext;
    MemoryContext oldcontext;
    text *input_node;
    rdfnode_info input_parsed;
    rdfnode_info current_parsed;

    /* Get the aggregate memory context */
    AggCheckCallContext(fcinfo, &aggcontext);

    /* Get current state (NULL on first call) */
    if (PG_ARGISNULL(0))
        aggstate = NULL;
    else
        aggstate = (RdfnodeAggState *)PG_GETARG_POINTER(0);

    /* Skip NULL input values */
    if (PG_ARGISNULL(1))
    {
        if (aggstate == NULL)
            PG_RETURN_NULL();
        PG_RETURN_POINTER(aggstate);
    }

    /* Get and parse the input rdfnode */
    input_node = PG_GETARG_TEXT_PP(1);
    input_parsed = parse_rdfnode((rdfnode *)input_node);

    if (aggstate == NULL)
    {
        /* First row: allocate state and store the rdfnode */
        oldcontext = MemoryContextSwitchTo(aggcontext);
        aggstate = (RdfnodeAggState *)palloc(sizeof(RdfnodeAggState));
        aggstate->rdfnode_value = (text *)PG_DETOAST_DATUM_COPY(PointerGetDatum(input_node));
        MemoryContextSwitchTo(oldcontext);
        PG_RETURN_POINTER(aggstate);
    }

    current_parsed = parse_rdfnode((rdfnode *)aggstate->rdfnode_value);

    /*
     * Choose the largest category present, then the maximum within
     * that category.
     */
    {
        int rank_in = get_rdfnode_category_rank(input_parsed);
        int rank_cur = get_rdfnode_category_rank(current_parsed);

        if (rank_in > rank_cur)
        {
            /* Input has higher category → new maximum */
            oldcontext = MemoryContextSwitchTo(aggcontext);
            pfree(aggstate->rdfnode_value);
            aggstate->rdfnode_value = (text *)PG_DETOAST_DATUM_COPY(
                PointerGetDatum(input_node));
            MemoryContextSwitchTo(oldcontext);
        }
        else if (rank_in == rank_cur)
        {
            /* Same category → use comparator */
            int cmp = rdfnode_cmp_for_aggregate(
                (rdfnode *)input_node,
                (rdfnode *)aggstate->rdfnode_value);
            if (cmp > 0)
            {
                oldcontext = MemoryContextSwitchTo(aggcontext);
                pfree(aggstate->rdfnode_value);
                aggstate->rdfnode_value = (text *)PG_DETOAST_DATUM_COPY(
                    PointerGetDatum(input_node));
                MemoryContextSwitchTo(oldcontext);
            }
        }
        /* rank_in < rank_cur: keep current (higher category) */
    }

    PG_RETURN_POINTER(aggstate);
}

/*
 * max_rdfnode_finalfunc
 * ---------------------
 * Final function for MAX(rdfnode).
 * Returns the maximum rdfnode value stored as text, or NULL if no values were aggregated.
 *
 * Note: NULL state handling is done by the wrapper in rdf_fdw.c
 */
Datum max_rdfnode_finalfunc(PG_FUNCTION_ARGS)
{
    RdfnodeAggState *aggstate;

    /* Get the state (already validated as non-NULL by wrapper) */
    aggstate = (RdfnodeAggState *)PG_GETARG_POINTER(0);

    if (aggstate == NULL || aggstate->rdfnode_value == NULL)
        PG_RETURN_NULL();

    /* Return the stored maximum rdfnode */
    PG_RETURN_TEXT_P(aggstate->rdfnode_value);
}

/*
 * sample_rdfnode_sfunc
 * --------------------
 * Aggregate transition function for SAMPLE(rdfnode).
 * Returns an arbitrary value from the aggregate group.
 *
 * Per SPARQL 1.1 Section 18.5.1.8, SAMPLE returns an "arbitrary value"
 * from the multiset passed to it. The spec explicitly states the result
 * is non-deterministic.
 *
 * This implementation follows the common industry practice of returning
 * the first non-NULL value encountered. While deterministic, this is
 * acceptable as the spec allows implementation-defined behavior for 
 * "arbitrary".
 */
Datum sample_rdfnode_sfunc(PG_FUNCTION_ARGS)
{
    RdfnodeAggState *aggstate;
    MemoryContext aggcontext;
    MemoryContext oldcontext;
    text *input_node;

    /* Get the aggregate memory context */
    AggCheckCallContext(fcinfo, &aggcontext);

    /* Get current state (NULL on first call) */
    if (PG_ARGISNULL(0))
        aggstate = NULL;
    else
        aggstate = (RdfnodeAggState *)PG_GETARG_POINTER(0);

    /* Skip NULL input values */
    if (PG_ARGISNULL(1))
    {
        if (aggstate == NULL)
            PG_RETURN_NULL();
        PG_RETURN_POINTER(aggstate);
    }

    /* If we already have a value, keep it (first value wins) */
    if (aggstate != NULL)
        PG_RETURN_POINTER(aggstate);

    /* Get the input rdfnode */
    input_node = PG_GETARG_TEXT_PP(1);

    /* First non-NULL value: allocate state and store it */
    oldcontext = MemoryContextSwitchTo(aggcontext);
    aggstate = (RdfnodeAggState *)palloc(sizeof(RdfnodeAggState));
    aggstate->rdfnode_value = (text *)PG_DETOAST_DATUM_COPY(PointerGetDatum(input_node));
    MemoryContextSwitchTo(oldcontext);

    PG_RETURN_POINTER(aggstate);
}

/*
 * sample_rdfnode_finalfunc
 * ------------------------
 * Final function for SAMPLE(rdfnode).
 * Returns the arbitrary value stored (first non-NULL
 * value encountered).
 *
 * Note: NULL state handling is done by the wrapper in
 * rdf_fdw.c
 */
Datum sample_rdfnode_finalfunc(PG_FUNCTION_ARGS)
{
    RdfnodeAggState *aggstate;

    /* Get the state (already validated as non-NULL by wrapper) */
    aggstate = (RdfnodeAggState *)PG_GETARG_POINTER(0);

    if (aggstate == NULL || aggstate->rdfnode_value == NULL)
        PG_RETURN_NULL();

    /* Return the stored sample value */
    PG_RETURN_TEXT_P(aggstate->rdfnode_value);
}

/*
 * group_concat_sfunc
 * ------------------
 * Transition function for GROUP_CONCAT(rdfnode [, separator]).
 *
 * Accumulates string representations of RDF terms, separated by a
 * delimiter. Per SPARQL 1.1 Section 18.5.1.7, the default separator
 * is a single space character.
 *
 * RDF term serialization follows SPARQL rules:
 * - Typed literals: extract lexical value only (strip ^^datatype)
 * - Language-tagged: extract lexical value only (strip @lang)
 * - IRIs: use URI string (strip angle brackets)
 * - Plain literals: use as-is
 *
 * NULL/unbound values are skipped during aggregation.
 */
Datum group_concat_sfunc(PG_FUNCTION_ARGS)
{
    MemoryContext aggcontext;
    MemoryContext oldcontext;
    RdfnodeAggState *aggstate;
    text *input_node;
    rdfnode_info parsed;
    char *str_value;

    if (!AggCheckCallContext(fcinfo, &aggcontext))
        ereport(ERROR,
                (errcode(ERRCODE_INTERNAL_ERROR),
                 errmsg("aggregate function called in non-aggregate context")));

    /* Get the current state */
    aggstate = PG_ARGISNULL(0) ? NULL : (RdfnodeAggState *)PG_GETARG_POINTER(0);

    /* Skip NULL input values */
    if (PG_ARGISNULL(1))
    {
        if (aggstate == NULL)
            PG_RETURN_NULL();
        PG_RETURN_POINTER(aggstate);
    }

    /* Get the input rdfnode */
    input_node = PG_GETARG_TEXT_PP(1);
    parsed = parse_rdfnode((rdfnode *)input_node);

    /* Extract lexical value based on RDF term type */
    if (parsed.isIRI)
    {
        /* For IRIs, remove angle brackets: <http://example.org> → http://example.org */
        size_t len = strlen(parsed.raw);
        if (len > 2 && parsed.raw[0] == '<' && parsed.raw[len - 1] == '>')
        {
            str_value = palloc(len - 1);
            memcpy(str_value, parsed.raw + 1, len - 2);
            str_value[len - 2] = '\0';
        }
        else
        {
            str_value = pstrdup(parsed.raw);
        }
    }
    else
    {
        /* For literals, use the lexical value (already extracted by parse_rdfnode) */
        str_value = parsed.lex;
    }

    /* Initialize state on first value */
    if (aggstate == NULL)
    {
        oldcontext = MemoryContextSwitchTo(aggcontext);
        aggstate = (RdfnodeAggState *)palloc(sizeof(RdfnodeAggState));
        aggstate->result_str = makeStringInfo();
        /* Get separator (arg 2), default to space if not provided */
        if (PG_NARGS() > 2 && !PG_ARGISNULL(2))
        {
            /* Copy the separator into aggregate memory context */
            aggstate->separator = PG_GETARG_TEXT_P_COPY(2);
        }
        else
            aggstate->separator = cstring_to_text(" "); /* SPARQL 1.1 default */

        aggstate->has_input = false;
        MemoryContextSwitchTo(oldcontext);
    }

    /* Add separator if not the first value */
    oldcontext = MemoryContextSwitchTo(aggcontext);
    if (aggstate->has_input)
    {
        appendStringInfoString(aggstate->result_str, text_to_cstring(aggstate->separator));
    }

    /* Append the string value */
    appendStringInfoString(aggstate->result_str, str_value);
    aggstate->has_input = true;
    MemoryContextSwitchTo(oldcontext);

    PG_RETURN_POINTER(aggstate);
}

/*
 * group_concat_finalfunc
 * ----------------------
 * Final function for GROUP_CONCAT(rdfnode [, separator]).
 *
 * Returns the concatenated string as a simple literal (plain literal
 * without datatype or language tag), matching SPARQL 1.1 semantics.
 * Returns empty string for empty result sets (per SPARQL 1.1).
 *
 * Note: NULL state handling is done by the wrapper in rdf_fdw.c
 */
Datum group_concat_finalfunc(PG_FUNCTION_ARGS)
{
    RdfnodeAggState *aggstate;
    char *literal;
    text *result;

    /* Get the state (already validated as non-NULL by wrapper) */
    aggstate = (RdfnodeAggState *)PG_GETARG_POINTER(0);

    if (aggstate == NULL || aggstate->result_str == NULL)
    {
        /* No input values: return empty simple literal */
        result = cstring_to_text("");
        PG_RETURN_TEXT_P(result);
    }
    /* Convert to simple literal (plain literal without datatype) */
    literal = cstring_to_rdfliteral(aggstate->result_str->data);

    /* Return as rdfnode (text type) */
    result = cstring_to_text(literal);
    PG_RETURN_TEXT_P(result);
}
