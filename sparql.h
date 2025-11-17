
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
#include "utils/numeric.h"

/*
 * XSD numeric type promotion hierarchy for SPARQL aggregates.
 * Based on SPARQL 1.1 spec section 18.5.1.3 and XPath type promotion rules.
 */
typedef enum
{
	XSD_TYPE_INTEGER = 0,  /* xsd:integer and subtypes (int, long, short, byte, etc.) */
	XSD_TYPE_DECIMAL = 1,  /* xsd:decimal */
	XSD_TYPE_FLOAT = 2,    /* xsd:float */
	XSD_TYPE_DOUBLE = 3    /* xsd:double */
} XsdNumericType;

/*
 * RdfnodeAggState
 * ---------------
 * Unified state structure for all rdfnode aggregate functions.
 * Different aggregates use different fields:
 *   - SUM: uses numeric_value, maxType, has_input
 *   - AVG: uses numeric_value, count, maxType, has_input
 *   - MIN/MAX: uses rdfnode_value (raw text with datatype)
 *   - COUNT: uses count only
 */
typedef struct
{
    Numeric numeric_value;  /* accumulated numeric value (SUM), sum for average (AVG) */
    text *rdfnode_value;    /* current min/max as full rdfnode text (MIN/MAX) */
    int64 count;            /* count of non-NULL values (AVG, COUNT) */
    XsdNumericType maxType; /* highest numeric type seen (for type promotion in SUM/AVG) */
    bool has_input;         /* true if any input values were processed (even non-numeric) */
} RdfnodeAggState;

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
extern XsdNumericType get_xsd_numeric_type(const char *dtype);
extern const char *get_xsd_datatype_uri(XsdNumericType type);

/* SPARQL Aggregate Functions */
extern Datum sum_rdfnode_sfunc(PG_FUNCTION_ARGS);
extern Datum sum_rdfnode_finalfunc(PG_FUNCTION_ARGS);
extern Datum avg_rdfnode_sfunc(PG_FUNCTION_ARGS);
extern Datum avg_rdfnode_finalfunc(PG_FUNCTION_ARGS);
extern Datum min_rdfnode_sfunc(PG_FUNCTION_ARGS);
extern Datum min_rdfnode_finalfunc(PG_FUNCTION_ARGS);
extern Datum max_rdfnode_sfunc(PG_FUNCTION_ARGS);
extern Datum max_rdfnode_finalfunc(PG_FUNCTION_ARGS);

#endif /* SPARQL_H */
