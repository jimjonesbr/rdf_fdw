CREATE SERVER IF NOT EXISTS makg
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://makg.org/sparql');

CREATE FOREIGN TABLE makg_papers_citation (
  paper text    OPTIONS (variable '?paper',  nodetype 'iri'),
  cited_by text OPTIONS (variable '?citing_paper',  nodetype 'iri')
)
SERVER makg OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX magc:    <https://makg.org/class/>
    PREFIX cito: <http://purl.org/spar/cito/>

    SELECT *
    WHERE {
      ?citing_paper a magc:Paper .
	    ?citing_paper cito:cites ?paper .
	    ?paper a magc:Paper .
    }
'); 


SELECT * FROm makg_papers_citation limit 11;

CREATE TABLE makg_papers_citation_local AS 
SELECT * FROM makg_papers_citation;