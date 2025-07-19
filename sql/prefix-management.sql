SET timezone TO 'Etc/UTC';

CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://query.wikidata.org/sparql',
  prefix_context 'default');

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
SELECT p, o FROM rdbms;

ALTER SERVER wikidata OPTIONS (SET prefix_context 'foo');
-- Prefix context does not exist. Issuing a WARNING.
SELECT p, o FROM rdbms;

-- No prefix context set. Using only prefixes from the
-- SPARQL query.
ALTER SERVER wikidata OPTIONS (DROP prefix_context);
SELECT p, o FROM rdbms;

DROP SERVER wikidata CASCADE;