
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

/*
 * All non IRI property values directly linked to a given resource.
 * Only numeric literals or literals written in English are accepted.
 */
CREATE FOREIGN TABLE dbpedia_resource (
  uri          rdfnode OPTIONS (variable '?uri'),
  property_uri rdfnode OPTIONS (variable '?propuri'),
  property     rdfnode OPTIONS (variable '?label'),
  value        rdfnode OPTIONS (variable '?val')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX  rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  SELECT *
  WHERE {
    ?uri ?propuri ?val .
    ?propuri rdfs:label ?label .
  } 
');

/*
 * Sir Edward Elgar (british composer)
 * Wikipedia Page   : https://en.wikipedia.org/wiki/Edward_Elgar
 * DBpedia resource : http://dbpedia.org/resource/Edward_Elgar 
 *
 * List only the subject's description
 */ 
SELECT DISTINCT sparql.lex(property) AS property, sparql.lex(value) AS value
FROM dbpedia_resource
WHERE 
  NOT sparql.isiri(value) AND
  uri = sparql.iri('http://dbpedia.org/resource/Edward_Elgar') AND 
  property = sparql.strlang('Beschreibung', 'de') AND
  sparql.lang(value) = 'de'
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
WHERE uri = sparql.iri('http://dbpedia.org/resource/Isle_of_Man')
ORDER BY property;
