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

/* bulk INSERT triples */
INSERT INTO ft (subject, predicate, object)
SELECT
  sparql.iri('<https://www.uni-muenster.de/rdf_fdw/delete-test>'),
  sparql.iri('http://www.w3.org/1999/02/22-rdf-syntax-ns#value'),
  i::rdfnode
FROM generate_series(1,10) AS j (i);

/* DELETE single triple */
DELETE FROM ft WHERE object = 8::rdfnode;
SELECT * FROM ft WHERE object = 8::rdfnode;

/* DELETE range of triples */
DELETE FROM ft WHERE object BETWEEN 2::rdfnode AND 5::rdfnode;
SELECT * FROM ft WHERE object BETWEEN 2::rdfnode AND 5::rdfnode;

/* DELETE triple with special character */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://www.uni-muenster.de/rdf_fdw/delete-test>',
  '<http://www.w3.org/2000/01/rdf-schema#comment>',
  '"🐘"@de');
DELETE FROM ft WHERE object = '"🐘"@de'::rdfnode;
SELECT * FROM ft WHERE object = '"🐘"@de'::rdfnode;

/* DELETE triple with empty literal */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://www.uni-muenster.de/rdf_fdw/delete-test>',
  '<http://www.w3.org/2000/01/rdf-schema#comment>',
  '""@pt');
DELETE FROM ft WHERE object = sparql.strlang('""', 'pt')::rdfnode;
SELECT * FROM ft WHERE object = sparql.strlang('""', 'pt')::rdfnode;

/* DELETE with compound WHERE condition */
DELETE FROM ft WHERE subject = '<https://www.uni-muenster.de/rdf_fdw/delete-test>'
  AND predicate = '<http://www.w3.org/1999/02/22-rdf-syntax-ns#value>'
  AND object = 10::rdfnode;
SELECT * FROM ft 
WHERE subject = '<https://www.uni-muenster.de/rdf_fdw/delete-test>'
  AND predicate = '<http://www.w3.org/1999/02/22-rdf-syntax-ns#value>'
  AND object = 10::rdfnode;

/* DELETE triple with typed literal */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://www.uni-muenster.de/rdf_fdw/delete-test>',
  '<http://www.w3.org/2000/01/rdf-schema#comment>',
  '"rdf_fdw"^^<http://www.w3.org/2001/XMLSchema#string>');
DELETE FROM ft WHERE object = sparql.strdt('rdf_fdw','<http://www.w3.org/2001/XMLSchema#string>');
SELECT * FROM ft WHERE object = sparql.strdt('rdf_fdw','<http://www.w3.org/2001/XMLSchema#string>');

/* DELETE triple with very long IRI */
INSERT INTO ft (subject, predicate, object) VALUES
  (('<https://przykład.pl/' || repeat('x', 1000) || '>')::rdfnode,
  '<http://www.w3.org/2000/01/rdf-schema#comment>',
  '"rdf_fdw"^^<http://www.w3.org/2001/XMLSchema#string>');
DELETE FROM ft WHERE subject = ('<https://przykład.pl/' || repeat('x', 1000) || '>')::rdfnode;
SELECT * FROM ft WHERE subject = ('<https://przykład.pl/' || repeat('x', 1000) || '>')::rdfnode;

/* DELETE non-existent triple (should succeed silently with DELETE 0) */
DELETE FROM ft WHERE object = 'foo'::rdfnode;

/* DELETE with literals containing escaped quotes */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://www.uni-muenster.de/rdf_fdw/delete-test>',
  '<http://www.w3.org/2000/01/rdf-schema#comment>',
  '"\"WWU\""@en');
DELETE FROM ft WHERE object = '"\"WWU\""@en'::rdfnode;
SELECT * FROM ft WHERE object = '"\"WWU\""@en'::rdfnode;

/* DELETE with literals containing newline */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://www.uni-muenster.de/rdf_fdw/delete-test>',
  '<http://www.w3.org/2000/01/rdf-schema#comment>',
  E'"Line1\nLine2"@en');
DELETE FROM ft WHERE object = E'"Line1\nLine2"@en'::rdfnode;
SELECT * FROM ft WHERE object = E'"Line1\nLine2"@en'::rdfnode;

/* DELETE triple with RETURNING */
INSERT INTO ft (subject, predicate, object) VALUES
  ('<https://www.uni-muenster.de/rdf_fdw/delete-test>',
  '<http://www.w3.org/2000/01/rdf-schema#comment>',
  '"🐘"@de');
DELETE FROM ft WHERE object = '"🐘"@de'::rdfnode
RETURNING OLD.subject, OLD.predicate, OLD.object;

/* bulk DELETE all inserted triples */
SELECT count(*) FROM ft;
DELETE FROM ft;
SELECT count(*) FROM ft;

DROP SERVER fuseki CASCADE;