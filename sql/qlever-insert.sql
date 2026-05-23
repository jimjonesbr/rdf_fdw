\pset null '(null)'

SELECT sparql.add_context('testctx', 'test context');
SELECT sparql.add_prefix('testctx', 'rdf', 'http://www.w3.org/2000/01/rdf-schema#');

CREATE SERVER qlever
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'http://qlever:7001/update', -- this tests if the regular endpoint is used for updates
  prefix_context 'testctx',
  batch_size '5'); 

CREATE USER MAPPING FOR postgres
SERVER qlever OPTIONS (token 'secret');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  foo       rdfnode OPTIONS (variable '?foo'), -- will be ignored
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER qlever OPTIONS (
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
ALTER SERVER qlever OPTIONS (ADD update_url 'http://qlever:7001/update',
                             SET endpoint 'http://qlever:7001/sparql');

SELECT subject, predicate, object FROM ft
WHERE subject = '<https://www.uni-muenster.de>'
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

/* insert with RETURNING */
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', '"Universidade de Münster"@pt')
RETURNING *;

/*
 * Here we transfer data from a local static graph into a destination named
 * graph in qlever. This exercises the cross-FDW INSERT-SELECT code path
 * without depending on any external network service.
 *
 * The source graph <http://rdf-fdw.test/wikidata-static> is pre-loaded with
 * a fixed snapshot of Wikidata altLabel data for Q192490 (PostgreSQL).
 */

/* Load static source data into a local named graph */
CREATE FOREIGN TABLE rdbms_static (
  s rdfnode OPTIONS (variable '?s'),
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER qlever OPTIONS (
  log_sparql 'false',
  sparql 'SELECT * { GRAPH <http://rdf-fdw.test/wikidata-static> {?s ?p ?o} }',
  sparql_update_pattern 'GRAPH <http://rdf-fdw.test/wikidata-static> { ?s ?p ?o . }'
);

INSERT INTO rdbms_static (s, p, o) VALUES
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"PG"@zh-CN'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"POSTGRE SQL"@vi'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"PgSQL"@pl'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"Postgre SQL"@sr'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"Postgre"@pl'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"Postgre"@sr'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"PostgreSQL project"@de'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"PostgreSQL, слободни софтвер"@sr'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"Postgres"@mul'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"Postgresql"@sr'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"pgsql"@pt-BR'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"postgres"@nl'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"پست گر اس کیوال"@fa'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"پستگر اسکیوال"@fa'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"পোস্টজিআরই"@bn'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"போசுகிரசு"@ta'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"โพสต์เกรส"@th'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"ポスグレ"@ja'),
  ('<http://www.wikidata.org/entity/Q192490>', '<http://www.w3.org/2004/02/skos/core#altLabel>', '"ポストグレスキューエル"@ja');

/* Read from the static local graph — same code path as reading from a remote endpoint */
CREATE FOREIGN TABLE rdbms_wikidata (
  s rdfnode OPTIONS (variable '?s'),
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER qlever OPTIONS (
  log_sparql 'false',
  sparql $$
    SELECT * {
      GRAPH <http://rdf-fdw.test/wikidata-static> {
        ?s ?p ?o .
        FILTER(?s=<http://www.wikidata.org/entity/Q192490>)
        FILTER(?p=<http://www.w3.org/2004/02/skos/core#altLabel>)
      }
    }
  $$
);

CREATE FOREIGN TABLE rdbms_qlever (
  s rdfnode OPTIONS (variable '?s'),
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER qlever OPTIONS (
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

INSERT INTO rdbms_qlever (s, p, o)
SELECT s, p, o FROM rdbms_wikidata;

SELECT * FROM rdbms_qlever 
ORDER BY o::text COLLATE "C";

COPY (
  SELECT s, p , o
  FROM rdbms_qlever 
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
ALTER SERVER qlever OPTIONS (SET update_url 'foo');
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

/* invalid triple pattern - no sparql_update_pattern OPTION */
ALTER SERVER qlever OPTIONS (SET update_url 'http://qlever:7001/update',
                             SET endpoint 'http://qlever:7001/sparql');
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

/* invalid value - blank node */
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', sparql.bnode());

/* invalid credentials test */
ALTER USER MAPPING FOR postgres
SERVER qlever OPTIONS (SET token 'bad_token'); -- wrong token

INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', '"foo"@de');

ALTER USER MAPPING FOR postgres
SERVER qlever OPTIONS (SET token 'secret'); -- restore correct token

/* read-only server: blocks INSERT regardless of triple pattern */
ALTER SERVER qlever OPTIONS (ADD readonly 'true');
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

/* table overrides server: server is readonly but table explicitly sets readonly=false */
ALTER FOREIGN TABLE ft OPTIONS (ADD readonly 'false');
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', '"foo"@en'); -- succeeds: table override allows writes
SELECT * FROM ft WHERE object = '"foo"@en';
ALTER FOREIGN TABLE ft OPTIONS (DROP readonly);

/* read-only foreign table: server is writable, table explicitly read-only */
ALTER SERVER qlever OPTIONS (SET readonly 'false');
ALTER FOREIGN TABLE ft OPTIONS (ADD readonly 'true');
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

/* read-write server and foreign table, but no triple pattern */
ALTER SERVER qlever OPTIONS (DROP readonly);
ALTER FOREIGN TABLE ft OPTIONS (DROP readonly);
ALTER FOREIGN TABLE ft OPTIONS (DROP sparql_update_pattern);
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

/* invalid triple patterns */
ALTER FOREIGN TABLE ft OPTIONS (ADD sparql_update_pattern '?s ?p .'); -- missing object variable
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');
ALTER FOREIGN TABLE ft OPTIONS (SET sparql_update_pattern ''); -- empty pattern
INSERT INTO ft (subject, predicate, object) VALUES
('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');

/* invalid data type */
ALTER FOREIGN TABLE ft OPTIONS (SET sparql_update_pattern '?s ?p ?o .'); -- restore correct pattern
ALTER FOREIGN TABLE ft ALTER COLUMN predicate TYPE text;
-- should fail, predicate column is now text, not rdfnode
INSERT INTO ft (subject, predicate, object) VALUES ('<https://www.uni-muenster.de>', '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>', 'http://dbpedia.org/resource/University');
ALTER FOREIGN TABLE ft ALTER COLUMN predicate TYPE rdfnode;

/* cleanup */
DELETE FROM ft;
DELETE FROM rdbms_qlever;    -- clear <http://www.uni-muenster.de/graph>
DELETE FROM rdbms_static;    -- clear <http://rdf-fdw.test/wikidata-static>
SELECT sparql.drop_context('testctx', true);
DROP SERVER qlever CASCADE;