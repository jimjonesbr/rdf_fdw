/* Edge cases and corner case tests for DELETE operations */

CREATE SERVER fuseki
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint   'http://fuseki:3030/dt/sparql',
  update_url 'http://fuseki:3030/dt/update');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER fuseki OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * WHERE {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .'
);

CREATE USER MAPPING FOR postgres
SERVER fuseki OPTIONS (user 'admin', password 'secret');

/* Test 1: DELETE with language-tagged literals */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://example.org/test1>', '<http://www.w3.org/2000/01/rdf-schema#label>', '"English label"@en'),
  ('<https://example.org/test1>', '<http://www.w3.org/2000/01/rdf-schema#label>', '"Deutsche Bezeichnung"@de'),
  ('<https://example.org/test1>', '<http://www.w3.org/2000/01/rdf-schema#label>', '"Libellé français"@fr');

DELETE FROM ft WHERE object = '"Deutsche Bezeichnung"@de'::rdfnode;
SELECT * FROM ft WHERE subject = '<https://example.org/test1>';

/* Test 2: DELETE with typed literals (different datatypes) */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://example.org/test2>', '<http://example.org/prop>', '"42"^^<http://www.w3.org/2001/XMLSchema#int>'),
  ('<https://example.org/test2>', '<http://example.org/prop>', '"42.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'),
  ('<https://example.org/test2>', '<http://example.org/prop>', '"42"^^<http://www.w3.org/2001/XMLSchema#string>');

DELETE FROM ft WHERE object = '"42"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT * FROM ft WHERE subject = '<https://example.org/test2>';

/* Test 3: DELETE with blank nodes (if supported) */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://example.org/test3>', '<http://example.org/hasBlankNode>', '_:b1'),
  ('<https://example.org/test3>', '<http://example.org/hasBlankNode>', '_:b2');

-- Attempt to delete by blank node (may not work due to blank node semantics)
DELETE FROM ft WHERE object = '_:b1'::rdfnode;
SELECT * FROM ft WHERE subject = '<https://example.org/test3>';

/* Test 4: DELETE non-existent triple (should succeed silently) */
DELETE FROM ft WHERE subject = '<https://example.org/does-not-exist>';
SELECT * FROM ft WHERE subject = '<https://example.org/does-not-exist>';

/* Test 5: DELETE with NULL values in the result set 
   This should trigger DELETE WHERE instead of DELETE DATA */
-- First, let's insert some triples with a pattern that might include NULLs
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://example.org/test5>', '<http://example.org/prop1>', '"value1"'),
  ('<https://example.org/test5>', '<http://example.org/prop2>', '"value2"');

-- This delete should work normally (no NULLs expected)
DELETE FROM ft WHERE subject = '<https://example.org/test5>';
SELECT * FROM ft WHERE subject = '<https://example.org/test5>';

/* Test 6: DELETE with special characters in literals */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://example.org/test6>', '<http://example.org/text>', '"Line 1\nLine 2"'),
  ('<https://example.org/test6>', '<http://example.org/text>', '"Tab\tseparated"'),
  ('<https://example.org/test6>', '<http://example.org/text>', '"Quote: \"Hello\""');

DELETE FROM ft WHERE subject = '<https://example.org/test6>';
SELECT * FROM ft WHERE subject = '<https://example.org/test6>';

/* Test 7: DELETE with URI special characters */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://example.org/test7#fragment>', '<http://example.org/prop>', '"value"'),
  ('<https://example.org/test7?param=1>', '<http://example.org/prop>', '"value"'),
  ('<https://example.org/test7/path/to/resource>', '<http://example.org/prop>', '"value"');

DELETE FROM ft WHERE predicate = '<http://example.org/prop>';
SELECT * FROM ft WHERE predicate = '<http://example.org/prop>';

/* Test 8: DELETE with empty string literal */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://example.org/test8>', '<http://example.org/emptyString>', '""');

DELETE FROM ft WHERE object = '""'::rdfnode;
SELECT * FROM ft WHERE subject = '<https://example.org/test8>';

/* Test 9: DELETE with very long literal (stress test) */
INSERT INTO ft (subject, predicate, object)
SELECT
  '<https://example.org/test9>',
  '<http://example.org/longText>',
  ('"' || repeat('A', i * 100) || '"')::rdfnode
FROM generate_series(1, 5) AS i;

DELETE FROM ft WHERE subject = '<https://example.org/test9>';
SELECT count(*) FROM ft WHERE subject = '<https://example.org/test9>';

/* Test 10: DELETE with multiple predicates (same subject) */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://example.org/test10>', '<http://xmlns.com/foaf/0.1/name>', '"John Doe"'),
  ('<https://example.org/test10>', '<http://xmlns.com/foaf/0.1/age>', '30'::rdfnode),
  ('<https://example.org/test10>', '<http://xmlns.com/foaf/0.1/email>', '"john@example.org"');

-- Delete only age property
DELETE FROM ft WHERE subject = '<https://example.org/test10>' AND predicate = '<http://xmlns.com/foaf/0.1/age>';
SELECT * FROM ft WHERE subject = '<https://example.org/test10>';

/* Test 11: DELETE with negative numbers and scientific notation */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://example.org/test11>', '<http://example.org/number>', '"-42"^^<http://www.w3.org/2001/XMLSchema#int>'),
  ('<https://example.org/test11>', '<http://example.org/number>', '"1.23e-4"^^<http://www.w3.org/2001/XMLSchema#double>');

DELETE FROM ft WHERE subject = '<https://example.org/test11>';
SELECT * FROM ft WHERE subject = '<https://example.org/test11>';

/* Test 12: Verify nothing was accidentally deleted */
SELECT count(*) as remaining_triples FROM ft;

/* Cleanup */
DROP SERVER fuseki CASCADE;
