CREATE SERVER epo
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://data.epo.org/linked-data/query'
);

CREATE FOREIGN TABLE applications (
  appuri text       OPTIONS (variable '?application'),
  appnum text      OPTIONS (variable '?appNum'),
  fdate date      OPTIONS (variable '?filingDate'),
  authority text      OPTIONS (variable '?authority')
)
SERVER epo OPTIONS (
  log_sparql 'true',
  sparql '
    prefix cpc: <http://data.epo.org/linked-data/def/cpc/>
    prefix dcterms: <http://purl.org/dc/terms/>
    prefix ipc: <http://data.epo.org/linked-data/def/ipc/>
    prefix mads: <http://www.loc.gov/standards/mads/rdf/v1.rdf>
    prefix owl: <http://www.w3.org/2002/07/owl#>
    prefix patent: <http://data.epo.org/linked-data/def/patent/>
    prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#>
    prefix skos: <http://www.w3.org/2004/02/skos/core#>
    prefix st3: <http://data.epo.org/linked-data/def/st3/>
    prefix text: <http://jena.apache.org/text#>
    prefix vcard: <http://www.w3.org/2006/vcard/ns#>
    prefix xsd: <http://www.w3.org/2001/XMLSchema#>

    SELECT ?application ?appNum ?filingDate ?authority {
    ?application rdf:type patent:Application ;
        patent:applicationNumber ?appNum ;
        patent:filingDate        ?filingDate ; 
        patent:applicationAuthority ?authority ;
        .
    }
'); 

SELECT * 
FROM applications
WHERE fdate > '2023-01-01'
LIMIT 100;