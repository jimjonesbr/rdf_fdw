CREATE SERVER testserver
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql'
);

/* invalid column option - OPTION 'foo' does not exist */
CREATE FOREIGN TABLE table_error1 (
  name text OPTIONS (foo '?s')
) SERVER testserver OPTIONS 
  (sparql 'SELECT * WHERE {?s ?p ?o}');

/* invalid column option - the column OPTION 'variable' cannot be empty. */
CREATE FOREIGN TABLE table_error2 (
  name text OPTIONS (variable '')
) SERVER testserver OPTIONS 
  (sparql 'SELECT * WHERE {?s ?p ?o}');

/* invalid foreign table option - SERVER option 'foo' does not exist.  */
CREATE FOREIGN TABLE table_error3 (
  name text OPTIONS (variable '?s')
) SERVER testserver OPTIONS 
  (foo 'SELECT * WHERE {?s ?p ?o}');

/* 
 * invalid foreign table option - SPARQL variable '?foo' does not exist 
 * in the SPARQL query. The query will return only empty rows.
 */
CREATE FOREIGN TABLE table_error4 (
  name text OPTIONS (variable '?foo')
) SERVER testserver OPTIONS 
  (log_sparql 'true', 
   sparql 'SELECT * WHERE {?s ?p ?o}');

SELECT * FROM table_error4
LIMIT 3;

/* invalid foreign table option - log_sparql must be boolean */
CREATE FOREIGN TABLE table_error5 (
  name text OPTIONS (variable '?s')
) SERVER testserver OPTIONS 
  (sparql 'SELECT * WHERE {?s ?p ?o}',
  log_sparql 'foo');

CREATE FOREIGN TABLE t1 (
  name text OPTIONS (variable '?s')
) SERVER testserver OPTIONS 
  (sparql 'SELECT ?s WHERE {?s ?p ?o} LIMIT 1', log_sparql 'true');

/* invalid SPARQL - missing closing curly braces (\n)*/
CREATE FOREIGN TABLE t2 (s text OPTIONS (variable '?s')
) SERVER testserver OPTIONS (sparql '
  SELECT ?s {?s ?p ?o '); 

/* invalid SPARQL - missing closing curly braces */
CREATE FOREIGN TABLE t3 (s text OPTIONS (variable '?s')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o'); 

/* invalid SPARQL - missing closing curly braces (\t) */
CREATE FOREIGN TABLE t4 (s text OPTIONS (variable '?s')
) SERVER testserver OPTIONS (sparql '  SELECT ?s {?s ?p ?o'); 

/* invalid SPARQL - missing opening curly braces (\n)*/
CREATE FOREIGN TABLE t5 (s text OPTIONS (variable '?s')
) SERVER testserver OPTIONS (sparql '
  SELECT ?s ?s ?p ?o}'); 

/* missing SELECT  */
CREATE FOREIGN TABLE t7 (s text OPTIONS (variable '?s')
) SERVER testserver OPTIONS (sparql '?s {?s ?p ?o}');

/* empty nodetype  */
CREATE FOREIGN TABLE t7 (s text OPTIONS (variable '?s', nodetype '')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');
/* invalid nodetype  */
CREATE FOREIGN TABLE t7 (s text OPTIONS (variable '?s', nodetype 'foo')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid literaltype - contains whitespaces  */
CREATE FOREIGN TABLE t7 (s text OPTIONS (variable '?s', literaltype ' xsd:string')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid language - contains whitespaces  */
CREATE FOREIGN TABLE t7 (s text OPTIONS (variable '?s', language 'de ')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid combination of 'literaltype' and 'language'  */
CREATE FOREIGN TABLE t8 (s text OPTIONS (variable '?s', literaltype 'iri', language 'es')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid 'variable' */
CREATE FOREIGN TABLE t9 (s text OPTIONS (variable 's', expression 'now()')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid 'variable' */
CREATE FOREIGN TABLE t10 (s text OPTIONS (variable '?a-z', expression 'now()')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid 'variable' */
CREATE FOREIGN TABLE t11 (s text OPTIONS (variable '?a$z', expression 'now()')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid 'variable' */
CREATE FOREIGN TABLE t12 (s text OPTIONS (variable '?a?z', expression 'now()')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid 'variable' */
CREATE FOREIGN TABLE t13 (s text OPTIONS (variable ' ?a', expression 'now()')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');

/* invalid foreign table option - fetch_size empty */
CREATE FOREIGN TABLE t14 (
  name text OPTIONS (variable '?s')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}', fetch_size '');

/* invalid foreign table option - fetch_size negative */
CREATE FOREIGN TABLE t15 (
  name text OPTIONS (variable '?s')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}', fetch_size '-1');

/* invalid option for rdfnode column*/
CREATE FOREIGN TABLE t16 (
  name rdfnode OPTIONS (variable '?s', expression 'STR(?s)')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');
SELECT * FROM t16;

/* clean up */
DROP SERVER testserver CASCADE;