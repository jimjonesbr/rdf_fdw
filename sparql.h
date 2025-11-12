
/*---------------------------------------------------------------------
 *
 * sparql.h
 *   SPARQL-related functions for RDF data manipulation.
 * 
 * Implements SPARQL 1.1 string functions, accessor functions, and
 * type checking.
 *
 * Copyright (C) 2022-2025 University of Münster, Germany
 *
 * ---------------------------------------------------------------------
 */

#ifndef SPARQL_H
#define SPARQL_H

#include "postgres.h"

/* 17.4.2 Functions on RDF Terms */
extern bool isIRI(char *input);
extern bool isBlank(char *term);
extern bool isLiteral(char *term);
extern bool isNumeric(char *term);
extern char *str(char *input);
extern char *lang(char *input);
extern char *datatype(char *input);
extern char *iri(char *input);
extern char *bnode(char *input);
extern char *strdt(char *literal, char *datatype);
extern char *strlang(char *literal, char *language);

/* 17.4.3 Functions on Strings */
extern int strlen_rdf(char *str);
extern char *substr_sparql(char *str, int start, int length);
extern char *lcase(char *str);
extern char *ucase(char *str);
extern bool strstarts(char *str, char *substr);
extern bool strends(char *str, char *substr);
extern bool contains(char *str, char *substr);
extern char *strbefore(char *str, char *delimiter);
extern char *strafter(char *str, char *delimiter);
extern char *encode_for_uri(char *str);
extern char *concat(char *left, char *right);
extern bool langmatches(char *lang_tag, char *pattern);

/* Custom functions */
extern char *lex(char *input);
extern char *generate_uuid_v4(void);

#endif /* SPARQL_H */
