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

CREATE FOREIGN TABLE makg_author (
  id text       OPTIONS (variable '?author',  nodetype 'iri'),
  name text     OPTIONS (variable '?authorName', nodetype 'literal', literaltype 'xsd:string'),
  citations int OPTIONS (variable '?ct', nodetype 'literal', literaltype 'xsd:integer')
)
SERVER makg OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX magp: <https://makg.org/property/>
    PREFIX magc: <https://makg.org/class/>
    PREFIX foaf: <http://xmlns.com/foaf/0.1/> 

    SELECT ?author ?authorName ?ct
    WHERE {
    ?author a magc:Author .
    ?author foaf:name ?authorName .
    ?author magp:citationCount ?ct
    }
'); 

CREATE FOREIGN TABLE makg_author_paper (
  paper_id  text OPTIONS (variable '?paper',  nodetype 'iri'),
  author_id text OPTIONS (variable '?creator', nodetype 'iri')
)
SERVER makg OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    PREFIX magc: <https://makg.org/class/>
    PREFIX dcterms: <http://purl.org/dc/terms/>

    SELECT *
    WHERE {
      ?paper rdf:type magc:Paper .
      ?paper dcterms:creator ?creator .
      ?creator rdf:type magc:Author
    }
'); 

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

CREATE FOREIGN TABLE makg_affiliations (
  id text       OPTIONS (variable '?paper',  nodetype 'iri'),
  name text     OPTIONS (variable '?affilName', nodetype 'literal', literaltype 'xsd:string'),
  homepage text OPTIONS (variable '?homepage', nodetype 'literal', literaltype 'xsd:string'),
  citations int OPTIONS (variable '?citCountAffil', nodetype 'literal', literaltype 'xsd:date'),
  npapers int   OPTIONS (variable '?paperCount', nodetype 'literal', literaltype 'xsd:integer'),
  rank int      OPTIONS (variable '?rank', nodetype 'literal', literaltype 'xsd:date'),
  lon numeric   OPTIONS (variable '?lon',   nodetype 'literal', literaltype 'xsd:string'),
  lat numeric   OPTIONS (variable '?lat',   nodetype 'literal', literaltype 'xsd:string')
)
SERVER makg OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX magp: <https://makg.org/property/>
    PREFIX mclass: <https://makg.org/class/>
    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
    PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
    PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>

    SELECT *
    WHERE {
        ?affiliation a mclass:Affiliation .
        ?affiliation foaf:name ?affilName .
        ?affiliation foaf:homepage ?homepage .
        ?affiliation magp:citationCount ?citCountAffil .
        ?affiliation magp:paperCount ?paperCount .
        OPTIONAL {
            ?affiliation magp:rank ?rank .
            ?affiliation geo:lat ?lat .
            ?affiliation geo:long ?lon.
        }
    }
'); 

CREATE FOREIGN TABLE makg_author_affiliation (
  affiliation_id  text OPTIONS (variable '?affiliation',  nodetype 'iri'),
  author_id       text OPTIONS (variable '?author', nodetype 'iri')
)
SERVER makg OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX org: <http://www.w3.org/ns/org#>
    PREFIX magc: <https://makg.org/class/>

    SELECT *
    WHERE {
      ?affiliation a magc:Affiliation .
      ?author org:memberOf ?affiliation .
      ?author a magc:Author .
    }
'); 
