---------------------------------------------
# PostgreSQL Foreign Data Wrapper for RDF Triplestores

The `rdf_fdw` is a PostgreSQL Foreign Data Wrapper to easily access RDF Triplestores, including pushdown of several SQL Query clauses.

> [!WARNING]  
> **THIS SOFTWARE IS CURRENTLY UNDER DEVELOPMENT AND IS STILL NOT READY FOR PRODUCTION USE**

![CI](https://github.com/jimjonesbr/rdf_fdw/actions/workflows/ci.yml/badge.svg)

## Index

- [Requirements](#requirements)
- [Build and Install](#build-and-install)
- [Update](#update)
- [Usage](#usage)
  - [CREATE SERVER](#create-server)
  - [CREATE FOREIGN TABLE](#create-foreign-table)
  - [ALTER TABLE and ALTER SERVER](#alter-table-and-alter-server)
  - [Version](#version)
- [Pushdown](#pushdown)
  - [LIMIT](#limit)
  - [ORDER BY](#order-by)
  - [DISTINCT](#distinct)
  - [WHERE](#where)
    - [Supported Data Types and Operators](#supported-data-types-and-operators)
    - [IN and ANY constructs](#in-and-any-constructs)
  - [Pushdown Examples](#pushdown-examples)
- [Examples](#examples)
  - [DBpedia](#dbpedia)
  - [Getty Thesaurus](#getty-thesaurus)
  - [BBC Programmes and Music](#bbc-programmes-and-music)
  - [Wikidata](#wikidata)
- [Deploy with Docker](#deploy-with-docker)
 
## [Requirements](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#requirements)

* [libxml2](http://www.xmlsoft.org/): version 2.5.0 or higher.
* [libcurl](https://curl.se/libcurl/): version 7.74.0 or higher.
* [PostgreSQL](https://www.postgresql.org): version 11 or higher.

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

The SQL command [CREATE SERVER](https://www.postgresql.org/docs/current/sql-createserver.html) defines a new foreign server. The user who defines the server becomes its owner. A SERVER requires an `endpoint`, so that `rdf_fdw` knows where to sent the SPARQL queries.

The following example creates a `SERVER` that connects to the DBpedia SPARQL Endpoint:

```sql
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');
```


**Server Options**:

| Server Option | Type          | Description                                                                                                        |
|---------------|----------------------|--------------------------------------------------------------------------------------------------------------------|
| `endpoint`     | **required**            | URL address of the SPARQL Endpoint.
| `enable_pushdown` | optional            | Globally enables or disables pushdown of SQL clauses into SPARQL (default `true`)
| `format` | optional            | The `rdf_fdw` expects the result sets encoded in the [SPARQL Query Results XML Format](https://www.w3.org/TR/rdf-sparql-XMLres/), which can be normally enforced by setting the MIME type `application/sparql-results+xml` in the `Accept` HTTP request header. However, there are some products that expect a differently value, e.g. `xml`, `rdf-xml`. In case it differs from the official MIME type, it should be set in this parameter (default `application/sparql-results+xml`).
| `http_proxy` | optional            | Proxy for HTTP requests.
| `proxy_user` | optional            | User for proxy server authentication.
| `proxy_user_password` | optional            | Password for proxy server authentication.
| `connect_timeout`         | optional            | Connection timeout for HTTP requests in seconds (default `300` seconds).
| `connect_retry`         | optional            | Number of attempts to retry a request in case of failure (default `3` times).
| `request_redirect`         | optional            | Enables URL redirect issued by the server (default `false`).
| `request_max_redirect`         | optional            | Limit of how many times the URL redirection may occur. If that many redirections have been followed, the next redirect will cause an error. Not setting this parameter or setting it to `0` will allow an infinite number of redirects.
| `custom`         | optional            | One or more parameters expected by the configured RDF triplestore. Multiple parameters separated by `&`, e.g. `signal_void=on&signal_unconnected=on`. Custom parameters are added to the URL.


### [CREATE FOREIGN TABLE](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#create_foreign_table)

Foreign Tables from the `rdf_fdw` work as a proxy between PostgreSQL clients and RDF Triplestores. Each `FOREIGN TABLE` column must be mapped to a SPARQL `variable`, so that PostgreSQL knows where to display each node retrieved from the SPARQL queries. Optionally, it is possible to add an `expression` to the column, so that function calls can be used to retrieve or format the data.

**Server Options**:

| Option        | Type        | Description                                                                                                        |
|---------------|-------------|--------------------------------------------------------------------------------------------------------------------|
| `sparql`      | **required**    | The raw SPARQL query to be executed    |
| `log_sparql`  | optional    | Logs the exact SPARQL query executed. This OPTION is useful to check for any modification to the configured SPARQL query due to push down  |
| `enable_pushdown` | optional            | Enables or disables pushdown of SQL clauses into SPARQL for a specific foreign table. This overrides the `SERVER` option `enable_pushdown` |

**Column Options**:

| Option        | Type        | Description                                                                                                        |
|---------------|-------------|--------------------------------------------------------------------------------------------------------------------|
| `variable`    | **required**    | A SPARQL variable used in the SERVER OPTION `sparql`. This option maps the table column to the SPARQL variable.    |
| `expression`  | optional    | Similar to `variable`, but instead of a SPARQL variable it can handle expressions, e.g. function calls. It is imperative that an `expression` is given an alias that matches the `variable`, so that the result sets can be returned to the right column. For instance, `variable '?foo'` and `expression 'CONCAT(?s,?o) AS ?foo'` |


The following example creates a `FOREIGN TABLE` connected to the server `dbpedia`. SELECT queries executed against this table will execute the SPARQL query set in the OPTION `sparql`, and its result sets are mapped to each column of the table via the column OPTION `variable`.

```sql
CREATE FOREIGN TABLE film (
  film_id text    OPTIONS (variable '?film'),
  name text       OPTIONS (variable '?name'),
  released date   OPTIONS (variable '?released'),
  runtime int     OPTIONS (variable '?runtime'),
  abstract text   OPTIONS (variable '?abstract')
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

### [ALTER TABLE and ALTER SERVER](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#alter-table-and-alter-server)

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

### [Version](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#version)

**Synopsis**

*text* **rdf_fdw_version**();

-------

**Availability**: 1.0.0

**Description**

Shows the version of the installed `rdf_fdw` and its main libraries.

**Usage**

```sql
SELECT rdf_fdw_version();
                                                                                       rdf_fdw_version
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 rdf_fdw = 0.0.1-dev, libxml = 2.9.10, libcurl = libcurl/7.74.0 OpenSSL/1.1.1w zlib/1.2.11 brotli/1.0.9 libidn2/2.3.0 libpsl/0.21.0 (+libidn2/2.3.0) libssh2/1.9.0 nghttp2/1.43.0 librtmp/2.3
(1 row)
```

## [Pushdown](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#pushdown)
 
A *pushdown* is the ability to translate SQL queries in such a way that operations are performed in the data source rather than in PostgreSQL, e.g. sorting, formatting, filtering. This feature can significantly reduce the number of records retrieved from the data source. For instance, a SQL `LIMIT` not pushed down means that the target system will perform a full scan in the data source, prepare everything for data transfer, return it to PostgreSQL via network, and then PostgreSQL will only locally discard the unnecessary data, which depending on the total number of records can be extremely inefficient. The `rdf_fdw` tries to translate SQL into SPARQL queries, which due to their conceptual differences is not always an easy task, so it is often worth considering to keep SQL queries involving foreign tables as simple as possible - or just to stick to the features, data types and operators described in this section. 

### LIMIT

`LIMIT` clauses are pushed down if the SQL query does not contain aggregates and all conditions in the `WHERE` clause can be pushed translated to SPARQL.
 
| SQL | SPARQL|
| -- | --- |
| `LIMIT x`| `LIMIT x` 
| `OFFSET y LIMIT x`| `OFFSET y LIMIT x` 
| `FETCH FIRST x ROWS` | `LIMIT x` |
| `FETCH FIRST ROW ONLY` | `LIMIT 1` |
| `OFFSET x ROWS FETCH FIRST y ROW ONLY` | `OFFSET y LIMIT x` |
 

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

| Data type                                                  | Supported operator                    |
|------------------------------------------------------------|---------------------------------------|
| `text`, `varchar`                                          | `=`                                   |
| `date`, `timestamp`, `timestamp with time zone`            | `=`, `<>`, `!=`, `>`, `>=`, `<`, `<=` |
| `smallint`, `int`, `bigint`, `numeric`, `double precision` | `=`, `<>`, `!=`, `>`, `>=`, `<`, `<=` |

#### IN and ANY constructs

SQL `IN`  and `ANY` constructs are translated into the SPARQL [`IN` operator](https://www.w3.org/TR/2013/REC-sparql11-query-20130321/#func-in), which will be placed in a [`FILTER` evaluation](https://www.w3.org/TR/2013/REC-sparql11-query-20130321/#evaluation).

### Pushdown Examples

| SQL                                                   | SPARQL |
|-------------------------------------------------------|--------|
| `name = 'foo'`                                        |  `FILTER(STR(?s) = "foo")`      |
| `name <> 'foo'`                                       |  `FILTER(STR(?s) != "foo")`      |
| `runtime > 42 `                                       |  `FILTER(?runtime > 42)`      |
| `runtime > 40+2 `                                     |  `FILTER(?runtime > 42)`      |
| `released BETWEEN '2021-04-01' AND '2021-04-30'`      |  `FILTER(xsd:date(?released) >= xsd:date("2021-04-01")) FILTER(xsd:date(?released) <= xsd:date("2021-04-30"))`      |
| `modified > '2021-04-06 14:07:00.26'`                 |  `FILTER(xsd:dateTime(?modified) > xsd:dateTime("2021-04-06T14:07:00.260000"))`      |
| `modified < '2021-04-06 14:07:00.26'`                 |  `FILTER(xsd:dateTime(?modified) < xsd:dateTime("2021-04-06T14:07:00.260000"))`      |
| `country IN ('Germany','France','Portugal')`          |  `FILTER(STR(?country) IN ("Germany", "France", "Portugal"))`      |
| `country NOT IN ('Germany','France','Portugal')`      |  `FILTER(STR(?country) NOT IN ("Germany", "France", "Portugal"))`      |
| `country = ANY(ARRAY['Germany','France','Portugal'])` |  `FILTER(STR(?country) IN ("Germany", "France", "Portugal"))`      |


## [Examples](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#examples)

These and other examples can be downloaded [here](https://github.com/jimjonesbr/rdf_fdw/tree/main/expected)

### [DBpedia](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#dbpedia)

#### Create a `SERVER` and `FOREIGN TABLE` to query the [DBpedia](https://dbpedia.org/sparql) SPARQL Endpoint (Politicians):

```sql
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

CREATE FOREIGN TABLE politicians (
  uri text        OPTIONS (variable '?person'),
  name text       OPTIONS (variable '?personname'),
  birthdate date  OPTIONS (variable '?birthdate'),
  party text      OPTIONS (variable '?partyname'),
  country text    OPTIONS (variable '?country')
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
  FILTER(STR(?country) IN ("Germany", "France"))
  FILTER(xsd:date(?birthdate) > xsd:date("1995-12-31"))
  FILTER(STR(?partyname) != "")
}
ORDER BY DESC (?birthdate), ASC (?partyname)
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

#### Create a `SERVER` and `FOREIGN TABLE` to query the [DBpedia](https://dbpedia.org/sparql) SPARQL Endpoint (German Public Universities):

**This examples requires the extension PostGIS**

```sql
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

CREATE FOREIGN TABLE german_public_universities (
  id text      OPTIONS (variable '?uri'),
  name text    OPTIONS (variable '?name'),
  lon numeric  OPTIONS (variable '?lon'),
  lat numeric  OPTIONS (variable '?lat'),
  wkt text     OPTIONS (variable '?wkt',
                        expression 'CONCAT("POINT(",?lon," ",?lat,")") AS ?wkt')
) SERVER dbpedia OPTIONS (
  log_sparql 'true',
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
      }'
  ); 
```

In the following SQL query we can observe that: 

* the executed SPARQL query was logged.
* the SPARQL `SELECT` was modified to retireve only the columns used in the SQL `SELECT` and `WHERE` clauses.
* the `expression` OPTION set in the column `wkt` was used in the SPARQL `SELECT` clause -  although it wasn't previously defined in the SPARQL query set in the `CREATE TABLE` statement. This expression creates a WKT (Well Known Text) literal, based on `lon` and `lat`, that can be cast into a PostGIS `geometry` or `geography` value.
* the SQL `ORDER BY lat DESC` clause was pushed down as SPARQL `ORDER BY DESC(lat)`.
* the `FETCH FIRST 10 ROWS ONLY` clause was pushed down as SPARQL `LIMIT 10`

```sql
SELECT name, wkt::geometry 
FROM german_public_universities 
ORDER BY lat DESC 
FETCH FIRST 10 ROWS ONLY;

NOTICE:  SPARQL query sent to 'https://dbpedia.org/sparql':


PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
PREFIX dbp: <http://dbpedia.org/property/>
PREFIX dbo: <http://dbpedia.org/ontology/>
PREFIX dbr:  <http://dbpedia.org/resource/>
    
SELECT ?name ?lat CONCAT("POINT(",?lon," ",?lat,")") AS ?wkt 
WHERE {
  ?uri dbo:type dbr:Public_university ;
  dbp:name ?name;
    geo:lat ?lat; 
    geo:long ?lon; 
    dbp:country dbr:Germany
   }
ORDER BY DESC (?lat)
LIMIT 10

                name                |                    wkt                     
------------------------------------+--------------------------------------------
 Europa Universität Flensburg       | 0101000000000000806CE722400000000054634B40
 University of Greifswald           | 010100000001000000CFBF2A40000000201D0C4B40
 University of Lübeck               | 0101000000FEFFFFFF62692540FFFFFFFF20EB4A40
 Hamburg University of Technology   | 0101000000000000005BF02340000000A0FCBA4A40
 University of Bremen               | 0101000000000000800CB5214001000000E78D4A40
 University of the Arts Bremen      | 0101000000000000C0F5882140000000208D8C4A40
 Humboldt University of Berlin      | 0101000000FEFFFFFF62C92A40000000A04F424A40
 Berlin University of the Arts      | 01010000000100004065A72A40000000602C414A40
 Berlin School of Economics and Law | 0101000000FEFFFF3FF1AC2A40000000A01D3E4A40
 Free University of Berlin          | 0101000000FFFFFFBFC3942A40000000C0FD394A40
(10 rows)
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
* All conditions were applied locally (`rdf_fdw` currently does not support sub selects).

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
  id text          OPTIONS (variable '?person'),
  name text        OPTIONS (variable '?name'),
  itemid text      OPTIONS (variable '?created'),
  title text       OPTIONS (variable '?title'),
  description text OPTIONS (variable '?description')
)
SERVER bbc OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX blterms: <http://www.bl.uk/schemas/bibliographic/blterms#>
  PREFIX dcterms: <http://purl.org/dc/terms/>
  PREFIX bibo: <http://purl.org/ontology/bibo/>

  SELECT ?person ?name ?created ?title ?description 
  WHERE 
  {
    ?person a foaf:Person ;
      foaf:name ?name ;
      blterms:hasCreated ?created .
    ?created a bibo:Book ;
      dcterms:title ?title ;
    dcterms:description ?description
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

PREFIX foaf: <http://xmlns.com/foaf/0.1/>
PREFIX blterms: <http://www.bl.uk/schemas/bibliographic/blterms#>
PREFIX dcterms: <http://purl.org/dc/terms/>
PREFIX bibo: <http://purl.org/ontology/bibo/>


SELECT DISTINCT ?name ?title ?description 
{
  ?person a foaf:Person ;
    foaf:name ?name ;
    blterms:hasCreated ?created .
  ?created a bibo:Book ;
    dcterms:title ?title ;
  dcterms:description ?description
 FILTER(STR(?name) = "John Lennon")
}
ORDER BY  ASC (?title)  ASC (?description)

                            title                             |                                                                      description                                                                      
--------------------------------------------------------------+-------------------------------------------------------------------------------------------------------------------------------------------------------
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
 Last interview : all we are saying, John Lennon and Yoko Ono | Previous ed.: published as The Playboy interviews with John Lennon and Yoko Ono. New York: Playboy Press, 1981; Sevenoaks: New English Library, 1982.
 John Lennon : drawings, performances, films                  | Published in conjunction with the exhibition "The art of John Lennon: drawings, performances, films", Kunsthalle Bremen, 21 May to 13 August 1995.
 John Lennon in his own write                                 | Originally published in Great Britain in1964 by Johnathan Cape.
 Sometime in New York City                                    | In box.
 Imagine John Yoko                                            | "This edition is limited to 2,000 copies worldwide, numbered 1-2,000, plus 10 copies retained by the artist, inscribed i-x"--Container.
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
  wikidata_id text  OPTIONS (variable '?place'),
  label text        OPTIONS (variable '?label'),
  wkt text    OPTIONS (variable '?location'),
  elevation numeric  OPTIONS (variable '?elev')
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

NOTICE:  SPARQL query sent to 'https://query.wikidata.org/sparql':

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


               wikidata_id                |      label      |                wkt                 
------------------------------------------+-----------------+------------------------------------
 http://www.wikidata.org/entity/Q61308849 | Tuktoyaktuk A   | Point(-133.03 69.43)
 http://www.wikidata.org/entity/Q403083   | Ahyi            | Point(145.033333333 20.416666666)
 http://www.wikidata.org/entity/Q14204611 | Bilad el-Rum    | Point(25.407 29.228419444)
 http://www.wikidata.org/entity/Q27745421 | Écluse de Malon | Point(-1.842397 47.798252)
 http://www.wikidata.org/entity/Q4518111  | Chupícuaro      | Point(-101.581388888 19.676944444)
 http://www.wikidata.org/entity/Q31796625 | Ad Duyūk        | Point(35.43298 31.87073)
 http://www.wikidata.org/entity/Q54888910 | Lydd Library    | Point(0.906514 50.949197)
 http://www.wikidata.org/entity/Q55112853 | Ansdell Library | Point(-2.991656 53.743795)
 http://www.wikidata.org/entity/Q2888647  | Petza'el        | Point(35.442222222 32.044166666)
 http://www.wikidata.org/entity/Q2888816  | Gilgal          | Point(35.44440556 31.99966944)
(10 rows)
```

## [Deploy with Docker](https://github.com/jimjonesbr/rdf_fdw/blob/master/README.md#deploy-with-docker)

To deploy `rdf_fdw` with docker just pick one of the supported PostgreSQL versions, install the [requirements](#requirements) and [compile](#build-and-install) the [source code](https://github.com/jimjonesbr/rdf_fdw/releases). For instance, a `rdf_fdw` `Dockerfile` for PostgreSQL 15 should look like this (minimal example):

```dockerfile
FROM postgres:15

RUN apt-get update && \
    apt-get install -y make gcc postgresql-server-dev-15 libxml2-dev libcurl4-openssl-dev

RUN tar xvzf rdf_fdw-[VERSION].tar.gz && \
    cd rdf_fdw-[VERSION] && \
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