CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://query.wikidata.org/sparql');

/*
 * Humans born in New York City
 * Author: Wikidata (https://www.wikidata.org/wiki/Wikidata:SPARQL_query_service/queries/examples#Humans_born_in_New_York_City)
 * 
 * This example highlights the correct way to use the place of birth (P19) property, and by extension the place of death (P20) property. 
 * Place of birth (P19) is the most specific known place of birth. For example, it is known that Donald Trump (Donald Trump (Q22686)) was 
 * born in the Jamaica Hospital (Jamaica Hospital Medical Center (Q23497866)) in New York City. Therefore, he wouldn't show up in direct 
 * query for humans born in New York City. 
 */

CREATE FOREIGN TABLE born_in_ny (
  wikidata_id text  OPTIONS (variable '?item'),
  name text         OPTIONS (variable '?itemLabel'),
  description text  OPTIONS (variable '?itemDescription'),
  nlinks int         OPTIONS (variable '?sitelinks')
)
SERVER wikidata OPTIONS (
  log_sparql 'true',
  sparql '
    SELECT DISTINCT ?item ?itemLabel ?itemDescription ?sitelinks
    WHERE {
        ?item wdt:P31 wd:Q5;          # Any instance of a human
            wdt:P19/wdt:P131* wd:Q60; # Who was born in any value (eg. a hospital)
            wikibase:sitelinks ?sitelinks.
        SERVICE wikibase:label { bd:serviceParam wikibase:language "[AUTO_LANGUAGE],en" }
    }
');  

/* As of Dec 2023 this query will return ~34k records */
SELECT name, description, nlinks
FROM born_in_ny
ORDER BY nlinks DESC;