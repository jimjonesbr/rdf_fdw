/*
 invalid foreign server option
 'foo' ins't a valid endpoint URL
*/
CREATE SERVER rdfserver_error1 
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'foo'
);

/* 
  empty foreign server option
  empty endpoints are not allowed
*/
CREATE SERVER rdfserver_error2
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint ''
);

/* 
  invalid enable_pushdown value
*/
CREATE SERVER rdfserver_error3
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  enable_pushdown 'foo'
);

/*
  invalid fetch_size
  nevative fetch_size
 */
CREATE SERVER rdfserver_error4
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  fetch_size '-1'
);

/*
  invalid fetch_size
  empty string
 */
CREATE SERVER rdfserver_error5
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  fetch_size ''
);

CREATE SERVER testserver
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

/* 
  invalid colum option 
  OPTION 'foo' does not exist
*/
CREATE FOREIGN TABLE table_error1 (
  name text OPTIONS (foo '?s')
) SERVER testserver OPTIONS 
  (sparql 'SELECT * WHERE {?s ?p ?o}');

/* 
  empty colum option 
  the column OPTION 'variable' cannot be empty.
*/
CREATE FOREIGN TABLE table_error2 (
  name text OPTIONS (variable '')
) SERVER testserver OPTIONS 
  (sparql 'SELECT * WHERE {?s ?p ?o}');

/* 
  invalid foreign table option 
  SERVER option 'foo' does not exist.  
*/
CREATE FOREIGN TABLE table_error3 (
  name text OPTIONS (variable '?s')
) SERVER testserver OPTIONS 
  (foo 'SELECT * WHERE {?s ?p ?o}');

/* 
  invalid foreign table option 
  SPARQL variable '?foo' does not exist in the SPARQL query.
  the query will return only empty rows.
*/
CREATE FOREIGN TABLE table_error4 (
  name text OPTIONS (variable '?foo')
) SERVER testserver OPTIONS 
  (log_sparql 'true', 
   sparql 'SELECT * WHERE {?s ?p ?o}');

SELECT * FROM table_error3
LIMIT 3;

/* 
  invalid foreign table option 
  log_sparql must be boolean
*/
CREATE FOREIGN TABLE table_error5 (
  name text OPTIONS (variable '?s')
) SERVER testserver OPTIONS 
  (sparql 'SELECT * WHERE {?s ?p ?o}',
  log_sparql 'foo');


/* INSERT, UPDATE and DELETE not supported */
CREATE SERVER testserver2
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql'
);

CREATE FOREIGN TABLE t1 (
  name text OPTIONS (variable '?s')
) SERVER testserver2 OPTIONS 
  (sparql 'SELECT ?s WHERE {?s ?p ?o} LIMIT 1', log_sparql 'true');

INSERT INTO t1 (name) VALUES ('foo');
UPDATE t1 SET name = 'foo';
DELETE FROM t1;

/* EXPLAIN isn't supported*/
EXPLAIN SELECT * FROM t1;

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
 invalid relation.
 an existing sequence is used instead of a relation on
 'target_table', so the oid retrieval will not fail.
 it has to check if the oid corresponds to a relation and
 throw an error otherwise.
 */
CREATE SEQUENCE seq1;
CALL
    rdf_fdw_clone_table(
        foreign_table => 't1',
        target_table  => 'seq1'
    );

/* invalid SPARQL - missing closing curly braces (\n)*/
CREATE FOREIGN TABLE t2 (s text OPTIONS (variable '?s')
) SERVER testserver2 OPTIONS (sparql '
  SELECT ?s {?s ?p ?o '); 

/* invalid SPARQL - missing closing curly braces */
CREATE FOREIGN TABLE t3 (s text OPTIONS (variable '?s')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o'); 

/* invalid SPARQL - missing closing curly braces (\t) */
CREATE FOREIGN TABLE t4 (s text OPTIONS (variable '?s')
) SERVER testserver2 OPTIONS (sparql '  SELECT ?s {?s ?p ?o'); 

/* invalid SPARQL - missing opening curly braces (\n)*/
CREATE FOREIGN TABLE t5 (s text OPTIONS (variable '?s')
) SERVER testserver2 OPTIONS (sparql '
  SELECT ?s ?s ?p ?o}'); 

/* empty WHERE clause */
CREATE FOREIGN TABLE t6 (s text OPTIONS (variable '?s')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {}'); 

SELECT * FROM t6;

/* missing SELECT  */
CREATE FOREIGN TABLE t7 (s text OPTIONS (variable '?s')
) SERVER testserver2 OPTIONS (sparql '?s {?s ?p ?o}');

/* empty nodetype  */
CREATE FOREIGN TABLE t7 (s text OPTIONS (variable '?s', nodetype '')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid nodetype  */
CREATE FOREIGN TABLE t7 (s text OPTIONS (variable '?s', nodetype 'foo')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid literaltype - contains whitespaces  */
CREATE FOREIGN TABLE t7 (s text OPTIONS (variable '?s', literaltype ' xsd:string')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid language - contains whitespaces  */
CREATE FOREIGN TABLE t7 (s text OPTIONS (variable '?s', language 'de ')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid combination of 'literaltype' and 'language'  */
CREATE FOREIGN TABLE t8 (s text OPTIONS (variable '?s', literaltype 'iri', language 'es')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid 'variable' */
CREATE FOREIGN TABLE t9 (s text OPTIONS (variable 's', expression 'now()')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid 'variable' */
CREATE FOREIGN TABLE t10 (s text OPTIONS (variable '?a-z', expression 'now()')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid 'variable' */
CREATE FOREIGN TABLE t11 (s text OPTIONS (variable '?a$z', expression 'now()')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid 'variable' */
CREATE FOREIGN TABLE t12 (s text OPTIONS (variable '?a?z', expression 'now()')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid 'variable' */
CREATE FOREIGN TABLE t13 (s text OPTIONS (variable ' ?a', expression 'now()')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* 
  invalid foreign table option 
  fetch_size empty
*/
CREATE FOREIGN TABLE t14 (
  name text OPTIONS (variable '?s')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}', fetch_size '');

/* 
  invalid foreign table option 
  fetch_size negative
*/
CREATE FOREIGN TABLE t15 (
  name text OPTIONS (variable '?s')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}', fetch_size '-1');

DROP SEQUENCE seq1;
DROP FOREIGN TABLE IF EXISTS t1;
DROP TABLE IF EXISTS t1_local, t2_local;
