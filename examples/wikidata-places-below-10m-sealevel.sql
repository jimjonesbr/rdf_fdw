CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://query.wikidata.org/sparql');

/*
 * Places that are below 10 meters above sea level
 * Items used: metre (Q11573)
 * Properties used: elevation above sea level (P2044) 
 *
 * Source: Wikidata (https://www.wikidata.org/wiki/Wikidata:SPARQL_query_service/queries/examples#Places_that_are_below_10_meters_above_sea_level)
 */

CREATE FOREIGN TABLE places_below_sea_level (
  wikidata_id rdfnode OPTIONS (variable '?place'),
  label       rdfnode OPTIONS (variable '?label'),
  wkt         rdfnode OPTIONS (variable '?location'),
  elevation   rdfnode OPTIONS (variable '?elev')
)
SERVER wikidata OPTIONS (
  log_sparql 'true',
  sparql '
  SELECT * WHERE
    {
      ?place rdfs:label ?label .
      ?place p:P2044/psv:P2044 ?placeElev.
      ?placeElev wikibase:quantityAmount ?elev.
      ?placeElev wikibase:quantityUnit ?unit.
      BIND(0.01 as ?km).
      ?place wdt:P625 ?location.    
      SERVICE wikibase:label { bd:serviceParam wikibase:language "[AUTO_LANGUAGE],en" }
      FILTER( (?elev < ?km*1000 && ?unit = wd:Q11573)
          || (?elev < ?km*3281 && ?unit = wd:Q3710)
          || (?elev < ?km      && ?unit = wd:Q828224) ).
    }
');  

SELECT wikidata_id, label, wkt
FROM places_below_sea_level
WHERE sparql.lang(label) = 'en'
FETCH FIRST 10 ROWS ONLY;
