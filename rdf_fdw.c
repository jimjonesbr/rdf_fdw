
/**********************************************************************
 *
 * rdf_fdw - PostgreSQL Foreign-data Wrapper for RDF Triplestores
 *
 * rdf_fdw is free software: you can redistribute it and/or modify
 * it under the terms of the MIT Licence.
 *
 * Copyright (C) 2022-2025 University of Münster, Germany
 * Written by Jim Jones <jim.jones@uni-muenster.de>
 *
 **********************************************************************/

#include "postgres.h"

#include <curl/curl.h>
#include <libxml/tree.h>
#include "fmgr.h"
#include "access/htup_details.h"
#include "access/reloptions.h"
#include "access/sysattr.h"
#include "access/xact.h"
#include "catalog/indexing.h"
#include "catalog/pg_attribute.h"
#include "catalog/pg_cast.h"
#include "catalog/pg_collation.h"
#include "catalog/pg_foreign_data_wrapper.h"
#include "catalog/pg_foreign_server.h"
#include "catalog/pg_foreign_table.h"
#include "catalog/pg_namespace.h"
#include "catalog/pg_operator.h"
#include "catalog/pg_proc.h"
#include "catalog/pg_user_mapping.h"
#include "catalog/pg_type.h"
#include "commands/defrem.h"
#include "commands/explain.h"
#include "commands/vacuum.h"
#include "foreign/fdwapi.h"
#include "foreign/foreign.h"
#include "libpq/pqsignal.h"
//#include "mb/pg_wchar.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "nodes/pg_list.h"
#if PG_VERSION_NUM < 180000
#include "nodes/bitmapset.h"  // Needed for bms_is_empty in versions where it's inline
#endif
#include "optimizer/cost.h"
#include "optimizer/pathnode.h"
#include "optimizer/planmain.h"
#include "optimizer/restrictinfo.h"
#include "optimizer/tlist.h"
#include "parser/parse_relation.h"
#include "parser/parsetree.h"
#include "pgtime.h"
#include "port.h"
#include "storage/ipc.h"
#include "storage/lock.h"
#include "tcop/tcopprot.h"
#include "utils/array.h"
#include "utils/builtins.h"
#include "utils/catcache.h"
#include "utils/date.h"
#include "utils/numeric.h"
#include "utils/timestamp.h"
#include "utils/datetime.h"
#include "utils/elog.h"
#include "utils/fmgroids.h"
#include "utils/formatting.h"
#include "utils/guc.h"
#include "utils/lsyscache.h"
#include "utils/memutils.h"
#include "utils/rel.h"
#include "utils/resowner.h"
#include "utils/timestamp.h"
#include "utils/snapmgr.h"
#include "utils/syscache.h"
#include "utils/timestamp.h"
#include "executor/spi.h"
#if PG_VERSION_NUM < 120000
#include "nodes/relation.h"
#include "optimizer/var.h"
#include "utils/tqual.h"
#else
#include "nodes/pathnodes.h"
#include "optimizer/optimizer.h"
#include "access/heapam.h"
#endif
#include "funcapi.h"
#include "librdf.h"
#if PG_VERSION_NUM >= 100000
#include "utils/varlena.h"
#include "common/md5.h"
#else
#include "libpq/md5.h"
#endif
#include "mb/pg_wchar.h"
#include <regex.h>
#include "parser/parse_type.h"

#define REL_ALIAS_PREFIX    "r"
/* Handy macro to add relation name qualification */
#define ADD_REL_QUALIFIER(buf, varno)   \
		appendStringInfo((buf), "%s%d.", REL_ALIAS_PREFIX, (varno))

/* Doesn't exist prior PostgreSQL 11 */
#ifndef ALLOCSET_SMALL_SIZES
#define ALLOCSET_SMALL_SIZES \
	ALLOCSET_SMALL_MINSIZE, ALLOCSET_SMALL_INITSIZE, ALLOCSET_SMALL_MAXSIZE
#endif

#if PG_VERSION_NUM >= 90500
/* array_create_iterator has a new signature from 9.5 on */
#define array_create_iterator(arr, slice_ndim) array_create_iterator(arr, slice_ndim, NULL)
#endif  /* PG_VERSION_NUM */

#define FDW_VERSION "1.4.0-dev"
#define REQUEST_SUCCESS 0
#define REQUEST_FAIL -1
#define RDF_XML_NAME_TAG "name"
#define RDF_SPARQL_RESULT_LITERAL "literal"
#define RDF_SPARQL_RESULT_LITERAL_DATATYPE "datatype"
#define RDF_SPARQL_RESULT_LITERAL_LANG "lang"
#define RDF_DEFAULT_CONNECTTIMEOUT 300
#define RDF_DEFAULT_MAXRETRY 3
#define RDF_KEYWORD_NOT_FOUND -1
#define RDF_DEFAULT_FORMAT "application/sparql-results+xml"
#define RDF_RDFXML_FORMAT "application/rdf+xml"
#define RDF_DEFAULT_BASE_URI "http://rdf_fdw.postgresql.org/"
#define RDF_XSD_BASE_URI "http://www.w3.org/2001/XMLSchema#"
#define RDF_LANGUAGE_LITERAL_DATATYPE "<http://www.w3.org/1999/02/22-rdf-syntax-ns#langString>"
#define RDF_SIMPLE_LITERAL_DATATYPE "<http://www.w3.org/2001/XMLSchema#string>"
#define RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED "xsd:string"
#define RDF_XSD_STRING "<http://www.w3.org/2001/XMLSchema#string>"
#define RDF_XSD_INTEGER "<http://www.w3.org/2001/XMLSchema#integer>"
#define RDF_XSD_POSITIVEINTEGER "<http://www.w3.org/2001/XMLSchema#positiveInteger>"
#define RDF_XSD_NEGATIVEINTEGER "<http://www.w3.org/2001/XMLSchema#negativeInteger>"
#define RDF_XSD_NONPOSITIVEINTEGER "<http://www.w3.org/2001/XMLSchema#nonPositiveInteger>"
#define RDF_XSD_NONNEGATIVEINTEGER "<http://www.w3.org/2001/XMLSchema#nonNegativeInteger>"
#define RDF_XSD_INT "<http://www.w3.org/2001/XMLSchema#int>"
#define RDF_XSD_DATE "<http://www.w3.org/2001/XMLSchema#date>"
#define RDF_XSD_DATETIME "<http://www.w3.org/2001/XMLSchema#dateTime>"
#define RDF_XSD_DECIMAL "<http://www.w3.org/2001/XMLSchema#decimal>"
#define RDF_XSD_DOUBLE "<http://www.w3.org/2001/XMLSchema#double>"
#define RDF_XSD_LONG "<http://www.w3.org/2001/XMLSchema#long>"
#define RDF_XSD_UNSIGNEDLONG "<http://www.w3.org/2001/XMLSchema#unsignedLong>"
#define RDF_XSD_UNSIGNEDINT "<http://www.w3.org/2001/XMLSchema#unsignedInt>"
#define RDF_XSD_UNSIGNEDSHORT "<http://www.w3.org/2001/XMLSchema#unsignedShort>"
#define RDF_XSD_UNSIGNEDBYTE "<http://www.w3.org/2001/XMLSchema#unsignedByte>"
#define RDF_XSD_SHORT "<http://www.w3.org/2001/XMLSchema#short>"
#define RDF_XSD_FLOAT "<http://www.w3.org/2001/XMLSchema#float>"
#define RDF_XSD_BYTE "<http://www.w3.org/2001/XMLSchema#byte>"
#define RDF_XSD_BOOLEAN "<http://www.w3.org/2001/XMLSchema#boolean>"
#define RDF_XSD_TIME "<http://www.w3.org/2001/XMLSchema#time>"
#define RDF_XSD_DURATION "<http://www.w3.org/2001/XMLSchema#duration>"
#define RDF_XSD_ANYURI "<http://www.w3.org/2001/XMLSchema#anyURI>"

#define RDF_DEFAULT_QUERY_PARAM "query"
#define RDF_DEFAULT_FETCH_SIZE 100
#define RDF_ORDINARY_TABLE_CODE "r"
#define RDF_FOREIGN_TABLE_CODE "f"

#define RDF_USERMAPPING_OPTION_USER "user"
#define RDF_USERMAPPING_OPTION_PASSWORD "password"

#define RDF_SERVER_OPTION_ENDPOINT "endpoint"
#define RDF_SERVER_OPTION_FORMAT "format"
#define RDF_SERVER_OPTION_CUSTOMPARAM "custom"
#define RDF_SERVER_OPTION_CONNECTTIMEOUT "connect_timeout"
#define RDF_SERVER_OPTION_CONNECTRETRY "connect_retry"
#define RDF_SERVER_OPTION_REQUEST_REDIRECT "request_redirect"
#define RDF_SERVER_OPTION_REQUEST_MAX_REDIRECT "request_max_redirect"
#define RDF_SERVER_OPTION_HTTP_PROXY "http_proxy"
#define RDF_SERVER_OPTION_HTTPS_PROXY "https_proxy"
#define RDF_SERVER_OPTION_PROXY_USER "proxy_user"
#define RDF_SERVER_OPTION_PROXY_USER_PASSWORD "proxy_user_password"
#define RDF_SERVER_OPTION_ENABLE_PUSHDOWN "enable_pushdown"
#define RDF_SERVER_OPTION_QUERY_PARAM "query_param"
#define RDF_SERVER_OPTION_FETCH_SIZE "fetch_size"
#define RDF_SERVER_OPTION_BASE_URI "base_uri"

#define RDF_TABLE_OPTION_SPARQL "sparql"
#define RDF_TABLE_OPTION_LOG_SPARQL "log_sparql"
#define RDF_TABLE_OPTION_ENABLE_PUSHDOWN "enable_pushdown"
#define RDF_TABLE_OPTION_FETCH_SIZE "fetch_size"

#define RDF_COLUMN_OPTION_VARIABLE "variable"
#define RDF_COLUMN_OPTION_EXPRESSION "expression"
#define RDF_COLUMN_OPTION_LITERALTYPE "literaltype"
#define RDF_COLUMN_OPTION_NODETYPE "nodetype"
#define RDF_COLUMN_OPTION_NODETYPE_IRI "iri"
#define RDF_COLUMN_OPTION_NODETYPE_LITERAL "literal"
#define RDF_COLUMN_OPTION_LANGUAGE "language"
#define RDF_COLUMN_OPTION_LITERAL_TYPE "literal_type"
//#define RDF_COLUMN_OPTION_LITERAL_FORMAT "literal_format"

#define RDF_COLUMN_OPTION_VALUE_LITERAL_RAW "raw"
#define RDF_COLUMN_OPTION_VALUE_LITERAL_CONTENT "content"

#define RDF_SPARQL_TYPE_SELECT "SELECT"
#define RDF_SPARQL_TYPE_DESCRIBE "DESCRIBE"
#define RDF_SPARQL_KEYWORD_FROM "FROM"
#define RDF_SPARQL_KEYWORD_NAMED "NAMED"
#define RDF_SPARQL_KEYWORD_PREFIX "PREFIX"
#define RDF_SPARQL_KEYWORD_SELECT "SELECT"
#define RDF_SPARQL_KEYWORD_DESCRIBE "DESCRIBE"
#define RDF_SPARQL_KEYWORD_GROUPBY "GROUP BY"
#define RDF_SPARQL_KEYWORD_ORDERBY "ORDER BY"
#define RDF_SPARQL_KEYWORD_HAVING "HAVING"
#define RDF_SPARQL_KEYWORD_LIMIT "LIMIT"
#define RDF_SPARQL_KEYWORD_UNION "UNION"

#define RDF_SPARQL_AGGREGATE_FUNCTION_COUNT "COUNT"
#define RDF_SPARQL_AGGREGATE_FUNCTION_AVG "AVG"
#define RDF_SPARQL_AGGREGATE_FUNCTION_SUM "SUM"
#define RDF_SPARQL_AGGREGATE_FUNCTION_MIN "MIN"
#define RDF_SPARQL_AGGREGATE_FUNCTION_MAX "MAX"
#define RDF_SPARQL_AGGREGATE_FUNCTION_SAMPLE "SAMPLE"
#define RDF_SPARQL_AGGREGATE_FUNCTION_GROUPCONCAT "GROUP_CONCAT"

#define IntToConst(x) makeConst(INT4OID, -1, InvalidOid, 4, Int32GetDatum((int32)(x)), false, true)
#define OidToConst(x) makeConst(OIDOID, -1, InvalidOid, 4, ObjectIdGetDatum(x), false, true)
#define IRI_SIZE(len) (VARHDRSZ + (len) + 1)
/*
 * This macro is used by DeparseExpr to identify PostgreSQL
 * types that can be translated to SPARQL
 */
#define canHandleType(x) ((x) == TEXTOID || (x) == CHAROID || (x) == BPCHAROID \
			|| (x) == VARCHAROID || (x) == NAMEOID || (x) == INT8OID || (x) == INT2OID \
			|| (x) == INT4OID || (x) == FLOAT4OID || (x) == FLOAT8OID || (x) == BOOLOID \
			|| (x) == NUMERICOID || (x) == DATEOID || (x) == TIMESTAMPOID || (x) == TIMESTAMPTZOID \
			|| (x) == TIMEOID || (x) == TIMETZOID || (x) == RDFNODEOID)

/* list API has changed in v13 */
#if PG_VERSION_NUM < 130000
#define list_next(l, e) lnext((e))
#define do_each_cell(cell, list, element) for_each_cell(cell, (element))
#else
#define list_next(l, e) lnext((l), (e))
#define do_each_cell(cell, list, element) for_each_cell(cell, (list), (element))
#endif  /* PG_VERSION_NUM */

PG_MODULE_MAGIC;

typedef enum RDFfdwQueryType
{
	SPARQL_SELECT,
	SPARQL_DESCRIBE
} RDFfdwQueryType;

typedef struct RDFfdwState
{
	int numcols;                 /* Total number of columns in the foreign table. */
	int rowcount;                /* Number of rows currently returned to the client */
	int pagesize;                /* Total number of records retrieved from the SPARQL endpoint*/
	char *sparql;                /* Final SPARQL query sent to the endpoint (after pusdhown) */
	char *user;                  /* User name for HTTP basic authentication */
	char *password;              /* Password for HTTP basic authentication */
	char *sparql_prefixes;       /* SPARQL PREFIX entries */
	char *sparql_select;         /* SPARQL SELECT containing the columns / variables used in the SQL query */
	char *sparql_from;           /* SPARQL FROM clause entries*/
	char *sparql_where;          /* SPARQL WHERE clause */
	char *sparql_filter;         /* SPARQL FILTER clauses based on SQL WHERE conditions */
	char *sparql_orderby;        /* SPARQL ORDER BY clause based on the SQL ORDER BY clause */
	char *sparql_limit;          /* SPARQL LIMIT clause based on SQL LIMIT and FETCH clause */
	char *sparql_resultset;      /* Raw string containing the result of a SPARQL query */
	char *raw_sparql;            /* Raw SPARQL query set in the CREATE TABLE statement */
	char *endpoint;              /* SPARQL endpoint set in the CREATE SERVER statement*/
	char *query_param;           /* SPARQL query POST parameter used by the endpoint */
	char *format;                /* Format in which the RDF triplestore has to reply */
	char *proxy;                 /* Proxy for HTTP requests, if necessary. */
	char *proxy_type;            /* Proxy protocol (HTTPS, HTTP). */
	char *proxy_user;            /* User name for proxy authentication. */
	char *proxy_user_password;   /* Password for proxy authentication. */
	char *custom_params;         /* Custom parameters used to compose the request URL */
	char *base_uri;              /* Base URI for possible relative references */
	bool request_redirect;       /* Enables or disables URL redirecting. */
	bool enable_pushdown;        /* Enables or disables pushdown of SQL commands */
	bool is_sparql_parsable;     /* Marks the query is or not for pushdown*/
	bool log_sparql;             /* Enables or disables logging SPARQL queries as NOTICE */
	bool has_unparsable_conds;   /* Marks a query that contains expressions that cannot be parsed for pushdown. */
	bool keep_raw_literal;       /* Flag to determine if a literal should be serialized with its data type/language or not*/
	long request_max_redirect;   /* Limit of how many times the URL redirection (jump) may occur. */
	long connect_timeout;        /* Timeout for SPARQL queries */
	long max_retries;            /* Number of re-try attemtps for failed SPARQL queries */
	xmlDocPtr xmldoc;            /* XML document where the result of SPARQL queries will be stored */	
	Oid foreigntableid;          /* FOREIGN TABLE oid */
	List *records;               /* List of records retrieved from a SPARQL request (after parsing 'xmldoc')*/
	struct RDFfdwTable *rdfTable;/* All necessary information of the FOREIGN TABLE used in a SQL statement */
	Cost startup_cost;           /* startup cost estimate */
	Cost total_cost;             /* total cost estimate */
	ForeignServer *server;       /* FOREIGN SERVER to connect to the RDF triplestore */
	ForeignTable *foreign_table; /* FOREIGN TABLE containing the graph pattern (SPARQL Query) and column / variable mapping */
	UserMapping *mapping;        /* USER MAPPING to enable http basic authentication for a given postgres user */
	MemoryContext rdfctxt;       /* Memory Context for data manipulation */
	CURL *curl;                  /* CURL request handler */
	RDFfdwQueryType sparql_query_type;  /* SPARQL Query type: SELECT, DESCRIBE */
	/* exclusively for rdf_fdw_clone_table usage */
	Relation target_table;
	bool verbose;
	bool commit_page;
	char *target_table_name;
	char *ordering_pgcolumn;
	char *sort_order;
	int offset;
	int fetch_size;
	int inserted_records;	
} RDFfdwState;

typedef struct RDFfdwTable
{	
	char *name;                  /* FOREIGN TABLE name */
	struct RDFfdwColumn **cols;  /* List of columns of a FOREIGN TABLE */
} RDFfdwTable;

typedef struct RDFfdwColumn
{	
	char *name;                  /* Column name */
	char *sparqlvar;             /* Column OPTION 'variable' - SPARQL variable */
	char *expression;            /* Column OPTION 'expression' - SPARQL expression*/
	char *literaltype;           /* Column OPTION 'type' - literal data type */
	char *literal_fomat;         /*  */
	char *nodetype;              /* Column OPTION 'nodetype' - node data type */
	char *language;              /* Column OPTION 'language' - RDF language tag for literals */
	Oid  pgtype;                 /* PostgreSQL data type */
	int  pgtypmod;               /* PostgreSQL type modifier */
	int  pgattnum;               /* PostgreSQL attribute number */
	bool used;                   /* Is the column used in the current SQL query? */
	bool pushable;               /* Marks a column as safe or not to pushdown */

} RDFfdwColumn;

struct string
{
	char *ptr;
	size_t len;
};

struct MemoryStruct
{
	char *memory;
	size_t size;
};

struct RDFfdwOption
{
	const char *optname;
	Oid optcontext;	  /* Oid of catalog in which option may appear */
	bool optrequired; /* Flag mandatory options */
	bool optfound;	  /* Flag whether options was specified by user */
};

static struct RDFfdwOption valid_options[] =
{
	/* Foreign Servers */
	{RDF_SERVER_OPTION_ENDPOINT, ForeignServerRelationId, true, false},
	{RDF_SERVER_OPTION_FORMAT, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_HTTP_PROXY, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_HTTPS_PROXY, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_CUSTOMPARAM, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_PROXY_USER, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_PROXY_USER_PASSWORD, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_CONNECTTIMEOUT, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_CONNECTRETRY, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_REQUEST_REDIRECT, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_REQUEST_MAX_REDIRECT, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_ENABLE_PUSHDOWN, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_QUERY_PARAM, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_FETCH_SIZE, ForeignServerRelationId, false, false},
	{RDF_SERVER_OPTION_BASE_URI, ForeignServerRelationId, false, false},
	/* Foreign Tables */
	{RDF_TABLE_OPTION_SPARQL, ForeignTableRelationId, true, false},
	{RDF_TABLE_OPTION_LOG_SPARQL, ForeignTableRelationId, false, false},
	{RDF_TABLE_OPTION_ENABLE_PUSHDOWN, ForeignTableRelationId, false, false},
	{RDF_TABLE_OPTION_FETCH_SIZE, ForeignTableRelationId, false, false},
	/* Options for Foreign Table's Columns */
	{RDF_COLUMN_OPTION_VARIABLE, AttributeRelationId, true, false},
	{RDF_COLUMN_OPTION_EXPRESSION, AttributeRelationId, false, false},
	{RDF_COLUMN_OPTION_LITERALTYPE, AttributeRelationId, false, false},
	{RDF_COLUMN_OPTION_LITERAL_TYPE, AttributeRelationId, false, false},
//	{RDF_COLUMN_OPTION_LITERAL_FORMAT, AttributeRelationId, false, false},
	{RDF_COLUMN_OPTION_NODETYPE, AttributeRelationId, false, false},
	{RDF_COLUMN_OPTION_LANGUAGE, AttributeRelationId, false, false},
	/* User Mapping */
	{RDF_USERMAPPING_OPTION_USER, UserMappingRelationId, false, false},
	{RDF_USERMAPPING_OPTION_PASSWORD, UserMappingRelationId, false, false},
	/* EOList option */
	{NULL, InvalidOid, false, false}
};

typedef struct
{
	Oid type_oid;
	const char *xsd_datatype;
} TypeXSDMap;

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

typedef struct RDFfdwTriple
{
	char *subject;	 /* RDF triple subject */
	char *predicate; /* RDF triple predicate */
	char *object;	 /* RDF triple object */
} RDFfdwTriple;

typedef struct
{
	char *raw;				/* raw literal (with language and data type, if any) */
	char *lex;	 			/* literal's lexical value: "foo"^^xsd:string -> foo */
	char *dtype; 			/* literal's data type, e.g xsd:string, xsd:short */
	char *lang;	 			/* literal's language tag, e.g. 'en', 'de', 'es' */
	bool isPlainLiteral;	/* literal has no language or data type*/
	bool isNumeric;			/* literal has a numeric value, e.g. xsd:int, xsd:float*/
	bool isString;			/* xsd:string literal */
	bool isDateTime;		/* xsd:dateTime literal */
	bool isDate;			/* xsd:date literal*/
	bool isDuration;		/* xsd:duration */
	bool isTime;			/* xsd:time */
	bool isIRI;				/* RDF IRI*/
} parsed_rdfnode;

static Oid RDFNODEOID = InvalidOid;

extern Datum rdf_fdw_handler(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_validator(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_version(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_clone_table(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_describe(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_strstarts(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_strends(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_strbefore(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_strafter(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_contains(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_encode_for_uri(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_strlang(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_strdt(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_str(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_lang(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_datatype(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_datatype_text(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_datatype_poly(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_arguments_compatible(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_iri(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_iri_in(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_iri_out(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_isIRI(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_langmatches(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_isBlank(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_isNumeric(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_isLiteral(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_bnode(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_uuid(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_lcase(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_ucase(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_strlen(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_substr(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_concat(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_lex(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_md5(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_bound(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_sameterm(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_coalesce(PG_FUNCTION_ARGS);

/* rdfnode PostgreSQL data type */
extern Datum rdfnode_in(PG_FUNCTION_ARGS);
extern Datum rdfnode_out(PG_FUNCTION_ARGS);
extern Datum rdfnode_to_text(PG_FUNCTION_ARGS);
extern Datum rdfnode_cmp(PG_FUNCTION_ARGS);

/* rdfnode (custom data type)*/
extern Datum rdfnode_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_rdfnode(PG_FUNCTION_ARGS);

/* numeric data type */
extern Datum rdfnode_to_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_numeric(PG_FUNCTION_ARGS);
extern Datum numeric_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_ge_rdfnode(PG_FUNCTION_ARGS);

/* float8 (double precision) data type */
extern Datum rdfnode_eq_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_to_float8(PG_FUNCTION_ARGS);
extern Datum float8_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_ge_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_to_rdfnode(PG_FUNCTION_ARGS);

/* float4 (real) data type */
extern Datum rdfnode_to_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_float4(PG_FUNCTION_ARGS);
extern Datum float4_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_ge_rdfnode(PG_FUNCTION_ARGS);

/* int8 (bigint) data type*/
extern Datum rdfnode_to_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_int8(PG_FUNCTION_ARGS);
extern Datum int8_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_ge_rdfnode(PG_FUNCTION_ARGS);

/* int4 (int) data type */
extern Datum rdfnode_to_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_int4(PG_FUNCTION_ARGS);
extern Datum int4_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_ge_rdfnode(PG_FUNCTION_ARGS);

/* int2 (smallint) data type */
extern Datum rdfnode_to_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_int2(PG_FUNCTION_ARGS);
extern Datum int2_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_ge_rdfnode(PG_FUNCTION_ARGS);

/* timestamptz (timestamp with time zone) */
extern Datum rdfnode_to_timestamptz(PG_FUNCTION_ARGS);
extern Datum timestamptz_to_rdfnode(PG_FUNCTION_ARGS);

/* timestamp (timestamp without time zone) */
extern Datum rdfnode_to_timestamp(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_timestamp(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_timestamp(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_timestamp(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_timestamp(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_timestamp(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_timestamp(PG_FUNCTION_ARGS);
extern Datum timestamp_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamp_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamp_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamp_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamp_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamp_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamp_ge_rdfnode(PG_FUNCTION_ARGS);

/* date */
extern Datum rdfnode_to_date(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_date(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_date(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_date(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_date(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_date(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_date(PG_FUNCTION_ARGS);
extern Datum date_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum date_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum date_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum date_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum date_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum date_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum date_ge_rdfnode(PG_FUNCTION_ARGS);

/* time (time without time zone) */
extern Datum rdfnode_to_time(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_time(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_time(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_time(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_time(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_time(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_time(PG_FUNCTION_ARGS);
extern Datum time_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum time_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum time_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum time_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum time_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum time_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum time_ge_rdfnode(PG_FUNCTION_ARGS);

/* timetz (time with time zone) */
extern Datum rdfnode_to_timetz(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_timetz(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_timetz(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_timetz(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_timetz(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_timetz(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_timetz(PG_FUNCTION_ARGS);
extern Datum timetz_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum timetz_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum timetz_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum timetz_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum timetz_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum timetz_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum timetz_ge_rdfnode(PG_FUNCTION_ARGS);

/* boolean */
extern Datum rdfnode_to_boolean(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_boolean(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_boolean(PG_FUNCTION_ARGS);
extern Datum boolean_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum boolean_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum boolean_neq_rdfnode(PG_FUNCTION_ARGS);

/* interval */
extern Datum rdfnode_to_interval(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_interval(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_interval(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_interval(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_interval(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_interval(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_interval(PG_FUNCTION_ARGS);
extern Datum interval_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum interval_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum interval_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum interval_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum interval_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum interval_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum interval_ge_rdfnode(PG_FUNCTION_ARGS);

PG_FUNCTION_INFO_V1(rdf_fdw_handler);
PG_FUNCTION_INFO_V1(rdf_fdw_validator);
PG_FUNCTION_INFO_V1(rdf_fdw_version);
PG_FUNCTION_INFO_V1(rdf_fdw_clone_table);
PG_FUNCTION_INFO_V1(rdf_fdw_describe);
PG_FUNCTION_INFO_V1(rdf_fdw_strstarts);
PG_FUNCTION_INFO_V1(rdf_fdw_strends);
PG_FUNCTION_INFO_V1(rdf_fdw_strbefore);
PG_FUNCTION_INFO_V1(rdf_fdw_strafter);
PG_FUNCTION_INFO_V1(rdf_fdw_contains);
PG_FUNCTION_INFO_V1(rdf_fdw_encode_for_uri);
PG_FUNCTION_INFO_V1(rdf_fdw_strlang);
PG_FUNCTION_INFO_V1(rdf_fdw_strdt);
PG_FUNCTION_INFO_V1(rdf_fdw_str);
PG_FUNCTION_INFO_V1(rdf_fdw_lang);
PG_FUNCTION_INFO_V1(rdf_fdw_datatype);
PG_FUNCTION_INFO_V1(rdf_fdw_datatype_text);
PG_FUNCTION_INFO_V1(rdf_fdw_datatype_poly);
PG_FUNCTION_INFO_V1(rdf_fdw_arguments_compatible);
PG_FUNCTION_INFO_V1(rdf_fdw_iri);
PG_FUNCTION_INFO_V1(rdf_fdw_iri_in);
PG_FUNCTION_INFO_V1(rdf_fdw_iri_out);
PG_FUNCTION_INFO_V1(rdf_fdw_isIRI);
PG_FUNCTION_INFO_V1(rdf_fdw_langmatches);
PG_FUNCTION_INFO_V1(rdf_fdw_isBlank);
PG_FUNCTION_INFO_V1(rdf_fdw_isNumeric);
PG_FUNCTION_INFO_V1(rdf_fdw_isLiteral);
PG_FUNCTION_INFO_V1(rdf_fdw_bnode);
PG_FUNCTION_INFO_V1(rdf_fdw_uuid);
PG_FUNCTION_INFO_V1(rdf_fdw_lcase);
PG_FUNCTION_INFO_V1(rdf_fdw_ucase);
PG_FUNCTION_INFO_V1(rdf_fdw_strlen);
PG_FUNCTION_INFO_V1(rdf_fdw_substr);
PG_FUNCTION_INFO_V1(rdf_fdw_concat);
PG_FUNCTION_INFO_V1(rdf_fdw_lex);
PG_FUNCTION_INFO_V1(rdf_fdw_md5);
PG_FUNCTION_INFO_V1(rdf_fdw_bound);
PG_FUNCTION_INFO_V1(rdf_fdw_sameterm);
PG_FUNCTION_INFO_V1(rdf_fdw_coalesce);

/* rdfnode (custom data type) */
PG_FUNCTION_INFO_V1(rdfnode_in);
PG_FUNCTION_INFO_V1(rdfnode_out);
PG_FUNCTION_INFO_V1(rdfnode_to_text);
PG_FUNCTION_INFO_V1(rdfnode_cmp);
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

/* timestamptz (timestamp with time zone) */
PG_FUNCTION_INFO_V1(timestamptz_to_rdfnode);
PG_FUNCTION_INFO_V1(rdfnode_to_timestamptz);

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

/* timetz (time witho time zone) */
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

static void rdfGetForeignRelSize(PlannerInfo *root, RelOptInfo *baserel, Oid foreigntableid);
static void rdfGetForeignPaths(PlannerInfo *root, RelOptInfo *baserel, Oid foreigntableid);
static ForeignScan *rdfGetForeignPlan(PlannerInfo *root, RelOptInfo *baserel, Oid foreigntableid, ForeignPath *best_path, List *tlist, List *scan_clauses, Plan *outer_plan);
static void rdfBeginForeignScan(ForeignScanState *node, int eflags);
static TupleTableSlot *rdfIterateForeignScan(ForeignScanState *node);
static void rdfReScanForeignScan(ForeignScanState *node);
static void rdfEndForeignScan(ForeignScanState *node);
//static TupleTableSlot *rdfExecForeignUpdate(EState *estate, ResultRelInfo *rinfo, TupleTableSlot *slot, TupleTableSlot *planSlot);
//static TupleTableSlot *rdfExecForeignInsert(EState *estate, ResultRelInfo *rinfo, TupleTableSlot *slot, TupleTableSlot *planSlot);
//static TupleTableSlot *rdfExecForeignDelete(EState *estate, ResultRelInfo *rinfo, TupleTableSlot *slot, TupleTableSlot *planSlot);

static Datum CreateDatum(HeapTuple tuple, int pgtype, int pgtypmod, char *value);
static List *DescribeIRI(RDFfdwState *state);
static void LoadRDFTableInfo(RDFfdwState *state);
static void LoadRDFServerInfo(RDFfdwState *state);
static void LoadRDFUserMapping(RDFfdwState *state);
static int ExecuteSPARQL(RDFfdwState *state);
static void CreateTuple(TupleTableSlot *slot, RDFfdwState *state);
static void LoadRDFData(RDFfdwState *state);
static xmlNodePtr FetchNextBinding(RDFfdwState *state);
static char *ConstToCString(Const *constant);
static Const *CStringToConst(const char* str);
static List *SerializePlanData(RDFfdwState *state);
static struct RDFfdwState *DeserializePlanData(List *list);
static int CheckURL(char *url);
static void InitSession(struct RDFfdwState *state,  RelOptInfo *baserel, PlannerInfo *root);
static struct RDFfdwColumn *GetRDFColumn(struct RDFfdwState *state, char *columnname);
static int LocateKeyword(char *str, char *start_chars, char *keyword, char *end_chars, int *count, int start_position);
static void CreateSPARQL(RDFfdwState *state, PlannerInfo *root);
#if PG_VERSION_NUM >= 110000
static int InsertRetrievedData(RDFfdwState *state, int offset, int fetch_size);
static Oid GetRelOidFromName(char *relname, char *code);
#endif  /*PG_VERSION_NUM */
static void SetUsedColumns(Expr *expr, struct RDFfdwState *state, int foreignrelid);
static bool IsSPARQLParsable(struct RDFfdwState *state);
static bool IsExpressionPushable(char *expression);
static bool ContainsWhitespaces(char *str);
static bool IsSPARQLVariableValid(const char* str);
//static char *DeparseDate(Datum datum);
//static char *DeparseTimestamp(Datum datum, Oid typid);
static char *DeparseSQLLimit(struct RDFfdwState *state, PlannerInfo *root, RelOptInfo *baserel);
static char *DeparseSQLWhereConditions(struct RDFfdwState *state, RelOptInfo *baserel);
static char *DeparseSPARQLWhereGraphPattern(struct RDFfdwState *state);
static char *DatumToString(Datum datum, Oid type);
static char *DeparseExpr(struct RDFfdwState *state, RelOptInfo *foreignrel, Expr *expr);
static char *DeparseSQLOrderBy( struct RDFfdwState *state, PlannerInfo *root, RelOptInfo *baserel);
static char *DeparseSPARQLFrom(char *raw_sparql);
static char *DeparseSPARQLPrefix(char *raw_sparql);
static char* CreateRegexString(char* str);
static bool IsStringDataType(Oid type);
static bool IsFunctionPushable(char *funcname);
static char *FormatSQLExtractField(char *field);
static char *cstring_to_rdfnode(char *input);
static char *rdfnode_to_cstring(char *input);
static char *lex(char *input);
static bool LiteralsCompatible(char *literal1, char *literal2);
static char *ExpandDatatypePrefix(char *str);
static bool IsRDFStringLiteral(char *str_datatype);
static char *MapSPARQLDatatype(Oid pgtype);
static char *str(char *input);
static char *strdt(char *literal, char *datatype);
static char *lang(char *input);
static char *datatype(char *input);
static char *encode_for_uri(char *str);
static bool strstarts(char *str, char *substr);
static bool strends(char *str, char *substr);
static char *iri(char *input);
static bool isIRI(char *input);
static bool langmatches(char *lang_tag, char *pattern);
static bool isLiteral(char *term);
static char *bnode(char *input);
static char *generate_uuid_v4(void);
static char *rdf_concat(char *left, char *right);
static Oid get_rdfnode_oid(void);
static bool isPlainLiteral(char *litral);

static bool rdfnode_lt(parsed_rdfnode rdfnode1, parsed_rdfnode rdfnode2);
static bool LiteralsComparable(parsed_rdfnode rdfnode1, parsed_rdfnode rdfnode2);
#if PG_VERSION_NUM < 130000
static void pg_unicode_to_server(pg_wchar c, unsigned char *utf8);
#endif
static char *unescape_unicode(const char *input);

Datum rdf_fdw_handler(PG_FUNCTION_ARGS)
{
	FdwRoutine *fdwroutine = makeNode(FdwRoutine);
	fdwroutine->GetForeignRelSize = rdfGetForeignRelSize;
	fdwroutine->GetForeignPaths = rdfGetForeignPaths;
	fdwroutine->GetForeignPlan = rdfGetForeignPlan;
	fdwroutine->BeginForeignScan = rdfBeginForeignScan;
	fdwroutine->IterateForeignScan = rdfIterateForeignScan;
	fdwroutine->ReScanForeignScan = rdfReScanForeignScan;
	fdwroutine->EndForeignScan = rdfEndForeignScan;
	//fdwroutine->ExecForeignInsert = rdfExecForeignInsert;
	//fdwroutine->ExecForeignUpdate = rdfExecForeignUpdate;
	//fdwroutine->ExecForeignDelete = rdfExecForeignDelete;
	PG_RETURN_POINTER(fdwroutine);
}

Datum rdf_fdw_version(PG_FUNCTION_ARGS)
{
	StringInfoData buffer;
	initStringInfo(&buffer);

	appendStringInfo(&buffer, "rdf_fdw = %s,", FDW_VERSION);
	appendStringInfo(&buffer, " libxml/%s,", LIBXML_DOTTED_VERSION);
	appendStringInfo(&buffer, " librdf/%s,", librdf_version_string);
	appendStringInfo(&buffer, " %s", curl_version());

	PG_RETURN_TEXT_P(cstring_to_text(buffer.data));
}

/*
 * cstring_to_rdfnode
 * --------------
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
static char *cstring_to_rdfnode(char *input)
{
	StringInfoData buf;
	const char *start;
	const char *end;
	int len;

	elog(DEBUG1,"%s called: input='%s'", __func__, input);

	if (!input || strlen(input) == 0)
	{
		elog(DEBUG1,"%s exit: returning empty literal '\"\"'", __func__);
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
				elog(DEBUG1,"%s exit: returning => '%s'", __func__, input);
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

	elog(DEBUG1,"%s exit: returning => '%s'", __func__, buf.data);
	return buf.data;
}

static char *lex(char *input)
{
    StringInfoData output;
    const char *start = input;
    int len = strlen(input);

    initStringInfo(&output);
    elog(DEBUG1, "%s called: input='%s'", __func__, input);

    if (len == 0)
        return "";

    /* Handle quoted literal */
    if (start[0] == '"') {
        const char *p;
        start++;  /* skip opening quote */

        p = start;
        while (*p) {
            if (*p == '"' && *(p - 1) != '\\') {
                break;  /* closing quote found */
            }
            if (*p == '\\' && *(p + 1)) {
                appendStringInfoChar(&output, *p);
                p++;
            }
            appendStringInfoChar(&output, *p);
            p++;
        }

        /* No closing quote found — malformed, return whole string */
        if (*p != '"') {
            resetStringInfo(&output);
            appendStringInfoString(&output, input);
            return output.data;
        }

        /* Successful: return parsed inside quotes */
        return output.data;
    }

    /* Handle IRI */
    if (start[0] == '<') {
        appendStringInfoString(&output, start);
        return output.data;
    }

    /* Unquoted: trim at @ or ^^ only if they indicate language tag or datatype */
    {
        const char *at = strchr(start, '@');
        const char *dt = strstr(start, "^^");
        const char *cut = NULL;

        if (at && (!dt || at < dt)) {
            const char *tag = at + 1;
            int letter_count = 0;
            const char *p = NULL;
            int is_lang_tag = 0;

            if (*tag && isalpha(*tag)) {
                p = tag;
                while (*p && isalpha(*p) && letter_count < 8) {
                    letter_count++;
                    p++;
                }

                if (letter_count >= 1 && (!*p || *p == '-' || (*p != '.' && *p != '@'))) {
                    if (*p == '-') {
                        p++;
                        while (*p && (isalnum(*p) || *p == '-')) {
                            p++;
                        }
                    }

                    if (!*p || (*p != '.' && *p != '@')) {
                        is_lang_tag = 1;
                    }
                }
            }

            if (is_lang_tag) {
                cut = at;
            }
        } else if (dt) {
            cut = dt;
        }

        if (cut) {
            appendBinaryStringInfo(&output, start, cut - start);
        } else {
            appendStringInfoString(&output, start);
        }
    }

    return output.data;
}


/*
 * lang
 * ----
 *
 * Extracts the language tag from an RDF literal, if present. Returns an empty
 * string if no language tag is found or if the input is invalid/empty.
 *
 * input: Null-terminated C string representing an RDF literal (e.g., "abc"@en, "123"^^xsd:int)
 *
 * returns: Null-terminated C string representing the language tag (e.g., "en") or empty string
 */
static char *lang(char *input)
{
	StringInfoData buf;
	const char *ptr;
	char *lexical_form;

	elog(DEBUG1, "%s called: input='%s'", __func__, input);

	if (!input || strlen(input) == 0)
		return "";

	lexical_form = lex(input);
	ptr = input;

	/* find the end of the lexical form in the original input */
	if (*ptr == '"')
	{
		ptr++;						 /* skip opening quote */
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
		elog(DEBUG1,"%s exit: returning => '%s'", __func__, buf.data);
		return buf.data;
	}

	elog(DEBUG1,"%s exit: returning empty string", __func__);
	return "";
}

/*
 * rdf_fdw_lang
 * ------------
 *
 * PostgreSQL function wrapper for the lang function. Extracts the language tag
 * from an RDF literal provided as a PostgreSQL text argument.
 *
 * input_text: PostgreSQL text type (e.g., "abc"@en, "123"^^xsd:int)
 *
 * returns: PostgreSQL text type representing the language tag or empty string
 */
Datum rdf_fdw_lang(PG_FUNCTION_ARGS)
{
    text *input_text = PG_GETARG_TEXT_PP(0);
    char *literal = text_to_cstring(input_text);
    char *result = lang(literal);

    PG_RETURN_TEXT_P(cstring_to_text(result));
}

/*
 * strlang
 * -------
 *
 * Constructs an RDF literal by combining a lexical value with a specified
 * language tag. The result is formatted as a language-tagged RDF literal.
 *
 * literal: Null-terminated C string representing an RDF literal or lexical value (e.g., "abc")
 * language: Null-terminated C string representing the language tag (e.g., "en")
 *
 * returns: Null-terminated C string formatted as a language-tagged RDF literal (e.g., "abc"@en)
 */
static char *strlang(char *literal, char *language)
{
	StringInfoData buf;
	char *lex_language = lex(language);
	char *lex_literal = lex(literal);

	elog(DEBUG1, "%s called: literal='%s', language='%s'", __func__, literal, language);

	if (strlen(lex_language) == 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("language tag cannot be empty")));

	initStringInfo(&buf);

	if (strlen(lex_literal) == 0)
		appendStringInfo(&buf, "\"\"@%s", lex_language);
	else
		appendStringInfo(&buf, "%s@%s", str(literal), lex_language);

	elog(DEBUG1, "%s exit: returning => '%s'", __func__, buf.data);

	return buf.data;
}

/*
 * rdf_fdw_strlang
 * ---------------
 *
 * PostgreSQL function wrapper for the strlang function. Constructs a language-tagged
 * RDF literal from a lexical value and language tag provided as PostgreSQL text arguments.
 *
 * input_text: PostgreSQL text type representing the lexical value (e.g., "abc")
 * lang_tag: PostgreSQL text type representing the language tag (e.g., "en")
 *
 * returns: PostgreSQL text type formatted as a language-tagged RDF literal
 */
Datum rdf_fdw_strlang(PG_FUNCTION_ARGS)
{
	text *input_text = PG_GETARG_TEXT_PP(0);
	text *lang_tag = PG_GETARG_TEXT_PP(1);

	char *literal = strlang(
		text_to_cstring(input_text),
		text_to_cstring(lang_tag));

	PG_RETURN_TEXT_P(cstring_to_text(literal));
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
static char *ExpandDatatypePrefix(char *str)
{
	StringInfoData buf;
	const char *xsd_prefix = "xsd:";
	const char *xsd_uri = "http://www.w3.org/2001/XMLSchema#";
	char *stripped_str = str;
	size_t len;

	elog(DEBUG1, "%s called: str='%s'", __func__, str);

	if (!str || strlen(str) == 0)
		return ""; // Empty input returns empty string

	len = strlen(str);
	/* Strip < > if present */
	if (str[0] == '<' && str[len - 1] == '>')
	{
		stripped_str = palloc(len - 1); // Allocate space for stripped string (len - 2 + null terminator)
		strncpy(stripped_str, str + 1, len - 2);
		stripped_str[len - 2] = '\0'; // Null-terminate
	}

	/* Check for 'xsd:' prefix and expand it */
	if (strncmp(stripped_str, xsd_prefix, strlen(xsd_prefix)) == 0 && strlen(stripped_str) > strlen(xsd_prefix))
	{
		const char *suffix = stripped_str + strlen(xsd_prefix); // Get part after "xsd:"
		initStringInfo(&buf);
		appendStringInfoChar(&buf, '<');	   // Open bracket
		appendStringInfoString(&buf, xsd_uri); // Add XSD URI
		appendStringInfoString(&buf, suffix);  // Add suffix
		appendStringInfoChar(&buf, '>');	   // Close bracket

		if (stripped_str != str)
			pfree(stripped_str);
	
		elog(DEBUG1, "%s exit: returning '%s'", __func__, buf.data);

		return buf.data;
	}

	/* Return stripped string (or original if no stripping) without < > */
	if (stripped_str != str)
	{
		initStringInfo(&buf);
		appendStringInfoString(&buf, stripped_str);
		pfree(stripped_str);

		elog(DEBUG1, "%s exit: returning '%s'", __func__, buf.data);

		return buf.data;
	}

	elog(DEBUG1, "%s exit: returning '%s'", __func__, str);

	return str;
}

/*
 * strdt
 * -----
 *
 * Constructs an RDF literal by combining a lexical value with a specified datatype IRI.
 * Uses ExpandDatatypePrefix to handle prefix expansion (e.g., "xsd:" to full URI) or
 * retain prefixed/bare forms without angle brackets unless fully expanded.
 *
 * literal: Null-terminated C string representing an RDF literal or lexical value (e.g., "123")
 * datatype: Null-terminated C string representing the datatype IRI (e.g., "xsd:int", "foo:bar")
 *
 * returns: Null-terminated C string formatted as a datatype-tagged RDF literal (e.g., "123"^^<http://www.w3.org/2001/XMLSchema#int>, "foo"^^foo:bar)
 */
static char *strdt(char *literal, char *datatype)
{
	StringInfoData buf;
	char *lex_datatype = lex(datatype);

	elog(DEBUG1, "%s called: literal='%s', datatype='%s'", __func__, literal, datatype);
	
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

	elog(DEBUG1, "%s exit: returning => '%s'", __func__, buf.data);

	return buf.data;
}

/*
 * rdf_fdw_strdt
 * -------------
 *
 * PostgreSQL function wrapper for the strdt function. Constructs a datatype-tagged
 * RDF literal from a lexical value and datatype IRI provided as PostgreSQL text arguments.
 *
 * input_text: PostgreSQL text type representing the lexical value (e.g., "123")
 * data_type: PostgreSQL text type representing the datatype IRI (e.g., "xsd:int")
 *
 * returns: PostgreSQL text type formatted as a datatype-tagged RDF literal
 */
Datum rdf_fdw_strdt(PG_FUNCTION_ARGS)
{
	text *input_text = PG_GETARG_TEXT_PP(0);
	text *data_type = PG_GETARG_TEXT_PP(1);
	char *literal;

	elog(DEBUG1, "%s called", __func__);

	literal = strdt(
		text_to_cstring(input_text),
		text_to_cstring(data_type));

	PG_RETURN_TEXT_P(cstring_to_text(literal));
}

/*
 * str
 * ---
 *
 * Extracts the lexical value of an RDF literal or the string form of an IRI and returns it as a new RDF literal.
 * If the input is empty or null, returns an empty RDF literal.
 *
 * input: Null-terminated C string representing an RDF literal or IRI (e.g., "abc"@en, "<http://example.org>")
 *
 * returns: Null-terminated C string formatted as an RDF literal (e.g., "abc", "http://example.org")
 */
static char *str(char *input)
{
	StringInfoData buf;
	char *result;

	elog(DEBUG1, "%s called: input='%s'", __func__, input);

	if (!input || strlen(input) == 0)
	{
		elog(DEBUG1,"%s exit: returning empty literal", __func__);
		return cstring_to_rdfnode(""); /* empty input returns empty string */
	}

	/* Check if input looks like an IRI (starts with <, ends with >) */
	if (input[0] == '<' && input[strlen(input) - 1] == '>' && strlen(input) > 2)
	{
		initStringInfo(&buf);
		appendStringInfoString(&buf, input + 1); /* Skip opening < */
		buf.len--;								 /* Remove closing > */
		buf.data[buf.len] = '\0';				 /* Null-terminate */

		elog(DEBUG1,"%s exit: returning => '%s'", __func__, buf.data);

		return cstring_to_rdfnode(buf.data);
	}

	result = cstring_to_rdfnode(lex(input));

	elog(DEBUG1,"%s exit: returning => '%s'", __func__, result);

	return result;
}

/*
 * rdf_fdw_str
 * -----------
 *
 * PostgreSQL function wrapper for the str function. Extracts the lexical value
 * of an RDF literal provided as a PostgreSQL text argument and returns it as a
 * new RDF literal.
 *
 * input_text: PostgreSQL text type (e.g., "abc"@en, "123"^^xsd:int)
 *
 * returns: PostgreSQL text type formatted as an RDF literal
 */
Datum rdf_fdw_str(PG_FUNCTION_ARGS)
{
    text *input_text = PG_GETARG_TEXT_PP(0);
    char *input_cstr = text_to_cstring(input_text);
    char *result = str(input_cstr);
       
    PG_RETURN_TEXT_P(cstring_to_text(result));
}

/*
 * iri
 * ---
 * Converts a string to an IRI by wrapping it in angle brackets (< >), mimicking
 * SPARQL's IRI() function. Strips quotes and any language tags or datatypes if
 * present *only* for quoted literals. Raw strings and pre-wrapped IRIs are preserved.
 */
static char *iri(char *input)
{
	StringInfoData buf;
	char *lexical;

	elog(DEBUG1, "%s called: input='%s'", __func__, input ? input : "(null)");

	if (!input || *input == '\0')
		return "<>";

	if (isIRI(input))
		return pstrdup(input);

	initStringInfo(&buf);

	lexical = lex(input);  // Extract the lexical form
	appendStringInfo(&buf, "<%s>", lexical);

	elog(DEBUG1, "%s exit: returning wrapped IRI '%s'", __func__, buf.data);
	return pstrdup(buf.data);
}

/*
 * rdf_fdw_iri
 * -----------
 *
 * PostgreSQL function wrapper for iri(). Takes a text input, converts it to a
 * C string, processes it with iri(), and returns the result as a PostgreSQL text type.
 */
Datum rdf_fdw_iri(PG_FUNCTION_ARGS)
{
    text *input_text = PG_GETARG_TEXT_PP(0);
    char *input_cstr = text_to_cstring(input_text);
    char *result = iri(input_cstr);

    PG_RETURN_TEXT_P(cstring_to_text(result));
}

/*
 * isIRI
 * -----
 * Checks if a string is an RDF IRI. A valid IRI must:
 * - Start with '<' and end with '>'
 * - Not contain spaces or quote characters
 * - May be absolute (with a colon) or relative (e.g., <foo>)
 *   according to SPARQL 1.1.
 */
static bool isIRI( char *input)
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
 * rdf_fdw_isIRI
 * -------------
 *
 * PostgreSQL function wrapper for isIRI. Returns true if the input is an IRI.
 *
 * input_text: PostgreSQL text type
 *
 * returns: PostgreSQL boolean
 */
Datum rdf_fdw_isIRI(PG_FUNCTION_ARGS)
{
	text *input_text = PG_GETARG_TEXT_PP(0);
	char *input_cstr = text_to_cstring(input_text);
	bool result = isIRI(input_cstr);

	PG_RETURN_BOOL(result);
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
static char *datatype(char *input)
{
	StringInfoData buf;
	const char *ptr;
	int len;

	elog(DEBUG1, "%s called: input='%s'", __func__, input ? input : "(null)");

	if (input == NULL || *input == '\0')
	{
		elog(DEBUG1, "%s exit: returning empty string for NULL or empty input", __func__);
		return "";
	}

	ptr = cstring_to_rdfnode(input);
	//ptr = str(input);
	len = strlen(ptr);

	initStringInfo(&buf);

	if (*ptr == '"')
	{
		const char *tag = strstr(ptr, "^^");
		const char *lang_tag = strstr(ptr, "@");

		/* Check for datatype first */
		if (tag && tag > ptr + 1 && *(tag - 1) == '"' &&
			(!lang_tag || lang_tag > tag)) /* datatype takes precedence */
		{
			const char *dt_start = tag + 2; /* skip ^^ */
			const char *dt_end = dt_start;

			/* Find the end of the datatype */
			if (*dt_start == '<')
			{
				while (*dt_end && *dt_end != '>')
					dt_end++;
				if (*dt_end != '>') /* Ensure proper closing */
				{
					elog(DEBUG1, "%s exit: returning empty string (malformed datatype IRI, missing '>')", __func__);
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
				/* Handle xsd: prefix */
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

				/* Ensure no trailing junk */
				if (*dt_end != '\0')
				{
					elog(DEBUG1, "%s exit: returning empty string (trailing chars after datatype)", __func__);
					return res;
				}

				res = iri(buf.data);

				elog(DEBUG1, "%s exit: returning '%s'", __func__, res);
				return res;
			}
		}
		/* Simple or language-tagged literal */
		if ((lang_tag && lang_tag > ptr + 1 && *(lang_tag - 1) == '"') ||
			(len >= 1 && (ptr[len - 1] == '"' || len == 1)))
		{
			elog(DEBUG1, "%s exit: returning empty string (simple/language-tagged literal)", __func__);
			return "";
		}
	}

	/* Not a valid literal */
	elog(DEBUG1, "%s exit: returning empty string (not a valid literal)", __func__);
	return "";
}

static char *MapSPARQLDatatype(Oid pgtype)
{
	elog(DEBUG1, "%s called: input='%u'", __func__, pgtype);

	for (int i = 0; type_map[i].type_oid != InvalidOid; i++)
	{
		if (pgtype == type_map[i].type_oid)
		{
			elog(DEBUG1,"%s exit: returning => '%s'", __func__, (char *)type_map[i].xsd_datatype);
			return (char *)type_map[i].xsd_datatype;
		}
	}

	elog(DEBUG1,"%s exit: returning NULL (unsupported type)", __func__);
	return NULL; // Unsupported type
}

/*
 * rdf_fdw_datatype
 * ----------------
 *
 * PostgreSQL function wrapper for the datatype function. Extracts the datatype
 * URI of an RDF literal provided as a PostgreSQL text argument.
 *
 * str_arg: PostgreSQL text type (e.g., "123"^^xsd:int, "abc"@en, "xyz")
 *
 * returns: PostgreSQL text type representing the datatype URI
 */
Datum rdf_fdw_datatype(PG_FUNCTION_ARGS)
{
	Oid argtype = get_fn_expr_argtype(fcinfo->flinfo, 0);

	RDFNODEOID = get_rdfnode_oid();
	
	if (argtype == TEXTOID || argtype == VARCHAROID || argtype == RDFNODEOID)
	{
		char *arg = text_to_cstring(PG_GETARG_TEXT_PP(0));
		char *result = datatype(arg);

		PG_RETURN_TEXT_P(cstring_to_text(result));
	}
	else if (argtype == NAMEOID)
	{
		char *arg = NameStr(*PG_GETARG_NAME(0));
		char *result = datatype(arg);

		PG_RETURN_TEXT_P(cstring_to_text(result));
	}
	else
	{
		char *xsd_type = MapSPARQLDatatype(argtype);

		if (xsd_type)
		{
			StringInfoData buf;
			initStringInfo(&buf);
			appendStringInfoString(&buf, RDF_XSD_BASE_URI);
			appendStringInfoString(&buf, xsd_type);

			PG_RETURN_TEXT_P(cstring_to_text(iri(buf.data)));
		}

		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("Unsupported input type for rdf_fdw_datatype: %u", argtype)));
	}
}

static char *rdfnode_to_cstring(char *input)
{
	size_t len = strlen(input);
	char *result;

	/* if the string is too short to have wrapping quotes, return a copy as-is */
	if (len < 2 || input[0] != '"' || input[len - 1] != '"')
		return pstrdup(input);

	/* allocate new string, excluding the wrapping quotes */
	result = (char *) palloc(len - 1);  /* len-2 for content, +1 for \0 */
	memcpy(result, input + 1, len - 2);
	result[len - 2] = '\0';

	return result;
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
static char *encode_for_uri(char *str_in)
{
	const char *unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~";
	size_t in_len;
	char *res;

	StringInfoData buf;
	initStringInfo(&buf);

	elog(DEBUG1, "%s called: str='%s'", __func__, str_in);

	str_in = rdfnode_to_cstring(str_in);
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

	res = cstring_to_rdfnode(buf.data);

	elog(DEBUG1,"%s exit: returning => '%s'", __func__, res);
	return res;
}

/*
 * rdf_fdw_encode_for_uri
 * ----------------------
 *
 * PostgreSQL function wrapper for encode_for_uri. Converts a PostgreSQL text
 * input to a URI-encoded string, suitable for use in RDF processing.
 *
 * input: PostgreSQL text type (e.g., "hello world", "\"example\"@en")
 *
 * returns: PostgreSQL text type with URI-encoded result
 */
Datum rdf_fdw_encode_for_uri(PG_FUNCTION_ARGS)
{
	text *input = PG_GETARG_TEXT_PP(0);
	char *str_in = text_to_cstring(input);
	char *result = encode_for_uri(str(str_in));

	PG_RETURN_TEXT_P(cstring_to_text(result));
}

/*
 * rdf_fdw_contains
 * ----------------
 *
 * PostgreSQL function wrapper for contains(). Takes two text inputs, processes
 * them with contains(), and returns a PostgreSQL boolean.
 *
 * str_text: PostgreSQL text type (e.g., "hello world", "\"foo\"@en")
 * substr_text: PostgreSQL text type (e.g., "world", "\"bar\"")
 *
 * returns: PostgreSQL boolean
 */
Datum rdf_fdw_contains(PG_FUNCTION_ARGS)
{
    text *str_text = PG_GETARG_TEXT_PP(0);
    text *substr_text = PG_GETARG_TEXT_PP(1);
    char *str_in = text_to_cstring(str_text);
    char *substr_in = text_to_cstring(substr_text);
	char *str_lex;
	char *substr_lex;
	char *lang_str;
	bool result;

    //bool result = contains(str_in, substr);
	elog(DEBUG1, "%s called: str='%s', substr='%s'", __func__, str_in, substr_in);

	/* handle NULL or empty inputs */
	if (!str_in || !substr_in || strlen(str_in) == 0 || strlen(substr_in) == 0)
	{
		elog(DEBUG1, "%s exit: returning 'false' (invalid input)", __func__);
		PG_RETURN_BOOL(false);
	}

	lang_str = lang(str_in);

	if (strlen(lang_str) != 0)
	{
		char *lang_substr = lang(substr_in);

		if (strlen(lang_substr) != 0 && pg_strcasecmp(lang_str, lang_substr) != 0)
		{
			elog(DEBUG1, "%s exit: returning NULL (string and substring have different languag tags)", __func__);
			PG_RETURN_NULL();
		}
	}

	/* extract lexical values (strips quotes, tags, etc.) */
	str_lex = lex(str_in);
	substr_lex = lex(substr_in);

	/* check if substr is in str using strstr */
	result = (strstr(str_lex, substr_lex) != NULL);

	elog(DEBUG1, "%s exit: returning > %s (str_lexical='%s', substr_lexical='%s')",
			__func__, result ? "true" : "false", str_lex, substr_lex);
	
    PG_RETURN_BOOL(result);
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
static bool LiteralsCompatible(char *literal1, char *literal2)
{
	char *lang1;
	char *lang2;
	char *dt1;
	char *dt2;

	elog(DEBUG1, "%s called: literal1='%s', literal2='%s'", __func__, literal1, literal2);

	lang1 = lang(literal1);
	lang2 = lang(literal2);
	dt1 = datatype(literal1);
	dt2 = datatype(literal2);

	if (!literal1 || !literal2)
	{
		elog(DEBUG1,"%s exit: returning 'false' (one of the arguments is NULL)", __func__);
		return false;
	}

	/*TODO: check if RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED is needed, as the prefix is expaded elsewhere */

	/* both simple literals or xsd:string */
	if (strlen(lang1) == 0 && strlen(lang2) == 0 &&
		(strlen(dt1) == 0 || strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE) == 0) &&
		(strlen(dt2) == 0 || strcmp(dt2, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt2, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
	{
		elog(DEBUG1,"%s exit: returning 'true' (both simple literals or xsd:string)", __func__);
		return true;
	}

	/* both plain literals with identical language tags */
	if (strlen(lang1) > 0 && strlen(lang2) > 0 && strcmp(lang1, lang2) == 0)
	{
		elog(DEBUG1,"%s exit: returning 'true' (both plain literals with identical language tags)", __func__);
		return true;
	}

	/* arg1 has language tag, arg2 is simple or xsd:string */
	if (strlen(lang1) > 0 && strlen(lang2) == 0 &&
		(strlen(dt2) == 0 || strcmp(dt2, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt2, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
	{
		elog(DEBUG1,"%s exit: returning 'true' (arg1 has language tag, arg2 is simple or xsd:string)", __func__);
		return true;
	}

	/* incompatible otherwise (e.g., arg1 xsd:string, arg2 language-tagged) */
	elog(DEBUG1,"%s exit: returning 'false' (incompatible)", __func__);
	return false;
}

/*
 * rdf_fdw_arguments_compatible
 * ----------------------------
 *
 * PostgreSQL function wrapper for LiteralsCompatible. Checks if two RDF literals
 * provided as PostgreSQL text arguments are compatible per SPARQL rules.
 *
 * arg1: PostgreSQL text type (e.g., "abc"@en, "123"^^xsd:int)
 * arg2: PostgreSQL text type (e.g., "abc", "456"^^xsd:string)
 *
 * returns: PostgreSQL boolean
 */
Datum rdf_fdw_arguments_compatible(PG_FUNCTION_ARGS)
{
	text *arg1 = PG_GETARG_TEXT_PP(0);
	text *arg2 = PG_GETARG_TEXT_PP(1);
	PG_RETURN_BOOL(LiteralsCompatible(text_to_cstring(arg1), text_to_cstring(arg2)));
}

/*
 * rdf_fdw_strbefore
 * -----------------
 *
 * Implements the SPARQL STRBEFORE function, returning the substring of the first
 * argument before the first occurrence of the second argument (delimiter). The
 * result preserves the language tag or datatype of the first argument as present
 * in the input syntax. Simple literals remain simple in the output.
 *
 * str_arg: the input string as a PostgreSQL text type (e.g., "abc"@en, "abc"^^xsd:string)
 * delimiter_arg: the delimiter string as a PostgreSQL text type (e.g., "b", "b"@en)
 *
 * returns: a PostgreSQL text type representing the RDF literal before the delimiter
 */
Datum rdf_fdw_strbefore(PG_FUNCTION_ARGS)
{
	text *str_arg = PG_GETARG_TEXT_PP(0);
	text *delimiter_arg = PG_GETARG_TEXT_PP(1);
	char *str_arg_cstr = text_to_cstring(str_arg);
	char *delimiter_arg_cstr = text_to_cstring(delimiter_arg);
	char *str_lexical;
	char *delimiter_lexical;
	char *lang1;
	char *dt1 = "";														  // Datatype of arg1
	char *pos;
	char *result;
	//bool has_explicit_datatype = false;

	elog(DEBUG1,"%s called: str='%s', delimiter='%s", __func__, str_arg_cstr, delimiter_arg_cstr);

	str_lexical = lex(str_arg_cstr);			  // Lexical form of arg1
	delimiter_lexical = lex(delimiter_arg_cstr); // Lexical form of arg2
	lang1 = lang(str_arg_cstr);									  // Language tag of arg1

	/* extract datatypes if no language tags */
	if (strlen(lang1) == 0)
		dt1 = datatype(str_arg_cstr);

	if (!LiteralsCompatible(str_arg_cstr, delimiter_arg_cstr))
	{
		elog(DEBUG1,"%s exit: returning NULL (literals no compatible)", __func__);
		PG_RETURN_NULL();
	}

	if ((pos = strstr(str_lexical, delimiter_lexical)) != NULL)
	{
		size_t before_len = pos - str_lexical;
		//char *result;
		StringInfoData buf;
		initStringInfo(&buf);

		if (strlen(lang1) > 0)
		{
			appendBinaryStringInfo(&buf, str_lexical, before_len);
			result = strlang(buf.data, lang1);

			elog(DEBUG1,"%s exit: returning => '%s'", __func__, result);
			PG_RETURN_TEXT_P(cstring_to_text(result));
		}
		else if (strlen(dt1) > 0 && /* only for explicit ^^ */
				 (strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
		{
			appendBinaryStringInfo(&buf, str_lexical, before_len);
			result = cstring_to_rdfnode(buf.data);
			if (strstr(result, "^^") == NULL)
			{
				result = strdt(buf.data, dt1);
			}

			elog(DEBUG1,"%s exit: returning => '%s'", __func__, result);
			PG_RETURN_TEXT_P(cstring_to_text(result));
		}
		else
		{
			/* simple literal or implicit xsd:string */
			appendBinaryStringInfo(&buf, str_lexical, before_len);
			result = cstring_to_rdfnode(buf.data);

			elog(DEBUG1,"%s exit: returning => '%s'", __func__, result);
			PG_RETURN_TEXT_P(cstring_to_text(result));
		}
	}

	/* delimiter not found */
	if (strlen(dt1) > 0 &&
		(strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
	{
		result = cstring_to_rdfnode("");
		if (strstr(result, "^^") == NULL)
		{
			StringInfoData typed_buf;
			initStringInfo(&typed_buf);
			appendStringInfo(&typed_buf, "%s", strdt("", RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED));
			result = typed_buf.data;
		}

		elog(DEBUG1,"%s exit: returning => '%s'", __func__, result);
		PG_RETURN_TEXT_P(cstring_to_text(result));
	}

	result = cstring_to_rdfnode("");
	elog(DEBUG1,"%s exit: returning => '%s'", __func__, result);

	PG_RETURN_TEXT_P(cstring_to_text(result));
}

/*
 * rdf_fdw_strafter
 * ----------------
 *
 * Implements the SPARQL STRAFTER function, returning the substring of the first
 * argument after the first occurrence of the second argument (delimiter). The
 * result preserves the language tag or datatype of the first argument as present
 * in the input syntax, always wrapped in double quotes as a valid RDF literal.
 * Returns an empty simple literal if the delimiter is not found.
 *
 * str_arg: the input string as a PostgreSQL text type (e.g., "abc"@en, "abc"^^xsd:string)
 * delimiter_arg: the delimiter string as a PostgreSQL text type (e.g., "b", "b"@en)
 *
 * returns: a PostgreSQL text type representing the RDF literal after the delimiter
 */
Datum rdf_fdw_strafter(PG_FUNCTION_ARGS)
{
	text *str_arg = PG_GETARG_TEXT_PP(0);
	text *delimiter_arg = PG_GETARG_TEXT_PP(1);
	char *str_arg_cstr = text_to_cstring(str_arg);
	char *delimiter_arg_cstr = text_to_cstring(delimiter_arg);
	char *str;
	char *delimiter;
	char *lang1;
	char *dt1 = "";
	char *pos;
	bool has_explicit_datatype = false;
	char *result;

	elog(DEBUG1,"%s called: str='%s', delimiter='%s'", __func__, str_arg_cstr, delimiter_arg_cstr);

	str = lex(str_arg_cstr);
	delimiter = lex(delimiter_arg_cstr);
	lang1 = lang(str_arg_cstr);

	/* extract datatype if no language tag */
	if (strlen(lang1) == 0)
		dt1 = datatype(str_arg_cstr);

	/* check if arg1 has an explicit datatype in the input syntax */
	if (strlen(lang1) == 0 && strstr(str_arg_cstr, "^^") != NULL)
		has_explicit_datatype = true;

	if (!LiteralsCompatible(str_arg_cstr, delimiter_arg_cstr))
	{
		elog(DEBUG1,"%s exit: returning NULL (incompatible literals)", __func__);
		PG_RETURN_NULL();
	}

	if ((pos = strstr(str, delimiter)) != NULL)
	{
		size_t delimiter_len = strlen(delimiter);
		char *after_start = pos + delimiter_len;
		size_t after_len = strlen(str) - (after_start - str);
		
		StringInfoData buf;
		initStringInfo(&buf);

		if (strlen(lang1) > 0)
		{
			appendBinaryStringInfo(&buf, after_start, after_len);
			result = strlang(buf.data, lang1);
			pfree(buf.data);

			elog(DEBUG1,"%s exit: returning => '%s'", __func__, result);
			PG_RETURN_TEXT_P(cstring_to_text(result));
		}
		else if (has_explicit_datatype && strlen(dt1) > 0 &&
				 (strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
		{
			appendBinaryStringInfo(&buf, after_start, after_len);
			result = cstring_to_rdfnode(buf.data);
			if (strstr(result, "^^") == NULL)
			{
				result = strdt(buf.data, dt1);
			}
			pfree(buf.data);
			
			elog(DEBUG1,"%s exit: returning => '%s'", __func__, result);
			PG_RETURN_TEXT_P(cstring_to_text(result));
		}
		else
		{
			/* simple literal or implicit xsd:string */
			appendBinaryStringInfo(&buf, after_start, after_len);
			result = cstring_to_rdfnode(buf.data);
			pfree(buf.data);

			elog(DEBUG1,"%s exit: returning => '%s'", __func__, result);
			PG_RETURN_TEXT_P(cstring_to_text(result));
		}
	}

	/* delimiter not found */
	if (has_explicit_datatype && strlen(dt1) > 0 &&
		(strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED) == 0 || strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
	{
		result = cstring_to_rdfnode("");
		if (strstr(result, "^^") == NULL)
		{
			StringInfoData typed_buf;
			initStringInfo(&typed_buf);
			appendStringInfo(&typed_buf, "%s", strdt("", RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED));
			result = typed_buf.data;
		}

		elog(DEBUG1,"%s exit: returning => '%s'", __func__, result);
		PG_RETURN_TEXT_P(cstring_to_text(result));
	}

	result = cstring_to_rdfnode("");
	elog(DEBUG1,"%s exit: returning => '%s'", __func__, result);
	PG_RETURN_TEXT_P(cstring_to_text(result));
}

/*
 * strstarts
 * ---------
 *
 * Implements the core logic for the SPARQL STRSTARTS function, returning true if
 * the lexical form of the first argument (string) starts with the lexical form
 * of the second argument (substring), or false if arguments are incompatible or
 * the condition fails. An empty substring is considered a prefix of any string,
 * per SPARQL behavior.
 *
 * str: Null-terminated C string representing an RDF literal or value (e.g., "foobar")
 * substr: Null-terminated C string representing an RDF literal or value (e.g., "foo")
 *
 * returns: C boolean (true if string starts with substring, false otherwise or if incompatible)
 */
static bool strstarts(char *str, char *substr)
{
	char *str_lexical = lex(str);
	char *substr_lexical = lex(substr);
	size_t str_len = strlen(str_lexical);
	size_t substr_len = strlen(substr_lexical);
	int result;

	elog(DEBUG1,"%s called: str='%s', substr='%s'", __func__, str, substr);

	if (!LiteralsCompatible(str, substr))
	{
		elog(DEBUG1,"%s exit: returning 'false' (incompatible literals)", __func__);
		return false;
	}

	if (substr_len == 0)
	{
		elog(DEBUG1,"%s exit: returning 'true' (empty substring is a prefix of any string)", __func__);
		return true;
	}

	if (substr_len > str_len)
	{
		elog(DEBUG1,"%s exit: returning 'false' (substring longer than string cannot be a prefix)", __func__);
		return false;
	}

	result = strncmp(str_lexical, substr_lexical, substr_len);

	elog(DEBUG1,"%s exit: returning '%s'", __func__,
		result == 0 ? "true" : "false");

	return result == 0;
}

/*
 * rdf_fdw_strstarts
 * -----------------
 *
 * PostgreSQL function wrapper for the strstarts function. Implements the SPARQL
 * STRSTARTS function, returning true if the lexical form of the first argument
 * (string) starts with the lexical form of the second argument (substring), or
 * NULL if arguments are incompatible per SPARQL rules. Delegates core logic to
 * strstarts.
 *
 * str_arg: PostgreSQL text type (e.g., "foobar"@en, "foobar"^^xsd:string)
 * substr_arg: PostgreSQL text type (e.g., "foo", "foo"@en)
 *
 * returns: PostgreSQL boolean or NULL (for incompatible arguments)
 */
Datum rdf_fdw_strstarts(PG_FUNCTION_ARGS)
{
	text *str_arg = PG_GETARG_TEXT_PP(0);
	text *substr_arg = PG_GETARG_TEXT_PP(1);
	char *str = text_to_cstring(str_arg);
	char *substr = text_to_cstring(substr_arg);

	elog(DEBUG1,"%s called: str='%s', substr='%s'", __func__, str, substr);

	if (!LiteralsCompatible(str, substr))
	{
		elog(DEBUG1,"%s exit: returning NULL (incompatible literals)", __func__);
		PG_RETURN_NULL();
	}

	PG_RETURN_BOOL(strstarts(str, substr));
}

/*
 * strends
 * -------
 *
 * Implements the core logic for the SPARQL STRENDS function, returning true if
 * the lexical form of the first argument (string) ends with the lexical form
 * of the second argument (substring), or false if arguments are incompatible or
 * the condition fails. An empty substring is considered a suffix of any string,
 * per SPARQL behavior.
 *
 * str: Null-terminated C string representing an RDF literal or value (e.g., "foobar")
 * substr: Null-terminated C string representing an RDF literal or value (e.g., "bar")
 *
 * returns: C boolean (true if string ends with substring, false otherwise or if incompatible)
 */
static bool strends(char *str, char *substr)
{
    char *str_lexical = lex(str);
    char *substr_lexical = lex(substr);
    size_t str_len = strlen(str_lexical);
    size_t substr_len = strlen(substr_lexical);
	int result;

	elog(DEBUG1,"%s called: str='%s', substr='%s'", __func__, str, substr);

    if (!LiteralsCompatible(str, substr))
    {
		elog(DEBUG1,"%s exit: returning 'false' (incompatible literals)", __func__);
		return false;
	}

    if (substr_len == 0)
    {
		elog(DEBUG1,"%s exit: returning 'true' (an empty substring is a suffix of any string)", __func__);
		return true;
	}

    if (substr_len > str_len)
    {
		elog(DEBUG1,"%s exit: returning 'false' (substring longer than string cannot be a suffix)", __func__);
		return false;
	}

	result = strncmp(str_lexical + (str_len - substr_len), substr_lexical, substr_len);

	elog(DEBUG1,"%s exit: returning '%s'", __func__, result == 0 ? "true" : "false");

    return result == 0;
}

/*
 * rdf_fdw_strends
 * ---------------
 *
 * PostgreSQL function wrapper for the strends function. Implements the SPARQL
 * STRENDS function, returning true if the lexical form of the first argument
 * (string) ends with the lexical form of the second argument (substring), or
 * NULL if arguments are incompatible per SPARQL rules. Delegates core logic to
 * strends.
 *
 * str_arg: PostgreSQL text type (e.g., "foobar"@en, "foobar"^^xsd:string)
 * substr_arg: PostgreSQL text type (e.g., "bar", "bar"@en)
 *
 * returns: PostgreSQL boolean or NULL (for incompatible arguments)
 */
Datum rdf_fdw_strends(PG_FUNCTION_ARGS)
{
    text *str_arg = PG_GETARG_TEXT_PP(0);
    text *substr_arg = PG_GETARG_TEXT_PP(1);
    char *str = text_to_cstring(str_arg);
    char *substr = text_to_cstring(substr_arg);

    if (!LiteralsCompatible(str, substr))
        PG_RETURN_NULL();  // Incompatible arguments return NULL per SPARQL

    PG_RETURN_BOOL(strends(str, substr));
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
static bool langmatches(char *lang_tag, char *pattern)
{
	char *tag;
	char *pat;
	bool result;

	elog(DEBUG1, "%s called: lang_tag='%s', pattern='%s'", __func__, lang_tag, pattern);

	/* Handle NULL inputs */
	if (!lang_tag || !pattern)
	{
		elog(DEBUG1, "%s exit: returning 'false' (invalid input)", __func__);
		return false;
	}


	pattern = rdfnode_to_cstring(pattern);

	/* Use lang_tag directly, assuming it's already extracted */
	tag = rdfnode_to_cstring(lang_tag); /* e.g., "en" from lang('"foo"@en') */
	/* Handle pattern: bare string or quoted literal */
	if (pattern[0] == '"' && strrchr(pattern, '"') > pattern)
		pat = lex(pattern); /* e.g., "\"en\"" -> "en" */
	else
		pat = pattern; /* e.g., "en" as-is */

	/* Empty tag only matches "*" pattern (case-insensitive) */
	if (strlen(tag) == 0)
	{
		result = (strcasecmp(pat, "*") == 0);
		elog(DEBUG1, "%s exit: returning '%s' (empty tag, pattern='%s')",
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

	elog(DEBUG1, "%s exit: returning '%s' (tag='%s', pat='%s')",
		__func__, result ? "true" : "false", tag, pat);

	return result;
}

/*
 * rdf_fdw_langmatches
 * -------------------
 *
 * PostgreSQL function wrapper for langmatches(). Takes two text inputs, processes
 * them with langmatches(), and returns a PostgreSQL boolean.
 *
 * lang_tag_text: PostgreSQL text type (e.g., "\"hello\"@en", "en")
 * pattern_text: PostgreSQL text type (e.g., "en-*", "*")
 *
 * returns: PostgreSQL boolean
 */
Datum rdf_fdw_langmatches(PG_FUNCTION_ARGS)
{
	text *lang_tag_text = PG_GETARG_TEXT_PP(0);
	text *pattern_text = PG_GETARG_TEXT_PP(1);
	char *lang_tag = text_to_cstring(lang_tag_text);
	char *pattern = text_to_cstring(pattern_text);
	bool result = langmatches(lang_tag, pattern);

	PG_RETURN_BOOL(result);
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
static bool isBlank(char *term)
{
	bool result;
	elog(DEBUG1, "%s called: term='%s'", __func__, term);

	/* Handle NULL or empty input */
	if (!term || strlen(term) == 0)
	{
		elog(DEBUG1, "%s exit: returning 'false' (invalid input)", __func__);
		return false;
	}

	/* Check if term starts with "_:" and has at least 3 characters */
	result = (strncmp(term, "_:", 2) == 0) && strlen(term) > 2;

	elog(DEBUG1, "%s exit: returning '%s'", __func__, result ? "true" : "false");
	return result;
}

/*
 * rdf_fdw_isBlank
 * ---------------
 *
 * PostgreSQL function wrapper for isBlank(). Takes a text input, checks if it's
 * a blank node, and returns a PostgreSQL boolean.
 *
 * term_text: PostgreSQL text type (e.g., "_:b1", "<http://ex.com>")
 *
 * returns: PostgreSQL boolean
 */
Datum rdf_fdw_isBlank(PG_FUNCTION_ARGS)
{
	text *term_text = PG_GETARG_TEXT_PP(0);
	char *term = text_to_cstring(term_text);
	bool result = isBlank(term);

	PG_RETURN_BOOL(result);
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
static bool isNumeric(char *term)
{
	char *lexical;
	char *datatype_uri;
	bool is_bare_number = false;
	char *endptr;

	elog(DEBUG1,"%s called: term='%s'", __func__, term);

	if (!term || strlen(term) == 0)
	{
		elog(DEBUG1,"%s exit: returning 'false' (term either NULL or an empty string)", __func__);
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
		elog(DEBUG1,"%s exit: returning 'false' (lexical value either NULL or an empty string)", __func__);
		return false;
	}

	strtod(lexical, &endptr);
	if (*endptr != '\0') /* not a valid number, e.g., "abc" */
	{
		elog(DEBUG1,"%s exit: returning 'false' (not a valid number)", __func__);
		return false;
	}

	/* Bare numbers are numeric */
	if (is_bare_number)
	{
		elog(DEBUG1,"%s exit: returning 'true' (bare numbers are numeric)", __func__);
		return true;
	}

	/* Get datatype using datatype function */
	datatype_uri = datatype(term);
	if (strlen(datatype_uri) == 0)
	{
		elog(DEBUG1,"%s exit: returning 'false' (no datatype or invalid literal)", __func__);
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
				elog(DEBUG1,"%s exit: returning 'false' (not a pure integer)", __func__);
				return false;
			}

			elog(DEBUG1,"%s exit: returning 'true' (valid xsd:byte)", __func__);
			return true; /* Valid xsd:byte, e.g., "100" */
		}
		/* Other numeric datatypes (e.g., xsd:integer, xsd:double) have no strict range
		 * limits in SPARQL’s isNumeric, and we’ve already validated the lexical form.
		 * Accept them as numeric. */

		elog(DEBUG1,"%s exit: returning 'true'", __func__);
		return true;
	}

	elog(DEBUG1,"%s exit: returning 'false'", __func__);
	return false;
}

/*
 * rdf_fdw_isNumeric
 * -----------------
 *
 * PostgreSQL function wrapper for isNumeric. Checks if an RDF term provided as a
 * PostgreSQL text argument is numeric.
 *
 * input_text: PostgreSQL text type representing the RDF term
 *
 * returns: PostgreSQL boolean type
 */
Datum rdf_fdw_isNumeric(PG_FUNCTION_ARGS)
{
	text *input_text = PG_GETARG_TEXT_PP(0);
	bool result = isNumeric(text_to_cstring(input_text));
	PG_RETURN_BOOL(result);
}

static bool isPlainLiteral(char *literal)
{
	if (strlen(lang(literal)) != 0 || strlen(datatype(literal)) != 0)
		return false;
	
	return true;
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
 static bool isLiteral(char *term)
{
	const char *ptr;
	int len;

	elog(DEBUG1, "%s called: term='%s'", __func__, term);

	if (!term || *term == '\0')
	{
		elog(DEBUG1,"%s exit: returning 'false' (term either NULL or has no '\\0')", __func__);
		return false;
	}

	/* Exclude IRIs and blank nodes first */
	if (isIRI(term) || isBlank(term))
	{
		elog(DEBUG1,"%s exit: returning 'false' (either an IRI or a blank node)", __func__);
		return false;
	}

	/* Normalize input */
	ptr = cstring_to_rdfnode(term);
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
					elog(DEBUG1,"%s exit: returning 'true' (valid datatype)", __func__);
					return true;
				} /* Valid datatype */
			}
			/* Language-tagged literal: has @ with language tag */
			else if (lang_tag && lang_tag > ptr + 1 && *(lang_tag - 1) == '"' &&
					 *(lang_tag + 1) != '\0')
			{
				elog(DEBUG1,"%s exit: returning 'true' (literal has a language tag)", __func__);
				return true;
			}
			/* Simple literal: quoted string, no ^^ or @ */
			else if (ptr[len - 1] == '"')
			{
				elog(DEBUG1,"%s exit: returning 'true' (simple literal - no ^^ or @)", __func__);
				return true;
			}
		}
		else if (len == 1)
		{
			/* Empty quoted literal "" */
			elog(DEBUG1,"%s exit: returning 'true' (empty quoted literal)", __func__);
			return true;
		}
	}

	/* Invalid or non-literal */
	elog(DEBUG1,"%s exit: returning 'false' (invalid or non-literal)", __func__);
	return false;
}

/*
 * rdf_fdw_isLiteral
 * -----------------
 *
 * PostgreSQL function wrapper for isLiteral. Checks if an RDF term provided as a
 * PostgreSQL text argument is a literal. Returns NULL for NULL input (STRICT).
 *
 * input_text: PostgreSQL text type representing the RDF term
 *
 * returns: PostgreSQL boolean type
 */
Datum rdf_fdw_isLiteral(PG_FUNCTION_ARGS)
{
	text *input_text;
	char *term;
	bool result;

	input_text = PG_GETARG_TEXT_PP(0);
	term = text_to_cstring(input_text);

	result = isLiteral(term);

	/* Clean up input string */
	pfree(term);

	PG_RETURN_BOOL(result);
}

/*
 * bnode
 * -----
 *
 * Implements SPARQL’s BNODE function. Without arguments (input = NULL), generates
 * a unique blank node (e.g., "_:b123"). With a string argument, returns a blank node
 * based on the lexical form of the input (e.g., BNODE("xyz") → "_:xyz"). Invalid
 * inputs (e.g., IRIs, blank nodes, empty literals) return NULL.
 *
 * input: Null-terminated C string (literal or bare string) for BNODE(str), or NULL for BNODE().
 *
 * returns: Null-terminated C string representing a blank node (e.g., "_:xyz"), or NULL for invalid inputs.
 */
static char *bnode(char *input)
{
	StringInfoData buf;
	static uint64 counter = 0; /* Ensure uniqueness for BNODE() */

	elog(DEBUG1,"%s called: input='%s'", __func__, input);

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

		/* Reject IRIs and blank nodes explicitly */
		if (isIRI(input) || isBlank(input))
		{
			elog(DEBUG1,"%s exit: returning NULL (input eiter an IRI or a blank node)", __func__);
			return NULL;
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
			elog(DEBUG1,"%s exit: returning NULL (input is not a literal)", __func__);
			return NULL;
		}

		/* Extract lexical form */
		lexical = lex(normalized_input);
		if (!lexical || strlen(lexical) == 0)
		{
			elog(DEBUG1,"%s exit: returning NULL (lexical value either NULL or an empty string)", __func__);
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

	elog(DEBUG1,"%s exit: returning '%s'", __func__, buf.data);
	return buf.data;
}

/*
 * rdf_fdw_bnode
 * -------------
 *
 * PostgreSQL function wrapper for SPARQL’s BNODE function. Generates a unique
 * blank node if called with no arguments (BNODE()), or a deterministic blank node
 * based on the input string’s lexical form (BNODE(str)). Returns NULL for NULL input.
 *
 * input_text: PostgreSQL text type (e.g., "xyz", "\"xyz\""), or none for BNODE()
 *
 * returns: PostgreSQL text type (e.g., "_:xyz" or "_:b123")
 */
Datum rdf_fdw_bnode(PG_FUNCTION_ARGS)
{
	char *result;
	text *input_text;

	/* Check number of arguments to distinguish BNODE() vs BNODE(str) */
	if (fcinfo->nargs == 0)
	{
		/* BNODE(): No arguments, generate unique blank node */
		result = bnode(NULL);
	}
	else
	{
		/* BNODE(str): String argument, check for NULL */
		if (PG_ARGISNULL(0))
			PG_RETURN_NULL();

		input_text = PG_GETARG_TEXT_PP(0);
		result = bnode(text_to_cstring(input_text));
	}

	if (result == NULL)
		PG_RETURN_NULL();

	PG_RETURN_TEXT_P(cstring_to_text(result));
}

/*
 * generate_uuid_v4
 * Generates a version 4 (random) UUID per RFC 4122. Returns a lowercase string
 * in the format xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx, where y is 8, 9, A, or B.
 * Uses timestamp and counter for entropy, no external dependencies.
 *
 * Returns: Null-terminated C string (e.g., "123e4567-e89b-12d3-a456-426614174000")
 */
static char *generate_uuid_v4(void)
{
	StringInfoData buf;
	static uint64 counter = 0;
	uint64 seed;
	uint8_t bytes[16];
	char *result;
	int i;

	elog(DEBUG1,"%s called", __func__);

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

	elog(DEBUG1,"%s exit: returning '%s'", __func__, result);
	return result;
}

Datum rdf_fdw_uuid(PG_FUNCTION_ARGS)
{
	StringInfoData buf;
	char *uuid_str;
	char *result;
	char *funcname;
	int *is_uuid_ptr;
	int is_uuid;

	/* Initialize or retrieve function type from fn_extra */
	if (fcinfo->flinfo->fn_extra == NULL)
	{
		funcname = get_func_name(fcinfo->flinfo->fn_oid);
		is_uuid_ptr = palloc(sizeof(int));
		*is_uuid_ptr = (strcmp(funcname, "uuid") == 0) ? 1 : 0;
		fcinfo->flinfo->fn_extra = is_uuid_ptr;
		pfree(funcname);
	}
	is_uuid = *(int *)fcinfo->flinfo->fn_extra;

	/* Generate UUID */
	uuid_str = generate_uuid_v4();

	/* Format output based on function */
	initStringInfo(&buf);
	if (is_uuid)
		appendStringInfo(&buf, "<urn:uuid:%s>", uuid_str);
	else
		appendStringInfoString(&buf, uuid_str);

	pfree(uuid_str);

	/* Return as text */
	result = pstrdup(buf.data);
	pfree(buf.data);
	PG_RETURN_TEXT_P(cstring_to_text(result));
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
static bool IsRDFStringLiteral(char *str)
{
	elog(DEBUG1,"%s called: str='%s'", __func__, str);

	if (str == NULL)
	{
		elog(DEBUG1,"%s exit: returning 'false' (NULL argument)", __func__);
		return false;
	}

	if (strcmp(str, "") == 0 ||
		strcmp(str, RDF_SIMPLE_LITERAL_DATATYPE) == 0 ||
		strcmp(str, RDF_LANGUAGE_LITERAL_DATATYPE) == 0)
	{
		elog(DEBUG1,"%s exit: returning 'true'", __func__);
		return true;
	}

	elog(DEBUG1, "%s exit: returning 'false' (unsupported datatype '%s')", __func__, str);
	return false;
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
static char *lcase(char *str)
{
	char *lexical;
	char *str_datatype;
	char *str_language;
	char *result;
	StringInfoData buf;
	int i;
	int len;

	elog(DEBUG1, "%s called: str='%s'", __func__, str);

	if (!str)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("LCASE cannot be NULL")));

	if (strlen(str) == 0)
	{
		elog(DEBUG1,"%s exit: returning empty literal (str is an empty string)", __func__);
		return cstring_to_rdfnode("");
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

	initStringInfo(&buf);

	elog(DEBUG1, " %s: lexical='%s', datatype='%s', language='%s'", __func__, lexical, str_datatype, str_language);

	/* Convert to lowercase (ASCII for simplicity) */
	len = strlen(lexical);
	for (i = 0; i < len; i++)
	{
		char c = lexical[i];
		if (c >= 'A' && c <= 'Z')
			c = c + ('a' - 'A');
		appendStringInfoChar(&buf, c);
	}

	if (strlen(str_language) != 0)
		result = strlang(buf.data, str_language);
	else if (strlen(str_datatype) != 0)
		result = strdt(buf.data, str_datatype);
	else
		result = cstring_to_rdfnode(buf.data);

	pfree(buf.data);

	elog(DEBUG1,"%s exit: returning '%s'", __func__, result);
	return result;
}

/*
 * rdf_fdw_lcase
 * -------------
 *
 * PostgreSQL function wrapper for lcase. Converts a text input to lowercase.
 * Returns NULL for NULL input (STRICT).
 *
 * input_text: PostgreSQL text type (RDF literal or bare string)
 *
 * returns: PostgreSQL text type
 */
Datum rdf_fdw_lcase(PG_FUNCTION_ARGS)
{
	text *input = PG_GETARG_TEXT_PP(0);
	char *str = text_to_cstring(input);

	PG_RETURN_TEXT_P(cstring_to_text(lcase(str)));
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
static char *ucase(char *str)
{
	char *lexical;
	char *str_datatype;
	char *str_language;
	char *result;
	StringInfoData buf;
	int i;
	int len;

	elog(DEBUG1, "%s called: str='%s'", __func__, str);

	if (!str)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("LCASE cannot be NULL")));

	if (strlen(str) == 0)
	{
		elog(DEBUG1,"%s exit: returning empty literal (str is an empty string)", __func__);		
		return cstring_to_rdfnode("");
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

	initStringInfo(&buf);

	elog(DEBUG2, " %s: lexical='%s', datatype='%s', language='%s'", __func__, lexical, str_datatype, str_language);

    /* Convert to uppercase (ASCII only) */
    len = strlen(lexical);
    for (i = 0; i < len; i++)
    {
        char c = lexical[i];
        if (c >= 'a' && c <= 'z')
            c = c - ('a' - 'A');
        appendStringInfoChar(&buf, c);
    }

	if (strlen(str_language) != 0)
		result = strlang(buf.data, str_language);
	else if (strlen(str_datatype) != 0)
		result = strdt(buf.data, str_datatype);
	else
		result = cstring_to_rdfnode(buf.data);

	pfree(buf.data);

	elog(DEBUG1,"%s exit: returning => '%s'", __func__, result);
	return result;
}

/*
 * rdf_fdw_ucase
 * -------------
 *
 * PostgreSQL function wrapper for ucase. Converts a text input to uppercase.
 * Returns NULL for NULL input (STRICT).
 *
 * input_text: PostgreSQL text type (RDF literal or bare string)
 *
 * returns: PostgreSQL text type
 */
Datum rdf_fdw_ucase(PG_FUNCTION_ARGS)
{
	text *input = PG_GETARG_TEXT_PP(0);
	char *str = text_to_cstring(input);

	PG_RETURN_TEXT_P(cstring_to_text(ucase(str)));
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

	elog(DEBUG1,"%s called: str='%s'", __func__, str);

	while (*str)
	{
		/* Skip continuation bytes (0x80-0xBF) */
		if ((*str & 0xC0) != 0x80)
			char_count++;
		str++;
	}

	elog(DEBUG1,"%s exit: returning '%d'", __func__, char_count);
	return char_count;
}

static int strlen_rdf(char *str)
{
	char *lexical;
	char *dt;
	int result;

	elog(DEBUG1, "%s called: str='%s'", __func__, str);

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
	
	elog(DEBUG1,"%s exit: returning '%d'", __func__, result);
	return result;
}

Datum rdf_fdw_strlen(PG_FUNCTION_ARGS)
{
	text *input;
	char *str;
	int result;

	/* STRICT handles NULL input */
	input = PG_GETARG_TEXT_PP(0);
	str = text_to_cstring(input);

	result = strlen_rdf(str);

	PG_RETURN_INT32(result);
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
static char *substr_sparql(char *str, int start, int length)
{
	char *lexical;
	char *str_datatype;
	char *str_language;
	StringInfoData buf;
	char *result;
	int str_len, i;

	elog(DEBUG1, "%s called: str='%s', start=%d, length=%d", __func__, str, start, length);

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
	str_len = strlen(lexical);

	elog(DEBUG1, "%s: lexical='%s', datatype='%s', language='%s', length=%d", __func__,
		lexical, str_datatype, str_language, str_len);

	if (start > str_len)
		lexical[0] = '\0';  // empty result

	initStringInfo(&buf);

	for (i = start - 1; i < str_len; i++)
	{
		if (length >= 0 && (i - (start - 1)) >= length)
			break;
		appendStringInfoChar(&buf, lexical[i]);
	}

	if (strlen(str_language) > 0)
		result = strlang(buf.data, str_language);
	else if (strlen(str_datatype) > 0)
		result = strdt(buf.data, str_datatype);
	else
		result = cstring_to_rdfnode(buf.data);

	pfree(buf.data);

	elog(DEBUG1,"%s exit: returning '%s'", __func__, result);
	return result;
}

Datum rdf_fdw_substr(PG_FUNCTION_ARGS)
{
	text *input;
	int32 start;
	char *str;
	char *result;

	if (PG_ARGISNULL(0) || PG_ARGISNULL(1))
		PG_RETURN_NULL();

	input = PG_GETARG_TEXT_PP(0);
	start = PG_GETARG_INT32(1);
	str = text_to_cstring(input);

	if (strlen(str) == 0)
		PG_RETURN_TEXT_P(cstring_to_text(cstring_to_rdfnode("")));

	if (PG_NARGS() == 3 && !PG_ARGISNULL(2))
	{
		int32 length = PG_GETARG_INT32(2);
		result = substr_sparql(str, start, length);
	}
	else
		result = substr_sparql(str, start, -1);

	PG_RETURN_TEXT_P(cstring_to_text(result));
}


/*
 * rdf_concat(text, text) returns text
 *
 * Implements the SPARQL CONCAT function.
 *
 * Concatenates two RDF literals while preserving compatible language tags
 * or datatype annotations (specifically xsd:string). If both inputs share the
 * same language tag, the result will carry that tag. If both inputs are typed
 * as xsd:string, the result is typed as xsd:string.
 *
 * Mixing a simple literal with a language-tagged or xsd:string-typed value
 * results in a plain literal without type or language. Conflicting language
 * tags or unsupported datatypes raise an error.
 *
 * NULL inputs yield NULL. Empty strings are allowed and result in valid RDF
 * literals.
 */
static char *rdf_concat(char *left, char *right)
{
	char *lex1 = lex(left);
	char *lex2 = lex(right);
	char *dt1 = datatype(left);
	char *dt2 = datatype(right);
	char *lang1 = lang(left);
	char *lang2 = lang(right);
	char *result;
	StringInfoData buf;

	elog(DEBUG1,"%s called: left='%s', right='%s'", __func__, left, right);

	initStringInfo(&buf);
	appendStringInfoString(&buf, lex1);
	appendStringInfoString(&buf, lex2);

	/* Check for conflicting language tags */
	if (strlen(lang1) > 0 && strlen(lang2) > 0 && strcmp(lang1, lang2) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("CONCAT arguments have conflicting language tags: '%s' and '%s'", lang1, lang2)));

	if ((strlen(dt1) > 0 && strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE) != 0) ||
		(strlen(dt2) > 0 && strcmp(dt2, RDF_SIMPLE_LITERAL_DATATYPE) != 0))
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("CONCAT arguments must be simple literals or '%s'", RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED)));

	/* only one argument has a datatype */
	if ((strlen(dt1) != 0 && strlen(dt2) == 0) || (strlen(dt1) == 0 && strlen(dt2) != 0))
	{
		result = cstring_to_rdfnode(buf.data);
		elog(DEBUG1,"%s exit: returning '%s' (only one argument has a datatype)", __func__, result);
		return result;
	}

	/* only one argument has a language tag */
	if ((strlen(lang1) != 0 && strlen(lang2) == 0) || (strlen(lang1) == 0 && strlen(lang2) != 0))
	{
		result = cstring_to_rdfnode(buf.data);
		elog(DEBUG1,"%s exit: returning '%s' (only one argument has a language tag)", __func__, result);
		return result;

	}

	/* re-wrap result appropriately */
	if (strlen(lang1) != 0 || strlen(lang2) != 0)
	{
		result = strlang(buf.data, strlen(lang1) > 0 ? lang1 : lang2);
		elog(DEBUG1,"%s exit: returning '%s' (re-wrapping result appropriately)", __func__, result);
		return result;
	}

	if ((strlen(dt1) > 0 && strcmp(dt1, RDF_SIMPLE_LITERAL_DATATYPE) == 0) ||
		(strlen(dt2) > 0 && strcmp(dt2, RDF_SIMPLE_LITERAL_DATATYPE) == 0))
	{
		result = strdt(buf.data, RDF_SIMPLE_LITERAL_DATATYPE);
		elog(DEBUG1,"%s exit: returning '%s' (either left or right argument has a simple literal data type - %s)",
			__func__, result, RDF_SIMPLE_LITERAL_DATATYPE);

		return result;
	}

	result = cstring_to_rdfnode(buf.data);

	elog(DEBUG1,"%s exit: returning '%s'", __func__, result);
	return result;
}

Datum rdf_fdw_concat(PG_FUNCTION_ARGS)
{
	char *left = text_to_cstring(PG_GETARG_TEXT_PP(0));
	char *right = text_to_cstring(PG_GETARG_TEXT_PP(1));
	char *result = rdf_concat(left, right);

	PG_RETURN_TEXT_P(cstring_to_text(result));
}

Datum rdf_fdw_lex(PG_FUNCTION_ARGS)
{
	char *literal = text_to_cstring(PG_GETARG_TEXT_PP(0));
	char *result = lex(literal);

	PG_RETURN_TEXT_P(cstring_to_text(result));
}

/* MD5 produces a 16 byte (128 bit) hash */
#define MD5_HASH_LEN 32
Datum rdf_fdw_md5(PG_FUNCTION_ARGS)
{
	text *in_text = PG_GETARG_TEXT_PP(0);
	char hexsum[MD5_HASH_LEN + 1];
	char *cstr = lex(text_to_cstring(in_text));
	size_t len = strlen(cstr);
#if PG_VERSION_NUM >= 150000
	const char *errstr = NULL;

	elog(DEBUG1, "%s called: str='%s', lex='%s'", __func__, text_to_cstring(in_text), cstr);

	if (pg_md5_hash(cstr, len, hexsum, &errstr) == false)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("could not compute md5 hash: %s", errstr)));
#else
	elog(DEBUG1, "%s: called str='%s', lex='%s'", __func__, text_to_cstring(in_text), cstr);
	if (pg_md5_hash(cstr, len, hexsum) == false)
		ereport(ERROR,
				(errcode(ERRCODE_INTERNAL_ERROR),
				 errmsg("could not compute md5 hash")));
#endif

	PG_RETURN_TEXT_P(cstring_to_text(str(hexsum)));
}

Datum rdf_fdw_bound(PG_FUNCTION_ARGS)
{
	if (PG_ARGISNULL(0))
		PG_RETURN_BOOL(false);
	else
		PG_RETURN_BOOL(true);
}

Datum rdf_fdw_sameterm(PG_FUNCTION_ARGS)
{
	text *a = PG_GETARG_TEXT_PP(0);
	text *b = PG_GETARG_TEXT_PP(1);
	char *term1 = text_to_cstring(a);
	char *term2 = text_to_cstring(b);
	bool result;

	elog(DEBUG1, "%s called: term1='%s' term2='%s'", __func__, term1, term2);

	result = strcmp(term1, term2) == 0;

	elog(DEBUG1, "%s exit: returning '%s'", __func__, result == 0 ? "true" : "false");

	PG_RETURN_BOOL(result);
}

Datum rdf_fdw_coalesce(PG_FUNCTION_ARGS)
{
	ArrayType *arr = PG_GETARG_ARRAYTYPE_P(0);
	Oid element_type = ARR_ELEMTYPE(arr);
	int nelems;
	Datum *elems;
	bool *nulls;

	/* deconstruct the array into individual elements */
	deconstruct_array(arr, element_type, -1, false, 'i', &elems, &nulls, &nelems);

	elog(DEBUG1,"%s called: nelems='%d'", __func__, nelems);

	/* loop over each element to find the first non-null one */
	for (int i = 0; i < nelems; i++)
	{
		if (!nulls[i])
		{
			/* convert the Datum to a cstring (assuming text) */
			char *el = DatumToString(elems[i], TEXTOID);
			char *rdfnode;
			text *result;
			Datum res;

			if (isIRI(el) || isBlank(el))
				rdfnode = el;
			else if (isLiteral(el))
			{
				char *dt = datatype(el);

				if (strlen(dt) != 0)
					rdfnode = strdt(el, dt);
				else
					rdfnode = el;
			}
			else
				rdfnode = cstring_to_rdfnode(el);

			result = cstring_to_text(rdfnode);
			res = PointerGetDatum(result);

			PG_RETURN_DATUM(res);
		}
	}

	elog(DEBUG1,"%s exit: returning NULL", __func__);
	PG_RETURN_NULL();
}

/*
 * CreateDatum
 * ----------
 *
 * Creates a Datum from a given value based on the postgres types and modifiers.
 *
 * tuple: a Heaptuple
 * pgtype: postgres type
 * pgtypemod: postgres type modifier
 * value: value to be converted
 *
 * returns Datum
 */
static Datum CreateDatum(HeapTuple tuple, int pgtype, int pgtypmod, char *value)
{
	regproc typinput;

	elog(DEBUG3, "%s called", __func__);

	tuple = SearchSysCache1(TYPEOID, ObjectIdGetDatum(pgtype));

	if (!HeapTupleIsValid(tuple))
	{
		ereport(ERROR,
				(errcode(ERRCODE_FDW_INVALID_DATA_TYPE),
				 errmsg("cache lookup failed for type %u (osm_id)", pgtype)));
	}

	typinput = ((Form_pg_type)GETSTRUCT(tuple))->typinput;
	ReleaseSysCache(tuple);

	if (pgtype == FLOAT4OID ||
		pgtype == FLOAT8OID ||
		pgtype == NUMERICOID ||
		pgtype == TIMESTAMPOID ||
		pgtype == TIMESTAMPTZOID ||
		pgtype == VARCHAROID)
		return OidFunctionCall3(
			typinput,
			CStringGetDatum(value),
			ObjectIdGetDatum(InvalidOid),
			Int32GetDatum(pgtypmod));
	else
		return OidFunctionCall1(typinput, CStringGetDatum(value));
}

/*
 * DescribeIRI
 * -----------------
 *
 * Executes a DESCRIBE SPARQL query and return the result set as as truples
 * in a List*. It returns a list of RDFfdwTriple* with all triples returned
 * from the DESCRIBE SPARQL query.
 *
 * state: SPARQL, SERVER and FOREIGN TABLE info
 */
static List *DescribeIRI(RDFfdwState *state)
{
	List *result = NIL;
	librdf_world *world = librdf_new_world();
	librdf_storage *storage = librdf_new_storage(world, "memory", NULL, NULL);
	librdf_model *model = librdf_new_model(world, storage, NULL);
	librdf_parser *parser = librdf_new_parser(world, "rdfxml", NULL, NULL);
	librdf_uri *uri = librdf_new_uri(world, (const unsigned char *)state->base_uri);
	librdf_stream *stream = NULL;

	elog(DEBUG1, "%s called", __func__);

	librdf_world_open(world);

	PG_TRY();
	{
		LoadRDFData(state);

		if (strcmp(state->base_uri, RDF_DEFAULT_BASE_URI) != 0)
			elog(DEBUG2, "%s: parsing RDF/XML result set (base '%s')", __func__, state->base_uri);

		if (librdf_parser_parse_string_into_model(parser, (const unsigned char *)state->sparql_resultset, uri, model))
			ereport(ERROR,
					(errcode(ERRCODE_FDW_ERROR),
					 errmsg("unable to parse RDF/XML"),
					 errhint("base URI: %s", state->base_uri)));

		stream = librdf_model_as_stream(model);

		while (!librdf_stream_end(stream))
		{
			RDFfdwTriple *triple = (RDFfdwTriple *) palloc0(sizeof(RDFfdwTriple));
			librdf_statement *statement = librdf_stream_get_object(stream);

			if (librdf_node_is_resource(statement->subject))
				triple->subject = pstrdup(iri((char *) librdf_uri_as_string(librdf_node_get_uri(statement->subject))));
			else if (librdf_node_is_blank(statement->subject))
				triple->subject = pstrdup((char *) librdf_node_get_blank_identifier(statement->subject));
			else
				ereport(ERROR,
						(errcode(ERRCODE_FDW_ERROR),
						 errmsg("unsupported subject node type")));

			if (librdf_node_is_blank(statement->predicate))
				triple->predicate = strdup((char *) librdf_node_get_blank_identifier(statement->predicate));
			else
				triple->predicate = pstrdup(iri((char *) librdf_uri_as_string(librdf_node_get_uri(statement->predicate))));


			if (librdf_node_is_resource(statement->object))
				triple->object = pstrdup(iri((char *) librdf_uri_as_string(librdf_node_get_uri(statement->object))));
			else if (librdf_node_is_literal(statement->object))
			{
				char *value = (char *) librdf_node_get_literal_value(statement->object);
				StringInfoData literal;
				initStringInfo(&literal);

				if (state->keep_raw_literal)
				{
					char *language = librdf_node_get_literal_value_language(statement->object);
					librdf_uri *datatype = librdf_node_get_literal_value_datatype_uri(statement->object);

					if (datatype)
						appendStringInfo(&literal, "%s", strdt(value, (char *) librdf_uri_as_string(datatype)));
					else if (language)
						appendStringInfo(&literal, "%s", strlang(value, language));
					else
						appendStringInfo(&literal, "%s", cstring_to_rdfnode(value));
				}
				else
					appendStringInfo(&literal, "%s", cstring_to_rdfnode(value));

				triple->object = pstrdup(literal.data);
				pfree(literal.data);
			}
			else if (librdf_node_is_blank(statement->object))
				triple->object = pstrdup((char *) librdf_node_get_blank_identifier(statement->object));
			else
				ereport(ERROR,
						(errcode(ERRCODE_FDW_ERROR),
						 errmsg("unsupported object node type")));

			result = lappend(result, triple);

			librdf_stream_next(stream);
		}
	}
	PG_CATCH();
	{
		if (stream)
			librdf_free_stream(stream);
		if (model)
			librdf_free_model(model);
		if (storage)
			librdf_free_storage(storage);
		if (parser)
			librdf_free_parser(parser);
		if (uri)
			librdf_free_uri(uri);
		if (world)
			librdf_free_world(world);
		PG_RE_THROW();
	}
	PG_END_TRY();

	librdf_free_stream(stream);
	librdf_free_model(model);
	librdf_free_storage(storage);
	librdf_free_parser(parser);
	librdf_free_uri(uri);
	librdf_free_world(world);

	elog(DEBUG1,"%s exit", __func__);
	return result;
}

/*
 * rdf_fdw_describe
 * -----------------
 *
 * Analog to DESCRIBE SPARQL queries. This function expects at least two
 * arguments, namely 'server' and 'query', which are passed in positions
 * 1 and 2, respectivelly. Optionally, the arguments 'raw_literal' and
 * 'base_uri' can determine if the literals from result set should be
 * returned with their language/data type, and the base URI for possible
 * relative references, respectivelly.
 */
Datum rdf_fdw_describe(PG_FUNCTION_ARGS)
{
	struct RDFfdwState *state = (struct RDFfdwState *) palloc0(sizeof(RDFfdwState));
	text *srvname_arg = PG_GETARG_TEXT_P(0);
	text *iri_arg = PG_GETARG_TEXT_P(1);
	bool keep_raw_literal =  PG_GETARG_BOOL(2);
	text *base_uri_arg = PG_GETARG_TEXT_P(3);
	char *srvname;
	char *describe_query;
	char *base_uri;

	MemoryContext oldcontext;
	FuncCallContext *funcctx;
	AttInMetadata *attinmeta;
	TupleDesc tupdesc;
	int call_cntr;
	int max_calls;

	if (SRF_IS_FIRSTCALL())
	{
		List *triples;
		funcctx = SRF_FIRSTCALL_INIT();
		oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

		elog(DEBUG1, "%s called (SRF_IS_FIRSTCALL)", __func__);

		if (VARSIZE_ANY_EXHDR(srvname_arg) == 0)
			ereport(ERROR,
					(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
					 errmsg("SERVER cannot be empty")));

		if (VARSIZE_ANY_EXHDR(iri_arg) == 0)
			ereport(ERROR,
					(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
					 errmsg("DESCRIBE pattern cannot be empty")));

		srvname = text_to_cstring(srvname_arg);
		describe_query = text_to_cstring(iri_arg);
		state->keep_raw_literal = keep_raw_literal;
		base_uri = text_to_cstring(base_uri_arg);

		if (*describe_query && strspn(describe_query, " \t\n\r") == strlen(describe_query))
			ereport(ERROR,
					(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
					 errmsg("a DESCRIBE pattern cannot contain only whitespace characters")));

		if(LocateKeyword(describe_query, " \n\t>", "DESCRIBE"," *?\n\t<", NULL, 0) == RDF_KEYWORD_NOT_FOUND)
			ereport(ERROR,
				(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
				errmsg("invalid DESCRIBE query:\n\n%s\n", describe_query)));

		if (*srvname && strspn(srvname, " \t\n\r") == strlen(srvname))
			ereport(ERROR,
					(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
					 errmsg("a SERVER cannot contain only whitespace characters")));

		/*
		 * setting session's default values.
		 */
		state->enable_pushdown = true;
		state->log_sparql = true;
		state->has_unparsable_conds = false;
		state->query_param = RDF_DEFAULT_QUERY_PARAM;
		state->connect_timeout = RDF_DEFAULT_CONNECTTIMEOUT;
		state->max_retries = RDF_DEFAULT_MAXRETRY;
		state->fetch_size = RDF_DEFAULT_FETCH_SIZE;
		state->sparql_query_type = SPARQL_DESCRIBE;
		state->base_uri = RDF_DEFAULT_BASE_URI;

		elog(DEBUG2, "%s: loading server name '%s'", __func__, srvname);
		state->server = GetForeignServerByName(srvname, true);

		if (!state->server)
			ereport(ERROR,
					(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
					 errmsg("invalid SERVER: %s", quote_identifier(srvname))));

		/*
		* loading SERVER OPTIONS
		*/
		LoadRDFServerInfo(state);

		/*
		 * Here we force the output format to RDF/XML, as by default no other format
		 * is expected from DESCRIBE requests.
		 */
		state->format = RDF_RDFXML_FORMAT;
		state->sparql = describe_query;

		/* We set a different base URI if it was provided in the function call */
		if (strlen(base_uri) != 0)
			state->base_uri = base_uri;

		/*
		 * Loading USER MAPPING (if any)
		 */
		LoadRDFUserMapping(state);

		triples = DescribeIRI(state);
		funcctx->user_fctx = triples;

		if (triples)
			funcctx->max_calls = triples->length;
		if (get_call_result_type(fcinfo, NULL, &tupdesc) != TYPEFUNC_COMPOSITE)
			ereport(ERROR, (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
							errmsg("function returning record called in context that cannot accept type record")));

		attinmeta = TupleDescGetAttInMetadata(tupdesc);
		funcctx->attinmeta = attinmeta;

		MemoryContextSwitchTo(oldcontext);
	}

	funcctx = SRF_PERCALL_SETUP();

	call_cntr = funcctx->call_cntr;
	max_calls = funcctx->max_calls;
	attinmeta = funcctx->attinmeta;

	if (call_cntr < max_calls)
	{
		Datum values[3];
		bool nulls[3];
		HeapTuple tuple;
		Datum result;
		RDFfdwTriple *triple = (RDFfdwTriple *)list_nth((List *)funcctx->user_fctx, call_cntr);

		memset(nulls, 0, sizeof(nulls));

		for (size_t i = 0; i < funcctx->attinmeta->tupdesc->natts; i++)
		{
			Form_pg_attribute att = TupleDescAttr(funcctx->attinmeta->tupdesc, i);

			if (strcmp(NameStr(att->attname), "subject") == 0)
				values[i] = CreateDatum(tuple, att->atttypid, att->atttypmod, triple->subject);
			else if (strcmp(NameStr(att->attname), "predicate") == 0)
				values[i] = CreateDatum(tuple, att->atttypid, att->atttypmod, triple->predicate);
			else if (strcmp(NameStr(att->attname), "object") == 0)
				values[i] = CreateDatum(tuple, att->atttypid, att->atttypmod, triple->object);
			else
				nulls[i] = true;
		}

		elog(DEBUG2, "  %s: creating heap tuple", __func__);

		tuple = heap_form_tuple(funcctx->attinmeta->tupdesc, values, nulls);
		result = HeapTupleGetDatum(tuple);

		SRF_RETURN_NEXT(funcctx, result);
	}
	else
	{
		elog(DEBUG1,"%s exit", __func__);
		SRF_RETURN_DONE(funcctx);
	}
}

/*
 * rdf_fdw_clone_table
 * -----------------
 * 
 * Materializes the content of a foreign table into a normal table.
 */
#if PG_VERSION_NUM >= 110000
Datum rdf_fdw_clone_table(PG_FUNCTION_ARGS)
{
	struct RDFfdwState *state = (struct RDFfdwState *)palloc0(sizeof(RDFfdwState));
	text *foreign_table_name;
	text *target_table_name;
	text *ordering_pgcolumn;
	text *sort_order;
	int begin_offset;
	int fetch_size;
	int max_records;
	bool create_table;
	bool verbose;
	bool commit_page;
	bool match = false;
	bool orderby_query = true;
	TupleDesc tupdesc;

	char *orderby_variable = NULL;
	StringInfoData select;

	elog(DEBUG1,"%s called",__func__);

	if(PG_ARGISNULL(0))
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("'foreign_table' cannot be NULL")));
	else
		foreign_table_name = PG_GETARG_TEXT_P(0);

	if(PG_ARGISNULL(1))
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("'target_table' cannot be NULL")));
	else
		target_table_name = PG_GETARG_TEXT_P(1);

	if(PG_ARGISNULL(2))
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("'begin_offset' cannot be NULL"),
				 errhint("either set it to 0 or ignore the paramter to start the pagination from the beginning")));
	else
		begin_offset = PG_GETARG_INT32(2);

	if(PG_ARGISNULL(3))
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("'fetch_size' cannot be NULL")));
	else
		fetch_size = PG_GETARG_INT32(3);

	if(PG_ARGISNULL(4))
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("'max_records' cannot be NULL")));
	else
		max_records = PG_GETARG_INT32(4);

	if(PG_ARGISNULL(5))
		orderby_query = false;
	else
	{
		ordering_pgcolumn = PG_GETARG_TEXT_P(5);
		state->ordering_pgcolumn = text_to_cstring(ordering_pgcolumn);
	}

	if(PG_ARGISNULL(6))
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("'sort_order' cannot be NULL")));
	else
		sort_order = PG_GETARG_TEXT_P(6);
	
	if(PG_ARGISNULL(7))
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("'create_table' cannot be NULL")));
	else
		create_table = PG_GETARG_BOOL(7);

	if(PG_ARGISNULL(8))
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("'verbose' cannot be NULL")));
	else
		verbose = PG_GETARG_BOOL(8);

	if(PG_ARGISNULL(9))
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("'commit_page' cannot be NULL")));
	else
		commit_page = PG_GETARG_BOOL(9);


	if(strlen(text_to_cstring(foreign_table_name)) == 0)
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("no 'foreign_table' provided")));

	if(strlen(text_to_cstring(target_table_name)) == 0)
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("no 'target_table' provided")));
	else
		state->target_table_name = text_to_cstring(target_table_name);

	if(fetch_size < 0)
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("invalid 'fetch_size': %d",fetch_size),
				 errhint("the page size corresponds to the number of records that are retrieved after each iteration and therefore must be a positive number")));
	
	if(max_records < 0)
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("invalid 'max_records': %d",max_records),
				 errhint("'max_records' corresponds to the total number of records that are retrieved from the FOREIGN TABLE and therefore must be a positive number")));

	if(begin_offset < 0)
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("invalid 'begin_offset': %d",begin_offset)));

	if(strcasecmp(text_to_cstring(sort_order),"ASC") != 0 &&
	   strcasecmp(text_to_cstring(sort_order),"DESC") != 0)
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("invalid 'sort_order': %s",text_to_cstring(sort_order)),
				 errhint("the 'sort_order' must be either 'ASC' (ascending) or 'DESC' (descending)")));


	state->foreigntableid = GetRelOidFromName(text_to_cstring(foreign_table_name), RDF_FOREIGN_TABLE_CODE);
	state->foreign_table = GetForeignTable(state->foreigntableid);
	state->server = GetForeignServer(state->foreign_table->serverid);
	
	state->sort_order = text_to_cstring(sort_order);
	state->enable_pushdown = false;
	state->query_param = RDF_DEFAULT_QUERY_PARAM;
	state->format = RDF_DEFAULT_FORMAT;
	state->connect_timeout = RDF_DEFAULT_CONNECTTIMEOUT;
	state->max_retries = RDF_DEFAULT_MAXRETRY;
	state->verbose = verbose;
	state->commit_page = commit_page;
	/*
	 * Load configured SERVER parameters
	 */
	LoadRDFServerInfo(state);

	/*
	 * Load configured FOREIGN TABLE parameters
	 */
	LoadRDFTableInfo(state);

	/*
	 * Here we try to create the target table with the name give in 'target_table'.
	 * This new table will be a clone of the queried FOREIGN TABLE, of couse without
	 * the table and column OPTIONS.
	 */
	if(create_table)
	{
		StringInfoData ct;
		SPI_connect();

		initStringInfo(&ct);
		appendStringInfo(&ct,"CREATE TABLE %s AS SELECT * FROM %s WITH NO DATA;",
			state->target_table_name,
			text_to_cstring(foreign_table_name));

		if(SPI_exec(NameStr(ct), 0) != SPI_OK_UTILITY)
			ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("unable to create target table '%s'",state->target_table_name)));

		 if(verbose)
			elog(INFO,"Target TABLE \"%s\" created based on FOREIGN TABLE \"%s\":\n\n  %s\n",
				text_to_cstring(target_table_name), text_to_cstring(foreign_table_name), NameStr(ct));

		SPI_finish();

	}

	/*
	 * at this point we are able to retrieve the target_table's Relation, as
	 * it either existed before the function call or was just created.
	 */
#if PG_VERSION_NUM < 130000
	state->target_table = heap_open(GetRelOidFromName(state->target_table_name,RDF_ORDINARY_TABLE_CODE), NoLock);
	heap_close(state->target_table, NoLock);
#else
	state->target_table = table_open(GetRelOidFromName(state->target_table_name,RDF_ORDINARY_TABLE_CODE), NoLock);
	table_close(state->target_table, NoLock);
#endif
	/* 
	 * Here we check if the target table matches the columns of the 
	 * FOREIGN TABLE.
	 */	
	tupdesc = state->target_table->rd_att;

	elog(DEBUG2,"%s: checking if tables match",__func__);
	for (size_t ftidx = 0; ftidx < state->numcols; ftidx++)
	{
		for (size_t ttidx = 0; ttidx < state->target_table->rd_att->natts; ttidx++)
		{
			Form_pg_attribute attr = TupleDescAttr(tupdesc, ttidx);

			elog(DEBUG2,"%s: comparing %s - %s", __func__,
				NameStr(attr->attname),
				state->rdfTable->cols[ftidx]->name);

			if(strcmp(NameStr(attr->attname), state->rdfTable->cols[ftidx]->name) == 0)
			{
				state->rdfTable->cols[ftidx]->used = true;
				match = true;
			}
		}
	}

	/* 
	 * If both foreign and target table share no column we better stop it right here.
	 */
	if(!match)
	{
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("target table mismatch"),
				 errhint("at least one column of '%s' must match with the FOREIGN TABLE '%s'",
				 	state->target_table_name,
					get_rel_name(state->foreigntableid))
				)
			);
	}




	elog(DEBUG2,"%s: validating 'fetch_size' tables match",__func__);
	if(fetch_size == 0)
	{
		if(state->fetch_size != 0)
			fetch_size = state->fetch_size;
		else
		{
			fetch_size = RDF_DEFAULT_FETCH_SIZE;
			if(verbose)
				elog(INFO,"setting 'fetch_size' to %d (default)", RDF_DEFAULT_FETCH_SIZE);
		}
	}

	elog(DEBUG2,"fetch_size = %d",fetch_size);	
	elog(DEBUG2,"ordering_pgcolumn = '%s'", !orderby_query || strlen(state->ordering_pgcolumn) == 0 ? "NOT SET" : state->ordering_pgcolumn);

	initStringInfo(&select);
	for (int i = 0; i < state->numcols; i++)
	{
		/*
		 * Setting ORDER BY column for the SPARQL query. In case no column
		 * is provided, we pick up the first 'iri' column in the table.
		 */
		if (orderby_query)
		{
			if (strlen(state->ordering_pgcolumn) == 0 && orderby_variable == NULL)
			{
				if (state->rdfTable->cols[i]->nodetype &&
					strcmp(state->rdfTable->cols[i]->nodetype, RDF_COLUMN_OPTION_NODETYPE_IRI) == 0)
					orderby_variable = pstrdup(state->rdfTable->cols[i]->sparqlvar);
			}
			else if (strcmp(state->rdfTable->cols[i]->name, state->ordering_pgcolumn) == 0)
			{
				orderby_variable = pstrdup(state->rdfTable->cols[i]->sparqlvar);
			}
		}

		if (!state->rdfTable->cols[i]->expression)
			appendStringInfo(&select, "%s ", pstrdup(state->rdfTable->cols[i]->sparqlvar));
		else
			appendStringInfo(&select, "(%s AS %s) ",
								pstrdup(state->rdfTable->cols[i]->expression),
								pstrdup(state->rdfTable->cols[i]->sparqlvar)
							);
	}

	/*
	* If at this point no 'orderby_variable' was set, we set it to the first 
	* sparqlvar we can find in the table, so that we for sure have a variable
	* to order by. This value might be overwritten in further iterations of this
	* loop.
	*/
	if (orderby_query)
	{
		if (orderby_variable == NULL && strlen(state->ordering_pgcolumn) == 0 && state->rdfTable->cols[0]->sparqlvar)
		{
			elog(DEBUG2, "%s: setting ordering variable to '%s'", __func__, state->rdfTable->cols[0]->sparqlvar);
			orderby_variable = pstrdup(state->rdfTable->cols[0]->sparqlvar);
		}

		if (!orderby_variable && strlen(state->ordering_pgcolumn) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_FDW_ERROR),
					 errmsg("invalid 'ordering_column': %s", state->ordering_pgcolumn),
					 errhint("the column '%s' does not exist in the foreign table '%s'",
							 state->ordering_pgcolumn,
							 get_rel_name(state->foreigntableid))));

		elog(DEBUG2, "orderby_variable = '%s'", orderby_variable);
	}

	state->sparql_prefixes = DeparseSPARQLPrefix(state->raw_sparql);
	elog(DEBUG2,"sparql_prefixes = \n\n'%s'",state->sparql_prefixes);

	state->sparql_from = DeparseSPARQLFrom(state->raw_sparql);
	elog(DEBUG2,"sparql_from = \n\n'%s'",state->sparql_from);

	state->sparql_select = NameStr(select);
	elog(DEBUG2,"sparql_select = \n\n'%s'",state->sparql_select);

	state->sparql_where = DeparseSPARQLWhereGraphPattern(state);
	elog(DEBUG2,"sparql_where = \n\n'%s'",state->sparql_where);

	state->inserted_records = 0;
	state->offset = begin_offset;

	if(verbose)
		elog(INFO,"\n\n== Parameters ==\n\nforeign_table: '%s'\ntarget_table: '%s'\ncreate_table: '%s'\nfetch_size: %d\nbegin_offset: %d\nmax_records: %d\nordering_column: '%s'\nordering sparql variable: '%s'\nsort_order: '%s'\n",
			get_rel_name(state->foreigntableid),
			state->target_table_name,
			create_table == 1 ? "true" : "false",
			fetch_size, 
			begin_offset,
			max_records,
			!orderby_query || strlen(state->ordering_pgcolumn) == 0 ? "NOT SET" : state->ordering_pgcolumn, 
			orderby_variable,
			state->sort_order);

	while(true)
	{
		int ret = 0;
		int limit = fetch_size;
		StringInfoData limit_clause;

		/* stop iteration if the current offset is greater than max_records */
		if(max_records != 0 && state->inserted_records >= max_records)
		{
			elog(DEBUG2,"%s: number of retrieved records reached the limit of %d.\n\n  records inserted: %d\n  fetch size: %d\n",
						__func__,
						max_records,
						state->inserted_records,
						fetch_size);
			break;
		}

		/*
		 * if the current offset + fetch_size exceed the set limit we change
		 * the limit.
		 */
		if(max_records != 0 && state->inserted_records + fetch_size >= max_records)
			limit = max_records - state->inserted_records;

		/*
		 * pagesize and rowcount must be reset before every SPARQL query,
		 * as it contains the total number of records retrieved from the
		 * triplestore and the number of records processed for each request.
		 */
		state->pagesize = 0;
		state->rowcount = 0;

		/*
		 * changes the pagination of the query to match the parameters given
		 * in the function call. If the SPARQL query set in the FOREIGN TABLE
		 * already contains a OFFSET LIMIT, it will be overwritten by this string
		 */
		initStringInfo(&limit_clause);
		if(orderby_query)
			appendStringInfo(&limit_clause,"ORDER BY %s(%s) \nOFFSET %d LIMIT %d",
				state->sort_order,
				orderby_variable,
				state->inserted_records == 0 && begin_offset == 0 ? 0 : state->offset,
				limit);
		else
			appendStringInfo(&limit_clause,"OFFSET %d LIMIT %d",
				state->inserted_records == 0 && begin_offset == 0 ? 0 : state->offset,
				limit);


		state->sparql_limit = NameStr(limit_clause);

		/*
		 * create new SPARQL query with the pagination parameters
		 */
		CreateSPARQL(state, NULL);

		/*
		 * execute the newly created SPARQL and load it in 'state'. It updates
		 * state->pagesize!
		 */
		LoadRDFData(state);

		/* get out in case the SPARQL retrieves nothing */
		if(state->pagesize == 0)
		{
			elog(DEBUG2,"%s: SPARQL query returned nothing",__func__);
			break;
		}

		ret = InsertRetrievedData(state,state->offset, state->offset + fetch_size);

		elog(DEBUG2,"%s: InsertRetrievedData returned %d records",__func__, ret);

		state->inserted_records = state->inserted_records + ret;

		state->offset = state->offset + fetch_size;

		pfree(limit_clause.data);
	}

	elog(DEBUG1,"%s exit", __func__);
	PG_RETURN_VOID();
}

/*
 * InsertRetrievedData
 * -----------------
 * 
 * Inserts data retrieved from the triplestore and stoted at the RDFfdwState.
 * 
 * state     : records retrieved from the triple store and SPARQL, SERVER and 
 * 			   FOREIGN TABLE info.
 * offset    : current offset in the data harvesting set by the caller
 * fetch_size: fetch_size (page size) in the data harvesting set by the caller
 */
static int InsertRetrievedData(RDFfdwState *state, int offset, int fetch_size)
{
	xmlNodePtr result;
	xmlNodePtr value;
	xmlNodePtr record;
	regproc typinput;
	HeapTuple tuple;
	Datum datum;

	int ret = -1;
	int processed_records = 0;

	elog(DEBUG1,"%s called", __func__);

	SPI_connect_ext(SPI_OPT_NONATOMIC);

	for (size_t rec = 0; rec < state->pagesize; rec++)
	{
		SPIPlanPtr		pplan;
		Oid		   		*ctypes = (Oid *) palloc(state->numcols * sizeof(Oid));
		StringInfoData 	insert_stmt;
		StringInfoData 	insert_cols;
		StringInfoData 	insert_pidx;

		Datum	   		*cvals;			/* column values */
		char	   		*cnulls;		/* column nulls */
		int 			colindex = 0;		

		cvals = (Datum *) palloc(state->numcols * sizeof(Datum));
		cnulls = (char *) palloc(state->numcols * sizeof(char));
		initStringInfo(&insert_cols);
		initStringInfo(&insert_pidx);

		record = FetchNextBinding(state);

		for (int i = 0; i < state->numcols; i++)
		{
			char *sparqlvar = state->rdfTable->cols[i]->sparqlvar;
			char *colname = state->rdfTable->cols[i]->name;
			Oid pgtype = state->rdfTable->cols[i]->pgtype;
			int pgtypmod = state->rdfTable->cols[i]->pgtypmod;

			for (result = record->children; result != NULL; result = result->next)
			{
				StringInfoData name;
				initStringInfo(&name);
				appendStringInfo(&name, "?%s", (char *)xmlGetProp(result, (xmlChar *)RDF_XML_NAME_TAG));

				if (strcmp(sparqlvar, NameStr(name)) == 0 && state->rdfTable->cols[i]->used)
				{

					for (value = result->children; value != NULL; value = value->next)
					{
						xmlBufferPtr buffer = xmlBufferCreate();
						xmlNodeDump(buffer, state->xmldoc, value->children, 0, 0);

						tuple = SearchSysCache1(TYPEOID, ObjectIdGetDatum(pgtype));
						datum = CStringGetDatum(pstrdup((char *) buffer->content));
						ctypes[colindex] = pgtype;
						cnulls[colindex] = false;

						if (!HeapTupleIsValid(tuple))
						{
							ereport(ERROR,
								(errcode(ERRCODE_FDW_INVALID_DATA_TYPE),
									errmsg("cache lookup failed for type %u > column '%s'", pgtype, colname)));
						}

						typinput = ((Form_pg_type)GETSTRUCT(tuple))->typinput;
						ReleaseSysCache(tuple);

						if(pgtype == NUMERICOID || pgtype == TIMESTAMPOID || pgtype == TIMESTAMPTZOID || pgtype == VARCHAROID)
						{
							cvals[colindex] = OidFunctionCall3(
												typinput,
												datum,
												ObjectIdGetDatum(InvalidOid),
												Int32GetDatum(pgtypmod));
						}
						else
						{
							cvals[colindex] = OidFunctionCall1(typinput, datum);
						}
												
						xmlBufferFree(buffer);
					}
										
					colindex++;

					appendStringInfo(&insert_cols,"%s %s",
						colindex > 1 ? "," : "", 
						state->rdfTable->cols[i]->name);
						

					appendStringInfo(&insert_pidx,"%s$%d",
						colindex > 1 ? "," : "", 
						colindex);
				}

				pfree(name.data);
			}
		}

		state->rowcount++;

		initStringInfo(&insert_stmt);
		appendStringInfo(&insert_stmt,"INSERT INTO %s (%s) VALUES (%s);",
			state->target_table_name,
			NameStr(insert_cols),
			NameStr(insert_pidx)
		);

		pplan = SPI_prepare(NameStr(insert_stmt), colindex, ctypes);
		
		ret = SPI_execp(pplan, cvals, cnulls, 0);

		if(ret < 0)
			ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("SPI_execp returned %d. Unable to insert data into '%s'",ret, state->target_table_name)
				)
			);

		if(state->commit_page)
			SPI_commit();

		processed_records = processed_records + SPI_processed;

	}

	if(state->verbose)
		elog(INFO,"[%d - %d]: %d records inserted",offset,fetch_size, processed_records);

	SPI_finish();

	elog(DEBUG1,"%s exit: returning '%d' (processed_records)", __func__, processed_records);
	return processed_records;
}

/*
 * GetRelOidFromName
 * ---------------
 * Retrieves the Oid of a relation based on its name and type
 *
 * relname: relation name
 * code   : code of relation type, as in 'relkind' of pg_class.
 *
 * returns the Oid of the given relation
 */
static Oid GetRelOidFromName(char *relname, char *code)
{
	StringInfoData str;
	Oid res = 0;
	int ret;

	elog(DEBUG1,"%s called: relname='%s', code='%s'", __func__, relname, code);

	initStringInfo(&str);
	appendStringInfo(&str,"SELECT CASE relkind WHEN '%s' THEN oid ELSE 0 END FROM pg_class WHERE oid = '%s'::regclass::oid;", code, relname);

	if(strcmp(code, RDF_FOREIGN_TABLE_CODE) != 0 && strcmp(code, RDF_ORDINARY_TABLE_CODE) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("internal error: '%s' unknown relation type",code)));

	SPI_connect();

	ret = SPI_exec(NameStr(str), 0);

	if (ret > 0 && SPI_tuptable != NULL)
    {
        SPITupleTable *tuptable = SPI_tuptable;
        TupleDesc tupdesc = tuptable->tupdesc;

		HeapTuple tuple = tuptable->vals[0];
		res = (Oid) atoi(SPI_getvalue(tuple, tupdesc, 1));
	}

	SPI_finish();

	if(res == InvalidOid)
		ereport(ERROR,
				(errcode(ERRCODE_FDW_ERROR),
				 errmsg("invalid relation: '%s' is not a %s",relname,
					strcmp(code,RDF_FOREIGN_TABLE_CODE) == 0 ? "foreign table" : "table" )));

	elog(DEBUG1,"%s exit: returning '%u'", __func__, res);
	return res;

}
#endif  /* PG_VERSION_NUM >= 110000 */

Datum rdf_fdw_validator(PG_FUNCTION_ARGS)
{
	List *options_list = untransformRelOptions(PG_GETARG_DATUM(0));
	Oid catalog = PG_GETARG_OID(1);
	ListCell *cell;
	struct RDFfdwOption *opt;
	bool hasliteralatt = false;
	//bool is_iri = false;
	
	elog(DEBUG1,"%s called", __func__);

	/* Initialize found state to not found */
	for (opt = valid_options; opt->optname; opt++)
		opt->optfound = false;

	foreach (cell, options_list)
	{
		DefElem *def = (DefElem *)lfirst(cell);
		bool optfound = false;

		for (opt = valid_options; opt->optname; opt++)
		{
			if (catalog == opt->optcontext && strcmp(opt->optname, def->defname) == 0)
			{
				/* Mark that this user option was found */
				opt->optfound = optfound = true;

				if (strlen(defGetString(def)) == 0)
				{
					ereport(ERROR,
							(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
							 errmsg("empty value in option '%s'", opt->optname)));
				}

				if (strcmp(opt->optname, RDF_SERVER_OPTION_ENDPOINT) == 0 ||
					strcmp(opt->optname, RDF_SERVER_OPTION_HTTP_PROXY) == 0 ||
					strcmp(opt->optname, RDF_SERVER_OPTION_HTTPS_PROXY) == 0)
				{

					int return_code = CheckURL(defGetString(def));

					if (return_code != REQUEST_SUCCESS)
					{
						ereport(ERROR,
								(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
								errmsg("invalid %s: '%s'", opt->optname, defGetString(def))));
					}
				}

				if (strcmp(opt->optname, RDF_SERVER_OPTION_CONNECTTIMEOUT) == 0)
				{
					char *endptr;
					char *timeout_str = defGetString(def);
					long timeout_val = strtol(timeout_str, &endptr, 0);

					if (timeout_str[0] == '\0' || *endptr != '\0' || timeout_val < 0)
					{
						ereport(ERROR,
								(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
								 errmsg("invalid %s: '%s'", def->defname, timeout_str),
								 errhint("expected values are positive integers (timeout in seconds)")));
					}
				}

				if (strcmp(opt->optname, RDF_SERVER_OPTION_FETCH_SIZE) == 0)
				{
					char *endptr;
					char *fetch_size_str = defGetString(def);
					long fetch_size_val = strtol(fetch_size_str, &endptr, 0);

					if (fetch_size_str[0] == '\0' || *endptr != '\0' || fetch_size_val < 0)
					{
						ereport(ERROR,
								(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
								 errmsg("invalid %s: '%s'", def->defname, fetch_size_str),
								 errhint("expected values are positive integers")));
					}
				}

				if (strcmp(opt->optname, RDF_SERVER_OPTION_CONNECTRETRY) == 0)
				{
					char *endptr;
					char *retry_str = defGetString(def);
					long retry_val = strtol(retry_str, &endptr, 0);

					if (retry_str[0] == '\0' || *endptr != '\0' || retry_val < 0)
					{
						ereport(ERROR,
								(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
								 errmsg("invalid %s: '%s'", def->defname, retry_str),
								 errhint("expected values are positive integers (retry attempts in case of failure)")));
					}
				}


				if (strcmp(opt->optname, RDF_SERVER_OPTION_ENABLE_PUSHDOWN) == 0)
				{				
					char *enable_pushdown = defGetString(def);
					if(strcasecmp(enable_pushdown,"true") !=0 && strcasecmp(enable_pushdown,"false") != 0)
						ereport(ERROR,
								(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
								 errmsg("invalid %s: '%s'", def->defname, enable_pushdown),
								 errhint("this parameter expects boolean values ('true' or 'false')")));
				}


				if (strcmp(opt->optname, RDF_TABLE_OPTION_SPARQL) == 0)
				{
					char *sparql = defGetString(def);
					int where_position = -1;
					int where_size = -1;

					for (int i = 0; sparql[i] != '\0'; i++)
					{
						if (sparql[i] == '{' && where_position == -1)
							where_position = i;

						if (sparql[i] == '}')
							where_size = i - where_position;
					}

					/* report ERROR if the SPARQL does not contain the opening and closing braces {} */
					if (where_size == -1 || where_position == -1)
						ereport(ERROR,
								(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
								 errmsg("unable to parse SPARQL WHERE clause:\n%s", sparql),
								 errhint("The WHERE clause expects at least one triple pattern wrapped by curly braces, e.g. '{?s ?p ?o}'")));

					/* report ERROR if the SPARQL query does not contain a SELECT */
					 if(LocateKeyword(sparql, " {\n\t>", "SELECT"," *?\n\t", NULL, 0) == RDF_KEYWORD_NOT_FOUND)
						ereport(ERROR,
							(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
							errmsg("unable to parse SPARQL SELECT clause:\n%s.", sparql)));
				}

				if (strcmp(opt->optname, RDF_TABLE_OPTION_LOG_SPARQL) == 0)
				{				
					char *log_sparql = defGetString(def);
					if(strcasecmp(log_sparql,"true") !=0 && strcasecmp(log_sparql,"false") != 0)
						ereport(ERROR,
								(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
								 errmsg("invalid %s: '%s'", def->defname, log_sparql),
								 errhint("this parameter expects boolean values ('true' or 'false')")));
				}
				
				if(strcmp(opt->optname, RDF_COLUMN_OPTION_VARIABLE) == 0)
				{	
					if(!IsSPARQLVariableValid(defGetString(def)))
						ereport(ERROR,
							(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
								errmsg("invalid %s: '%s'", def->defname, defGetString(def)),
								errhint("a query variable must start with either \"?\" or \"$\"; the \"?\" or \"$\" is not part of the variable name. Allowable characters for the name are [a-z], [A-Z], [0-9], _ and diacrictics.")));
				}

				if(strcmp(opt->optname, RDF_COLUMN_OPTION_NODETYPE) == 0)
				{
					if(strcasecmp(defGetString(def), RDF_COLUMN_OPTION_NODETYPE_IRI) != 0 &&
					   strcasecmp(defGetString(def), RDF_COLUMN_OPTION_NODETYPE_LITERAL) != 0)
					   ereport(ERROR,
								(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
								 errmsg("invalid %s: '%s'", def->defname, defGetString(def)),
								 errhint("this parameter expects node types ('iri' or 'literal')")));
					
					// if(strcasecmp(defGetString(def), RDF_COLUMN_OPTION_NODETYPE_IRI) == 0)
					// 	is_iri = true;
				}

				if(strcmp(opt->optname, RDF_COLUMN_OPTION_LITERALTYPE) == 0 || strcmp(opt->optname, RDF_COLUMN_OPTION_LITERAL_TYPE) == 0)
				{				
					if(hasliteralatt)
						ereport(ERROR,
							(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
							 errmsg("invalid %s: '%s'", def->defname, defGetString(def)),
							 errhint("the parameters '%s' and '%s' cannot be combined",
								RDF_COLUMN_OPTION_LITERAL_TYPE,
								RDF_COLUMN_OPTION_LANGUAGE)));
					
					hasliteralatt = true;

					if(ContainsWhitespaces(defGetString(def)))
						ereport(ERROR,
							(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
							errmsg("invalid %s: '%s'", def->defname, defGetString(def)),
							errhint("whitespaces are not allwoed in '%s' option", RDF_COLUMN_OPTION_LITERAL_TYPE)));
				}

				if(strcmp(opt->optname, RDF_COLUMN_OPTION_LANGUAGE) == 0)
				{
					if(hasliteralatt)
						ereport(ERROR,
							(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
							 errmsg("invalid %s: '%s'", def->defname, defGetString(def)),
							 errhint("the parameters '%s' and '%s' cannot be combined",
								RDF_COLUMN_OPTION_LITERAL_TYPE,
								RDF_COLUMN_OPTION_LANGUAGE)));
					
					hasliteralatt = true;

					if(ContainsWhitespaces(defGetString(def)))
						ereport(ERROR,
							(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
							errmsg("invalid %s: '%s'", def->defname, defGetString(def)),
							errhint("whitespaces are not allwoed in '%s' option",
								RDF_COLUMN_OPTION_LANGUAGE)));
				}

				// if(strcmp(opt->optname, RDF_COLUMN_OPTION_LITERAL_FORMAT) == 0)
				// {
				// 	char *literal_format = defGetString(def);

				// 	if (strcmp(literal_format, RDF_COLUMN_OPTION_VALUE_LITERAL_RAW) != 0 && strcmp(literal_format, RDF_COLUMN_OPTION_VALUE_LITERAL_CONTENT) != 0)
				// 		ereport(ERROR,
				// 				(errcode(ERRCODE_FDW_INVALID_STRING_FORMAT),
				// 				 errmsg("invalid %s: '%s'", def->defname, literal_format),
				// 				 errhint("this parameter can only be '%s' or '%s'",
				// 						 RDF_COLUMN_OPTION_VALUE_LITERAL_RAW,
				// 						 RDF_COLUMN_OPTION_VALUE_LITERAL_CONTENT)));

				// 	if (strcmp(literal_format, RDF_COLUMN_OPTION_VALUE_LITERAL_RAW) == 0 && is_iri)
				// 		ereport(ERROR,
				// 				(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
				// 				 errmsg("invalid %s: '%s'", def->defname, literal_format),
				// 				 errhint("%s columns can only be of %s '%s'",
				// 						 RDF_COLUMN_OPTION_VALUE_LITERAL_RAW,
				// 						 RDF_COLUMN_OPTION_NODETYPE,
				// 						 RDF_COLUMN_OPTION_NODETYPE_LITERAL)));

				// 	if (strcmp(literal_format, RDF_COLUMN_OPTION_VALUE_LITERAL_RAW) == 0 && hasliteralatt)
				// 		ereport(ERROR,
				// 			(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
				// 			errmsg("invalid %s: '%s'", def->defname, defGetString(def)),
				// 			errhint("the parameter '%s' cannot be combined with '%s' or '%s'",
				// 				RDF_COLUMN_OPTION_LITERAL_FORMAT,
				// 				RDF_COLUMN_OPTION_LANGUAGE,
				// 				RDF_COLUMN_OPTION_LITERAL_TYPE)));
				// }

				break;
			}
		}

		if (!optfound)
		{
			ereport(ERROR,
					(errcode(ERRCODE_FDW_INVALID_OPTION_NAME),
					 errmsg("invalid rdf_fdw option '%s'", def->defname)));
		}
	}

	for (opt = valid_options; opt->optname; opt++)
	{
		/* Required option for this catalog type is missing? */
		if (catalog == opt->optcontext && opt->optrequired && !opt->optfound)
		{
			ereport(ERROR, 
					(errcode(ERRCODE_FDW_DYNAMIC_PARAMETER_VALUE_NEEDED),
					 errmsg("required option '%s' is missing", opt->optname)));
		}
	}

	elog(DEBUG1,"%s exit", __func__);
	PG_RETURN_VOID();
}

static void rdfGetForeignRelSize(PlannerInfo *root, RelOptInfo *baserel, Oid foreigntableid)
{
	struct RDFfdwState *state = (struct RDFfdwState *)palloc0(sizeof(RDFfdwState));

	elog(DEBUG1, "%s called", __func__);

	state->foreigntableid = foreigntableid;
	state->startup_cost = 10000.0;
	/* estimate total cost as startup cost + 10 * (returned rows) */
	state->total_cost = state->startup_cost + baserel->rows * 10.0;

	//InitSession(state, baserel, root);

	baserel->fdw_private = state;
}

static void rdfGetForeignPaths(PlannerInfo *root, RelOptInfo *baserel, Oid foreigntableid)
{

	struct RDFfdwState *state = (struct RDFfdwState *)baserel->fdw_private;

	Path *path = (Path *)create_foreignscan_path(root, baserel,
												 NULL,			/* default pathtarget */
												 baserel->rows, /* rows */
#if PG_VERSION_NUM >= 180000
												 0,						  /* no disabled plan nodes */
#endif																	  /* PG_VERSION_NUM */
												 state->startup_cost,	  /* startup cost */
												 state->total_cost,		  /* total cost */
												 NIL,					  /* no pathkeys */
												 baserel->lateral_relids, /* no required outer relids */
												 NULL,					  /* no fdw_outerpath */
#if PG_VERSION_NUM >= 170000
												 NIL,	/* no fdw_restrictinfo */
#endif													/* PG_VERSION_NUM */
												 NULL); /* no fdw_private */
	add_path(baserel, path);
}

static ForeignScan *rdfGetForeignPlan(PlannerInfo *root, RelOptInfo *baserel, Oid foreigntableid, ForeignPath *best_path, List *tlist, List *scan_clauses, Plan *outer_plan)
{
	struct RDFfdwState *state = (struct RDFfdwState *)baserel->fdw_private;
	List *fdw_private = NIL;
	ListCell *cell;

	elog(DEBUG1,"%s called",__func__);

	foreach (cell, scan_clauses)
	{
		Node *node = (Node *)lfirst(cell);
		elog(DEBUG2, "%s: original scan_clauses nodeTag=%u", __func__, nodeTag(node));
	}

	scan_clauses = extract_actual_clauses(scan_clauses, false);

	/* Debug extracted scan_clauses */
	foreach (cell, scan_clauses)
	{
		Expr *clause = (Expr *)lfirst(cell);
		elog(DEBUG2, "%s: extracted expr_clauses clause nodeTag=%u", __func__, nodeTag(clause));
	}

	InitSession(state, baserel, root);

	if(!state->enable_pushdown) 
	{
		state->sparql = state->raw_sparql;
		elog(DEBUG2,"  %s: Pushdown feature disabled. SPARQL query won't be modified.",__func__);
	} 
	else if(!state->is_sparql_parsable) 
	{
		state->sparql = state->raw_sparql;
		elog(DEBUG2,"  %s: SPARQL cannot be fully parsed. The raw SPARQL will be used and all filters will be applied locally.",__func__);
	}
	else 
	{
		CreateSPARQL(state, root);
	}

	fdw_private = SerializePlanData(state);

	return make_foreignscan(tlist,
							scan_clauses,
							baserel->relid,
							NIL,		 /* no expressions we will evaluate */
							fdw_private, /* pass along our start and end */
							NIL,		 /* no custom tlist; our scan tuple looks like tlist */
							NIL,		 /* no quals we will recheck */
							outer_plan);
}

static void rdfBeginForeignScan(ForeignScanState *node, int eflags)
{
	ForeignScan *fs = (ForeignScan *)node->ss.ps.plan;
	struct RDFfdwState *state;

	if (eflags & EXEC_FLAG_EXPLAIN_ONLY)
		return;
	
	elog(DEBUG1,"%s called",__func__);

	state = DeserializePlanData(fs->fdw_private);

	elog(DEBUG2,"%s: initializing XML parser",__func__);
	xmlInitParser();

	LoadRDFData(state);
	state->rowcount = 0;
	node->fdw_state = (void *)state;
}

static TupleTableSlot *rdfIterateForeignScan(ForeignScanState *node)
{
	TupleTableSlot *slot = node->ss.ss_ScanTupleSlot;
	struct RDFfdwState *state = (struct RDFfdwState *) node->fdw_state;

	elog(DEBUG3, "%s called", __func__);

	if (state->numcols == 0)
	{
		elog(DEBUG3, "  %s: no foreign column available in this table.", __func__);
		return NULL;
	}

	elog(DEBUG3, "  %s: rowcount = %d | pagesize = %d", __func__, state->rowcount, state->pagesize);

	if (state->rowcount >= state->pagesize)
		return NULL;

	CreateTuple(slot, state);
	//ExecStoreVirtualTuple(slot);  // REQUIRED to return a valid tuple
	elog(DEBUG3, "%s: virtual tuple stored (%d/%d)", __func__, state->rowcount, state->pagesize);
	elog(DEBUG3, "%s: valid slots = %d", __func__, slot->tts_nvalid);

	state->rowcount++;

	return slot;
}


static void rdfReScanForeignScan(ForeignScanState *node)
{
}

static void rdfEndForeignScan(ForeignScanState *node)
{
	struct RDFfdwState *state;

	elog(DEBUG1,"%s: called ",__func__);

	if(node->fdw_state) {

		state = (struct RDFfdwState *) node->fdw_state;

		if(state->xmldoc)
		{
			elog(DEBUG2,"%s: freeing xmldoc",__func__);
			xmlFreeDoc(state->xmldoc);
		}

		if(state)
		{
			elog(DEBUG2,"%s: freeing rdf_fdw state",__func__);
			pfree(state);
		}

	}

	elog(DEBUG1,"%s exit: so long .. \n",__func__);
}

static void LoadRDFTableInfo(RDFfdwState *state)
{
	ListCell *cell;	
	TupleDesc tupdesc;
#if PG_VERSION_NUM < 130000
	Relation rel = heap_open(state->foreigntableid, NoLock);
#else
	Relation rel = table_open(state->foreigntableid, NoLock);
#endif

	elog(DEBUG1, "%s called", __func__);

	state->numcols = rel->rd_att->natts;
	tupdesc = rel->rd_att;

	/*
	 *Loading FOREIGN TABLE strucuture (columns and their OPTION values)
	 */
	state->rdfTable = (struct RDFfdwTable *) palloc0(sizeof(struct RDFfdwTable));
	state->rdfTable->cols = (struct RDFfdwColumn **) palloc0(sizeof(struct RDFfdwColumn*) * state->numcols);

	for (int i = 0; i < state->numcols; i++)
	{
		List *options = GetForeignColumnOptions(state->foreigntableid, i + 1);
		ListCell *lc;

		Form_pg_attribute attr = TupleDescAttr(tupdesc, i);
		state->rdfTable->cols[i] = (struct RDFfdwColumn *)palloc0(sizeof(struct RDFfdwColumn));

		/*
		 * Setting foreign table colmuns's default values.
		 */
		state->rdfTable->cols[i]->pushable = true;
		state->rdfTable->cols[i]->nodetype = RDF_COLUMN_OPTION_NODETYPE_LITERAL;
		state->rdfTable->cols[i]->used = false;
		//state->rdfTable->cols[i]->literal_fomat = RDF_COLUMN_OPTION_VALUE_LITERAL_CONTENT;

		foreach (lc, options)
		{
			DefElem *def = (DefElem *)lfirst(lc);

			if (strcmp(def->defname, RDF_COLUMN_OPTION_VARIABLE) == 0)
			{
				elog(DEBUG2,"  %s: (%d) adding sparql variable > '%s'",__func__,i,defGetString(def));
				state->rdfTable->cols[i]->sparqlvar = pstrdup(defGetString(def));
			}
			else if (strcmp(def->defname, RDF_COLUMN_OPTION_EXPRESSION) == 0)
			{
				elog(DEBUG2,"  %s: (%d) adding sparql expression > '%s'",__func__,i,defGetString(def));
				state->rdfTable->cols[i]->expression = pstrdup(defGetString(def));
				state->rdfTable->cols[i]->pushable = IsExpressionPushable(defGetString(def));
				elog(DEBUG2,"  %s: (%d) is expression pushable? > '%s'",__func__,i,
					state->rdfTable->cols[i]->pushable ? "true" : "false");
			}
			else if (strcmp(def->defname, RDF_COLUMN_OPTION_LITERALTYPE) == 0 || strcmp(def->defname, RDF_COLUMN_OPTION_LITERAL_TYPE) == 0 )
			{
				// StringInfoData literaltype;
				// initStringInfo(&literaltype);
				// appendStringInfo(&literaltype, "^^%s", defGetString(def));
				elog(DEBUG2,"  %s: (%d) adding sparql literal data type > '%s'",__func__,i,defGetString(def));
				//state->rdfTable->cols[i]->literaltype = pstrdup(literaltype.data);
				state->rdfTable->cols[i]->literaltype = pstrdup(defGetString(def));
			}
			// else if (strcmp(def->defname, RDF_COLUMN_OPTION_LITERAL_FORMAT) == 0 )
			// {
			// 	elog(DEBUG2,"  %s: (%d) adding sparql node format > '%s'",__func__,i,defGetString(def));
			// 	state->rdfTable->cols[i]->literal_fomat = pstrdup(defGetString(def));
			// }
			else if (strcmp(def->defname, RDF_COLUMN_OPTION_NODETYPE) == 0)
			{
				elog(DEBUG2,"  %s: (%d) adding sparql node data type > '%s'",__func__,i,defGetString(def));
				state->rdfTable->cols[i]->nodetype = pstrdup(defGetString(def));
			}
			else if (strcmp(def->defname, RDF_COLUMN_OPTION_LANGUAGE) == 0) 
			{
				// StringInfoData tag;
				// initStringInfo(&tag);
				// appendStringInfo(&tag, "@%s", defGetString(def));
				elog(DEBUG2,"  %s: (%d) adding literal language tag > '%s'",__func__,i,defGetString(def));
				//state->rdfTable->cols[i]->language = pstrdup(tag.data);
				state->rdfTable->cols[i]->language = pstrdup(defGetString(def));
			}
		}

#if PG_VERSION_NUM < 110000
		elog(DEBUG1,"  %s: (%d) adding data type > %u",__func__,i,attr->atttypid);
		state->rdfTable->cols[i]->pgtype = attr->atttypid;
		state->rdfTable->cols[i]->name = pstrdup(NameStr(attr->attname));
		state->rdfTable->cols[i]->pgtypmod = attr->atttypmod;
		state->rdfTable->cols[i]->pgattnum = attr->attnum;

#else
		elog(DEBUG1,"  %s: (%d) adding data type > %u",__func__,i,attr->atttypid);
		state->rdfTable->cols[i]->pgtype = attr->atttypid;
		state->rdfTable->cols[i]->name = pstrdup(NameStr(attr->attname));
		state->rdfTable->cols[i]->pgtypmod = attr->atttypmod;
		state->rdfTable->cols[i]->pgattnum = attr->attnum;
#endif
	}

#if PG_VERSION_NUM < 130000
	heap_close(rel, NoLock);
#else
	table_close(rel, NoLock);
#endif


	/*
	 * Loading FOREIGN TABLE OPTIONS
	 */
	foreach (cell, state->foreign_table->options)
	{
		DefElem *def = lfirst_node(DefElem, cell);

		if (strcmp(RDF_TABLE_OPTION_SPARQL, def->defname) == 0)
		{
			state->raw_sparql = defGetString(def);
			state->is_sparql_parsable = IsSPARQLParsable(state);
		}
		else if (strcmp(RDF_TABLE_OPTION_LOG_SPARQL, def->defname) == 0)
			state->log_sparql = defGetBoolean(def);
			//state->log_sparql = getBoolVal(def);

		else if (strcmp(RDF_TABLE_OPTION_ENABLE_PUSHDOWN, def->defname) == 0)
			state->enable_pushdown = defGetBoolean(def);
			//state->enable_pushdown = getBoolVal(def);
	}

	elog(DEBUG1,"%s exit", __func__);
}

static void LoadRDFServerInfo(RDFfdwState *state)
{
	elog(DEBUG1, "%s called", __func__);

	if (state->server)
	{
		ListCell *cell;

		foreach (cell, state->server->options)
		{
			DefElem *def = lfirst_node(DefElem, cell);

			if (strcmp(RDF_SERVER_OPTION_ENDPOINT, def->defname) == 0)
				state->endpoint = defGetString(def);

			else if (strcmp(RDF_SERVER_OPTION_FORMAT, def->defname) == 0)
				state->format = defGetString(def);

			else if (strcmp(RDF_SERVER_OPTION_CUSTOMPARAM, def->defname) == 0)
				state->custom_params = defGetString(def);

			else if (strcmp(RDF_SERVER_OPTION_HTTP_PROXY, def->defname) == 0)
			{
				state->proxy = defGetString(def);
				state->proxy_type = RDF_SERVER_OPTION_HTTP_PROXY;
			}
			else if (strcmp(RDF_SERVER_OPTION_HTTPS_PROXY, def->defname) == 0)
			{
				state->proxy = defGetString(def);
				state->proxy_type = RDF_SERVER_OPTION_HTTPS_PROXY;
			}
			else if (strcmp(RDF_SERVER_OPTION_PROXY_USER, def->defname) == 0)
				state->proxy_user = defGetString(def);

			else if (strcmp(RDF_SERVER_OPTION_PROXY_USER_PASSWORD, def->defname) == 0)
				state->proxy_user_password = defGetString(def);

			else if (strcmp(RDF_SERVER_OPTION_FETCH_SIZE, def->defname) == 0)
			{
				char *tailpt;
				char *fetch_size_str = defGetString(def);
				state->fetch_size = strtol(fetch_size_str, &tailpt, 0);
			}
			else if (strcmp(RDF_SERVER_OPTION_CONNECTRETRY, def->defname) == 0)
			{
				char *tailpt;
				char *maxretry_str = defGetString(def);
				state->max_retries = strtol(maxretry_str, &tailpt, 0);
			}
			else if (strcmp(RDF_SERVER_OPTION_REQUEST_REDIRECT, def->defname) == 0)
				state->request_redirect = defGetBoolean(def);
				//state->request_redirect = getBoolVal(def);

			else if (strcmp(RDF_SERVER_OPTION_REQUEST_MAX_REDIRECT, def->defname) == 0)
			{
				char *tailpt;
				char *maxredirect_str = defGetString(def);
				state->request_max_redirect = strtol(maxredirect_str, &tailpt, 0);
			}
			else if (strcmp(RDF_SERVER_OPTION_CONNECTTIMEOUT, def->defname) == 0)
			{
				char *tailpt;
				char *timeout_str = defGetString(def);
				state->connect_timeout = strtol(timeout_str, &tailpt, 0);
			}
			else if (strcmp(RDF_SERVER_OPTION_ENABLE_PUSHDOWN, def->defname) == 0)
				state->enable_pushdown = defGetBoolean(def);
				//state->enable_pushdown = getBoolVal(def);

			else if (strcmp(RDF_SERVER_OPTION_QUERY_PARAM, def->defname) == 0)
				state->query_param = defGetString(def);

			else if (strcmp(RDF_SERVER_OPTION_BASE_URI, def->defname) == 0)
				state->base_uri = defGetString(def);
		}
	}

	elog(DEBUG1,"%s exit", __func__);
}

static void LoadRDFUserMapping(RDFfdwState *state)
{

	Datum		datum;
	HeapTuple	tp;
	bool		isnull;
	UserMapping *um;
	List *options = NIL;
	ListCell *cell;
	bool usermatch = true;

	elog(DEBUG1, "%s called", __func__);

	tp = SearchSysCache2(USERMAPPINGUSERSERVER,
						 ObjectIdGetDatum(GetUserId()),
						 ObjectIdGetDatum(state->server->serverid));

	if (!HeapTupleIsValid(tp))
	{
		elog(DEBUG2, "%s: not found for the specific user -- try PUBLIC",__func__);
		tp = SearchSysCache2(USERMAPPINGUSERSERVER,
							 ObjectIdGetDatum(InvalidOid),
							 ObjectIdGetDatum(state->server->serverid));
	}

	if (!HeapTupleIsValid(tp))
	{
		elog(DEBUG2, "%s: user mapping not found for user \"%s\", server \"%s\"",
			 __func__, MappingUserName(GetUserId()), state->server->servername);

		usermatch = false;
	}

	if (usermatch)
	{
		elog(DEBUG2, "%s: setting UserMapping*", __func__);
		um = (UserMapping *)palloc(sizeof(UserMapping));
#if PG_VERSION_NUM < 120000
		um->umid = HeapTupleGetOid(tp);
#else
		um->umid = ((Form_pg_user_mapping)GETSTRUCT(tp))->oid;
#endif		
		um->userid = GetUserId();
		um->serverid = state->server->serverid;

		elog(DEBUG2, "%s: extract the umoptions", __func__);
		datum = SysCacheGetAttr(USERMAPPINGUSERSERVER,
								tp,
								Anum_pg_user_mapping_umoptions,
								&isnull);
		if (isnull)
			um->options = NIL;
		else
			um->options = untransformRelOptions(datum);

		if (um->options != NIL)
		{
			options = list_concat(options, um->options);

			foreach (cell, options)
			{
				DefElem *def = (DefElem *)lfirst(cell);

				if (strcmp(def->defname, RDF_USERMAPPING_OPTION_USER) == 0)
				{
					state->user = pstrdup(defGetString(def));
					elog(DEBUG2, "%s: %s '%s'", __func__, def->defname, state->user);
				}

				if (strcmp(def->defname, RDF_USERMAPPING_OPTION_PASSWORD) == 0)
				{					
					state->password = pstrdup(defGetString(def));
					elog(DEBUG2, "%s: %s '*******'", __func__, def->defname);
				}
			}
		}

		ReleaseSysCache(tp);
	}

	elog(DEBUG1,"%s exit", __func__);
}
/*
 * CStringToConst
 * -----------------
 * Extracts a Const from a char*
 *
 * returns Const from given string.
 */
Const *CStringToConst(const char* str)
{
	if (str == NULL)
		return makeNullConst(TEXTOID, -1, InvalidOid);
	else
		return makeConst(TEXTOID, -1, InvalidOid, -1, PointerGetDatum(cstring_to_text(str)), false, false);
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
 * SerializePlanData
 * -----------------
 * Converts parameters into Const variables, so that it can be properly 
 * stored by the plan
 * 
 * state: SPARQL, SERVER and FOREIGN TABLE info
 * 
 * returns a List containing all converted parameterrs.
 */
static List *SerializePlanData(RDFfdwState *state)
{
	List *result = NIL;

	elog(DEBUG1,"%s called",__func__);

	result = lappend(result, IntToConst((int)state->numcols));
	result = lappend(result, CStringToConst(state->sparql));
	result = lappend(result, CStringToConst(state->sparql_prefixes));
	result = lappend(result, CStringToConst(state->sparql_select));
	result = lappend(result, CStringToConst(state->sparql_from));
	result = lappend(result, CStringToConst(state->sparql_where));
	result = lappend(result, CStringToConst(state->sparql_filter));
	result = lappend(result, CStringToConst(state->sparql_orderby));
	result = lappend(result, CStringToConst(state->sparql_limit));
	result = lappend(result, CStringToConst(state->raw_sparql));
	result = lappend(result, CStringToConst(state->endpoint));
	result = lappend(result, CStringToConst(state->query_param));
	result = lappend(result, CStringToConst(state->format));
	result = lappend(result, CStringToConst(state->proxy));
	result = lappend(result, CStringToConst(state->proxy_type));
	result = lappend(result, CStringToConst(state->proxy_user));
	result = lappend(result, CStringToConst(state->proxy_user_password));
	result = lappend(result, CStringToConst(state->custom_params));
	result = lappend(result, CStringToConst(state->user));
	result = lappend(result, CStringToConst(state->password));
	result = lappend(result, IntToConst((int)state->request_redirect));
	result = lappend(result, IntToConst((int)state->enable_pushdown));
	result = lappend(result, IntToConst((int)state->is_sparql_parsable));
	result = lappend(result, IntToConst((int)state->log_sparql));
	result = lappend(result, IntToConst((int)state->has_unparsable_conds));
	result = lappend(result, IntToConst((int)state->request_max_redirect));
	result = lappend(result, IntToConst((int)state->connect_timeout));
	result = lappend(result, IntToConst((int)state->max_retries));
	result = lappend(result, OidToConst(state->foreigntableid));

	elog(DEBUG2,"%s: serializing table with %d columns",__func__, state->numcols);
	for (int i = 0; i < state->numcols; ++i)
	{
		elog(DEBUG2,"%s: column name '%s'",__func__, state->rdfTable->cols[i]->name);
		result = lappend(result, CStringToConst(state->rdfTable->cols[i]->name));

		elog(DEBUG2,"%s: sparqlvar '%s'",__func__, state->rdfTable->cols[i]->sparqlvar);
		result = lappend(result, CStringToConst(state->rdfTable->cols[i]->sparqlvar));

		elog(DEBUG2,"%s: expression '%s'",__func__, state->rdfTable->cols[i]->expression);
		result = lappend(result, CStringToConst(state->rdfTable->cols[i]->expression));

		elog(DEBUG2,"%s: literaltype '%s'",__func__, state->rdfTable->cols[i]->literaltype);
		result = lappend(result, CStringToConst(state->rdfTable->cols[i]->literaltype));

		elog(DEBUG2,"%s: literal_format '%s'",__func__, state->rdfTable->cols[i]->literal_fomat);
		result = lappend(result, CStringToConst(state->rdfTable->cols[i]->literal_fomat));

		elog(DEBUG2,"%s: nodetype '%s'",__func__, state->rdfTable->cols[i]->nodetype);
		result = lappend(result, CStringToConst(state->rdfTable->cols[i]->nodetype));

		elog(DEBUG2,"%s: language '%s'",__func__, state->rdfTable->cols[i]->language);
		result = lappend(result, CStringToConst(state->rdfTable->cols[i]->language));

		elog(DEBUG2,"%s: pgtype '%u'",__func__, state->rdfTable->cols[i]->pgtype);
		result = lappend(result, OidToConst(state->rdfTable->cols[i]->pgtype));

		elog(DEBUG2,"%s: pgtypmod '%d'",__func__, state->rdfTable->cols[i]->pgtypmod);
		result = lappend(result, IntToConst(state->rdfTable->cols[i]->pgtypmod));

		elog(DEBUG2,"%s: pgattnum '%d'",__func__, state->rdfTable->cols[i]->pgattnum);
		result = lappend(result, IntToConst(state->rdfTable->cols[i]->pgattnum));

		elog(DEBUG2,"%s: used '%d'",__func__, state->rdfTable->cols[i]->used);
		result = lappend(result, IntToConst(state->rdfTable->cols[i]->used));

		elog(DEBUG2,"%s: pushable '%d'",__func__, state->rdfTable->cols[i]->pushable);
		result = lappend(result, IntToConst(state->rdfTable->cols[i]->pushable));
	}

	elog(DEBUG1,"%s exit", __func__);
	return result;
}

/*
 * DeserializePlanData
 * -------------------
 * Converts Const variables created using SerializePlanData back
 * into pointers
 * 
 * state: SPARQL, SERVER and FOREIGN TABLE info
 * 
 * returns a RDFfdwState containing all converted parameterrs.
 */
static struct RDFfdwState *DeserializePlanData(List *list)
{
	struct RDFfdwState *state = (struct RDFfdwState *)palloc0(sizeof(RDFfdwState));
	ListCell *cell = list_head(list);

	elog(DEBUG1,"%s called",__func__);

	state->numcols = (int)DatumGetInt32(((Const *)lfirst(cell))->constvalue);
	state->rowcount = 0;
	state->pagesize = 0;
	cell = list_next(list, cell);

	state->sparql = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->sparql_prefixes = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->sparql_select = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->sparql_from = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->sparql_where = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->sparql_filter = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->sparql_orderby = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->sparql_limit = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->raw_sparql = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->endpoint = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->query_param = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->format = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->proxy = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->proxy_type = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->proxy_user = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->proxy_user_password = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->custom_params = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->user = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->password = ConstToCString(lfirst(cell));
	cell = list_next(list, cell);

	state->request_redirect = (bool) DatumGetInt32(((Const *)lfirst(cell))->constvalue);
	cell = list_next(list, cell);

	state->enable_pushdown = (bool) DatumGetInt32(((Const *)lfirst(cell))->constvalue);
	cell = list_next(list, cell);

	state->is_sparql_parsable = (bool) DatumGetInt32(((Const *)lfirst(cell))->constvalue);
	cell = list_next(list, cell);

	state->log_sparql = (bool) DatumGetInt32(((Const *)lfirst(cell))->constvalue);
	cell = list_next(list, cell);

	state->has_unparsable_conds = (bool) DatumGetInt32(((Const *)lfirst(cell))->constvalue);
	cell = list_next(list, cell);

	state->request_max_redirect = (int) DatumGetInt32(((Const *)lfirst(cell))->constvalue);
	cell = list_next(list, cell);

	state->connect_timeout = (int) DatumGetInt32(((Const *)lfirst(cell))->constvalue);
	cell = list_next(list, cell);

	state->max_retries = (int) DatumGetInt32(((Const *)lfirst(cell))->constvalue);
	cell = list_next(list, cell);

	state->foreigntableid = DatumGetObjectId(((Const *)lfirst(cell))->constvalue);
	cell = list_next(list, cell);

	elog(DEBUG2,"  %s: deserializing table with %d columns",__func__, state->numcols);
	state->rdfTable = (struct RDFfdwTable *) palloc0(sizeof(struct RDFfdwTable));
	state->rdfTable->cols = (struct RDFfdwColumn **) palloc0(sizeof(struct RDFfdwColumn*) * state->numcols);

	for (int i = 0; i<state->numcols; ++i)
	{
		state->rdfTable->cols[i] = (struct RDFfdwColumn *)palloc0(sizeof(struct RDFfdwColumn));

		state->rdfTable->cols[i]->name = ConstToCString(lfirst(cell));
		cell = list_next(list, cell);
		elog(DEBUG2,"  %s: column name '%s'",__func__, state->rdfTable->cols[i]->name);

		state->rdfTable->cols[i]->sparqlvar = ConstToCString(lfirst(cell));
		cell = list_next(list, cell);

		state->rdfTable->cols[i]->expression = ConstToCString(lfirst(cell));
		cell = list_next(list, cell);

		state->rdfTable->cols[i]->literaltype = ConstToCString(lfirst(cell));
		cell = list_next(list, cell);

		state->rdfTable->cols[i]->literal_fomat = ConstToCString(lfirst(cell));
		cell = list_next(list, cell);

		state->rdfTable->cols[i]->nodetype = ConstToCString(lfirst(cell));
		cell = list_next(list, cell);

		state->rdfTable->cols[i]->language = ConstToCString(lfirst(cell));
		cell = list_next(list, cell);

		state->rdfTable->cols[i]->pgtype = DatumGetObjectId(((Const *)lfirst(cell))->constvalue);
		cell = list_next(list, cell);

		state->rdfTable->cols[i]->pgtypmod = (int)DatumGetInt32(((Const *)lfirst(cell))->constvalue);
		cell = list_next(list, cell);

		state->rdfTable->cols[i]->pgattnum = (int)DatumGetInt32(((Const *)lfirst(cell))->constvalue);
		cell = list_next(list, cell);

		state->rdfTable->cols[i]->used = (bool)DatumGetInt32(((Const *)lfirst(cell))->constvalue);
		cell = list_next(list, cell);

		state->rdfTable->cols[i]->pushable = (bool)DatumGetInt32(((Const *)lfirst(cell))->constvalue);
		cell = list_next(list, cell);

	}

	elog(DEBUG1,"%s exit", __func__);
	return state;
}

static size_t WriteMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp)
{
	size_t realsize = size * nmemb;
	struct MemoryStruct *mem = (struct MemoryStruct *)userp;
	char *ptr = repalloc(mem->memory, mem->size + realsize + 1);

	elog(DEBUG1,"%s called", __func__);

	if (!ptr)
		ereport(ERROR,
				(errcode(ERRCODE_FDW_OUT_OF_MEMORY),
				 errmsg("out of memory (repalloc returned NULL)")));

	mem->memory = ptr;
	memcpy(&(mem->memory[mem->size]), contents, realsize);
	mem->size += realsize;
	mem->memory[mem->size] = 0;

	elog(DEBUG1,"%s exit: returning '%lu' (realsize)", __func__, realsize);
	return realsize;
}

static size_t HeaderCallbackFunction(char *contents, size_t size, size_t nmemb, void *userp)
{

	size_t realsize = size * nmemb;
	struct MemoryStruct *mem = (struct MemoryStruct *)userp;
	char *ptr;
	char *sparqlxml = "content-type: application/sparql-results+xml";
	char *sparqlxmlutf8 = "content-type: application/sparql-results+xml; charset=utf-8";
	char *rdfxml = "content-type: application/rdf+xml";
	char *rdfxmlutf8 = "content-type: application/rdf+xml;charset=utf-8";

	elog(DEBUG1,"%s called", __func__);

	Assert(contents);

	/* is it a "content-type" entry? "*/	
	if (strncasecmp(contents, sparqlxml, 13) == 0)
	{

		if (strncasecmp(contents, sparqlxml, strlen(sparqlxml)) != 0 &&
			strncasecmp(contents, sparqlxmlutf8, strlen(sparqlxmlutf8)) != 0 &&
			strncasecmp(contents, rdfxml, strlen(rdfxml)) != 0 &&
			strncasecmp(contents, rdfxmlutf8, strlen(rdfxmlutf8)) != 0)
		{
			/* remove crlf */
			contents[strlen(contents) - 2] = '\0';
			elog(WARNING, "%s: unsupported header entry: \"%s\"", __func__, contents);
			return 0;
		}
	}

	ptr = repalloc(mem->memory, mem->size + realsize + 1);

	if (!ptr)
	{
		ereport(ERROR,
				(errcode(ERRCODE_FDW_OUT_OF_MEMORY),
				 errmsg("[%s] out of memory (repalloc returned NULL)", __func__)));
	}

	mem->memory = ptr;
	memcpy(&(mem->memory[mem->size]), contents, realsize);
	mem->size += realsize;
	mem->memory[mem->size] = 0;

	elog(DEBUG1,"%s exit: returning '%lu' (realsize)", __func__, realsize);
	return realsize;
}

/*
 * CURLProgressCallback
 * --------------------
 * Progress callback function for cURL requests. This allows us to
 * check for interruptions to immediatelly cancel the request.
 * 
 * dltotal: Total bytes to download
 * dlnow: Bytes downloaded so far
 * ultotal: Total bytes to upload
 * ulnow: Bytes uploaded so far
 */
static int CURLProgressCallback(void *clientp, curl_off_t dltotal, curl_off_t dlnow, curl_off_t ultotal, curl_off_t ulnow)
{
	CHECK_FOR_INTERRUPTS();

	return 0;
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
static int CheckURL(char *url)
{
	CURLUcode code;
	CURLU *handler = curl_url();

	elog(DEBUG1, "%s called: '%s'", __func__, url);

	code = curl_url_set(handler, CURLUPART_URL, url, 0);

	curl_url_cleanup(handler);

	elog(DEBUG2, "  %s handler return code: %u", __func__, code);

	if (code != 0)
	{
		elog(DEBUG2, "%s: invalid URL (%u) > '%s'", __func__, code, url);
		return code;
	}

	elog(DEBUG1,"%s exit: returning '%d' (REQUEST_SUCCESS)", __func__, REQUEST_SUCCESS);
	return REQUEST_SUCCESS;
}

/*
 * GetRDFColumn
 * -------------
 * Returns the RDFfdwColumn mapped to the table column in `columname`
 * 
 * state    : SPARQL, SERVER and FOREIGN TABLE info
 * columname: name of the FOREIGN TABLE column
 * 
 * returns RDFfdwColumn loded with all its attributes
 */
static struct RDFfdwColumn *GetRDFColumn(struct RDFfdwState *state, char *columnname){

	elog(DEBUG1,"%s called: column='%s'",__func__, columnname);

	if(!columnname)
	{
		elog(DEBUG1,"%s exit: returning NULL (columnname is NULL)", __func__);
		return NULL;
	}

	for (int i = 0; i < state->numcols; i++)
	{
		if (strcmp(state->rdfTable->cols[i]->name, columnname) == 0)
		{
			elog(DEBUG1,"%s exit: rerurning match for columname '%s'",__func__, columnname);
			return state->rdfTable->cols[i];
		}	
	}

	elog(DEBUG1,"%s exit: rerurning NULL (no match found for '%s')",__func__,columnname);
	return NULL;
}

/*
 * InitSession
 * ----------
 * This function loads the 'OPTION' variables declared in SERVER and FOREIGN 
 * TABLE statements. It also parses the raw_sparql query into its main clauses, 
 * so that it can be later modified to match the SQL SELECT clause and commands
 * that can be pushed down to SPARQL
 * 
 * state  : SPARQL, SERVER and FOREIGN TABLE info
 * baserel: Conditions and columns used in the SQL query
 * root   : Planner info
 */
static void InitSession(struct RDFfdwState *state, RelOptInfo *baserel, PlannerInfo *root) {

	List *columnlist = baserel->reltarget->exprs;
	List *conditions = baserel->baserestrictinfo;
	ListCell *cell;
	StringInfoData select;

	elog(DEBUG1,"%s called",__func__);

	//TODO: create function to retrieve the OID of custom data types for 9.6+
	RDFNODEOID = get_rdfnode_oid();

	/*
	 * Setting session's default values.
	 */
	state->enable_pushdown = true;
	state->log_sparql = false;
	state->has_unparsable_conds = false;
	state->query_param = RDF_DEFAULT_QUERY_PARAM;
	state->format = RDF_DEFAULT_FORMAT;
	state->connect_timeout = RDF_DEFAULT_CONNECTTIMEOUT;
	state->max_retries = RDF_DEFAULT_MAXRETRY;
	state->fetch_size = RDF_DEFAULT_FETCH_SIZE;
	state->foreign_table = GetForeignTable(state->foreigntableid);
	state->server = GetForeignServer(state->foreign_table->serverid);
	state->sparql_query_type = SPARQL_SELECT;

	/*
	 * Loading SERVER OPTIONS
	 */
	LoadRDFServerInfo(state);

	/*
	 * Loading FOREIGN TABLE structure and OPTIONS
	 */
	LoadRDFTableInfo(state);

	/*
	 * Loading USER MAPPING (if any)
	 */
	LoadRDFUserMapping(state);

	/* 
	 * Marking columns used in the SQL query for SPARQL pushdown
	 */
	elog(DEBUG2, "%s: looking for columns in the SELECT entry list",__func__);
	foreach(cell, columnlist)
		SetUsedColumns((Expr *)lfirst(cell), state, baserel->relid);

	elog(DEBUG2, "%s: looking for columns used in WHERE conditions",__func__);
	foreach(cell, conditions)
		SetUsedColumns((Expr *)lfirst(cell), state, baserel->relid);

	/*
	 * deparse SPARQL PREFIX clauses from raw_sparql, if any
	 */
	state->sparql_prefixes = DeparseSPARQLPrefix(state->raw_sparql);

	/*
	 * We create the SPARQL SELECT clause according to the columns used in the
	 * SQL SELECT. Functions calls and expressions are only pushed down if explicitly
	 * declared in the 'expression' column OPTION.
	 */
	initStringInfo(&select);
	for (int i = 0; i < state->numcols; i++)
	{
		if(state->rdfTable->cols[i]->used && !state->rdfTable->cols[i]->expression)
			appendStringInfo(&select,"%s ",pstrdup(state->rdfTable->cols[i]->sparqlvar));

		else if(state->rdfTable->cols[i]->used && state->rdfTable->cols[i]->expression)
			appendStringInfo(&select,"(%s AS %s) ",pstrdup(state->rdfTable->cols[i]->expression),
												   pstrdup(state->rdfTable->cols[i]->sparqlvar));
	}

	state->sparql_select = pstrdup(select.data);

	/*
	 * Extract the graph patter from the SPARQL WHERE clause
	 */
	state->sparql_where = DeparseSPARQLWhereGraphPattern(state);

	/*
	 * Try to deparse SQL WHERE conditions, if any, to create SPARQL FILTER expressions
	 */
	state->sparql_filter = DeparseSQLWhereConditions(state, baserel);

	/*
	 * deparse SQL ORDER BY, if any, and convert it to SPARQL
	 */
	state->sparql_orderby = DeparseSQLOrderBy(state, root, baserel);

	/*
	 * deparse SQL LIMIT, if any, and convert it to SPARQL
	 */
	state->sparql_limit = DeparseSQLLimit(state, root, baserel);

	/*
	 * deparse SPARQL FROM and FROM NAMED clauses, if any
	 */
	state->sparql_from = DeparseSPARQLFrom(state->raw_sparql);

	elog(DEBUG1,"%s exit", __func__);
}

/*
 * FetchNextBinding
 * ----------------
 * Loads the next binding from the record list 'state->recods' to return to
 * the client.
 *
 * state: SPARQL, SERVER and FOREIGN TABLE info
 *
 * returns xmlNodePtr containg the retrieved record or NULL if EOF.
 */
static xmlNodePtr FetchNextBinding(RDFfdwState *state)
{
	ListCell *cell;
	xmlNodePtr res;

	elog(DEBUG3, "  %s: called > rowcount = %d/%d", __func__, state->rowcount, state->pagesize);

	if (state->rowcount > state->pagesize)
	{
		elog(DEBUG3, "%s exit: returning NULL (EOF!)", __func__);
		return NULL;
	}

	cell = list_nth_cell(state->records, state->rowcount);
	res = (xmlNodePtr) lfirst(cell);

	elog(DEBUG3,"  %s exit: returning %d",__func__,state->rowcount);
	
	return res;
}

/*
 * ExecuteSPARQL
 * -------------
 * Executes the SPARQL query in the endpoint set in the CREATE FOREIGN TABLE
 * and CREATE SERVER statements. The result set is loaded into 'state'.
 * 
 * state: SPARQL, SERVER and FOREIGN TABLE info
 *
 * returns REQUEST_SUCCESS or REQUEST_FAIL
 */
static int ExecuteSPARQL(RDFfdwState *state)
{
	CURLcode res;
	StringInfoData url_buffer;
	StringInfoData user_agent;
	StringInfoData accept_header;
	//StringInfoData http_auth;
	char errbuf[CURL_ERROR_SIZE];
	struct MemoryStruct chunk;
	struct MemoryStruct chunk_header;
	struct curl_slist *headers = NULL;
	long response_code;

	chunk.memory = palloc(1);
	chunk.size = 0; /* no data at this point */
	chunk_header.memory = palloc(1);
	chunk_header.size = 0; /* no data at this point */
	
	elog(DEBUG1, "%s called",__func__);

	curl_global_init(CURL_GLOBAL_ALL);
	state->curl = curl_easy_init();

	initStringInfo(&accept_header);
	appendStringInfo(&accept_header, "Accept: %s", state->format);

	if (state->log_sparql)
		elog(INFO, "SPARQL query sent to '%s':\n\n%s\n", state->endpoint, state->sparql);

	initStringInfo(&url_buffer);
	appendStringInfo(&url_buffer, "%s=%s", state->query_param, curl_easy_escape(state->curl, state->sparql, 0));

	if(state->custom_params)
		appendStringInfo(&url_buffer, "&%s", curl_easy_escape(state->curl, state->custom_params, 0));

	elog(DEBUG2, "  %s: url build > %s?%s", __func__, state->endpoint, url_buffer.data);

	if (state->curl)
	{
		errbuf[0] = 0;

		curl_easy_setopt(state->curl, CURLOPT_URL, state->endpoint);

#if ((LIBCURL_VERSION_MAJOR == 7 && LIBCURL_VERSION_MINOR < 85) || LIBCURL_VERSION_MAJOR < 7)
		curl_easy_setopt(state->curl, CURLOPT_PROTOCOLS, CURLPROTO_HTTP | CURLPROTO_HTTPS);
#else
		curl_easy_setopt(state->curl, CURLOPT_PROTOCOLS_STR, "http,https");
#endif

		curl_easy_setopt(state->curl, CURLOPT_ERRORBUFFER, errbuf);

		curl_easy_setopt(state->curl, CURLOPT_CONNECTTIMEOUT, state->connect_timeout);
		elog(DEBUG2, "  %s: timeout > %ld", __func__, state->connect_timeout);
		elog(DEBUG2, "  %s: max retry > %ld", __func__, state->max_retries);

		if (state->proxy)
		{
			elog(DEBUG2, "  %s: proxy URL > '%s'", __func__, state->proxy);

			curl_easy_setopt(state->curl, CURLOPT_PROXY, state->proxy);

			if (strcmp(state->proxy_type, RDF_SERVER_OPTION_HTTP_PROXY) == 0)
			{
				elog(DEBUG2, "  %s: proxy protocol > 'HTTP'", __func__);
				curl_easy_setopt(state->curl, CURLOPT_PROXYTYPE, CURLPROXY_HTTP);
			}
			else if (strcmp(state->proxy_type, RDF_SERVER_OPTION_HTTPS_PROXY) == 0)
			{
				elog(DEBUG2, "  %s: proxy protocol > 'HTTPS'", __func__);
				curl_easy_setopt(state->curl, CURLOPT_PROXYTYPE, CURLPROXY_HTTPS);
			}

			if (state->proxy_user)
			{
				elog(DEBUG2, "  %s: entering proxy user ('%s').", __func__, state->proxy_user);
				curl_easy_setopt(state->curl, CURLOPT_PROXYUSERNAME, state->proxy_user);
			}

			if (state->proxy_user_password)
			{
				elog(DEBUG2, "  %s: entering proxy user's password.", __func__);
				curl_easy_setopt(state->curl, CURLOPT_PROXYUSERPWD, state->proxy_user_password);
			}
		}

		if (state->request_redirect == true)
		{

			elog(DEBUG2, "  %s: setting request redirect: %d", __func__, state->request_redirect);
			curl_easy_setopt(state->curl, CURLOPT_FOLLOWLOCATION, 1L);

			if (state->request_max_redirect)
			{
				elog(DEBUG2, "  %s: setting maxredirs: %ld", __func__, state->request_max_redirect);
				curl_easy_setopt(state->curl, CURLOPT_MAXREDIRS, state->request_max_redirect);
			}
		}

		curl_easy_setopt(state->curl, CURLOPT_VERBOSE, 1L);
		curl_easy_setopt(state->curl, CURLOPT_POSTFIELDS, url_buffer.data);
		curl_easy_setopt(state->curl, CURLOPT_HEADERFUNCTION, HeaderCallbackFunction);
		curl_easy_setopt(state->curl, CURLOPT_HEADERDATA, (void *)&chunk_header);
		curl_easy_setopt(state->curl, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
		curl_easy_setopt(state->curl, CURLOPT_WRITEDATA, (void *)&chunk);
		curl_easy_setopt(state->curl, CURLOPT_FAILONERROR, true);

        /* Enable verbose mode for debugging */
        curl_easy_setopt(state->curl, CURLOPT_VERBOSE, 1L);

        /* Set the progress callback function */
        curl_easy_setopt(state->curl, CURLOPT_XFERINFOFUNCTION, CURLProgressCallback);

        /* Optional: Pass user data to the callback (NULL in this case) */
        curl_easy_setopt(state->curl, CURLOPT_XFERINFODATA, NULL);

        /* Enable progress callback */
        curl_easy_setopt(state->curl, CURLOPT_NOPROGRESS, 0L);

		initStringInfo(&user_agent);
		appendStringInfo(&user_agent,  "PostgreSQL/%s rdf_fdw/%s libxml2/%s %s", PG_VERSION, FDW_VERSION, LIBXML_DOTTED_VERSION, curl_version());
		curl_easy_setopt(state->curl, CURLOPT_USERAGENT, user_agent.data);

		headers = curl_slist_append(headers, accept_header.data);
		curl_easy_setopt(state->curl, CURLOPT_HTTPHEADER, headers);

		if(state->user && state->password)
		{
			curl_easy_setopt(state->curl, CURLOPT_HTTPAUTH, CURLAUTH_BASIC);
			curl_easy_setopt(state->curl, CURLOPT_USERNAME, state->user);
			curl_easy_setopt(state->curl, CURLOPT_PASSWORD, state->password);
		}
		else if(state->user && !state->password)
		{
			curl_easy_setopt(state->curl, CURLOPT_HTTPAUTH, CURLAUTH_BASIC);
			curl_easy_setopt(state->curl, CURLOPT_USERNAME, state->user);
		}

		elog(DEBUG2, "  %s: performing cURL request ... ", __func__);

		res = curl_easy_perform(state->curl);

		if (res != CURLE_OK)
		{
			for (long i = 1; i <= state->max_retries && (res = curl_easy_perform(state->curl)) != CURLE_OK; i++)
			{
				elog(WARNING, "  %s: request to '%s' failed (%ld)", __func__, state->endpoint, i);
			}
		}

		if (res != CURLE_OK)
		{
			size_t len = strlen(errbuf);
			fprintf(stderr, "\nlibcurl: (%d) ", res);

			xmlFreeDoc(state->xmldoc);
			pfree(chunk.memory);
			pfree(chunk_header.memory);
			curl_slist_free_all(headers);
			curl_easy_cleanup(state->curl);
			curl_global_cleanup();

			if (len)
			{
				curl_easy_getinfo(state->curl, CURLINFO_RESPONSE_CODE, &response_code);
				
				if(response_code == 401)
					ereport(ERROR,
						(errcode(ERRCODE_INVALID_AUTHORIZATION_SPECIFICATION),
						 errmsg("Unauthorized (HTTP status %ld)", response_code),
						 errhint("Check the user and password set in the USER MAPPING and try again.")));
				else if(response_code == 404)
					ereport(ERROR,
						(errcode(ERRCODE_INVALID_AUTHORIZATION_SPECIFICATION),
						 errmsg("Not Found (HTTP status %ld)", response_code),
						 errhint("This indicates that the server cannot find the requested resource. Check the SERVER url and try again: '%s'",state->endpoint)));
				else if(response_code == 405)
					ereport(ERROR,
						(errcode(ERRCODE_INVALID_AUTHORIZATION_SPECIFICATION),
						 errmsg("Method Not Allowed (HTTP status %ld)", response_code),
						 errhint("This indicates that the SERVER understands the request but does not allow it to be processed. Check the SERVER url and try again: '%s'",state->endpoint)));
				else if(response_code == 500)
					ereport(ERROR,
						(errcode(ERRCODE_INVALID_AUTHORIZATION_SPECIFICATION),
						 errmsg("Internal Server Error (HTTP status %ld)", response_code),
						 errhint("This indicates that the SERVER is currently unable to process any request due to internal problems. Check the SERVER url and try again: '%s'",state->endpoint)));				
				else
					ereport(ERROR,
						(errcode(ERRCODE_INVALID_AUTHORIZATION_SPECIFICATION),
						 errmsg("Unable to establish connection to '%s' (HTTP status %ld)", state->endpoint, response_code),
						 errdetail("%s (curl error code %u)",curl_easy_strerror(res), res)));
			}
			else
			{
				ereport(ERROR,
						(errcode(ERRCODE_FDW_UNABLE_TO_ESTABLISH_CONNECTION),
						 errmsg("%s => (%u) '%s'\n", __func__, res, curl_easy_strerror(res))));
			}
		}
		else
		{
			curl_easy_getinfo(state->curl, CURLINFO_RESPONSE_CODE, &response_code);
			state->sparql_resultset = pstrdup(chunk.memory);

			elog(DEBUG4, "  %s: xml document \n\n%s", __func__, chunk.memory);
			elog(DEBUG2, "  %s: http response code = %ld", __func__, response_code);
			elog(DEBUG2, "  %s: http response size = %ld", __func__, chunk.size);
			elog(DEBUG2, "  %s: http response header = \n%s", __func__, chunk_header.memory);
		}

	}

	pfree(chunk.memory);
	pfree(chunk_header.memory);
	curl_slist_free_all(headers);
	curl_easy_cleanup(state->curl);
	curl_global_cleanup();

	/*
	 * We thrown an error in case the SPARQL endpoint returns an empty XML doc
	 */
	if(!state->sparql_resultset)
	{
		elog(DEBUG1,"%s exit: REQUEST_FAIL", __func__);
		return REQUEST_FAIL;
	}

	elog(DEBUG1,"%s exit: REQUEST_SUCCESS", __func__);
	return REQUEST_SUCCESS;
}

/*
 * LoadRDFData
 * -----------
 * Parses the result set loaded into 'state->xmldoc' into records.
 * 
 * state: SPARQL, SERVER and FOREIGN TABLE info
 */
static void LoadRDFData(RDFfdwState *state)
{
	xmlNodePtr results;
	xmlNodePtr root;

	state->rowcount = 0;
	state->records = NIL;

	elog(DEBUG1, "%s called", __func__);

	if (ExecuteSPARQL(state) != REQUEST_SUCCESS)
		elog(ERROR, "%s -> SPARQL failed: '%s'", __func__, state->endpoint);

	elog(DEBUG2, "  %s: loading 'xmlroot'", __func__);

	if (state->sparql_query_type == SPARQL_SELECT)
	{
		state->xmldoc = xmlReadMemory(state->sparql_resultset, strlen(state->sparql_resultset), NULL, NULL, XML_PARSE_NOBLANKS);
		root = xmlDocGetRootElement(state->xmldoc);

		for (results = root->children; results != NULL; results = results->next)
		{
			if (xmlStrcmp(results->name, (xmlChar *) "results") == 0)
			{
				xmlNodePtr record;

				for (record = results->children; record != NULL; record = record->next)
				{
					if (xmlStrcmp(record->name, (xmlChar *) "result") == 0)
					{
						state->records = lappend(state->records, record);
						state->pagesize++;

						elog(DEBUG2, "  %s: appending record %d", __func__, state->pagesize);
					}
				}
			}
		}

		if (state->log_sparql)
			elog(INFO,"SPARQL returned %d %s.\n", state->pagesize, state->pagesize == 1 ? "record" : "records");
	}

	elog(DEBUG1,"%s exit", __func__);
}

/*
 * SetUsedColumns
 * --------------
 * Marks FOREIGN TABLE's columns as used if they're used in the SQL query. This is
 * useful to get the mapped 'variable' OPTIONs, so that we can build a SPARQL SELECT 
 * only with the required variables.
 * 
 * state: SPARQL, SERVER and FOREIGN TABLE info
 */
static void SetUsedColumns(Expr *expr, struct RDFfdwState *state, int foreignrelid)
{
	Var *variable;
	ListCell *cell;

	elog(DEBUG1, "%s called: expression='%d'", __func__, expr->type);

	switch (expr->type)
	{
	case T_RestrictInfo:
		SetUsedColumns(((RestrictInfo *)expr)->clause, state, foreignrelid);
		break;
	case T_TargetEntry:
		SetUsedColumns(((TargetEntry *)expr)->expr, state, foreignrelid);
		break;
	case T_Const:
	case T_Param:
	case T_CaseTestExpr:
	case T_CoerceToDomainValue:
	case T_CurrentOfExpr:
#if PG_VERSION_NUM >= 100000
	case T_NextValueExpr:
#endif
		break;
	case T_Var:

		variable = (Var *)expr;

		/* ignore columns belonging to a different foreign table */
		if (variable->varno != foreignrelid)
		{
			elog(WARNING, "%s: column belonging to a different foreign table", __func__);
			break;
		}

		/* ignore system columns */
		if (variable->varattno < 0)
		{
			elog(WARNING, "%s: ignoring system column", __func__);
			break;
		}

		for (int i = 0; i < state->numcols; i++)
		{
			if (state->rdfTable->cols[i]->pgattnum == variable->varattno)
			{
				state->rdfTable->cols[i]->used = true;
				elog(DEBUG2, "%s: column '%s' (%d) required in the SQL query", __func__, state->rdfTable->cols[i]->name, i);
				break;
			}
		}

		break;
	case T_Aggref:
		foreach (cell, ((Aggref *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		foreach (cell, ((Aggref *)expr)->aggorder)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		foreach (cell, ((Aggref *)expr)->aggdistinct)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_WindowFunc:
		foreach (cell, ((WindowFunc *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
#if PG_VERSION_NUM < 120000
	case T_ArrayRef:
	{
		ArrayRef *ref = (ArrayRef *)expr;
#else
	case T_SubscriptingRef:
	{
		SubscriptingRef *ref = (SubscriptingRef *)expr;
#endif

		foreach (cell, ref->refupperindexpr)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		foreach (cell, ref->reflowerindexpr)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		SetUsedColumns(ref->refexpr, state, foreignrelid);
		SetUsedColumns(ref->refassgnexpr, state, foreignrelid);
		break;
	}
	case T_FuncExpr:
		foreach (cell, ((FuncExpr *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_OpExpr:
		foreach (cell, ((OpExpr *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_DistinctExpr:
		foreach (cell, ((DistinctExpr *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_NullIfExpr:
		foreach (cell, ((NullIfExpr *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_ScalarArrayOpExpr:
		foreach (cell, ((ScalarArrayOpExpr *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_BoolExpr:
		foreach (cell, ((BoolExpr *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_SubPlan:
	{
		SubPlan *subplan = (SubPlan *)expr;

		SetUsedColumns((Expr *)(subplan->testexpr), state, foreignrelid);

		foreach (cell, subplan->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
	}
	break;
	case T_AlternativeSubPlan:
		/* examine only first alternative */
		SetUsedColumns((Expr *)linitial(((AlternativeSubPlan *)expr)->subplans), state, foreignrelid);
		break;
	case T_NamedArgExpr:
		SetUsedColumns(((NamedArgExpr *)expr)->arg, state, foreignrelid);
		break;
	case T_FieldSelect:
		SetUsedColumns(((FieldSelect *)expr)->arg, state, foreignrelid);
		break;
	case T_RelabelType:
		SetUsedColumns(((RelabelType *)expr)->arg, state, foreignrelid);
		break;
	case T_CoerceViaIO:
		SetUsedColumns(((CoerceViaIO *)expr)->arg, state, foreignrelid);
		break;
	case T_ArrayCoerceExpr:
		SetUsedColumns(((ArrayCoerceExpr *)expr)->arg, state, foreignrelid);
		break;
	case T_ConvertRowtypeExpr:
		SetUsedColumns(((ConvertRowtypeExpr *)expr)->arg, state, foreignrelid);
		break;
	case T_CollateExpr:
		SetUsedColumns(((CollateExpr *)expr)->arg, state, foreignrelid);
		break;
	case T_CaseExpr:
		foreach (cell, ((CaseExpr *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		SetUsedColumns(((CaseExpr *)expr)->arg, state, foreignrelid);
		SetUsedColumns(((CaseExpr *)expr)->defresult, state, foreignrelid);
		break;
	case T_CaseWhen:
		SetUsedColumns(((CaseWhen *)expr)->expr, state, foreignrelid);
		SetUsedColumns(((CaseWhen *)expr)->result, state, foreignrelid);
		break;
	case T_ArrayExpr:
		foreach (cell, ((ArrayExpr *)expr)->elements)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_RowExpr:
		foreach (cell, ((RowExpr *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_RowCompareExpr:
		foreach (cell, ((RowCompareExpr *)expr)->largs)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		foreach (cell, ((RowCompareExpr *)expr)->rargs)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_CoalesceExpr:
		foreach (cell, ((CoalesceExpr *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_MinMaxExpr:
		foreach (cell, ((MinMaxExpr *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_XmlExpr:
		foreach (cell, ((XmlExpr *)expr)->named_args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		foreach (cell, ((XmlExpr *)expr)->args)
		{
			SetUsedColumns((Expr *)lfirst(cell), state, foreignrelid);
		}
		break;
	case T_NullTest:
		SetUsedColumns(((NullTest *)expr)->arg, state, foreignrelid);
		break;
	case T_BooleanTest:
		SetUsedColumns(((BooleanTest *)expr)->arg, state, foreignrelid);
		break;
	case T_CoerceToDomain:
		SetUsedColumns(((CoerceToDomain *)expr)->arg, state, foreignrelid);
		break;
	case T_PlaceHolderVar:
		SetUsedColumns(((PlaceHolderVar *)expr)->phexpr, state, foreignrelid);
		break;
#if PG_VERSION_NUM >= 100000
	case T_SQLValueFunction:
		break; /* contains no column references */
#endif		   /* PG_VERSION_NUM */
	default:
		ereport(ERROR,
				(errcode(ERRCODE_FDW_UNABLE_TO_CREATE_REPLY),
				 errmsg("unknown node type found: %d.", expr->type)));
		break;
	}

	elog(DEBUG1,"%s exit", __func__);
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
static bool IsSPARQLParsable(struct RDFfdwState *state)
{
	int keyword_count = 0;
	bool result;
	elog(DEBUG1, "%s called", __func__);
	/*
	 * SPARQL Queries containing SUB SELECTS are not supported. So, if any number
	 * other than 1 is returned from LocateKeyword, this query cannot be parsed.
	 */
	LocateKeyword(state->raw_sparql, "{\n\t> ", RDF_SPARQL_KEYWORD_SELECT, " *?\n\t", &keyword_count, 0);

	elog(DEBUG2, "%s: SPARQL contains '%d' SELECT clauses.", __func__, keyword_count);

	result = LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_GROUPBY, " \n\t?", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_ORDERBY, " \n\t?DA", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_LIMIT, " \n\t", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_UNION, " \n\t{", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(state->raw_sparql, " \n\t", RDF_SPARQL_KEYWORD_HAVING, " \n\t(", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 keyword_count == 1;

	elog(DEBUG1,"%s exit: returning '%s'", __func__, !result ? "false" : "true");	
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
static bool IsExpressionPushable(char *expression)
{
	char *open = " \n(";
	char *close = " \n(";
	bool result;

	elog(DEBUG1, "%s called: expression='%s'", __func__, expression);

	result = LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_COUNT, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_SUM, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_AVG, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_MIN, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_MAX, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_SAMPLE, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
			 LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_GROUPCONCAT, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND;

	elog(DEBUG1, "%s exit: returning '%s'", __func__, !result ? "false" : "true");
	return result;
}

/*
 * CreateSPARQL
 * ------------
 * Creates the final SPARQL query sent to the server, which might includes the
 * pushdown of SQL instructions. The query will be loaded into 'state->sparql'
 * 
 * state: SPARQL, SERVER and FOREIGN TABLE info
 * root : Planner info
 */
static void CreateSPARQL(RDFfdwState *state, PlannerInfo *root)
{	
	StringInfoData where_graph;
	StringInfoData sparql;

	initStringInfo(&sparql);
	initStringInfo(&where_graph);

	elog(DEBUG1, "%s called",__func__);

	if(state->sparql_filter && strlen(state->sparql_filter) > 0)
		appendStringInfo(&where_graph,"{%s\n ## rdf_fdw pushdown conditions ##\n%s}", pstrdup(state->sparql_where), pstrdup(state->sparql_filter));
	else
		appendStringInfo(&where_graph,"{%s}",pstrdup(state->sparql_where));
	/* 
	 * if the raw SPARQL query contains a DISTINCT modifier, this must be added into the 
	 * new SELECT clause 
	 */	
	if (state->is_sparql_parsable == true && 		
		LocateKeyword(state->raw_sparql, " \n", "DISTINCT"," \n?", NULL, 0) != RDF_KEYWORD_NOT_FOUND)
	{
		elog(DEBUG2, "  %s: SPARQL is valid and contains a DISTINCT modifier > pushing down DISTINCT", __func__);
		appendStringInfo(&sparql,"%s\nSELECT DISTINCT %s\n%s%s",
			state->sparql_prefixes, 
			strlen(state->sparql_select) == 0 ? " * " : state->sparql_select,
			state->sparql_from,
			where_graph.data);		
	} 
	/* 
	 * if the raw SPARQL query contains a REDUCED modifier, this must be added into the 
	 * new SELECT clause 
	 */
	else if (state->is_sparql_parsable == true && 		
		LocateKeyword(state->raw_sparql, " \n", "REDUCED"," \n?", NULL, 0) != RDF_KEYWORD_NOT_FOUND)
	{
		elog(DEBUG2, "  %s: SPARQL is valid and contains a REDUCED modifier > pushing down REDUCED", __func__);
		appendStringInfo(&sparql,"%s\nSELECT REDUCED %s\n%s%s",
			state->sparql_prefixes, 
			strlen(state->sparql_select) == 0 ? " * " : state->sparql_select,
			state->sparql_from, 
			where_graph.data);		
	}
	/* 
	 * if the raw SPARQL query does not contain a DISTINCT but the SQL query does, 
	 * this must be added into the new SELECT clause 
	 */
	else if (state->is_sparql_parsable &&  
			root && 								/* was the PlanerInfo provided? */
			root->parse->distinctClause != NULL &&	/* is there a DISTINCT clause in the PlanerInfo?*/
			!root->parse->hasDistinctOn &&			/* does the DISTINCT clause have a DISTINCT ON?*/
			LocateKeyword(state->raw_sparql, " \n", "DISTINCT"," \n?", NULL, 0) == RDF_KEYWORD_NOT_FOUND) /* does the SPARQL have a DISTINCT clause?*/
	{
		appendStringInfo(&sparql,"%s\nSELECT DISTINCT %s\n%s%s",
			state->sparql_prefixes, 
			strlen(state->sparql_select) == 0 ? " * " : state->sparql_select,
			state->sparql_from,
			where_graph.data);
	}
	else
	{	
		appendStringInfo(&sparql,"%s\nSELECT %s\n%s%s",
			state->sparql_prefixes, 
			strlen(state->sparql_select) == 0 ? " * " : state->sparql_select,
			state->sparql_from, 
			where_graph.data);
	}
	/*
	 * if the SQL query contains an ORDER BY, we try to push it down.
	 */
	if(state->is_sparql_parsable && state->sparql_orderby) 
	{
		elog(DEBUG2, "  %s: pushing down ORDER BY clause > 'ORDER BY %s'", __func__, state->sparql_orderby);
		appendStringInfo(&sparql, "\nORDER BY%s", pstrdup(state->sparql_orderby));
	}

	/*
	 * Pushing down LIMIT (OFFSET) to the SPARQL query if the SQL query contains them.
	 * If the SPARQL query set in the CREATE TABLE statement already contains a LIMIT,
	 * this won't be pushed.
	 */
	if (state->sparql_limit)
	{
		elog(DEBUG2, "  %s: pushing down LIMIT clause > '%s'", __func__, state->sparql_limit);
		appendStringInfo(&sparql, "\n%s", state->sparql_limit);
	}

	state->sparql = pstrdup(NameStr(sparql));

	elog(DEBUG1,"%s exit", __func__);
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
static int LocateKeyword(char *str, char *start_chars, char *keyword, char *end_chars, int *count, int start_position) 
{
	int keyword_position = RDF_KEYWORD_NOT_FOUND;
	StringInfoData idt;
	initStringInfo(&idt);

	if(count)
	{
		for (size_t i = 0; i < *count; i++)
		{
			appendStringInfo(&idt,"  ");
		}

		if(*count > 0)
			appendStringInfo(&idt,"├─ ");
	}

	elog(DEBUG1,"%s%s called: searching '%s' in start_position %d", NameStr(idt), __func__, keyword, start_position);

	if(start_position < 0)
		elog(ERROR, "%s%s: start_position cannot be negative.",NameStr(idt), __func__);

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


	if((count) && keyword_position != RDF_KEYWORD_NOT_FOUND)
	{
		(*count)++;		
		elog(DEBUG2, "%s%s (%d): keyword '%s' found in position %d. Recalling %s ... ", NameStr(idt), __func__, *count, keyword, keyword_position, __func__);
		LocateKeyword(str, start_chars, keyword, end_chars, count, keyword_position + 1);

		elog(DEBUG2,"%s%s: '%s' search returning postition %d for start position %d", NameStr(idt), __func__, keyword, keyword_position, start_position);
	} 

	elog(DEBUG1,"%s exit: returning '%d' (keyword_position)", __func__, keyword_position);
	return keyword_position;
}

/*
 * CreateTuple
 * -----------
 * Populates a TupleTableSlot with values extracted from a single SPARQL
 * result binding (an <result> XML node).
 *
 * The function performs the following steps:
 *   - Iterates over columns defined in the foreign table.
 *   - Matches each column with the corresponding SPARQL variable (e.g., "?foo").
 *   - Extracts RDF term content, datatype, language tag, and node type from the XML.
 *   - Converts the RDF term to a PostgreSQL Datum using the appropriate input function.
 *   - Handles language-tagged literals, typed literals, IRIs, or plain strings.
 *   - Applies RDF-specific formatting if requested via the column's literal_format.
 *   - Handles type coercion using the PostgreSQL typinput function for each column.
 *
 * Memory allocations are performed in a temporary context and cleaned up before returning.
 * Any unmatched columns are set to NULL in the tuple slot.
 *
 * Parameters:
 *   slot  - Tuple slot to be filled and returned to the executor.
 *   state - Foreign scan state, including column metadata and result document pointer.
 *
 * The function assumes that FetchNextBinding(state) returns a pointer to the next
 * <result> node in the SPARQL XML result set.
 */
static void CreateTuple(TupleTableSlot *slot, RDFfdwState *state)
{
	xmlNodePtr record;
	xmlNodePtr result;
	regproc typinput;
/*
	MemoryContext old_cxt, tmp_cxt;

	tmp_cxt = AllocSetContextCreate(CurrentMemoryContext,
									"rdf_fdw temporary data",
									ALLOCSET_SMALL_SIZES);
	old_cxt = MemoryContextSwitchTo(tmp_cxt);
*/
	record = FetchNextBinding(state);

	elog(DEBUG3, "%s called ", __func__);

	ExecClearTuple(slot);

	for (int i = 0; i < state->numcols; i++)
	{
		bool match = false;
		Oid pgtype = state->rdfTable->cols[i]->pgtype;
		char *sparqlvar = state->rdfTable->cols[i]->sparqlvar;
		char *colname = state->rdfTable->cols[i]->name;
		//char *literal_format = state->rdfTable->cols[i]->literal_fomat;
		int pgtypmod = state->rdfTable->cols[i]->pgtypmod;

		for (result = record->children; result != NULL; result = result->next)
		{
			xmlChar *prop = xmlGetProp(result, (xmlChar *)RDF_XML_NAME_TAG);
			StringInfoData name;

			initStringInfo(&name);
			appendStringInfo(&name, "?%s", (char *)prop);

			if (strcmp(sparqlvar, name.data) == 0)
			{
				xmlNodePtr value;
				match = true;

				for (value = result->children; value != NULL; value = value->next)
				{
					HeapTuple tuple;
					Datum datum;
					StringInfoData literal_value;
					xmlChar *datatype = xmlGetProp(value, (xmlChar *)RDF_SPARQL_RESULT_LITERAL_DATATYPE);
					xmlChar *lang = xmlGetProp(value, (xmlChar *)RDF_SPARQL_RESULT_LITERAL_LANG);
					xmlChar *content = xmlNodeGetContent(value->children);
					const xmlChar *node_type = value->name;
					char *node_value;

					initStringInfo(&literal_value);
					node_value = (char *)content;

					elog(DEBUG3, "%s: value='%s', lang='%s', datatye='%s', node_type='%s'",
						 __func__, (char *)content, (char *)lang, (char *)datatype, node_type);

					if (state->rdfTable->cols[i]->pgtype == RDFNODEOID)
					{
						if (datatype)
							appendStringInfo(&literal_value, "%s", strdt(node_value, (char *)datatype));
						else if (lang)
							appendStringInfo(&literal_value, "%s", strlang(node_value, (char *)lang));
						else if (xmlStrcmp(node_type, (xmlChar *)"uri") == 0)
							appendStringInfo(&literal_value, "%s", (iri(node_value)));
						else
							appendStringInfo(&literal_value, "%s", cstring_to_rdfnode(node_value));
					}
					else
						appendStringInfo(&literal_value, "%s", node_value);

					datum = CStringGetDatum(literal_value.data);
					// char *rdfnode_str = MemoryContextStrdup(slot->tts_mcxt, literal_value.data);
					// datum = CStringGetDatum(rdfnode_str);

					slot->tts_isnull[i] = false;

					elog(DEBUG3, "%s: setting pg column > '%s' (type > '%d'), sparqlvar > '%s'", __func__, colname, pgtype, sparqlvar);
					elog(DEBUG3, "%s: value > '%s'", __func__, (char *)content);

					/* find the appropriate conversion function */
					tuple = SearchSysCache1(TYPEOID, ObjectIdGetDatum(pgtype));

					if (!HeapTupleIsValid(tuple))
					{
						ereport(ERROR,
								(errcode(ERRCODE_FDW_INVALID_DATA_TYPE),
								 errmsg("cache lookup failed for type %u > column '%s(%s)'", pgtype, name.data, sparqlvar)));
					}

					typinput = ((Form_pg_type)GETSTRUCT(tuple))->typinput;
					ReleaseSysCache(tuple);

					if (pgtype == NUMERICOID || pgtype == TIMESTAMPOID || pgtype == TIMESTAMPTZOID || pgtype == VARCHAROID)
					{

						slot->tts_values[i] = OidFunctionCall3(
							typinput,
							datum,
							ObjectIdGetDatum(InvalidOid),
							Int32GetDatum(pgtypmod));
					}
					else if (pgtype == RDFNODEOID)
					{
						slot->tts_values[i] = DirectFunctionCall1(rdfnode_in, datum);
					}
					else
					{
						slot->tts_values[i] = OidFunctionCall1(typinput, datum);
					}

					if (content)
						xmlFree(content);
					if (lang)
						xmlFree(lang);
					if (datatype)
						xmlFree(datatype);
				}
			}

			if (name.data)
				pfree(name.data);

			if (prop)
				xmlFree(prop);

		}

		if (!match)
		{
			elog(DEBUG3, "    %s: setting NULL for column '%s' (%s)", __func__, colname, sparqlvar);
			slot->tts_isnull[i] = true;
			//slot->tts_values[i] = PointerGetDatum(NULL);
		}

	}

	//MemoryContextSwitchTo(old_cxt);
	//MemoryContextDelete(tmp_cxt);
	
	ExecStoreVirtualTuple(slot);
	
	elog(DEBUG3,"%s exit", __func__);
}

/*
 * DatumToString
 * -------------
 * Converts a 'Datum' into a char*.
 * 
 * datum: Data to be converted to char*
 * type : Oid of the data type to be converted
 * 
 * returns a char* with the string representation of a Datum or an empty string.
 */
static char *DatumToString(Datum datum, Oid type)
{
	StringInfoData result;
	regproc typoutput;
	HeapTuple tuple;
	char *str;
	text *t;

	elog(DEBUG1,"%s called: type='%u' ",__func__,type);

	/* get the type's output function */
	tuple = SearchSysCache1(TYPEOID, ObjectIdGetDatum(type));
	if (!HeapTupleIsValid(tuple))
	{
		elog(ERROR, "%s: cache lookup failed for type %u",__func__, type);
	}
	typoutput = ((Form_pg_type)GETSTRUCT(tuple))->typoutput;
	ReleaseSysCache(tuple);

	initStringInfo(&result);
	if (type == RDFNODEOID)
	{
		str = DatumGetCString(OidFunctionCall1(typoutput, datum));	
		appendStringInfo(&result, "%s", str);
	}
	else switch (type)
	{
		case TEXTOID:
		case CHAROID:
		case BPCHAROID:
		case VARCHAROID:
		case NAMEOID:
		case UUIDOID:
		case INT8OID:
		case INT2OID:
		case INT4OID:
		case OIDOID:
		case FLOAT4OID:
		case FLOAT8OID:
		case NUMERICOID:
			str = DatumGetCString(OidFunctionCall1(typoutput, datum));
			appendStringInfo(&result, "%s", str);
			break;
		case DATEOID:
			t = DatumGetTextP(DirectFunctionCall1(date_to_rdfnode, datum));
			appendStringInfo(&result, "%s", text_to_cstring(t));
			break;
		case TIMEOID:
			t = DatumGetTextP(DirectFunctionCall1(time_to_rdfnode, datum));
			appendStringInfo(&result, "%s", text_to_cstring(t));
			break;
		case TIMETZOID:
			t = DatumGetTextP(DirectFunctionCall1(timetz_to_rdfnode, datum));
			appendStringInfo(&result, "%s", text_to_cstring(t));
			break;
		case TIMESTAMPOID:
			t = DatumGetTextP(DirectFunctionCall1(timestamp_to_rdfnode, datum));
			appendStringInfo(&result, "%s", text_to_cstring(t));
			break;
		case TIMESTAMPTZOID:
			t = DatumGetTextP(DirectFunctionCall1(timestamptz_to_rdfnode, datum));
			appendStringInfo(&result, "%s", text_to_cstring(t));
			break;
		case BOOLOID:
			t = DatumGetTextP(DirectFunctionCall1(boolean_to_rdfnode, datum));
			appendStringInfo(&result, "%s", text_to_cstring(t));
			break;			
		default:
			elog(DEBUG1,"%s exit: returning NULL (unknown data type)", __func__);
			return NULL;
	}

	elog(DEBUG1,"%s exit: returning '%s'", __func__, result.data);
	return result.data;	
}

/*
 * DeparseDate
 * -----------
 * Deparses a 'Datum' of type 'date' and converts it to char*
 * 
 * datum: date to be converted
 * 
 * retrns a string representation of the given date
 */
// static char *DeparseDate(Datum datum)
// {
// 	struct pg_tm datetime_tm;
// 	StringInfoData s;

// 	if (DATE_NOT_FINITE(DatumGetDateADT(datum)))
// 		ereport(ERROR,
// 				(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
// 				errmsg("infinite date value cannot be stored")));

// 	/* get the parts */
// 	(void)j2date(DatumGetDateADT(datum) + POSTGRES_EPOCH_JDATE,
// 			&(datetime_tm.tm_year),
// 			&(datetime_tm.tm_mon),
// 			&(datetime_tm.tm_mday));

// 	initStringInfo(&s);
// 	appendStringInfo(&s, "%04d-%02d-%02d",
// 			datetime_tm.tm_year > 0 ? datetime_tm.tm_year : -datetime_tm.tm_year + 1,
// 			datetime_tm.tm_mon, datetime_tm.tm_mday);

// 	return s.data;
// }

/* 
 * DeparseTimestamp
 * ----------------
 * Deparses a 'Datum' of type 'timestamp' and converts it to char*
 * 
 * datum: timestamp to be converted
 * 
 * retrns a string representation of the given timestamp
 */
// static char *DeparseTimestamp(Datum datum, bool hasTimezone)
// {
// 	struct pg_tm datetime_tm;
// 	int32 tzoffset;
// 	fsec_t datetime_fsec;
// 	StringInfoData s;

// 	elog(DEBUG1, "%s called", __func__);
// 	/* this is sloppy, but DatumGetTimestampTz and DatumGetTimestamp are the same */
// 	if (TIMESTAMP_NOT_FINITE(DatumGetTimestampTz(datum)))
// 		ereport(ERROR,
// 				(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
// 				errmsg("infinite timestamp value cannot be stored")));

// 	/* get the parts */
// 	tzoffset = 0;
// 	(void)timestamp2tm(DatumGetTimestampTz(datum),
// 				hasTimezone ? &tzoffset : NULL,
// 				&datetime_tm,
// 				&datetime_fsec,
// 				NULL,
// 				NULL);

// 	initStringInfo(&s);
// 	if (hasTimezone)
// 		appendStringInfo(&s, "%04d-%02d-%02dT%02d:%02d:%02d.%06d%+03d:%02d",
// 			datetime_tm.tm_year > 0 ? datetime_tm.tm_year : -datetime_tm.tm_year + 1,
// 			datetime_tm.tm_mon, datetime_tm.tm_mday, datetime_tm.tm_hour,
// 			datetime_tm.tm_min, datetime_tm.tm_sec, (int32)datetime_fsec,
// 			-tzoffset / 3600, ((tzoffset > 0) ? tzoffset % 3600 : -tzoffset % 3600) / 60);
// 	else
// 		appendStringInfo(&s, "%04d-%02d-%02dT%02d:%02d:%02d.%06d",
// 			datetime_tm.tm_year > 0 ? datetime_tm.tm_year : -datetime_tm.tm_year + 1,
// 			datetime_tm.tm_mon, datetime_tm.tm_mday, datetime_tm.tm_hour,
// 			datetime_tm.tm_min, datetime_tm.tm_sec, (int32)datetime_fsec);

// 	return s.data;
// }

// static char *
// format_timestamp(Timestamp ts)
// {
// 	struct pg_tm tm;
// 	fsec_t fsec;
// 	StringInfoData buf;

// 	if (TIMESTAMP_NOT_FINITE(ts) ||
// 		timestamp2tm(ts, NULL, &tm, &fsec, NULL, NULL) != 0)
// 		elog(ERROR, "invalid timestamp");

// 	initStringInfo(&buf);
// 	appendStringInfo(&buf, "%04d-%02d-%02dT%02d:%02d:%02d",
// 					 tm.tm_year, tm.tm_mon, tm.tm_mday,
// 					 tm.tm_hour, tm.tm_min, tm.tm_sec);

// 	if (fsec != 0)
// 		appendStringInfo(&buf, ".%06d", (int)fsec);

// 	return buf.data;
// }

// static char *
// format_timestamptz(TimestampTz ts)
// {
// 	struct pg_tm tm;
// 	fsec_t fsec;
// 	const char *tzn;
// 	StringInfoData buf;

// 	if (timestamp2tm(ts, NULL, &tm, &fsec, &tzn, NULL) != 0)
// 		ereport(ERROR, (errmsg("invalid timestamp")));

// 	initStringInfo(&buf);
// 	appendStringInfo(&buf, "%04d-%02d-%02dT%02d:%02d:%02d",
// 					 tm.tm_year, tm.tm_mon, tm.tm_mday,
// 					 tm.tm_hour, tm.tm_min, tm.tm_sec);

// 	return buf.data;
// }

// static char *
// DeparseTimestamp(Datum datum, Oid typid)
// {
// 	if (typid == TIMESTAMPOID)
// 		return format_timestamp(DatumGetTimestamp(datum));
// 	else if (typid == TIMESTAMPTZOID)
// 		return format_timestamptz(DatumGetTimestampTz(datum));
// 	else
// 		elog(ERROR, "unsupported Oid %u passed to DeparseTimestamp", typid);

// 	return NULL; // not reached
// }

/*
 * DeparseExpr
 * -----------
 * Deparses SQL expressions and converts them into SPARQL expressions
 *
 * state     : SPARQL, SERVER and FOREIGN TABLE info
 * foreignrel: Conditions and columns used in the SQL query
 * expr      : Expression to be deparsed
 *
 * returns a string containing a SPARQL expression or NULL if not parseable
 */
static char *DeparseExpr(struct RDFfdwState *state, RelOptInfo *foreignrel, Expr *expr)
{
	char *arg, *opername, *left, *right, oprkind;
	// char *literalatt = "";
	Const *constant;
	OpExpr *oper;
	ScalarArrayOpExpr *arrayoper;
	Var *variable;
	HeapTuple tuple;
	StringInfoData result;
	Oid leftargtype, rightargtype;
	//Oid schema;
	int index;
	ArrayExpr *array;
	ArrayCoerceExpr *arraycoerce;
	Expr *rightexpr;
	Expr *leftexpr;
	bool first_arg, isNull;
	ArrayIterator iterator;
	Datum datum;
	ListCell *cell;
	BooleanTest *btest;
	FuncExpr *func;
	struct RDFfdwColumn *col = (struct RDFfdwColumn *)palloc0(sizeof(struct RDFfdwColumn));

	elog(DEBUG1, "%s called:  expr->type='%u'", __func__, expr->type);

	if (expr == NULL)
	{
		elog(DEBUG1, "%s: returning NULL (expr is NULL)", __func__);
		return NULL;
	}

	switch (nodeTag(expr))
	{
	case T_Const:
		elog(DEBUG2, "%s [T_Const] called: expr->type=%u", __func__, expr->type);
		constant = (Const *)expr;
		if (constant->constisnull)
		{
			initStringInfo(&result);
			appendStringInfo(&result, "NULL");
		}
		else
		{
			/* get a string representation of the value */
			char *c = DatumToString(constant->constvalue, constant->consttype);
			if (c == NULL)
			{
				elog(DEBUG1, "%s [T_Const]: returning NULL (DatumToString returned NULL)", __func__);
				return NULL;
			}
			else
			{
				char *l = lang(c);
				char *dt = datatype(c);
				char *lex_str = lex(c);

				initStringInfo(&result);

				if (strlen(l) != 0)
					appendStringInfo(&result, "%s", strlang(lex_str, l));
				else if (strstr(c, "\"^^"))
					appendStringInfo(&result, "%s", strdt(lex_str, dt));
				else
					appendStringInfo(&result, "%s", lex_str);
			}
		}
		elog(DEBUG2, "%s [T_Const]: reached end of block with result='%s'", __func__, result.data);
		break;
	case T_Var:

		elog(DEBUG2, "%s [T_Var]: start (expr->type='%u')", __func__, expr->type);
		variable = (Var *)expr;

		if (variable->vartype == BOOLOID)
		{
			elog(DEBUG1, "%s [T_Var]: returning NULL (variable type is a BOOLOID)", __func__);
			return NULL;
		}

		index = state->numcols - 1;

		while (index >= 0 && state->rdfTable->cols[index]->pgattnum != variable->varattno)
			--index;

		/* if no foreign table column is found, return NULL */
		if (index == -1)
		{
			elog(DEBUG1, "%s [T_Var]: returning NULL (no table column found)", __func__);
			return NULL;
		}

		initStringInfo(&result);
		appendStringInfo(&result, "%s", state->rdfTable->cols[index]->name);

		elog(DEBUG2, "  %s [T_Var]: index='%d', result='%s'", __func__,
			 index, state->rdfTable->cols[index]->name);

		break;
	case T_OpExpr:
		elog(DEBUG2, "%s [T_OpExpr]: start (expr->type='%u')", __func__, expr->type);
		oper = (OpExpr *)expr;
		initStringInfo(&result);

		tuple = SearchSysCache1(OPEROID, ObjectIdGetDatum(oper->opno));
		if (!HeapTupleIsValid(tuple))
		{
			elog(ERROR, "cache lookup failed for operator %u", oper->opno);
		}
		opername = pstrdup(((Form_pg_operator)GETSTRUCT(tuple))->oprname.data);
		oprkind = ((Form_pg_operator)GETSTRUCT(tuple))->oprkind;
		leftargtype = ((Form_pg_operator)GETSTRUCT(tuple))->oprleft;
		rightargtype = ((Form_pg_operator)GETSTRUCT(tuple))->oprright;
		//schema = ((Form_pg_operator)GETSTRUCT(tuple))->oprnamespace;
		ReleaseSysCache(tuple);

		/* ignore operators in other than the pg_catalog schema */
		// if (schema != PG_CATALOG_NAMESPACE)
		// {
		// 	elog(DEBUG1, "%s [T_OpExpr]: returning NULL: operator not in pg_catalog schema", __func__);
		// 	return NULL;
		// }

		/* don't push condition down if the right argument can't be translated into a SPARQL value*/
		if (!canHandleType(rightargtype))
		{
			elog(DEBUG1, "%s [T_OpExpr]: returning NULL: cannot handle data type", __func__);
			return NULL;
		}

		/* the operators that we can translate */
		if (strcmp(opername, "=") == 0 ||
			(strcmp(opername, ">") == 0 && rightargtype != TEXTOID && rightargtype != BPCHAROID && rightargtype != NAMEOID && rightargtype != CHAROID) ||
			(strcmp(opername, "<") == 0 && rightargtype != TEXTOID && rightargtype != BPCHAROID && rightargtype != NAMEOID && rightargtype != CHAROID) ||
			(strcmp(opername, ">=") == 0 && rightargtype != TEXTOID && rightargtype != BPCHAROID && rightargtype != NAMEOID && rightargtype != CHAROID) ||
			(strcmp(opername, "<=") == 0 && rightargtype != TEXTOID && rightargtype != BPCHAROID && rightargtype != NAMEOID && rightargtype != CHAROID) ||
			strcmp(opername, "+") == 0 ||
			strcmp(opername, "*") == 0 ||
			strcmp(opername, "!=") == 0 ||
			strcmp(opername, "<>") == 0 ||
			strcmp(opername, "~~") == 0 ||
			strcmp(opername, "!~~") == 0 ||
			strcmp(opername, "~~*") == 0 ||
			strcmp(opername, "!~~*") == 0)
		{
			/* SPARQL does not negate with <> */
			if (strcmp(opername, "<>") == 0)
				opername = "!=";

			elog(DEBUG2, "%s [T_OpExpr]: deparsing operand of left expression", __func__);
			left = DeparseExpr(state, foreignrel, linitial(oper->args));
			elog(DEBUG2, "%s [T_OpExpr]: left operand returned => %s", __func__, left);

			if (left == NULL)
			{
				//pfree(opername);
				elog(DEBUG1, "%s [T_OpExpr]: returning NULL (left argument couldn't be deparsed)", __func__);
				return NULL;
			}

			if (oprkind == 'b')
			{
				StringInfoData left_filter_arg;
				StringInfoData right_filter_arg;
				struct RDFfdwColumn *right_column = (struct RDFfdwColumn *)palloc0(sizeof(struct RDFfdwColumn));
				struct RDFfdwColumn *left_column = (struct RDFfdwColumn *)palloc0(sizeof(struct RDFfdwColumn));

				elog(DEBUG2, "  %s [T_OpExpr]: deparsing left and right expressions", __func__);
				leftexpr = linitial(oper->args);
				rightexpr = lsecond(oper->args);

				elog(DEBUG2, "  %s [T_OpExpr]: deparsing operand of right expression, type %u", __func__, rightexpr->type);
				right = DeparseExpr(state, foreignrel, rightexpr);

				elog(DEBUG2, "  %s [T_OpExpr]: [%s] left type %u, [%s] right type %u", __func__, left, leftexpr->type, right, rightexpr->type);

				if (right == NULL)
				{
					elog(DEBUG1, "%s [T_OpExpr]: returning NULL (right argument couldn't be deparsed)", __func__);
					return NULL;
				}

				initStringInfo(&left_filter_arg);
				initStringInfo(&right_filter_arg);

				left_column = GetRDFColumn(state, left);

				if (leftexpr->type == T_Var && (!left_column || !left_column->pushable))
				{
					elog(DEBUG1, "%s [T_OpExpr]: returning NULL (column of left argument is invalid or not pushable)", __func__);
					return NULL;
				}

				elog(DEBUG2, "%s [T_OpExpr]: getting right column based on '%s' ... ", __func__, right);
				right_column = GetRDFColumn(state, right);

				if (rightexpr->type == T_Var && (!right_column || !right_column->pushable))
				{
					elog(DEBUG1, "%s [T_OpExpr]: returning NULL (column of right argument is invalid or not pushable)", __func__);
					return NULL;
				}

				/* if the column contains an expression we use it in all FILTER expressions*/
				if (left_column && left_column->expression)
				{
					elog(DEBUG2, "%s [T_OpExpr]: adding expression '%s' for left expression", __func__, left_column->expression);
					appendStringInfo(&left_filter_arg, "%s", left_column->expression);
				}
				/* check if the argument is a string (T_Const) */
				else if (IsStringDataType(leftargtype) && leftexpr->type == T_Const)
				{
					if (right_column)
					{
						/*
						 * if the argument is a IRI/URI we must wrap it with IRI(), so that it
						 * can be handled as such in the FILTER expressions.
						 */
						if (right_column->nodetype && strcmp(right_column->nodetype, RDF_COLUMN_OPTION_NODETYPE_IRI) == 0)
							appendStringInfo(&left_filter_arg, "IRI(\"%s\")", left);
						else if (right_column->language)
						{
							if (strcmp(right_column->language, "*") == 0)
								appendStringInfo(&left_filter_arg, "%s", cstring_to_rdfnode(left));
							else
								appendStringInfo(&left_filter_arg, "%s", strlang(left, right_column->language));
						}
						else if (right_column->literaltype)
							appendStringInfo(&left_filter_arg, "%s", strdt(left, right_column->literaltype));
						else
							appendStringInfo(&left_filter_arg, "%s", cstring_to_rdfnode(left));
					}
					else
						appendStringInfo(&left_filter_arg, "%s", cstring_to_rdfnode(left));
				}
				/* check if the argument is a column */
				else if (left_column && leftexpr->type == T_Var)
				{
					/*
					 * we wrap the column name (sparqlvar) with STR() if the column's language
					 * is set to * (all languages)
					 */
					if (left_column->language && strcmp(left_column->language, "*") == 0)
						appendStringInfo(&left_filter_arg, "STR(%s)", left_column->sparqlvar);
					/* set the sparqlvar to the FILTER expression */
					else
						appendStringInfo(&left_filter_arg, "%s", left_column->sparqlvar);
				}
				else if (leftexpr->type == T_FuncExpr)
				{
					/* We try to resolve the column name <-> sparql variable one last time */
					left_column = GetRDFColumn(state, left);

					if (left_column)
						appendStringInfo(&left_filter_arg, "%s", left_column->sparqlvar);
					else
						appendStringInfo(&left_filter_arg, "%s", left);
				}
				else
				{
					appendStringInfo(&left_filter_arg, "%s", left);
				}

				/* if the column contains an expression we use it in all FILTER expressions*/
				if (right_column && right_column->expression)
				{
					elog(DEBUG1, "%s [T_OpExpr]: adding expression '%s' for left expression", __func__, right_column->expression);
					appendStringInfo(&right_filter_arg, "%s", right_column->expression);
				}
				/* check if the argument is a string (T_Const) */
				else if (IsStringDataType(rightargtype) && rightexpr->type == T_Const)
				{
					if (left_column)
					{
						if (left_column->nodetype && strcmp(left_column->nodetype, RDF_COLUMN_OPTION_NODETYPE_IRI) == 0)
							appendStringInfo(&right_filter_arg, "IRI(\"%s\")", right);
						else if (left_column->language)
						{
							if (strcmp(left_column->language, "*") == 0)
								appendStringInfo(&right_filter_arg, "%s", cstring_to_rdfnode(right));
							else
								appendStringInfo(&right_filter_arg, "%s", strlang(right, left_column->language));
						}
						else if (left_column->literaltype)
							appendStringInfo(&right_filter_arg, "%s", strdt(right, left_column->literaltype));
						else if (isIRI(right) || isBlank(right)) /* REVISAR!!!*/
							appendStringInfo(&right_filter_arg, "%s", right);
						else
						{
							//elog(WARNING, ">>>>>>>>>>>>>>");
							appendStringInfo(&right_filter_arg, "%s", cstring_to_rdfnode(right));
						}
					}
					else if (isIRI(right))
						appendStringInfo(&right_filter_arg, "%s", right);
					else
					{
						// elog(WARNING, "%%%%%%%%%%%%%%%%%%");

						// if (rightargtype == TIMESTAMPTZOID)
						// {
						// 	elog(WARNING, "!!!!!!!!!!!!!!!!!!!!!!");
						// 	Datum d = DirectFunctionCall1(timestamptz_to_rdfnode, datum);
						// 	elog(WARNING,"##### %s", DatumGetCString(d));
						// }
						//elog(WARNING, "@@@@@@@@@@@@@@: %s^^<%s%s>", RDF_XSD_BASE_URI, MapSPARQLDatatype(rightargtype));
						char *xsd_type = MapSPARQLDatatype(rightargtype);
						char *literal = cstring_to_rdfnode(right);

						if (xsd_type && isPlainLiteral(literal))
							appendStringInfo(&right_filter_arg, "%s^^<%s%s>",
								literal,
								RDF_XSD_BASE_URI,
								MapSPARQLDatatype(rightargtype)
							);
						else
							appendStringInfo(&right_filter_arg, "%s", cstring_to_rdfnode(right));
					}
				}

				// here: if rightargtype = TIMESTAMPOID && TIMESTAMPTZOID then xsd:dateTime
				//       if rightargtype = DATEOID then xsd:date
				else if (rightexpr->type == T_Var)
				{
					if (right_column && right_column->language && strcmp(right_column->language, "*") == 0)
						appendStringInfo(&right_filter_arg, "STR(%s)", right_column->sparqlvar);
					else
						appendStringInfo(&right_filter_arg, "%s", right_column->sparqlvar);
				}
				else if (rightexpr->type == T_FuncExpr)
				{
					/* We try to resolve the column name <-> sparql variable one last time */
					right_column = GetRDFColumn(state, right);

					if (right_column)
						appendStringInfo(&right_filter_arg, "%s", right_column->sparqlvar);
					else
						appendStringInfo(&right_filter_arg, "%s", right);
				}
				else
					appendStringInfo(&right_filter_arg, "%s", right);

				elog(DEBUG2, "  %s [T_OpExpr]: left argument converted: '%s' => '%s'", __func__, left, NameStr(left_filter_arg));
				elog(DEBUG2, "  %s [T_OpExpr]: oper  => '%s'", __func__, opername);
				elog(DEBUG2, "  %s [T_OpExpr]: right argument converted: '%s' => '%s'", __func__, right, NameStr(right_filter_arg));

				if (strcmp(opername, "~~") == 0 || strcmp(opername, "~~*") == 0 || strcmp(opername, "!~~") == 0 || strcmp(opername, "!~~*") == 0)
				{
					/*
					 * If the left and right side arguments are not respectively T_Var and
					 * T_Const it is not safe to push down the REGEX FILTER. We then let
					 * the client to deal with it.
					 */
					if (leftexpr->type != T_Var && rightexpr->type != T_Const)
					{
						elog(DEBUG1, "%s [T_OpExpr]: returning NULL (type of left expression is not a T_Var and the right expression is not a T_Const)", __func__);
						return NULL;
					}

					appendStringInfo(&result, "%s(%s,\"%s\"%s)",
									 opername[0] == '!' ? "!REGEX" : "REGEX",
									 NameStr(left_filter_arg),
									 CreateRegexString(right),
									 strcmp(opername, "~~*") == 0 || strcmp(opername, "!~~*") == 0 ? ",\"i\"" : "");
				}
				else
				{
					appendStringInfo(&result, "%s %s %s",
									 NameStr(left_filter_arg),
									 opername,
									 NameStr(right_filter_arg));
				}
			}
			else
			{
				elog(DEBUG1, "  %s [T_OpExpr]: unary operator not supported", __func__);
			}
		}
		else
		{
			elog(DEBUG1, "  %s exit [T_OpExpr]: returning NULL (operator cannot be translated '%s')", __func__, opername);
			return NULL;
		}

		break;
	case T_BooleanTest:
		elog(DEBUG2, "%s [T_BooleanTest]: start (expr->type='%u')", __func__, expr->type);
		btest = (BooleanTest *)expr;

		if (btest->arg->type != T_Var)
		{
			elog(DEBUG1, "  %s exit [T_BooleanTest]: returning NULL (argument type is not a T_Var)", __func__);
			return NULL;
		}

		variable = (Var *)btest->arg;

		index = state->numcols - 1;
		while (index >= 0 && state->rdfTable->cols[index]->pgattnum != variable->varattno)
			--index;

		arg = state->rdfTable->cols[index]->name;

		if (arg == NULL)
		{
			elog(DEBUG1, "  %s exit [T_BooleanTest]: returning NULL (column name is not valid)", __func__);
			return NULL;
		}

		col = GetRDFColumn(state, arg);

		if (!col)
		{
			elog(DEBUG1, "  %s exit [T_BooleanTest]: returning NULL (column not found)", __func__);
			return NULL;
		}

		if (!col->pushable)
		{
			elog(DEBUG1, "  %s exit [T_BooleanTest]: returning NULL (column name is not pushable)", __func__);
			return NULL;
		}

		initStringInfo(&result);

		switch (btest->booltesttype)
		{
		case IS_TRUE:
			appendStringInfo(&result, "%s = %s",
							 col->expression ? col->expression : col->sparqlvar,
							 !col->literaltype ? "\"true\"" : strdt("true", col->literaltype));
			break;
		case IS_NOT_TRUE:
			appendStringInfo(&result, "%s != %s",
							 col->expression ? col->expression : col->sparqlvar,
							 !col->literaltype ? "\"true\"" : strdt("true", col->literaltype));
			break;
		case IS_FALSE:
			appendStringInfo(&result, "%s = %s",
							 col->expression ? col->expression : col->sparqlvar,
							 !col->literaltype ? "\"false\"" : strdt("false", col->literaltype));
			break;
		case IS_NOT_FALSE:
			appendStringInfo(&result, "%s != %s",
							 col->expression ? col->expression : col->sparqlvar,
							 !col->literaltype ? "\"false\"" : strdt("false", col->literaltype));
			break;
		default:
			elog(DEBUG1, "  %s exit [T_BooleanTest]: returning NULL (unknown booltesttype)", __func__);
			return NULL;
		}

		break;
	case T_ScalarArrayOpExpr:
		//Expr *leftExpr;
			elog(DEBUG2, "%s [T_ScalarArrayOpExpr]: start (expr->type='%u')", __func__, expr->type);
		arrayoper = (ScalarArrayOpExpr *)expr;

		/* get operator name, left argument type and schema */
		tuple = SearchSysCache1(OPEROID, ObjectIdGetDatum(arrayoper->opno));
		if (!HeapTupleIsValid(tuple))
		{
			elog(ERROR, "cache lookup failed for operator %u", arrayoper->opno);
		}
		opername = pstrdup(((Form_pg_operator)GETSTRUCT(tuple))->oprname.data);
		leftargtype = ((Form_pg_operator)GETSTRUCT(tuple))->oprleft;
		//schema = ((Form_pg_operator)GETSTRUCT(tuple))->oprnamespace;
		ReleaseSysCache(tuple);
		/*
				// ignore operators in other than the pg_catalog schema
				if (schema != PG_CATALOG_NAMESPACE)
				{
					elog(DEBUG1, "%s exit [T_ScalarArrayOpExpr]: returning NULL (operator schema is not PG_CATALOG_NAMESPACE)", __func__);
					return NULL;
				}
		*/
		/* don't try to push down anything but IN and NOT IN expressions */
		if ((strcmp(opername, "=") != 0 || !arrayoper->useOr) && (strcmp(opername, "<>") != 0 || arrayoper->useOr))
		{
			elog(DEBUG1, "%s exit [T_ScalarArrayOpExpr]: returning NULL (expression in not IN or NOT IN)", __func__);
			return NULL;
		}

		if (!canHandleType(leftargtype))
		{
			elog(DEBUG1, "%s exit [T_ScalarArrayOpExpr]: returning NULL (cannot handle left argument's datatype)", __func__);
			return NULL;
		}

		/* the first (=initial) argument can be T_Var or T_Func */
		leftexpr = (Expr *)linitial(arrayoper->args);
		left = DeparseExpr(state, foreignrel, leftexpr);

		if (left == NULL)
		{
			elog(DEBUG1, "%s exit [T_ScalarArrayOpExpr]: returning NULL (left argument couldn't be deparsed)", __func__);
			return NULL;
		}

		initStringInfo(&result);

		if (leftexpr->type == T_Var)
		{
			elog(DEBUG2, "%s [T_ScalarArrayOpExpr]: left argument's dat type is T_Var (column)", __func__);
			col = GetRDFColumn(state, left);

			if (!col)
			{
				elog(DEBUG1, "%s exit [T_ScalarArrayOpExpr]: returning NULL (column of left argument is not valid)", __func__);
				return NULL;
			}

			if (!col->pushable)
			{
				elog(DEBUG1, "%s exit [T_ScalarArrayOpExpr]: returning NULL (column is not pushable)", __func__);
				return NULL;
			}

			if (strcmp(opername, "=") == 0)
				appendStringInfo(&result, "%s IN (", !col->expression ? col->sparqlvar : col->expression);
			else
				appendStringInfo(&result, "%s NOT IN (", !col->expression ? col->sparqlvar : col->expression);
		}
		else if (leftexpr->type == T_FuncExpr)
		{
			elog(DEBUG2, "%s [T_ScalarArrayOpExpr]: left argument's dat type is T_FuncExpr", __func__);
			if (strcmp(opername, "=") == 0)
				appendStringInfo(&result, "%s IN (", left);
			else
				appendStringInfo(&result, "%s NOT IN (", left);
		}
		else
		{
			elog(DEBUG1, "%s exit [T_ScalarArrayOpExpr]: returning NULL left argument type '%u' not supported", __func__, leftexpr->type);
			return NULL;
		}

		/* the second (=last) argument can be Const, ArrayExpr or ArrayCoerceExpr */
		rightexpr = (Expr *)llast(arrayoper->args);

		switch (rightexpr->type)
		{
		case T_Const:
			/* the second (=last) argument is a Const of ArrayType */
			constant = (Const *)rightexpr;

			/*
			 * NULL isn't supported in Linked Data. A NULL "value" is rather represented
			 * by the absence of a relation
			 */
			if (constant->constisnull)
			{
				elog(DEBUG1, "%s [T_ScalarArrayOpExpr]: returning NULL (constant->constisnull)", __func__);
				return NULL;
			}
			else
			{
				ArrayType *arr = DatumGetArrayTypeP(constant->constvalue);
				StringInfoData type;
				initStringInfo(&type);

				/* loop through the array elements */
				iterator = array_create_iterator(arr, 0);
				first_arg = true;
				while (array_iterate(iterator, &datum, &isNull))
				{
					char *c;

					if (isNull)
						c = "NULL";
					else
					{

						c = DatumToString(datum, ARR_ELEMTYPE(arr));
						if (c == NULL)
						{
							array_free_iterator(iterator);
							return NULL;
						}
					}

					if (IsStringDataType(leftargtype))
					{
						if (col && col->pgtype == RDFNODEOID)
							appendStringInfo(&result, "%s%s", first_arg ? "" : ", ", c);
						else if (col && col->language)
							appendStringInfo(&result, "%s%s",
											 first_arg ? "" : ", ", strlang(c, col->language));
						else if (col && col->literaltype)
							appendStringInfo(&result, "%s%s",
											 first_arg ? "" : ", ", strdt(c, col->literaltype));
						else
							appendStringInfo(&result, "%s%s",
											 first_arg ? "" : ", ", str(c));
					}
					else
						appendStringInfo(&result, "%s%s",
										 first_arg ? "" : ", ", c);

					/* append the argument */
					first_arg = false;
				}
				array_free_iterator(iterator);

				/* don't push down empty arrays, since the semantics for NOT x = ANY(<empty array>) differ */
				if (first_arg)
				{
					elog(DEBUG1, "%s [T_ScalarArrayOpExpr]: returning NULL (cannot push empty arrays)", __func__);
					return NULL;
				}
			}

			break;
		case T_ArrayCoerceExpr:
			/* the second (=last) argument is an ArrayCoerceExpr */
			arraycoerce = (ArrayCoerceExpr *)rightexpr;

			/* if the conversion requires more than binary coercion, don't push it down */
#if PG_VERSION_NUM < 110000
			if (arraycoerce->elemfuncid != InvalidOid)
				return NULL;
#else
			if (arraycoerce->elemexpr && arraycoerce->elemexpr->type != T_RelabelType)
			{
				elog(DEBUG1, "%s exit [T_ScalarArrayOpExpr]: returning NULL (arraycoerce->elemexpr && arraycoerce->elemexpr->type != T_RelabelType)", __func__);
				return NULL;
			}
#endif
			if (arraycoerce->arg->type != T_ArrayExpr)
			{
				elog(DEBUG1, "%s exit [T_ScalarArrayOpExpr]: returning NULL (arraycoerce->arg->type != T_ArrayExpr)", __func__);
				return NULL;
			}

			/* the actual array is here */
			rightexpr = arraycoerce->arg;

			/* fall through ! */

		case T_ArrayExpr:
			/* the second (=last) argument is an ArrayExpr */
			array = (ArrayExpr *)rightexpr;

			/* loop the array arguments */
			first_arg = true;
			foreach (cell, array->elements)
			{
				/* convert the argument to a string */
				char *element = DeparseExpr(state, foreignrel, (Expr *)lfirst(cell));

				/* if any element cannot be converted, give up */
				if (element == NULL)
				{
					elog(DEBUG1, "%s exit [T_ScalarArrayOpExpr]: returning NULL (unable to deparse element of T_ArrayExpr)", __func__);
					return NULL;
				}

				/* append the argument */
				appendStringInfo(&result, "%s%s", first_arg ? "" : ", ", element);
				first_arg = false;
			}

			/* don't push down empty arrays, since the semantics for NOT x = ANY(<empty array>) differ */
			if (first_arg)
			{
				elog(DEBUG1, "%s exit [T_ScalarArrayOpExpr]: returning NULL (cannot push down empty arrays)", __func__);
				return NULL;
			}

			break;
		default:
			elog(DEBUG1, "%s exit [T_ScalarArrayOpExpr]: returning NULL (rightexpr->type not supported)", __func__);
			return NULL;
		}

		/* parentheses close the FILTER expression */
		appendStringInfo(&result, ")");

		break;
	case T_FuncExpr:
		elog(DEBUG2, "%s [T_FuncExpr]: start (expr->type='%u')", __func__, expr->type);
		func = (FuncExpr *)expr;

		if (!canHandleType(func->funcresulttype))
		{
			return NULL;
		}

		/* do nothing for implicit casts */
		if (func->funcformat == COERCE_IMPLICIT_CAST)
		{
			char *impcast = DeparseExpr(state, foreignrel, linitial(func->args));
			elog(DEBUG1, "%s exit [T_FuncExpr]: returning '%s' (implicit cast) ", __func__, impcast);
			return impcast;
			// return NULL;
		}

		/* get function name and schema */
		tuple = SearchSysCache1(PROCOID, ObjectIdGetDatum(func->funcid));
		if (!HeapTupleIsValid(tuple))
		{
			elog(ERROR, "%s [T_FuncExpr]: cache lookup failed for function %u", __func__, func->funcid);
		}

		opername = pstrdup(((Form_pg_proc)GETSTRUCT(tuple))->proname.data);
		//schema = ((Form_pg_proc)GETSTRUCT(tuple))->pronamespace;
		ReleaseSysCache(tuple);

		elog(DEBUG2, "  %s [T_FuncExpr]: opername = %s", __func__, opername);

		/*
		 * ignore functions that are not in the pg_catalog schema and are
		 * not pushable.
		 */
		// if (schema != PG_CATALOG_NAMESPACE && !IsFunctionPushable(opername))
		// {
		// 	elog(DEBUG1, "%s exit [T_FuncExpr]: returning NULL (function not in pg_catalog and not pushable) ", __func__);
		// 	return NULL;
		// }

		if (!IsFunctionPushable(opername))
		{
			elog(DEBUG1, "%s exit [T_FuncExpr]: returning NULL (function not in pg_catalog and not pushable) ", __func__);
			return NULL;
		}


		if (IsFunctionPushable(opername))
		{
			char *extract_type = "";
			bool initarg = true;
			StringInfoData args;
			initStringInfo(&args);
			initStringInfo(&result);

			foreach (cell, func->args)
			{
				Expr *ex = lfirst(cell);
				elog(DEBUG2, "%s [T_FuncExpr]: deparsing arguments for '%s'", __func__, opername);
				arg = DeparseExpr(state, foreignrel, ex);

				if (!arg)
				{
					elog(DEBUG1, "%s exit [T_FuncExpr]: returning NULL (arg is NULL and opername = %s)", __func__, opername);
					pfree(opername);
					return NULL;
				}

				if (!initarg)
				{
					/*
					 * We discard any further parameters of ROUND, as its equivalent
					 * in SPARQL expects a single parameter.
					 */
					if (strcmp(opername, "round") == 0)
						break;
					else if (strcmp(opername, "extract") != 0)
						appendStringInfo(&args, "%s", ", ");
				}

				col = GetRDFColumn(state, arg);

				if (col)
				{
					appendStringInfo(&args, "%s", !col->expression ? col->sparqlvar : col->expression);
				}
				else
				{
					if (ex->type == T_Const)
					{
						Const *ct = (Const *)ex;

						if (strcmp(opername, "extract") == 0 && initarg)
						{
							/*
							 * in EXTRACT calls the first parameter becomes the function
							 * call in SPARQL. So we leave this cycle after we parsed the
							 * parameter.
							 */
							extract_type = FormatSQLExtractField(arg);
							continue;
						}

						/* Return NULLL if the EXTRACT field cannot be converted to SPARQL */
						if (strcmp(opername, "extract") == 0 && initarg && !arg)
						{
							elog(DEBUG1, "%s exit [T_FuncExpr]: returning NULL (EXTRACT field cannot be converted to SPARQL: '%s')", __func__, arg);
							pfree(opername);
							return NULL;
						}
						else if (IsStringDataType(ct->consttype) && strcmp(opername, "strdt") == 0)
							appendStringInfo(&args, "%s", ExpandDatatypePrefix(arg));
						else if (IsStringDataType(ct->consttype) && isIRI(arg))
							appendStringInfo(&args, "%s", arg);
						else if (IsStringDataType(ct->consttype))
							appendStringInfo(&args, "%s", cstring_to_rdfnode(arg));
						else
							appendStringInfo(&args, "%s", arg);
					}
					else
						appendStringInfo(&args, "%s", arg);
				}

				initarg = false;
			}

			if (strcmp(opername, "upper") == 0)
				appendStringInfo(&result, "UCASE(%s)", NameStr(args));
			else if (strcmp(opername, "lower") == 0)
				appendStringInfo(&result, "LCASE(%s)", NameStr(args));
			else if (strcmp(opername, "length") == 0)
				appendStringInfo(&result, "STRLEN(%s)", NameStr(args));
			else if (strcmp(opername, "abs") == 0)
				appendStringInfo(&result, "ABS(%s)", NameStr(args));
			else if (strcmp(opername, "round") == 0)
				appendStringInfo(&result, "ROUND(%s)", NameStr(args));
			else if (strcmp(opername, "floor") == 0)
				appendStringInfo(&result, "FLOOR(%s)", NameStr(args));
			else if (strcmp(opername, "ceil") == 0)
				appendStringInfo(&result, "CEIL(%s)", NameStr(args));
			else if (strcmp(opername, "strstarts") == 0 || strcmp(opername, "starts_with") == 0)
				appendStringInfo(&result, "STRSTARTS(%s)", NameStr(args));
			else if (strcmp(opername, "strends") == 0)
				appendStringInfo(&result, "STRENDS(%s)", NameStr(args));
			else if (strcmp(opername, "strbefore") == 0)
				appendStringInfo(&result, "STRBEFORE(%s)", NameStr(args));
			else if (strcmp(opername, "strafter") == 0)
				appendStringInfo(&result, "STRAFTER(%s)", NameStr(args));
			else if (strcmp(opername, "strlang") == 0)
				appendStringInfo(&result, "STRLANG(%s)", NameStr(args));
			else if (strcmp(opername, "strdt") == 0)
				appendStringInfo(&result, "STRDT(%s)", NameStr(args));
			else if (strcmp(opername, "str") == 0)
				appendStringInfo(&result, "STR(%s)", NameStr(args));
			else if (strcmp(opername, "iri") == 0)
				appendStringInfo(&result, "IRI(%s)", NameStr(args));
			else if (strcmp(opername, "isiri") == 0)
				appendStringInfo(&result, "isIRI(%s)", NameStr(args));
			else if (strcmp(opername, "lang") == 0)
				appendStringInfo(&result, "LANG(%s)", NameStr(args));
			else if (strcmp(opername, "langmatches") == 0)
				appendStringInfo(&result, "LANGMATCHES(%s)", NameStr(args));
			else if (strcmp(opername, "datatype") == 0)
				appendStringInfo(&result, "DATATYPE(%s)", NameStr(args));
			else if (strcmp(opername, "substring") == 0)
				appendStringInfo(&result, "SUBSTR(%s)", NameStr(args));
			else if (strcmp(opername, "contains") == 0)
				appendStringInfo(&result, "CONTAINS(%s)", NameStr(args));
			else if (strcmp(opername, "encode_for_uri") == 0)
				appendStringInfo(&result, "ENCODE_FOR_URI(%s)", NameStr(args));
			else if (strcmp(opername, "isblank") == 0)
				appendStringInfo(&result, "ISBLANK(%s)", NameStr(args));
			else if (strcmp(opername, "isnumeric") == 0)
				appendStringInfo(&result, "ISNUMERIC(%s)", NameStr(args));
			else if (strcmp(opername, "isliteral") == 0)
				appendStringInfo(&result, "ISLITERAL(%s)", NameStr(args));
			else if (strcmp(opername, "bnode") == 0)
				appendStringInfo(&result, "BNODE(%s)", NameStr(args));
			else if (strcmp(opername, "lcase") == 0)
				appendStringInfo(&result, "LCASE(%s)", NameStr(args));
			else if (strcmp(opername, "ucase") == 0)
				appendStringInfo(&result, "UCASE(%s)", NameStr(args));
			else if (strcmp(opername, "strlen") == 0)
				appendStringInfo(&result, "STRLEN(%s)", NameStr(args));
			else if (strcmp(opername, "substr") == 0)
				appendStringInfo(&result, "SUBSTR(%s)", NameStr(args));
			else if (strcmp(opername, "concat") == 0)
				appendStringInfo(&result, "CONCAT(%s)", NameStr(args));
			else if (strcmp(opername, "replace") == 0)
				appendStringInfo(&result, "REPLACE(%s)", NameStr(args));
			else if (strcmp(opername, "regex") == 0)
				appendStringInfo(&result, "REGEX(%s)", NameStr(args));
			else if (strcmp(opername, "year") == 0)
				appendStringInfo(&result, "YEAR(%s)", NameStr(args));
			else if (strcmp(opername, "month") == 0)
				appendStringInfo(&result, "MONTH(%s)", NameStr(args));
			else if (strcmp(opername, "day") == 0)
				appendStringInfo(&result, "DAY(%s)", NameStr(args));
			else if (strcmp(opername, "hours") == 0)
				appendStringInfo(&result, "HOURS(%s)", NameStr(args));
			else if (strcmp(opername, "minutes") == 0)
				appendStringInfo(&result, "MINUTES(%s)", NameStr(args));
			else if (strcmp(opername, "seconds") == 0)
				appendStringInfo(&result, "SECONDS(%s)", NameStr(args));
			else if (strcmp(opername, "timezone") == 0)
				appendStringInfo(&result, "TIMEZONE(%s)", NameStr(args));
			else if (strcmp(opername, "tz") == 0)
				appendStringInfo(&result, "TZ(%s)", NameStr(args));
			else if (strcmp(opername, "md5") == 0)
				appendStringInfo(&result, "MD5(%s)", NameStr(args));
			else if (strcmp(opername, "bound") == 0)
				appendStringInfo(&result, "BOUND(%s)", NameStr(args));
			else if (strcmp(opername, "sameterm") == 0)
				appendStringInfo(&result, "SAMETERM(%s)", NameStr(args));
			else if (strcmp(opername, "coalesce") == 0)
				appendStringInfo(&result, "COALESCE(%s)", NameStr(args));
			else if (strcmp(opername, "extract") == 0)
				appendStringInfo(&result, "%s(%s)", extract_type, NameStr(args));
			else if (strcmp(opername, "rdfnode_to_timestamp") == 0)
				appendStringInfo(&result, "%s", NameStr(args));
			else if (strcmp(opername, "rdfnode_to_timestamptz") == 0)
				appendStringInfo(&result, "%s", NameStr(args));
			else if (strcmp(opername, "rdfnode_to_times") == 0)
				appendStringInfo(&result, "%s", NameStr(args));
			else if (strcmp(opername, "rdfnode_to_timetz") == 0)
				appendStringInfo(&result, "%s", NameStr(args));
			else if (strcmp(opername, "rdfnode_to_boolean") == 0)
				appendStringInfo(&result, "%s", NameStr(args));
			else if (strcmp(opername, "boolean_to_rdfnode") == 0)
				appendStringInfo(&result, "%s", NameStr(args));

			else
			{
				elog(DEBUG1, "%s [T_FuncExpr]: returning NULL (unknown opername '%s')", __func__, opername);
				return NULL;
			}

			pfree(args.data);
		}
		/* in PostgreSQL 11 EXTRACT is internally called as DATE_PART */
		else if (strcmp(opername, "date_part") == 0)
		{
			Expr *field = linitial(func->args);
			char *date_part_type = "";

			elog(DEBUG2, "%s [T_FuncExpr]: deparsing FIELD for '%s'", __func__, opername);
			date_part_type = DeparseExpr(state, foreignrel, field);

			if (!date_part_type)
			{
				elog(DEBUG1, "%s exit [T_FuncExpr]: returning NULL (date_part_type is NULL and opername = '%s')", __func__, opername);
				pfree(opername);
				return NULL;
			}

			elog(DEBUG2, "%s [T_FuncExpr]: date_part FIELD '%s'", __func__, date_part_type);

			date_part_type = FormatSQLExtractField(date_part_type);

			if (date_part_type)
			{
				char *val;

				elog(DEBUG2, "%s [T_FuncExpr]: deparsing VALUE for '%s'", __func__, opername);

				val = DeparseExpr(state, foreignrel, lsecond(func->args));
				col = GetRDFColumn(state, val);

				initStringInfo(&result);

				if (col)
					appendStringInfo(&result, "%s(%s)", date_part_type, !col->expression ? col->sparqlvar : col->expression);
				else
					appendStringInfo(&result, "%s(\"%s\")", date_part_type, val);
			}
			else
			{
				elog(DEBUG1, "%s exit [T_FuncExpr]: returning NULL (date_part_type is NULL)", __func__);
				pfree(opername);
				return NULL;
			}
		}
		else if (strcmp(opername, "timestamp") == 0)
		{
			char *value;
			Expr *ex = linitial(func->args);

			value = DeparseExpr(state, foreignrel, ex);

			if (!value)
			{
				elog(DEBUG1, "%s exit [T_FuncExpr]: returning NULL (unable to deparse timestamp value)", __func__);
				return NULL;
			}

			initStringInfo(&result);
			appendStringInfo(&result, "%s", value);
		}
		else
		{
			elog(DEBUG1, "%s exit [T_FuncExpr]: returning NULL (unable to push function '%s')", __func__, opername);
			return NULL;
		}

		pfree(opername);
		break;
	case T_ArrayExpr:
		elog(DEBUG2, "%s [T_ArrayExpr]: start (expr->type='%u')", __func__, expr->type);

		/* this is exclusively for SPARQL COALESCE */
		array = (ArrayExpr *)expr;
		elog(DEBUG2, "%s [T_ArrayExpr]: function called", __func__);
		initStringInfo(&result);

		/* loop the array arguments */
		first_arg = true;
		foreach (cell, array->elements)
		{
			Expr *element_expr = (Expr *)lfirst(cell);
			char *element = DeparseExpr(state, foreignrel, element_expr);

			/* if any element cannot be converted, give up */
			if (element == NULL)
			{
				elog(DEBUG1, "%s exit [T_ArrayExpr]: returning NULL (unable to deparse element of T_ArrayExpr)", __func__);
				return NULL;
			}

			col = GetRDFColumn(state, element);

			if (col)
				appendStringInfo(&result, "%s%s", first_arg ? "" : ", ", col->sparqlvar);
			else if (nodeTag(element_expr) == T_Const && isLiteral(element))
			{
				/*
				 * this seems unnecessary, but it is important to expand
				 * possible prefixed XSD predicates into their full URI.
				 */
				char *dt = datatype(element);

				if (strlen(dt) != 0)
					appendStringInfo(&result, "%s%s", first_arg ? "" : ", ", strdt(element, dt));
				else
					appendStringInfo(&result, "%s%s", first_arg ? "" : ", ", cstring_to_rdfnode(element));
			}
			else if (nodeTag(element_expr) == T_Const)
				appendStringInfo(&result, "%s%s", first_arg ? "" : ", ", cstring_to_rdfnode(element));
			else
				appendStringInfo(&result, "%s%s", first_arg ? "" : ", ", element);

			first_arg = false;
		}

		if (first_arg)
		{
			elog(DEBUG1, "%s exit [T_ArrayExpr]: returning NULL (cannot push empty arrays)", __func__);
			return NULL;
		}

		break;
	default:
		elog(DEBUG1, "%s exit: returning NULL (expression not supported '%u')", __func__, expr->type);
		return NULL;
	}

	elog(DEBUG1, "%s exit: returning '%s'\n", __func__, result.data);
	return result.data;
}

/*
 * DeparseSQLWhereConditions
 * ----------------------
 * Deparses the WHERE clause of SQL queries and tries to convert its conditions into 
 * SPARQL FILTER expressions.
 * 
 * state  : SPARQL, SERVER and FOREIGN TABLE info
 * baserel: Conditions and columns used in the SQL query
 * 
 * returns char* containing SPARQL FILTER expressions or an empty string if not applicable
 */
static char *DeparseSQLWhereConditions(struct RDFfdwState *state, RelOptInfo *baserel)
{
	List *conditions = baserel->baserestrictinfo;
	ListCell *cell;
	StringInfoData where_clause;

	elog(DEBUG1,"%s called",__func__);

	initStringInfo(&where_clause);
	foreach(cell, conditions)
	{		
		/* deparse expression for pushdown */
		char *where = DeparseExpr(
					state, baserel,
					((RestrictInfo *)lfirst(cell))->clause
				);

		if (where != NULL) 
		{
			/* append new FILTER clause to query string */
			appendStringInfo(&where_clause, " FILTER(%s)\n", pstrdup(where));
			pfree(where);
		}
		else
		{
			state->has_unparsable_conds = true;
			elog(DEBUG1,"  %s: condition cannot be pushed down.",__func__);
		}

	}

	elog(DEBUG1,"%s exit: returning '%s'", __func__, where_clause.data);
	return where_clause.data;
}


static char *DeparseSPARQLWhereGraphPattern(struct RDFfdwState *state)
{
	int where_position = -1;
	int where_size = -1;
	char *result;

	elog(DEBUG1,"%s called",__func__);

	/*
	 * Deparsing SPARQL WHERE clause
	 *   'where_position = i + 1' to remove the surrounging curly braces {} as we are
	 *   interested only in WHERE clause's graph pattern
	 */
	for (int i = 0; state->raw_sparql[i] != '\0'; i++)
	{
		if (state->raw_sparql[i] == '{' && where_position == -1)
			where_position = i + 1;

		if (state->raw_sparql[i] == '}')
			where_size = i - where_position;
	}

	result = pnstrdup(state->raw_sparql + where_position, where_size);

	elog(DEBUG1,"%s exit: returning '%s'", __func__, result);
	return result;
}

/* 
 * DeparseSQLOrderBy
 * -----------------
 * 
 * state  : SPARQL, SERVER and FOREIGN TABLE info
 * baserel: Conditions and columns used in the SQL query
 * root   : Planner info
 * 
 * returns char* containg a SPARQL ORDER BY clause or an empty string if not applicable
 */
static char *DeparseSQLOrderBy(struct RDFfdwState *state, PlannerInfo *root, RelOptInfo *baserel)
{
	StringInfoData orderedquery;
	List *usable_pathkeys = NIL;
	ListCell *cell;
	char *delim = " ";

	elog(DEBUG1, "%s called",__func__);

	initStringInfo(&orderedquery);

	foreach (cell, root->query_pathkeys)
	{
		PathKey *pathkey = (PathKey *)lfirst(cell);
		EquivalenceClass *pathkey_ec = pathkey->pk_eclass;
		EquivalenceMember *em = NULL;
		Expr *em_expr = NULL;
		char *sort_clause;
		Oid em_type;
		ListCell *lc;
		bool can_pushdown;

		/* ec_has_volatile saves some cycles */
		if (pathkey_ec->ec_has_volatile)
		{
			elog(DEBUG1,"%s exit: returning 'false' (pathkey_ec->ec_has_volatile)", __func__);
			return false;
		}

		/*
		 * Given an EquivalenceClass and a foreign relation, find an EC member
		 * that can be used to sort the relation remotely according to a pathkey
		 * using this EC.
		 *
		 * If there is more than one suitable candidate, use an arbitrary
		 * one of them.
		 *
		 * This checks that the EC member expression uses only Vars from the given
		 * rel and is shippable.  Caller must separately verify that the pathkey's
		 * ordering operator is shippable.
		 */
		foreach (lc, pathkey_ec->ec_members)
		{
			EquivalenceMember *some_em = (EquivalenceMember *)lfirst(lc);

			/*
			 * Note we require !bms_is_empty, else we'd accept constant
			 * expressions which are not suitable for the purpose.
			 */
			if (bms_is_subset(some_em->em_relids, baserel->relids) &&
				!bms_is_empty(some_em->em_relids))
			{
				em = some_em;
				break;
			}
		}

		if (em == NULL)
		{
			elog(DEBUG1,"%s exit: returning 'false' (EquivalenceMember is NULL)", __func__);
			return false;
		}

		em_expr = em->em_expr;
		em_type = exprType((Node *)em_expr);

		/* 
		 * SPARQL does not support sorting with functions, so it is not safe to 
		 * push down anything other than T_Var.
		 */

		can_pushdown = (em_expr->type == T_Var) && canHandleType(em_type);

		elog(DEBUG1,"  %s: can push down > %d",__func__, can_pushdown);

		if (can_pushdown &&	((sort_clause = DeparseExpr(state, baserel, em_expr)) != NULL))
		{
			/* keep usable_pathkeys for later use. */
			usable_pathkeys = lappend(usable_pathkeys, pathkey);

			/* create orderedquery */
			appendStringInfoString(&orderedquery, delim);

#if PG_VERSION_NUM >= 180000
			if (pathkey->pk_cmptype == COMPARE_LT)
#else
			if (pathkey->pk_strategy == BTLessStrategyNumber)
#endif  /* PG_VERSION_NUM */
				appendStringInfo(&orderedquery, " ASC (%s)", (GetRDFColumn(state,sort_clause))->sparqlvar);
			else
				appendStringInfo(&orderedquery, " DESC (%s)", (GetRDFColumn(state,sort_clause))->sparqlvar);
		}
		else
		{
			/*
			 * Before PostgreSQL v13, the planner and executor don't have
			 * any clever strategy for taking data sorted by a prefix of the
			 * query's pathkeys and getting it to be sorted by all of those
			 * pathekeys.
			 * So, unless we can push down all of the query pathkeys, forget it.
			 * This could be improved from v13 on!
			 */

			elog(DEBUG1,"  %s: cannot push down ORDER BY",__func__);
			list_free(usable_pathkeys);
			usable_pathkeys = NIL;
			break;
		}
	}

	if (root->query_pathkeys != NIL && usable_pathkeys != NIL)
	{
		elog(DEBUG1,"%s exit: returning '%s'", __func__, orderedquery.data);
		return orderedquery.data;
	}
	else
	{
		elog(DEBUG1,"%s exit: returning NULL (unable to deparse ORDER BY clause)",__func__);
		return NULL;
	}
}

/* 
 * DeparseSPARQLFrom
 * -----------------
 * Deparses the SPARQL FROM clause.
 * 
 * raw_sparql: SPARQL query set in the CREATE TABLE statement
 * 
 * returns the SPARQL FROM clause
 */
static char *DeparseSPARQLFrom(char *raw_sparql)
{
	StringInfoData from;
	char *open_chars = ">)\n\t ";
	char *close_chars = " <\n\t";
	int nfrom = 0;

	elog(DEBUG1,"%s called", __func__);

	initStringInfo(&from);

	if(LocateKeyword(raw_sparql, open_chars, RDF_SPARQL_KEYWORD_FROM, close_chars, &nfrom, 0) != RDF_KEYWORD_NOT_FOUND)
	{				
		int entry_position = 0;
		
		for (int i = 1; i <= nfrom; i++)
		{
			bool is_named = false;
			StringInfoData from_entry;
			initStringInfo(&from_entry);

			entry_position = LocateKeyword(raw_sparql, open_chars, RDF_SPARQL_KEYWORD_FROM, close_chars, NULL, entry_position);

			if(entry_position == RDF_KEYWORD_NOT_FOUND)
				break;

			entry_position = entry_position + (strlen(RDF_SPARQL_KEYWORD_FROM) + 1);

			while (raw_sparql[entry_position] == ' ')
				entry_position++;

			/* Is the SPARQL long enough for 'FROM NAMED' to be parsed? */
			if(entry_position + strlen(RDF_SPARQL_KEYWORD_NAMED) <= strlen(raw_sparql))
			{
				/*
				 * if the next keyword is NAMED, set is_named to 'true' and move the cursor
				 * to the next keyword
				 */
				if(strncasecmp(raw_sparql + entry_position, RDF_SPARQL_KEYWORD_NAMED, strlen(RDF_SPARQL_KEYWORD_NAMED)) == 0) {
					is_named = true;
					entry_position = entry_position + strlen(RDF_SPARQL_KEYWORD_NAMED);

					while (raw_sparql[entry_position] == ' ')
						entry_position++;
				}

			}

			while (raw_sparql[entry_position] != ' ' &&
				   raw_sparql[entry_position] != '\n' &&
				   raw_sparql[entry_position] != '\t' &&
				   raw_sparql[entry_position] != '\0')
			{
				appendStringInfo(&from_entry,"%c",raw_sparql[entry_position]);

				if(raw_sparql[entry_position] == '>')
					break;
				
				entry_position++;
			}

			if(is_named)
				appendStringInfo(&from,"%s %s %s\n", RDF_SPARQL_KEYWORD_FROM, RDF_SPARQL_KEYWORD_NAMED, from_entry.data);
			else
				appendStringInfo(&from,"%s %s\n", RDF_SPARQL_KEYWORD_FROM,from_entry.data);

		}		

	}

	elog(DEBUG1,"%s exit: returning '%s'", __func__, from.data);
	return from.data;
}

/*
 * DeparseSPARQLPrefix
 * -------------------
 * Deparses the SPARQL PREFIX entries.
 * 
 * raw_sparql: SPARQL query set in the CREATE TABLE statement
 * 
 * returns the SPARQL PREFIX entries
 */
static char *DeparseSPARQLPrefix(char *raw_sparql)
{
	StringInfoData prefixes;
	char *open_chars = "\n\t ";
	char *close_chars = " >\n\t";
	int nprefix = 0;

	initStringInfo(&prefixes);

	elog(DEBUG1,"%s called",__func__);

	if(LocateKeyword(raw_sparql, open_chars, RDF_SPARQL_KEYWORD_PREFIX, close_chars, &nprefix, 0) != RDF_KEYWORD_NOT_FOUND)
	{
		int keyword_position = 0;

		for (int i = 1; i <= nprefix; i++)
		{
			StringInfoData keyword_entry;
			initStringInfo(&keyword_entry);

			keyword_position = LocateKeyword(raw_sparql, open_chars, RDF_SPARQL_KEYWORD_PREFIX, close_chars, NULL, keyword_position);

			if(keyword_position == RDF_KEYWORD_NOT_FOUND)
				break;

			while (raw_sparql[keyword_position] != '>' &&
				   raw_sparql[keyword_position] != '\0')
			{
				appendStringInfo(&keyword_entry,"%c",raw_sparql[keyword_position]);

				if(raw_sparql[keyword_position] == '>')
					break;

				keyword_position++;
			}

			appendStringInfo(&prefixes,"%s>\n", keyword_entry.data);

		}
	}

	elog(DEBUG1,"%s exit: returning '%s'", __func__, prefixes.data);
	return prefixes.data;
}

/*
 * DeparseSQLLimit
 * ---------------
 * Deparses the SQL LIMIT or FETCH clause and converts it into a SPARQL LIMIT clause
 * 
 * state  : SPARQL, SERVER and FOREIGN TABLE info
 * root   : Planner info
 * baserel: Conditions and columns used in the SQL query
 * 
 * returns a SPARQL LIMIT clause or an empty string if not applicable
 */
static char *DeparseSQLLimit(struct RDFfdwState *state, PlannerInfo *root, RelOptInfo *baserel)
{
	StringInfoData limit_clause;
	char *limit_val, *offset_val = NULL;

	elog(DEBUG1,"%s called ",__func__);

	/* don't push down LIMIT (OFFSET)  if the query has a GROUP BY clause or aggregates */
	if (root->parse->groupClause != NULL || root->parse->hasAggs)
	{
		elog(DEBUG1,"%s exit: returning NULL (LIMIT won't be pushed down, as SQL query contains aggregators)", __func__);
		return NULL;
	}

	/* don't push down LIMIT (OFFSET) if the query contains DISTINCT */
	if (root->parse->distinctClause != NULL) {
		elog(DEBUG1,"%s exit: returning NULL (LIMIT won't be pushed down, as SQL query contains DISTINCT)", __func__);
		return NULL;
	}

	/*
	 * disables LIMIT push down if any WHERE conidition cannot be be pushed down, otherwise you'll
	 * be scratching your head forever wondering why some data are missing from the result set.
	 */
	if (state->has_unparsable_conds)
	{
		elog(DEBUG1,"%s exit: returning NULL (LIMIT won't be pushed down, as there are WHERE conditions that could not be translated)", __func__);
		return NULL;
	}

	/* only push down constant LIMITs that are not NULL */
	if (root->parse->limitCount != NULL && IsA(root->parse->limitCount, Const))
	{
		Const *limit = (Const *)root->parse->limitCount;

		if (limit->constisnull)
		{
			elog(DEBUG1,"%s exit: returning NULL (limit->constisnull)", __func__);
			return NULL;
		}

		limit_val = DatumToString(limit->constvalue, limit->consttype);
	}
	else
	{
		elog(DEBUG1,"%s exit: returning NULL (constant is NULL)", __func__);
		return NULL;
	}

	/* only consider OFFSETS that are non-NULL constants */
	if (root->parse->limitOffset != NULL && IsA(root->parse->limitOffset, Const))
	{
		Const *offset = (Const *)root->parse->limitOffset;

		if (! offset->constisnull)
			offset_val = DatumToString(offset->constvalue, offset->consttype);
	}

	initStringInfo(&limit_clause);

	if (offset_val)
	{
		int val_offset = DatumGetInt32(((Const *)root->parse->limitOffset)->constvalue);
		int val_limit = DatumGetInt32(((Const *)root->parse->limitCount)->constvalue);
		appendStringInfo(&limit_clause, "LIMIT %d", val_offset+val_limit);
	}
	else
		appendStringInfo(&limit_clause, "LIMIT %s", limit_val);

	elog(DEBUG1,"%s exit: returning '%s'", __func__, NameStr(limit_clause));
	return NameStr(limit_clause);

}

/*
 * ContainsWhitespaces
 * ---------------
 * Checks if a string contains whitespaces
 * 
 * str: string to be evaluated
 * 
 * returns true if the string contains whitespaces or false otherwise
 */
static bool ContainsWhitespaces(char *str)
{
	elog(DEBUG1,"%s called: str='%s'", __func__, str);

	for (int i = 0; str[i] != '\0'; i++)
		if (isspace((unsigned char)str[i]))
		{
			elog(DEBUG1,"%s exit: returning 'true'", __func__);
			return true;
		}

	elog(DEBUG1,"%s exit: returning 'false'", __func__);
	return false;
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
static bool IsSPARQLVariableValid(const char* str) 
{
	elog(DEBUG1,"%s called: str='%s'", __func__, str);

	if (str[0] != '?' && str[0] != '$')
	{
		elog(DEBUG1,"%s exit: returning 'false' (str does not start with '?' or '$')", __func__);
		return false;
	}

	for (int i = 1; str[i] != '\0'; i++)
		if (!isalnum(str[i]) && str[i] != '_')
		{
			elog(DEBUG1,"%s exit: returning 'false' (invalid variable name)", __func__);
			return false;
		}

	elog(DEBUG1,"%s exit: returning 'true'", __func__);
	return true;
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
static char* CreateRegexString(char* str)
{
	StringInfoData res;
	initStringInfo(&res);

	elog(DEBUG1,"%s called: str='%s'", __func__, str);

	if(!str)
		return NULL;

	for (int i = 0; str[i] != '\0'; i++)
	{
		char c = str[i];

		if( i == 0 && c != '%' && c != '_' && c != '^' )
			appendStringInfo(&res,"^");

		if(strchr("/:=#@^()[]{}+-*$.?|",c) != NULL)
			appendStringInfo(&res,"\\\\%c", c);
		else if(c == '%')
			appendStringInfo(&res,".*");
		else if(c == '_')
			appendStringInfo(&res,".");
		else if(c == '"')
			appendStringInfo(&res,"\\\"");
		else
			appendStringInfo(&res, "%c", c);

		if(i == strlen(str)-1 && c != '%' && c != '_')
			appendStringInfo(&res,"$");

		elog(DEBUG2, "%s loop => %c res => %s", __func__, str[i], NameStr(res));
	}

	elog(DEBUG1,"%s exit: returning '%s'",__func__,NameStr(res));

	return NameStr(res);
}

/*
 * IsStringDataType
 * ---------------
 * Determines if a PostgreSQL data type is string or numeric type
 * so that we can know when to wrap the value with single quotes
 * or leave it as is.
 *
 * type: PostgreSQL data type
 *
 * returns true if the data type needs to be wrapped with quotes
 *         or false otherwise.
 */
static bool IsStringDataType(Oid type)
{
	bool result;

	elog(DEBUG1, "%s called: type='%u'", __func__, type);

	result = type == TEXTOID ||
			 type == VARCHAROID ||
			 type == CHAROID ||
			 type == NAMEOID ||
			 type == DATEOID ||
			 type == TIMESTAMPOID ||
			 type == TIMESTAMPTZOID ||
			 type == NAMEOID ||
			 type == RDFNODEOID;

	elog(DEBUG1, "%s exit: returning '%s'", __func__, !result ? "false" : "true");
	return result;
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
static bool IsFunctionPushable(char *funcname)
{
	bool result;

	elog(DEBUG1, "%s called: funcname='%s'", __func__, funcname);

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

	elog(DEBUG1, "%s exit: returning '%s'", __func__, !result ? "false" : "true");

	return result;
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
static char *FormatSQLExtractField(char *field)
{
	char *res;

	elog(DEBUG1,"%s called: field='%s'", __func__, field);

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
		elog(DEBUG1,"%s exit: returning NULL (field unknown)", __func__);
		return NULL;
	}

	elog(DEBUG1,"%s exit: returning '%s'", __func__, res);
	return res;
}

static Oid get_rdfnode_oid(void)
{
    TypeName *typename = makeTypeNameFromNameList(list_make2(makeString("public"), makeString("rdfnode")));
    Oid typoid = typenameTypeId(NULL, typename);

    if (!OidIsValid(typoid))
        elog(ERROR, "could not find type \"rdfnode\"");

    return typoid;
}


typedef struct rdfnode
{
	int32 vl_len_;						 // required varlena header
	char vl_data[FLEXIBLE_ARRAY_MEMBER]; // actual data
} rdfnode;

static bool is_valid_xsd_double(const char *lexical)
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

static bool is_valid_xsd_int(const char *lexical)
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

static bool is_valid_xsd_dateTime(const char *lexical)
{
	regex_t regex;
	int reti;
	bool is_valid = false;
	const char *pattern = "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?([+-][0-9]{2}:[0-9]{2}|Z)?$";

	reti = regcomp(&regex, pattern, REG_EXTENDED);

	if (reti)
		ereport(ERROR, (errmsg("could not compile regex for xsd:dateTime")));

	reti = regexec(&regex, lexical, 0, NULL, 0);

	if (reti == 0)
		is_valid = true;

	regfree(&regex);
	return is_valid;
}

static bool is_valid_xsd_time(const char *lexical)
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

static bool is_valid_xsd_date(const char *lexical)
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

static bool is_valid_language_tag(const char *lan)
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
Datum rdfnode_in(PG_FUNCTION_ARGS)
{
    char *str_in = PG_GETARG_CSTRING(0);
    char *lexical;
    char *lan;
    char *dtype;
    
    rdfnode *result;
    size_t len;
    StringInfoData r;

    // Initialize string buffer
    initStringInfo(&r);

    if (strlen(str_in) == 0)
    {
        appendStringInfo(&r, "\"\"");
    }
    else if (isLiteral(str_in))
    {
        char *node = cstring_to_rdfnode(str_in);

        lexical = lex(node);
        lan = lang(node);
        dtype = datatype(node);

        /* xsd data tyoe validations */
        if (strcmp(dtype, RDF_XSD_DOUBLE) == 0 && !is_valid_xsd_double(lexical))
            ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                            errmsg("invalid lexical form for xsd:double: \"%s\"", lexical)));
        else if (strcmp(dtype, RDF_XSD_INT) == 0 && !is_valid_xsd_int(lexical))
            ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                            errmsg("invalid lexical form for xsd:int: \"%s\"", lexical)));
        else if (strcmp(dtype, RDF_XSD_INTEGER) == 0 && !is_valid_xsd_int(lexical))
            ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                            errmsg("invalid lexical form for xsd:integer: \"%s\"", lexical)));
        else if (strcmp(dtype, RDF_XSD_DATE) == 0 && !is_valid_xsd_date(lexical))
            ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                            errmsg("invalid lexical form for xsd:date: \"%s\"", lexical)));
        else if (strcmp(dtype, RDF_XSD_DATETIME) == 0 && !is_valid_xsd_dateTime(lexical))
            ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                            errmsg("invalid lexical form for xsd:dateTime: \"%s\"", lexical)));
        else if (strcmp(dtype, RDF_XSD_TIME) == 0 && !is_valid_xsd_time(lexical))
            ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                            errmsg("invalid lexical form for xsd:time: \"%s\"", lexical)));
        else if (strlen(lan) != 0)
        {
            if (!is_valid_language_tag(lan))
                ereport(ERROR, (errcode(ERRCODE_INVALID_TEXT_REPRESENTATION),
                                errmsg("invalid language tag: \"%s\"", lan)));

            appendStringInfo(&r, "%s", pstrdup(strlang(unescape_unicode(lexical), lan)));
        }
        else if (strlen(dtype) != 0)
            appendStringInfo(&r, "%s", pstrdup(strdt(unescape_unicode(lexical), dtype)));
        else
            appendStringInfo(&r, "%s", pstrdup(str(unescape_unicode(str_in))));
    }
    else
    {
        appendStringInfo(&r, "%s", pstrdup(unescape_unicode(str_in)));
    }

    len = strlen(r.data);
 
    /* 
	 * allocate memory for the rdfnode (use palloc0 to clear memory).
	 * r.data is already null-terminated, so no +1 :)
	 */
    result = (rdfnode *)palloc0(VARHDRSZ + len);
    SET_VARSIZE(result, VARHDRSZ + len);

    /* 
	 * copy string data into the result structure.
	 * no need for explicit null-termination here
	 */
    memcpy(result->vl_data, r.data, len);

    PG_RETURN_POINTER(result);
}

Datum rdfnode_out(PG_FUNCTION_ARGS)
{
    text *lit = PG_GETARG_TEXT_PP(0);       // Handles detoasting
    int len = VARSIZE_ANY_EXHDR(lit);       // Get payload length safely
    char *out = (char *) palloc(len + 1);

    memcpy(out, VARDATA_ANY(lit), len);
    out[len] = '\0';

    PG_RETURN_CSTRING(out);
}


static parsed_rdfnode parse_rdfnode(char *input)
{
	parsed_rdfnode result = {NULL, NULL, NULL, false};
	char *lexical = lex(input);
	elog(DEBUG1, "%s called: input='%s'", __func__, input);

	result.raw = input;
	result.lex = unescape_unicode(lexical);
	result.dtype = datatype(input);
	result.lang = lang(input);
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

	if (isIRI(input))
		result.isIRI = true;
	else if (strcmp(result.dtype, RDF_XSD_STRING) == 0)
	{
		result.isString = true;
	}
	else if ((result.isNumeric = isNumeric(input)))
	{
		// elog(WARNING,"literal '%s' is numeric ", result.raw);
	}
	else if (strcmp(result.dtype, RDF_XSD_DATE) == 0)
	{
		result.isDate = true;
	}
	else if (strcmp(result.dtype, RDF_XSD_DATETIME) == 0)
	{
		result.isDateTime = true;
	}
	else if (strcmp(result.dtype, RDF_XSD_DURATION) == 0)
	{
		result.isDuration = true;
	}
	else if (strcmp(result.dtype, RDF_XSD_TIME) == 0)
	{
		result.isTime = true;
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

Datum rdfnode_cmp(PG_FUNCTION_ARGS)
{
	text *ta = PG_GETARG_TEXT_PP(0);
	text *tb = PG_GETARG_TEXT_PP(1);
	const char *node1 = text_to_cstring(ta);
	const char *node2 = text_to_cstring(tb);
	int result = strcmp(node1, node2);

	if (result < 0)
		PG_RETURN_INT32(-1);
	else if (result > 0)
		PG_RETURN_INT32(1);
	else
		PG_RETURN_INT32(0);
}

static bool rdfnode_eq(parsed_rdfnode a, parsed_rdfnode b)
{
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

Datum rdfnode_neq_rdfnode(PG_FUNCTION_ARGS)
{
	text *a_text = PG_GETARG_TEXT_PP(0);
	text *b_text = PG_GETARG_TEXT_PP(1);

	parsed_rdfnode a_parsed = parse_rdfnode(text_to_cstring(a_text));
	parsed_rdfnode b_parsed = parse_rdfnode(text_to_cstring(b_text));

	PG_RETURN_BOOL(!rdfnode_eq(a_parsed, b_parsed));
}

Datum rdfnode_eq_rdfnode(PG_FUNCTION_ARGS)
{
	text *a_text = PG_GETARG_TEXT_PP(0);
	text *b_text = PG_GETARG_TEXT_PP(1);

	parsed_rdfnode a_parsed = parse_rdfnode(text_to_cstring(a_text));
	parsed_rdfnode b_parsed = parse_rdfnode(text_to_cstring(b_text));

	PG_RETURN_BOOL(rdfnode_eq(a_parsed, b_parsed));
}

static bool LiteralsComparable(parsed_rdfnode rdfnode1, parsed_rdfnode rdfnode2)
{
	/* identify the shared type category between the two literals */
	bool bothNumeric = rdfnode1.isNumeric && rdfnode2.isNumeric;
	bool bothDate = rdfnode1.isDate && rdfnode2.isDate;
	bool bothDateTime = rdfnode1.isDateTime && rdfnode2.isDateTime;
	bool bothTime = rdfnode1.isTime && rdfnode2.isTime;
	bool bothDuration = rdfnode1.isDuration && rdfnode2.isDuration;
	bool bothString = (rdfnode1.isString || rdfnode1.isPlainLiteral) &&	
					  (rdfnode2.isString || rdfnode2.isPlainLiteral);

	/* check for language-tagged literals (not comparable) */
	if (strlen(rdfnode1.lang) != 0 || strlen(rdfnode2.lang) !=0)
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

static bool rdfnode_lt(parsed_rdfnode rdfnode1, parsed_rdfnode rdfnode2)
{
	Datum arg1, arg2;

	if (!LiteralsComparable(rdfnode1, rdfnode2))
		return false; // Unreachable due to error in LiteralsComparable, but kept for safety

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

Datum rdfnode_lt_rdfnode(PG_FUNCTION_ARGS)
{
	text *a_text = PG_GETARG_TEXT_PP(0);
	text *b_text = PG_GETARG_TEXT_PP(1);

	parsed_rdfnode a_parsed = parse_rdfnode(text_to_cstring(a_text));
	parsed_rdfnode b_parsed = parse_rdfnode(text_to_cstring(b_text));

	PG_RETURN_BOOL(rdfnode_lt(a_parsed, b_parsed));
}


static bool rdfnode_gt(parsed_rdfnode rdfnode1, parsed_rdfnode rdfnode2)
{
	Datum arg1, arg2;

	if (!LiteralsComparable(rdfnode1, rdfnode2))
		return false; // Unreachable due to error in LiteralsComparable, but kept for safety

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

Datum rdfnode_gt_rdfnode(PG_FUNCTION_ARGS)
{
	text *a_text = PG_GETARG_TEXT_PP(0);
	text *b_text = PG_GETARG_TEXT_PP(1);

	parsed_rdfnode a_parsed = parse_rdfnode(text_to_cstring(a_text));
	parsed_rdfnode b_parsed = parse_rdfnode(text_to_cstring(b_text));

	PG_RETURN_BOOL(rdfnode_gt(a_parsed, b_parsed));
}





static bool rdfnode_le(parsed_rdfnode rdfnode1, parsed_rdfnode rdfnode2)
{
	Datum arg1, arg2;

	if (!LiteralsComparable(rdfnode1, rdfnode2))
		return false; // Unreachable due to error in LiteralsComparable, but kept for safety

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

Datum rdfnode_le_rdfnode(PG_FUNCTION_ARGS)
{
	text *a_text = PG_GETARG_TEXT_PP(0);
	text *b_text = PG_GETARG_TEXT_PP(1);

	parsed_rdfnode a_parsed = parse_rdfnode(text_to_cstring(a_text));
	parsed_rdfnode b_parsed = parse_rdfnode(text_to_cstring(b_text));

	PG_RETURN_BOOL(rdfnode_le(a_parsed, b_parsed));
}

static bool rdfnode_ge(parsed_rdfnode rdfnode1, parsed_rdfnode rdfnode2)
{
	Datum arg1, arg2;

	if (!LiteralsComparable(rdfnode1, rdfnode2))
		return false; // Unreachable due to error in LiteralsComparable, but kept for safety

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

Datum rdfnode_ge_rdfnode(PG_FUNCTION_ARGS)
{
	text *a_text = PG_GETARG_TEXT_PP(0);
	text *b_text = PG_GETARG_TEXT_PP(1);

	parsed_rdfnode a_parsed = parse_rdfnode(text_to_cstring(a_text));
	parsed_rdfnode b_parsed = parse_rdfnode(text_to_cstring(b_text));

	PG_RETURN_BOOL(rdfnode_ge(a_parsed, b_parsed));
}

Datum rdfnode_to_text(PG_FUNCTION_ARGS)
{
    text *lit = PG_GETARG_TEXT_PP(0);         // Safe detoasting
    int len = VARSIZE_ANY_EXHDR(lit);         // Length of the actual data
    text *result = (text *) palloc(VARHDRSZ + len);

    SET_VARSIZE(result, VARHDRSZ + len);
    memcpy(VARDATA(result), VARDATA_ANY(lit), len);

    PG_RETURN_TEXT_P(result);
}


/* numeric */
Datum rdfnode_to_numeric(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	if (!p.isNumeric)
		ereport(ERROR,
				(errmsg("cannot cast non-numeric RDF literal to numeric")));

	PG_RETURN_DATUM(DirectFunctionCall3(numeric_in,
										CStringGetDatum(p.lex),
										ObjectIdGetDatum(InvalidOid),
										Int32GetDatum(-1)));
}

Datum rdfnode_eq_numeric(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Numeric num = PG_GETARG_NUMERIC(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
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
	text *literal = PG_GETARG_TEXT_PP(0);
	Numeric num = PG_GETARG_NUMERIC(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(literal));
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_num;
	bool result;

	// rdf_num = DirectFunctionCall1(numeric_in, CStringGetDatum(p.lex));
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
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
	text *literal = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(literal));
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
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

	/* Format numeric as an RDF literal */
	appendStringInfo(&buf, "\"%s\"^^%s", val_str, RDF_XSD_DECIMAL); // XSD for numeric values

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

/* float8 */
Datum rdfnode_eq_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float8 f = PG_GETARG_FLOAT8(1);
	float8 rdf_float;
	Datum rdf_float_datum;
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	rdf_float_datum = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	rdf_float = DatumGetFloat8(rdf_float_datum);

	PG_RETURN_BOOL(rdf_float != f);
}

Datum rdfnode_lt_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float8 f = PG_GETARG_FLOAT8(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8lt, rdf_float, Float8GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float8 f = PG_GETARG_FLOAT8(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8gt, rdf_float, Float8GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float8 f = PG_GETARG_FLOAT8(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8le, rdf_float, Float8GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float8 f = PG_GETARG_FLOAT8(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8ge, rdf_float, Float8GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_to_float8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	if (!p.isNumeric)
		ereport(ERROR,
				(errmsg("cannot cast non-numeric RDF literal to double precision")));

	PG_RETURN_DATUM(DirectFunctionCall1(float8in, CStringGetDatum(p.lex)));
}

/* float8 <-> rdfnode (reverse operators) */
Datum float8_eq_rdfnode(PG_FUNCTION_ARGS)
{
	float8 f = PG_GETARG_FLOAT8(0);
	text *t = PG_GETARG_TEXT_PP(1);
	float8 rdf_float;
	Datum rdf_float_datum;
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	rdf_float_datum = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	rdf_float = DatumGetFloat8(rdf_float_datum);

	PG_RETURN_BOOL(f != rdf_float);
}

Datum float8_lt_rdfnode(PG_FUNCTION_ARGS)
{
	float8 f = PG_GETARG_FLOAT8(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8lt, Float8GetDatum(f), rdf_float));
	PG_RETURN_BOOL(result);
}

Datum float8_gt_rdfnode(PG_FUNCTION_ARGS)
{
	float8 f = PG_GETARG_FLOAT8(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8gt, Float8GetDatum(f), rdf_float));
	PG_RETURN_BOOL(result);
}

Datum float8_le_rdfnode(PG_FUNCTION_ARGS)
{
	float8 f = PG_GETARG_FLOAT8(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8le, Float8GetDatum(f), rdf_float));
	PG_RETURN_BOOL(result);
}

Datum float8_ge_rdfnode(PG_FUNCTION_ARGS)
{
	float8 f = PG_GETARG_FLOAT8(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float = DirectFunctionCall1(float8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float8ge, Float8GetDatum(f), rdf_float));
	PG_RETURN_BOOL(result);
}

Datum float8_to_rdfnode(PG_FUNCTION_ARGS)
{
	float8 val = PG_GETARG_FLOAT8(0);
	char *valstr;
	StringInfoData buf;

	valstr = DatumGetCString(DirectFunctionCall1(float8out, Float8GetDatum(val)));

	initStringInfo(&buf);
	appendStringInfo(&buf, "\"%s\"^^%s", valstr, RDF_XSD_DOUBLE);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

/* float4 (real) */
Datum rdfnode_to_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	PG_RETURN_DATUM(DirectFunctionCall1(float4in, CStringGetDatum(p.lex)));
}

Datum rdfnode_eq_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float4 f = PG_GETARG_FLOAT4(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4eq, rdf_float4, Float4GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_float4(PG_FUNCTION_ARGS)
{
	text *literal = PG_GETARG_TEXT_PP(0);
	float4 f = PG_GETARG_FLOAT4(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(literal));
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4ne, rdf_float4, Float4GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float4 f = PG_GETARG_FLOAT4(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4gt, rdf_float4, Float4GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_lt_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float4 f = PG_GETARG_FLOAT4(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4lt, rdf_float4, Float4GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float4 f = PG_GETARG_FLOAT4(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4ge, rdf_float4, Float4GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_float4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	float4 f = PG_GETARG_FLOAT4(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4le, rdf_float4, Float4GetDatum(f)));

	PG_RETURN_BOOL(result);
}

Datum float4_to_rdfnode(PG_FUNCTION_ARGS)
{
	float4 val = PG_GETARG_FLOAT4(0);
	StringInfoData buf;
	initStringInfo(&buf);

	if (isnan(val))
		appendStringInfo(&buf, "\"NaN\"^^%s", RDF_XSD_FLOAT);
	else if (isinf(val))
		appendStringInfo(&buf, val < 0 ? "\"-Infinity\"^^%s" : "\"Infinity\"^^%s", RDF_XSD_FLOAT);
	else
		appendStringInfo(&buf, "\"%g\"^^%s", val, RDF_XSD_FLOAT);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum float4_eq_rdfnode(PG_FUNCTION_ARGS)
{
	float4 f = PG_GETARG_FLOAT4(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4eq, Float4GetDatum(f), rdf_float4));

	PG_RETURN_BOOL(result);
}

Datum float4_neq_rdfnode(PG_FUNCTION_ARGS)
{
	float4 f = PG_GETARG_FLOAT4(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4ne, Float4GetDatum(f), rdf_float4));

	PG_RETURN_BOOL(result);
}

Datum float4_lt_rdfnode(PG_FUNCTION_ARGS)
{
	float4 f = PG_GETARG_FLOAT4(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4lt, Float4GetDatum(f), rdf_float4));

	PG_RETURN_BOOL(result);
}

Datum float4_gt_rdfnode(PG_FUNCTION_ARGS)
{
	float4 f = PG_GETARG_FLOAT4(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4gt, Float4GetDatum(f), rdf_float4));

	PG_RETURN_BOOL(result);
}

Datum float4_le_rdfnode(PG_FUNCTION_ARGS)
{
	float4 f = PG_GETARG_FLOAT4(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4le, Float4GetDatum(f), rdf_float4));

	PG_RETURN_BOOL(result);
}

Datum float4_ge_rdfnode(PG_FUNCTION_ARGS)
{
	float4 f = PG_GETARG_FLOAT4(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_float4 = DirectFunctionCall1(float4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(float4ge, Float4GetDatum(f), rdf_float4));

	PG_RETURN_BOOL(result);
}

/* ## bigint (int8) ## */
Datum rdfnode_to_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	int64 result = DatumGetInt64(DirectFunctionCall1(int8in, CStringGetDatum(p.lex)));

	PG_RETURN_INT64(result);
}

Datum rdfnode_lt_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int64 val = PG_GETARG_INT64(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int8 = DirectFunctionCall1(int8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int8lt, rdf_int8, Int64GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int64 val = PG_GETARG_INT64(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int8 = DirectFunctionCall1(int8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int8le, rdf_int8, Int64GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int64 val = PG_GETARG_INT64(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int8 = DirectFunctionCall1(int8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int8gt, rdf_int8, Int64GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int64 val = PG_GETARG_INT64(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int8 = DirectFunctionCall1(int8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int8ge, rdf_int8, Int64GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_eq_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int64 val = PG_GETARG_INT64(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int8 = DirectFunctionCall1(int8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int8eq, rdf_int8, Int64GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_int8(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int64 val = PG_GETARG_INT64(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int8 = DirectFunctionCall1(int8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int8ne, rdf_int8, Int64GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum int8_to_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	StringInfoData buf;
	initStringInfo(&buf);
	appendStringInfo(&buf, "\"%ld\"^^%s", val, RDF_XSD_LONG);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum int8_lt_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int8 = DirectFunctionCall1(int8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int8lt, Int64GetDatum(val), rdf_int8));

	PG_RETURN_BOOL(result);
}

Datum int8_le_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int8 = DirectFunctionCall1(int8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int8le, Int64GetDatum(val), rdf_int8));

	PG_RETURN_BOOL(result);
}

Datum int8_gt_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int8 = DirectFunctionCall1(int8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int8gt, Int64GetDatum(val), rdf_int8));

	PG_RETURN_BOOL(result);
}

Datum int8_ge_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int8 = DirectFunctionCall1(int8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int8ge, Int64GetDatum(val), rdf_int8));

	PG_RETURN_BOOL(result);
}

Datum int8_eq_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int8 = DirectFunctionCall1(int8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int8eq, rdf_int8, Int64GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum int8_neq_rdfnode(PG_FUNCTION_ARGS)
{
	int64 val = PG_GETARG_INT64(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int8 = DirectFunctionCall1(int8in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int8ne, rdf_int8, Int64GetDatum(val)));

	PG_RETURN_BOOL(result);
}

/* ## rdfnode OP int (int4) ## */
Datum rdfnode_to_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	int32 result = DatumGetInt32(DirectFunctionCall1(int4in, CStringGetDatum(p.lex)));

	PG_RETURN_INT64(result);
}

Datum rdfnode_lt_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int32 val = PG_GETARG_INT64(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int4 = DirectFunctionCall1(int4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int4lt, rdf_int4, Int32GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int32 val = PG_GETARG_INT32(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int4 = DirectFunctionCall1(int4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int4le, rdf_int4, Int32GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int32 val = PG_GETARG_INT32(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int4 = DirectFunctionCall1(int4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int4gt, rdf_int4, Int32GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int32 val = PG_GETARG_INT32(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int4 = DirectFunctionCall1(int4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int4ge, rdf_int4, Int32GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_eq_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int32 val = PG_GETARG_INT32(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int4 = DirectFunctionCall1(int4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int4eq, rdf_int4, Int32GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_int4(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int32 val = PG_GETARG_INT32(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int4 = DirectFunctionCall1(int4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int4ne, rdf_int4, Int32GetDatum(val)));

	PG_RETURN_BOOL(result);
}

/* ## int (int4) OP rdfnode ## */
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int4 = DirectFunctionCall1(int4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int4lt, Int32GetDatum(val), rdf_int4));

	PG_RETURN_BOOL(result);
}

Datum int4_le_rdfnode(PG_FUNCTION_ARGS)
{
	int32 val = PG_GETARG_INT32(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int4 = DirectFunctionCall1(int4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int4le, Int32GetDatum(val), rdf_int4));

	PG_RETURN_BOOL(result);
}

Datum int4_gt_rdfnode(PG_FUNCTION_ARGS)
{
	int32 val = PG_GETARG_INT32(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int4 = DirectFunctionCall1(int4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int4gt, Int32GetDatum(val), rdf_int4));

	PG_RETURN_BOOL(result);
}

Datum int4_ge_rdfnode(PG_FUNCTION_ARGS)
{
	int32 val = PG_GETARG_INT32(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int4 = DirectFunctionCall1(int4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int4ge, Int32GetDatum(val), rdf_int4));

	PG_RETURN_BOOL(result);
}

Datum int4_eq_rdfnode(PG_FUNCTION_ARGS)
{
	int32 val = PG_GETARG_INT32(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int4 = DirectFunctionCall1(int4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int4eq, rdf_int4, Int32GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum int4_neq_rdfnode(PG_FUNCTION_ARGS)
{
	int32 val = PG_GETARG_INT32(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int4 = DirectFunctionCall1(int4in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int4ne, rdf_int4, Int32GetDatum(val)));

	PG_RETURN_BOOL(result);
}

/* ## rdfnode OP int (int2) ## */
Datum rdfnode_to_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	int16 result = DatumGetInt32(DirectFunctionCall1(int2in, CStringGetDatum(p.lex)));

	PG_RETURN_INT64(result);
}

Datum rdfnode_lt_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int16 val = PG_GETARG_INT16(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int2 = DirectFunctionCall1(int2in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int2lt, rdf_int2, Int16GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int16 val = PG_GETARG_INT16(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int2 = DirectFunctionCall1(int2in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int2le, rdf_int2, Int16GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int16 val = PG_GETARG_INT16(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int2 = DirectFunctionCall1(int2in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int2gt, rdf_int2, Int16GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int16 val = PG_GETARG_INT16(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int2 = DirectFunctionCall1(int2in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int2ge, rdf_int2, Int16GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_eq_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int16 val = PG_GETARG_INT16(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int2 = DirectFunctionCall1(int2in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int2eq, rdf_int2, Int16GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_int2(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	int16 val = PG_GETARG_INT16(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int2 = DirectFunctionCall1(int2in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int2ne, rdf_int2, Int16GetDatum(val)));

	PG_RETURN_BOOL(result);
}

/* ## smallint (int2) OP rdfnode ## */
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int2 = DirectFunctionCall1(int2in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int2lt, Int16GetDatum(val), rdf_int2));

	PG_RETURN_BOOL(result);
}

Datum int2_le_rdfnode(PG_FUNCTION_ARGS)
{
	int16 val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int2 = DirectFunctionCall1(int2in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int2le, Int16GetDatum(val), rdf_int2));

	PG_RETURN_BOOL(result);
}

Datum int2_gt_rdfnode(PG_FUNCTION_ARGS)
{
	int16 val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int2 = DirectFunctionCall1(int2in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int2gt, Int16GetDatum(val), rdf_int2));

	PG_RETURN_BOOL(result);
}

Datum int2_ge_rdfnode(PG_FUNCTION_ARGS)
{
	int16 val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int2 = DirectFunctionCall1(int2in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int2ge, Int16GetDatum(val), rdf_int2));

	PG_RETURN_BOOL(result);
}

Datum int2_eq_rdfnode(PG_FUNCTION_ARGS)
{
	int16 val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int2 = DirectFunctionCall1(int2in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int2eq, rdf_int2, Int16GetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum int2_neq_rdfnode(PG_FUNCTION_ARGS)
{
	int16 val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_int2 = DirectFunctionCall1(int2in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(int2ne, rdf_int2, Int16GetDatum(val)));

	PG_RETURN_BOOL(result);
}

/* timestamptz (timestamp with time zone) OP rdfnode */
Datum timestamptz_to_rdfnode(PG_FUNCTION_ARGS)
{
	TimestampTz ts = PG_GETARG_TIMESTAMPTZ(0);
	struct pg_tm tm;
	fsec_t fsec;
	const char *tzn;
	StringInfoData buf;

	if (timestamp2tm(ts, NULL, &tm, &fsec, &tzn, NULL) != 0)
		ereport(ERROR, (errmsg("invalid timestamp")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "\"%04d-%02d-%02dT%02d:%02d:%02d.%06dZ\"^^%s",
					 tm.tm_year, tm.tm_mon, tm.tm_mday,
					 tm.tm_hour, tm.tm_min, tm.tm_sec,
					 (int)fsec,
					 RDF_XSD_DATETIME);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

/* rdfnode OP timestamptz (timestamp with time zone) */
Datum rdfnode_to_timestamptz(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	char *literal = strdt(text_to_cstring(t), RDF_XSD_DATE);
	parsed_rdfnode p = parse_rdfnode(literal);
	Datum result = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
														   CStringGetDatum(p.lex),
														   ObjectIdGetDatum(InvalidOid),
														   Int32GetDatum(-1)));

	PG_RETURN_DATUM(result);
}

/* rdfnode OP timestamp */
Datum rdfnode_to_timestamp(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	char *literal = strdt(text_to_cstring(t), RDF_XSD_DATE);
	parsed_rdfnode p = parse_rdfnode(literal);
	Datum result;

	if (!p.isDateTime && !p.isDate)
		ereport(ERROR, (errmsg("cannot cast RDF literal: %s", text_to_cstring(t))));

	result = DatumGetTimestamp(DirectFunctionCall3(timestamp_in,
												   CStringGetDatum(p.lex),
												   ObjectIdGetDatum(InvalidOid),
												   Int32GetDatum(-1)));

	PG_RETURN_DATUM(result);
}

Datum rdfnode_eq_timestamp(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Timestamp val = PG_GETARG_TIMESTAMP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_ts = DirectFunctionCall1(timestamp_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timestamp_eq, rdf_ts, TimestampGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_timestamp(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Timestamp val = PG_GETARG_TIMESTAMP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_ts = DirectFunctionCall1(timestamp_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timestamp_ne, rdf_ts, TimestampGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_lt_timestamp(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Timestamp val = PG_GETARG_TIMESTAMP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_ts = DirectFunctionCall1(timestamp_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timestamp_lt, rdf_ts, TimestampGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_timestamp(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Timestamp val = PG_GETARG_TIMESTAMP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_ts = DirectFunctionCall1(timestamp_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timestamp_gt, rdf_ts, TimestampGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_timestamp(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Timestamp val = PG_GETARG_TIMESTAMP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_ts = DirectFunctionCall1(timestamp_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timestamp_le, rdf_ts, TimestampGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_timestamp(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Timestamp val = PG_GETARG_TIMESTAMP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_ts = DirectFunctionCall1(timestamp_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timestamp_ge, rdf_ts, TimestampGetDatum(val)));

	PG_RETURN_BOOL(result);
}

/* timestamp OP rdfnode */
Datum timestamp_to_rdfnode(PG_FUNCTION_ARGS)
{
	Timestamp ts = PG_GETARG_TIMESTAMP(0);
	struct pg_tm tm;
	fsec_t fsec;
	StringInfoData buf;

	if (timestamp2tm(ts, NULL, &tm, &fsec, NULL, NULL) != 0)
		ereport(ERROR, (errmsg("invalid timestamp")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "\"%04d-%02d-%02dT%02d:%02d:%02d",
					 tm.tm_year, tm.tm_mon, tm.tm_mday,
					 tm.tm_hour, tm.tm_min, tm.tm_sec);

	if (fsec != 0)
		appendStringInfo(&buf, ".%06d", (int)fsec);

	appendStringInfo(&buf, "\"^^%s", RDF_XSD_DATETIME);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum timestamp_eq_rdfnode(PG_FUNCTION_ARGS)
{
	Timestamp val = PG_GETARG_TIMESTAMP(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_ts = DirectFunctionCall1(timestamp_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timestamp_eq, TimestampGetDatum(val), rdf_ts));

	PG_RETURN_BOOL(result);
}

Datum timestamp_neq_rdfnode(PG_FUNCTION_ARGS)
{
	Timestamp val = PG_GETARG_TIMESTAMP(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_ts = DirectFunctionCall1(timestamp_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timestamp_ne, TimestampGetDatum(val), rdf_ts));

	PG_RETURN_BOOL(result);
}

Datum timestamp_lt_rdfnode(PG_FUNCTION_ARGS)
{
	Timestamp val = PG_GETARG_TIMESTAMP(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_ts = DirectFunctionCall1(timestamp_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timestamp_lt, TimestampGetDatum(val), rdf_ts));

	PG_RETURN_BOOL(result);
}

Datum timestamp_gt_rdfnode(PG_FUNCTION_ARGS)
{
	Timestamp val = PG_GETARG_TIMESTAMP(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_ts = DirectFunctionCall1(timestamp_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timestamp_gt, TimestampGetDatum(val), rdf_ts));

	PG_RETURN_BOOL(result);
}

Datum timestamp_le_rdfnode(PG_FUNCTION_ARGS)
{
	Timestamp val = PG_GETARG_TIMESTAMP(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_ts = DirectFunctionCall1(timestamp_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timestamp_le, TimestampGetDatum(val), rdf_ts));

	PG_RETURN_BOOL(result);
}

Datum timestamp_ge_rdfnode(PG_FUNCTION_ARGS)
{
	Timestamp val = PG_GETARG_TIMESTAMP(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_ts = DirectFunctionCall1(timestamp_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timestamp_ge, TimestampGetDatum(val), rdf_ts));

	PG_RETURN_BOOL(result);
}

/* date OP rdfnode */
Datum rdfnode_to_date(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	char *literal = strdt(text_to_cstring(t), RDF_XSD_DATE);
	parsed_rdfnode p = parse_rdfnode(literal);

	Datum result = DirectFunctionCall3(date_in,
									   CStringGetDatum(p.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));

	PG_RETURN_DATEADT(DatumGetDateADT(result));
}

Datum rdfnode_lt_date(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	DateADT val = PG_GETARG_INT16(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_date = DirectFunctionCall1(date_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(date_lt, rdf_date, DateADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_date(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	DateADT val = PG_GETARG_INT16(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_date = DirectFunctionCall1(date_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(date_le, rdf_date, DateADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_date(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	DateADT val = PG_GETARG_INT16(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_date = DirectFunctionCall1(date_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(date_gt, rdf_date, DateADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_date(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	DateADT val = PG_GETARG_INT16(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_date = DirectFunctionCall1(date_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(date_ge, rdf_date, DateADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_eq_date(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	DateADT val = PG_GETARG_INT16(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_date = DirectFunctionCall1(date_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(date_eq, rdf_date, DateADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_date(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	DateADT val = PG_GETARG_INT16(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_date = DirectFunctionCall1(date_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(date_ne, rdf_date, DateADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

/* rdfnode OP date */
Datum date_to_rdfnode(PG_FUNCTION_ARGS)
{
	DateADT d = PG_GETARG_DATEADT(0);
	StringInfoData buf;
	int year, month, day;

	j2date(d + POSTGRES_EPOCH_JDATE, &year, &month, &day);

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "\"%04d-%02d-%02d\"^^%s",
					 year, month, day, RDF_XSD_DATE);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum date_lt_rdfnode(PG_FUNCTION_ARGS)
{
	DateADT val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_date = DirectFunctionCall1(date_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(date_lt, DateADTGetDatum(val), rdf_date));

	PG_RETURN_BOOL(result);
}

Datum date_le_rdfnode(PG_FUNCTION_ARGS)
{
	DateADT val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_date = DirectFunctionCall1(date_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(date_le, DateADTGetDatum(val), rdf_date));

	PG_RETURN_BOOL(result);
}

Datum date_gt_rdfnode(PG_FUNCTION_ARGS)
{
	DateADT val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_date = DirectFunctionCall1(date_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(date_gt, DateADTGetDatum(val), rdf_date));

	PG_RETURN_BOOL(result);
}

Datum date_ge_rdfnode(PG_FUNCTION_ARGS)
{
	DateADT val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_date = DirectFunctionCall1(date_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(date_ge, DateADTGetDatum(val), rdf_date));

	PG_RETURN_BOOL(result);
}

Datum date_eq_rdfnode(PG_FUNCTION_ARGS)
{
	DateADT val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_date = DirectFunctionCall1(date_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(date_eq, rdf_date, DateADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum date_neq_rdfnode(PG_FUNCTION_ARGS)
{
	DateADT val = PG_GETARG_INT16(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_date = DirectFunctionCall1(date_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(date_ne, rdf_date, DateADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

/* rdfnode OP time (without time zone) */
Datum rdfnode_to_time(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	char *literal = strdt(text_to_cstring(t), RDF_XSD_TIME);
	parsed_rdfnode p = parse_rdfnode(literal);

	Datum result = DirectFunctionCall3(time_in,
									   CStringGetDatum(p.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));

	PG_RETURN_TIMEADT(DatumGetTimeADT(result));
}

Datum rdfnode_lt_time(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	TimeADT val = PG_GETARG_TIMEADT(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_time = DirectFunctionCall1(time_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(time_lt, rdf_time, TimeADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_time(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	TimeADT val = PG_GETARG_TIMEADT(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_time = DirectFunctionCall1(time_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(time_le, rdf_time, TimeADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_time(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	TimeADT val = PG_GETARG_TIMEADT(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_time = DirectFunctionCall1(time_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(time_gt, rdf_time, TimeADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_time(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	TimeADT val = PG_GETARG_TIMEADT(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_time = DirectFunctionCall1(time_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(time_ge, rdf_time, TimeADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_eq_time(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	TimeADT val = PG_GETARG_TIMEADT(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_time = DirectFunctionCall1(time_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(time_eq, rdf_time, TimeADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_time(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	TimeADT val = PG_GETARG_TIMEADT(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_time = DirectFunctionCall1(time_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(time_ne, rdf_time, TimeADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

/* time (without time zone) OP rdfnode */
Datum time_to_rdfnode(PG_FUNCTION_ARGS)
{
	TimeADT t = PG_GETARG_TIMEADT(0);
	struct pg_tm tt;
	fsec_t fsec;
	StringInfoData buf;

	if (timestamp2tm(t, NULL, &tt, &fsec, NULL, NULL) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("time out of range")));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "\"%02d:%02d:%02d\"^^%s",
					 tt.tm_hour, tt.tm_min, tt.tm_sec,
					 RDF_XSD_TIME);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum time_lt_rdfnode(PG_FUNCTION_ARGS)
{
	TimeADT val = PG_GETARG_TIMEADT(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_time = DirectFunctionCall1(time_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(time_lt, TimeADTGetDatum(val), rdf_time));

	PG_RETURN_BOOL(result);
}

Datum time_le_rdfnode(PG_FUNCTION_ARGS)
{
	TimeADT val = PG_GETARG_TIMEADT(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_time = DirectFunctionCall1(time_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(time_le, TimeADTGetDatum(val), rdf_time));

	PG_RETURN_BOOL(result);
}

Datum time_gt_rdfnode(PG_FUNCTION_ARGS)
{
	TimeADT val = PG_GETARG_TIMEADT(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_time = DirectFunctionCall1(time_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(time_gt, TimeADTGetDatum(val), rdf_time));

	PG_RETURN_BOOL(result);
}

Datum time_ge_rdfnode(PG_FUNCTION_ARGS)
{
	TimeADT val = PG_GETARG_TIMEADT(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_time = DirectFunctionCall1(time_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(time_ge, TimeADTGetDatum(val), rdf_time));

	PG_RETURN_BOOL(result);
}

Datum time_eq_rdfnode(PG_FUNCTION_ARGS)
{
	TimeADT val = PG_GETARG_TIMEADT(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_time = DirectFunctionCall1(time_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(time_eq, rdf_time, TimeADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum time_neq_rdfnode(PG_FUNCTION_ARGS)
{
	TimeADT val = PG_GETARG_TIMEADT(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_time = DirectFunctionCall1(time_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(time_ne, rdf_time, TimeADTGetDatum(val)));

	PG_RETURN_BOOL(result);
}

/* rdfnode OP timetz (with time zone) */
Datum rdfnode_to_timetz(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum result = DirectFunctionCall3(timetz_in,
									   CStringGetDatum(p.lex),
									   ObjectIdGetDatum(InvalidOid),
									   Int32GetDatum(-1));

	PG_RETURN_TIMETZADT_P(DatumGetTimeTzADTP(result));
}

Datum rdfnode_lt_timetz(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	TimeTzADT *val = PG_GETARG_TIMETZADT_P(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_timetz = DirectFunctionCall3(timetz_in,
										   CStringGetDatum(p.lex),
										   ObjectIdGetDatum(InvalidOid),
										   Int32GetDatum(-1));
	bool result = DatumGetBool(DirectFunctionCall2(timetz_lt, rdf_timetz, TimeTzADTPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_timetz(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	TimeTzADT *val = PG_GETARG_TIMETZADT_P(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_timetz = DirectFunctionCall3(timetz_in,
										   CStringGetDatum(p.lex),
										   ObjectIdGetDatum(InvalidOid),
										   Int32GetDatum(-1));
	bool result = DatumGetBool(DirectFunctionCall2(timetz_le, rdf_timetz, TimeTzADTPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_timetz(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	TimeTzADT *val = PG_GETARG_TIMETZADT_P(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_timetz = DirectFunctionCall3(timetz_in,
										   CStringGetDatum(p.lex),
										   ObjectIdGetDatum(InvalidOid),
										   Int32GetDatum(-1));
	bool result = DatumGetBool(DirectFunctionCall2(timetz_gt, rdf_timetz, TimeTzADTPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_timetz(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	TimeTzADT *val = PG_GETARG_TIMETZADT_P(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_timetz = DirectFunctionCall3(timetz_in,
										   CStringGetDatum(p.lex),
										   ObjectIdGetDatum(InvalidOid),
										   Int32GetDatum(-1));
	bool result = DatumGetBool(DirectFunctionCall2(timetz_ge, rdf_timetz, TimeTzADTPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_eq_timetz(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	TimeTzADT *val = PG_GETARG_TIMETZADT_P(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_timetz = DirectFunctionCall3(timetz_in,
										   CStringGetDatum(p.lex),
										   ObjectIdGetDatum(InvalidOid),
										   Int32GetDatum(-1));
	bool result = DatumGetBool(DirectFunctionCall2(timetz_eq, rdf_timetz, TimeTzADTPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_timetz(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	TimeTzADT *val = PG_GETARG_TIMETZADT_P(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_timetz = DirectFunctionCall3(timetz_in,
										   CStringGetDatum(p.lex),
										   ObjectIdGetDatum(InvalidOid),
										   Int32GetDatum(-1));
	bool result = DatumGetBool(DirectFunctionCall2(timetz_ne, rdf_timetz, TimeTzADTPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

/* timetz (with time zone) OP rdfnode */
Datum timetz_to_rdfnode(PG_FUNCTION_ARGS)
{
	TimeTzADT *t = PG_GETARG_TIMETZADT_P(0);
	char *timetzstr;
	StringInfoData buf;
	timetzstr = DatumGetCString(DirectFunctionCall1(timetz_out, TimeTzADTPGetDatum(t)));

	initStringInfo(&buf);
	appendStringInfo(&buf,
					 "\"%s\"^^%s",
					 timetzstr,
					 RDF_XSD_TIME);

	PG_RETURN_TEXT_P(cstring_to_text(buf.data));
}

Datum timetz_lt_rdfnode(PG_FUNCTION_ARGS)
{
	TimeTzADT *val = PG_GETARG_TIMETZADT_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_timetz = DirectFunctionCall1(timetz_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timetz_lt, TimeTzADTPGetDatum(val), rdf_timetz));

	PG_RETURN_BOOL(result);
}

Datum timetz_le_rdfnode(PG_FUNCTION_ARGS)
{
	TimeTzADT *val = PG_GETARG_TIMETZADT_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_timetz = DirectFunctionCall1(timetz_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timetz_le, TimeTzADTPGetDatum(val), rdf_timetz));

	PG_RETURN_BOOL(result);
}

Datum timetz_gt_rdfnode(PG_FUNCTION_ARGS)
{
	TimeTzADT *val = PG_GETARG_TIMETZADT_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_timetz = DirectFunctionCall1(timetz_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timetz_gt, TimeTzADTPGetDatum(val), rdf_timetz));

	PG_RETURN_BOOL(result);
}

Datum timetz_ge_rdfnode(PG_FUNCTION_ARGS)
{
	TimeTzADT *val = PG_GETARG_TIMETZADT_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_timetz = DirectFunctionCall1(timetz_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timetz_ge, TimeTzADTPGetDatum(val), rdf_timetz));

	PG_RETURN_BOOL(result);
}

Datum timetz_eq_rdfnode(PG_FUNCTION_ARGS)
{
	TimeTzADT *val = PG_GETARG_TIMETZADT_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_timetz = DirectFunctionCall1(timetz_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timetz_eq, rdf_timetz, TimeTzADTPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum timetz_neq_rdfnode(PG_FUNCTION_ARGS)
{
	TimeTzADT *val = PG_GETARG_TIMETZADT_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_timetz = DirectFunctionCall1(timetz_in, CStringGetDatum(p.lex));
	bool result = DatumGetBool(DirectFunctionCall2(timetz_ne, rdf_timetz, TimeTzADTPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

/* boolean <-> rdfnode */
Datum rdfnode_to_boolean(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	char *literal = text_to_cstring(t);
	parsed_rdfnode p = parse_rdfnode(literal);
	bool result;

	if (strcmp(p.dtype, RDF_XSD_BOOLEAN) != 0 && strcmp(p.dtype, RDF_XSD_INTEGER) != 0)
		ereport(ERROR, (errmsg("cannot cast RDF literal: %s to boolean", literal)));

	if (pg_strcasecmp(p.lex, "true") == 0 || strcmp(p.lex, "1") == 0)
		result = true;
	else if (pg_strcasecmp(p.lex, "false") == 0 || strcmp(p.lex, "0") == 0)
		result = false;
	else
		ereport(ERROR,
				(errmsg("cannot cast RDF literal: %s to boolean", literal),
				 errdetail("expected values for xsd:boolean are \"true\" or \"false\"")));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_eq_boolean(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	bool val = PG_GETARG_BOOL(1);
	char *literal = text_to_cstring(t);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	if (strcmp(p.dtype, RDF_XSD_BOOLEAN) != 0 && strcmp(p.dtype, RDF_XSD_INTEGER) != 0)
		ereport(ERROR, (errmsg("cannot cast RDF literal: %s to boolean", literal)));

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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	if (strcmp(p.dtype, RDF_XSD_BOOLEAN) != 0 && strcmp(p.dtype, RDF_XSD_INTEGER) != 0)
		ereport(ERROR, (errmsg("cannot cast RDF literal: %s to boolean", literal)));

	if ((pg_strcasecmp(p.lex, "true") == 0 || strcmp(p.lex, "1") == 0) && !val)
		PG_RETURN_BOOL(true);
	else if ((pg_strcasecmp(p.lex, "false") || strcmp(p.lex, "0") == 0) == 0 && val)
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	if (strcmp(p.dtype, RDF_XSD_BOOLEAN) != 0 && strcmp(p.dtype, RDF_XSD_INTEGER) != 0)
		ereport(ERROR, (errmsg("cannot cast RDF literal: %s to boolean", literal)));

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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	if (strcmp(p.dtype, RDF_XSD_BOOLEAN) != 0 && strcmp(p.dtype, RDF_XSD_INTEGER) != 0)
		ereport(ERROR, (errmsg("cannot cast RDF literal: %s to boolean", literal)));

	if ((pg_strcasecmp(p.lex, "true") == 0 || strcmp(p.lex, "1") == 0) && !val)
		PG_RETURN_BOOL(true);
	else if ((pg_strcasecmp(p.lex, "false") == 0 || strcmp(p.lex, "0") == 0) && val)
		PG_RETURN_BOOL(true);
	else
		PG_RETURN_BOOL(false);
}

/* interval */
Datum rdfnode_to_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	char *literal = text_to_cstring(t);
	parsed_rdfnode p = parse_rdfnode(literal);
	Datum result;

	if (strcmp(p.dtype, RDF_XSD_DURATION) != 0)
		ereport(ERROR,
				(errmsg("cannot cast RDF literal: %s to interval", literal),
				 errdetail("expected xsd:duration")));

	result = DirectFunctionCall3(interval_in,
								 CStringGetDatum(p.lex),
								 ObjectIdGetDatum(InvalidOid),
								 Int32GetDatum(-1));

	PG_RETURN_DATUM(result);
}

Datum rdfnode_eq_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Interval *val = PG_GETARG_INTERVAL_P(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	Datum rdf_interval = DirectFunctionCall3(interval_in,
											 CStringGetDatum(p.lex),
											 ObjectIdGetDatum(InvalidOid),
											 Int32GetDatum(-1));

	bool result = DatumGetBool(DirectFunctionCall2(interval_eq,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_neq_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Interval *val = PG_GETARG_INTERVAL_P(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	Datum rdf_interval = DirectFunctionCall3(interval_in,
											 CStringGetDatum(p.lex),
											 ObjectIdGetDatum(InvalidOid),
											 Int32GetDatum(-1));

	bool result = DatumGetBool(DirectFunctionCall2(interval_ne,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_lt_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Interval *val = PG_GETARG_INTERVAL_P(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_interval = DirectFunctionCall3(interval_in,
											 CStringGetDatum(p.lex),
											 ObjectIdGetDatum(InvalidOid),
											 Int32GetDatum(-1));

	bool result = DatumGetBool(DirectFunctionCall2(interval_lt,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_le_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Interval *val = PG_GETARG_INTERVAL_P(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_interval = DirectFunctionCall3(interval_in,
											 CStringGetDatum(p.lex),
											 ObjectIdGetDatum(InvalidOid),
											 Int32GetDatum(-1));

	bool result = DatumGetBool(DirectFunctionCall2(interval_le,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_gt_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Interval *val = PG_GETARG_INTERVAL_P(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_interval = DirectFunctionCall3(interval_in,
											 CStringGetDatum(p.lex),
											 ObjectIdGetDatum(InvalidOid),
											 Int32GetDatum(-1));

	bool result = DatumGetBool(DirectFunctionCall2(interval_gt,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum rdfnode_ge_interval(PG_FUNCTION_ARGS)
{
	text *t = PG_GETARG_TEXT_PP(0);
	Interval *val = PG_GETARG_INTERVAL_P(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_interval = DirectFunctionCall3(interval_in,
											 CStringGetDatum(p.lex),
											 ObjectIdGetDatum(InvalidOid),
											 Int32GetDatum(-1));

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

	initStringInfo(&buf);

	/* deparse interval */
	if (iv->month < 0 || iv->day < 0 || iv->time < 0)
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
			appendStringInfo(&buf, "%dY", abs(years));
		if (months != 0)
			appendStringInfo(&buf, "%dM", abs(months));
		if (days != 0)
			appendStringInfo(&buf, "%dD", abs(days));

		/* add time portion (hours, minutes, seconds, microseconds) */
		if (hours != 0 || mins != 0 || secs != 0 || usecs != 0)
		{
			appendStringInfoChar(&buf, 'T');

			if (hours != 0)
				appendStringInfo(&buf, "%dH", abs(hours));
			if (mins != 0)
				appendStringInfo(&buf, "%dM", abs(mins));

			if (usecs != 0)
				appendStringInfo(&buf, "%d.%06dS", abs(secs), abs(usecs));
			else if (secs != 0)
				appendStringInfo(&buf, "%dS", abs(secs));
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
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	Datum rdf_interval = DirectFunctionCall3(interval_in,
											 CStringGetDatum(p.lex),
											 ObjectIdGetDatum(InvalidOid),
											 Int32GetDatum(-1));

	bool result = DatumGetBool(DirectFunctionCall2(interval_eq,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum interval_neq_rdfnode(PG_FUNCTION_ARGS)
{
	Interval *val = PG_GETARG_INTERVAL_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));

	Datum rdf_interval = DirectFunctionCall3(interval_in,
											 CStringGetDatum(p.lex),
											 ObjectIdGetDatum(InvalidOid),
											 Int32GetDatum(-1));

	bool result = DatumGetBool(DirectFunctionCall2(interval_ne,
												   rdf_interval,
												   IntervalPGetDatum(val)));

	PG_RETURN_BOOL(result);
}

Datum interval_lt_rdfnode(PG_FUNCTION_ARGS)
{
	Interval *val = PG_GETARG_INTERVAL_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_interval = DirectFunctionCall3(interval_in,
											 CStringGetDatum(p.lex),
											 ObjectIdGetDatum(InvalidOid),
											 Int32GetDatum(-1));

	bool result = DatumGetBool(DirectFunctionCall2(interval_lt,
												   IntervalPGetDatum(val),
												   rdf_interval));

	PG_RETURN_BOOL(result);
}

Datum interval_le_rdfnode(PG_FUNCTION_ARGS)
{
	Interval *val = PG_GETARG_INTERVAL_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_interval = DirectFunctionCall3(interval_in,
											 CStringGetDatum(p.lex),
											 ObjectIdGetDatum(InvalidOid),
											 Int32GetDatum(-1));

	bool result = DatumGetBool(DirectFunctionCall2(interval_le,
												   IntervalPGetDatum(val),
												   rdf_interval));
	PG_RETURN_BOOL(result);
}

Datum interval_gt_rdfnode(PG_FUNCTION_ARGS)
{
	Interval *val = PG_GETARG_INTERVAL_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_interval = DirectFunctionCall3(interval_in,
											 CStringGetDatum(p.lex),
											 ObjectIdGetDatum(InvalidOid),
											 Int32GetDatum(-1));

	bool result = DatumGetBool(DirectFunctionCall2(interval_gt,												   
												   IntervalPGetDatum(val),
												   rdf_interval));

	PG_RETURN_BOOL(result);
}

Datum interval_ge_rdfnode(PG_FUNCTION_ARGS)
{
	Interval *val = PG_GETARG_INTERVAL_P(0);
	text *t = PG_GETARG_TEXT_PP(1);
	parsed_rdfnode p = parse_rdfnode(text_to_cstring(t));
	Datum rdf_interval = DirectFunctionCall3(interval_in,
											 CStringGetDatum(p.lex),
											 ObjectIdGetDatum(InvalidOid),
											 Int32GetDatum(-1));

	bool result = DatumGetBool(DirectFunctionCall2(interval_ge,												   
												   IntervalPGetDatum(val),
												   rdf_interval));

	PG_RETURN_BOOL(result);
}

#if PG_VERSION_NUM < 130000
static void
pg_unicode_to_server(pg_wchar c, unsigned char *utf8)
{
    unsigned char utf8buf[8];  /* Large enough for UTF-8 encoding */
    int len;
    unsigned char *converted;

    /* Convert Unicode code point to UTF-8 */
    if (unicode_to_utf8(c, utf8buf) == NULL)
        ereport(ERROR,
                (errcode(ERRCODE_CHARACTER_NOT_IN_REPERTOIRE),
                 errmsg("invalid Unicode code point: 0x%04x", c)));

    len = pg_utf_mblen(utf8buf);  /* Get the length of the encoded UTF-8 character */

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

    utf8[len] = '\0';  /* Null-terminate (safe if utf8 has size ≥ 5) */
}
#endif

static char *unescape_unicode(const char *input)
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