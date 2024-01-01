
/**********************************************************************
 *
 * rdf_fdw - Foreign-data Wrapper for RDF Triplestores
 *
 * rdf_fdw is free software: you can redistribute it and/or modify
 * it under the terms of the MIT Licence.
 *
 * Copyright (C) 2022-2024 University of Münster, Germany
 * Written by Jim Jones <jim.jones@uni-muenster.de>
 *
 **********************************************************************/

#include "postgres.h"
#include "fmgr.h"
#include "foreign/fdwapi.h"
#include "optimizer/restrictinfo.h"
#include "optimizer/planmain.h"
#include "utils/rel.h"

#include "access/htup_details.h"
#include "access/sysattr.h"
#include "access/reloptions.h"

#if PG_VERSION_NUM >= 120000
#include "access/table.h"
#endif

#include "foreign/foreign.h"
#include "commands/defrem.h"

#include "nodes/makefuncs.h"
#include "nodes/nodeFuncs.h"
#include "nodes/pg_list.h"
#include "optimizer/pathnode.h"

#include <stdio.h>
#include <stdlib.h>
#include <curl/curl.h>
#include <utils/builtins.h>
#include <utils/array.h>
#include <commands/explain.h>
#include <libxml/tree.h>
#include <catalog/pg_collation.h>
#include <funcapi.h>
#include "lib/stringinfo.h"
#include <utils/lsyscache.h>
#include "utils/datetime.h"
#include "utils/timestamp.h"
#include "utils/formatting.h"
#include "catalog/pg_operator.h"
#include "utils/syscache.h"
#include "catalog/pg_foreign_table.h"
#include "catalog/pg_foreign_server.h"
#include "catalog/pg_user_mapping.h"
#include "catalog/pg_type.h"
#include "access/reloptions.h"
#include "catalog/pg_namespace.h"

#if PG_VERSION_NUM < 120000
#include "nodes/relation.h"
#include "optimizer/var.h"
#include "utils/tqual.h"
#else
#include "nodes/pathnodes.h"
#include "optimizer/optimizer.h"
#include "access/heapam.h"
#endif
#include "utils/date.h"


#define REL_ALIAS_PREFIX    "r"
/* Handy macro to add relation name qualification */
#define ADD_REL_QUALIFIER(buf, varno)   \
		appendStringInfo((buf), "%s%d.", REL_ALIAS_PREFIX, (varno))

#define FDW_VERSION "0.0.1-dev"
#define REQUEST_SUCCESS 0
#define REQUEST_FAIL -1
#define RDF_XML_NAME_TAG "name"
#define RDF_DEFAULT_CONNECTTIMEOUT 300
#define RDF_DEFAULT_MAXRETRY 3
#define RDF_KEYWORD_NOT_FOUND -1
#define RDF_DEFAULT_FORMAT "application/sparql-results+xml"
#define RDF_DEFAULT_QUERY_PARAM "query"

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

#define RDF_TABLE_OPTION_SPARQL "sparql"
#define RDF_TABLE_OPTION_LOG_SPARQL "log_sparql"
#define RDF_TABLE_OPTION_ENABLE_PUSHDOWN "enable_pushdown"

#define RDF_COLUMN_OPTION_VARIABLE "variable"
#define RDF_COLUMN_OPTION_EXPRESSION "expression"

#define RDF_SPARQL_KEYWORD_FROM "FROM"
#define RDF_SPARQL_KEYWORD_NAMED "NAMED"
#define RDF_SPARQL_KEYWORD_PREFIX "PREFIX"
#define RDF_SPARQL_KEYWORD_SELECT "SELECT"
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

/*
 * This macro is used by DeparseExpr to identify PostgreSQL
 * types that can be translated to SPARQL
 */
#define canHandleType(x) ((x) == TEXTOID || (x) == CHAROID || (x) == BPCHAROID \
			|| (x) == VARCHAROID || (x) == NAMEOID || (x) == INT8OID || (x) == INT2OID \
			|| (x) == INT4OID || (x) == FLOAT4OID || (x) == FLOAT8OID \
			|| (x) == NUMERICOID || (x) == DATEOID || (x) == TIMESTAMPOID || (x) == TIMESTAMPTZOID)


PG_MODULE_MAGIC;

typedef struct RDFfdwState
{
	int numcols;                 /* Total number of columns in the foreign table. */
	int rowcount;                /* Number of rows currently returned to the client */
	int pagesize;                /* Total number of records retrieved from the SPARQL endpoint*/
	char *sparql_prefixes;       /* SPARQL PREFIX entries */
	char *sparql_select;         /* SPARQL SELECT containing the columns / variables used in the SQL query */
	char *sparql_from;           /* SPARQL FROM clause entries*/
	char *sparql_where;          /* SPARQL WHERE clause */
	char *sparql_filter;         /* SPARQL FILTER clauses based on SQL WHERE conditions */
	char *sparql_orderby;        /* SPARQL ORDER BY clause based on the SQL ORDER BY clause */
	char *sparql_limit;          /* SPARQL LIMIT clause based on SQL LIMIT and FETCH clause */
	char *raw_sparql;            /* Raw SPARQL query set in the CREATE TABLE statement */
	char *endpoint;              /* SPARQL endpoint set in the CREATE SERVER statement*/
	char *query_param;           /* SPARQL query POST parameter used by the endpoint */
	char *format;                /* Format in which the RDF triplestore has to reply */
	char *proxy;                 /* Proxy for HTTP requests, if necessary. */
	char *proxyType;             /* Proxy protocol (HTTPS, HTTP). */
	char *proxyUser;             /* User name for proxy authentication. */
	char *proxyUserPassword;     /* Password for proxy authentication. */
	char *customParams;          /* Custom parameters used to compose the request URL */
	bool requestRedirect;        /* Enables or disables URL redirecting. */
	bool enablePushdown;         /* Enables or disables pushdown of SQL commands */
	bool is_sparql_parsable;     /* Marks the query is or not for pushdown*/
	bool log_sparql;             /* Enables or disables logging SPARQL queries as NOTICE */
	long requestMaxRedirect;     /* Limit of how many times the URL redirection (jump) may occur. */
	long connectTimeout;         /* Timeout for SPARQL queries */
	long maxretries;             /* Number of re-try attemtps for failed SPARQL queries */
	xmlDocPtr xmldoc;            /* XML document where the result of SPARQL queries will be stored */	
	Oid foreigntableid;          /* FOREIGN TABLE oid */
	List *records;               /* List of records retrieved from a SPARQL request (after parsing 'xmldoc')*/
	struct RDFfdwTable *rdfTable;/* All necessary information of the FOREIGN TABLE used in a SQL statement */
	StringInfoData sparql;       /* Final SPARQL query sent to the endpoint (after pusdhown) */
	List *remote_conds;          /* Conditions that can be pushed down as SPARQL */
	List *local_conds;           /* Conditions that cannot be pushed down as SPARQL */
} RDFfdwState;

typedef struct RDFfdwTable
{	
	char *name;                  /* FOREIGN TABLE name */
	int   nfdwcols;              /* Total number of columns */
	struct RDFfdwColumn **cols;  /* List of columns of a FOREIGN TABLE */

} RDFfdwTable;

typedef struct RDFfdwColumn
{	
	char *name;                  /* Column name */
	char *sparqlvar;             /* Column OPTION 'variable'*/
	char *expression;            /* Column OPTION 'expression' */
	Oid  pgtype;                 /* PostgreSQL data type */
	int  pgtypmod;               /* PostgreSQL type modifier */
	int  pgattnum;               /* PostgreSQL attribute number */
	bool used;                   /* Is the column used in the current SQL query? */
	bool pushable;               /* Marks a column as safe or not to pushdown */

} RDFfdwColumn;

typedef struct RDFfdwTableOptions
{
	Oid foreigntableid;

} RDFfdwTableOptions;

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
	/* Foreign Tables */
	{RDF_TABLE_OPTION_SPARQL, ForeignTableRelationId, true, false},
	{RDF_TABLE_OPTION_LOG_SPARQL, ForeignTableRelationId, false, false},
	{RDF_TABLE_OPTION_ENABLE_PUSHDOWN, ForeignTableRelationId, false, false},
	/* Options for Foreign Table's Columns */
	{RDF_COLUMN_OPTION_VARIABLE, AttributeRelationId, true, false},
	{RDF_COLUMN_OPTION_EXPRESSION, AttributeRelationId, false, false},
	/* EOList option */
	{NULL, InvalidOid, false, false}
};

extern Datum rdf_fdw_handler(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_validator(PG_FUNCTION_ARGS);
extern Datum rdf_fdw_version(PG_FUNCTION_ARGS);

PG_FUNCTION_INFO_V1(rdf_fdw_handler);
PG_FUNCTION_INFO_V1(rdf_fdw_validator);
PG_FUNCTION_INFO_V1(rdf_fdw_version);

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

static int ExecuteSPARQL(RDFfdwState *state);
static void CreateTuple(TupleTableSlot *slot, RDFfdwState *state);
static void LoadRDFData(RDFfdwState *state);
static xmlNodePtr FetchNextBinding(RDFfdwState *state);
static int CheckURL(char *url);
static void InitSession(struct RDFfdwState *state,  RelOptInfo *baserel, PlannerInfo *root);
static struct RDFfdwColumn *GetRDFColumn(struct RDFfdwState *state, char *columnname);
static int LocateKeyword(char *str, char *start_chars, char *keyword, char *end_chars, int *count, int start_position);
static void CreateSPARQL(RDFfdwState *state, PlannerInfo *root);
static void SetUsedColumns(Expr *expr, struct RDFfdwState *state, int foreignrelid);
static bool IsSPARQLParsable(struct RDFfdwState *state);
static bool IsExpressionPushable(char *expression);
static char *DeparseDate(Datum datum);
static char *DeparseTimestamp(Datum datum, bool hasTimezone);
static char *DeparseSQLLimit(struct RDFfdwState *state, PlannerInfo *root, RelOptInfo *baserel);
static char *DeparseSQLWhereConditions(struct RDFfdwState *state, RelOptInfo *baserel);
static char *DatumToString(Datum datum, Oid type);
static char *DeparseExpr(struct RDFfdwState *state, RelOptInfo *foreignrel, Expr *expr);
static char *DeparseSQLOrderBy( struct RDFfdwState *state, PlannerInfo *root, RelOptInfo *baserel);
static char *DeparseSPARQLFrom(char *raw_sparql);
static char *DeparseSPARQLPrefix(char *raw_sparql);


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
	appendStringInfo(&buffer, " libxml = %s,", LIBXML_DOTTED_VERSION);
	appendStringInfo(&buffer, " libcurl = %s", curl_version());

	PG_RETURN_TEXT_P(cstring_to_text(buffer.data));
}

Datum rdf_fdw_validator(PG_FUNCTION_ARGS)
{
	List *options_list = untransformRelOptions(PG_GETARG_DATUM(0));
	Oid catalog = PG_GETARG_OID(1);
	ListCell *cell;
	struct RDFfdwOption *opt;
	
	/* Initialize found state to not found */
	for (opt = valid_options; opt->optname; opt++)
	{
		opt->optfound = false;
	}

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
					
					//TODO: check if the SPARQL variable is valid.

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

	ForeignTable *ft = GetForeignTable(foreigntableid);	
	RDFfdwTableOptions *opts = (RDFfdwTableOptions *)palloc0(sizeof(RDFfdwTableOptions));
	
	elog(DEBUG1, "%s called", __func__);
			
	opts->foreigntableid = ft->relid;
	baserel->fdw_private = opts;
}

static void rdfGetForeignPaths(PlannerInfo *root, RelOptInfo *baserel, Oid foreigntableid)
{

	Path *path = (Path *)create_foreignscan_path(root, baserel,
												 NULL,				/* default pathtarget */
												 baserel->rows,		/* rows */
												 1,					/* startup cost */
												 1 + baserel->rows, /* total cost */
												 NIL,				/* no pathkeys */
												 NULL,				/* no required outer relids */
												 NULL,				/* no fdw_outerpath */
												 NIL);				/* no fdw_private */
	add_path(baserel, path);
}

static ForeignScan *rdfGetForeignPlan(PlannerInfo *root, RelOptInfo *baserel, Oid foreigntableid, ForeignPath *best_path, List *tlist, List *scan_clauses, Plan *outer_plan)
{

	List *fdw_private;
	RDFfdwTableOptions *opts = baserel->fdw_private;
	RDFfdwState *state = (RDFfdwState *)palloc0(sizeof(RDFfdwState));
	
	state->foreigntableid = opts->foreigntableid;

	InitSession(state, baserel, root);

	if(!state->enablePushdown) 
	{
		initStringInfo(&state->sparql);
		appendStringInfo(&state->sparql,"%s",state->raw_sparql);		
		elog(DEBUG1,"%s: Pushdown feature disabled. SPARQL query won't be modified.",__func__);
	} 
	else if(!state->is_sparql_parsable) 
	{
		initStringInfo(&state->sparql);
		appendStringInfo(&state->sparql,"%s",state->raw_sparql);		
		elog(DEBUG1,"%s: SPARQL cannot be fully parsed. The raw SPARQL will be used and all filters will be applied locally.",__func__);
	}
	else 
	{
		CreateSPARQL(state, root);
	}
	

	fdw_private = list_make1(state);

	scan_clauses = extract_actual_clauses(scan_clauses, false);

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
	RDFfdwState *state = (RDFfdwState *)linitial(fs->fdw_private);

	if (eflags & EXEC_FLAG_EXPLAIN_ONLY)
		return;

	xmlInitParser();
	
	LoadRDFData(state);

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
		pfree(state);
		xmlCleanupParser();

		elog(DEBUG2,"  %s: no rows left (%d/%d)",__func__,state->rowcount , state->pagesize);
	}

	return slot;
	
}

static void rdfReScanForeignScan(ForeignScanState *node)
{
}

static void rdfEndForeignScan(ForeignScanState *node)
{
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

	Assert(contents);

	/* is it a "content-type" entry? "*/	
	if (strncasecmp(contents, sparqlxml, 13) == 0)
	{

		if (strncasecmp(contents, sparqlxml, strlen(sparqlxml)) != 0 &&
			strncasecmp(contents, sparqlxmlutf8, strlen(sparqlxmlutf8)) != 0)
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

	ForeignTable *ft = GetForeignTable(state->foreigntableid);
	ForeignServer *server = GetForeignServer(ft->serverid);	
	List *columnlist = baserel->reltarget->exprs;
	List *conditions = baserel->baserestrictinfo;
	ListCell *cell;
	int where_position = -1;
	int where_size = -1;
	StringInfoData select;

#if PG_VERSION_NUM < 130000
	Relation rel = heap_open(ft->relid, NoLock);
#else
	Relation rel = table_open(state->foreigntableid, NoLock);
#endif
	
	elog(DEBUG1,"%s called",__func__);

	state->enablePushdown = true;
	state->log_sparql = false;
	state->query_param = RDF_DEFAULT_QUERY_PARAM;
	state->format = RDF_DEFAULT_FORMAT;
	state->connectTimeout = RDF_DEFAULT_CONNECTTIMEOUT;
	state->maxretries = RDF_DEFAULT_MAXRETRY;	
	state->numcols = rel->rd_att->natts;

	/* 
	 *Loading FOREIGN TABLE strucuture (columns and their OPTION values)
	 */
	state->rdfTable = (struct RDFfdwTable *) palloc0(sizeof(struct RDFfdwTable));
	state->rdfTable->cols = (struct RDFfdwColumn **) palloc0(sizeof(struct RDFfdwColumn*) * state->numcols);

	for (int i = 0; i < state->numcols; i++)
	{
		List *options = GetForeignColumnOptions(state->foreigntableid, i + 1);
		ListCell *lc;

		state->rdfTable->cols[i] = (struct RDFfdwColumn *)palloc0(sizeof(struct RDFfdwColumn));
		state->rdfTable->cols[i]->pushable = true;

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
				elog(DEBUG1,"  %s: (%d) is expression pushable? > '%s'",__func__,i,state->rdfTable->cols[i]->pushable ? "true" : "false");
			}
		
		}

		elog(DEBUG1,"  %s: (%d) adding data type > %u",__func__,i,rel->rd_att->attrs[i].atttypid);

		state->rdfTable->cols[i]->pgtype = rel->rd_att->attrs[i].atttypid;
		state->rdfTable->cols[i]->name = pstrdup(NameStr(rel->rd_att->attrs[i].attname));
		state->rdfTable->cols[i]->pgtypmod = rel->rd_att->attrs[i].atttypmod;
		state->rdfTable->cols[i]->pgattnum = rel->rd_att->attrs[i].attnum;

		if (!canHandleType(state->rdfTable->cols[i]->pgtype))
		{
			ereport(ERROR,
					(errcode(ERRCODE_FDW_INVALID_DATA_TYPE),
					 errmsg("data type of '%s' not supported: %d\n", state->rdfTable->cols[i]->name, state->rdfTable->cols[i]->pgtype)));

#if PG_VERSION_NUM < 130000
			heap_close(rel, NoLock);
#else
			table_close(rel, NoLock);
#endif
		}

		/* 
		 * The parser will set it to true if the column is used in the SQL query.
		 */
		state->rdfTable->cols[i]->used = false; 
	}

#if PG_VERSION_NUM < 130000
	heap_close(rel, NoLock);
#else
	table_close(rel, NoLock);
#endif

	/* Loading Foreign Server OPTIONS */
	foreach (cell, server->options)
	{
		DefElem *def = lfirst_node(DefElem, cell);

		if (strcmp(RDF_SERVER_OPTION_ENDPOINT, def->defname) == 0)
			state->endpoint = defGetString(def);
		else if (strcmp(RDF_SERVER_OPTION_FORMAT, def->defname) == 0) 
			state->format = defGetString(def);
		else if (strcmp(RDF_SERVER_OPTION_CUSTOMPARAM, def->defname) == 0) 
			state->customParams = defGetString(def);
		else if (strcmp(RDF_SERVER_OPTION_HTTP_PROXY, def->defname) == 0)
		{
			state->proxy = defGetString(def);
			state->proxyType = RDF_SERVER_OPTION_HTTP_PROXY;
		}
		else if (strcmp(RDF_SERVER_OPTION_HTTPS_PROXY, def->defname) == 0)
		{
			state->proxy = defGetString(def);
			state->proxyType = RDF_SERVER_OPTION_HTTPS_PROXY;
		}
		else if (strcmp(RDF_SERVER_OPTION_PROXY_USER, def->defname) == 0)
		{
			state->proxyUser = defGetString(def);
		}
		else if (strcmp(RDF_SERVER_OPTION_PROXY_USER_PASSWORD, def->defname) == 0)
		{
			state->proxyUserPassword = defGetString(def);
		}
		else if (strcmp(RDF_SERVER_OPTION_CONNECTRETRY, def->defname) == 0)
		{
			char *tailpt;
			char *maxretry_str = defGetString(def);
			state->maxretries = strtol(maxretry_str, &tailpt, 0);
		}
		else if (strcmp(RDF_SERVER_OPTION_REQUEST_REDIRECT, def->defname) == 0)
		{
			state->requestRedirect = defGetBoolean(def);
		}
		else if (strcmp(RDF_SERVER_OPTION_REQUEST_MAX_REDIRECT, def->defname) == 0)
		{
			char *tailpt;
			char *maxredirect_str = defGetString(def);
			state->requestMaxRedirect = strtol(maxredirect_str, &tailpt, 0);
		}
		else if (strcmp(RDF_SERVER_OPTION_CONNECTTIMEOUT, def->defname) == 0)
		{
			char *tailpt;
			char *timeout_str = defGetString(def);
			state->connectTimeout = strtol(timeout_str, &tailpt, 0);
		}
		else if (strcmp(RDF_SERVER_OPTION_ENABLE_PUSHDOWN, def->defname) == 0)
		{
			state->enablePushdown = defGetBoolean(def);
		}
		else if (strcmp(RDF_SERVER_OPTION_QUERY_PARAM, def->defname) == 0)
		{
			state->query_param = defGetString(def);
		}
		
	}


	/* 
	 * Loading Foreign Table OPTIONS 
	 */
	foreach (cell, ft->options)
	{
		DefElem *def = lfirst_node(DefElem, cell);

		if (strcmp(RDF_TABLE_OPTION_SPARQL, def->defname) == 0) 
		{
			state->raw_sparql = defGetString(def);
			state->is_sparql_parsable = IsSPARQLParsable(state);

		} else if (strcmp(RDF_TABLE_OPTION_LOG_SPARQL, def->defname) == 0) 
		{
			state->log_sparql = defGetBoolean(def);
		} 
		else if (strcmp(RDF_TABLE_OPTION_ENABLE_PUSHDOWN, def->defname) == 0) 
		{
			state->enablePushdown = defGetBoolean(def);
		}

					
	}

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
	 * Deparsing SPARQL WHERE clause  
	 *   'where_position = i + 1' to remove the surrounging curly braces {} as we are 
	 *   interested only in WHERE clause's containing triples
	 */
	for (int i = 0; state->raw_sparql[i] != '\0'; i++)
	{
		if (state->raw_sparql[i] == '{' && where_position == -1)
			where_position = i + 1;

		if (state->raw_sparql[i] == '}')
			where_size = i - where_position;
	}	
	state->sparql_where = pnstrdup(state->raw_sparql + where_position, where_size);

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

	elog(DEBUG2, "%s: called > rowcount = %d/%d", __func__, state->rowcount, state->pagesize);

	if (state->rowcount > state->pagesize)
	{
		elog(DEBUG1, "%s: EOF!", __func__);
		return NULL;
	}

	cell = list_nth_cell(state->records, state->rowcount);

	elog(DEBUG2,"  %s: returning %d",__func__,state->rowcount);
	
	return (xmlNodePtr) lfirst(cell);

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

	CURL *curl;
	CURLcode res;
	StringInfoData url_buffer;
	StringInfoData user_agent;
	StringInfoData accept_header;
	char errbuf[CURL_ERROR_SIZE];
	struct MemoryStruct chunk;
	struct MemoryStruct chunk_header;
	struct curl_slist *headers = NULL;

	chunk.memory = palloc(1);
	chunk.size = 0; /* no data at this point */
	chunk_header.memory = palloc(1);
	chunk_header.size = 0; /* no data at this point */
	
	elog(DEBUG1, "%s called",__func__);

	curl_global_init(CURL_GLOBAL_ALL);
	curl = curl_easy_init();

	initStringInfo(&accept_header);
	appendStringInfo(&accept_header, "Accept: %s", state->format);

	if(state->log_sparql)
		elog(NOTICE,"SPARQL query sent to '%s':\n\n%s\n",state->endpoint,state->sparql.data);

	initStringInfo(&url_buffer);
	appendStringInfo(&url_buffer, "%s=%s", state->query_param, curl_easy_escape(curl, state->sparql.data, 0));

	if(state->customParams)
		appendStringInfo(&url_buffer, "&%s", curl_easy_escape(curl, state->customParams, 0));

	elog(DEBUG1, "  %s: url build > %s?%s", __func__, state->endpoint, url_buffer.data);

	if (curl)
	{
		errbuf[0] = 0;

		curl_easy_setopt(curl, CURLOPT_URL, state->endpoint);

#if ((LIBCURL_VERSION_MAJOR == 7 && LIBCURL_VERSION_MINOR < 85) || LIBCURL_VERSION_MAJOR < 7)
		curl_easy_setopt(curl, CURLOPT_PROTOCOLS, CURLPROTO_HTTP | CURLPROTO_HTTPS);
#else
		curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "http,https");
#endif

		curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, errbuf);

		curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, state->connectTimeout);
		elog(DEBUG1, "  %s: timeout > %ld", __func__, state->connectTimeout);
		elog(DEBUG1, "  %s: max retry > %ld", __func__, state->maxretries);

		if (state->proxy)
		{
			elog(DEBUG1, "  %s: proxy URL > '%s'", __func__, state->proxy);

			curl_easy_setopt(curl, CURLOPT_PROXY, state->proxy);

			if (strcmp(state->proxyType, RDF_SERVER_OPTION_HTTP_PROXY) == 0)
			{
				elog(DEBUG1, "  %s: proxy protocol > 'HTTP'", __func__);
				curl_easy_setopt(curl, CURLOPT_PROXYTYPE, CURLPROXY_HTTP);
			}
			else if (strcmp(state->proxyType, RDF_SERVER_OPTION_HTTPS_PROXY) == 0)
			{
				elog(DEBUG1, "  %s: proxy protocol > 'HTTPS'", __func__);
				curl_easy_setopt(curl, CURLOPT_PROXYTYPE, CURLPROXY_HTTPS);
			}

			if (state->proxyUser)
			{
				elog(DEBUG1, "  %s: entering proxy user ('%s').", __func__, state->proxyUser);
				curl_easy_setopt(curl, CURLOPT_PROXYUSERNAME, state->proxyUser);
			}

			if (state->proxyUserPassword)
			{
				elog(DEBUG1, "  %s: entering proxy user's password.", __func__);
				curl_easy_setopt(curl, CURLOPT_PROXYUSERPWD, state->proxyUserPassword);
			}
		}

		if (state->requestRedirect == true)
		{

			elog(DEBUG1, "  %s: setting request redirect: %d", __func__, state->requestRedirect);
			curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);

			if (state->requestMaxRedirect)
			{
				elog(DEBUG1, "  %s: setting maxredirs: %ld", __func__, state->requestMaxRedirect);
				curl_easy_setopt(curl, CURLOPT_MAXREDIRS, state->requestMaxRedirect);
			}
		}

		curl_easy_setopt(curl, CURLOPT_VERBOSE, 1L);
		curl_easy_setopt(curl, CURLOPT_POSTFIELDS, url_buffer.data);
		curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, HeaderCallbackFunction);
		curl_easy_setopt(curl, CURLOPT_HEADERDATA, (void *)&chunk_header);
		curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
		curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);
		curl_easy_setopt(curl, CURLOPT_FAILONERROR, true);

		initStringInfo(&user_agent);
		appendStringInfo(&user_agent,  "PostgreSQL/%s rdf_fdw/%s libxml2/%s %s", PG_VERSION, FDW_VERSION, LIBXML_DOTTED_VERSION, curl_version());
		curl_easy_setopt(curl, CURLOPT_USERAGENT, user_agent.data);

		headers = curl_slist_append(headers, accept_header.data);
		curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

		elog(DEBUG2, "  %s: performing cURL request ... ", __func__);

		res = curl_easy_perform(curl);

		if (res != CURLE_OK)
		{
			for (long i = 1; i <= state->maxretries && (res = curl_easy_perform(curl)) != CURLE_OK; i++)
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
			curl_easy_cleanup(curl);
			curl_global_cleanup();

			if (len)
			{
				ereport(ERROR,
						(errcode(ERRCODE_FDW_UNABLE_TO_ESTABLISH_CONNECTION),
						 errmsg("%s => (%u) %s%s", __func__, res, errbuf,
								((errbuf[len - 1] != '\n') ? "\n" : ""))));
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
			long response_code;
			curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
			state->xmldoc = xmlReadMemory(chunk.memory, chunk.size, NULL, NULL, XML_PARSE_NOBLANKS);

			elog(DEBUG2, "  %s: http response code = %ld", __func__, response_code);
			elog(DEBUG2, "  %s: http response size = %ld", __func__, chunk.size);
			elog(DEBUG2, "  %s: http response header = \n%s", __func__, chunk_header.memory);

		}

	}

	pfree(chunk.memory);
	pfree(chunk_header.memory);
	curl_slist_free_all(headers);
	curl_easy_cleanup(curl);
	curl_global_cleanup();

	/*
	 * We thrown an error in case the SPARQL endpoint returns an empty XML doc
	 */
	if(!state->xmldoc)
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
	xmlNodePtr record;

	state->rowcount = 0;
	state->records = NIL;

	elog(DEBUG1, "%s called",__func__);

	if (ExecuteSPARQL(state) != REQUEST_SUCCESS)
		elog(ERROR, "%s -> SPARQL failed: '%s'", __func__, state->endpoint);

	elog(DEBUG2, "  %s: loading 'xmlroot'",__func__);

	Assert(state->xmldoc);
	
	for (results = xmlDocGetRootElement(state->xmldoc)->children; results != NULL; results = results->next)
	{
		if (xmlStrcmp(results->name, (xmlChar *)"results") == 0)
		{
			for (record = results->children; record != NULL; record = record->next)
			{
				if (xmlStrcmp(record->name, (xmlChar *)"result") == 0)
				{
					state->records = lappend(state->records, record);
					state->pagesize++;

					elog(DEBUG2, "	appending %d > %s", state->pagesize, record->name);
				}
			}
		}
	}

	if(record)
		xmlFreeNode(record);
	if(results)
		xmlFreeNode(results);

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
			elog(DEBUG1, "  %s: column belonging to a different foreign table", __func__);
			break;
		}

		/* ignore system columns */
		if (variable->varattno < 0)
		{
			elog(DEBUG1, "  %s: ignoring as system column", __func__);
			break;
		}

		for (int i = 0; i < state->numcols; i++)
		{

			if (state->rdfTable->cols[i]->pgattnum == variable->varattno)
			{
				state->rdfTable->cols[i]->used = true;
				elog(DEBUG1, "  %s: column '%s' (%d) required in the SQL query", __func__, state->rdfTable->cols[i]->name, i);
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

static bool IsExpressionPushable(char *expression) {

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

	initStringInfo(&state->sparql);	
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
		appendStringInfo(&state->sparql,"%s\nSELECT DISTINCT %s\n%s%s",
			state->sparql_prefixes, 
			state->sparql_select,
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
		appendStringInfo(&state->sparql,"%s\nSELECT REDUCED %s\n%s%s",
			state->sparql_prefixes, 
			state->sparql_select, 
			state->sparql_from, 
			where_graph.data);		
	}
	/* 
	 * if the raw SPARQL query does not contain a DISTINCT but the SQL query does, 
	 * this must be added into the new SELECT clause 
	 */
	else if (state->is_sparql_parsable &&  
			LocateKeyword(state->raw_sparql, " \n", "DISTINCT"," \n?", NULL, 0) == RDF_KEYWORD_NOT_FOUND && 
	        root->parse->distinctClause != NULL && 
			!root->parse->hasDistinctOn)
		appendStringInfo(&state->sparql,"%s\nSELECT DISTINCT %s\n%s%s",
			state->sparql_prefixes, 
			state->sparql_select,
			state->sparql_from,
			where_graph.data);
	else
		appendStringInfo(&state->sparql,"%s\nSELECT %s\n%s%s",
			state->sparql_prefixes, 
			state->sparql_select, 
			state->sparql_from, 
			where_graph.data);

	/*
	 * if the SQL query contains an ORDER BY, we try to push it down.
	 */
	if(state->is_sparql_parsable && state->sparql_orderby) {
		elog(DEBUG1, "  %s: pushing down ORDER BY clause > 'ORDER BY %s'", __func__, state->sparql_orderby);
		appendStringInfo(&state->sparql, "\nORDER BY%s", pstrdup(state->sparql_orderby));
	}

	/*
	 * Pushing down LIMIT (OFFSET) to the SPARQL query if the SQL query contains them.
	 * If the SPARQL query set in the CREATE TABLE statement already contains a LIMIT,
	 * this won't be pushed.
	 */
	if (state->sparql_limit)
	{
		elog(DEBUG1, "  %s: pushing down LIMIT clause > '%s'", __func__, state->sparql_limit);
		appendStringInfo(&state->sparql, "\n%s", state->sparql_limit);
	}
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
		
	elog(DEBUG1,"%s called: '%s' in start_position %d",__func__, keyword, start_position);

	if(start_position < 0)
		elog(ERROR, "%s: start_position cannot be negative.", __func__);

	/* 
	 * Some SPARQL keywords can be placed in the very beginning of a query, so they not always 
	 * have a preceeding character. So here we first check if the searched keyword exists
	 * in the beginning of the string.
	 */
	if (((strcasecmp(keyword, RDF_SPARQL_KEYWORD_SELECT) == 0 && strncasecmp(str, RDF_SPARQL_KEYWORD_SELECT, strlen(RDF_SPARQL_KEYWORD_SELECT)) == 0) ||
		 (strcasecmp(keyword, RDF_SPARQL_KEYWORD_PREFIX) == 0 && strncasecmp(str, RDF_SPARQL_KEYWORD_PREFIX, strlen(RDF_SPARQL_KEYWORD_PREFIX)) == 0)) && 
		 start_position == 0)
	{
		elog(DEBUG1, "%s: nothing before SELECT. Setting keyword_position to 0,", __func__);
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
		elog(DEBUG1, "  %s (%d): keyword '%s' found in position '%d'. Recalling %s ... ", __func__, *count, keyword, keyword_position, __func__);
		LocateKeyword(str, start_chars, keyword, end_chars, count, keyword_position + 1);
		(*count)++;
	}
		

	elog(DEBUG1,"  %s: '%s' returning  %d",__func__, keyword, keyword_position);
	
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
	
	xmlNodePtr record = FetchNextBinding(state);
	xmlNodePtr result;
	xmlNodePtr value;
	regproc typinput;
	HeapTuple tuple;
	Datum datum;
	xmlBufferPtr buffer;

	StringInfoData name;
	initStringInfo(&name);

	elog(DEBUG2,"%s called ",__func__);

	for (int i = 0; i < state->numcols; i++)
	{
		bool match = false;
		Oid pgtype = state->rdfTable->cols[i]->pgtype;
		char *sparqlvar = state->rdfTable->cols[i]->sparqlvar;
		char *colname = state->rdfTable->cols[i]->name;
		int pgtypmod = state->rdfTable->cols[i]->pgtypmod;

		elog(DEBUG2, "  %s: setting column > %s (type > %d), sparqlvar > %s",__func__, colname, pgtype, sparqlvar);	

		for (result = record->children; result != NULL; result = result->next)
		{
			appendStringInfo(&name, "?%s", (char *)xmlGetProp(result, (xmlChar *)RDF_XML_NAME_TAG));
			
			if (strcmp(sparqlvar, name.data) == 0)
			{
				match = true;

				for (value = result->children; value != NULL; value = value->next)
				{
	
					buffer = xmlBufferCreate();

					xmlNodeDump(buffer, state->xmldoc, value->children, 0, 0);
					datum = CStringGetDatum(pstrdup((char *) buffer->content));
					slot->tts_isnull[i] = false;

					elog(DEBUG2, "    %s: setting value for column '%s' (%s) > '%s'",__func__, name.data, sparqlvar, pstrdup((char *)buffer->content));

					/* find the appropriate conversion function */
					tuple = SearchSysCache1(TYPEOID, ObjectIdGetDatum(pgtype));

					if (!HeapTupleIsValid(tuple)) 
					{
						ereport(ERROR, 
							(errcode(ERRCODE_FDW_INVALID_DATA_TYPE),
								errmsg("cache lookup failed for type %u > column '%s(%s)'", pgtype,name.data,sparqlvar)));
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

			resetStringInfo(&name);

		}

		if(!match) 
		{
			elog(DEBUG2, "    %s: setting NULL for column '%s' (%s)",__func__, colname, sparqlvar);
			slot->tts_isnull[i] = true;
			slot->tts_values[i] = PointerGetDatum(NULL);					
		}

	}

	if(result)
		xmlFreeNode(result);
	if(value)
		xmlFreeNode(value);
	if(record)
		xmlFreeNode(record);
	pfree(name.data);
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
		elog(ERROR, "cache lookup failed for type %u", type);
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
	char *opername, *left, *right, oprkind;
	char *sparqlvar;
	Const *constant;
	OpExpr *oper;
	ScalarArrayOpExpr *arrayoper;
	Var *variable;
	HeapTuple tuple;
	StringInfoData result;
	Oid leftargtype, rightargtype, schema;
	int index;
	StringInfoData alias;
	ArrayExpr *array;
	ArrayCoerceExpr *arraycoerce;
	Expr *rightexpr;
	bool first_arg, isNull;
	ArrayIterator iterator;
	Datum datum;
	ListCell *cell;
	struct RDFfdwColumn *col = (struct RDFfdwColumn *) palloc0(sizeof(struct RDFfdwColumn));

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
		index = state->numcols - 1;

		while (index >= 0 && state->rdfTable->cols[index]->pgattnum != variable->varattno)
			--index;

		/* if no foreign table column corresponds, translate as NULL */
		if (index == -1)
		{
			initStringInfo(&result);
			appendStringInfo(&result, "NULL");
			break;
		}

		initStringInfo(&result);
		/* qualify with an alias based on the range table index */
		initStringInfo(&alias);

		appendStringInfo(&result, "%s%s", alias.data, state->rdfTable->cols[index]->name);

		elog(DEBUG1, "  %s T_Var -> index = %d result = %s", __func__, index, state->rdfTable->cols[index]->name);
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
			strcmp(opername, "<>") == 0)
		{

			/* SPARQL does not suppot <> */
			if (strcmp(opername, "<>") == 0)
				opername = "!=";

			left = DeparseExpr(state, foreignrel, linitial(oper->args));

			if (left == NULL)
			{
				pfree(opername);
				return NULL;
			}

			if (oprkind == 'b')
			{

				/* binary operator */
				right = DeparseExpr(state, foreignrel, lsecond(oper->args));
				rightexpr = lsecond(oper->args);

				if (right == NULL)
					return NULL;

				initStringInfo(&result);

				col = GetRDFColumn(state, left);

				/* if the sparql variable cannot be found, there is no point in keep going */
				if(!col)
					return NULL;

				/* 
				 * if the column contains an 'expression' it is not safe to push it down.
				 * as it might contain function calls that are invalid in FILTER conditions
				 */
				// if(col->expression)
				// 	return NULL;

				if ((leftargtype == TEXTOID || leftargtype == VARCHAROID || leftargtype == CHAROID || leftargtype == NAMEOID) && rightexpr->type == T_Const)
				{
					if(col->pushable && col->expression)
						appendStringInfo(&result, "%s %s \"%s\"", col->expression, opername, right);
					else
						appendStringInfo(&result, "STR(%s) %s \"%s\"", col->sparqlvar, opername, right);
				}
				else if (leftargtype == DATEOID && rightexpr->type == T_Const)
				{
					if(col->pushable && col->expression)
						appendStringInfo(&result, "%s %s xsd:date(\"%s\")", col->sparqlvar, opername, right);
					else
						appendStringInfo(&result, "xsd:date(%s) %s xsd:date(\"%s\")", col->sparqlvar, opername, right);
				}
				else if ((leftargtype == TIMESTAMPOID || leftargtype == TIMESTAMPTZOID) && rightexpr->type == T_Const)
				{
					appendStringInfo(&result, "xsd:dateTime(%s) %s xsd:dateTime(\"%s\")", col->sparqlvar, opername, right);
				}
				else
				{
					if(col->pushable && col->expression)
						appendStringInfo(&result, "%s %s %s", col->expression, opername, right);
					else
						appendStringInfo(&result, "%s %s %s", col->sparqlvar, opername, right);
				}

			}
			else
			{
				elog(DEBUG1, "  %s: unary operator not supported", __func__);
			}
		}
		else
		{
			elog(DEBUG1, "  %s: operator cannot be translated > '%s' ", __func__, opername);
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

		initStringInfo(&result);
		sparqlvar = (GetRDFColumn(state, left))->sparqlvar;

		if (strcmp(opername, "=") == 0)
			if ((leftargtype == TEXTOID || leftargtype == VARCHAROID || leftargtype == CHAROID || leftargtype == NAMEOID))
				appendStringInfo(&result, "STR(%s) IN (", sparqlvar);
			else if (leftargtype == DATEOID)
				appendStringInfo(&result, "xsd:date(%s) IN (", sparqlvar);
			else if (leftargtype == TIMESTAMPOID || leftargtype == TIMESTAMPTZOID)
				appendStringInfo(&result, "xsd:dateTime(%s) IN (", sparqlvar);
			else
				appendStringInfo(&result, "%s IN (", sparqlvar);
		else
			if ((leftargtype == TEXTOID || leftargtype == VARCHAROID || leftargtype == CHAROID || leftargtype == NAMEOID))
				appendStringInfo(&result, "STR(%s) NOT IN (", sparqlvar);
			else if (leftargtype == DATEOID)
				appendStringInfo(&result, "xsd:date(%s) NOT IN (", sparqlvar);
			else if (leftargtype == TIMESTAMPOID || leftargtype == TIMESTAMPTZOID)
				appendStringInfo(&result, "xsd:dateTime(%s) NOT IN (", sparqlvar);
			else
				appendStringInfo(&result, "%s NOT IN (", sparqlvar);

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

				/* loop through the array elements */
				iterator = array_create_iterator(arr, 0, NULL);
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

				
					if (leftargtype == TEXTOID || leftargtype == VARCHAROID || leftargtype == CHAROID || leftargtype == NAMEOID)
						appendStringInfo(&result, "%s\"%s\"", first_arg ? "" : ", ", c);
					else if (leftargtype == DATEOID)
						appendStringInfo(&result, "%sxsd:date(\"%s\")", first_arg ? "" : ", ", c);
					else if (leftargtype == TIMESTAMPOID || leftargtype == TIMESTAMPTZOID)
						appendStringInfo(&result, "%sxsd:dateTime(\"%s\")", first_arg ? "" : ", ", c);
					else
						appendStringInfo(&result, "%s%s", first_arg ? "" : ", ", c);

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

			if (arraycoerce->elemexpr && arraycoerce->elemexpr->type != T_RelabelType)
				return NULL;

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
	default:
		elog(DEBUG1, "  %s: expression not supported > %u", __func__, expr->type);
		return NULL;
	}

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
		/* check if the condition can be pushed down */
		char *where = DeparseExpr(
					state, baserel,
					((RestrictInfo *)lfirst(cell))->clause
				);

		if (where != NULL) {
			state->remote_conds = lappend(state->remote_conds, ((RestrictInfo *)lfirst(cell))->clause);

			/* append new FILTER clause to query string */
			appendStringInfo(&where_clause, " FILTER(%s)\n", pstrdup(where));
			pfree(where);

		}
		else
		{
			state->local_conds = lappend(state->local_conds, ((RestrictInfo *)lfirst(cell))->clause);
			elog(DEBUG1,"  %s: condition cannot be pushed down.",__func__);
		}
			
	}

	return where_clause.data;
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
	if (state->local_conds != NIL)
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
		appendStringInfo(&limit_clause,
						 "LIMIT %s+%s",
						 offset_val, limit_val);
	else
		appendStringInfo(&limit_clause,
						 "LIMIT %s",
						 limit_val);

	return limit_clause.data;

}