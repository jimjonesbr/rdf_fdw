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
  log_sparql 'false',
  sparql 
    $$
     SELECT * 
     WHERE {?s ?p ?o .}
    $$,
  sparql_update_pattern '?s ?p ?o .'
);

CREATE USER MAPPING FOR postgres
SERVER fuseki OPTIONS (user 'admin', password 'secret');

/* inserting a large literal (100k characters) */
INSERT INTO ft (subject, predicate, object)
VALUES  ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', repeat('x', 100000)::rdfnode);

SELECT subject, predicate, sparql.strlen(object) 
FROM ft;

SELECT subject, predicate, sparql.strlen(object) 
FROM ft;

/* updating the large literal (100k characters) */
UPDATE ft SET
  object = repeat('y', 100000)::rdfnode
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';

/* deleting triple with large literal */
DELETE FROM ft;

/* inserting a 100k triples */
INSERT INTO ft (subject, predicate, object)
SELECT '<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', i::rdfnode 
FROM generate_series(1,100000) AS g(i);

SELECT * FROM ft
LIMIT 5;

/* deleting 100k triples */
DELETE FROM ft;

SELECT * FROM ft;

DROP SERVER fuseki CASCADE;