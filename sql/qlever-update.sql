\pset null '(null)'

CREATE SERVER qlever
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint   'http://qlever:7001/sparql',
  update_url 'http://qlever:7001/update');

CREATE USER MAPPING FOR postgres
SERVER qlever OPTIONS (token 'secret');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER qlever OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * WHERE {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .'
);

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

/* update to xsd:string literal (per RDF 1.1, xsd:string is equivalent to a plain literal;
   both QLever and GraphDB return it without the ^^xsd:string datatype annotation) */
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

/* update to xsd:long literal
   Note: QLever normalizes all XSD integer subtypes (xsd:short, xsd:long, etc.) to xsd:int
   internally, so the value is returned as "423712345678911"^^xsd:int even though it was
   inserted as xsd:long and exceeds xsd:int's maximum value (2,147,483,647). */
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

/* invalid credentials test */
ALTER USER MAPPING FOR postgres
SERVER qlever OPTIONS (SET token 'wrongtoken'); -- wrong token

UPDATE ft SET
  object = '"University of Münster"@en'
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';

ALTER USER MAPPING FOR postgres
SERVER qlever OPTIONS (SET token 'secret'); -- restore correct token

/* read-only server: blocks UPDATE regardless of triple pattern */
ALTER SERVER qlever OPTIONS (ADD readonly 'true');
UPDATE ft SET object = '"foo"@en';

/* table overrides server: server is readonly but table explicitly sets readonly=false */
ALTER FOREIGN TABLE ft OPTIONS (ADD readonly 'false');
UPDATE ft SET object = '"foo"@en'; -- succeeds: table override allows writes
SELECT * FROM ft WHERE subject = '<https://www.uni-muenster.de>';
ALTER FOREIGN TABLE ft OPTIONS (DROP readonly);

/* read-only foreign table: server is writable, table explicitly read-only */
ALTER SERVER qlever OPTIONS (SET readonly 'false');
ALTER FOREIGN TABLE ft OPTIONS (ADD readonly 'true');
UPDATE ft SET object = '"foo"@en';

/* read-write server and foreign table, but no triple pattern */
ALTER SERVER qlever OPTIONS (DROP readonly);
ALTER FOREIGN TABLE ft OPTIONS (DROP readonly);
ALTER FOREIGN TABLE ft OPTIONS (DROP sparql_update_pattern);
UPDATE ft SET object = '"foo"@en';

/* invalid triple patterns */
ALTER FOREIGN TABLE ft OPTIONS (ADD sparql_update_pattern '?s ?p .'); -- missing object variable
UPDATE ft SET object = '"foo"@en';
ALTER FOREIGN TABLE ft OPTIONS (SET sparql_update_pattern ''); -- empty pattern
UPDATE ft SET object = '"foo"@en';

/* cleanup */
ALTER FOREIGN TABLE ft OPTIONS (SET sparql_update_pattern '?s ?p ?o .'); -- restore correct pattern
UPDATE ft SET object = '"updated"'::rdfnode WHERE subject IN (SELECT subject FROM ft WHERE predicate = '<http://foo.bar>');
UPDATE ft SET object = '"updated"'::rdfnode WHERE subject IN (SELECT subject FROM ft WHERE predicate <> '<http://foo.bar>');
DELETE FROM ft;
DROP SERVER qlever CASCADE;