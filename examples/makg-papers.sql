CREATE SERVER makg
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://makg.org/sparql');

CREATE FOREIGN TABLE makg_papers (
  id text       OPTIONS (variable '?paper',  nodetype 'iri'),
  title text    OPTIONS (variable '?paperTitle', nodetype 'literal', literaltype 'xsd:string'),
  pubdate date  OPTIONS (variable '?paperPubDate', nodetype 'literal', literaltype 'xsd:date'),
  keyword text  OPTIONS (variable '?keyword',   nodetype 'literal', literaltype 'xsd:string'),
  field text    OPTIONS (variable '?fieldname',   nodetype 'literal', literaltype 'xsd:string')
)
SERVER makg OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX rdf:     <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    PREFIX magc:    <https://makg.org/class/>
    PREFIX dcterms: <http://purl.org/dc/terms/>
    PREFIX foaf:    <http://xmlns.com/foaf/0.1/>
    PREFIX fabio:   <http://purl.org/spar/fabio/>
    PREFIX prism:   <http://prismstandard.org/namespaces/basic/2.0/>
    PREFIX xsd:     <http://www.w3.org/2001/XMLSchema#>

    SELECT *
    WHERE {
      ?paper rdf:type magc:Paper .
      ?paper prism:keyword ?keyword .
      ?paper fabio:hasDiscipline ?field .
      ?paper dcterms:title ?paperTitle .
      ?paper prism:publicationDate ?paperPubDate .
      OPTIONAL {?field foaf:name ?fieldname} 
    }
'); 


SELECT *
FROM makg_papers
WHERE
  pubdate BETWEEN '2018-01-01' AND' 2020-01-01' AND
  field = 'Medicine' AND
  keyword = 'patients';


/* Create a logcal copy */
CREATE TABLE makg_papers_local AS
SELECT * FROM makg_papers;

/* Group keywords in an array */
SELECT DISTINCT
  id, title, pubdate, field,
  string_agg(keyword,', ' ORDER BY keyword ASC) AS keywords
FROM makg_papers_local
WHERE field IN ('Mathematics','Computer science')
GROUP BY id, title, pubdate, field;