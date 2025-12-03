
SELECT (current_setting('server_version_num')::int < 140000) AS skip_test \gset

\if :skip_test
\quit
\endif

SET timezone TO 'Etc/UTC';

CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://query.wikidata.org/sparql');

CREATE FOREIGN TABLE ft (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER wikidata OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * {wd:Q192490 ?p ?o . FILTER (?p = <http://www.w3.org/2000/01/rdf-schema#label>)}');

/*
 * 't1' only partially matches with 'dbpedia_cities', with columns
 * 'city_name' and 'uri'.
 * SERVER option 'fetch_size' will be used, as both FOREIGN TABLE and
 * function call do not set 'fetch_size'. 
 * 'commit_page' is set to 'false', so all retrieved and inserted records
 * are committed only when the transaction finishes.
 */
CREATE TABLE public.t1(p rdfnode, o rdfnode);
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft',
        target_table  => 'public.t1',
        verbose => true,        
        commit_page => false
    );

SELECT * FROM public.t1 ORDER BY o::text COLLATE "C";

/*
 * only a single column of 't2' matches the foreign table 'dbpedia_cities'.
 * reducing the 'fetch_size' to 2 and setting maximum limit of 9 records.
 * the SPARQL query will be ordered by 'city_name'
 */
CREATE TABLE public.t2(p rdfnode, o rdfnode);
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft',
        target_table  => 'public.t2',
        fetch_size => 2,
        max_records => 9,
        orderby_column => 'o',
        verbose => true,
        commit_page => true
    );

SELECT * FROM public.t2 ORDER BY o::text COLLATE "C";

/* 
 * 't3' does not exist. it will be created by the function due to
 * 'create_table => true' as a copy of 'dbedia_cities'
 */
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft',
        target_table  => 'public.t3',
        create_table => true,
        orderby_column => 'o',
        sort_order => 'DESC',
        verbose => true
    );

SELECT * FROM public.t3 ORDER BY o::text COLLATE "C";

/*
 * 'public.t4' only partially matches the columns of 'public.ft'.
 * the non-matching columns will be set to NULL.
 */
CREATE TABLE public.t4 (p rdfnode, o rdfnode, foo text);
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft',
        target_table  => 'public.t4',
        orderby_column => 'o',
        fetch_size => 4,
        max_records => 15
    );

SELECT * FROM public.t4 ORDER BY o::text COLLATE "C";

/*
 * 'public.t5' does not exist.
 * it will be created, since 'create_table' is set to true.
 */
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft',
        target_table  => 'public.t5',
        orderby_column => 'o',
        create_table => true,
        fetch_size => 4,
        max_records => 15
    );

SELECT * FROM public.t5 ORDER BY o::text COLLATE "C";

/* 
 * the matching columns of 'public.t4' and 'public.t5' 
 * must be identical 
 */
SELECT p,o FROM public.t4
EXCEPT
SELECT p,o FROM public.t5;

/* 
 * setting 'begin_offset' to 10
 */
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft',
        target_table  => 'public.t6',
        orderby_column => 'o',
        create_table => true,
        begin_offset => 10,
        fetch_size => 2,
        max_records => 7,
        verbose => true
    );

SELECT * FROM public.t6 ORDER BY o::text COLLATE "C";

/*
 * clean up the mess
 */
DROP TABLE IF EXISTS public.t1, public.t2, public.t3, public.t4, public.t5, public.t6;
DROP SERVER wikidata CASCADE;

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
