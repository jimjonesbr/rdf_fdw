-- Example used in the PGConf.dev 2026 Poster
DROP SERVER IF EXISTS wikidata CASCADE;

CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://query.wikidata.org/sparql');

CREATE FOREIGN TABLE films (
  name    rdfnode OPTIONS (variable '?filmLabel'),
  cost    rdfnode OPTIONS (variable '?cost'),
  country rdfnode OPTIONS (variable '?ccode')
)
SERVER wikidata OPTIONS (
  sparql $$
    SELECT ?film ?filmLabel ?cost
    WHERE {
      ?film wdt:P31/wdt:P279* wd:Q11424 ; # film
        wdt:P2130 ?cost ;        # capital cost (USD)
        wdt:P136 wd:Q157443 ;    # genre comedy
        wdt:P1981 wd:Q20644796 ; # FSK 12        
        wdt:P495 ?c .
      ?c wdt:P297 ?ccode .       # country code
      SERVICE wikibase:label {
        bd:serviceParam wikibase:language "en" .
      }
    } $$
);

SELECT name FROM films
WHERE country = 'GB'::rdfnode AND
      cost BETWEEN 3500000 AND 4000000
ORDER BY name ASC, cost DESC
FETCH FIRST ROW ONLY;