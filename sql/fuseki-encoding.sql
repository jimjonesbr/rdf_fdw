/*
 * Values travel between a database that is not encoded in UTF-8 and an
 * endpoint, which speaks UTF-8 only. The test runs in a LATIN1 database of its
 * own and takes a value with a non-ASCII character through each path:
 *
 *  - INSERT and DELETE send it in the body of a SPARQL update;
 *  - a condition on it is pushed down into the query string of a SELECT;
 *  - reading it back converts it from UTF-8 to LATIN1.
 *
 * The client encoding is set to UTF8 so that this file and its expected
 * output can hold the character as it is; the server converts it to LATIN1.
 */

DROP DATABASE IF EXISTS rdf_fdw_latin1;
CREATE DATABASE rdf_fdw_latin1
  ENCODING 'LATIN1' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0;

\c rdf_fdw_latin1
SET client_encoding TO 'UTF8';

CREATE EXTENSION rdf_fdw;

SELECT getdatabaseencoding() AS server_encoding;

CREATE SERVER fuseki
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'http://fuseki:3030/dt/sparql',
  update_url 'http://fuseki:3030/dt/update');

CREATE USER MAPPING FOR postgres
SERVER fuseki OPTIONS (user 'admin', password 'secret');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o')
)
SERVER fuseki OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .');

/* left behind by an earlier run that failed half-way */
DELETE FROM ft WHERE subject = '<http://example.org/rdf_fdw/encoding>';

INSERT INTO ft (subject, predicate, object) VALUES
('<http://example.org/rdf_fdw/encoding>', '<http://www.w3.org/2000/01/rdf-schema#label>', '"café"@fr');

/* é is the single byte e9 in LATIN1 */
SELECT object, encode(object::text::bytea, 'hex') AS latin1_bytes
FROM ft
WHERE subject = '<http://example.org/rdf_fdw/encoding>';

/* the condition is pushed down, so it only matches if the endpoint gets é */
SELECT subject
FROM ft
WHERE object = '"café"@fr'::rdfnode;

DELETE FROM ft WHERE subject = '<http://example.org/rdf_fdw/encoding>';

SELECT count(*)
FROM ft
WHERE subject = '<http://example.org/rdf_fdw/encoding>';

\c contrib_regression
DROP DATABASE rdf_fdw_latin1;
