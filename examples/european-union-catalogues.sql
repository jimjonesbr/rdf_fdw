CREATE SERVER eudata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://data.europa.eu/sparql');

/*
 * Get a list of all catalogues on data.europa.eu
 * This query retrieves a full list catalogues published on data.europa.eu. It then retrieves with an OPTIONAL 
 * clause the catalogue's title, homepage, geographical coverage etc.
 * 
 * Source: European data (https://data.europa.eu/de/about/sparql)
 */

CREATE FOREIGN TABLE catalogues (
  parent text   OPTIONS (variable '?parentCatalog'),
  catalog text  OPTIONS (variable '?catalog'),
  title text    OPTIONS (variable '?title'),
  spatial text  OPTIONS (variable '?spatial'),
  pubtype text  OPTIONS (variable '?typePublisher'),
  homepage text OPTIONS (variable '?homepage'),
  email text    OPTIONS (variable '?email')
)
SERVER eudata OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX dcat: <http://www.w3.org/ns/dcat#>
    PREFIX dct: <http://purl.org/dc/terms/>
    PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>

    SELECT *
    WHERE {
      ?catalog ?p ?o.
      FILTER (?o=<http://www.w3.org/ns/dcat#Catalog>)
      OPTIONAL {?catalog <http://purl.org/dc/terms/title> ?title}
      OPTIONAL {?parentCatalog <http://purl.org/dc/terms/hasPart> ?catalog}
      OPTIONAL {?catalog <http://purl.org/dc/terms/spatial> ?spatial.}
      OPTIONAL {?catalog <http://purl.org/dc/terms/publisher> ?publisher.
      OPTIONAL {?publisher <http://xmlns.com/foaf/0.1/homepage> ?homepage.}
      OPTIONAL {?publisher <http://xmlns.com/foaf/0.1/mbox> ?email.}
      OPTIONAL {?publisher <http://purl.org/dc/terms/type> ?typePublisher.}
      }
    }    
');


SELECT DISTINCT catalog, title, email
FROM catalogues
WHERE email IS NOT NULL
ORDER BY title;