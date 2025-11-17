
---------------------------------------------
# RDF Triplestore Foreign Data Wrapper for PostgreSQL (rdf_fdw)

`rdf_fdw` is a PostgreSQL Foreign Data Wrapper that enables seamless access to RDF triplestores via SPARQL endpoints. It supports pushdown of many SQL clauses and includes built-in implementations of most SPARQL 1.1 functions.

![CI](https://github.com/jimjonesbr/rdf_fdw/actions/workflows/ci.yml/badge.svg)

## Index

- [Requirements](#requirements)
- [Build and Install](#build-and-install)
- [Update](#update)
- [Usage](#usage)
  - [CREATE USER MAPPING](#create-user-mapping)
  - [CREATE SERVER](#create-server)
  - [CREATE FOREIGN TABLE](#create-foreign-table)
  - [ALTER FOREIGN TABLE and ALTER SERVER](#alter-foreign-table-and-alter-server)
  - [Prefix Management](#prefix-management)
  - [rdf_fdw_version](#rdf_fdw_version)
  - [rdf_fdw_settings](#rdf_fdw_settings)
  - [rdf_fdw_clone_table](#rdf_fdw_clone_table)
- [RDF Node Handling](#rdf-node-handling)
- [SPARQL Functions](#sparql-functions)
- [SPARQL Describe](#sparql-describe)
- [Pushdown](#pushdown)
- [Examples](#examples)
- [Deploy with Docker](#deploy-with-docker)
 
## [Requirements](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#requirements)

* [libxml2](http://www.xmlsoft.org/): version 2.5.0 or higher.
* [libcurl](https://curl.se/libcurl/): version 7.74.0 or higher.
* [librdf](https://librdf.org/): version 1.0.17 or higher.
* [pkg-config](https://linux.die.net/man/1/pkg-config): pkg-config 0.29.2 or higher.
* [PostgreSQL](https://www.postgresql.org): version 9.5 or higher.
* [gcc](https://gcc.gnu.org/) and [make](https://www.gnu.org/software/make/) to compile the code.

In an Ubuntu environment you can install all dependencies with the following command:

```shell
apt-get install -y make gcc postgresql-server-dev-17 libxml2-dev libcurl4-gnutls-dev librdf0-dev pkg-config
```

> [!NOTE]  
> `postgresql-server-dev-17` only installs the libraries for PostgreSQL 17. Change it if you're using another PostgreSQL version.

## [Build and Install](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#build_and_install)

Ensure [pg_config](https://www.postgresql.org/docs/current/app-pgconfig.html) is properly set before running `make`. This executable is typically found in your PostgreSQL installation's `bin` directory.

```bash
$ cd rdf_fdw
$ make
```

After compilation, install the Foreign Data Wrapper:

```bash
$ make install
```

Then, create the extension in PostgreSQL:

```sql
CREATE EXTENSION rdf_fdw;
```

To install a specific version, use:

```sql
CREATE EXTENSION rdf_fdw WITH VERSION '2.1';
```

To run the predefined regression tests: 

```bash
$ make PGUSER=postgres installcheck

```

> [!NOTE]  
> `rdf_fdw` loads all retrieved RDF data into memory before converting it for PostgreSQL. If you expect large data volumes, ensure that PostgreSQL has sufficient memory, or retrieve data in chunks using `rdf_fdw_clone_table` or a custom script.


## [Update](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#update)

To update the extension's version you must first build and install the binaries and then run `ALTER EXTENSION`:


```sql
ALTER EXTENSION rdf_fdw UPDATE;
```

To update to an specific version use `UPDATE TO` and the full version number, e.g.

```sql
ALTER EXTENSION rdf_fdw UPDATE TO '2.1';
```

## [Usage](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#usage)

To use `rdf_fdw`, you must first create a `SERVER` that connects to a SPARQL endpoint. Then, define a `FOREIGN TABLE` that specifies the SPARQL instructions used to retrieve data from the endpoint. This section walks through all the steps required to set up and query RDF data using the foreign data wrapper.

### [CREATE SERVER](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#create_server)

The SQL command [CREATE SERVER](https://www.postgresql.org/docs/current/sql-createserver.html) defines a new foreign server. The user who defines the server becomes its owner. A `SERVER` requires an `endpoint` to specify where `rdf_fdw` should send SPARQL queries.

The following example creates a `SERVER` that connects to the DBpedia SPARQL endpoint:

```sql
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');
```


**Server Options**

| Server Option | Type          | Description                                                                                                        |
|---------------|----------------------|--------------------------------------------------------------------------------------------------------------------|
| `endpoint`     | **required**            | URL address of the SPARQL Endpoint.
| `enable_pushdown` | optional            | Globally enables or disables [pushdown](#pushdown) of SQL clauses into SPARQL (default `true`)
| `format` | optional            | The `rdf_fdw` expects the result sets to be encoded in the [SPARQL Query Results XML Format](https://www.w3.org/TR/rdf-sparql-XMLres/), which is typically enforced by setting the MIME type `application/sparql-results+xml` in the `Accept` HTTP request header. However, some products deviate from this standard and expect a different value, e.g. `xml`, `rdf-xml`. If the expected parameter differs from the official MIME type, it should be specified explicitly (default `application/sparql-results+xml`).
| `http_proxy` | optional            | Proxy for HTTP requests.
| `proxy_user` | optional            | User for proxy server authentication.
| `proxy_user_password` | optional            | Password for proxy server authentication.
| `connect_timeout`         | optional            | Connection timeout for HTTP requests in seconds (default `300` seconds).
| `connect_retry`         | optional            | Number of attempts to retry a request in case of failure (default `3` times).
| `request_redirect`         | optional            | Enables URL redirect issued by the server (default `false`).
| `request_max_redirect`         | optional            | Specifies the maximum number of URL redirects allowed. If this limit is reached, any further redirection will result in an error. Leaving this parameter unset or setting it to `0` allows an unlimited number of redirects.
| `custom`         | optional            | One or more parameters expected by the configured RDF triplestore. Multiple parameters separated by `&`, e.g. `signal_void=on&signal_unconnected=on`. Custom parameters are appended to the request URL.
| `query_param`         | optional            | The request parameter in which the SPARQL endpoint expects the query in an HTTP request. Most endpoints expect the SPARQL query to be in the parameter `query` - and this is the `rdf_fdw` default value. So, chances are you'll never need to touch this server option.
| `prefix_context`     | optional            | Name of the context where predefined `PREFIX` entries are stored. When set, all prefixes registered in the context are automatically prepended to every generated SPARQL query. If the query also contains its own `PREFIX` declarations, those are appended **after** the context-defined ones. See [Prefix Management](#prefix-management) for more details.
| `enable_xml_huge`         | optional            | When set to `true`, the `rdf_fdw` will enable [`XML_PARSE_HUGE`](https://gnome.pages.gitlab.gnome.org/libxml2/html/parser_8h.html#a7d2daaf67df051ca5ef0b319b640442c) while parsing SPARQL XML results. This allows processing of documents with very large text nodes or deeply nested structures, bypassing libxml2's default safety limits. Use of this option is **strongly discouraged unless the SPARQL endpoint is fully trusted**. Enabling `XML_PARSE_HUGE` disables important parser limits designed to protect against resource exhaustion and denial-of-service attacks. For this reason, the option defaults to `false`. This option should only be used in controlled environments where the data provenance is secure and the size and complexity of result sets are known in advance. (default `false`).

> [!NOTE]  
> To visualise the foreign server's options use the `psql` meta-command `\des[+]`

### [CREATE USER MAPPING](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#create-user-mapping)

[CREATE USER MAPPING](https://www.postgresql.org/docs/current/sql-createusermapping.html) defines a mapping of a PostgreSQL user to an user in the target triplestore. For instance, to map the PostgreSQL user `postgres` to the user `admin` in the `SERVER` named `graphdb`:

```sql
CREATE SERVER graphdb
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (endpoint 'http://192.168.178.27:7200/repositories/myrepo');

CREATE USER MAPPING FOR postgres
SERVER graphdb OPTIONS (user 'admin', password 'secret');
```

| Option | Type | Description |
|---|---|---|
| `user` | **required** | name of the user for authentication |
| `password` | optional |   password of the user set in the option `user` |

The `rdf_fdw` will try to authenticate the given user using HTTP Basic Authentication - no other authentication method is currently supported. This feature can be ignored if the triplestore does not require user authentication.

> [!NOTE]  
> To visualise created user mappings use the `psql` meta-command `\deu[+]` or run `SELECT * FROM pg_user_mappings` in a client of your choice.

### [CREATE FOREIGN TABLE](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#create_foreign_table)

Foreign Tables from the `rdf_fdw` work as a proxy between PostgreSQL clients and RDF Triplestores. Each column in a `FOREIGN TABLE` must be mapped to a SPARQL variable. This allows PostgreSQL to extract and assign results from the SPARQL query into the right column.

**Table Options**

| Option        | Type        | Description                                                                                                        |
|---------------|-------------|--------------------------------------------------------------------------------------------------------------------|
| `sparql`      | **required**    | The raw SPARQL query to be executed    |
| `log_sparql`  | optional    | Logs the exact SPARQL query executed. Useful for verifying modifications to the query due to pushdown. Default `true`  |
| `enable_pushdown` | optional            | Enables or disables [pushdown](#pushdown) of SQL clauses into SPARQL for a specific foreign table. Overrides the `SERVER` option `enable_pushdown` |

Columns can use **one** of two data type categories:

#### RDF Node
The custom `rdfnode` type is designed to handle full RDF nodes, including both IRIs and literals with optional language tags or datatypes. It preserves the structure and semantics of RDF terms and is ideal when you need to manipulate or inspect RDF-specific details. Columns of this type only support the `variable`.

**Column Options**

| Option        | Type        | Description                                                                                                        |
|---------------|-------------|--------------------------------------------------------------------------------------------------------------------|
| `variable`    | **required**    | Maps the table column to a SPARQL variable used in the table option `sparql`. A variable must start with either `?` or `$` (*`?` or `$` are **not** part of the variable name!)*. The name must be a string with the following characters:  `[a-z]`, `[A-Z]`,`[0-9]`   |

Example:

```sql
CREATE FOREIGN TABLE hbf (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER linkedgeodata OPTIONS (
  log_sparql 'true',
  sparql 
    'SELECT ?p ?o 
     WHERE {<http://linkedgeodata.org/triplify/node376142577> ?p ?o}');
```

#### PostgreSQL native types
Alternatively, columns can be declared using PostgreSQL native types such as `text`, `date`, `int`, `boolean`, `numeric`, `timestamp`, etc. These are suitable for typed RDF literals or when you want automatic casting into PostgreSQL types. Native types support a wider range of column options:

**Column Options**

| Option        | Type        | Description                                                                                                        |
|---------------|-------------|--------------------------------------------------------------------------------------------------------------------|
| `variable`    | **required**    | Maps the table column to a SPARQL variable used in the table option `sparql`. A variable must start with either `?` or `$` (*`?` or `$` are **not** part of the variable name!)*. The name must be a string with the following characters:  `[a-z]`, `[A-Z]`,`[0-9]`   |
| `expression`  | optional    | Similar to `variable`, but instead of a SPARQL variable, it can handle expressions, such as [function calls](https://www.w3.org/TR/sparql11-query/#SparqlOps). Any expression supported by the data source can be used. |
| `language`    | optional        | RDF language tag, e.g. `en`,`de`,`pt`,`es`,`pl`, etc. This option ensures that the pushdown feature correctly sets the literal language tag in `FILTER` expressions. Set it to `*` to make `FILTER` expressions ignore language tags when comparing literals.   |  
| `literal_type`        | optional    | Data type for typed literals, e.g. `xsd:string`, `xsd:date`, `xsd:boolean`. This option ensures that the pushdown feature correctly sets the literal type of expressions from SQL `WHERE` conditions. Set it to `*` to make `FILTER` expressions ignore data types when comparing literals. |
| `nodetype`  | optional    | Type of the RDF node. Expected values are `literal` or `iri`. This option helps the query planner to optimize SPARQL `FILTER` expressions when the `WHERE` conditions are pushed down (default `literal`)  |


The following example creates a `FOREIGN TABLE` connected to the server `dbpedia`. `SELECT` queries executed against this table will execute the SPARQL query set in the OPTION `sparql`, and its result sets are mapped to each column of the table via the column OPTION `variable`.

```sql
CREATE FOREIGN TABLE film (
  film_id text    OPTIONS (variable '?film',     nodetype 'iri'),
  name text       OPTIONS (variable '?name',     nodetype 'literal', literal_type 'xsd:string'),
  released date   OPTIONS (variable '?released', nodetype 'literal', literal_type 'xsd:date'),
  runtime int     OPTIONS (variable '?runtime',  nodetype 'literal', literal_type 'xsd:integer'),
  abstract text   OPTIONS (variable '?abstract', nodetype 'literal', literal_type 'xsd:string')
)
SERVER dbpedia OPTIONS (
  sparql '
    PREFIX dbr: <http://dbpedia.org/resource/>
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>

    SELECT DISTINCT ?film ?name ?released ?runtime ?abstract
    WHERE
    {
      ?film a dbo:Film ;
            rdfs:comment ?abstract ;
            dbp:name ?name ;
            dbp:released ?released ;
            dbp:runtime ?runtime .
      FILTER (LANG ( ?abstract ) = "en")
      FILTER (datatype(?released) = xsd:date)
      FILTER (datatype(?runtime) = xsd:integer)
     }
'); 
```

> [!NOTE]  
> To visualise the foreign table's columns and options use the `psql` meta-commands `\d[+]` or `\det[+]`

### [ALTER FOREIGN TABLE and ALTER SERVER](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#alter-foreign-table-and-alter-server)

All options and parameters set to a `FOREIGN TABLE` or `SERVER` can be changed, dropped, and new ones can be added using the [`ALTER FOREIGN TABLE`](https://www.postgresql.org/docs/current/sql-alterforeigntable.html) and [`ALTER SERVER`](https://www.postgresql.org/docs/current/sql-alterserver.html) commands.


Adding options

```sql
ALTER FOREIGN TABLE film OPTIONS (ADD enable_pushdown 'false',
                                  ADD log_sparql 'true');

ALTER SERVER dbpedia OPTIONS (ADD enable_pushdown 'false');
```

Changing previously configured options

```sql
ALTER FOREIGN TABLE film OPTIONS (SET enable_pushdown 'false');

ALTER SERVER dbpedia OPTIONS (SET enable_pushdown 'true');
```

Dropping options

```sql
ALTER FOREIGN TABLE film OPTIONS (DROP enable_pushdown,
                                  DROP log_sparql);

ALTER SERVER dbpedia OPTIONS (DROP enable_pushdown);
```
### [Prefix Management](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#prefix-mangement)

To simplify the reuse and sharing of common SPARQL prefixes, `rdf_fdw` provides a prefix management system based on two catalog tables and a suite of helper functions.

This feature enables you to register prefix contexts (named groups of prefixes), and to associate specific prefix -> URI mappings under those contexts. This is especially useful when working with multiple RDF vocabularies or endpoint configurations.

#### [Prefix Context](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#context)

The prefix context is a named container for a set of SPARQL prefixes. It is represented by the table `sparql.prefix_contexts`:

| Column        | Type          | Description                          |
| ------------- | ------------- | ------------------------------------ |
| `context`     | `text`        | Primary key; name of the context.    |
| `description` | `text`        | Optional description of the context. |
| `modified_at` | `timestamptz` | Timestamp of the last update.        |

##### Functions

**Adding a new context**
```sql
sparql.add_context(context_name text, context_description text DEFAULT NULL, override boolean DEFAULT false)
```

Registers a new context. If override is set to `true` updates the context if it already exists, otherwise, raises an exception on conflict.

**Deleting an existing context**

```sql
sparql.drop_context(context_name text, cascade boolean DEFAULT false)
```
Deletes a context. If cascade is set to `true` deletes all associated prefixes, otherwise raises an exception if dependent prefixes exist.

#### [Prefix](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#prefix)

A prefix maps a shorthand identifier to a full URI within a context. These are stored in `sparql.prefixes`:

| Column        | Type          | Description                       |
| ------------- | ------------- | --------------------------------- |
| `prefix`      | `text`        | The SPARQL prefix label.          |
| `uri`         | `text`        | The fully qualified URI.          |
| `context`     | `text`        | Foreign key to `prefix_contexts`. |
| `modified_at` | `timestamptz` | Timestamp of the last update.     |

##### Functions

**Adding a new PREFIX**
```sql
sparql.add_prefix(context_name text, prefix_name text, uri text, override boolean DEFAULT false)
```
Adds a prefix to a context. If override is set to `true` updates the URI if the prefix already exists. Otherwise raises an exception on conflict.

***Deleting an existing PREFIX**

```sql
sparql.drop_prefix(context_name text, prefix_name text)
```
Removes a prefix from a context. Raises an exception if the prefix does not exist.

**Examples**

```sql
-- Create a context
SELECT sparql.add_context('default', 'Default SPARQL prefix context');

-- Add prefixes to it
SELECT sparql.add_prefix('default', 'rdf',  'http://www.w3.org/1999/02/22-rdf-syntax-ns#');
SELECT sparql.add_prefix('default', 'rdfs', 'http://www.w3.org/2000/01/rdf-schema#');
SELECT sparql.add_prefix('default', 'owl',  'http://www.w3.org/2002/07/owl#');
SELECT sparql.add_prefix('default', 'xsd',  'http://www.w3.org/2001/XMLSchema#');
```
Once registered, these prefixes can be automatically included in generated SPARQL queries for any `rdf_fdw` foreign server that references the associated context.

### [rdf_fdw_version](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#rdf_fdw_version)

```sql
text rdf_fdw_version();
```

**Description**

Returns comprehensive version information for `rdf_fdw`, PostgreSQL, compiler, and all dependencies (libxml, librdf, libcurl) in a single formatted string.

-------

**Usage**

```sql
SELECT rdf_fdw_version();
                                                      rdf_fdw_version                                                       
----------------------------------------------------------------------------------------------------------------------------
 rdf_fdw 2.2-dev (PostgreSQL 17.5 (Debian 17.5-1.pgdg110+1), compiled by gcc, libxml 2.9.10, librdf 1.0.17, libcurl 7.74.0)
(1 row)
```

### [rdf_fdw_settings](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#rdf_fdw_settings)

```sql
VIEW rdf_fdw_settings(component text, version text);
```

**Description**

A system view that provides detailed version information for `rdf_fdw` and all its dependencies, including core libraries (PostgreSQL, libxml, librdf, libcurl) and optional components (SSL, zlib, libSSH, nghttp2), along with compiler and build information. Returns individual component names and their corresponding versions for convenient programmatic access.

-------

**Usage**

```sql
SELECT * FROM rdf_fdw_settings;

 component  |            version             
------------+--------------------------------
 rdf_fdw    | 2.2-dev
 PostgreSQL | 17.5 (Debian 17.5-1.pgdg110+1)
 libxml     | 2.9.10
 librdf     | 1.0.17
 libcurl    | 7.74.0
 ssl        | GnuTLS/3.7.1
 zlib       | 1.2.11
 libSSH     | libssh2/1.9.0
 nghttp2    | 1.43.0
 compiler   | gcc
 built      | 2025-11-13 09:08:02 UTC
(11 rows)
```

### [rdf_fdw_clone_table](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#rdf_fdw_clone_table)

```sql
void rdf_fdw_clone_table(
  foreign_table text,
  target_table text,
  begin_offset int,
  fetch_size int,
  max_records int,
  orderby_column text,
  sort_order text,
  create_table boolean,
  verbose boolean,
  commit_page boolean
)
```

* PostgreSQL 11+ only

**Description**

This procedure is designed to copy data from a `FOREIGN TABLE` to an ordinary `TABLE`. It provides the possibility to retrieve the data set in batches, so that known issues related to triplestore limits and client's memory don't bother too much. 

**Parameters**

`foreign_table` **(required)**:  `FOREIGN TABLE` from where the data has to be copied.

`target_table` **(required)**: heap `TABLE` where the data from the `FOREIGN TABLE` is copied to.

`begin_offset`: starting point in the SPARQL query pagination. Default `0`.

`fetch_size`: size of the page fetched from the triplestore. Default is the value set at `fetch_size` in either `SERVER` or `FOREIGN TABLE`. In case `SERVER` and `FOREIGN TABLE` do not set `fetch_size`, the default will be set to `100`.

`max_records`: maximum number of records that should be retrieved from the `FOREIGN TABLE`. Default `0`, which means no limit. 

`orderby_column`: ordering column used for the pagination - just like in SQL `ORDER BY`. Default `''`, which means that the function will chose a column to use in the `ORDER BY` clause on its own. That is, the procedure will try to set the first column with the option `nodetype` set to `iri`. If the table has no `iri` typed `nodetype`, the first column will be chosen as ordering column. If you do not wish to have an `ORDER BY` clause at al, set this parameter to `NULL`.

`sort_order`: `ASC` or `DESC` to sort the data returned in ascending or descending order, respectivelly. Default `ASC`.

`create_table`: creates the table set in `target_table` before harvesting the `FOREIGN TABLE`. Default `false`.

`verbose`: prints debugging messages in the standard output. Default `false`.

`commit_page`: commits the inserted records immediatelly or only after the transaction is finished. Useful for those who want records to be discarded in case of an error - following the principle of *everything or nothing*. Default `true`, which means that all inserts will me committed immediatelly.

-------

**Usage Example**

```sql
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

CREATE FOREIGN TABLE public.dbpedia_cities (
  uri text           OPTIONS (variable '?city', nodetype 'iri'),
  city_name text     OPTIONS (variable '?name', nodetype 'literal', literal_type 'xsd:string'),
  elevation numeric  OPTIONS (variable '?elevation', nodetype 'literal', literal_type 'xsd:integer')
)
SERVER dbpedia OPTIONS (
  sparql '
    PREFIX dbo:  <http://dbpedia.org/ontology/>
    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
    PREFIX dbr:  <http://dbpedia.org/resource/>
    SELECT *
    {?city a dbo:City ;
      foaf:name ?name ;
      dbo:federalState dbr:North_Rhine-Westphalia ;
      dbo:elevation ?elevation
    }
');

/*
 * Materialize all records from the FOREIGN TABLE 'public.dbpedia_cities' in 
 * the table 'public.t1_local'. 
 */ 
CALL rdf_fdw_clone_table(
      foreign_table => 'dbpedia_cities',
      target_table  => 't1_local',
      create_table => true);

SELECT * FROM t1_local;
                            uri                            |      city_name      | elevation 
-----------------------------------------------------------+---------------------+-----------
 http://dbpedia.org/resource/Aachen                        | Aachen              |     173.0
 http://dbpedia.org/resource/Bielefeld                     | Bielefeld           |     118.0
 http://dbpedia.org/resource/Dortmund                      | Dortmund            |      86.0
 http://dbpedia.org/resource/Düsseldorf                    | Düsseldorf          |      38.0
 http://dbpedia.org/resource/Gelsenkirchen                 | Gelsenkirchen       |      60.0
 http://dbpedia.org/resource/Hagen                         | Hagen               |     106.0
 http://dbpedia.org/resource/Hamm                          | Hamm                |      37.7
 http://dbpedia.org/resource/Herne,_North_Rhine-Westphalia | Herne               |      65.0
 http://dbpedia.org/resource/Krefeld                       | Krefeld             |      39.0
 http://dbpedia.org/resource/Mönchengladbach               | Mönchengladbach     |      70.0
 http://dbpedia.org/resource/Mülheim                       | Mülheim an der Ruhr |      26.0
 http://dbpedia.org/resource/Münster                       | Münster             |      60.0
 http://dbpedia.org/resource/Remscheid                     | Remscheid           |     365.0
(13 rows)
```

## [RDF Node Handling](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#rdf-node-handling)
The `rdf_fdw` extension introduces a custom data type called `rdfnode` that represents full RDF nodes exactly as they appear in a triplestore. It supports:

- **IRIs** (e.g., `<http://example.org/resource>`)
- **Plain literals** (e.g., `"42"`)
- **Literals with language tags** (e.g., `"foo"@es`)
- **Typed literals** (e.g., `"42"^^xsd:integer`)

This type is useful when you want to inspect or preserve the full structure of RDF terms—including their language tags or datatypes—rather than just working with the value.

### Casting Between `rdfnode` and Native PostgreSQL Types

Although `rdfnode` preserves the full RDF term, you can cast it to standard PostgreSQL types like `text`, `int`, or `date` when you only care about the literal value. Likewise, native PostgreSQL values can be cast into `rdfnode`, with appropriate RDF serialization.

From `rdfnode` to PostgreSQL:

```sql
SELECT CAST('"42"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode AS int);
 int4 
------
   42
(1 row)

SELECT CAST('"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode AS numeric);
 numeric 
---------
   42.73
(1 row)

SELECT CAST('"2025-05-16"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode AS date);
    date    
------------
 2025-05-16
(1 row)

SELECT CAST('"2025-05-16T06:41:50"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode AS timestamp);
      timestamp      
---------------------
 2025-05-16 06:41:50
(1 row)
```
From PostgreSQL to `rdfnode`:

```sql
SELECT CAST('"foo"^^xsd:string' AS rdfnode);
                     rdfnode                      
--------------------------------------------------
 "foo"^^<http://www.w3.org/2001/XMLSchema#string>
(1 row)

SELECT CAST(42.73 AS rdfnode);
                       rdfnode                       
-----------------------------------------------------
 "42.73"^^<http://www.w3.org/2001/XMLSchema#decimal>
(1 row)

SELECT CAST(422892987223 AS rdfnode);
                         rdfnode                         
---------------------------------------------------------
 "422892987223"^^<http://www.w3.org/2001/XMLSchema#long>
(1 row)

SELECT CAST(CURRENT_DATE AS rdfnode);
                     current_date                      
-------------------------------------------------------
 "2025-05-16"^^<http://www.w3.org/2001/XMLSchema#date>
(1 row)

SELECT CAST(CURRENT_TIMESTAMP AS rdfnode);
                             current_timestamp                              
----------------------------------------------------------------------------
 "2025-05-16T06:41:50.221129Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>
(1 row)
```

### Choosing Between rdfnode and Native PostgreSQL Types

You can define foreign table columns using either:

* `rdfnode` **(recommended)** — Use this when you want to preserve the full RDF term, including language tags, datatypes, and IRIs. This is also required if you want to use SPARQL functions, which do not support native PostgreSQL types.

* PostgreSQL native types (e.g., `text`, `int`, `date`) — Use these when you prefer automatic type coercion and simpler SQL filtering, treating RDF values more like regular PostgreSQL data.

In short:

* Use rdfnode when you need full RDF semantics or access to SPARQL-specific features.
* Use native types when you prefer SQL-like convenience and don’t require RDF semantics or SPARQL functions.

### Comparison of `rdfnode` with Native PostgreSQL Types

`rdfnode` supports standard comparison operators like `=`, `!=`, `<`, `<=`, `>`, `>=` — just like in SPARQL. Comparisons follow SPARQL 1.1 [RDFterm-equal](https://www.w3.org/TR/sparql11-query/#func-RDFterm-equal) rules.

Examples: `rdfnode` vs `rdfnode`

```sql
SELECT '"foo"@en'::rdfnode = '"foo"@fr'::rdfnode;
 ?column? 
----------
 f
(1 row)

SELECT '"foo"^^xsd:string'::rdfnode > '"foobar"^^xsd:string'::rdfnode;
 ?column? 
----------
 f
(1 row)

SELECT '"foo"^^xsd:string'::rdfnode < '"foobar"^^xsd:string'::rdfnode;
 ?column? 
----------
 t
(1 row)

 SELECT '"42"^^xsd:int'::rdfnode = '"42"^^xsd:short'::rdfnode;
 ?column? 
----------
 t
(1 row)

 SELECT '"73.42"^^xsd:float'::rdfnode < '"100"^^xsd:short'::rdfnode;
 ?column? 
----------
 t
(1 row)
```

The `rdfnode` data type also allow comparisons with PostgreSQL native data types, such as `int`, `date`, `numeric`, etc.

Examples: `rdfnode` vs PostgreSQL types

```sql
SELECT '"42"^^xsd:int'::rdfnode = 42;
 ?column? 
----------
 t
(1 row)

SELECT '"2010-01-08"^^xsd:date'::rdfnode < '2020-12-30'::date;
 ?column? 
----------
 t
(1 row)

SELECT '"42.73"^^xsd:decimal'::rdfnode > 42;
 ?column? 
----------
 t
(1 row)

SELECT '"42.73"^^xsd:decimal'::rdfnode < 42.99;
 ?column? 
----------
 t
(1 row)

SELECT '"2025-05-19T10:45:42Z"^^xsd:dateTime'::rdfnode = '2025-05-19 10:45:42'::timestamp;
 ?column? 
----------
 t
(1 row)
```

## [SPARQL Functions](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#sparql-functions)

`rdf_fdw` implements most of the [SPARQL 1.1 built-in functions](https://www.w3.org/TR/sparql11-query/#funcs), exposing them as SQL-callable functions under the dedicated `sparql` schema. This avoids conflicts with similarly named built-in PostgreSQL functions such as `round`, `replace`, or `ceil`. These functions operate on RDF values retrieved through `FOREIGN TABLEs` and can be used in SQL queries or as part of pushdown expressions. They adhere closely to SPARQL semantics, including handling of RDF literals, language tags, datatypes, and null propagation rules, enabling expressive and standards-compliant RDF querying directly inside PostgreSQL.

> [!WARNING]  
> While most RDF triplestores claim SPARQL 1.1 compliance, their behavior often diverges from the standard—particularly in how they handle literals with language tags or datatypes. For example, the following query may produce different results depending on the backend:
>
>```sparql
>SELECT (REPLACE("foo"@en, "o"@de, "xx"@fr) AS ?str) {}
>```
>* Virtuoso &rarr; `"fxxxx"`
>* Blazegraph &rarr; **Unknown error**: *incompatible operand for REPLACE: "o"@de*
>* GraphDB &rarr; `"fxxxx"@en`
>
>Such inconsistencies can lead to unexpected or confusing results. To avoid surprises:
>* Always test how your target triplestore handles tagged or typed literals.
>* Consider simpler (less performant) alternatives like [`STR`](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#str) when working with language-tagged values.
>* Enable the `log_sparql` option in `rdf_fdw` to compare the number of records returned by the SPARQL endpoint with those visible in PostgreSQL. If the counts differ, it likely means some records were filtered out locally due to incompatible behavior in pushdown function evaluation.

### [SUM](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#sum)

```sql
sparql.sum(value rdfnode) → rdfnode
```

Computes the sum of numeric `rdfnode` values with XSD type promotion according to SPARQL 1.1 specification ([section 18.5.1.3](https://www.w3.org/TR/sparql11-query/#aggregates)). The function follows XPath type promotion rules where numeric types are promoted in the hierarchy: `xsd:integer` < `xsd:decimal` < `xsd:float` < `xsd:double`. The result type is determined by the highest type encountered during aggregation.

Examples:

```sql
-- Sum of integers returns integer
SELECT sparql.sum(val) 
FROM (VALUES ('"10"^^xsd:integer'::rdfnode),
             ('"20"^^xsd:integer'::rdfnode),
             ('"30"^^xsd:integer'::rdfnode)) AS t(val);
                       sum                        
--------------------------------------------------
 "60"^^<http://www.w3.org/2001/XMLSchema#integer>
(1 row)

-- Mixing integer and decimal promotes to decimal
SELECT sparql.sum(val)
FROM (VALUES ('"10"^^xsd:integer'::rdfnode), 
             ('"20.5"^^xsd:decimal'::rdfnode),
             ('"30"^^xsd:integer'::rdfnode)) AS t(val);
                        sum                         
----------------------------------------------------
 "60.5"^^<http://www.w3.org/2001/XMLSchema#decimal>
(1 row)

-- Mixing with float promotes to float
SELECT sparql.sum(val)
FROM (VALUES ('"10.5"^^xsd:decimal'::rdfnode),
             ('"20.3"^^xsd:decimal'::rdfnode),
             ('"5"^^xsd:float'::rdfnode)) AS t(val);
                       sum                        
--------------------------------------------------
 "35.8"^^<http://www.w3.org/2001/XMLSchema#float>
(1 row)
```

> [!NOTE]  
> The `SUM` aggregate follows SPARQL 1.1 semantics ([section 18.5.1.3](https://www.w3.org/TR/sparql11-query/#aggregates)):
>* NULL values (unbound variables) are skipped during aggregation
>* Returns `"0"^^xsd:integer` for empty sets or when all values are NULL (per spec: "The sum of no bindings is 0")
>* Non-numeric values cause type errors and are excluded from the aggregate (similar to NULL)
>* Returns SQL NULL if all values are non-numeric (no numeric values to sum)
>* Type promotion ensures precision is maintained (e.g., integer → decimal → float → double)
>* All XSD integer subtypes (`xsd:int`, `xsd:long`, `xsd:short`, `xsd:byte`, etc.) are treated as `xsd:integer`

### [AVG](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#avg)

```sql
sparql.avg(value rdfnode) → rdfnode
```

Computes the average (arithmetic mean) of numeric `rdfnode` values with XSD type promotion according to SPARQL 1.1 specification ([section 18.5.1.4](https://www.w3.org/TR/sparql11-query/#aggregates)). Like `SUM`, the function follows XPath type promotion rules: `xsd:integer` < `xsd:decimal` < `xsd:float` < `xsd:double`. The result type is determined by the highest type encountered during aggregation.

Examples:

```sql
-- Average of integers returns integer
SELECT sparql.avg(val)
FROM (VALUES ('"10"^^xsd:integer'::rdfnode),
             ('"20"^^xsd:integer'::rdfnode),
             ('"30"^^xsd:integer'::rdfnode)) AS t(val);
                                avg                                
-------------------------------------------------------------------
 "20.0000000000000000"^^<http://www.w3.org/2001/XMLSchema#integer>
(1 row)

-- Mixing integer and decimal promotes to decimal
SELECT sparql.avg(val)
FROM (VALUES ('"10"^^xsd:integer'::rdfnode),
             ('"20.5"^^xsd:decimal'::rdfnode),
             ('"30"^^xsd:integer'::rdfnode)) AS t(val);
                                avg                                
-------------------------------------------------------------------
 "20.1666666666666667"^^<http://www.w3.org/2001/XMLSchema#decimal>
(1 row)

-- NULL values are skipped
SELECT sparql.avg(val)
FROM (VALUES ('"10"^^xsd:integer'::rdfnode),
             (NULL::rdfnode),
             ('"30"^^xsd:integer'::rdfnode)) AS t(val);
                                avg                                
-------------------------------------------------------------------
 "20.0000000000000000"^^<http://www.w3.org/2001/XMLSchema#integer>
(1 row)
```

> [!NOTE]  
> The `AVG` aggregate follows SPARQL 1.1 semantics ([section 18.5.1.4](https://www.w3.org/TR/sparql11-query/#aggregates)):
>* NULL values (unbound variables) are skipped during aggregation
>* Returns `"0"^^xsd:integer` for empty sets or when all values are NULL (per spec: "Avg({}) = 0/0 = 0")
>* Non-numeric values cause type errors and are excluded from the aggregate (similar to NULL)
>* Returns SQL NULL if all values are non-numeric (no numeric values to average)
>* Division by count is performed using PostgreSQL's numeric division
>* Type promotion follows the same rules as SUM (integer → decimal → float → double)

### [MIN](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#min)

```sql
sparql.min(value rdfnode) → rdfnode
```

Returns the minimum numeric `rdfnode` value according to SPARQL 1.1 specification ([section 18.5.1.5](https://www.w3.org/TR/sparql11-query/#aggregates)). The function preserves the XSD datatype of the minimum value found. When comparing values of different numeric types, they are promoted to a common type following XPath rules before comparison.

Examples:

```sql
-- Minimum of integers
SELECT sparql.min(val)
FROM (VALUES ('"30"^^xsd:integer'::rdfnode),
             ('"10"^^xsd:integer'::rdfnode),
             ('"20"^^xsd:integer'::rdfnode)) AS t(val);
                       min                        
--------------------------------------------------
 "10"^^<http://www.w3.org/2001/XMLSchema#integer>
(1 row)

-- Minimum with negative values
SELECT sparql.min(val)
FROM (VALUES ('"10"^^xsd:integer'::rdfnode),
             ('"-5"^^xsd:integer'::rdfnode),
             ('"3"^^xsd:integer'::rdfnode)) AS t(val);
                       min                        
--------------------------------------------------
 "-5"^^<http://www.w3.org/2001/XMLSchema#integer>
(1 row)
```

> [!NOTE]  
> The `MIN` aggregate follows SPARQL 1.1 semantics with SQL-compatible NULL handling:
>* NULL values are skipped during aggregation
>* Returns SQL NULL when all input values are NULL (no value to select)
>* Returns SQL NULL for empty result sets (no rows match WHERE clause)

### [MAX](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#max)

```sql
sparql.max(value rdfnode) → rdfnode
```

Returns the maximum numeric `rdfnode` value according to SPARQL 1.1 specification ([section 18.5.1.6](https://www.w3.org/TR/sparql11-query/#aggregates)). The function preserves the XSD datatype of the maximum value found. When comparing values of different numeric types, they are promoted to a common type following XPath rules before comparison.

Examples:

```sql
-- Maximum of integers
SELECT sparql.max(val)
FROM (VALUES ('"30"^^xsd:integer'::rdfnode),
             ('"10"^^xsd:integer'::rdfnode),
             ('"20"^^xsd:integer'::rdfnode)) AS t(val);
                       max                        
--------------------------------------------------
 "30"^^<http://www.w3.org/2001/XMLSchema#integer>
(1 row)

-- Maximum with negative values
SELECT sparql.max(val)
FROM (VALUES ('"-10"^^xsd:integer'::rdfnode),
             ('"-5"^^xsd:integer'::rdfnode),
             ('"-20"^^xsd:integer'::rdfnode)) AS t(val);
                       max                        
--------------------------------------------------
 "-5"^^<http://www.w3.org/2001/XMLSchema#integer>
(1 row)
```

> [!NOTE]  
> The `MAX` aggregate follows SPARQL 1.1 semantics with SQL-compatible NULL handling:
>* NULL values are skipped during aggregation
>* Returns SQL NULL when all input values are NULL (no value to select)
>* Returns SQL NULL for empty result sets (no rows match WHERE clause)

### [BOUND](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#bound)

```sql
sparql.bound(value rdfnode) → boolean
```

Returns `true` if the RDF node is *bound* to a value, and `false` otherwise. Values like `NaN` or `INF` are considered bound.

Example:
```sql
SELECT sparql.bound(NULL), sparql.bound('"NaN"^^xsd:double');
 bound | bound 
-------+-------
 f     | t
(1 row)
```

### [COALESCE](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#coalesce)

```sql
sparql.coalesce(value1 rdfnode, value2 rdfnode, ... ) → rdfnode
```

Returns the **first bound** RDF node from the argument list. If none of the inputs are bound (i.e., all are `NULL`), returns `NULL`. The behavior mimics the SPARQL 1.1 `COALESCE()` function, valuating arguments from left to right. This is useful when working with optional data where fallback values are needed.

Example:

```sql
 SELECT sparql.coalesce(NULL, NULL, '"foo"^^xsd:string');
                     coalesce                     
--------------------------------------------------
 "foo"^^<http://www.w3.org/2001/XMLSchema#string>
(1 row)
```

### [SAMETERM](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#sameterm)

```sql
sparql.sameTerm(a rdfnode, b rdfnode) → boolean
```

Returns `true` if the two RDF nodes are exactly the same term, and `false` otherwise. This comparison is strict and includes datatype, language tag, and node type (e.g., literal vs IRI). The behavior follows SPARQL 1.1's [sameTerm functional form](https://www.w3.org/TR/sparql11-query/#func-sameTerm), which does not allow coercion or implicit casting — unlike `=` or `IS NOT DISTINCT FROM`.

Examples:

```sql
SELECT sparql.sameterm('"42"^^xsd:int', '"42"^^xsd:long');
 sameterm 
----------
 f
(1 row)

SELECT sparql.sameterm('"foo"@en', '"foo"@en');
 sameterm 
----------
 t
(1 row)

SELECT sparql.sameterm('"foo"@en', '"foo"@fr');
 sameterm 
----------
 f
(1 row)
```

> [!NOTE]  
> Use `sameterm` when you need exact RDF identity, including type and language tag. For value-based comparison with implicit coercion, use `=` instead.

## [isIRI](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#isiri)

```sql
sparql.isiri(value rdfnode) → boolean
```
Returns `true` if the given RDF node is an IRI, and `false` otherwise. This function implements the SPARQL 1.1 [isIRI()](https://www.w3.org/TR/sparql11-query/#func-isIRI) test, which checks whether the term is an IRI—not a literal, blank node, or unbound value.

Examples:

```sql
SELECT sparql.isIRI('<https://foo.bar/>'); 
 isiri 
-------
 t
(1 row)

SELECT sparql.isIRI('"foo"^^xsd:string');
 isiri 
-------
 f
(1 row)

SELECT sparql.isIRI('_:bnode42');
 isiri 
-------
 f
(1 row)

SELECT sparql.isIRI(NULL);
 isiri 
-------
 f
(1 row)
```

> [!NOTE]  
> isURI is an alternate spelling for the isIRI function.

## [isBLANK](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#isblank)
```sql
sparql.isblank(value rdfnode) → boolean
```

Returns `true` if the given RDF node is a blank node, and `false` otherwise. This function implements the SPARQL 1.1 [isBlank()](https://www.w3.org/TR/sparql11-query/#func-isBlank) function, which is used to detect anonymous resources (blank nodes) in RDF graphs.

```sql
SELECT sparql.isblank('_:bnode42');
 isblank 
---------
 t
(1 row)

SELECT sparql.isblank('"foo"^^xsd:string');
 isblank 
---------
 f
(1 row)
```

## [isLITERAL](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#isliteral)

```sql
sparql.isliteral(value rdfnode) → boolean
```

Returns `true` if the given RDF node is a literal, and `false` otherwise. This function implements the SPARQL 1.1 [isLiteral()](https://www.w3.org/TR/sparql11-query/#func-isLiteral) test. It returns `false` for IRIs, blank nodes, and unbound (`NULL`) values.

Examples:

```sql
SELECT sparql.isliteral('"foo"^^xsd:string');
 isliteral 
-----------
 t
(1 row)

SELECT sparql.isliteral('"foo"^^@es');
 isliteral 
-----------
 t
(1 row)

SELECT sparql.isliteral('_:bnode42');
 isliteral 
-----------
 f
(1 row)

SELECT sparql.isliteral('<http://foo.bar>');
 isliteral 
-----------
 f
(1 row)

SELECT sparql.isliteral(NULL);
 isliteral 
-----------
 f
(1 row)
```

## [isNUMERIC](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#isnumeric)

```sql
sparql.isnumeric(term rdfnode) → boolean
```

Returns `true` if the RDF node is a literal with a numeric datatype (such as `xsd:int`, `xsd:decimal`, etc.), and `false` otherwise. See the SPARQL 1.1 section on [Operand Data Types](https://www.w3.org/TR/sparql11-query/#operandDataTypes) for more details.

Examples:

```sql
SELECT sparql.isnumeric('"42"^^xsd:integer');
 isnumeric 
-----------
 t
(1 row)

SELECT sparql.isnumeric('"42.73"^^xsd:decimal');
 isnumeric 
-----------
 t
(1 row)

SELECT sparql.isnumeric('"42.73"^^xsd:string');
 isnumeric 
-----------
 f
(1 row)

SELECT sparql.isnumeric(NULL);
 isnumeric 
-----------
 f
(1 row)
```

## [STR](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#str)

```sql
sparql.str(value rdfnode) → rdfnode
```
Returns the **lexical form** (the string content) of the RDF node, as described at This implements the SPARQL 1.1 [str()](https://www.w3.org/TR/sparql11-query/#func-str) specification. For literals, this means stripping away the language tag or datatype. For IRIs, it returns the IRI string. For blank nodes, returns their label.

Examples:

```sql
SELECT sparql.str('"foo"@en');
  str  
-------
 "foo"
(1 row)

SELECT sparql.str('"foo"^^xsd:string');
  str  
-------
 "foo"
(1 row)

SELECT sparql.str('<http://foo.bar>');
       str        
------------------
 "http://foo.bar"
(1 row)
```

## [LANG](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#lang)

```sql
sparql.str(value rdfnode) → rdfnode
```

Returns the language tag of the literal, or an empty string if none exists. Implements the SPARQL 1.1 [LANG()](https://www.w3.org/TR/sparql11-query/#func-lang) function. All other RDF nodes — including IRIs, blank nodes, and typed literals — return an empty string.

```sql
SELECT sparql.lang('"foo"@es');
 lang 
------
 es
(1 row)

SELECT sparql.lang('"foo"');
 lang 
------
 
(1 row)

SELECT sparql.lang('"foo"^^xsd:string');
 lang 
------
 
(1 row)
```

## [DATATYPE](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#datatype)

```sql
sparql.datatype(value rdfnode) → rdfnode
```

Returns the **datatype IRI** of a literal RDF node.

* For typed literals, returns the declared datatype (e.g., `xsd:int`, `xsd:dateTime`, etc.).
* For plain (untyped) literals, returns `xsd:string`.
* For language-tagged literals, returns `rdf:langString`.
* For non-literals (IRIs, blank nodes), returns `NULL`.

This behavior complies with both SPARQL 1.1 and RDF 1.1.

Examples:

```sql
SELECT sparql.datatype('"42"^^xsd:int');
                datatype                
----------------------------------------
 <http://www.w3.org/2001/XMLSchema#int>
(1 row)

SELECT sparql.datatype('"foo"');
                 datatype                  
-------------------------------------------
 <http://www.w3.org/2001/XMLSchema#string>
(1 row)

SELECT sparql.datatype('"foo"@de');
                        datatype                         
---------------------------------------------------------
 <http://www.w3.org/1999/02/22-rdf-syntax-ns#langString>
(1 row)

SELECT sparql.datatype('<http://foo.bar>');
 datatype 
----------
 NULL
(1 row)

SELECT sparql.datatype('_:bnode42');
 datatype 
----------
 NULL
(1 row)
```

> [!NOTE]  
> Keep in mind that some triplestores (like Virtuoso) return `xsd:anyURI` for IRIs, but this behaviour is not defined in SPARQL 1.1 and is not standard-compliant.

## [IRI](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#iri)

```sql
sparql.iri(value rdfnode) → rdfnode
```

Constructs an RDF IRI from a string. Implements the SPARQL 1.1 [IRI()](https://www.w3.org/TR/sparql11-query/#func-iri) function. If the input is not a valid IRI, the function still wraps it as-is into an RDF IRI. No validation is performed.

Examples:

```sql
SELECT sparql.iri('http://foo.bar');
       iri        
------------------
 <http://foo.bar>
(1 row)
```

## [BNODE](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#bnode)

```sql
sparql.bnode(value rdfnode DEFAULT NULL) → rdfnode
```
Constructs a blank node. If a string is provided, it's used as the label. If called with no argument, generates an automatically scoped blank node identifier. Implements the SPARQL 1.1 [BNODE()](https://www.w3.org/TR/sparql11-query/#func-bnode) function.

Examples:

```sql
SELECT sparql.bnode('foo');
 bnode 
-------
 _:foo
(1 row)

SELECT sparql.bnode('"foo"^^xsd:string');
 bnode 
-------
 _:foo
(1 row)

SELECT sparql.bnode();
       bnode        
--------------------
 _:b800704569809508
(1 row)
```

## [STRDT](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#strdt)

```sql
sparql.strdt(lexical rdfnode, datatype_iri rdfnode) → rdfnode
```

Constructs a typed literal from a lexical string and a datatype IRI. Implements the SPARQL 1.1 [STRDT()](https://www.w3.org/TR/sparql11-query/#func-strdt) function. This function can also be used to change the datatype of an existing literal by extracting its lexical form (e.g., with `sparql.str()`) and applying a new datatype.

Examples:

```sql
SELECT sparql.strdt('42','xsd:int');
                    strdt                     
----------------------------------------------
 "42"^^<http://www.w3.org/2001/XMLSchema#int>
(1 row)

SELECT sparql.strdt('2025-01-01', 'http://www.w3.org/2001/XMLSchema#date');
                         strdt                         
-------------------------------------------------------
 "2025-01-01"^^<http://www.w3.org/2001/XMLSchema#date>
(1 row)

SELECT sparql.strdt('"2025-01-01"^^xsd:string', 'http://www.w3.org/2001/XMLSchema#date');
                         strdt                         
-------------------------------------------------------
 "2025-01-01"^^<http://www.w3.org/2001/XMLSchema#date>
(1 row)
```

## [STLANG](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#strlang)

```sql
sparql.strlang(lexical rdfnode, lang_tag rdfnode) → rdfnode
```
Constructs a language-tagged literal from a string and a language code. Implements the SPARQL 1.1 [STRLANG()](https://www.w3.org/TR/sparql11-query/#func-strlang) function. You can also use this function to re-tag an existing literal by extracting its lexical form and assigning a new language tag.

Examples:

```sql
SELECT sparql.strlang('foo','pt');
 strlang  
----------
 "foo"@pt
(1 row)

SELECT sparql.strlang('"foo"@pt','es');
 strlang  
----------
 "foo"@es
(1 row)
```

## [UUID](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#uuid)

```sql
sparql.uuid() → rdfnode
```

Generates a fresh, globally unique IRI. Implements the SPARQL 1.1 [UUID()](https://www.w3.org/TR/sparql11-query/#func-uuid) function.

Example:

```sql
SELECT sparql.uuid();
                      uuid                       
-------------------------------------------------
 <urn:uuid:1beda602-2e35-4d13-a907-071454d2fce7>
(1 row)
```

## [STRUUID](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#struuid)

```sql
sparql.struuid() → rdfnode
```

Generates a fresh, random UUID as a plain literal string. Implements the SPARQL 1.1 [STRUUID()](https://www.w3.org/TR/sparql11-query/#func-struuid) function. Each call returns a unique string literal containing the UUID. This is useful when you want to store or display the UUID as text rather than an IRI.

Example:

```sql
SELECT sparql.struuid();
                struuid                 
----------------------------------------
 "25a55e10-f789-4aab-bb7f-05f2ba495fd2"
(1 row)
```

## [STRLEN](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#strlen)

```sql
sparql.strlen(value rdfnode) → int
```

Returns the number of characters in the **lexical form** of the RDF node. Implements the SPARQL 1.1 [STRLEN()](https://www.w3.org/TR/sparql11-query/#func-strlen) function.

Examples:

```sql
SELECT sparql.strlen('"foo"');
 strlen 
--------
      3
(1 row)

SELECT sparql.strlen('"foo"@de');
 strlen 
--------
      3
(1 row)

SELECT sparql.strlen('"foo"^^xsd:string');
 strlen 
--------
      3
(1 row)

SELECT sparql.strlen('"42"^^xsd:int');
 strlen 
--------
      2
(1 row)
```

## [SUBSTR](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#substr)

```sql
sparql.substr(value rdfnode, start int, length int DEFAULT NULL) → rdfnode
```

Extracts a substring from the lexical form of the RDF node. Implements the SPARQL 1.1 [SUBSTR()](https://www.w3.org/TR/sparql11-query/#func-substr) function.

* The start index is 1-based.
* If length is omitted, returns everything to the end of the string.
* returns `NULL` if any of the arguments is `NULL`

Examples:

```sql
SELECT sparql.substr('"foobar"', 1, 3);
 substr 
--------
 "foo"
(1 row)

SELECT sparql.substr('"foobar"', 4);
 substr 
--------
 "bar"
(1 row)
```

## [UCASE](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#ucase)

```sql
sparql.ucase(value rdfnode) → rdfnode
```

Converts the **lexical form** of the literal to uppercase. Implements the SPARQL 1.1 [UCASE()](https://www.w3.org/TR/sparql11-query/#func-ucase) function.

Examples:

```sql
SELECT sparql.ucase('"foo"');
 ucase 
-------
 "FOO"
(1 row)

SELECT sparql.ucase('"foo"@en');
  ucase   
----------
 "FOO"@en
(1 row)

SELECT sparql.ucase('"foo"^^xsd:string');
                      ucase                       
--------------------------------------------------
 "FOO"^^<http://www.w3.org/2001/XMLSchema#string>
(1 row)
```

## [LCASE](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#lcase)

```sql
sparql.lcase(value rdfnode) → rdfnode
```

Converts the **lexical form** of the literal to lowercase. Implements the SPARQL 1.1 [LCASE()](https://www.w3.org/TR/sparql11-query/#func-lcase) function.

Examples:

```sql
SELECT sparql.lcase('"FOO"');
 lcase 
-------
 "foo"
(1 row)

SELECT sparql.lcase('"FOO"@en');
  lcase   
----------
 "foo"@en
(1 row)

SELECT sparql.lcase('"FOO"^^xsd:string');
                      lcase                       
--------------------------------------------------
 "foo"^^<http://www.w3.org/2001/XMLSchema#string>
(1 row)
```

## [STRSTARTS](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#strstarts)

```sql
sparql.strstarts(value rdfnode, prefix rdfnode) → boolean
```

Returns `true` if the **lexical form** of the RDF node starts with the given string. Implements the SPARQL 1.1 [STRSTARTS()](https://www.w3.org/TR/sparql11-query/#func-strstarts) function.

Examples:

```sql
SELECT sparql.strstarts('"foobar"^^xsd:string', '"foo"^^xsd:string');
 strstarts 
-----------
 t
(1 row)

SELECT sparql.strstarts('"foobar"@en', '"foo"^^xsd:string');
 strstarts 
-----------
 t
(1 row)
```

## [STRENDS](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#strends)

```sql
sparql.strends(value rdfnode, suffix rdfnode) → boolean
```

Returns `true` if the **lexical form** of the RDF node ends with the given string. Implements the SPARQL 1.1 [STRENDS() ](https://www.w3.org/TR/sparql11-query/#func-strends)function.

Examples:

```sql
SELECT sparql.strends('"foobar"^^xsd:string', '"bar"^^xsd:string');
 strends 
---------
 t
(1 row)

SELECT sparql.strends('"foobar"@en', '"bar"^^xsd:string');
 strends 
---------
 t
(1 row)
```

## [CONTAINS](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#contains)

```sql
sparql.contains(value rdfnode, substring rdfnode) → boolean
```

Returns `true` if the **lexical form** of the RDF node contains the given substring. Implements the SPARQL 1.1 [CONTAINS()](https://www.w3.org/TR/sparql11-query/#func-contains) function.

Examples:

```sql
SELECT sparql.contains('"_foobar_"^^xsd:string', '"foo"');
 contains 
----------
 t
(1 row)

SELECT sparql.contains('"_foobar_"^^xsd:string', '"foo"@en');
 contains 
----------
 t
(1 row)
```

## [STRBEFORE](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#strbefore)

```sql
sparql.strbefore(value rdfnode, delimiter rdfnode) → rdfnode
```

Returns the substring before the first occurrence of the delimiter in the **lexical form**. If the delimiter is not found, returns an empty string. Implements the SPARQL 1.1 [STRBEFORE()](https://www.w3.org/TR/sparql11-query/#func-strbefore) function.

Examples:

```sql
SELECT sparql.strbefore('"foobar"^^xsd:string','"bar"^^xsd:string');
                    strbefore                     
--------------------------------------------------
 "foo"^^<http://www.w3.org/2001/XMLSchema#string>
(1 row)

SELECT sparql.strbefore('"foobar"@en','"bar"^^xsd:string');
 strbefore 
-----------
 "foo"@en
(1 row)

SELECT sparql.strbefore('"foobar"','"bar"^^xsd:string');
 strbefore 
-----------
 "foo"
(1 row)

SELECT sparql.strbefore('"foobar"','"bar"');
 strbefore 
-----------
 "foo"
(1 row)
```

## [STRAFTER](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#strafter)

```sql
sparql.strafter(value rdfnode, delimiter rdfnode) → rdfnode
```

Returns the substring after the first occurrence of the delimiter in the **lexical form**. If the delimiter is not found, returns an empty string. Implements the SPARQL 1.1 [STRAFTER()](https://www.w3.org/TR/sparql11-query/#func-strafter) function.

Examples:

```sql
SELECT sparql.strafter('"foobar"^^xsd:string','"foo"^^xsd:string');
                     strafter                     
--------------------------------------------------
 "bar"^^<http://www.w3.org/2001/XMLSchema#string>
(1 row)

SELECT sparql.strafter('"foobar"@en','"foo"^^xsd:string');
 strafter 
----------
 "bar"@en
(1 row)

SELECT sparql.strafter('"foobar"','"foo"^^xsd:string');
 strafter 
----------
 "bar"
(1 row)

SELECT sparql.strafter('"foobar"','"foo"');
 strafter 
----------
 "bar"
(1 row)
```

## [ENCODE_FOR_URI](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#encode_for_uri)

```sql
sparql.encode_for_uri(value rdfnode) → rdfnode
```

Returns a URI-safe version of the lexical form by percent-encoding special characters. Implements the SPARQL 1.1 [ENCODE_FOR_URI()](https://www.w3.org/TR/sparql11-query/#func-encode) function.

```sql
SELECT sparql.encode_for_uri('"foo&bar!"');
 encode_for_uri 
----------------
 "foo%26bar%21"
(1 row)
```

## [CONCAT](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#concat)

```sql
sparql.concat(value1 rdfnode, value2 rdfnode, ...) → rdfnode
```

Concatenates all input strings into one. Implements the SPARQL 1.1 [CONCAT()](https://www.w3.org/TR/sparql11-query/#func-concat) function.


```sql
SELECT sparql.concat('"foo"@en','"&"@en', '"bar"@en');
    concat    
--------------
 "foo&bar"@en
(1 row)

SELECT sparql.concat('"foo"^^xsd:string','"&"^^xsd:string', '"bar"^^xsd:string');
                        concat                        
------------------------------------------------------
 "foo&bar"^^<http://www.w3.org/2001/XMLSchema#string>
(1 row)

SELECT sparql.concat('"foo"','"&"', '"bar"');
  concat   
-----------
 "foo&bar"
(1 row)
```

## [LANGMATCHES](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#langmatches)

```sql
sparql.langmatches(lang_tag rdfnode, pattern rdfnode) → boolean
```

Checks whether a language tag matches a language pattern (e.g., `en` matches `en-US`).
Implements the SPARQL 1.1 [LANGMATCHES()](https://www.w3.org/TR/sparql11-query/#func-langMatches) function.

Example:

```sql
SELECT sparql.langmatches('en', 'en');
 langmatches 
-------------
 t
(1 row)

SELECT sparql.langmatches('en-US', 'en');
 langmatches 
-------------
 t
(1 row)

SELECT sparql.langmatches('en', 'de');
 langmatches 
-------------
 f
(1 row)

SELECT sparql.langmatches('en', '*');
 langmatches 
-------------
 t
(1 row)
```

## [REGEX](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#regex)

```sql
sparql.regex(value rdfnode, pattern rdfnode, flags rdfnode DEFAULT '') → boolean
```

Checks if the lexical form matches the given regular expression. Implements the SPARQL 1.1 [REGEX()](https://www.w3.org/TR/sparql11-query/#func-regex) function.

* Supported flags: `i` (case-insensitive)

Example:

```sql
SELECT sparql.regex('"Hello World"', '^hello', 'i');
 regex 
-------
 t
(1 row)
```

## [REPLACE](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#replace)

```sql
sparql.replace(value rdfnode, pattern rdfnode, replacement rdfnode, flags rdfnode DEFAULT '') → rdfnode

```

Replaces parts of the **lexical form** using a regular expression. Implements the SPARQL 1.1 [REPLACE()](https://www.w3.org/TR/sparql11-query/#func-replace) function.

* Supports `i`, `m`, and `g` flags.

```sql
SELECT sparql.replace('"foo bar foo"', 'foo', 'baz', 'g');
    replace    
---------------
 "baz bar baz"
(1 row)
```

## [ABS](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#abs)

```sql
sparql.abs(value rdfnode) → numeric
```

Returns the absolute value of a numeric literal. Implements the SPARQL 1.1 [ABS()](https://www.w3.org/TR/sparql11-query/#func-abs) function.

Examples:

```sql
SELECT sparql.abs('"-42"^^xsd:int');
                     abs                      
----------------------------------------------
 "42"^^<http://www.w3.org/2001/XMLSchema#int>
(1 row)

SELECT sparql.abs('"3.14"^^xsd:decimal');
                        abs                         
----------------------------------------------------
 "3.14"^^<http://www.w3.org/2001/XMLSchema#decimal>
(1 row)
```

## [ROUND](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#round)

```sql
sparql.round(value rdfnode) → numeric
```

Rounds the numeric literal to the nearest integer. Implements the SPARQL 1.1 [ROUND()](https://www.w3.org/TR/sparql11-query/#func-round) function.

Examples:

```sql
SELECT sparql.round('"2.5"^^xsd:decimal');
                      round                      
-------------------------------------------------
 "3"^^<http://www.w3.org/2001/XMLSchema#decimal>
(1 row)

SELECT sparql.round('"-2.5"^^xsd:float');
                     round                      
------------------------------------------------
 "-2"^^<http://www.w3.org/2001/XMLSchema#float>
(1 row)
```

## [CEIL](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#ceil)

```sql
sparql.ceil(value rdfnode) → numeric
```
Returns the smallest integer greater than or equal to the numeric value. Implements the SPARQL 1.1 [CEIL()](https://www.w3.org/TR/sparql11-query/#func-ceil) function.

Examples:

```sql
SELECT sparql.ceil('"3.14"^^xsd:decimal');
                      ceil                       
-------------------------------------------------
 "4"^^<http://www.w3.org/2001/XMLSchema#decimal>
(1 row)

SELECT sparql.ceil('"-2.1"^^xsd:float');
                      ceil                      
------------------------------------------------
 "-2"^^<http://www.w3.org/2001/XMLSchema#float>
(1 row)
```

## [FLOOR](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#floor)

```sql
sparql.floor(value rdfnode) → numeric
```

Returns the greatest integer less than or equal to the numeric value. Implements the SPARQL 1.1 [FLOOR()](https://www.w3.org/TR/sparql11-query/#func-floor) function.

Examples:

```sql
SELECT sparql.floor('"3.9"^^xsd:decimal');
                      floor                      
-------------------------------------------------
 "3"^^<http://www.w3.org/2001/XMLSchema#decimal>
(1 row)

SELECT sparql.floor('"-2.1"^^xsd:float');
                     floor                      
------------------------------------------------
 "-3"^^<http://www.w3.org/2001/XMLSchema#float>
(1 row)
```

## [RAND](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#rand)

```sql
sparql.rand() → rdfnode
```

Returns a random floating-point number between 0.0 and 1.0. Implements the SPARQL 1.1 [RAND()](https://www.w3.org/TR/sparql11-query/#idp2130040) function.

Examples:

```sql
SELECT sparql.rand();
                               rand                               
------------------------------------------------------------------
 "0.14079881274421657"^^<http://www.w3.org/2001/XMLSchema#double>
(1 row)
```

## [YEAR](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#year)

```sql
sparql.year(value rdfnode) → int
```

Returns the year component of an xsd:dateTime or xsd:date literal. Implements the SPARQL 1.1 [YEAR()](https://www.w3.org/TR/sparql11-query/#func-year) function.

Example:

```sql
SELECT sparql.year('"2025-05-17T14:00:00Z"^^xsd:dateTime');
 year 
------
 2025
```

## [MONTH](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#month)

```sql
sparql.month(value rdfnode) → int
```
Returns the month component (1–12) from a datetime or date. Implements the SPARQL 1.1 [MONTH()](https://www.w3.org/TR/sparql11-query/#func-month) function.

Example:

```sql
SELECT sparql.month('"2025-05-17T14:00:00Z"^^xsd:dateTime');
 month 
-------
     5
(1 row)
```

## [DAY](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#day)

```sql
sparql.day(value rdfnode) → int
```

Returns the day of the month from a date or datetime literal. Implements the SPARQL 1.1 [DAY()](https://www.w3.org/TR/sparql11-query/#func-day) function.

Example:

```sql
SELECT sparql.day('"2025-05-17T14:00:00Z"^^xsd:dateTime');
 day 
-----
  17
(1 row)
```

## [HOURS](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#hours)

```sql
sparql.hours(value rdfnode) → int
```

Extracts the hour (0–23) from a datetime literal. Implements the SPARQL 1.1 [HOURS()](https://www.w3.org/TR/sparql11-query/#func-hours) function.

Example:

```sql
SELECT sparql.hours('"2025-05-17T14:00:00Z"^^xsd:dateTime');
 hours 
-------
    14
(1 row)
```

## [MINUTES](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#minutes)

```sql
sparql.minutes(value rdfnode) → int
```

Returns the minute component (0–59) of a datetime literal. Implements the SPARQL 1.1 [MINUTES()](https://www.w3.org/TR/sparql11-query/#func-minutes) function.

Example: 

```sql
SELECT sparql.minutes('"2025-05-17T14:42:37Z"^^xsd:dateTime');
 minutes 
---------
      42
(1 row)
```

## [SECONDS](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#seconds)

```sql
sparql.seconds(value rdfnode) → int
```

Returns the seconds (including fractions) from a datetime literal. Implements the SPARQL 1.1 [SECONDS()](https://www.w3.org/TR/sparql11-query/#func-seconds) function.

Example:

```sql
SELECT sparql.seconds('"2025-05-17T14:42:37Z"^^xsd:dateTime');
 seconds 
---------
      37
(1 row)
```

## [TIMEZONE](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#timezone)

```sql
sparql.timezone(datetime rdfnode) → rdfnode
```

Returns the timezone offset as a duration literal (e.g., "PT2H"), or NULL if none. Implements the SPARQL 1.1 [TIMEZONE()](https://www.w3.org/TR/sparql11-query/#func-timezone) function.

Example:

```sql
SELECT sparql.timezone('"2025-05-17T10:00:00+02:00"^^xsd:dateTime');
                          timezone                          
------------------------------------------------------------
 "PT2H"^^<http://www.w3.org/2001/XMLSchema#dayTimeDuration>
(1 row)
```

## [TZ](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#tz)

```sql
sparql.tz(datetime rdfnode) → rdfnode
```

Returns the timezone offset as a string (e.g., `+02:00` or `Z`). Implements the SPARQL 1.1 [TZ()](https://www.w3.org/TR/sparql11-query/#func-tz) function.

Examples:

```sql
SELECT sparql.tz('"2025-05-17T10:00:00+02:00"^^xsd:dateTime');
    tz    
----------
 "+02:00"
(1 row)

SELECT sparql.tz('"2025-05-17T08:00:00Z"^^xsd:dateTime');
 tz  
-----
 "Z"
(1 row)
```

## [MD5](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#md5)

```sql
sparql.md5(value rdfnode) → rdfnode
```

Returns the MD5 hash of the lexical form of the input RDF literal, encoded as a lowercase hexadecimal string. Implements the SPARQL 1.1 [MD5()](https://www.w3.org/TR/sparql11-query/#func-md5) function. The result is returned as a plain literal (xsd:string).

Examples:

```sql
SELECT sparql.md5('"foo"');
                md5                 
------------------------------------
 "acbd18db4cc2f85cedef654fccc4a4d8"
(1 row)

SELECT sparql.md5('42'::rdfnode);
                md5                 
------------------------------------
 "a1d0c6e83f027327d8461063f4ac58a6"
(1 row)
```

## [LEX](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#lex)

```sql
sparql.lex(value rdfnode) → rdfnode
```

Extracts the lexical value of a given `rdfnode`. This isa convenience function that is not part of the SPARQL 1.1 standard.

Examples:

```sql
SELECT sparql.lex('"foo"^^xsd:string');
 lex 
-----
 foo
(1 row)

SELECT sparql.lex('"foo"@es');
 lex 
-----
 foo
(1 row)
```

## [SPARQL describe](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#sparql-describe)
```sql
sparql.describe(server text, query text, raw_literal boolean, base_uri text) → triple
```
**Description**

The `sparql.describe` function executes a SPARQL `DESCRIBE` query against a specified RDF triplestore `SERVER`. It retrieves RDF triples describing a resource (or resources) identified by the query and returns them as a table with three columns: subject, predicate, and object. This function is useful for exploring RDF data by fetching detailed descriptions of resources from a triplestore.
The function leverages the Redland RDF library (librdf) to parse the `RDF/XML` response from the triplestore into triples, which are then returned as rows in the result set.

**Parameters**

`server` **(required)**: The name of the foreign server (defined via `CREATE SERVER`) that specifies the SPARQL endpoint to query. This must correspond to an existing `rdf_fdw` server configuration. Cannot be empty or `NULL`.

`describe_query` **(required)**: A valid SPARQL `DESCRIBE` query string (e.g., `DESCRIBE <http://example.org/resource>`). Cannot be empty or `NULL`.

`raw_literal`: Controls how literal values in the object column are formatted (default `true`):
* **true**: Preserves the full RDF literal syntax, including datatype (e.g., `"123"^^<http://www.w3.org/2001/XMLSchema#integer>`) or language tags (e.g., `"hello"@en`).
* **false**: Strips datatype and language tags, returning only the literal value (e.g., `"123"` or `"hello"`).

`base_uri`: The base URI used to resolve relative URIs in the `RDF/XML` response from the triplestore. If empty, defaults to "http://rdf_fdw.postgresql.org/". Useful for ensuring correct URI resolution in the parsed triples.


**Return Value**

Returns a table with the following `rdfnode` columns:
* `subject`: The subject of each RDF triple, typically a URI or blank node identifier.
* `predicate`: The predicate (*property*) of each RDF triple, always a URI.
* `object`: The object of each RDF triple, which may be a URI, blank node, or literal value.

**Usage Example**

```sql
CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (endpoint 'https://query.wikidata.org/sparql');

SELECT subject, predicate, object
FROM rdf_fdw_describe('wikidata', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>', true);

INFO:  SPARQL query sent to 'https://query.wikidata.org/sparql':

DESCRIBE <http://www.wikidata.org/entity/Q61308849>


                 subject                  |                 predicate                  |                               object
------------------------------------------+--------------------------------------------+------------------------------------------------------------------------------
 http://www.wikidata.org/entity/Q61308849 | http://www.wikidata.org/prop/direct/P3999  | "2015-01-01T00:00:00Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>
 http://www.wikidata.org/entity/Q61308849 | http://schema.org/dateModified             | "2024-05-01T21:36:41Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>
 http://www.wikidata.org/entity/Q61308849 | http://schema.org/version                  | "2142303130"^^<http://www.w3.org/2001/XMLSchema#integer>
 http://www.wikidata.org/entity/Q61308849 | http://www.wikidata.org/prop/direct/P127   | http://www.wikidata.org/entity/Q349450
...
 http://www.wikidata.org/entity/Q61308849 | http://www.wikidata.org/prop/direct/P625   | "Point(-133.03 69.43)"^^<http://www.opengis.net/ont/geosparql#wktLiteral>
(37 rows)
```

## [Pushdown](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#pushdown)

A *pushdown* is the ability to translate SQL queries so that operations—such as sorting, formatting, and filtering—are performed directly in the data source rather than in PostgreSQL. This feature can significantly reduce the number of records retrieved from the data source.  

For example, if a SQL `LIMIT` clause is not pushed down, the target system will perform a full scan of the data source, prepare the entire result set for transfer, send it to PostgreSQL over the network, and only then will PostgreSQL discard the unnecessary data. Depending on the total number of records, this process can be extremely inefficient.  

In a nutshell, the `rdf_fdw` extension attempts to translate SQL into SPARQL queries. However, due to fundamental differences between the two languages, this is not always straightforward. As a rule of thumb, it is often best to keep SQL queries involving foreign tables as simple as possible. The `rdf_fdw` supports pushdown of most [SPARQL 1.1 built-in functions](https://www.w3.org/TR/sparql11-query/#funcs) and several PostgreSQL instructions, such as `LIMIT` and `IN`/`NOT IN`.

### [LIMIT](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#limit)

`LIMIT` clauses are pushed down only if the SQL query does not contain aggregates and when all conditions in the `WHERE` clause can be translated to SPARQL.
 
| SQL | SPARQL|
| -- | --- |
| `LIMIT x`| `LIMIT x` 
| `FETCH FIRST x ROWS` | `LIMIT x` |
| `FETCH FIRST ROW ONLY` | `LIMIT 1` |

**OFFSET** pushdown is **not** supported, meaning that OFFSET filters will be applied locally in PostgreSQL.

Example:

```sql
SELECT s, p, o FROM rdbms
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.langmatches(sparql.lang(o), 'es')
FETCH FIRST 5 ROWS ONLY;

INFO:  SPARQL query sent to 'https://query.wikidata.org/sparql':

SELECT ?s ?p ?o 
{
      ?s wdt:P31 wd:Q3932296 .
          ?s ?p ?o
         
 ## rdf_fdw pushdown conditions ##
 FILTER(?p = <http://www.w3.org/2000/01/rdf-schema#label>)
 FILTER(LANGMATCHES(LANG(?o), "es"))
}
LIMIT 5

INFO:  SPARQL returned 5 records.

                    s                     |                      p                       |             o             
------------------------------------------+----------------------------------------------+---------------------------
 <http://www.wikidata.org/entity/Q850>    | <http://www.w3.org/2000/01/rdf-schema#label> | "MySQL"@es
 <http://www.wikidata.org/entity/Q60463>  | <http://www.w3.org/2000/01/rdf-schema#label> | "Ingres"@es
 <http://www.wikidata.org/entity/Q192490> | <http://www.w3.org/2000/01/rdf-schema#label> | "PostgreSQL"@es
 <http://www.wikidata.org/entity/Q215819> | <http://www.w3.org/2000/01/rdf-schema#label> | "Microsoft SQL Server"@es
 <http://www.wikidata.org/entity/Q80426>  | <http://www.w3.org/2000/01/rdf-schema#label> | "Vectorwise"@es
(5 rows)
```

* `FETCH FIRST 5 ROWS ONLY` was pushed down as `LIMIT 5` in the SPARQL query.

### [ORDER BY](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#order-by)

`ORDER BY` can be pushed down if the data types can be translated into SPARQL.

| SQL | SPARQL|
| -- | --- |
| `ORDER BY x ASC`, `ORDER BY x` | `ORDER BY ASC(x)`|
| `ORDER BY x DESC` |`ORDER BY DESC(x)` |

Example:

```sql
SELECT s, p, o FROM rdbms
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.langmatches(sparql.lang(o), 'es')
ORDER BY s ASC, o DESC
FETCH FIRST 5 ROWS ONLY;

INFO:  SPARQL query sent to 'https://query.wikidata.org/sparql':

SELECT ?s ?p ?o 
{
      ?s wdt:P31 wd:Q3932296 .
          ?s ?p ?o
         
 ## rdf_fdw pushdown conditions ##
 FILTER(?p = <http://www.w3.org/2000/01/rdf-schema#label>)
 FILTER(LANGMATCHES(LANG(?o), "es"))
}
ORDER BY  ASC (?s)  DESC (?o)
LIMIT 5

INFO:  SPARQL returned 5 records.

                     s                      |                      p                       |            o             
--------------------------------------------+----------------------------------------------+--------------------------
 <http://www.wikidata.org/entity/Q1012765>  | <http://www.w3.org/2000/01/rdf-schema#label> | "SQL Express Edition"@es
 <http://www.wikidata.org/entity/Q1050734>  | <http://www.w3.org/2000/01/rdf-schema#label> | "Informix"@es
 <http://www.wikidata.org/entity/Q12621393> | <http://www.w3.org/2000/01/rdf-schema#label> | "Tibero"@es
 <http://www.wikidata.org/entity/Q1493683>  | <http://www.w3.org/2000/01/rdf-schema#label> | "MySQL Clúster"@es
 <http://www.wikidata.org/entity/Q15275385> | <http://www.w3.org/2000/01/rdf-schema#label> | "SingleStore"@es
(5 rows)
```

* `ORDER BY s ASC, o DESC` was pushed down as SPARQL `ORDER BY  ASC (?s)  DESC (?o)`
### [DISTINCT](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#distinct)

`DISTINCT` is pushed down to the SPARQL `SELECT` statement just as in SQL. However, if the configured SPARQL query already includes a `DISTINCT` or `REDUCED` modifier, the SQL `DISTINCT` won't be pushed down. Since there is no SPARQL equivalent for `DISTINCT ON`, this feature cannot be pushed down.  

Example:

```sql
SELECT DISTINCT p, o FROM rdbms
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.langmatches(sparql.lang(o), 'de');

INFO:  SPARQL query sent to 'https://query.wikidata.org/sparql':

SELECT DISTINCT ?p ?o 
{
      ?s wdt:P31 wd:Q3932296 .
          ?s ?p ?o
         
 ## rdf_fdw pushdown conditions ##
 FILTER(?p = <http://www.w3.org/2000/01/rdf-schema#label>)
 FILTER(LANGMATCHES(LANG(?o), "de"))
}
ORDER BY ASC (?p)  ASC (?o)

INFO:  SPARQL returned 43 records.

                      p                       |                 o                 
----------------------------------------------+-----------------------------------
 <http://www.w3.org/2000/01/rdf-schema#label> | "4th Dimension"@de
 <http://www.w3.org/2000/01/rdf-schema#label> | "Amazon Redshift"@de
 <http://www.w3.org/2000/01/rdf-schema#label> | "ArcSDE"@de
...
 <http://www.w3.org/2000/01/rdf-schema#label> | "dBASE Mac"@de
(43 rows)
```

* `DISTINCT` was pushed down to SPARQL.

### [WHERE](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#where)

The `rdf_fdw` extension supports pushdown of many SQL expressions in the `WHERE` clause. When applicable, these expressions are translated into SPARQL `FILTER` clauses, allowing filtering to occur directly at the RDF data source. 

The following expressions in the `WHERE` clause are eligible for pushdown:

* Comparisons involving PostgreSQL data types (e.g., `integer`, `text`, `boolean`) or `rdfnode`, when used with the supported operators:

  ✅ **Supported Data Types and Operators**

  | Data type                                                  | Operators                             |
  |------------------------------------------------------------|---------------------------------------|
  | `rdfnode`                                                  | `=`, `!=`,`<>`, `>`, `>=`, `<`, `<=`  |
  | `text`, `char`, `varchar`, `name`                          | `=`, `<>`, `!=`, `~~`, `!~~`, `~~*`,`!~~*`                       |
  | `date`, `timestamp`, `timestamp with time zone`            | `=`, `<>`, `!=`, `>`, `>=`, `<`, `<=` |
  | `smallint`, `int`, `bigint`, `numeric`, `double precision` | `=`, `<>`, `!=`, `>`, `>=`, `<`, `<=` |
  | `boolean`                                                  | `IS`, `IS NOT`                        |

* ✅ `IN`/`NOT IN` and `ANY` constructs with constant lists.
  
  SQL `IN`  and `ANY` constructs are translated into the SPARQL [`IN` operator](https://www.w3.org/TR/2013/REC-sparql11-query-20130321/#func-in), which will be placed in a [`FILTER` evaluation](https://www.w3.org/TR/2013/REC-sparql11-query-20130321/#evaluation), as long as the list has the supported data types.

* ✅ Nearly all supported [SPARQL functions](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#sparql-functions) are pushdown-capable, including:
  * `LANG()`, `DATATYPE()`, `STR()`, `isBLANK()`, `isIRI()`, etc.
  * Numeric, string, and datetime functions such as `ROUND()`, `STRLEN()`, `YEAR()`, and others.
  
  ⚠️ **Exceptions**: Due to their volatile nature, the SPARQL functions RAND() and NOW() cannot be pushed down. Because their results cannot be reproduced consistently by PostgreSQL, any rows returned from the endpoint would be filtered out locally during re-evaluation.

❌ **Conditions That Prevent Pushdown**

A `WHERE` condition will not be pushed down if:

* The option `enable_pushdown` is set to `false`.
* The underlying SPARQL query includes:
  * a `GROUP BY` clause
  * solution modifiers like `OFFSET`, `ORDER BY`, `LIMIT`, `DISTINCT`, or `REDUCED`
  * subqueries or federated queries
* The condition includes an unsupported data type or operator.
* The condition contains `OR` logical operators (not yet supported).


#### Pushdown Examples

For the examples in this section consider this `SERVER` and `FOREIGN TABLE` setting (Wikidata):

```SQL
CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://query.wikidata.org/sparql');

CREATE FOREIGN TABLE rdbms (
  s rdfnode OPTIONS (variable '?s'),
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER wikidata OPTIONS (
  sparql 
    'SELECT * {
      ?s wdt:P31 wd:Q3932296 .
	  ?s ?p ?o
	 }'
);
```

1. Pusdown of `WHERE` conditions involving `rdfnode` values and `=` and `!=` operators. All conditions are pushed as `FILTER` expressions.

```sql

SELECT s, o FROM rdbms
WHERE 
  o = '"PostgreSQL"@es' AND
  o <> '"Oracle"@es';

INFO:  SPARQL query sent to 'https://query.wikidata.org/sparql':

SELECT ?s ?o 
{
      ?s wdt:P31 wd:Q3932296 .
          ?s ?p ?o
         
 ## rdf_fdw pushdown conditions ##
 FILTER(?o = "PostgreSQL"@es)
 FILTER(?o != "Oracle"@es)
}

INFO:  SPARQL returned 1 record.

                    s                     |        o        
------------------------------------------+-----------------
 <http://www.wikidata.org/entity/Q192490> | "PostgreSQL"@es
(1 row)
```

2. Pusdown of `WHERE` conditions involving `rdfnode` values and `=`, `>`, and `<` operators. All conditions are pushed as `FILTER` expressions. Note that the `timpestamp` values are automatically cast to the correspondent XSD data type.

```sql
SELECT s, o FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P577>' AND
  o > '1996-01-01'::timestamp AND o < '1996-12-31'::timestamp;

INFO:  SPARQL query sent to 'https://query.wikidata.org/sparql':

SELECT ?s ?p ?o 
{
      ?s wdt:P31 wd:Q3932296 .
          ?s ?p ?o
         
 ## rdf_fdw pushdown conditions ##
 FILTER(?p = <http://www.wikidata.org/prop/direct/P577>)
 FILTER(?o > "1996-01-01T00:00:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>)
 FILTER(?o < "1996-12-31T00:00:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>)
}

INFO:  SPARQL returned 1 record.

                    s                     |                                  o                                  
------------------------------------------+---------------------------------------------------------------------
 <http://www.wikidata.org/entity/Q192490> | "1996-07-08T00:00:00Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>
(1 row)
```
3. Pusdown of `WHERE` conditions with `IN` and `ANY` constructs. All conditions are pushed down as `FILTER` expressions.

```sql
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  o IN ('"PostgreSQL"@en', '"IBM Db2"@fr', '"MySQL"@es');

INFO:  SPARQL query sent to 'https://query.wikidata.org/sparql':

SELECT ?p ?o 
{
      ?s wdt:P31 wd:Q3932296 .
          ?s ?p ?o         
 ## rdf_fdw pushdown conditions ##
 FILTER(?p = <http://www.w3.org/2000/01/rdf-schema#label>)
 FILTER(?o IN ("PostgreSQL"@en, "IBM Db2"@fr, "MySQL"@es))
}

INFO:  SPARQL returned 3 records.

                      p                       |        o        
----------------------------------------------+-----------------
 <http://www.w3.org/2000/01/rdf-schema#label> | "MySQL"@es
 <http://www.w3.org/2000/01/rdf-schema#label> | "PostgreSQL"@en
 <http://www.w3.org/2000/01/rdf-schema#label> | "IBM Db2"@fr
(3 rows)
```

```sql
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  o = ANY(ARRAY['"PostgreSQL"@en'::rdfnode,'"IBM Db2"@fr'::rdfnode,'"MySQL"@es'::rdfnode]);

INFO:  SPARQL query sent to 'https://query.wikidata.org/sparql':

SELECT ?p ?o 
{
      ?s wdt:P31 wd:Q3932296 .
          ?s ?p ?o
         
 ## rdf_fdw pushdown conditions ##
 FILTER(?p = <http://www.w3.org/2000/01/rdf-schema#label>)
 FILTER(?o IN ("PostgreSQL"@en, "IBM Db2"@fr, "MySQL"@es))
}

INFO:  SPARQL returned 3 records.

                      p                       |        o        
----------------------------------------------+-----------------
 <http://www.w3.org/2000/01/rdf-schema#label> | "MySQL"@es
 <http://www.w3.org/2000/01/rdf-schema#label> | "PostgreSQL"@en
 <http://www.w3.org/2000/01/rdf-schema#label> | "IBM Db2"@fr
(3 rows)
```

4. Pusdown of `WHERE` conditions involving SPARQL functions. The function calls for `LANGMATCHES()`, `LANG()`, and `STRENDS()` are pushed down in `FILTER` expressions.

```sql
SELECT s, o FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o), 'de') AND
  sparql.strends(o, sparql.strlang('SQL','de'));

INFO:  SPARQL query sent to 'https://query.wikidata.org/sparql':

SELECT ?s ?p ?o 
{
      ?s wdt:P31 wd:Q3932296 .
          ?s ?p ?o
         
 ## rdf_fdw pushdown conditions ##
 FILTER(?p = <http://www.w3.org/2000/01/rdf-schema#label>)
 FILTER(LANGMATCHES(LANG(?o), "de"))
 FILTER(STRENDS(?o, "SQL"@de))
}

INFO:  SPARQL returned 4 records.

                     s                     |        o        
-------------------------------------------+-----------------
 <http://www.wikidata.org/entity/Q850>     | "MySQL"@de
 <http://www.wikidata.org/entity/Q192490>  | "PostgreSQL"@de
 <http://www.wikidata.org/entity/Q5014224> | "CSQL"@de
 <http://www.wikidata.org/entity/Q6862049> | "Mimer SQL"@de
(4 rows)
```

## [Examples](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#examples)

### [LinkedGeoData](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#linkedgeodata)

Retrieve all amenities 100 from Leipzig Central Station that are wheelchair accessible and had its entry modified after January 1st, 2015.

```sql
CREATE SERVER linkedgeodata 
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'http://linkedgeodata.org/sparql');

CREATE FOREIGN TABLE leipzig_hbf (
  hbf_iri    rdfnode OPTIONS (variable '?s'),
  modified   rdfnode OPTIONS (variable '?mod'),
  loc_iri    rdfnode OPTIONS (variable '?x'),
  loc_label  rdfnode OPTIONS (variable '?l'), 
  wheelchair rdfnode OPTIONS (variable '?wc')

) SERVER linkedgeodata OPTIONS (
  log_sparql 'true',
  sparql '
PREFIX lgdo: <http://linkedgeodata.org/ontology/>
PREFIX geom: <http://geovocab.org/geometry#>
PREFIX ogc: <http://www.opengis.net/ont/geosparql#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>

SELECT * {
  ?s owl:sameAs <http://dbpedia.org/resource/Leipzig_Hauptbahnhof> ;
    geom:geometry [ogc:asWKT ?sg] .

  ?x a lgdo:Amenity ;
    rdfs:label ?l ;
	<http://purl.org/dc/terms/modified> ?mod ;
	<http://linkedgeodata.org/ontology/wheelchair> ?wc ;
    geom:geometry [ogc:asWKT ?xg] .
    FILTER(bif:st_intersects (?sg, ?xg, 0.1)) .
}'); 

SELECT loc_iri, sparql.lex(loc_label), CAST(modified AS timestamp)
FROM leipzig_hbf
WHERE 
  sparql.contains(loc_label, 'bahnhof') AND  
  modified > '2015-01-01'::date AND 
  wheelchair = true
FETCH FIRST 10 ROWS ONLY;

INFO:  SPARQL query sent to 'http://linkedgeodata.org/sparql':

PREFIX lgdo: <http://linkedgeodata.org/ontology/>
PREFIX geom: <http://geovocab.org/geometry#>
PREFIX ogc: <http://www.opengis.net/ont/geosparql#>
PREFIX owl: <http://www.w3.org/2002/07/owl#>

SELECT ?mod ?x ?l ?wc 
{
  ?s owl:sameAs <http://dbpedia.org/resource/Leipzig_Hauptbahnhof> ;
    geom:geometry [ogc:asWKT ?sg] .

  ?x a lgdo:Amenity ;
    rdfs:label ?l ;
        <http://purl.org/dc/terms/modified> ?mod ;
        <http://linkedgeodata.org/ontology/wheelchair> ?wc ;
    geom:geometry [ogc:asWKT ?xg] .
    FILTER(bif:st_intersects (?sg, ?xg, 0.1)) .

 ## rdf_fdw pushdown conditions ##
 FILTER(CONTAINS(?l, "bahnhof"))
 FILTER(?mod > "2015-01-01"^^<http://www.w3.org/2001/XMLSchema#date>)
 FILTER(?wc = "true"^^<http://www.w3.org/2001/XMLSchema#boolean>)
}
LIMIT 10

INFO:  SPARQL returned 2 records.

                     loc_iri                      |            lex            |      modified       
--------------------------------------------------+---------------------------+---------------------
 <http://linkedgeodata.org/triplify/way165354553> | Parkplatz am Hauptbahnhof | 2015-03-10 16:46:08
 <http://linkedgeodata.org/triplify/way90961368>  | Hauptbahnhof, Ostseite    | 2015-04-29 14:13:14
(2 rows)
```

In this query we can observe that:
 
* all `WHERE` conditions were pushed down as `FILTER` expressions
* the `FETCH FIRST 10 ROWS ONLY` was pushed down as `LIMIT 10`
* the lexical value of the literal in `loc_label` was extracted using the function [LEX()](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#lex).
* the `xsd:dateTime` literal in `modified` was successfully converted to `timestamp` using SQL `CAST`.

### [DBpedia](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#dbpedia)

```sql
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

CREATE FOREIGN TABLE politicians (
  uri text        OPTIONS (variable '?person',     nodetype 'iri'),
  name text       OPTIONS (variable '?personname', nodetype 'literal', literal_type 'xsd:string'),
  birthdate date  OPTIONS (variable '?birthdate',  nodetype 'literal', literal_type 'xsd:date'),
  party text      OPTIONS (variable '?partyname',  nodetype 'literal', literal_type 'xsd:string'),
  country text    OPTIONS (variable '?country',    nodetype 'literal', language 'en')
)
SERVER dbpedia OPTIONS (
  sparql '
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>

    SELECT *
    WHERE {
      ?person 
          a dbo:Politician;
          dbo:birthDate ?birthdate;
          dbp:name ?personname;
          dbo:party ?party .       
        ?party 
          dbp:country ?country;
          rdfs:label ?partyname .
        FILTER NOT EXISTS {?person dbo:deathDate ?died}
        FILTER(LANG(?partyname) = "de")
      } 
');

SELECT name, birthdate, party
FROM politicians
WHERE 
  country IN ('Germany','France') AND 
  birthdate > '1995-12-31' AND
  party <> ''
ORDER BY birthdate DESC, party ASC
FETCH FIRST 5 ROWS ONLY;

INFO:  SPARQL query sent to 'https://dbpedia.org/sparql':

PREFIX dbp: <http://dbpedia.org/property/>
PREFIX dbo: <http://dbpedia.org/ontology/> 

SELECT ?personname ?birthdate ?partyname ?country 
{
      ?person 
          a dbo:Politician;
          dbo:birthDate ?birthdate;
          dbp:name ?personname;
          dbo:party ?party .       
        ?party 
          dbp:country ?country;
          rdfs:label ?partyname .
        FILTER NOT EXISTS {?person dbo:deathDate ?died}
        FILTER(LANG(?partyname) = "de")
      
 ## rdf_fdw pushdown conditions ##
 FILTER(?country IN ("Germany"@en, "France"@en))
 FILTER(?birthdate > "1995-12-31"^^<http://www.w3.org/2001/XMLSchema#date>)
 FILTER(?partyname != ""^^<http://www.w3.org/2001/XMLSchema#string>)
}
ORDER BY  DESC (?birthdate)  ASC (?partyname)
LIMIT 5

INFO:  SPARQL returned 5 records.

        name        | birthdate  |                  party                  
--------------------+------------+-----------------------------------------
 Louis Boyard       | 2000-08-26 | La France insoumise
 Klara Schedlich    | 2000-01-04 | Bündnis 90/Die Grünen
 Pierrick Berteloot | 1999-01-11 | Rassemblement National
 Niklas Wagener     | 1998-04-16 | Bündnis 90/Die Grünen
 Jakob Blankenburg  | 1997-08-05 | Sozialdemokratische Partei Deutschlands
(5 rows)
```

In this example we can observe that: 

* the executed SPARQL query was logged.
* the SPARQL `SELECT` was modified to retrieve only the columns used in the SQL `SELECT` and `WHERE` clauses.
* the conditions in the SQL `WHERE` clause were pushed down as SPARQL `FILTER` conditions.
* the SQL `ORDER BY` clause was pushed down as SPARQL `ORDER BY`.
* the `FETCH FIRST ... ROWS ONLY` was pushed down as SPARQL `LIMIT`
* the column `country` has a `language` option, and its value is used as a language tag in the SPARQL expression: `FILTER(?country IN ("Germany"@en, "France"@en))`

### [Import data into QGIS](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#import-data-into-qgis)

The `rdf_fdw` can also be used as a bridge between GIS (Geographic Information Systems) and RDF Triplestores. This example demonstrates how to retrieve geographic coordinates of all German public universities from DBpedia, create WKT (Well Known Text) literals, and import the data into [QGIS](https://qgis.org/) to visualize it on a map.

> [!NOTE]  
> This example requires the extension PostGIS.

```sql
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

CREATE FOREIGN TABLE german_public_universities (
  id text                   OPTIONS (variable '?uri', nodetype 'iri'),
  name text                 OPTIONS (variable '?name',nodetype 'literal'),
  lon numeric               OPTIONS (variable '?lon', nodetype 'literal'),
  lat numeric               OPTIONS (variable '?lat', nodetype 'literal'),
  geom geometry(point,4326) OPTIONS (variable '?wkt', nodetype 'literal',
                                    expression 'CONCAT("POINT(",?lon," ",?lat,")") AS ?wkt')
) SERVER dbpedia OPTIONS (
  sparql '
    PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>
    PREFIX dbr:  <http://dbpedia.org/resource/>
    SELECT ?uri ?name ?lon ?lat
    WHERE {
      ?uri dbo:type dbr:Public_university ;
        dbp:name ?name;
        geo:lat ?lat; 
        geo:long ?lon; 
        dbp:country dbr:Germany
      }
  ');
```
Now that we have our `FOREIGN TABLE` in place, we just need to create a [New PostGIS Connection in QGIS](https://docs.qgis.org/3.34/en/docs/user_manual/managing_data_source/opening_data.html#creating-a-stored-connection) and go to **Database > DB Manager ...**, select the table we just created and query the data using SQL:

```sql
SELECT id, name, geom
FROM german_public_universities
```
![unis](examples/img/qgis-query.png?raw=true)

Finally give the layer a name, select the geometry column and press **Load**.

![unis](examples/img/qgis-map.png?raw=true)

### [Publish FOREIGN TABLE as WFS layer in GeoServer](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#publish-foreign-table-as-wfs-layer-in-geoserver)

Just like with an ordinary `TABLE` in PostgreSQL, it is possible to create and publish `FOREIGN TABLES` as WFS layers in GeoServer. 

First create the `FOREIGN TABLE`:

```sql
CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://query.wikidata.org/sparql');

CREATE FOREIGN TABLE museums_brittany (
  id text                   OPTIONS (variable '?villeId', nodetype 'iri'),
  label text                OPTIONS (variable '?museumLabel',nodetype 'literal'),
  ville text                OPTIONS (variable '?villeIdLabel', nodetype 'literal'),
  geom geometry(point,4326) OPTIONS (variable '?coord', nodetype 'literal')
) SERVER wikidata OPTIONS (
  sparql '
    SELECT DISTINCT ?museumLabel ?villeId ?villeIdLabel ?coord
    WHERE
    {
      ?museum wdt:P539 ?museofile. # french museofile Id
      ?museum wdt:P131* wd:Q12130. # in Brittany
      ?museum wdt:P131 ?villeId.   # city of the museum
      ?museum wdt:P625 ?coord .    # wkt literal      
      SERVICE wikibase:label { bd:serviceParam wikibase:language "fr". } # french label
    }
  ');
```
Then set up the [Workspace](https://docs.geoserver.org/latest/en/user/data/webadmin/workspaces.html) and [Store](https://docs.geoserver.org/latest/en/user/data/webadmin/stores.html), go to  **Layers -> Add a new layer**, select the proper workspace and go to **Configure new SQL view...** to create a layer create a layer with a native **SQL statement**:

```sql
SELECT id, label, ville, geom
FROM museums_brittany
```

![geoserver](examples/img/geoserver-layer.png?raw=true)

Afer that set the geometery column and identifier, and hit **Save**. Finally, fill in the remaining layer attributes, such as Style, Bounding Boxes and Spatial Reference System, and click **Save** - see this [instructions](https://docs.geoserver.org/latest/en/user/data/webadmin/layers.html) for more details. After that you'll be able to reach your layer from a standard OGC WFS client, e.g. using [QGIS](https://docs.qgis.org/3.34/en/docs/server_manual/services/wfs.html).

![geoserver-wfs](examples/img/geoserver-wfs-client.png?raw=true)

![geoserver-wfs-map](examples/img/geoserver-wfs-map.png?raw=true)
## [Deploy with Docker](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#deploy-with-docker)

To deploy the `rdf_fdw` with docker just pick one of the supported PostgreSQL versions, install the [requirements](#requirements) and [compile](#build-and-install) the [source code](https://github.com/jimjonesbr/rdf_fdw/releases). For example, a `rdf_fdw` `Dockerfile` for PostgreSQL 17 should look like this (minimal example):

```dockerfile
FROM postgres:17

RUN apt-get update && \
    apt-get install -y make gcc postgresql-server-dev-17 libxml2-dev libcurl4-gnutls-dev librdf0-dev pkg-config

RUN mkdir /extensions
COPY ./rdf_fdw-2.1.0.tar.gz /extensions/
WORKDIR /extensions

RUN tar xvzf rdf_fdw-2.1.0.tar.gz && \
    cd rdf_fdw-2.1.0 && \
    make -j && \
    make install
```

To build the image save it in a `Dockerfile` and  run the following command in the root directory - this will create an image called `rdf_fdw_image`.:
 
```bash
 $ docker build -t rdf_fdw_image .
```

After successfully building the image you're ready to `run` or `create` the container ..
 
```bash
$ docker run --name my_container -e POSTGRES_HOST_AUTH_METHOD=trust rdf_fdw_image
```

.. and then finally you're able to create and use the extension!

```bash
$ docker exec -u postgres my_container psql -d mydatabase -c "CREATE EXTENSION rdf_fdw;"
```

### [For testers and developers](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#for-testers-and-developers)

Think you're cool enough? Try compiling the latest commits from source!

Dockerfile


```dockerfile
FROM postgres:17

RUN apt-get update && \
    apt-get install -y git make gcc postgresql-server-dev-17 libxml2-dev libcurl4-gnutls-dev librdf0-dev pkg-config

WORKDIR /

RUN git clone https://github.com/jimjonesbr/rdf_fdw.git && \
    cd rdf_fdw && \
    make -j && \
    make install
```
Deployment

```bash
 $ docker build -t rdf_fdw_image .
 $ docker run --name my_container -e POSTGRES_HOST_AUTH_METHOD=trust rdf_fdw_image
 $ docker exec -u postgres my_container psql -d mydatabase -c "CREATE EXTENSION rdf_fdw;"
```

If you've found a bug or have general comments, do not hesitate to open an issue. Any feedback is much appreciated!