CREATE SERVER testserver
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  connect_timeout '42'
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

/* The 'variable' option is required, but PostgreSQL only runs an FDW
 * validator for columns that actually carry an OPTIONS clause, so a column
 * declared with no options at all never reached it and left the SPARQL
 * variable unset. Every consumer dereferences it unconditionally, starting
 * with the pstrdup() that builds the SPARQL SELECT clause, so planning a
 * query against such a table used to crash the backend. It is rejected at
 * plan time now; EXPLAIN is enough to reach the check, and no request is
 * made to the endpoint. */
CREATE FOREIGN TABLE t17 (
  name rdfnode
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');
EXPLAIN (COSTS OFF) SELECT name FROM t17;

/* the same applies to a column that the query never selects: the option is
 * required of every column, not only of the ones a given query happens to
 * touch */
CREATE FOREIGN TABLE t18 (
  name rdfnode OPTIONS (variable '?s'),
  untouched rdfnode
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');
EXPLAIN (COSTS OFF) SELECT name FROM t18;

/* dropped columns are exempt: they carry no options by construction and are
 * never mapped to a SPARQL variable */
CREATE FOREIGN TABLE t19 (
  name rdfnode OPTIONS (variable '?s'),
  gone rdfnode OPTIONS (variable '?g')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');
ALTER FOREIGN TABLE t19 DROP COLUMN gone;
EXPLAIN (COSTS OFF) SELECT name FROM t19;

/* nor may a dropped column be named by the deprecated-types warning, which
 * used to report "........pg.dropped.N........" as a column using a
 * deprecated native PostgreSQL type */
CREATE FOREIGN TABLE t20 (
  name text OPTIONS (variable '?s'),
  gone rdfnode OPTIONS (variable '?g')
) SERVER testserver OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');
ALTER FOREIGN TABLE t20 DROP COLUMN gone;
EXPLAIN (COSTS OFF) SELECT name FROM t20;

/* SPARQL names a variable with either sigil, and "?x" and "$x" are the same
 * variable. A mapping declared with "$" must therefore behave exactly like the
 * same mapping declared with "?", including in the SELECT clause rdf_fdw
 * generates - the result bindings an endpoint sends back carry no sigil, and
 * are matched against the mapped variable as "?name". */
CREATE FOREIGN TABLE t21 (
  s rdfnode OPTIONS (variable '$s'),
  o rdfnode OPTIONS (variable '$o')
) SERVER testserver OPTIONS (sparql 'SELECT * {$s ?p $o}');
EXPLAIN (COSTS OFF) SELECT s, o FROM t21 WHERE o = 1::rdfnode;

/* clean up */
DROP SERVER testserver CASCADE;