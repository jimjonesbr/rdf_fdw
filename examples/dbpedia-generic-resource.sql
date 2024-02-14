
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

/*
 * All non IRI property values directly linked to a given resource.
 * Only numeric literals or literals written in English are accepted.
 */
CREATE FOREIGN TABLE dbpedia_resource (
  uri text           OPTIONS (variable '?uri', nodetype 'iri'),
  property_uri text  OPTIONS (variable '?propuri', nodetype 'literal'),
  property text      OPTIONS (variable '?label', nodetype 'literal', language '*'),
  value text         OPTIONS (variable '?val', nodetype 'literal')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX  rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  SELECT *
  WHERE {
    ?uri ?propuri ?val .
    ?propuri rdfs:label ?label .
    FILTER(!isIRI(?val))
    FILTER(LANG(?val) = "en" || LANG(?val) = "")
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
