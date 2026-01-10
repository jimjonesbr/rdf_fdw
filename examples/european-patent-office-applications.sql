SELECT sparql.add_context('epo_context', 'European Patent Office Linked Data context');

SELECT sparql.add_prefix('epo_context', 'cpc', 'http://data.epo.org/linked-data/def/cpc/');
SELECT sparql.add_prefix('epo_context', 'dcterms', 'http://purl.org/dc/terms/');
SELECT sparql.add_prefix('epo_context', 'ipc', 'http://data.epo.org/linked-data/def/ipc/');
SELECT sparql.add_prefix('epo_context', 'mads', 'http://www.loc.gov/standards/mads/rdf/v1.rdf');
SELECT sparql.add_prefix('epo_context', 'owl', 'http://www.w3.org/2002/07/owl#');
SELECT sparql.add_prefix('epo_context', 'patent', 'http://data.epo.org/linked-data/def/patent/');
SELECT sparql.add_prefix('epo_context', 'rdf', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#');
SELECT sparql.add_prefix('epo_context', 'rdfs', 'http://www.w3.org/2000/01/rdf-schema#');
SELECT sparql.add_prefix('epo_context', 'skos', 'http://www.w3.org/2004/02/skos/core#');
SELECT sparql.add_prefix('epo_context', 'st3', 'http://data.epo.org/linked-data/def/st3/');
SELECT sparql.add_prefix('epo_context', 'text', 'http://jena.apache.org/text#');
SELECT sparql.add_prefix('epo_context', 'vcard', 'http://www.w3.org/2006/vcard/ns#');
SELECT sparql.add_prefix('epo_context', 'xsd', 'http://www.w3.org/2001/XMLSchema#');

CREATE SERVER epo
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://data.epo.org/linked-data/query',
  prefix_context 'epo_context'
);

CREATE FOREIGN TABLE applications (
  appuri    rdfnode OPTIONS (variable '?application'),
  appnum    rdfnode OPTIONS (variable '?appNum'),
  fdate     rdfnode OPTIONS (variable '?filingDate'),
  authority rdfnode OPTIONS (variable '?authority')
)
SERVER epo OPTIONS (
  log_sparql 'true',
  sparql '
    SELECT ?application ?appNum ?filingDate ?authority {
    ?application rdf:type patent:Application ;
        patent:applicationNumber ?appNum ;
        patent:filingDate        ?filingDate ; 
        patent:applicationAuthority ?authority ;
        .
    }
'); 

SELECT appuri, appnum, fdate, authority 
FROM applications
WHERE fdate > '2023-01-01'::date
FETCH FIRST 10 ROWS ONLY;

SELECT appuri, appnum, fdate, authority 
FROM applications
WHERE appuri = '<http://data.epo.org/linked-data/id/application/EP/23723398>'
FETCH FIRST 10 ROWS ONLY;