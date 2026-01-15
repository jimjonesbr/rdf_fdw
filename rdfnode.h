/*---------------------------------------------------------------------
 *
 * rdfnode.h
 *
 * Centralized definitions for RDF node representation.
 * 
 * Copyright (C) 2022-2026 Jim Jones <jim.jones@uni-muenster.de>
 * 
 *---------------------------------------------------------------------
 */

#ifndef RDFNODE_H
#define RDFNODE_H

#include "postgres.h"

typedef struct rdfnode
{
	int32 vl_len_;						 /* required varlena header */
	char vl_data[FLEXIBLE_ARRAY_MEMBER]; /* actual data */
} rdfnode;

typedef struct
{
	char *raw;			 /* raw literal (with language and data type, if any) */
	char *lex;			 /* literal's lexical value: "foo"^^xsd:string -> foo */
	char *dtype;		 /* literal's data type, e.g xsd:string, xsd:short */
	char *lang;			 /* literal's language tag, e.g. 'en', 'de', 'es' */
	bool isPlainLiteral; /* literal has no language or data type*/
	bool isNumeric;		 /* literal has a numeric value, e.g. xsd:int, xsd:float*/
	bool isString;		 /* xsd:string literal */
	bool isDateTime;	 /* xsd:dateTime literal */
	bool isDate;		 /* xsd:date literal*/
	bool isDuration;	 /* xsd:duration */
	bool isTime;		 /* xsd:time */
	bool isIRI;			 /* RDF IRI*/
} rdfnode_info;

extern bool rdfnode_eq(rdfnode *n1, rdfnode *n2);
extern bool rdfnode_ge(rdfnode *n1, rdfnode *n2);
extern bool rdfnode_le(rdfnode *n1, rdfnode *n2);
extern bool rdfnode_gt(rdfnode *n1, rdfnode *n2);
extern bool rdfnode_lt(rdfnode *n1, rdfnode *n2);

extern bool LiteralsComparable(rdfnode *n1, rdfnode *n2);
extern int rdfnode_cmp_for_aggregate(rdfnode *n1, rdfnode *n2);
extern rdfnode_info parse_rdfnode(rdfnode *node);

#endif /* RDFNODE_H */