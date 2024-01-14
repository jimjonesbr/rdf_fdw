DROP SERVER seadatanet CASCADE;

CREATE SERVER seadatanet
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'https://edmo.seadatanet.org/sparql/sparql',
  format 'xml',
  enable_pushdown 'true'
);

CREATE FOREIGN TABLE seadatanet (
  identifier text    OPTIONS (variable '?org',  nodetype 'iri'),
  name  varchar      OPTIONS (variable '?name', nodetype 'literal'),
  modified timestamp OPTIONS (variable '?modifiedDate', nodetype 'literal', literaltype 'xsd:dateTime')
) SERVER seadatanet OPTIONS 
  (log_sparql 'true',
   sparql '
    PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
    SELECT ?org ?name ?modifiedDate
    WHERE {
      ?org a <http://www.w3.org/ns/org#Organization> ;
           <http://purl.org/dc/terms/modified> ?modifiedDate ;
           <http://www.w3.org/ns/org#name> ?name .
   }
  ');

SELECT name, modified
FROM seadatanet
WHERE 
  modified > '2020-01-01' AND
  modified < '2021-04-30'
ORDER BY modified
FETCH FIRST 10 ROWS ONLY; 

SELECT name, modified
FROM seadatanet
WHERE 
  modified BETWEEN '2021-04-01'::timestamp AND '2021-04-30'::timestamp
ORDER BY modified
FETCH FIRST 15 ROWS ONLY; 