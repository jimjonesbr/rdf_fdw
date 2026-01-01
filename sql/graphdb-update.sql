\pset null '(null)'

CREATE SERVER graphdb
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint   'http://graphdb:7200/repositories/test',
  update_url 'http://graphdb:7200/repositories/test/statements');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER graphdb OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * WHERE {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .'
);

CREATE USER MAPPING FOR postgres
SERVER graphdb OPTIONS (user 'admin', password 'secret');

INSERT INTO ft (subject, predicate, object)
VALUES  ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', '"Westfälische Wilhelms-Universität Münster"@de');

SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

UPDATE ft SET
  object = '"University of Münster"@en'
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';

SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

UPDATE ft 
SET object = '""'::rdfnode
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

UPDATE ft 
SET object = '🐘'::rdfnode
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

/* update using existing column */
UPDATE ft 
SET object = predicate
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

/* update literals with quotes */
UPDATE ft 
SET object = '"\"text with quotes\""'::rdfnode
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

/* update literals containing newlines */
UPDATE ft 
SET object = '"text \n newline"'::rdfnode
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

/* update to xsd:string literal (graphdb might omit xsd:string datatype) */
UPDATE ft 
SET object = '"text xsd string"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

/* update to xsd:int literal */
UPDATE ft 
SET object = 42::rdfnode
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

/* update to xsd:decimal literal */
UPDATE ft 
SET object = 42.37::rdfnode
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

/* update to xsd:long literal */
UPDATE ft 
SET object = 423712345678911::rdfnode
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

/* update with NULL - must fail (after SELECT since FDW must fetch OLD values first) */
UPDATE ft 
SET object = NULL
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

/* update rdfnode with a blank node */
UPDATE ft 
SET object = sparql.bnode()
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';

/* update with RETURNING */
UPDATE ft SET
  object = '"Westfälische Wilhelms-Universität Münster"@de'
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>'
RETURNING OLD.subject, OLD.predicate, OLD.object,
          NEW.subject AS new_subject, NEW.predicate AS new_predicate, NEW.object AS new_object;

/* cleanup */
DELETE FROM ft;
DROP SERVER graphdb CASCADE;