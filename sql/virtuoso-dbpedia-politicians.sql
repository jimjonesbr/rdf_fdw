-- SET client_min_messages = DEBUG1;

CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://dbpedia.org/sparql',
  format 'application/sparql-results+xml',
  enable_pushdown 'true'
);



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
    WHERE
      {
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
 * DISTINCT and WHERE clause will be pushed down.
 * LIMIT won't be pushed down, as the SQL contains ORDER BY
 */
SELECT DISTINCT 
  name, 
  birthdate,  
  party, 
  country
FROM politicians
WHERE country = 'Germany'
ORDER BY birthdate DESC, party ASC
LIMIT 10;


/*
 * DISTINCT ON won't be pushed - SPARQL does not support it.
 * WHERE clause will be pushed down.
 * LIMIT won't be pushed down, as the SQL contains ORDER BY
 */
SELECT DISTINCT ON (birthdate)
  name, 
  birthdate, 
  party, 
  country
FROM politicians
WHERE country = 'Germany'
ORDER BY birthdate
LIMIT 3;


/* ################### SPARQL  Aggregators ################### */

CREATE FOREIGN TABLE party_members (
  country text  OPTIONS (variable '?country'),
  party text    OPTIONS (variable '?partyname'),
  nmembers int  OPTIONS (variable '?qt')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>
    
    SELECT ?country ?partyname COUNT(?person) AS ?qt 
    WHERE
    {
      ?person 
        a dbo:Politician ;
          dbo:party ?party .
        ?party 
          dbp:country ?country ;
          dbp:name ?partyname .
      FILTER NOT EXISTS {?person dbo:deathDate ?died}      
  }
  GROUP BY ?country ?partyname
  ORDER BY DESC (?qt)
'); 


/*
 * All filters (WHERE, FETCH and ILIKE) will be applied locally,
 * as the raw SPARQL cannot be parsed - it contains aggregators.
 */
SELECT party, nmembers 
FROM party_members
WHERE country ~~* '%isle of man%'
ORDER BY nmembers ASC
FETCH FIRST 5 ROWS ONLY;


/* ################### SPARQL UNION ################### */

CREATE FOREIGN TABLE chanceler_candidates (
  name text  OPTIONS (variable '?name'),
  party text    OPTIONS (variable '?partyname'),
  birthdate date  OPTIONS (variable '?birthdate')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>
    
    SELECT ?name ?partyname ?birthdate
    WHERE {
       ?person rdfs:label ?name
       { ?person rdfs:label "Friedrich Merz"@de }      
       UNION
       { ?person rdfs:label "Markus Söder"@de }            
       ?person dbo:birthDate ?birthdate .
       ?person dbo:party ?party .
       ?party dbp:name ?partyname 
      FILTER(LANG(?name) = "de") 
    } 
'); 


/*
 * All filters (WHERE and ORDER BY) will be applied locally,
 * as the raw SPARQL cannot be parsed - it contains UNION.
 */
SELECT name, party, birthdate
FROM chanceler_candidates
WHERE party <> ''
ORDER BY birthdate DESC;