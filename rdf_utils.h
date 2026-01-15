
/*---------------------------------------------------------------------
 *
 * rdf_utils.h
 *   Utility functions for RDF data manipulation and validation.
 *
 * Copyright (C) 2022-2026 Jim Jones <jim.jones@uni-muenster.de>
 * 
 *---------------------------------------------------------------------
 */

#ifndef RDF_UTILS_H
#define RDF_UTILS_H

#include "postgres.h"
#include "rdf_fdw.h"
#include "rdfnode.h"
#include "mb/pg_wchar.h"

/* Type mapping structure for PostgreSQL to XSD datatype conversion */
typedef struct
{
	Oid type_oid;
	const char *xsd_datatype;
} TypeXSDMap;

extern int LocateKeyword(char *str, char *start_chars, char *keyword, char *end_chars, int *count, int start_position);

/* RDF Literal Construction */
extern char *rdfnode_to_cstring(rdfnode *node);
extern char *cstring_to_rdfliteral(char *input);
extern char *EscapeSPARQLLiteral(const char *input);
extern char *ExpandDatatypePrefix(char *str);
extern char *unescape_unicode(const char *input);

/* Type Checking and Validation */
extern bool isPlainLiteral(char *literal);
extern bool LiteralsCompatible(char *literal1, char *literal2);
extern bool IsRDFStringLiteral(char *str_datatype);
extern bool IsSPARQLVariableValid(const char *str);
extern bool IsSPARQLParsable(struct RDFfdwState *state);
extern bool IsExpressionPushable(char *expression);
extern bool ContainsWhitespaces(char *str);
extern bool IsStringDataType(Oid type);
extern bool is_valid_language_tag(const char *lan);
extern bool is_valid_xsd_date(const char *lexical);
extern bool is_valid_xsd_time(const char *lexical);
extern bool is_valid_xsd_dateTime(const char *lexical);
extern bool is_valid_xsd_int(const char *lexical);
extern bool is_valid_xsd_double(const char *lexical);
extern int CheckURL(char *url);
extern void ValidateSPARQLUpdatePattern(RDFfdwState *state);
extern char *str_replace(const char *source, const char *search, const char *replace);
/* PostgreSQL to RDF Type Mapping */
extern char *MapSPARQLDatatype(Oid pgtype);

/* Query Pushdown Support */
extern bool IsFunctionPushable(char *funcname);
extern char *ConstToCString(Const *constant);
extern Const *CStringToConst(const char *str);

/* SPARQL Query Generation */
extern char *CreateRegexString(char *str);
extern char *FormatSQLExtractField(char *field);

#if PG_VERSION_NUM < 130000
void pg_unicode_to_server(pg_wchar c, unsigned char *utf8);
#endif

#endif /* RDF_UTILS_H */
