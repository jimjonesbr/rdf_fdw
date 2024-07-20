CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql',
         fetch_size '5');

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
    {
        ?city a dbo:City ;
            foaf:name ?name ;
            dbo:federalState dbr:North_Rhine-Westphalia ;
            dbo:elevation ?elevation
    }
    ORDER BY ?name
    OFFSET 7300 LIMIT 4200
');

/*
 * 't1' only partially matches with 'dbpedia_cities', with columns
 * 'city_name' and 'uri'.
 * SERVER option 'fetch_size' will be used, as both FOREIGN TABLE and
 * function call do not set 'fetch_size'. 
 * 'commit_page' is set to 'false', so all retrieved and inserted records
 * are committed only when the transaction finishes.
 */
CREATE TABLE public.t1(id serial, city_name text, c1_null text, uri text, c2_null text);
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.dbpedia_cities',
        target_table  => 'public.t1',
        verbose => true,
        commit_page => false
    );

SELECT * FROM public.t1;

/*
 * only a single column of 't2' matches the foreign table 'dbpedia_cities'.
 * reducing the 'fetch_size' to 2 and setting maximum limit of 9 records.
 * the SPARQL query will be ordered by 'city_name'
 */ 
 
CREATE TABLE public.t2(id serial, foo int, bar date, city_name text);
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.dbpedia_cities',
        target_table  => 'public.t2',
        fetch_size => 2,
        max_records => 9,
        orderby_column => 'city_name',
        verbose => true,
        commit_page => true
    );

SELECT * FROM public.t2;

/* 
 * 't3' does not exist. it will be created by the function due to
 * 'create_table => true' as a copy of 'dbedia_cities'
 */
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.dbpedia_cities',
        target_table  => 'public.t3',
        create_table => true,
        orderby_column => 'elevation',
        sort_order => 'DESC',
        verbose => true
    );

SELECT * FROM public.t3;


/*----------------------------------------------------------------------------------------------------------*/

CREATE FOREIGN TABLE public.film (
  film_id text    OPTIONS (variable '?film'),
  name text       OPTIONS (variable '?name', language 'en'),
  released date   OPTIONS (variable '?released', literaltype 'xsd:date'),
  runtime int     OPTIONS (variable '?runtime'),
  abstract text   OPTIONS (variable '?abstract')
)
SERVER dbpedia OPTIONS (
  log_sparql 'false',
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
     OFFSET 7300 LIMIT 4200
'); 

/*
 * 'public.heap1' only partially matches the columns of 'public.film'.
 * the non-matching columns will be set to NULL.
 */
CREATE TABLE public.heap1 (id bigserial, foo text, runtime int, bar text, name varchar, released date);
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.film',
        target_table  => 'public.heap1',
        orderby_column => 'released',
        fetch_size => 4,
        max_records => 15
    );

SELECT * FROM public.heap1;

/*
 * 'public.heap2' does not exist.
 * it will be created, since 'create_table' is set to true.
 */
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.film',
        target_table  => 'public.heap2',
        orderby_column => 'released',
        create_table => true,
        fetch_size => 4,
        max_records => 15
    );

SELECT runtime,name,released FROM public.heap2;

/* 
 * the matching columns of 'public.heap1' and 'public.heap2' 
 * must be identical 
 */
SELECT runtime,name,released FROM public.heap1
EXCEPT
SELECT runtime,name,released FROM public.heap2;

/* 
 * setting 'begin_offset' to 10
 */
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.film',
        target_table  => 'public.heap3',
        orderby_column => 'released',
        create_table => true,
        begin_offset => 10,
        fetch_size => 2,
        max_records => 7,
        verbose => true
    );

SELECT runtime,name,released FROM public.heap3;

/*
 * clean up the mess
 */
DROP TABLE IF EXISTS public.t1, public.t2, public.t3, public.heap1, public.heap2, public.heap3;
DROP FOREIGN TABLE public.film, dbpedia_cities;
DROP SERVER dbpedia;

/* == Exceptions == */
CREATE TABLE public.t1_local(id serial, c1_null text, c2_null text);
CREATE TABLE public.t2_local(name text, foo text);

/*
 ordinary table instead of foreign table in 'foreign_table'
 */
CALL
    rdf_fdw_clone_table(
        foreign_table => 't1_local',
        target_table  => 't2_local'
    );

/*
 foreign table instead of an ordinary table in 'target_table'
 */
CALL
    rdf_fdw_clone_table(
        foreign_table => 't1',
        target_table  => 't1'
    );

/*
 empty target_table
*/
CALL
    rdf_fdw_clone_table(
        foreign_table => 't1',
        target_table => ''
    );

/*
 empty foreign_table
*/
CALL
    rdf_fdw_clone_table(
        foreign_table => '',
        target_table => 't1_local'
    );

/*
 negative fetch_size
*/
CALL
    rdf_fdw_clone_table(
        foreign_table => 't1',
        target_table => 't1_local',
        fetch_size => -1
    );

/*
 negative begin_offset
*/
CALL
    rdf_fdw_clone_table(
        foreign_table => 't1',
        target_table => 't1_local',
        begin_offset => -1
    );

/*
 invalid ordering_column
*/
CALL
    rdf_fdw_clone_table(
        foreign_table => 't1',
        target_table => 't2_local',
        orderby_column => 'foo'
    );

/*
 target table does not match any column of t1
 */
CALL
    rdf_fdw_clone_table(
        foreign_table => 't1',
        target_table  => 't1_local'
    );

/*
 invalid sort_order
*/
CALL
    rdf_fdw_clone_table(
        foreign_table => 't1',
        target_table => 't1_local',
        sort_order => 'foo'
    );

/*
  NULL foreign_table
*/
CALL rdf_fdw_clone_table(
      foreign_table => NULL,
      target_table  => 't1_local');

/*
  NULL target_table
*/
CALL rdf_fdw_clone_table(
      foreign_table => 't1',
      target_table  => NULL);

/*
  NULL begin_offset
*/
CALL rdf_fdw_clone_table(
      foreign_table => 't1',
      target_table  => 't1_local',
      begin_offset => NULL);

/*
  NULL fetch_size
*/
CALL rdf_fdw_clone_table(
      foreign_table => 't1',
      target_table  => 't1_local',
      begin_offset => 42,
      fetch_size => NULL);

/*
  NULL max_records
*/
CALL rdf_fdw_clone_table(
      foreign_table => 't1',
      target_table  => 't1_local',
      begin_offset => 42,
      fetch_size => 8,
      max_records => NULL);

/*
  NULL sort_order
*/
CALL rdf_fdw_clone_table(
      foreign_table => 't1',
      target_table  => 't1_local',
      begin_offset => 42,
      fetch_size => 8,
      max_records => 103,
      orderby_column => 'foo',
      sort_order => NULL);

/*
  NULL create_table
*/
CALL rdf_fdw_clone_table(
      foreign_table => 't1',
      target_table  => 't1_local',
      begin_offset => 42,
      fetch_size => 8,
      max_records => 103,
      orderby_column => 'foo',
      sort_order => 'DESC',
      create_table => NULL);

/*
  NULL verbose
*/
CALL rdf_fdw_clone_table(
      foreign_table => 't1',
      target_table  => 't1_local',
      begin_offset => 42,
      fetch_size => 8,
      max_records => 103,
      orderby_column => 'foo',
      sort_order => 'DESC',
      create_table => true,
      verbose => NULL);

/*
  NULL commit_page
*/
CALL rdf_fdw_clone_table(
      foreign_table => 't1',
      target_table  => 't1_local',
      begin_offset => 42,
      fetch_size => 8,
      max_records => 103,
      orderby_column => 'foo',
      sort_order => 'DESC',
      create_table => true,
      verbose => false,
      commit_page => NULL);

DROP TABLE IF EXISTS t1_local, t2_local;