CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

/*
 * Living politicians in DBpedia that are affiliated to a party. The party name must have
 * a german translation.
 * 
 * SPARQL author: Jim Jones
 */

CREATE FOREIGN TABLE politicians (
  uri text        OPTIONS (variable '?person'),
  name text       OPTIONS (variable '?personname'),
  birthdate date  OPTIONS (variable '?birthdate'),
  party text      OPTIONS (variable '?partyname'),
  country text    OPTIONS (variable '?country')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>

    SELECT *
    WHERE {
      ?person 
          a dbo:Politician;
          dbo:birthDate ?birthdate;
          dbp:name ?personname;
          dbo:party ?party .       
        ?party 
          dbp:country ?country;
          rdfs:label ?partyname .
        FILTER NOT EXISTS {?person dbo:deathDate ?died}
        FILTER(LANG(?partyname) = "de")
      } 
');

/* 
 * Select the 5 youngest politicians from Germany and France who were bortn after Dec 31st 1995.
 */

SELECT name, birthdate, party
FROM politicians
WHERE 
  country IN ('Germany','France') AND 
  birthdate > '1995-12-31' AND
  party <> ''
ORDER BY birthdate DESC, party ASC
FETCH FIRST 5 ROWS ONLY;
