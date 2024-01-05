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
  uri text    OPTIONS (variable '?subject',  nodetype 'iri'),
  label text  OPTIONS (variable '?label', nodetype 'literal', language 'en'),
  lang text   OPTIONS (variable '?lang', expression 'LANG(?label)')
)
SERVER agrovoc OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX skos:   <http://www.w3.org/2004/02/skos/core#> 
  PREFIX skosxl: <http://www.w3.org/2008/05/skos-xl#> 
  PREFIX xsd:    <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

  SELECT ?subject ?label 
  WHERE { 
    ?subject a skos:Concept . 
    ?subject skos:broader+ <http://aims.fao.org/aos/agrovoc/c_5993> . 
    ?subject skosxl:prefLabel ?xLabel . 
    ?xLabel skosxl:literalForm ?label .
  } 
'); 

/* 
 * The WHERE condition will be pushed down in a FILTER expression, and the 
 * literal will get the language configured in the CREATE TABLE statement
 */
SELECT * FROM plants
WHERE label = 'chrysanthemums';

/* 
 * The WHERE condition will be pushed down in a FILTER expression, and the 
 * string will be wrapped in a IRI() call, since the column is declared with
 * the nodetype 'iri'
 */
SELECT * FROM plants
WHERE uri = 'http://aims.fao.org/aos/agrovoc/c_25549';