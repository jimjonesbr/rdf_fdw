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

/* 
  invalid enable_xml_huge value
*/
CREATE SERVER rdfserver_error6
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  enable_xml_huge 'foo'
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

SELECT * FROM table_error4
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


/* UPDATE and DELETE not supported */
CREATE SERVER testserver2
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql'
);

CREATE FOREIGN TABLE t1 (
  name text OPTIONS (variable '?s')
) SERVER testserver2 OPTIONS 
  (sparql 'SELECT ?s WHERE {?s ?p ?o} LIMIT 1', log_sparql 'true');

UPDATE t1 SET name = 'foo';

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

/*
 empty user name
*/
CREATE USER MAPPING FOR postgres SERVER testserver2 OPTIONS (user '', password 'foo');

/*
 empty password
*/
CREATE USER MAPPING FOR postgres SERVER testserver2 OPTIONS (user 'foo', password '');

/*
 invalid option
*/
CREATE USER MAPPING FOR postgres SERVER testserver2 OPTIONS (user 'jim', foo 'bar');

/* invalid option for rdfnode column*/
CREATE FOREIGN TABLE t16 (
  name rdfnode OPTIONS (variable '?s', expression 'STR(?s)')
) SERVER testserver2 OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');
SELECT * FROM t16;

DROP SERVER testserver2 CASCADE;