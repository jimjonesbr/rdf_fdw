CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql',
         fetch_size '5');

CREATE FOREIGN TABLE public.dbpedia_cities (
  uri text           OPTIONS (variable '?city', nodetype 'iri'),
  city_name text     OPTIONS (variable '?name', nodetype 'literal', literaltype 'xsd:string'),
  elevation text  OPTIONS (variable '?elevation', nodetype 'literal', literaltype 'xsd:integer')
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
 */
CREATE TABLE public.t1(id serial, city_name text, c1_null text, uri text, c2_null text);

/* 
 * SERVER option 'fetch_size' will be used, as both FOREIGN TABLE and
 * function call do not set 'fetch_size'.
 */
--SET client_min_messages = DEBUG2;
SELECT
    rdf_fdw_clone_table(
        foreign_table => 'public.dbpedia_cities',
        target_table  => 'public.t1',
        verbose => true
    );

SELECT * FROM public.t1;

--select pg_sleep(11);
/*
 * only a single column of 't2' matches the foreign table 'dbpedia_cities'.
 * reducing the 'fetch_size' to 2 and setting maximum limit of 9 records.
 * the SPARQL query will be ordered by 'city_name'
 */ 
 
CREATE TABLE public.t2(id serial, foo int, bar date, city_name text);
SELECT
    rdf_fdw_clone_table(
        foreign_table => 'public.dbpedia_cities',
        target_table  => 'public.t2',
        fetch_size => 2,
        max_records => 9,
        ordering_column => 'city_name',
        verbose => true
    );

SELECT * FROM public.t2;

/* 
 * 't3' does not exist. it will be created by the function due to
 * 'create_table => true' as a copy of 'dbedia_cities'
 */
SELECT
    rdf_fdw_clone_table(
        foreign_table => 'public.dbpedia_cities',
        target_table  => 'public.t3',
        create_table => true,
        ordering_column => 'city_name',
        verbose => true
    );

SELECT * FROM public.t3;



DROP TABLE IF EXISTS public.t1, public.t2, public.t3;















/*
CREATE TABLE public.t2(
  id serial,
  c1_null text,
  c2_null text
);

SELECT
    rdf_fdw_clone_table(
        foreign_table => 'public.dbpedia_cities'::regclass::oid,
        target_table  => 'public.t2'::regclass::oid
    );

DROP TABLE IF EXISTS t1,t2;

*/


/*
CREATE SERVER testserver2
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql'
);

CREATE FOREIGN TABLE t1 (
  name text OPTIONS (variable '?s')
) SERVER testserver2 OPTIONS 
  (sparql 'SELECT ?s WHERE {?s ?p ?o}', log_sparql 'true');


SET client_min_messages = DEBUG1;

SELECT
    rdf_fdw_clone_table(
        foreign_table => 't1'::regclass::oid,
        target_table  => 't1_local'::regclass::oid
    );
*/



--SET client_min_messages = DEBUG1;


/*
SELECT count(*) FROM public.t_dbpedia0;


SELECT
    rdf_fdw_clone_table(
        foreign_table => 'public.dbpedia_cities'::regclass::oid,
        target_table => 'public.t_dbpedia1',
        fetch_size => 2,
        max_records => 9,
        create_table => true,
        verbose => true
    );

SELECT * FROM t_local1;

SELECT 
    rdf_fdw_clone_table(
        foreign_table => 'public.dbpedia_cities'::regclass::oid,
        ordering_column => 'city_name',
        target_table => 'public.t_dbpedia2',
        fetch_size => 6,
        create_table => true,
        verbose => true
    );

SELECT * FROM t_local2;
*/


/* 
 * Target table exists
 * Manually create target table with columns in a different order than 
 * in the FOREIGN TABLE 
 */
 /*
CREATE TABLE public.t_dbpedia3 (city_name text, uri text);

SELECT 
    rdf_fdw_clone_table(
        foreign_table => 'public.dbpedia_cities'::regclass::oid,
        target_table => 'public.t_dbpedia3',
        fetch_size => 5,
        verbose => true
    );

SELECT * FROM public.t_dbpedia3;

DROP SERVER dbpedia CASCADE;

DROP TABLE t_dbpedia1;
DROP TABLE t_dbpedia2;
DROP TABLE t_dbpedia3;

*/

