
CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

/* Example: Get all named graphs in the Wikidata endpoint */
CREATE FOREIGN TABLE dbpedia_graphs (
  graph rdfnode OPTIONS (variable '?g')
)
SERVER dbpedia OPTIONS (
  sparql 'SELECT DISTINCT ?g WHERE {GRAPH ?g { ?s ?p ?o }}'
);

SELECT graph FROM dbpedia_graphs;

/* Example: Get all properties without rdfs:label */
CREATE FOREIGN TABLE property_nolabel (
  property rdfnode OPTIONS (variable '?property')
)
SERVER dbpedia OPTIONS (
  sparql 'SELECT ?property
WHERE {
  ?property a rdf:Property .
  FILTER NOT EXISTS { ?property rdfs:label ?label }
}');

SELECT property FROM property_nolabel LIMIT 10;