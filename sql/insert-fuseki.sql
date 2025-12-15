SELECT sparql.add_context('testctx', 'test context');
SELECT sparql.add_prefix('testctx', 'rdf', 'http://www.w3.org/2000/01/rdf-schema#');

CREATE SERVER fuseki
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'http://fuseki:3030/dt/update', -- this tests if the regular endpoint is used for updates
  prefix_context 'testctx'); 

CREATE USER MAPPING FOR postgres
SERVER fuseki OPTIONS (user 'admin', password 'secret');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  foo       rdfnode OPTIONS (variable '?foo'), -- will be ignored
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER fuseki OPTIONS (
  log_sparql 'false',
  sparql 'SELECT * {?s ?p ?o}',
  sparql_update_pattern 
    '?s ?p ?o .
     ?s rdf:comment "added via rdf_fdw 🐘"^^<http://www.w3.org/2001/XMLSchema#string>.'
  );

INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University'),
('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', ''),
('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', '""'),
('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', '""@es'),
('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', '"University of Münster"@en'),
('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', '"Westfälische \"Wilhelms-Universität\" Münster"@de'),
('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', '"Westfälische \nWilhelms-Universität\n Münster"@de'),
('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', '"Westfälische .. Wilhelms-Universität . Münster"@de'),
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#seeAlso>', '🐘'::rdfnode);

/* Set the endpoint to the right URL and add update_url */
ALTER SERVER fuseki OPTIONS (ADD update_url 'http://fuseki:3030/dt/update',
                             SET endpoint 'http://fuseki:3030/dt/sparql');

SELECT subject, predicate, object FROM ft
ORDER BY predicate, object::text COLLATE "C";

/* Test DEFAULT values handling */
ALTER FOREIGN TABLE ft ALTER COLUMN object SET DEFAULT '"default literal"'::rdfnode;
INSERT INTO ft (subject, predicate) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#altLabel>');
SELECT subject, predicate, object FROM ft 
WHERE predicate = '<http://www.w3.org/2000/01/rdf-schema#altLabel>';
ALTER FOREIGN TABLE ft ALTER COLUMN object DROP DEFAULT;

/* insert large literal */
ALTER FOREIGN TABLE ft OPTIONS (SET log_sparql 'false'); -- disable logging to not flood the ouput file
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#altLabel>', repeat('b', 1000000)::rdfnode);

SELECT subject, predicate, sparql.strlen(object)
FROM ft WHERE predicate = '<http://www.w3.org/2000/01/rdf-schema#altLabel>';

/* bulk insert */
INSERT INTO ft (subject, predicate, object)
SELECT
  sparql.iri('https://www.uni-muenster.de'),
  sparql.iri('http://www.w3.org/1999/02/22-rdf-syntax-ns#value'),
  i::rdfnode
FROM generate_series(1,100) AS j (i);

SELECT count(*) FROM ft;

/* 
 * Here we transfer data from Wikidata to Fuseki. 
 * The NAMED GRAPH is manually specified in the sparql
 * and sparql_update_pattern options. Fuseki will then
 * create the graph in query time, if it does not exist.
 */
CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://query.wikidata.org/sparql');

CREATE FOREIGN TABLE rdbms_wikidata (
  s rdfnode OPTIONS (variable '?s'),
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER wikidata OPTIONS (
  log_sparql 'false',
  sparql $$
    SELECT * {?s ?p ?o .
    FILTER(?s=<http://www.wikidata.org/entity/Q192490>)
    FILTER(?p=<http://www.w3.org/2004/02/skos/core#altLabel>)}
  $$
  );

CREATE FOREIGN TABLE rdbms_fuseki (
  s rdfnode OPTIONS (variable '?s'),
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER fuseki OPTIONS (
  log_sparql 'true',
  sparql $$
    SELECT * {
      GRAPH <http://www.uni-muenster.de/graph> {
        ?s ?p ?o .    
      FILTER(?s=<http://www.wikidata.org/entity/Q192490>)
      FILTER(?p=<http://www.w3.org/2004/02/skos/core#altLabel>)
      }
    }
    $$,
  sparql_update_pattern $$
    GRAPH <http://www.uni-muenster.de/graph> {
      ?s ?p ?o .
    }
  $$);

INSERT INTO rdbms_fuseki (s, p, o)
SELECT s, p, o FROM rdbms_wikidata;

SELECT * FROM rdbms_fuseki 
ORDER BY o::text COLLATE "C";

COPY (
  SELECT s, p , o
  FROM rdbms_fuseki 
  ORDER BY o::text COLLATE "C"
) TO STDOUT DELIMITER E' ';

/*** Exception tests ***/

/* COPY .. FROM must fail - not supported */
COPY ft (subject, predicate, object) FROM STDIN WITH (DELIMITER ' ');
<https://www.uni-muenster.de> <http://www.w3.org/1999/02/22-rdf-syntax-ns#value> "42"^^<http://www.w3.org/2001/XMLSchema#int>
<https://www.uni-muenster.de> <http://www.w3.org/1999/02/22-rdf-syntax-ns#value> "37"^^<http://www.w3.org/2001/XMLSchema#int>
\.

/* INSERT must fail - all columns must be of type rdfnode */
ALTER FOREIGN TABLE ft ALTER COLUMN predicate TYPE text;
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');
ALTER FOREIGN TABLE ft ALTER COLUMN predicate TYPE rdfnode;

/* INSERT must fail - no column with the variable ?p */
ALTER FOREIGN TABLE ft ALTER COLUMN predicate OPTIONS (SET variable '?bar');
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

/* ALTER COLUMN must fail - variable is required */
ALTER FOREIGN TABLE ft ALTER COLUMN predicate OPTIONS (DROP variable);
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

\set VERBOSITY terse
/* invalid sparql_update_pattern - no triple pattern */
ALTER FOREIGN TABLE ft ALTER COLUMN predicate OPTIONS (SET variable '?p');
ALTER FOREIGN TABLE ft OPTIONS (SET sparql_update_pattern '?s ?o .');
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

/* invalid sparql_update_pattern - no variable */
ALTER FOREIGN TABLE ft OPTIONS (SET sparql_update_pattern 'foo .');
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

/* invalid update_url - no URL */
ALTER FOREIGN TABLE ft OPTIONS (SET sparql_update_pattern '?s ?p o .');
ALTER SERVER fuseki OPTIONS (SET update_url 'foo');
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

/* invalid triple pattern - no sparql_update_pattern OPTION */
ALTER SERVER fuseki OPTIONS (SET update_url 'http://fuseki:3030/dt/update',
                             SET endpoint 'http://fuseki:3030/dt/sparql');
ALTER FOREIGN TABLE ft OPTIONS (DROP sparql_update_pattern);
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

/* invalid triple pattern - empty sparql_update_pattern OPTION */
ALTER FOREIGN TABLE ft OPTIONS (ADD sparql_update_pattern ' ');
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

/* invalid value - NULL value */
ALTER FOREIGN TABLE ft OPTIONS (SET sparql_update_pattern '?s ?p ?o .');
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', NULL);

/* cleanup */
DELETE FROM ft;
DROP SERVER fuseki CASCADE;
DROP SERVER wikidata CASCADE;