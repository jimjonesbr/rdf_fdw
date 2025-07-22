SET timezone TO 'Etc/UTC';

SELECT sparql.add_context('testctx', 'test context');
SELECT sparql.add_prefix('testctx', 'foo', 'http://example.org/foo#');
SELECT sparql.add_prefix('testctx', 'bar', 'http://example.org/bar#');

CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://query.wikidata.org/sparql',
  prefix_context 'testctx');

CREATE FOREIGN TABLE rdbms (
  p rdfnode OPTIONS (variable '?l'),
  o rdfnode OPTIONS (variable '?cr')
)
SERVER wikidata OPTIONS (
  log_sparql 'true',
  sparql '
  prefix wd: <http://www.wikidata.org/entity/>   PreFiX skos:         <http://www.w3.org/2004/02/skos/core#>

PREFIX        wdt: <http://www.wikidata.org/prop/direct/>


SELECT * {
  ?s skos:altLabel ?l .
  ?s wdt:P6216 ?cr
  FILTER (?s = wd:Q192490)
  FILTER (LANG(?l) ="en")
}');

-- Prefixes configured in the default context added
-- and existing prefixes formatted
SELECT p, o FROM rdbms ORDER BY p::text COLLATE "C";

ALTER SERVER wikidata OPTIONS (SET prefix_context 'foo');
-- Prefix context does not exist. Issuing a WARNING.
SELECT p, o FROM rdbms ORDER BY p::text COLLATE "C";

-- No prefix context set. Using only prefixes from the
-- SPARQL query.
ALTER SERVER wikidata OPTIONS (DROP prefix_context);
SELECT p, o FROM rdbms ORDER BY p::text COLLATE "C";

\set VERBOSITY terse
-- Add existing context and prefix (must fail)
SELECT sparql.add_context('testctx', 'test context');
SELECT sparql.add_prefix('testctx', 'foo', 'http://example.org/foo#');

-- Add existing context and prefix forcing overwrite
SELECT sparql.add_context('testctx', 'test context - updated', true);
SELECT sparql.add_prefix('testctx', 'foo', 'http://example.org/foo-updated#', true);

-- Check the prefix context and prefixes
SELECT context, description FROM sparql.prefix_contexts ORDER BY context COLLATE "C";
SELECT context, prefix, uri FROM sparql.prefixes ORDER BY context, prefix COLLATE "C";

-- Drop prefix
SELECT sparql.drop_prefix('testctx', 'foo');
SELECT context, prefix, uri FROM sparql.prefixes WHERE context = 'testctx' ORDER BY prefix COLLATE "C";

-- Drop context forcing cascade
SELECT sparql.drop_context('testctx', true);

SELECT context, description FROM sparql.prefix_contexts ORDER BY context COLLATE "C";
SELECT context, prefix, uri FROM sparql.prefixes ORDER BY context, prefix COLLATE "C";

DROP SERVER wikidata CASCADE;