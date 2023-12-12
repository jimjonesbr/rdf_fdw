CREATE SERVER getty
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'http://vocab.getty.edu/sparql.xml',
  format 'application/sparql-results+xml'
);


CREATE FOREIGN TABLE getty_places (
  uri text     OPTIONS (variable '?place'),
  name text    OPTIONS (variable '?name'),
  lon numeric  OPTIONS (variable '?lon'),
  lat numeric  OPTIONS (variable '?lat')
)
SERVER getty OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX ontogeo: <http://www.ontotext.com/owlim/geo#>
  PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  PREFIX gvp: <http://vocab.getty.edu/ontology#>
  PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
  PREFIX schema: <http://schema.org/>
  SELECT *
  WHERE {
  ?place skos:inScheme tgn: ;
    foaf:focus ?geouri ;
    foaf:focus [ontogeo:within(50.787185 3.389722 53.542265 7.169019)] ;
    gvp:parentString ?name .
  ?geouri a schema:Place ;
   	geo:lat ?lat ;
    geo:long ?lon
  }
  '); 


SELECT DISTINCT name, lon, lat  
FROM getty_places 
ORDER BY lat
LIMIT 10;

SELECT uri, lon, lat
FROM getty_places
WHERE name = 'West Flanders, Flanders, Belgium, Europe, World';

SELECT DISTINCT ON (name) name, lon, lat
FROM getty_places
WHERE lat BETWEEN 52.5 AND 53.0;
