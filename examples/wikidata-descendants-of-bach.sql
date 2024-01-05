
CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://query.wikidata.org/sparql');

/*
 * Descendants of Bach 
 *
 * Source: Wikidata [https://m.wikidata.org/wiki/Wikidata:SPARQL_query_service/queries/examples/human]
 */
CREATE FOREIGN TABLE bach_descendants (
  uri text           OPTIONS (variable '?human'),
  name text          OPTIONS (variable '?humanLabel'),
  father text        OPTIONS (variable '?fatherLabel'),
  mother text        OPTIONS (variable '?motherLabel'),
  birth date         OPTIONS (variable '?dob'),
  place_birth text   OPTIONS (variable '?pobLabel')
)
SERVER wikidata OPTIONS (
  log_sparql 'true',
  sparql '
  SELECT ?human ?humanLabel ?fatherLabel ?motherLabel ?dob ?pobLabel ?famLabel ?geni
  WHERE
    {
    wd:Q1339 wdt:P40/wdt:P40* ?human .
        ?human wdt:P31 wd:Q5 .      
        OPTIONAL{?human wdt:P22 ?father .}
        OPTIONAL{?human wdt:P25 ?mother .}
        OPTIONAL{?human wdt:P569 ?dob .}
        OPTIONAL{?human wdt:P19 ?pob .}
        OPTIONAL{?human wdt:P2600 ?geni .}
        OPTIONAL{?human wdt:P53 ?fam .}
    SERVICE wikibase:label { bd:serviceParam wikibase:language "[AUTO_LANGUAGE],en" }
    }
');

SELECT *
FROM bach_descendants
ORDER BY birth;