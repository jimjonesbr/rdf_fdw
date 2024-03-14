CREATE SERVER makg
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://makg.org/sparql');

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


SELECT * FROM makg_affiliations LIMIT 10;
