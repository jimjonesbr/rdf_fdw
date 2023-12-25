CREATE SERVER bbc
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://lod.openlinksw.com/sparql',
  format 'application/sparql-results+xml'
);


CREATE FOREIGN TABLE artists (
  id text          OPTIONS (variable '?person'),
  name text        OPTIONS (variable '?name'),
  itemid text      OPTIONS (variable '?created'),
  title text       OPTIONS (variable '?title'),
  description text OPTIONS (variable '?description')
)
SERVER bbc OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX foaf: <http://xmlns.com/foaf/0.1/>
  PREFIX blterms: <http://www.bl.uk/schemas/bibliographic/blterms#>
  PREFIX dcterms: <http://purl.org/dc/terms/>
  PREFIX bibo: <http://purl.org/ontology/bibo/>

  SELECT ?person ?name ?created ?title ?description 
  WHERE 
  {
    ?person a foaf:Person ;
      foaf:name ?name ;
      blterms:hasCreated ?created .
    ?created a bibo:Book ;
      dcterms:title ?title ;
    dcterms:description ?description
   } 
'); 

SELECT DISTINCT title, description 
FROM artists
WHERE name = 'John Lennon';