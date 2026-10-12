/*
 * When a foreign scan contacts the endpoint. These tests need no network:
 * the server points at a port nothing listens on, with retries off, so a
 * query that is actually sent fails at once, and a statement that succeeds
 * proves that nothing was sent.
 */
SET client_min_messages TO WARNING;
\set VERBOSITY terse

CREATE SERVER se_srv FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (endpoint 'http://127.0.0.1:1/sparql', connect_retry '0', connect_timeout '1');

CREATE FOREIGN TABLE se_ft (
  s rdfnode OPTIONS (variable '?s'),
  o rdfnode OPTIONS (variable '?o')
) SERVER se_srv OPTIONS (sparql 'SELECT ?s ?o {?s ?p ?o}');

/* a scan that is read from sends its query */
SELECT * FROM se_ft;

/*
 * The executor initialises every scan of a plan before it reads any row,
 * including scans it then never reads from. None of these sends a query.
 */

/* a condition that does not depend on the rows is checked once, above the
 * scan; when it is false, the scan is never read */
SELECT * FROM se_ft WHERE now() < '2000-01-01';

/* a subquery evaluated only for a row of the outer query, which has none */
SELECT x, (SELECT count(*) FROM se_ft) FROM generate_series(1, 0) AS x;

/* a cursor sends its query when it is fetched from, not when it is declared */
BEGIN;
DECLARE se_cur CURSOR FOR SELECT * FROM se_ft;
CLOSE se_cur;
DECLARE se_cur CURSOR FOR SELECT * FROM se_ft;
FETCH se_cur;
ROLLBACK;

DROP SERVER se_srv CASCADE;
