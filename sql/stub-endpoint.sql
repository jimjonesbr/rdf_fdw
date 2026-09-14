/*
 * Tests against the stub SPARQL endpoint deployed by
 * scripts/postgres-env/stub-endpoint/deploy-stub-endpoint.sh.
 *
 * A conforming triplestore cannot produce the responses exercised here, so
 * these cases are not reachable through the other local tests: what rdf_fdw
 * does with a malformed or hostile answer has to be driven by an endpoint we
 * control.
 */

CREATE SERVER stub
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'http://stub-endpoint/single-binding.xml',
  connect_timeout '5');

CREATE SERVER stub_repeated
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'http://stub-endpoint/repeated-binding.xml',
  connect_timeout '5');

CREATE FOREIGN TABLE ft_single (
  s rdfnode OPTIONS (variable '?s')
) SERVER stub OPTIONS (sparql 'SELECT ?s WHERE {?s ?p ?o}');

CREATE FOREIGN TABLE ft_repeated (
  s rdfnode OPTIONS (variable '?s')
) SERVER stub_repeated OPTIONS (sparql 'SELECT ?s WHERE {?s ?p ?o}');

/* control: a well formed single-binding response */
SELECT * FROM ft_single;

/*
 * A response that repeats a variable inside one <result>. InsertRetrievedData()
 * sizes its type, value and null arrays by the number of foreign table
 * columns, but used to advance the index it writes them at once per matching
 * binding instead of once per column: the inner loop walked every binding of
 * the row and did not stop at the first match. 400 bindings against a
 * one-column table therefore wrote an Oid, a char and a full 8-byte Datum
 * past the end of all three allocations, 399 times over, with both the length
 * and the contents chosen by whoever answered the request. The allocator
 * noticed the smashed chunk header:
 *
 *   ERROR:  repalloc called with invalid pointer 0x... (header 0x00007f...)
 *
 * A column takes its value from a single binding, so the scan stops at the
 * first match and the extra bindings are ignored.
 */
CREATE TABLE cloned_repeated (s rdfnode);

CALL rdf_fdw_clone_table(
  foreign_table => 'ft_repeated',
  target_table  => 'cloned_repeated',
  fetch_size    => 1,
  max_records   => 1,
  create_table  => false,
  verbose       => false);

SELECT count(*) AS rows_cloned, min(s::text) AS value FROM cloned_repeated;

/* the same response through an ordinary foreign scan, which takes a different
 * path and was never affected */
SELECT * FROM ft_repeated;

/* clean up */
DROP TABLE cloned_repeated;
DROP SERVER stub CASCADE;
DROP SERVER stub_repeated CASCADE;
