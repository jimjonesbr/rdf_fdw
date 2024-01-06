CREATE SERVER bbc
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://lod.openlinksw.com/sparql',
  format 'application/sparql-results+xml'
);

/*
 * Authors and their work registered in the BBC Programmes and Music database
 */

CREATE FOREIGN TABLE artists (
  id text          OPTIONS (variable '?person',  nodetype 'iri'),
  name text        OPTIONS (variable '?name',    nodetype 'literal'),
  itemid text      OPTIONS (variable '?created', nodetype 'iri'),
  title text       OPTIONS (variable '?title',   nodetype 'literal'),
  description text OPTIONS (variable '?descr',   nodetype 'literal')
)
SERVER bbc OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX foaf:    <http://xmlns.com/foaf/0.1/>
  PREFIX blterms: <http://www.bl.uk/schemas/bibliographic/blterms#>
  PREFIX dcterms: <http://purl.org/dc/terms/>
  PREFIX bibo:    <http://purl.org/ontology/bibo/>
  PREFIX xsd:     <http://www.w3.org/2001/XMLSchema#>

  SELECT *
  {
    ?person a foaf:Person ;
      foaf:name ?name ;
      blterms:hasCreated ?created .
    ?created a bibo:Book ;
      dcterms:title ?title ;
    dcterms:description ?descr
  } 
'); 


SELECT DISTINCT title, description 
FROM artists
WHERE name = 'John Lennon';
