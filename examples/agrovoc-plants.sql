CREATE SERVER agrovoc
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://agrovoc.fao.org/sparql',
  format 'application/sparql-results+xml'
);

/*
 * Food and Agriculture Organization of the United Nations
 *
 * Select all concepts that point to c_5993 (plants) as broader and show their English (en) prefLabels
 * Source: https://agrovoc.fao.org/sparql
 */

CREATE FOREIGN TABLE plants (
  uri text       OPTIONS (variable '?subject'),
  label text      OPTIONS (variable '?label')
)
SERVER agrovoc OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX skos: <http://www.w3.org/2004/02/skos/core#> 
  PREFIX skosxl: <http://www.w3.org/2008/05/skos-xl#> 
  SELECT ?subject ?label 
  WHERE { 
    ?subject a skos:Concept . 
    ?subject skos:broader+ <http://aims.fao.org/aos/agrovoc/c_5993> . 
    ?subject skosxl:prefLabel ?xLabel . 
    ?xLabel skosxl:literalForm ?label . 
    FILTER (lang(?label)="en") 
  } 
'); 

SELECT * FROM plants
ORDER BY label;