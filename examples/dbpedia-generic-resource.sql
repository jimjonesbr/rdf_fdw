
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

/*
 * All non IRI property values directly linked to a given resource.
 * Only numeric literals or literals written in English are accepted.
 * 
 * SPARQL author: Jim Jones
 */
CREATE FOREIGN TABLE dbpedia_resource (
  uri text           OPTIONS (variable '?uri'),
  property_uri text  OPTIONS (variable '?propuri'),
  property text      OPTIONS (variable '?proplabel'),
  value text         OPTIONS (variable '?val')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX  rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  SELECT ?prop ?val
  WHERE {
    ?uri ?propuri ?val .
    ?propuri rdfs:label ?proplabel .
    FILTER(!isIRI(?val))
    FILTER(LANG(?val) = "en" || LANG(?val) = "")
    FILTER(LANG(?proplabel) = "en")
  } 
');

/*
 * Sir Edward Elgar (british composer)
 * Wikipedia Page   : https://en.wikipedia.org/wiki/Edward_Elgar
 * DBpedia resource : http://dbpedia.org/resource/Edward_Elgar 
 *
 * List only the subject's abstract
 */ 
SELECT property, value 
FROM dbpedia_resource
WHERE 
  uri = 'http://dbpedia.org/resource/Edward_Elgar' AND 
  property = 'has abstract'
ORDER BY property;


/*
 * Isle of Man
 * Wikipedia Page   : https://en.wikipedia.org/wiki/Isle_of_Man
 * DBpedia resource : http://dbpedia.org/resource/Isle_of_Man
 * 
 * List all non IRI properties directly related to the subject
 */ 
SELECT property, value
FROM dbpedia_resource
WHERE uri = 'http://dbpedia.org/resource/Isle_of_Man'
ORDER BY property;
