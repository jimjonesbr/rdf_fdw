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


CREATE SERVER testserver
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  enable_pushdown 'fAlSe'
);
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