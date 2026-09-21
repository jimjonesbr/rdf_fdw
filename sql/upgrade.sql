DROP EXTENSION IF EXISTS rdf_fdw;
CREATE EXTENSION rdf_fdw VERSION '2.1';

SELECT extversion FROM pg_extension WHERE extname = 'rdf_fdw';

CREATE SERVER fs FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (endpoint 'http://example.com/sparql');

CREATE FOREIGN TABLE ft (
  s rdfnode OPTIONS (variable '?s'),
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
) SERVER fs OPTIONS 
  (sparql 'SELECT ?s ?p ?o WHERE { }');

ALTER EXTENSION rdf_fdw UPDATE TO '2.2';
SELECT extversion FROM pg_extension WHERE extname = 'rdf_fdw';

ALTER EXTENSION rdf_fdw UPDATE TO '2.3';
SELECT extversion FROM pg_extension WHERE extname = 'rdf_fdw';

ALTER EXTENSION rdf_fdw UPDATE TO '2.4';
SELECT extversion FROM pg_extension WHERE extname = 'rdf_fdw';

ALTER EXTENSION rdf_fdw UPDATE TO '2.5';
SELECT extversion FROM pg_extension WHERE extname = 'rdf_fdw';

ALTER EXTENSION rdf_fdw UPDATE TO '2.6';
SELECT extversion FROM pg_extension WHERE extname = 'rdf_fdw';

ALTER EXTENSION rdf_fdw UPDATE TO '2.7';
SELECT extversion FROM pg_extension WHERE extname = 'rdf_fdw';

/*
 * 2.8 replaces the rdfnode B-tree operator class, and replacing an operator
 * class does not rewrite what was built with it. An index keeps the order it
 * was written in, and a stored query keeps the ordering operator it was parsed
 * with; neither is reported, and both give wrong answers or unhelpful errors
 * afterwards. The upgrade refuses to run while either exists.
 */
CREATE TABLE upgrade_terms (term rdfnode);
CREATE INDEX upgrade_terms_term ON upgrade_terms (term);

/* refused: the index would keep an order the new class does not produce */
\set VERBOSITY terse
ALTER EXTENSION rdf_fdw UPDATE TO '3.0';

DROP INDEX upgrade_terms_term;
CREATE VIEW upgrade_sorted AS SELECT DISTINCT term FROM upgrade_terms;

/* refused: the view holds an ordering operator that is leaving the class */
ALTER EXTENSION rdf_fdw UPDATE TO '3.0';
\set VERBOSITY default

/* a stored query that only compares is not affected and does not refuse */
CREATE VIEW upgrade_filtered AS
  SELECT * FROM upgrade_terms WHERE term = '"1"^^xsd:integer'::rdfnode;
DROP VIEW upgrade_sorted;

ALTER EXTENSION rdf_fdw UPDATE TO '3.0';
SELECT extversion FROM pg_extension WHERE extname = 'rdf_fdw';

/* and that view still answers, with the operators it was parsed with */
INSERT INTO upgrade_terms VALUES ('"1"^^xsd:integer'), ('"01"^^xsd:integer');
SELECT count(*) AS rows_matched FROM upgrade_filtered;

DROP VIEW upgrade_filtered;
DROP TABLE upgrade_terms;
DROP SERVER fs CASCADE;
