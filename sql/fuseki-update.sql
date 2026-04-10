\pset null '(null)'

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

/* invalid credentials test */
ALTER USER MAPPING FOR postgres
SERVER fuseki OPTIONS (SET user 'admin', SET password 'foo'); -- wrong password

UPDATE ft SET
  object = '"University of Münster"@en'
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';

ALTER USER MAPPING FOR postgres
SERVER fuseki OPTIONS (SET user 'admin', SET password 'secret'); -- restore correct password

/* read-only server: blocks UPDATE regardless of triple pattern */
ALTER SERVER fuseki OPTIONS (ADD readonly 'true');
UPDATE ft SET object = '"foo"@en';

/* table overrides server: server is readonly but table explicitly sets readonly=false */
ALTER FOREIGN TABLE ft OPTIONS (ADD readonly 'false');
UPDATE ft SET object = '"foo"@en'; -- succeeds: table override allows writes
SELECT * FROM ft WHERE subject = '<https://www.uni-muenster.de>';
ALTER FOREIGN TABLE ft OPTIONS (DROP readonly);

/* read-only foreign table: server is writable, table explicitly read-only */
ALTER SERVER fuseki OPTIONS (SET readonly 'false');
ALTER FOREIGN TABLE ft OPTIONS (ADD readonly 'true');
UPDATE ft SET object = '"foo"@en';

/* read-write server and foreign table, but no triple pattern */
ALTER SERVER fuseki OPTIONS (DROP readonly);
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
DELETE FROM ft;
DROP SERVER fuseki CASCADE;