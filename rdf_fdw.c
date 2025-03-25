
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
#include "mb/pg_wchar.h"
#include "miscadmin.h"
#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "nodes/pg_list.h"
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
#include <funcapi.h>
#include <librdf.h>

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
#define RDF_DEFAULT_CONNECTTIMEOUT 300
#define RDF_DEFAULT_MAXRETRY 3
#define RDF_KEYWORD_NOT_FOUND -1
#define RDF_DEFAULT_FORMAT "application/sparql-results+xml"
#define RDF_RDFXML_FORMAT "application/rdf+xml"
#define RDF_DEFAULT_BASE_URI "http://rdf_fdw.postgresql.org/"
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

/*
 * This macro is used by DeparseExpr to identify PostgreSQL
 * types that can be translated to SPARQL
 */
#define canHandleType(x) ((x) == TEXTOID || (x) == CHAROID || (x) == BPCHAROID \
			|| (x) == VARCHAROID || (x) == NAMEOID || (x) == INT8OID || (x) == INT2OID \
			|| (x) == INT4OID || (x) == FLOAT4OID || (x) == FLOAT8OID || (x) == BOOLOID \
			|| (x) == NUMERICOID || (x) == DATEOID || (x) == TIMESTAMPOID || (x) == TIMESTAMPTZOID)

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
	{RDF_COLUMN_OPTION_NODETYPE, AttributeRelationId, false, false},
	{RDF_COLUMN_OPTION_LANGUAGE, AttributeRelationId, false, false},
	/* User Mapping */
	{RDF_USERMAPPING_OPTION_USER, UserMappingRelationId, false, false},
	{RDF_USERMAPPING_OPTION_PASSWORD, UserMappingRelationId, false, false},
	/* EOList option */
	{NULL, InvalidOid, false, false}
};

typedef struct RDFfdwTriple
{
	char *subject;	 /* RDF triple subject */
	char *predicate; /* RDF triple predicate */
	char *object;	 /* RDF triple object */
} RDFfdwTriple;

extern Datum rdf_fdw_handler(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_validator(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_version(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_clone_table(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_describe(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_strstarts(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_strends(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_strbefore(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_strafter(PG_FUNCTION_ARGS);

PG_FUNCTION_INFO_V1(rdf_fdw_handler);
PG_FUNCTION_INFO_V1(rdf_fdw_validator);
PG_FUNCTION_INFO_V1(rdf_fdw_version);
PG_FUNCTION_INFO_V1(rdf_fdw_clone_table);
PG_FUNCTION_INFO_V1(rdf_fdw_describe);
PG_FUNCTION_INFO_V1(rdf_fdw_strstarts);
PG_FUNCTION_INFO_V1(rdf_fdw_strends);
PG_FUNCTION_INFO_V1(rdf_fdw_strbefore);
PG_FUNCTION_INFO_V1(rdf_fdw_strafter);

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
static char *DeparseDate(Datum datum);
static char *DeparseTimestamp(Datum datum, bool hasTimezone);
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
static bool IsSPARQLStringFunction(char *funcname);
static char *FormatSQLExtractField(char *field);

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
 * rdf_fdw_strbefore
 * ----------
 *
 * This function implements the SPARQL function STRBEFORE() as
 * described in the SPARQL 1.1 Standard.
 */
Datum rdf_fdw_strbefore(PG_FUNCTION_ARGS)
{
    text *input = PG_GETARG_TEXT_PP(0);
    text *delimiter = PG_GETARG_TEXT_PP(1);
    char *input_str = text_to_cstring(input);
    char *delimiter_str = text_to_cstring(delimiter);
    char *pos;

    if ((pos = strstr(input_str, delimiter_str)) != NULL)
    {
        int before_len = pos - input_str;
        PG_RETURN_TEXT_P(cstring_to_text_with_len(input_str, before_len));
    }

    PG_RETURN_TEXT_P(cstring_to_text(""));
}

/*
 * rdf_fdw_strafter
 * ----------
 *
 * This function implements the SPARQL function STRAFTER() as
 * described in the SPARQL 1.1 Standard.
 */
Datum rdf_fdw_strafter(PG_FUNCTION_ARGS)
{
    text *input = PG_GETARG_TEXT_PP(0);
    text *delimiter = PG_GETARG_TEXT_PP(1);
    char *input_str = text_to_cstring(input);
    char *delimiter_str = text_to_cstring(delimiter);
    char *pos;

	if ((pos = strstr(input_str, delimiter_str)) != NULL)
	{
		pos += strlen(delimiter_str); // Move past the delimiter
		PG_RETURN_TEXT_P(cstring_to_text(pos));
	}

	PG_RETURN_TEXT_P(cstring_to_text(""));
}


/*
 * rdf_fdw_strstarts
 * ----------
 *
 * This function implements the SPARQL function STRSTARTS() as
 * described in the SPARQL 1.1 Standard.
 */
Datum rdf_fdw_strstarts(PG_FUNCTION_ARGS)
{
    text *str = PG_GETARG_TEXT_PP(0);
    text *prefix = PG_GETARG_TEXT_PP(1);

    int str_len = VARSIZE_ANY_EXHDR(str);
    int prefix_len = VARSIZE_ANY_EXHDR(prefix);
    char *str_data = VARDATA_ANY(str);
    char *prefix_data = VARDATA_ANY(prefix);

    if (prefix_len > str_len)
        PG_RETURN_BOOL(false);

    /* Compare characters from the beginning */
    for (int i = 0; i < prefix_len; i++)
    {
        if (str_data[i] != prefix_data[i])
            PG_RETURN_BOOL(false);
    }

    PG_RETURN_BOOL(true);
}

/*
 * rdf_fdw_strends
 * ----------
 *
 * This function implements the SPARQL function STRENDS() as
 * described in the SPARQL 1.1 Standard.
 */
Datum rdf_fdw_strends(PG_FUNCTION_ARGS)
{
    text *str = PG_GETARG_TEXT_PP(0);
    text *suffix = PG_GETARG_TEXT_PP(1);

    int str_len = VARSIZE_ANY_EXHDR(str);
    int suffix_len = VARSIZE_ANY_EXHDR(suffix);
    char *str_data = VARDATA_ANY(str);
    char *suffix_data = VARDATA_ANY(suffix);

    if (suffix_len > str_len)
        PG_RETURN_BOOL(false);

    /* Compare characters from the end */
    for (int i = 0; i < suffix_len; i++)
    {
        if (str_data[str_len - suffix_len + i] != suffix_data[i])
            PG_RETURN_BOOL(false);
    }

    PG_RETURN_BOOL(true);
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
			elog(DEBUG1, "%s: parsing RDF/XML result set (base '%s')", __func__, state->base_uri);

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
				triple->subject = pstrdup((char *) librdf_uri_as_string(librdf_node_get_uri(statement->subject)));
			else if (librdf_node_is_blank(statement->subject))
				triple->subject = pstrdup((char *) librdf_node_get_blank_identifier(statement->subject));
			else
				ereport(ERROR,
						(errcode(ERRCODE_FDW_ERROR),
						 errmsg("unsupported subject node type")));

			triple->predicate = pstrdup((char *) librdf_uri_as_string(librdf_node_get_uri(statement->predicate)));

			if (librdf_node_is_resource(statement->object))
				triple->object = pstrdup((char *) librdf_uri_as_string(librdf_node_get_uri(statement->object)));
			else if (librdf_node_is_literal(statement->object))
			{
				const char *value = (char *) librdf_node_get_literal_value(statement->object);
				StringInfoData literal;
				initStringInfo(&literal);

				if (state->keep_raw_literal)
				{
					const char *language = librdf_node_get_literal_value_language(statement->object);
					librdf_uri *datatype = librdf_node_get_literal_value_datatype_uri(statement->object);

					if (datatype)
						appendStringInfo(&literal, "\"%s\"^^<%s>", value, librdf_uri_as_string(datatype));
					else if (language)
						appendStringInfo(&literal, "\"%s\"@%s", value, language);
					else
						appendStringInfo(&literal, "\"%s\"", value);
				}
				else
					appendStringInfo(&literal, "%s", value);

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
		 * Setting session's default values.
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

		elog(DEBUG1, "%s loading server name: %s", __func__, srvname);
		state->server = GetForeignServerByName(srvname, true);

		if (!state->server)
			ereport(ERROR,
					(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
					 errmsg("invalid SERVER: %s", quote_identifier(srvname))));

		/*
		* Loading SERVER OPTIONS
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

	elog(DEBUG1,"%s: checking if tables match",__func__);
	for (size_t ftidx = 0; ftidx < state->numcols; ftidx++)
	{
		for (size_t ttidx = 0; ttidx < state->target_table->rd_att->natts; ttidx++)
		{
			Form_pg_attribute attr = TupleDescAttr(tupdesc, ttidx);

			elog(DEBUG1,"%s: comparing %s - %s", __func__,
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




	elog(DEBUG1,"%s: validating 'fetch_size' tables match",__func__);
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

	elog(DEBUG1,"fetch_size = %d",fetch_size);
	
	elog(DEBUG1,"ordering_pgcolumn = '%s'", !orderby_query || strlen(state->ordering_pgcolumn) == 0 ? "NOT SET" : state->ordering_pgcolumn);

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
			elog(DEBUG1, "%s: setting ordering variable to '%s'", __func__, state->rdfTable->cols[0]->sparqlvar);
			orderby_variable = pstrdup(state->rdfTable->cols[0]->sparqlvar);
		}

		if (!orderby_variable && strlen(state->ordering_pgcolumn) != 0)
			ereport(ERROR,
					(errcode(ERRCODE_FDW_ERROR),
					 errmsg("invalid 'ordering_column': %s", state->ordering_pgcolumn),
					 errhint("the column '%s' does not exist in the foreign table '%s'",
							 state->ordering_pgcolumn,
							 get_rel_name(state->foreigntableid))));

		elog(DEBUG1, "orderby_variable = '%s'", orderby_variable);
	}

	state->sparql_prefixes = DeparseSPARQLPrefix(state->raw_sparql);
	elog(DEBUG1,"sparql_prefixes = \n\n'%s'",state->sparql_prefixes);

	state->sparql_from = DeparseSPARQLFrom(state->raw_sparql);
	elog(DEBUG1,"sparql_from = \n\n'%s'",state->sparql_from);

	state->sparql_select = NameStr(select);
	elog(DEBUG1,"sparql_select = \n\n'%s'",state->sparql_select);

	state->sparql_where = DeparseSPARQLWhereGraphPattern(state);
	elog(DEBUG1,"sparql_where = \n\n'%s'",state->sparql_where);

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
			elog(DEBUG1,"%s: number of retrieved records reached the limit of %d.\n\n  records inserted: %d\n  fetch size: %d\n",
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
			elog(DEBUG1,"%s: SPARQL query returned nothing",__func__);
			break;
		}

		ret = InsertRetrievedData(state,state->offset, state->offset + fetch_size);

		elog(DEBUG1,"%s: InsertRetrievedData returned %d records",__func__, ret);

		state->inserted_records = state->inserted_records + ret;

		state->offset = state->offset + fetch_size;

		pfree(limit_clause.data);
	}

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

				if (strcmp(opt->optname, RDF_SERVER_OPTION_ENDPOINT) == 0 || strcmp(opt->optname, RDF_SERVER_OPTION_HTTP_PROXY) == 0 || strcmp(opt->optname, RDF_SERVER_OPTION_HTTPS_PROXY) == 0)
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
				}

				if(strcmp(opt->optname, RDF_COLUMN_OPTION_LITERALTYPE) == 0)
				{				
					if(hasliteralatt)
						ereport(ERROR,
							(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
							 errmsg("invalid %s: '%s'", def->defname, defGetString(def)),
							 errhint("the parameters '%s' and '%s' cannot be combined",RDF_COLUMN_OPTION_LITERALTYPE, RDF_COLUMN_OPTION_LANGUAGE)));
					
					hasliteralatt = true;

					if(ContainsWhitespaces(defGetString(def)))
						ereport(ERROR,
							(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
							errmsg("invalid %s: '%s'", def->defname, defGetString(def)),
							errhint("whitespaces are not allwoed in '%s' option", RDF_COLUMN_OPTION_LITERALTYPE)));

				}

				if(strcmp(opt->optname, RDF_COLUMN_OPTION_LANGUAGE) == 0)
				{
					if(hasliteralatt)
						ereport(ERROR,
							(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
							 errmsg("invalid %s: '%s'", def->defname, defGetString(def)),
							 errhint("the parameters '%s' and '%s' cannot be combined",RDF_COLUMN_OPTION_LITERALTYPE, RDF_COLUMN_OPTION_LANGUAGE)));
					
					hasliteralatt = true;

					if(ContainsWhitespaces(defGetString(def)))
						ereport(ERROR,
							(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
							errmsg("invalid %s: '%s'", def->defname, defGetString(def)),
							errhint("whitespaces are not allwoed in '%s' option", RDF_COLUMN_OPTION_LANGUAGE)));
				}

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

	InitSession(state, baserel, root);

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

	elog(DEBUG1,"%s called",__func__);
	scan_clauses = extract_actual_clauses(scan_clauses, false);

	if(!state->enable_pushdown) 
	{
		state->sparql = state->raw_sparql;
		elog(DEBUG1,"  %s: Pushdown feature disabled. SPARQL query won't be modified.",__func__);
	} 
	else if(!state->is_sparql_parsable) 
	{
		state->sparql = state->raw_sparql;
		elog(DEBUG1,"  %s: SPARQL cannot be fully parsed. The raw SPARQL will be used and all filters will be applied locally.",__func__);
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

	state = DeserializePlanData(fs->fdw_private);

	elog(DEBUG1,"%s: initializing XML parser",__func__);
	xmlInitParser();

	LoadRDFData(state);
	state->rowcount = 0;
	node->fdw_state = (void *)state;
}

static TupleTableSlot *rdfIterateForeignScan(ForeignScanState *node)
{
	TupleTableSlot *slot = node->ss.ss_ScanTupleSlot;
	struct RDFfdwState *state = (struct RDFfdwState *) node->fdw_state;

	elog(DEBUG2,"%s called",__func__);

	ExecClearTuple(slot);	

	if (state->numcols == 0)
	{
		elog(DEBUG2,"  %s: no foreign column available in this table.",__func__);	
		return slot;
	}

	elog(DEBUG2,"  %s: state->rowcount = %d | state->pagesize = %d",__func__,state->rowcount , state->pagesize);

	if(state->rowcount < state->pagesize)
	{		
		CreateTuple(slot, state);
		ExecStoreVirtualTuple(slot);
		elog(DEBUG2,"  %s: virtual tuple stored (%d/%d)",__func__,state->rowcount , state->pagesize);
		state->rowcount++;
	} 
	else 
	{
	   /*
		* No further records to be retrieved. Let's clean up the XML parser before ending the query.
		*/	
		elog(DEBUG2,"  %s: no rows left (%d/%d)",__func__,state->rowcount , state->pagesize);

		elog(DEBUG1,"%s: freeing xml parser",__func__);
		xmlCleanupParser();
	}

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
			elog(DEBUG1,"%s: freeing xmldoc",__func__);
			xmlFreeDoc(state->xmldoc);
		}

		if(state)
		{
			elog(DEBUG1,"%s: freeing rdf_fdw state",__func__);
			pfree(state);
		}

	}

	elog(DEBUG1,"%s: so long .. \n",__func__);
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

		foreach (lc, options)
		{
			DefElem *def = (DefElem *)lfirst(lc);

			if (strcmp(def->defname, RDF_COLUMN_OPTION_VARIABLE) == 0)
			{
				elog(DEBUG1,"  %s: (%d) adding sparql variable > '%s'",__func__,i,defGetString(def));
				state->rdfTable->cols[i]->sparqlvar = pstrdup(defGetString(def));
			}
			else if (strcmp(def->defname, RDF_COLUMN_OPTION_EXPRESSION) == 0)
			{
				elog(DEBUG1,"  %s: (%d) adding sparql expression > '%s'",__func__,i,defGetString(def));
				state->rdfTable->cols[i]->expression = pstrdup(defGetString(def));
				state->rdfTable->cols[i]->pushable = IsExpressionPushable(defGetString(def));
				elog(DEBUG1,"  %s: (%d) is expression pushable? > '%s'",__func__,i,
					state->rdfTable->cols[i]->pushable ? "true" : "false");
			}
			else if (strcmp(def->defname, RDF_COLUMN_OPTION_LITERALTYPE) == 0)
			{
				StringInfoData literaltype;
				initStringInfo(&literaltype);
				appendStringInfo(&literaltype, "^^%s", defGetString(def));
				elog(DEBUG1,"  %s: (%d) adding sparql literal data type > '%s'",__func__,i,defGetString(def));
				state->rdfTable->cols[i]->literaltype = pstrdup(literaltype.data);
			}
			else if (strcmp(def->defname, RDF_COLUMN_OPTION_NODETYPE) == 0)
			{
				elog(DEBUG1,"  %s: (%d) adding sparql node data type > '%s'",__func__,i,defGetString(def));
				state->rdfTable->cols[i]->nodetype = pstrdup(defGetString(def));
			}
			else if (strcmp(def->defname, RDF_COLUMN_OPTION_LANGUAGE) == 0) 
			{
				StringInfoData tag;
				initStringInfo(&tag);
				appendStringInfo(&tag, "@%s", defGetString(def));
				elog(DEBUG1,"  %s: (%d) adding literal language tag > '%s'",__func__,i,defGetString(def));
				state->rdfTable->cols[i]->language = pstrdup(tag.data);
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
					elog(DEBUG1, "%s: %s '%s'", __func__, def->defname, state->user);
				}

				if (strcmp(def->defname, RDF_USERMAPPING_OPTION_PASSWORD) == 0)
				{					
					state->password = pstrdup(defGetString(def));
					elog(DEBUG1, "%s: %s '*******'", __func__, def->defname);
				}
			}
		}

		ReleaseSysCache(tp);
	}

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

	elog(DEBUG1,"%s: serializing table with %d columns",__func__, state->numcols);
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

	elog(DEBUG1,"  %s: deserializing table with %d columns",__func__, state->numcols);
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

	return state;
}

static size_t WriteMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp)
{
	size_t realsize = size * nmemb;
	struct MemoryStruct *mem = (struct MemoryStruct *)userp;
	char *ptr = repalloc(mem->memory, mem->size + realsize + 1);

	if (!ptr)
		ereport(ERROR,
				(errcode(ERRCODE_FDW_OUT_OF_MEMORY),
				 errmsg("out of memory (repalloc returned NULL)")));

	mem->memory = ptr;
	memcpy(&(mem->memory[mem->size]), contents, realsize);
	mem->size += realsize;
	mem->memory[mem->size] = 0;

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

	elog(DEBUG1, "%s called > '%s'", __func__, url);

	code = curl_url_set(handler, CURLUPART_URL, url, 0);

	curl_url_cleanup(handler);

	elog(DEBUG1, "  %s handler return code: %u", __func__, code);

	if (code != 0)
	{
		elog(DEBUG1, "%s: invalid URL (%u) > '%s'", __func__, code, url);
		return code;
	}

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

	elog(DEBUG1,"%s called > column '%s'",__func__,columnname);

	if(!columnname)
		return NULL;

	for (int i = 0; i < state->numcols; i++)
	{
		if (strcmp(state->rdfTable->cols[i]->name, columnname) == 0)
			return state->rdfTable->cols[i];		
	}

	elog(DEBUG1,"%s: no match found for '%s'",__func__,columnname);
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
	elog(DEBUG1, "%s: looking for columns in the SELECT entry list",__func__);
	foreach(cell, columnlist)
		SetUsedColumns((Expr *)lfirst(cell), state, baserel->relid);

	elog(DEBUG1, "%s: looking for columns used in WHERE conditions",__func__);
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

	elog(DEBUG2, "  %s: called > rowcount = %d/%d", __func__, state->rowcount, state->pagesize);

	if (state->rowcount > state->pagesize)
	{
		elog(DEBUG1, "%s: EOF!", __func__);
		return NULL;
	}

	cell = list_nth_cell(state->records, state->rowcount);
	res = (xmlNodePtr) lfirst(cell);

	elog(DEBUG2,"  %s: returning %d",__func__,state->rowcount);
	
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

	elog(DEBUG1, "  %s: url build > %s?%s", __func__, state->endpoint, url_buffer.data);

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
		elog(DEBUG1, "  %s: timeout > %ld", __func__, state->connect_timeout);
		elog(DEBUG1, "  %s: max retry > %ld", __func__, state->max_retries);

		if (state->proxy)
		{
			elog(DEBUG1, "  %s: proxy URL > '%s'", __func__, state->proxy);

			curl_easy_setopt(state->curl, CURLOPT_PROXY, state->proxy);

			if (strcmp(state->proxy_type, RDF_SERVER_OPTION_HTTP_PROXY) == 0)
			{
				elog(DEBUG1, "  %s: proxy protocol > 'HTTP'", __func__);
				curl_easy_setopt(state->curl, CURLOPT_PROXYTYPE, CURLPROXY_HTTP);
			}
			else if (strcmp(state->proxy_type, RDF_SERVER_OPTION_HTTPS_PROXY) == 0)
			{
				elog(DEBUG1, "  %s: proxy protocol > 'HTTPS'", __func__);
				curl_easy_setopt(state->curl, CURLOPT_PROXYTYPE, CURLPROXY_HTTPS);
			}

			if (state->proxy_user)
			{
				elog(DEBUG1, "  %s: entering proxy user ('%s').", __func__, state->proxy_user);
				curl_easy_setopt(state->curl, CURLOPT_PROXYUSERNAME, state->proxy_user);
			}

			if (state->proxy_user_password)
			{
				elog(DEBUG1, "  %s: entering proxy user's password.", __func__);
				curl_easy_setopt(state->curl, CURLOPT_PROXYUSERPWD, state->proxy_user_password);
			}
		}

		if (state->request_redirect == true)
		{

			elog(DEBUG1, "  %s: setting request redirect: %d", __func__, state->request_redirect);
			curl_easy_setopt(state->curl, CURLOPT_FOLLOWLOCATION, 1L);

			if (state->request_max_redirect)
			{
				elog(DEBUG1, "  %s: setting maxredirs: %ld", __func__, state->request_max_redirect);
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

			elog(DEBUG3, "  %s: xml document \n\n%s", __func__, chunk.memory);
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
		return REQUEST_FAIL;

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
			if (xmlStrcmp(results->name, (xmlChar *)"results") == 0)
			{
				xmlNodePtr record;

				for (record = results->children; record != NULL; record = record->next)
				{
					if (xmlStrcmp(record->name, (xmlChar *)"result") == 0)
					{
						state->records = lappend(state->records, record);
						state->pagesize++;

						elog(DEBUG2, "  %s: appending record %d", __func__, state->pagesize);
					}
				}
			}
		}
	}
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

	elog(DEBUG1, "%s called: expression > %d", __func__, expr->type);

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
				elog(DEBUG1, "%s: column '%s' (%d) required in the SQL query", __func__, state->rdfTable->cols[i]->name, i);
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
	elog(DEBUG1,"%s called",__func__);
	/* 
	 * SPARQL Queries containing SUB SELECTS are not supported. So, if any number
	 * other than 1 is returned from LocateKeyword, this query cannot be parsed.
	 */
	LocateKeyword(state->raw_sparql, "{\n\t> ", RDF_SPARQL_KEYWORD_SELECT," *?\n\t", &keyword_count, 0);
	
	elog(DEBUG1,"%s: SPARQL contains '%d' SELECT clauses.",__func__, keyword_count);

	return LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_GROUPBY," \n\t?", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
	       LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_ORDERBY," \n\t?DA", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
		   LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_LIMIT," \n\t", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
		   LocateKeyword(state->raw_sparql, " \n\t}", RDF_SPARQL_KEYWORD_UNION," \n\t{", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
		   LocateKeyword(state->raw_sparql, " \n\t",  RDF_SPARQL_KEYWORD_HAVING," \n\t(", NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
		   keyword_count == 1;
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

	return LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_COUNT, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
	       LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_SUM, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
		   LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_AVG, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
		   LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_MIN, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
		   LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_MAX, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
		   LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_SAMPLE, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND &&
		   LocateKeyword(expression, open, RDF_SPARQL_AGGREGATE_FUNCTION_GROUPCONCAT, close, NULL, 0) == RDF_KEYWORD_NOT_FOUND;
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

	if(state->sparql_filter) 
		appendStringInfo(&where_graph,"{%s%s}",pstrdup(state->sparql_where),pstrdup(state->sparql_filter));
	else
		appendStringInfo(&where_graph,"{%s}",pstrdup(state->sparql_where));
	/* 
	 * if the raw SPARQL query contains a DISTINCT modifier, this must be added into the 
	 * new SELECT clause 
	 */	
	if (state->is_sparql_parsable == true && 		
		LocateKeyword(state->raw_sparql, " \n", "DISTINCT"," \n?", NULL, 0) != RDF_KEYWORD_NOT_FOUND)
	{
		elog(DEBUG1, "  %s: SPARQL is valid and contains a DISTINCT modifier > pushing down DISTINCT", __func__);
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
		elog(DEBUG1, "  %s: SPARQL is valid and contains a REDUCED modifier > pushing down REDUCED", __func__);
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
		elog(DEBUG1, "  %s: pushing down ORDER BY clause > 'ORDER BY %s'", __func__, state->sparql_orderby);
		appendStringInfo(&sparql, "\nORDER BY%s", pstrdup(state->sparql_orderby));
	}

	/*
	 * Pushing down LIMIT (OFFSET) to the SPARQL query if the SQL query contains them.
	 * If the SPARQL query set in the CREATE TABLE statement already contains a LIMIT,
	 * this won't be pushed.
	 */
	if (state->sparql_limit)
	{
		elog(DEBUG1, "  %s: pushing down LIMIT clause > '%s'", __func__, state->sparql_limit);
		appendStringInfo(&sparql, "\n%s", state->sparql_limit);
	}

	state->sparql = pstrdup(NameStr(sparql));
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
		elog(DEBUG1, "%s%s: nothing before SELECT. Setting keyword_position to 0.", NameStr(idt), __func__);
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
		elog(DEBUG1, "%s%s (%d): keyword '%s' found in position %d. Recalling %s ... ", NameStr(idt), __func__, *count, keyword, keyword_position, __func__);
		LocateKeyword(str, start_chars, keyword, end_chars, count, keyword_position + 1);

		elog(DEBUG1,"%s%s: '%s' search returning postition %d for start position %d", NameStr(idt), __func__, keyword, keyword_position, start_position);
	} 

	return keyword_position;
}

/*
 * CreateTuple
 * -----------
 * Creates tuple with data (or NULLs) to return to the client
 * 
 * slot : Tuple slot
 * state: SPARQL, SERVER and FOREIGN TABLE info
 */
static void CreateTuple(TupleTableSlot *slot, RDFfdwState *state)
{
	xmlNodePtr record;
	xmlNodePtr result;
	regproc typinput;
	MemoryContext old_cxt, tmp_cxt;

	tmp_cxt = AllocSetContextCreate(CurrentMemoryContext,
									"rdf_fdw temporary data",
									ALLOCSET_SMALL_SIZES);

	old_cxt = MemoryContextSwitchTo(tmp_cxt);

	record = FetchNextBinding(state);

	elog(DEBUG2,"%s called ",__func__);

	for (int i = 0; i < state->numcols; i++)
	{
		bool match = false;
		Oid pgtype = state->rdfTable->cols[i]->pgtype;
		char *sparqlvar = state->rdfTable->cols[i]->sparqlvar;
		char *colname = state->rdfTable->cols[i]->name;
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

					xmlBufferPtr buffer = xmlBufferCreate();

					xmlNodeDump(buffer, state->xmldoc, value->children, 0, 0);

					datum = CStringGetDatum((char*) buffer->content);
					slot->tts_isnull[i] = false;

					elog(DEBUG2, "  %s: setting pg column > '%s' (type > '%d'), sparqlvar > '%s'",__func__, colname, pgtype, sparqlvar);
					elog(DEBUG3, "    %s: value > '%s'",__func__, (char *)buffer->content);

					/* find the appropriate conversion function */
					tuple = SearchSysCache1(TYPEOID, ObjectIdGetDatum(pgtype));

					if (!HeapTupleIsValid(tuple)) 
					{
						ereport(ERROR, 
							(errcode(ERRCODE_FDW_INVALID_DATA_TYPE),
								errmsg("cache lookup failed for type %u > column '%s(%s)'", pgtype, name.data,sparqlvar)));
					}

					typinput = ((Form_pg_type)GETSTRUCT(tuple))->typinput;
					ReleaseSysCache(tuple);

					if(pgtype == NUMERICOID || pgtype == TIMESTAMPOID || pgtype == TIMESTAMPTZOID || pgtype == VARCHAROID)
					{

						slot->tts_values[i] = OidFunctionCall3(
												typinput,
												datum,
												ObjectIdGetDatum(InvalidOid),
												Int32GetDatum(pgtypmod));
					}
					else
					{
						slot->tts_values[i] = OidFunctionCall1(typinput, datum);
					}

					xmlBufferFree(buffer);

				}

			}

			pfree(name.data);

			if(prop)
				xmlFree(prop);

		}

		if(!match) 
		{
			elog(DEBUG2, "    %s: setting NULL for column '%s' (%s)",__func__, colname, sparqlvar);
			slot->tts_isnull[i] = true;
			slot->tts_values[i] = PointerGetDatum(NULL);
		}

	}

	MemoryContextSwitchTo(old_cxt);
	MemoryContextDelete(tmp_cxt);

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

	elog(DEBUG1,"%s called: type > %u ",__func__,type);

	/* get the type's output function */
	tuple = SearchSysCache1(TYPEOID, ObjectIdGetDatum(type));
	if (!HeapTupleIsValid(tuple))
	{
		elog(ERROR, "%s: cache lookup failed for type %u",__func__, type);
	}
	typoutput = ((Form_pg_type)GETSTRUCT(tuple))->typoutput;
	ReleaseSysCache(tuple);

	switch (type)
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
			initStringInfo(&result);
			appendStringInfo(&result, "%s", str);
			break;
		case DATEOID:
			str = DeparseDate(datum);
			initStringInfo(&result);
			appendStringInfo(&result, "%s", str);
			break;
		case TIMESTAMPOID:
			str = DeparseTimestamp(datum, false);
			initStringInfo(&result);
			appendStringInfo(&result, "%s", str);
			break;
		case TIMESTAMPTZOID:
			str = DeparseTimestamp(datum, true);
			initStringInfo(&result);
			break;
		default:
			return NULL;
	}

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
static char *DeparseDate(Datum datum)
{
	struct pg_tm datetime_tm;
	StringInfoData s;

	if (DATE_NOT_FINITE(DatumGetDateADT(datum)))
		ereport(ERROR,
				(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
				errmsg("infinite date value cannot be stored")));

	/* get the parts */
	(void)j2date(DatumGetDateADT(datum) + POSTGRES_EPOCH_JDATE,
			&(datetime_tm.tm_year),
			&(datetime_tm.tm_mon),
			&(datetime_tm.tm_mday));

	initStringInfo(&s);
	appendStringInfo(&s, "%04d-%02d-%02d",
			datetime_tm.tm_year > 0 ? datetime_tm.tm_year : -datetime_tm.tm_year + 1,
			datetime_tm.tm_mon, datetime_tm.tm_mday);

	return s.data;
}

/* 
 * DeparseTimestamp
 * ----------------
 * Deparses a 'Datum' of type 'timestamp' and converts it to char*
 * 
 * datum: timestamp to be converted
 * 
 * retrns a string representation of the given timestamp
 */
static char *DeparseTimestamp(Datum datum, bool hasTimezone)
{
	struct pg_tm datetime_tm;
	int32 tzoffset;
	fsec_t datetime_fsec;
	StringInfoData s;

	/* this is sloppy, but DatumGetTimestampTz and DatumGetTimestamp are the same */
	if (TIMESTAMP_NOT_FINITE(DatumGetTimestampTz(datum)))
		ereport(ERROR,
				(errcode(ERRCODE_FDW_INVALID_ATTRIBUTE_VALUE),
				errmsg("infinite timestamp value cannot be stored")));

	/* get the parts */
	tzoffset = 0;
	(void)timestamp2tm(DatumGetTimestampTz(datum),
				hasTimezone ? &tzoffset : NULL,
				&datetime_tm,
				&datetime_fsec,
				NULL,
				NULL);

	initStringInfo(&s);
	if (hasTimezone)
		appendStringInfo(&s, "%04d-%02d-%02dT%02d:%02d:%02d.%06d%+03d:%02d",
			datetime_tm.tm_year > 0 ? datetime_tm.tm_year : -datetime_tm.tm_year + 1,
			datetime_tm.tm_mon, datetime_tm.tm_mday, datetime_tm.tm_hour,
			datetime_tm.tm_min, datetime_tm.tm_sec, (int32)datetime_fsec,
			-tzoffset / 3600, ((tzoffset > 0) ? tzoffset % 3600 : -tzoffset % 3600) / 60);
	else
		appendStringInfo(&s, "%04d-%02d-%02dT%02d:%02d:%02d.%06d",
			datetime_tm.tm_year > 0 ? datetime_tm.tm_year : -datetime_tm.tm_year + 1,
			datetime_tm.tm_mon, datetime_tm.tm_mday, datetime_tm.tm_hour,
			datetime_tm.tm_min, datetime_tm.tm_sec, (int32)datetime_fsec);

	return s.data;
}

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
	char *literalatt = "";
	Const *constant;
	OpExpr *oper;
	ScalarArrayOpExpr *arrayoper;
	Var *variable;
	HeapTuple tuple;
	StringInfoData result;
	Oid leftargtype, rightargtype, schema;
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

	elog(DEBUG1, "%s called > %u", __func__, expr->type);

	if (expr == NULL)
		return NULL;

	switch (expr->type)
	{
	case T_Const:
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
				return NULL;
			else
			{
				initStringInfo(&result);
				appendStringInfo(&result, "%s", c);
			}
		}
		break;
	case T_Var:
		variable = (Var *)expr;

		if (variable->vartype == BOOLOID)
			return NULL;

		index = state->numcols - 1;

		while (index >= 0 && state->rdfTable->cols[index]->pgattnum != variable->varattno)
			--index;

		/* if no foreign table column is found, return NULL */
		if (index == -1)
			return NULL;

		initStringInfo(&result);
		appendStringInfo(&result, "%s", state->rdfTable->cols[index]->name);

		elog(DEBUG1, "  %s (T_Var): index = %d, result = '%s'", __func__, index, state->rdfTable->cols[index]->name);

		break;
	case T_OpExpr:
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
		schema = ((Form_pg_operator)GETSTRUCT(tuple))->oprnamespace;
		ReleaseSysCache(tuple);

		/* ignore operators in other than the pg_catalog schema */
		if (schema != PG_CATALOG_NAMESPACE)
			return NULL;

		/* don't push condition down if the right argument can't be translated into a SPARQL value*/
		if (!canHandleType(rightargtype))
			return NULL;

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

			elog(DEBUG1,"  %s (T_OpExpr): deparsing operand of left expression", __func__);
			left = DeparseExpr(state, foreignrel, linitial(oper->args));
			elog(DEBUG1,"  %s (T_OpExpr): left operand returned => %s", __func__, left);

			if (left == NULL)
			{
				pfree(opername);
				return NULL;
			}

			if (oprkind == 'b')
			{
				StringInfoData left_filter_arg;
				StringInfoData right_filter_arg;
				struct RDFfdwColumn *right_column = (struct RDFfdwColumn *)palloc0(sizeof(struct RDFfdwColumn));
				struct RDFfdwColumn *left_column = (struct RDFfdwColumn *)palloc0(sizeof(struct RDFfdwColumn));
				
				char *right_literal_attribute = "";
				char *left_literal_attribute = "";

				elog(DEBUG1,"  %s (T_OpExpr): deparsing left and right expressions", __func__);
				leftexpr = linitial(oper->args);
				rightexpr = lsecond(oper->args);
				
				elog(DEBUG1,"  %s (T_OpExpr): deparsing operand of right expression, type %u", __func__, rightexpr->type);
				right = DeparseExpr(state, foreignrel, rightexpr);
				

				elog(DEBUG1,"  %s (T_OpExpr): [%s] left type %u, [%s] right type %u", __func__, left, leftexpr->type, right, rightexpr->type);


				if (right == NULL)
					return NULL;

				initStringInfo(&left_filter_arg);
				initStringInfo(&right_filter_arg);

				left_column = GetRDFColumn(state, left);

				if(leftexpr->type == T_Var)
				{
					// left_column = GetRDFColumn(state, left);

					/* return NULL if the column cannot be found or cannot be pushed down */
					if(!left_column || !left_column->pushable)
						return NULL;
					/* set literal type as attribute, e.g. ^^xsd:string, ^^xsd:integer */
					else if (left_column->literaltype)
						left_literal_attribute = left_column->literaltype;
					/* set language as attribute, e.g. de, en, es */
					else if (left_column->language)
						left_literal_attribute = left_column->language;
				}
				
				elog(DEBUG1,"%s: getting right column based on '%s' ... ",__func__, right);
				right_column = GetRDFColumn(state, right);

				if(rightexpr->type == T_Var)
				{					
					// right_column = GetRDFColumn(state, right);
					
					/* return NULL if the column cannot be found or cannot be pushed down */
					if(!right_column || !right_column->pushable)
						return NULL;
					/* set literal type as attribute, e.g. ^^xsd:string, ^^xsd:integer */
					else if (right_column->literaltype)
						right_literal_attribute = right_column->literaltype;
					/* set language as attribute, e.g. de, en, es */
					else if (right_column->language)
						right_literal_attribute = right_column->language;
				}



				/* if the column contains an expression we use it in all FILTER expressions*/
				if(left_column && left_column->expression)
				{
					elog(DEBUG1,"%s: adding expression '%s' for left expression",__func__, left_column->expression);
					appendStringInfo(&left_filter_arg,"%s",left_column->expression);
				}
					
				/* check if the argument is a string (T_Const) */
				else if(IsStringDataType(leftargtype) && leftexpr->type == T_Const)
				{
					/* 
					 * if the argument is a IRI/URI we must wrap it with IRI(), so that it
					 * can be handled as such in the FILTER expressions.
					 */
					if (right_column && right_column->nodetype && strcmp(right_column->nodetype, RDF_COLUMN_OPTION_NODETYPE_IRI) == 0)
						appendStringInfo(&left_filter_arg,"IRI(\"%s\")",left);
					/* 
					 * we ignore the attribute of the left side if the right side argument's 
					 * language is set to * (all languages) 
					 */
					else if(strcmp(right_literal_attribute,"@*") == 0)
						appendStringInfo(&left_filter_arg,"\"%s\"",left);					
					/* add the attribute to the argument as set in the CREATE TABLE statement */
					else
						appendStringInfo(&left_filter_arg,"\"%s\"%s",left, right_literal_attribute);
				}
				/* check if the argument is a column */
				else if(left_column && leftexpr->type == T_Var)
				{
					/* 
					 * we wrap the column name (sparqlvar!) with STR() if the column's language
					 * is set ti * (all languages)
					 */
					if(strcmp(left_literal_attribute,"@*") == 0)
						appendStringInfo(&left_filter_arg,"STR(%s)",left_column->sparqlvar);
					/* set the sparqlvar to the FILTER expression */
					else
						appendStringInfo(&left_filter_arg,"%s",left_column->sparqlvar);
				}
				else if(leftexpr->type == T_FuncExpr)
				{
					/* We try to resolve the column name <-> sparql variable one last time */
					left_column = GetRDFColumn(state, left);

					if(left_column)
						appendStringInfo(&left_filter_arg, "%s", left_column->sparqlvar);
					else
						appendStringInfo(&left_filter_arg, "%s", left);
				} 
				else
				{
					appendStringInfo(&left_filter_arg, "%s", left);
				}
					





				/* if the column contains an expression we use it in all FILTER expressions*/
				if(right_column && right_column->expression)
				{
					elog(DEBUG1,"%s: adding expression '%s' for left expression",__func__, right_column->expression);
					appendStringInfo(&right_filter_arg,"%s",right_column->expression);
				}
				/* check if the argument is a string (T_Const) */
				else if(IsStringDataType(rightargtype) && rightexpr->type == T_Const)
				{	
					/* 
					 * if the argument is a IRI/URI we must wrap it with IRI(), so that it
					 * can be handled as such in the FILTER expressions.
					 */
					if(left_column && left_column->nodetype && strcmp(left_column->nodetype, RDF_COLUMN_OPTION_NODETYPE_IRI) == 0)
						appendStringInfo(&right_filter_arg, "IRI(\"%s\")",right);
					/* 
					 * we ignore the attribute of the right side if the left side argument's 
					 * language is set to * (all languages) 
					 */
					else if(strcmp(left_literal_attribute,"@*") == 0)
						appendStringInfo(&right_filter_arg, "\"%s\"", right);
					/* add the attribute to the argument as set in the CREATE TABLE statement */
					else					
						appendStringInfo(&right_filter_arg,"\"%s\"%s", right, left_literal_attribute);
				}
				else if(rightexpr->type == T_Var)
				{
					/* 
					 * we wrap the column name (sparqlvar!) with STR() if the column's language
					 * is set ti * (all languages)
					 */
					if(right_column && strcmp(right_literal_attribute, "@*") == 0)
						appendStringInfo(&right_filter_arg, "STR(%s)", right_column->sparqlvar);
					/* set the sparqlvar to the FILTER expression */
					else
						appendStringInfo(&right_filter_arg,"%s", right_column->sparqlvar);
				}
				else if(rightexpr->type == T_FuncExpr)
				{ 
					/* We try to resolve the column name <-> sparql variable one last time */
					right_column = GetRDFColumn(state, right);

					if(right_column)
						appendStringInfo(&right_filter_arg, "%s", right_column->sparqlvar);
					else
						appendStringInfo(&right_filter_arg, "%s", right);
				}
				else
					appendStringInfo(&right_filter_arg, "%s", right);

 
				elog(DEBUG1,"  %s (T_OpExpr): left argument converted: '%s' => '%s'", __func__, left, NameStr(left_filter_arg));
				elog(DEBUG1,"  %s (T_OpExpr): oper  => '%s'", __func__, opername);
				elog(DEBUG1,"  %s (T_OpExpr): right argument converted: '%s' => '%s'", __func__, right,  NameStr(right_filter_arg));


				if (strcmp(opername, "~~") == 0 || strcmp(opername, "~~*") == 0 || strcmp(opername, "!~~") == 0 || strcmp(opername, "!~~*") == 0)
				{
					/* 
					 * If the left and right side arguments are not respectively T_Var and 
					 * T_Const it is not safe to push down the REGEX FILTER. We then let
					 * the client to deal with it.
					 */
					if(leftexpr->type != T_Var && rightexpr->type != T_Const)
						return NULL;

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
				elog(DEBUG1, "  %s (T_OpExpr): unary operator not supported", __func__);
			}
		}
		else
		{
			elog(DEBUG1, "  %s (T_OpExpr): operator cannot be translated > '%s' ", __func__, opername);
			return NULL;
		}

		break;
	case T_BooleanTest:
		btest = (BooleanTest *)expr;

		if (btest->arg->type != T_Var)
			return NULL;

		variable = (Var *)btest->arg;

		index = state->numcols - 1;
		while (index >= 0 && state->rdfTable->cols[index]->pgattnum != variable->varattno)
			--index;

		arg = state->rdfTable->cols[index]->name;

		if (arg == NULL)
			return NULL;

		col = GetRDFColumn(state, arg);

		if (!col)
			return NULL;

		if (!col->pushable)
			return NULL;

		initStringInfo(&result);

		switch (btest->booltesttype)
		{
		case IS_TRUE:
			appendStringInfo(&result, "%s = \"true\"%s",
							 col->expression ? col->expression : col->sparqlvar,
							 col->literaltype ? col->literaltype : "");
			break;
		case IS_NOT_TRUE:
			appendStringInfo(&result, "%s != \"true\"%s",
							 col->expression ? col->expression : col->sparqlvar,
							 col->literaltype ? col->literaltype : "");
			break;
		case IS_FALSE:
			appendStringInfo(&result, "%s = \"false\"%s",
							 col->expression ? col->expression : col->sparqlvar,
							 col->literaltype ? col->literaltype : "");
			break;
		case IS_NOT_FALSE:
			appendStringInfo(&result, "%s != \"false\"%s",
							 col->expression ? col->expression : col->sparqlvar,
							 col->literaltype ? col->literaltype : "");
			break;
		default:
			return NULL;
		}

		break;
	case T_ScalarArrayOpExpr:
		arrayoper = (ScalarArrayOpExpr *)expr;

		/* get operator name, left argument type and schema */
		tuple = SearchSysCache1(OPEROID, ObjectIdGetDatum(arrayoper->opno));
		if (!HeapTupleIsValid(tuple))
		{
			elog(ERROR, "cache lookup failed for operator %u", arrayoper->opno);
		}
		opername = pstrdup(((Form_pg_operator)GETSTRUCT(tuple))->oprname.data);
		leftargtype = ((Form_pg_operator)GETSTRUCT(tuple))->oprleft;
		schema = ((Form_pg_operator)GETSTRUCT(tuple))->oprnamespace;
		ReleaseSysCache(tuple);

		/* ignore operators in other than the pg_catalog schema */
		if (schema != PG_CATALOG_NAMESPACE)
			return NULL;

		/* don't try to push down anything but IN and NOT IN expressions */
		if ((strcmp(opername, "=") != 0 || !arrayoper->useOr) && (strcmp(opername, "<>") != 0 || arrayoper->useOr))
			return NULL;

		if (!canHandleType(leftargtype))
			return NULL;

		left = DeparseExpr(state, foreignrel, linitial(arrayoper->args));
		if (left == NULL)
			return NULL;

		col = GetRDFColumn(state, left);
		if (!col)
			return NULL;

		if (!col->pushable)
			return NULL;

		initStringInfo(&result);

		if (strcmp(opername, "=") == 0)
			appendStringInfo(&result, "%s IN (", !col->expression ? col->sparqlvar : col->expression);
		else
			appendStringInfo(&result, "%s NOT IN (", !col->expression ? col->sparqlvar : col->expression);

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
				return NULL;
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

					if (col->literaltype)
						literalatt = col->literaltype;

					if (col->language)
						literalatt = col->language;

					if (leftargtype == TEXTOID ||
						leftargtype == VARCHAROID ||
						leftargtype == CHAROID ||
						leftargtype == NAMEOID ||
						leftargtype == BOOLOID ||
						leftargtype == DATEOID ||
						leftargtype == TIMESTAMPOID ||
						leftargtype == TIMESTAMPTZOID)
						appendStringInfo(&result, "%s\"%s\"%s",
										 first_arg ? "" : ", ", c, literalatt);
					else
						appendStringInfo(&result, "%s%s%s",
										 first_arg ? "" : ", ", c, literalatt);

					/* append the argument */
					first_arg = false;
				}
				array_free_iterator(iterator);

				/* don't push down empty arrays, since the semantics for NOT x = ANY(<empty array>) differ */
				if (first_arg)
					return NULL;
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
				return NULL;
#endif
			/* punt on anything but ArrayExpr (e.g, parameters) */
			if (arraycoerce->arg->type != T_ArrayExpr)
				return NULL;

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
					return NULL;

				/* append the argument */
				appendStringInfo(&result, "%s%s", first_arg ? "" : ", ", element);
				first_arg = false;
			}

			/* don't push down empty arrays, since the semantics for NOT x = ANY(<empty array>) differ */
			if (first_arg)
				return NULL;

			break;
		default:
			return NULL;
		}

		/* parentheses close the FILTER expression */
		appendStringInfo(&result, ")");

		break;
	case T_FuncExpr:

		func = (FuncExpr *)expr;
		
		elog(DEBUG1,"  %s (T_FuncExpr): called",__func__);

		if (!canHandleType(func->funcresulttype))
			return NULL;

		/* do nothing for implicit casts */
		if (func->funcformat == COERCE_IMPLICIT_CAST)
		{
			elog(DEBUG1,"  %s (T_FuncExpr): implicit cast! ",__func__);
			return DeparseExpr(state, foreignrel, linitial(func->args));
			//return NULL;
		}

		/* get function name and schema */
		tuple = SearchSysCache1(PROCOID, ObjectIdGetDatum(func->funcid));
		if (!HeapTupleIsValid(tuple))
		{
			elog(ERROR, "%s (T_FuncExpr): cache lookup failed for function %u",__func__, func->funcid);
		}

		opername = pstrdup(((Form_pg_proc)GETSTRUCT(tuple))->proname.data);
		schema = ((Form_pg_proc)GETSTRUCT(tuple))->pronamespace;
		ReleaseSysCache(tuple);

		elog(DEBUG1,"  %s (T_FuncExpr): opername = %s",__func__, opername);

		/*
		 * ignore functions that are not in the pg_catalog schema and are
		 * not pushable.
		 */
		if (schema != PG_CATALOG_NAMESPACE && !IsFunctionPushable(opername))
			return NULL;

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
				elog(DEBUG1, "  %s (T_FuncExpr): deparsing arguments for '%s'", __func__, opername);
				arg = DeparseExpr(state, foreignrel, ex);
				
				if(!arg)
				{
					elog(DEBUG1, "  %s (T_FuncExpr): arg is NULL (opername = %s)", __func__, opername);
					pfree(opername);
					return NULL;
				}

				if(!initarg)
				{
					/* 
					 * We discard any further parameters of ROUND, as its equivalent
					 * in SPARQL expects a single parameter.
					 */
					if(strcmp(opername, "round") == 0)
						break;
					else if(strcmp(opername, "extract") != 0)
						appendStringInfo(&args, "%s", ", ");
				}

				col = GetRDFColumn(state, arg);

				if(col)
				{
					if(!IsSPARQLStringFunction(opername))
						appendStringInfo(&args, "%s",  !col->expression ? col->sparqlvar : col->expression);
					else
						appendStringInfo(&args, "STR(%s)", !col->expression ? col->sparqlvar : col->expression);
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
							elog(DEBUG1, "  %s (T_FuncExpr): EXTRACT field cannot be converted to SPARQL: '%s'", __func__, arg);
							pfree(opername);
							return NULL;
						}

						else if(IsStringDataType(ct->consttype))
							appendStringInfo(&args, "\"%s\"", arg);	
						else
							appendStringInfo(&args, "%s", arg);
					}
					else
						appendStringInfo(&args, "%s", arg);

				}
				
				initarg = false;

			}

			if(strcmp(opername, "upper") == 0)
				appendStringInfo(&result, "UCASE(%s)", NameStr(args));
			else if(strcmp(opername, "lower") == 0)
				appendStringInfo(&result, "LCASE(%s)", NameStr(args));
			else if(strcmp(opername, "length") == 0)
				appendStringInfo(&result, "STRLEN(%s)", NameStr(args));
			else if(strcmp(opername, "abs") == 0)
				appendStringInfo(&result, "ABS(%s)", NameStr(args));
			else if(strcmp(opername, "round") == 0)
				appendStringInfo(&result, "ROUND(%s)", NameStr(args));
			else if(strcmp(opername, "floor") == 0)
				appendStringInfo(&result, "FLOOR(%s)", NameStr(args));
			else if(strcmp(opername, "ceil") == 0)
				appendStringInfo(&result, "CEIL(%s)", NameStr(args));
			else if(strcmp(opername, "strstarts") == 0 || strcmp(opername, "starts_with") == 0)
				appendStringInfo(&result, "STRSTARTS(%s)", NameStr(args));
			else if(strcmp(opername, "strends") == 0)
				appendStringInfo(&result, "STRENDS(%s)", NameStr(args));
			else if(strcmp(opername, "strbefore") == 0)
				appendStringInfo(&result, "STRBEFORE(%s)", NameStr(args));
			else if(strcmp(opername, "strafter") == 0)
				appendStringInfo(&result, "STRAFTER(%s)", NameStr(args));
			else if(strcmp(opername, "substring") == 0)
				appendStringInfo(&result, "SUBSTR(%s)", NameStr(args));
			else if(strcmp(opername, "md5") == 0)
				appendStringInfo(&result, "MD5(%s)", NameStr(args));
			else if(strcmp(opername, "extract") == 0)
				appendStringInfo(&result, "%s(%s)", extract_type, NameStr(args));
			else
				return NULL;
			
			pfree(args.data);
		}
		/* In PostgreSQL 11 EXTRACT is internally called as DATE_PART */
		else if(strcmp(opername, "date_part") == 0)
		{
			Expr *field = linitial(func->args);
			char *date_part_type = "";

			elog(DEBUG1, "  %s (T_FuncExpr): deparsing FIELD for '%s'", __func__, opername);
			date_part_type = DeparseExpr(state, foreignrel, field);
			
			if(!date_part_type)
			{
				elog(DEBUG1, "  %s (T_FuncExpr): date_part_type is NULL (opername = %s)", __func__, opername);
				pfree(opername);
				return NULL;
			}

			elog(DEBUG1, "  %s (T_FuncExpr): date_part FIELD '%s'", __func__, date_part_type);

			date_part_type = FormatSQLExtractField(date_part_type);

			if(date_part_type)
			{
				char * val;
				
				elog(DEBUG1, "  %s (T_FuncExpr): deparsing VALUE for '%s'", __func__, opername);
				val = DeparseExpr(state, foreignrel, lsecond(func->args));

				col = GetRDFColumn(state, val);


				initStringInfo(&result);

				if(col)
					appendStringInfo(&result, "%s(%s)", date_part_type, !col->expression ? col->sparqlvar : col->expression);
				else
					appendStringInfo(&result, "%s(\"%s\")", date_part_type, val);
			}
			else
			{	
				pfree(opername);
				return NULL;
			}

		}
		else if(strcmp(opername, "timestamp") == 0)
		{
			char *value;
			Expr *ex = linitial(func->args);
			
			value = DeparseExpr(state, foreignrel, ex);

			if(!value)
				return NULL;

			initStringInfo(&result);
			appendStringInfo(&result, "%s",  value);

			elog(DEBUG1, "  %s (T_FuncExpr): returning VALUE for '%s': '%s'", __func__, opername,NameStr(result));
		}
		else
		{
			elog(DEBUG1, "  %s (T_FuncExpr): function '%s' is not pushable", __func__, opername);
			return NULL;
		}

		pfree(opername);
		break;
	default:
		elog(DEBUG1, "  %s: expression not supported > %u", __func__, expr->type);
		return NULL;
	}

	elog(DEBUG1,"\n");

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

	return where_clause.data;
}


static char *DeparseSPARQLWhereGraphPattern(struct RDFfdwState *state)
{
	int where_position = -1;
	int where_size = -1;
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

	return pnstrdup(state->raw_sparql + where_position, where_size);
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
			return false;

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
			return false;

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

			if (pathkey->pk_strategy == BTLessStrategyNumber)
				appendStringInfo(&orderedquery, " ASC (%s)", (GetRDFColumn(state,sort_clause))->sparqlvar);
			else
				appendStringInfo(&orderedquery, " DESC (%s)", (GetRDFColumn(state,sort_clause))->sparqlvar);

			//delim = ", ";

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
		return orderedquery.data;
	else
	{
		elog(DEBUG1,"  %s: unable to deparse ORDER BY clause ",__func__);
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
		elog(DEBUG1,"  %s: LIMIT won't be pushed down, as SQL query contains aggregators.",__func__);
		return NULL;
	}

	/* don't push down LIMIT (OFFSET) if the query contains DISTINCT */
	if (root->parse->distinctClause != NULL) {
		elog(DEBUG1,"  %s: LIMIT won't be pushed down, as SQL query contains DISTINCT.",__func__);
		return NULL;
	}

	/*
	 * disables LIMIT push down if any WHERE conidition cannot be be pushed down, otherwise you'll
	 * be scratching your head forever wondering why some data are missing from the result set.
	 */
	if (state->has_unparsable_conds)
	{
		elog(DEBUG1,"  %s: LIMIT won't be pushed down, as there are WHERE conditions that could not be translated.",__func__);
		return NULL;
	}

	/* only push down constant LIMITs that are not NULL */
	if (root->parse->limitCount != NULL && IsA(root->parse->limitCount, Const))
	{
		Const *limit = (Const *)root->parse->limitCount;

		if (limit->constisnull)
			return NULL;

		limit_val = DatumToString(limit->constvalue, limit->consttype);
	}
	else
		return NULL;

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
	for (int i = 0; str[i] != '\0'; i++)
		if (isspace((unsigned char)str[i]))
			return true;

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
	if (str[0] != '?' && str[0] != '$')
		return false;

	for (int i = 1; str[i] != '\0'; i++)
		if (!isalnum(str[i]) && str[i] != '_')
			return false;

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

	elog(DEBUG1,"%s called with string => %s", __func__, str);

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

	elog(DEBUG1,"%s returning => %s",__func__,NameStr(res));

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
	return 
		type == TEXTOID ||
		type == VARCHAROID ||
		type == CHAROID ||
		type == NAMEOID ||
		type == DATEOID ||
		type == TIMESTAMPOID ||
		type == TIMESTAMPTZOID ||
		type == NAMEOID;
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
	return 
		strcmp(funcname, "abs") == 0 ||
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
		strcmp(funcname, "extract") == 0 ||
		strcmp(funcname, "substring") == 0;
}

/*
 * IsSPARQLStringFunction
 * ---------------
 * This function is a workaround solely written to tell which SPARQL
 * functions expect parameters of type string, so that they can be properly
 * wrapped with STR().
 *
 * funcname: name of the PostgreSQL function
 *
 * returns true if the function expects a string parameter or false otherwise
 */
static bool IsSPARQLStringFunction(char *funcname)
{
	return 
		strcmp(funcname, "upper") == 0 ||
		strcmp(funcname, "lower") == 0 ||
		strcmp(funcname, "length") == 0 ||
		strcmp(funcname, "starts_with") == 0 ||
		strcmp(funcname, "strstarts") == 0 ||
		strcmp(funcname, "strends") == 0 ||
		strcmp(funcname, "strbefore") == 0 ||
		strcmp(funcname, "strafter") == 0 ||
		strcmp(funcname, "md5") == 0 ||
		strcmp(funcname, "substring") == 0;
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
		res = NULL;

	return res;
}