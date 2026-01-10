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
  parent   rdfnode OPTIONS (variable '?parentCatalog'),
  catalog  rdfnode OPTIONS (variable '?catalog'),
  title    rdfnode OPTIONS (variable '?title'),
  spatial  rdfnode OPTIONS (variable '?spatial'),
  pubtype  rdfnode OPTIONS (variable '?typePublisher'),
  homepage rdfnode OPTIONS (variable '?homepage'),
  email    rdfnode OPTIONS (variable '?email')
)
SERVER eudata OPTIONS (
  log_sparql 'true',
  sparql '
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