
CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://query.wikidata.org/sparql');

/*
 * Descendants of Bach 
 *
 * Source: Wikidata [https://m.wikidata.org/wiki/Wikidata:SPARQL_query_service/queries/examples/human]
 */
CREATE FOREIGN TABLE bach_descendants (
  uri         rdfnode OPTIONS (variable '?human'),
  name        rdfnode OPTIONS (variable '?humanLabel'),
  father      rdfnode OPTIONS (variable '?fatherLabel'),
  mother      rdfnode OPTIONS (variable '?motherLabel'),
  birth       rdfnode OPTIONS (variable '?dob'),
  place_birth rdfnode OPTIONS (variable '?pobLabel')
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

SELECT uri, sparql.lex(name) AS name, sparql.lex(father) AS father, 
       sparql.lex(mother) AS mother, sparql.lex(birth) AS birth, 
       sparql.lex(place_birth) AS place_birth
FROM bach_descendants
ORDER BY birth;