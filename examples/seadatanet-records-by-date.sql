SET timezone TO 'Etc/UTC';

CREATE SERVER seadatanet
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'https://edmo.seadatanet.org/sparql/sparql',
  format 'xml',
  enable_pushdown 'true'
);

CREATE FOREIGN TABLE seadatanet (
  identifier rdfnode OPTIONS (variable '?org'),
  name       rdfnode OPTIONS (variable '?name'),
  modified   rdfnode OPTIONS (variable '?modifiedDate')
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

SELECT name, modified::timestamptz
FROM seadatanet
WHERE 
  modified > '2020-01-01'::timestamptz AND
  modified < '2021-04-30'::timestamptz
ORDER BY modified
FETCH FIRST 10 ROWS ONLY; 

SELECT name, modified::timestamptz
FROM seadatanet
WHERE modified BETWEEN 
  '2021-04-01'::timestamptz AND 
  '2021-04-30'::timestamp
ORDER BY modified
FETCH FIRST 15 ROWS ONLY; 