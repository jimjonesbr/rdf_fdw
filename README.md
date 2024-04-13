
---------------------------------------------
# RDF Triplestore Foreign Data Wrapper for PostgreSQL (rdf_fdw)

The `rdf_fdw` is a PostgreSQL Foreign Data Wrapper to easily access RDF triplestores via SPARQL endpoints, including pushdown of several SQL Query clauses.

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
  - [version](#version)
  - [rdf_fdw_clone_table](#rdf_fdw_clone_table)
- [Pushdown](#pushdown)
  - [LIMIT](#limit)
  - [ORDER BY](#order-by)
  - [DISTINCT](#distinct)
  - [WHERE](#where)
    - [Supported Data Types and Operators](#supported-data-types-and-operators)
    - [IN and ANY constructs](#in-and-any-constructs)
    - [Pattern matching operators LIKE and ILIKE](#pattern-matching-operators-like-and-ilike)
  - [Pushdown Examples](#pushdown-examples)
- [Examples](#examples)
  - [DBpedia](#dbpedia)
  - [Getty Thesaurus](#getty-thesaurus)
  - [BBC Programmes and Music](#bbc-programmes-and-music)
  - [Wikidata](#wikidata)
  - [Import data into QGIS](#import-data-into-qgis)
  - [Publish FOREIGN TABLE as WFS layer in GeoServer](#publish-foreign-table-as-wfs-layer-in-geoserver)
- [Deploy with Docker](#deploy-with-docker)
 
## [Requirements](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#requirements)

* [libxml2](http://www.xmlsoft.org/): version 2.5.0 or higher.
* [libcurl](https://curl.se/libcurl/): version 7.74.0 or higher.
* [PostgreSQL](https://www.postgresql.org): version 11 or higher.
* [gcc](https://gcc.gnu.org/) and [make](https://www.gnu.org/software/make/) to complile the code.

In an Ubuntu environment you can install all dependencies with the following command:

```shell
apt install -y make gcc postgresql-server-dev-16 libxml2-dev libcurl4-openssl-dev
```

> [!NOTE]  
> `postgresql-server-dev-16` only installs the libraries for PostgreSQL 16. Change it if you're using another PostgreSQL version.

## [Build and Install](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#build_and_install)

To compile the source code you need to ensure the [pg_config](https://www.postgresql.org/docs/current/app-pgconfig.html) executable is properly set when you run `make` - this executable is typically in your PostgreSQL installation's bin directory. After that, just run `make` in the root directory:

```bash
$ cd rdf_fdw
$ make
```

After compilation, just run `make install` to install the Foreign Data Wrapper:

```bash
$ make install
```

After building and installing the extension you're ready to create the extension in a PostgreSQL database with `CREATE EXTENSION`:

```sql
CREATE EXTENSION rdf_fdw;
```

To install an specific version add the full version number in the `WITH VERSION` clause

```sql
CREATE EXTENSION rdf_fdw WITH VERSION '1.0';
```

To run the predefined regression tests run `make installcheck` with the user `postgres`:

```bash
$ make PGUSER=postgres installcheck

```

> [!NOTE]  
> In order for `rdf_fdw` to convert the data retrieved from the RDF triplestore into a format that can be interpreted by PostgreSQL, it must first load all the retrieved data into memory. Therefore, if you expect to retrieve large volumes of data with a single query, make sure PostgreSQL has access to sufficient memory. Another option is to retrieve the data in chuncks by using `rdf_fdw_clone_table` or a customised script.


## [Update](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#update)

To update the extension's version you must first build and install the binaries and then run `ALTER EXTENSION`:


```sql
ALTER EXTENSION rdf_fdw UPDATE;
```

To update to an specific version use `UPDATE TO` and the full version number

```sql
ALTER EXTENSION rdf_fdw UPDATE TO '1.1';
```

## [Usage](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#usage)

To use the `rdf_fdw` you must first create a `SERVER` to connect to a SPARQL endpoint. After that, you have to create the `FOREIGN TABLE`s, which will contain the SPARQL instructions of what to retrieve from the endpoint.

### [CREATE SERVER](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#create_server)

The SQL command [CREATE SERVER](https://www.postgresql.org/docs/current/sql-createserver.html) defines a new foreign server. The user who defines the server becomes its owner. A `SERVER` requires an `endpoint`, so that `rdf_fdw` knows where to sent the SPARQL queries.

The following example creates a `SERVER` that connects to the DBpedia SPARQL Endpoint:

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
| `format` | optional            | The `rdf_fdw` expects the result sets encoded in the [SPARQL Query Results XML Format](https://www.w3.org/TR/rdf-sparql-XMLres/), which can be normally enforced by setting the MIME type `application/sparql-results+xml` in the `Accept` HTTP request header. However, there are some products that deviate from the standard and expect a differently value, e.g. `xml`, `rdf-xml`. In case the expected parameter differs from the official MIME type, it should be set in this parameter (default `application/sparql-results+xml`).
| `http_proxy` | optional            | Proxy for HTTP requests.
| `proxy_user` | optional            | User for proxy server authentication.
| `proxy_user_password` | optional            | Password for proxy server authentication.
| `connect_timeout`         | optional            | Connection timeout for HTTP requests in seconds (default `300` seconds).
| `connect_retry`         | optional            | Number of attempts to retry a request in case of failure (default `3` times).
| `request_redirect`         | optional            | Enables URL redirect issued by the server (default `false`).
| `request_max_redirect`         | optional            | Limit of how many times the URL redirection may occur. If that many redirections have been followed, the next redirect will cause an error. Not setting this parameter or setting it to `0` will allow an infinite number of redirects.
| `custom`         | optional            | One or more parameters expected by the configured RDF triplestore. Multiple parameters separated by `&`, e.g. `signal_void=on&signal_unconnected=on`. Custom parameters are appended to the request URL.
| `query_param`         | optional            | The request parameter where the SPARQL endpoint expects the query in a HTTP request. Most SPARQL endpoints expects the query to be in the parameter `query` - and this is the `rdf_fdw` default value. So, chances are you'll never need to touch this server option (default `query`)

### [CREATE USER MAPPING](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#create-user-mapping)

Availability: **1.1.0**

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

### [CREATE FOREIGN TABLE](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#create_foreign_table)

Foreign Tables from the `rdf_fdw` work as a proxy between PostgreSQL clients and RDF Triplestores. Each `FOREIGN TABLE` column must be mapped to a SPARQL `variable`, so that PostgreSQL knows where to display each node retrieved from the SPARQL queries. Optionally, it is possible to add an `expression` to the column, so that function calls can be used to retrieve or format the data.

**Table Options**

| Option        | Type        | Description                                                                                                        |
|---------------|-------------|--------------------------------------------------------------------------------------------------------------------|
| `sparql`      | **required**    | The raw SPARQL query to be executed    |
| `log_sparql`  | optional    | Logs the exact SPARQL query executed. This option is useful to check for any modification to the configured SPARQL query due to pushdown  |
| `enable_pushdown` | optional            | Enables or disables [pushdown](#pushdown) of SQL clauses into SPARQL for a specific foreign table. This overrides the `SERVER` option `enable_pushdown` |

**Column Options**

| Option        | Type        | Description                                                                                                        |
|---------------|-------------|--------------------------------------------------------------------------------------------------------------------|
| `variable`    | **required**    |This option maps the table column to a SPARQL variable used in the table option `sparql`. A variable must start with either `?` or `$` (*`?` or `$` are **not** part of the variable name!)*, and the name must be a string with the following characters:  `[a-z]`, `[A-Z]`,`[0-9]`   |
| `expression`  | optional    | Similar to `variable`, but instead of a SPARQL variable it can handle expressions, such as [function calls](https://www.w3.org/TR/sparql11-query/#SparqlOps). All expressions supported by the data source can be used in this option. |
| `language`    | optional        | RDF language tag, e.g. `en`,`de`,`pt`,`es`,`pl`, etc. This option is necessary for the pushdown feature to properly set the literal language tag in `FILTER` expressions. Set it to `*` to make `FILTER` espressions ignore language tags when comparing literals.   |  
| `literaltype`        | optional    | Data type for typed literals , e.g. `xsd:string`, `xsd:date`, `xsd:boolean`. This option is necessary for the pushdown feature to properly set the literal type of expressions from SQL `WHERE` conditions. Set it to `*` to make `FILTER` espressions ignore data types when comparing literals. |
| `nodetype`  | optional    | Type of the RDF node. Expected values are `literal` or `iri`. This option helps the query planner to optimize SPARQL `FILTER` expressions when the `WHERE` conditions are pushed down (default `literal`)  |



The following example creates a `FOREIGN TABLE` connected to the server `dbpedia`. SELECT queries executed against this table will execute the SPARQL query set in the OPTION `sparql`, and its result sets are mapped to each column of the table via the column OPTION `variable`.

```sql
CREATE FOREIGN TABLE film (
  film_id text    OPTIONS (variable '?film',     nodetype 'iri'),
  name text       OPTIONS (variable '?name',     nodetype 'literal', literaltype 'xsd:string'),
  released date   OPTIONS (variable '?released', nodetype 'literal', literaltype 'xsd:date'),
  runtime int     OPTIONS (variable '?runtime',  nodetype 'literal', literaltype 'xsd:integer'),
  abstract text   OPTIONS (variable '?abstract', nodetype 'literal', literaltype 'xsd:string')
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

### [version](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#version)

**Synopsis**

```
text rdf_fdw_version();
```

**Availability**: 1.0.0

**Description**

Shows the version of the installed `rdf_fdw` and its main libraries.

-------

**Usage**

```sql
SELECT * FROM rdf_fdw_version();
                                                                                             rdf_fdw_version
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 rdf_fdw = 1.0.0, libxml/2.9.14 libcurl/7.88.1 OpenSSL/3.0.11 zlib/1.2.13 brotli/1.0.9 zstd/1.5.4 libidn2/2.3.3 libpsl/0.21.2 (+libidn2/2.3.3) libssh2/1.10.0 nghttp2/1.52.0 librtmp/2.3 OpenLDAP/2.5.13
(1 row)
```
### [rdf_fdw_clone_table](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#rdf_fdw_clone_table)
**Synopsis**
```
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

**Availability**: 1.0.0

**Description**

This procedure is designed to copy data from a `FOREIGN TABLE` to an ordinary `TABLE`. It provides the possibility to retrieve the data set in batches, so that issues related to triplestore limits and client's memory don't bother too much. 
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

`commit_page`: commits the inserted records immediatelly or only after the transaction is finished. Useful for those who want records to be discarded in case of an error - following the principle of *everyhing or nothing*. Default `true`, which means that all inserts will me committed immediatelly.

-------

**Usage Example**

```sql
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

CREATE FOREIGN TABLE public.dbpedia_cities (
  uri text           OPTIONS (variable '?city', nodetype 'iri'),
  city_name text     OPTIONS (variable '?name', nodetype 'literal', literaltype 'xsd:string'),
  elevation numeric  OPTIONS (variable '?elevation', nodetype 'literal', literaltype 'xsd:integer')
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
 * Materilize all records from the FOREIGN TABLE 'public.dbpedia_cities' in 
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

## [Pushdown](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#pushdown)
 
A *pushdown* is the ability to translate SQL queries in such a way that operations are performed in the data source rather than in PostgreSQL, e.g. sorting, formatting, filtering. This feature can significantly reduce the number of records retrieved from the data source. For instance, a SQL `LIMIT` not pushed down means that the target system will perform a full scan in the data source, prepare everything for data transfer, return it to PostgreSQL via network, and then PostgreSQL will only locally discard the unnecessary data, which depending on the total number of records can be extremely inefficient. The `rdf_fdw` tries to translate SQL into SPARQL queries, which due to their conceptual differences is not always an easy task, so it is often worth considering to keep SQL queries involving foreign tables as simple as possible - or just to stick to the features, data types and operators described in this section. 

### LIMIT

`LIMIT` clauses are pushed down only if the SQL query does not contain aggregates and when all conditions in the `WHERE` clause can be translated to SPARQL.
 
| SQL | SPARQL|
| -- | --- |
| `LIMIT x`| `LIMIT x` 
| `FETCH FIRST x ROWS` | `LIMIT x` |
| `FETCH FIRST ROW ONLY` | `LIMIT 1` |

Pushdown of **OFFSET** clauses is **not** supported, which means that OFFSET filters will be applied locally in the client. Take a look at [rdf_fdw_clone_table](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#rdf_fdw_clone_table) if you wish to retrieve records in batches.

### ORDER BY

`ORDER BY` can be pushed down if the data types can be translated into SPARQL.

| SQL | SPARQL|
| -- | --- |
| `ORDER BY x ASC`, `ORDER BY x` | `ORDER BY ASC(x)`|
| `ORDER BY x DESC` |`ORDER BY DESC(x)` |


### DISTINCT

`DISTINCT` is pushed down to the SPARQL SELECT statement just like in SQL. In case that the configured SPARQL query already contains a `DISTINCT` or a `REDUCED` modifier, the SQL `DISTINCT` won't be pushed down. There is no equivalent for `DISTINCT ON`, so it cannot be pushed down either.

### WHERE

The `rdf_fdw` will attempt to translate RDF literals to the data type of the mapped column, and this can be quite tricky! RDF literals can be pretty much everything, as often they have no explicit data type declarations, e.g. `"wwu"` and `"wwu"^^xsd:string` are equivalent. The contents of literals are often also not validated by the RDF triplestores, but PostgreSQL will validate them in query time. So, if a retrieved literal cannot be translated to declared column data type, the query will be interrupted. SQL `WHERE` conditions are translated into SPARQL `FILTER` expressions, as long as the involved columns data types and operators are supported.


#### Supported Data Types and Operators

| Data type                                                  | Operators                             |
|------------------------------------------------------------|---------------------------------------|
| `text`, `char`, `varchar`, `name`                          | `=`, `<>`, `!=`, `~~`, `!~~`, `~~*`, `!~~*`                       |
| `date`, `timestamp`, `timestamp with time zone`            | `=`, `<>`, `!=`, `>`, `>=`, `<`, `<=` |
| `smallint`, `int`, `bigint`, `numeric`, `double precision` | `=`, `<>`, `!=`, `>`, `>=`, `<`, `<=` |
| `boolean`                                                  | `IS`, `IS NOT`                        |

#### IN and ANY constructs

SQL `IN`  and `ANY` constructs are translated into the SPARQL [`IN` operator](https://www.w3.org/TR/2013/REC-sparql11-query-20130321/#func-in), which will be placed in a [`FILTER` evaluation](https://www.w3.org/TR/2013/REC-sparql11-query-20130321/#evaluation).

#### Pattern matching operators LIKE and ILIKE

Expressions using `LIKE` and `ILIKE` - or their equivalent operators `~~` and `~~*` -  are converted to [REGEX](https://www.w3.org/TR/sparql11-query/#func-regex) filters in SPARQL. It is important to notice that pattern matching operations using `LIKE`/`ILIKE` only support the wildcards `%` and `_`, and therefore only these characters will be translated to their `REGEX` equivalents. Any other character that might be potentially used as a wildcard in `REGEX`, such as `^`, `|` or `$`,  will be escaped.

> [!NOTE]  
> These pattern matching operators do not support nondeterministic collations. If required, apply a different collation to the expression to work around this limitation.

### Pushdown Examples

 Foreign table columns with the option `literaltype`

| PostgreSQL Type  | Literal Type   | SQL WHERE Condition                                   | SPARQL (pushdown)                                                                              |
|------------------|----------------|-------------------------------------------------------|------------------------------------------------------------------------------------------------|
| `text`           | `xsd:string`   | `name = 'foo'`                                        |  `FILTER(?s = "foo"^^xsd:string)`                                                              |
| `text`           | `*`            | `name <> 'foo'`                                       |  `FILTER(STR(?s) != "foo")`                                                                    |
| `text`           | `*`            | `name ILIKE '%Jon_s'`, ` name ~~* '%Jon_s'`          |  `FILTER(REGEX(?name,".*Jon.s$","i"))`                                                         |
| `text`           | `*`            | `name LIKE '%foo%'`, `name ~~ '%foo%';`          |  `FILTER(REGEX(?name,".*foo.*"))`                                                            |
| `int`            | `xsd:integer`  | `runtime > 42 `                                       |  `FILTER(?runtime > 42)`                                                                       |
| `int`            | `xsd:integer`  | `runtime > 40+2 `                                     |  `FILTER(?runtime > 42)`                                                                       |
| `numeric`        | -              | `val >= 42.73`                                        |  `FILTER(?val >= 42.73)`                                                                       |
| `date`           | `xsd:date`     | `released BETWEEN '2021-04-01' AND '2021-04-30'`      |  `FILTER(?released >= "2021-04-01"^^xsd:date) FILTER(?released <= "2021-04-30"^^xsd:date)`     |
| `timestamp`      | `xsd:dateTime` | `modified > '2021-04-06 14:07:00.26'`                 |  `FILTER(?modified > "2021-04-06T14:07:00.260000"^^xsd:dateTime)`                              |
| `timestamp`      | `xsd:dateTime` | `modified < '2021-04-06 14:07:00.26'`                 |  `FILTER(?modified < "2021-04-06T14:07:00.260000"^^xsd:dateTime)`                              |
| `text`           | `xsd:string`   | `country IN ('Germany','France','Portugal')`          |  `FILTER(?country IN ("Germany"^^xsd:string, "France"^^xsd:string, "Portugal"^^xsd:string))`   |
| `varchar`        | -              | `country NOT IN ('Germany','France','Portugal')`      |  `FILTER(?country NOT IN ("Germany", "France", "Portugal"))`                                   |
| `name`           | -              | `country = ANY(ARRAY['Germany','France','Portugal'])` |  `FILTER(?country IN ("Germany", "France", "Portugal"))`                                       |
| `boolean`        | `xsd:boolean`  | `bnode IS TRUE`                                       |  `FILTER(?node = "true"^^xsd:boolean)`                                                         |
| `boolean`        | `xsd:boolean`  | `bnode IS NOT TRUE`                                   |  `FILTER(?node != "true"^^xsd:boolean)`                                                        |
| `boolean`        | `xsd:boolean`  | `bnode IS FALSE`                                      |  `FILTER(?node = "false"^^xsd:boolean)`                                                        |
| `boolean`        | `xsd:boolean`  | `bnode IS NOT FALSE`                                  |  `FILTER(?node != "false"^^xsd:boolean)`                                                       |

Foreign table columns with the option `language`
 
| PostgreSQL Type  | Language Tag   | SQL WHERE Condition                                   | SPARQL (pushdown)                                                                              |
|------------------|----------------|-------------------------------------------------------|------------------------------------------------------------------------------------------------|
| `text`           | `en`           | `name = 'foo'`                                        |  `FILTER(?s = "foo"@en)`                                                                       |
| `name`           | `de`           | `name <> 'foo'`                                       |  `FILTER(?s != "foo"@de)`                                                                      |
| `varchar`        | `en`           | `country NOT IN ('Germany','France','Portugal')`      |  `FILTER(?country NOT IN ("Germany"@en, "France"@en, "Portugal"@en))`                          |
| `text`           | `*`            | `name = 'foo'`                                        |  `FILTER(STR(?s) = "foo")`                                                                     |

Foreign table columns with the option `expression`
 
| PostgreSQL Type  | Expression                        | Literal Type | SQL WHERE Condition | SPARQL (pushdown)                                                                              |
|------------------|-----------------------------------|--------------|---------------------|------------------------------------------------------------------------------------------------|
| `boolean`        | `STRSTARTS(STR(?country),"https")`| `xsd:boolean`|`bnode IS TRUE`      |  `FILTER(STRSTARTS(STR(?country),"http") = "true"^^xsd:boolean)`                               |
| `int`            | `STRLEN(?variable)`               | `xsd:integer`|`strlen > 10`        |  `FILTER(STRLEN(?variable) > 10)`                                                              |
| `text`           | `UCASE(?variable)`                | -            |`uname = 'FOO'`      |  `FILTER(UCASE(?variable) = "FOO")`                                                            |

## [Examples](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#examples)

These and other examples can be downloaded [here](https://github.com/jimjonesbr/rdf_fdw/tree/main/examples)

### [DBpedia](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#dbpedia)

#### Create a `SERVER` and `FOREIGN TABLE` to query the [DBpedia](https://dbpedia.org/sparql) SPARQL Endpoint (Politicians):

```sql
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

CREATE FOREIGN TABLE politicians (
  uri text        OPTIONS (variable '?person',     nodetype 'iri'),
  name text       OPTIONS (variable '?personname', nodetype 'literal', literaltype 'xsd:string'),
  birthdate date  OPTIONS (variable '?birthdate',  nodetype 'literal', literaltype 'xsd:date'),
  party text      OPTIONS (variable '?partyname',  nodetype 'literal', literaltype 'xsd:string'),
  country text    OPTIONS (variable '?country',    nodetype 'literal', language 'en')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
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
```

In the following SQL query we can observe that: 

* the executed SPARQL query was logged.
* the SPARQL `SELECT` was modified to retireve only the columns used in the SQL `SELECT` and `WHERE` clauses.
* the conditions in the SQL `WHERE` clause were pushed down as SPARQL `FILTER` conditions.
* the SQL `ORDER BY` clause was pushed down as SPARQL `ORDER BY`.
* the `FETCH FIRST ... ROWS ONLY` was pushed down as SPARQL `LIMIT`
* the column `country` has a `language` option, and its value is used as a language tag in the SPARQL expression: `FILTER(?country IN ("Germany"@en, "France"@en))`

```sql
SELECT name, birthdate, party
FROM politicians
WHERE 
  country IN ('Germany','France') AND 
  birthdate > '1995-12-31' AND
  party <> ''
ORDER BY birthdate DESC, party ASC
FETCH FIRST 5 ROWS ONLY;
NOTICE:  SPARQL query sent to 'https://dbpedia.org/sparql':

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
       FILTER(?country IN ("Germany"@en, "France"@en))
 FILTER(?birthdate > "1995-12-31"^^xsd:date)
 FILTER(?partyname != ""^^xsd:string)
}
ORDER BY  DESC (?birthdate)  ASC (?partyname)
LIMIT 5

        name        | birthdate  |                  party                  
--------------------+------------+-----------------------------------------
 Louis Boyard       | 2000-08-26 | La France insoumise
 Klara Schedlich    | 2000-01-04 | Bündnis 90/Die Grünen
 Pierrick Berteloot | 1999-01-11 | Rassemblement National
 Niklas Wagener     | 1998-04-16 | Bündnis 90/Die Grünen
 Jakob Blankenburg  | 1997-08-05 | Sozialdemokratische Partei Deutschlands
(5 rows)

```

### [Getty Thesaurus](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#getty-thesaurus)

#### Create a `SERVER` and `FOREIGN TABLE` to query the [Getty Thesaurus](http://vocab.getty.edu/sparql) SPARQL endpoint [Non-Italians Who Worked in Italy](http://vocab.getty.edu/queries?toc=&query=SELECT+*+WHERE+%7B%3Fs+a+%3Fo%7D+LIMIT+1&implicit=true&equivalent=false#Non-Italians_Who_Worked_in_Italy):

Find non-Italians who worked in Italy and lived during a given time range

* Having event that took place in tgn:1000080 Italy or any of its descendants
* Birth date between 1250 and 1780
* Just for variety, we look for artists as descendants of facets ulan:500000003 "Corporate bodies" or ulan:500000002 "Persons, Artists", rather than having type "artist" as we did in previous queries. In the previous query we used values{..} but we here use filter(in(..)).
* Not having nationality aat:300111198 Italian or any of its descendants

```sql
CREATE SERVER getty
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'http://vocab.getty.edu/sparql.xml',
  format 'application/sparql-results+xml'
);

CREATE FOREIGN TABLE getty_non_italians (
  uri text   OPTIONS (variable '?x'),
  name text  OPTIONS (variable '?name'),
  bio text   OPTIONS (variable '?bio'),
  birth int  OPTIONS (variable '?birth')
)
SERVER getty OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX ontogeo: <http://www.ontotext.com/owlim/geo#>
  PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  PREFIX gvp: <http://vocab.getty.edu/ontology#>
  PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
  PREFIX schema: <http://schema.org/>
  PREFIX foaf: <http://xmlns.com/foaf/0.1/>

   SELECT ?x ?name ?bio ?birth {
  {SELECT DISTINCT ?x
    {?x foaf:focus/bio:event/(schema:location|(schema:location/gvp:broaderExtended)) tgn:1000080-place}}
 	 ?x gvp:prefLabelGVP/xl:literalForm ?name;
	    foaf:focus/gvp:biographyPreferred [
	    schema:description ?bio;
       	gvp:estStart ?birth].

  FILTER ("1250"^^xsd:gYear <= ?birth && ?birth <= "1780"^^xsd:gYear)
  FILTER EXISTS {?x gvp:broaderExtended ?facet.
  FILTER(?facet in (ulan:500000003, ulan:500000002))}
  FILTER NOT EXISTS {?x foaf:focus/(schema:nationality|(schema:nationality/gvp:broaderExtended)) aat:300111198}}
  '); 
```

In the following SQL query we can observe that: 

* the executed SPARQL query was logged.
* all conditions were applied locally (`rdf_fdw` currently does not support sub selects).
* the columns of the FOREIGN TABLE have only the required option `variable`, as the other options are only necessary for the pushdown feature.

```sql
SELECT name, bio, birth
FROM getty_non_italians
WHERE bio ~~* '%artist%'
ORDER BY birth 
LIMIT 10;

NOTICE:  SPARQL query sent to 'http://vocab.getty.edu/sparql.xml':

  PREFIX ontogeo: <http://www.ontotext.com/owlim/geo#>
  PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  PREFIX gvp: <http://vocab.getty.edu/ontology#>
  PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
  PREFIX schema: <http://schema.org/>
  PREFIX foaf: <http://xmlns.com/foaf/0.1/>

   SELECT ?x ?name ?bio ?birth {
  {SELECT DISTINCT ?x
    {?x foaf:focus/bio:event/(schema:location|(schema:location/gvp:broaderExtended)) tgn:1000080-place}}
 	 ?x gvp:prefLabelGVP/xl:literalForm ?name;
	    foaf:focus/gvp:biographyPreferred [
	    schema:description ?bio;
       	gvp:estStart ?birth].

  FILTER ("1250"^^xsd:gYear <= ?birth && ?birth <= "1780"^^xsd:gYear)
  FILTER EXISTS {?x gvp:broaderExtended ?facet.
  FILTER(?facet in (ulan:500000003, ulan:500000002))}
  FILTER NOT EXISTS {?x foaf:focus/(schema:nationality|(schema:nationality/gvp:broaderExtended)) aat:300111198}}
  

                name                 |                                  bio                                  | birth 
-------------------------------------+-----------------------------------------------------------------------+-------
 Juán de España                      | Spanish artist and goldsmith, active 1455                             |  1415
 Coecke van Aelst, Pieter, the elder | Flemish artist, architect, and author, 1502-1550                      |  1502
 Worst, Jan                          | Dutch artist, active ca. 1645-1655                                    |  1605
 Mander, Karel van, III              | Dutch portraitist and decorative artist, 1608-1670, active in Denmark |  1608
 Ulft, Jacob van der                 | Dutch artist, 1627-1689                                               |  1627
 Fiammingo, Giacomo                  | Flemish artist, fl. 1655                                              |  1635
 Marotte, Charles                    | French artist, fl. ca.1719-1743                                       |  1699
 Troll, Johann Heinrich              | Swiss artist, 1756-1824                                               |  1756
 Beys, G.                            | French artist, fl. ca.1786-1800                                       |  1766
 Vaucher, Gabriel Constant           | Swiss artist, 1768-1814                                               |  1768
(10 rows)

```

### [BBC Programmes and Music](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#bbc-programmes-and-music)

#### Create a `SERVER` and `FOREIGN TABLE` to query the [BBC Programmes and Music](http://vocab.getty.edu/sparql) SPARQL endpoint (authors and their work)

```sql
CREATE SERVER bbc
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://lod.openlinksw.com/sparql',
  format 'application/sparql-results+xml'
);


CREATE FOREIGN TABLE artists (
  id text          OPTIONS (variable '?person',  nodetype 'iri'),
  name text        OPTIONS (variable '?name',    nodetype 'literal'),
  itemid text      OPTIONS (variable '?created', nodetype 'iri'),
  title text       OPTIONS (variable '?title',   nodetype 'literal'),
  description text OPTIONS (variable '?descr',   nodetype 'literal')
)
SERVER bbc OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX foaf:    <http://xmlns.com/foaf/0.1/>
  PREFIX blterms: <http://www.bl.uk/schemas/bibliographic/blterms#>
  PREFIX dcterms: <http://purl.org/dc/terms/>
  PREFIX bibo:    <http://purl.org/ontology/bibo/>
  PREFIX xsd:     <http://www.w3.org/2001/XMLSchema#>

  SELECT *
  {
    ?person a foaf:Person ;
      foaf:name ?name ;
      blterms:hasCreated ?created .
    ?created a bibo:Book ;
      dcterms:title ?title ;
    dcterms:description ?descr
  } 
'); 
```

In the following SQL query we can observe that: 

* the executed SPARQL query was logged.
* the SPARQL `SELECT` clause was reduced to the columns used in the SQL query
* `DISTINCT` and `WHERE` and clauses were pushed down.
* an `ORDER BY` was automatically pushded down due the use of `DISTINCT`

```sql
SELECT DISTINCT title, description 
FROM artists
WHERE name = 'John Lennon';

NOTICE:  SPARQL query sent to 'https://lod.openlinksw.com/sparql':

 PREFIX foaf:    <http://xmlns.com/foaf/0.1/>
 PREFIX blterms: <http://www.bl.uk/schemas/bibliographic/blterms#>
 PREFIX dcterms: <http://purl.org/dc/terms/>
 PREFIX bibo:    <http://purl.org/ontology/bibo/>
 PREFIX xsd:     <http://www.w3.org/2001/XMLSchema#>

SELECT DISTINCT ?name ?title ?descr 
{
    ?person a foaf:Person ;
      foaf:name ?name ;
      blterms:hasCreated ?created .
    ?created a bibo:Book ;
      dcterms:title ?title ;
    dcterms:description ?descr
   FILTER(?name = "John Lennon")
}
ORDER BY  ASC (?title)  ASC (?descr)

                            title                             |                                                                      description                                
                                      
--------------------------------------------------------------+-----------------------------------------------------------------------------------------------------------------
--------------------------------------
 Sometime in New York City                                    | Limited ed. of 3500 copies.
 All you need is love                                         | Originally published: 2019.
 The John Lennon letters                                      | Originally published: London: Weidenfeld &amp; Nicolson, 2012.
 Imagine John Yoko                                            | In slip case housed in box (37 x 29 x 8 cm).
 Imagine                                                      | Originally published: 2017.
 More Beatles hits arranged for ukulele                       | Words and music by John Lennon and Paul McCartney except Something, words and music by George Harrison.
 The Lennon play : In his own write the Lennon play           | 'Adapted from John Lennon's best-selling books "In his own write" and "A Spaniard in the works".' - Book jacket.
 More Beatles hits arranged for ukulele                       | Publishers no.: NO91245.
 The John Lennon letters                                      | Originally published: 2012.
 Imagine John Yoko                                            | Includes numbered officially stamped giclée print in clothbound portfolio case.
 Last interview : all we are saying, John Lennon and Yoko Ono | Previous ed.: published as The Playboy interviews with John Lennon and Yoko Ono. New York: Playboy Press, 1981; 
Sevenoaks: New English Library, 1982.
 John Lennon : drawings, performances, films                  | Published in conjunction with the exhibition "The art of John Lennon: drawings, performances, films", Kunsthalle
 Bremen, 21 May to 13 August 1995.
 John Lennon in his own write                                 | Originally published in Great Britain in1964 by Johnathan Cape.
 Sometime in New York City                                    | In box.
 Imagine John Yoko                                            | "This edition is limited to 2,000 copies worldwide, numbered 1-2,000, plus 10 copies retained by the artist, ins
cribed i-x"--Container.
 Last interview : all we are saying, John Lennon and Yoko Ono | This ed. originally published: London: Sidgwick &amp; Jackson, 2000.
 Imagine John Yoko                                            | Includes index.
 Sometime in New York City                                    | Includes index.
 A Spaniard in the works                                      | Originally published: Great Britain : Johnathan Cape, 1965.
 All you need is love                                         | Board book.
 The Playboy interviews with John Lennon and Yoko Ono         | Originally published: New York : Playboy Press, c1981.
 Skywriting by word of mouth                                  | Originally published: New York: HarperCollins; London: Jonathan Cape, 1986.
 John Lennon in his own write ; and a Spaniard in the works   | Originally published: 1964.
 John Lennon in his own write ; and a Spaniard in the works   | Originally published: 1965.
 Lennon on Lennon : conversations with John Lennon            | "This edition published by arrangement with Chicago Review Press"--Title page verso.
(25 rows)

```

### [Wikidata](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#wikidata)

#### Create a `SERVER` and `FOREIGN TABLE` to query the [Wikidata](https://query.wikidata.org/sparql) SPARQL endpoint (Places that are below 10 meters above sea level and their geo coordinates)

```sql
CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://query.wikidata.org/sparql');

CREATE FOREIGN TABLE places_below_sea_level (
  wikidata_id text         OPTIONS (variable '?place'),
  label text               OPTIONS (variable '?label'),
  wkt geometry(point,4326) OPTIONS (variable '?location'),
  elevation numeric        OPTIONS (variable '?elev')
)
SERVER wikidata OPTIONS (
  log_sparql 'true',
  sparql '
  SELECT *
  WHERE
  {
    ?place rdfs:label ?label .
    ?place p:P2044/psv:P2044 ?placeElev.
    ?placeElev wikibase:quantityAmount ?elev.
    ?placeElev wikibase:quantityUnit ?unit.
    bind(0.01 as ?km).
    FILTER( (?elev < ?km*1000 && ?unit = wd:Q11573)
        || (?elev < ?km*3281 && ?unit = wd:Q3710)
        || (?elev < ?km      && ?unit = wd:Q828224) ).
    ?place wdt:P625 ?location.    
    FILTER(LANG(?label)="en")
    SERVICE wikibase:label { bd:serviceParam wikibase:language "[AUTO_LANGUAGE],en" }
  }
');   
```

In the following SQL query we can observe that: 

* the executed SPARQL query was logged.
* the SPARQL `SELECT` clause was reduced to the columns used in the SQL query
* the `FETCH FIRST 10 ROWS ONLY` was pushded down in a SPARQL `LIMIT`

```sql
SELECT wikidata_id, label, wkt
FROM places_below_sea_level
FETCH FIRST 10 ROWS ONLY;

INFO:  SPARQL query sent to 'https://query.wikidata.org/sparql':

SELECT ?place ?label ?location 
{
    ?place rdfs:label ?label .
    ?place p:P2044/psv:P2044 ?placeElev.
    ?placeElev wikibase:quantityAmount ?elev.
    ?placeElev wikibase:quantityUnit ?unit.
    bind(0.01 as ?km).
    FILTER( (?elev < ?km*1000 && ?unit = wd:Q11573)
        || (?elev < ?km*3281 && ?unit = wd:Q3710)
        || (?elev < ?km      && ?unit = wd:Q828224) ).
    ?place wdt:P625 ?location.    
    FILTER(LANG(?label)="en")
    SERVICE wikibase:label { bd:serviceParam wikibase:language "[AUTO_LANGUAGE],en" }
  }
LIMIT 10

               wikidata_id                |      label      |                    wkt                     
------------------------------------------+-----------------+--------------------------------------------
 http://www.wikidata.org/entity/Q61308849 | Tuktoyaktuk A   | 0101000000295C8FC2F5A060C0EC51B81E855B5140
 http://www.wikidata.org/entity/Q403083   | Ahyi            | 010100000041E3101111216240A9CDA7AAAA6A3440
 http://www.wikidata.org/entity/Q31796625 | Ad Duyūk        | 01010000003AE97DE36BB7414065A54929E8DE3F40
 http://www.wikidata.org/entity/Q54888910 | Lydd Library    | 010100000074B7EBA52902ED3F0C3B8C497F794940
 http://www.wikidata.org/entity/Q27745421 | Écluse de Malon | 0101000000E8F9D346757AFDBFB9FB1C1F2DE64740
 http://www.wikidata.org/entity/Q14204611 | Bilad el-Rum    | 0101000000D578E9263168394021C059B2793A3D40
 http://www.wikidata.org/entity/Q2888647  | Petza'el        | 0101000000F886DEBC9AB841408D05D940A7054040
 http://www.wikidata.org/entity/Q2888816  | Gilgal          | 0101000000272E0948E2B84140539C1F56EAFF3F40
 http://www.wikidata.org/entity/Q4518111  | Chupícuaro      | 0101000000F10DBD79356559C05C30283B4CAD3340
 http://www.wikidata.org/entity/Q2889475  | Na'aran         | 010100000069A1D4C627BA41409EE61CF084F73F40
(10 rows)

```
### [Import data into QGIS](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#import-data-into-qgis)

#### Create a `SERVER` and a `FOREIGN TABLE` to query the [DBpedia](https://dbpedia.org/sparql) SPARQL Geographic Information Systems
The `rdf_fdw` can also be used as a bridge between GIS (Geographic Information Systems) and RDF Triplestores. This example shows how to retrieve geographic coordinates of all German public universities from DBpedia, create a WKT (Well Known Text) representation of them, and finally import this data into [QGIS](https://qgis.org/) to plot a map.

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

To deploy `rdf_fdw` with docker just pick one of the supported PostgreSQL versions, install the [requirements](#requirements) and [compile](#build-and-install) the [source code](https://github.com/jimjonesbr/rdf_fdw/releases). For instance, a `rdf_fdw` `Dockerfile` for PostgreSQL 15 should look like this (minimal example):

```dockerfile
FROM postgres:15

RUN apt-get update && \
    apt-get install -y make gcc postgresql-server-dev-15 libxml2-dev libcurl4-openssl-dev

RUN mkdir /extensions
COPY ./rdf_fdw-1.0.0.tar.gz /extensions/
WORKDIR /extensions

RUN tar xvzf rdf_fdw-1.0.0.tar.gz && \
    cd rdf_fdw-1.0.0 && \
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

If you're cool enough, try out the latest commits:

Dockerfile


```dockerfile
FROM postgres:15

RUN apt-get update && \
    apt-get install -y git make gcc postgresql-server-dev-15 libxml2-dev libcurl4-openssl-dev

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