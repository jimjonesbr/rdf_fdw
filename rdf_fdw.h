/*---------------------------------------------------------------------
 *
 * rdf_fdw.h
 * 
 * RDF-related constants for the rdf_fdw extension.
 * Centralized definitions for RDF/SPARQL URIs, datatypes, formats, and
 * configuration defaults.
 * 
 * Copyright (C) 2022-2025 University of Münster, Germany
 * 
 *---------------------------------------------------------------------
 */

#ifndef RDF_FDW_H
#define RDF_FDW_H

#include "postgres.h"
#include "foreign/foreign.h" /* ForeignServer, ForeignTable, UserMapping */
#include "utils/rel.h"       /* Relation */
#include <curl/curl.h>       /* CURL */
#include <libxml/tree.h>     /* xmlDocPtr, xmlNodePtr */
#include "lib/stringinfo.h"  /* StringInfoData */
/* Version */
#define FDW_VERSION "2.3-dev"

/* Request status codes */
#define REQUEST_SUCCESS 0
#define REQUEST_FAIL -1

/* Table options */
#define RDF_TABLE_OPTION_SPARQL "sparql"
#define RDF_TABLE_OPTION_SPARQL_UPDATE_PATTERN "sparql_update_pattern"
#define RDF_TABLE_OPTION_LOG_SPARQL "log_sparql"
#define RDF_TABLE_OPTION_ENABLE_PUSHDOWN "enable_pushdown"
#define RDF_TABLE_OPTION_FETCH_SIZE "fetch_size"

/* Column options */
#define RDF_COLUMN_OPTION_VARIABLE "variable"
#define RDF_COLUMN_OPTION_EXPRESSION "expression"
#define RDF_COLUMN_OPTION_LITERALTYPE "literaltype"
#define RDF_COLUMN_OPTION_NODETYPE "nodetype"
#define RDF_COLUMN_OPTION_NODETYPE_IRI "iri"
#define RDF_COLUMN_OPTION_NODETYPE_LITERAL "literal"
#define RDF_COLUMN_OPTION_LANGUAGE "language"
#define RDF_COLUMN_OPTION_LITERAL_TYPE "literal_type"
#define RDF_COLUMN_OPTION_VALUE_LITERAL_RAW "raw"
#define RDF_COLUMN_OPTION_VALUE_LITERAL_CONTENT "content"

/* SPARQL query type keywords */
#define RDF_SPARQL_TYPE_SELECT "SELECT"
#define RDF_SPARQL_TYPE_DESCRIBE "DESCRIBE"

/* SPARQL keywords */
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
#define RDF_SPARQL_KEYWORD_MINUS "MINUS"

/* SPARQL aggregate functions */
#define RDF_SPARQL_AGGREGATE_FUNCTION_COUNT "COUNT"
#define RDF_SPARQL_AGGREGATE_FUNCTION_AVG "AVG"
#define RDF_SPARQL_AGGREGATE_FUNCTION_SUM "SUM"
#define RDF_SPARQL_AGGREGATE_FUNCTION_MIN "MIN"
#define RDF_SPARQL_AGGREGATE_FUNCTION_MAX "MAX"
#define RDF_SPARQL_AGGREGATE_FUNCTION_SAMPLE "SAMPLE"
#define RDF_SPARQL_AGGREGATE_FUNCTION_GROUPCONCAT "GROUP_CONCAT"

/* XML and SPARQL result tags */
#define RDF_XML_NAME_TAG "name"
#define RDF_SPARQL_RESULT_LITERAL "literal"
#define RDF_SPARQL_RESULT_LITERAL_DATATYPE "datatype"
#define RDF_SPARQL_RESULT_LITERAL_LANG "lang"

/* Connection and query defaults */
#define RDF_DEFAULT_CONNECTTIMEOUT 300
#define RDF_DEFAULT_MAXRETRY 3
#define RDF_KEYWORD_NOT_FOUND -1
#define RDF_DEFAULT_FORMAT "application/sparql-results+xml"
#define RDF_RDFXML_FORMAT "application/rdf+xml"
#define RDF_DEFAULT_QUERY_PARAM "query"
#define RDF_DEFAULT_FETCH_SIZE 100
#define RDF_DEFAULT_BATCH_SIZE 50

/* RDF base URIs */
#define RDF_DEFAULT_BASE_URI "http://rdf_fdw.postgresql.org/"
#define RDF_XSD_BASE_URI "http://www.w3.org/2001/XMLSchema#"

/* RDF datatype URIs */
#define RDF_LANGUAGE_LITERAL_DATATYPE "<http://www.w3.org/1999/02/22-rdf-syntax-ns#langString>"
#define RDF_SIMPLE_LITERAL_DATATYPE "<http://www.w3.org/2001/XMLSchema#string>"
#define RDF_SIMPLE_LITERAL_DATATYPE_PREFIXED "xsd:string"

/* XSD datatype URIs */
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

/* Table type codes */
#define RDF_ORDINARY_TABLE_CODE "r"
#define RDF_FOREIGN_TABLE_CODE "f"

/* User mapping options */
#define RDF_USERMAPPING_OPTION_USER "user"
#define RDF_USERMAPPING_OPTION_PASSWORD "password"

/* Server options */
#define RDF_SERVER_OPTION_SELECT_URL "endpoint"
#define RDF_SERVER_OPTION_UPDATE_URL "update_url"
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
#define RDF_SERVER_OPTION_PREFIX_CONTEXT "prefix_context"
#define RDF_SERVER_OPTION_ENABLE_XML_HUGE "enable_xml_huge"
#define RDF_SERVER_OPTION_BATCH_SIZE "batch_size" 

extern Oid RDFNODEOID;

typedef enum RDFfdwQueryType
{
	SPARQL_SELECT,
	SPARQL_DESCRIBE,
	SPARQL_INSERT,
	SPARQL_DELETE,
	SPARQL_UPDATE
} RDFfdwQueryType;

typedef struct RDFfdwState
{
	int numcols;					   /* Total number of columns in the foreign table. */
	int rowcount;					   /* Number of rows currently returned to the client */
	int pagesize;					   /* Total number of records retrieved from the SPARQL endpoint*/
	char *sparql;					   /* Final SPARQL query sent to the endpoint (after pusdhown) */
	char *user;						   /* User name for HTTP basic authentication */
	char *password;					   /* Password for HTTP basic authentication */
	char *sparql_prefixes;			   /* SPARQL PREFIX entries */
	char *sparql_select;			   /* SPARQL SELECT containing the columns / variables used in the SQL query */
	char *sparql_from;				   /* SPARQL FROM clause entries*/
	char *sparql_where;				   /* SPARQL WHERE clause */
	char *sparql_filter;			   /* SPARQL FILTER clauses based on SQL WHERE conditions */
	char *sparql_filter_expr;          /* SPARQL FILTER clauses as single expression (for EXPLAIN output) */
	char *sparql_orderby;			   /* SPARQL ORDER BY clause based on the SQL ORDER BY clause */
	char *sparql_limit;				   /* SPARQL LIMIT clause based on SQL LIMIT and FETCH clause */
	char *sparql_resultset;			   /* Raw string containing the result of a SPARQL query */
	char *sparql_update_pattern;       /* SPARQL triple pattern for INSERT/DELETE/UPDATE queries */
	char *raw_sparql;				   /* Raw SPARQL query set in the CREATE TABLE statement */
	char *endpoint;					   /* SPARQL endpoint set in the CREATE SERVER statement*/
	char *query_param;				   /* SPARQL query POST parameter used by the endpoint */
	char *format;					   /* Format in which the RDF triplestore has to reply */
	char *prefix_context;              /* Prefix context for SPARQL queries */
	char *proxy;					   /* Proxy for HTTP requests, if necessary. */
	char *proxy_type;				   /* Proxy protocol (HTTPS, HTTP). */
	char *proxy_user;				   /* User name for proxy authentication. */
	char *proxy_user_password;		   /* Password for proxy authentication. */
	char *custom_params;			   /* Custom parameters used to compose the request URL */
	char *base_uri;					   /* Base URI for possible relative references */
	bool request_redirect;			   /* Enables or disables URL redirecting. */
	bool enable_pushdown;			   /* Enables or disables pushdown of SQL commands */
	bool enable_xml_huge;			   /* Enables or disables XML parser to handle huge XML documents */
	bool is_sparql_parsable;		   /* Marks the query is or not for pushdown*/
	bool log_sparql;				   /* Enables or disables logging SPARQL queries as NOTICE */
	bool has_unparsable_conds;		   /* Marks a query that contains expressions that cannot be parsed for pushdown. */
	bool keep_raw_literal;			   /* Flag to determine if a literal should be serialized with its data type/language or not*/
	List *remote_conds;				   /* List of RestrictInfo nodes that were successfully pushed down to the remote SPARQL endpoint */
	long request_max_redirect;		   /* Limit of how many times the URL redirection (jump) may occur. */
	long connect_timeout;			   /* Timeout for SPARQL queries */
	long max_retries;				   /* Number of re-try attemtps for failed SPARQL queries */
	xmlDocPtr xmldoc;				   /* XML document where the result of SPARQL queries will be stored */
	Oid foreigntableid;				   /* FOREIGN TABLE oid */
	List *records;					   /* List of records retrieved from a SPARQL request (after parsing 'xmldoc')*/
	List *prefixes; 		   		   /* List of RDF prefixes used in the SPARQL query and context */
	struct RDFfdwTable *rdfTable;	   /* All necessary information of the FOREIGN TABLE used in a SQL statement */
	Cost startup_cost;				   /* startup cost estimate */
	Cost total_cost;				   /* total cost estimate */
	ForeignServer *server;			   /* FOREIGN SERVER to connect to the RDF triplestore */
	ForeignTable *foreign_table;	   /* FOREIGN TABLE containing the graph pattern (SPARQL Query) and column / variable mapping */
	UserMapping *mapping;			   /* USER MAPPING to enable http basic authentication for a given postgres user */
	MemoryContext rdfctxt;			   /* Memory Context for data manipulation */
	CURL *curl;						   /* CURL request handler */
	RDFfdwQueryType sparql_query_type; /* SPARQL Query type: SELECT, DESCRIBE */
	MemoryContext temp_cxt;			   /* Temporary memory context for per-row allocations during INSERT */
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
	int batch_size; 				   /* Number of rows to batch for INSERT/UPDATE/DELETE */
	int batch_count;				   /* Current number of rows in the batch buffer */
	StringInfoData batch_statements;   /* Buffer for batched SPARQL statements */
} RDFfdwState;

typedef struct RDFfdwTable
{
	char *name;					/* FOREIGN TABLE name */
	struct RDFfdwColumn **cols; /* List of columns of a FOREIGN TABLE */
} RDFfdwTable;

typedef struct RDFfdwColumn
{
	char *name;			 /* Column name */
	char *sparqlvar;	 /* Column OPTION 'variable' - SPARQL variable */
	char *expression;	 /* Column OPTION 'expression' - SPARQL expression*/
	char *literaltype;	 /* Column OPTION 'type' - literal data type */
	char *literal_fomat; /*  */
	char *nodetype;		 /* Column OPTION 'nodetype' - node data type */
	char *language;		 /* Column OPTION 'language' - RDF language tag for literals */
	Oid pgtype;			 /* PostgreSQL data type */
	int pgtypmod;		 /* PostgreSQL type modifier */
	int pgattnum;		 /* PostgreSQL attribute number */
	bool used;			 /* Is the column used in the current SQL query? */
	bool pushable;		 /* Marks a column as safe or not to pushdown */

} RDFfdwColumn;

struct RDFfdwOption
{
	const char *optname;
	Oid optcontext;	  /* Oid of catalog in which option may appear */
	bool optrequired; /* Flag mandatory options */
	bool optfound;	  /* Flag whether options was specified by user */
};

typedef struct RDFPrefix
{
	char *prefix;	/* prefix name, e.g. foaf, dcterms, owl */
	char *url; 		/* prefix url */
} RDFPrefix;

typedef struct RDFfdwTriple
{
	char *subject;	 /* RDF triple subject */
	char *predicate; /* RDF triple predicate */
	char *object;	 /* RDF triple object */
} RDFfdwTriple;

#endif /* RDF_FDW_H */
