
CREATE SERVER seadatanet
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'https://edmo.seadatanet.org/sparql/sparql',
  format 'xml',
  enable_pushdown 'true'
);

CREATE FOREIGN TABLE seadatanet (
  identifier text OPTIONS (variable '?id'),
  name  varchar OPTIONS (variable '?name'),
  modified timestamp OPTIONS (variable '?modified'),
  notation int OPTIONS (variable '?notation')
) SERVER seadatanet OPTIONS 
  (log_sparql 'true',
   sparql '
    PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>PREFIX foaf: <http://xmlns.com/foaf/0.1/>
    PREFIX ns: <http://www.w3.org/2006/vcard/ns#>PREFIX dct: <http://purl.org/dc/terms/>
    PREFIX skos: <http://www.w3.org/2004/02/skos/core#>SELECT* WHERE{?id ns:hasGeo ?geo;
        <http://www.w3.org/ns/org#name> ?name;
        dct:modified ?modified ;
        skos:notation ?notation}
  ');

SELECT name, modified
FROM seadatanet
WHERE 
  modified > '2021-04-01' AND
  modified < '2021-04-30'
ORDER BY modified
LIMIT 10;

SELECT name, modified
FROM seadatanet
WHERE 
  modified BETWEEN '2021-04-01'::timestamp AND '2021-04-30'::timestamp
ORDER BY modified
LIMIT 10;

/* ################### SeaDataNet EDMO Code Country ################### */

CREATE FOREIGN TABLE edmo_country (
  code int OPTIONS (variable '?EDMO_CODE'),
  org_name  varchar OPTIONS (variable '?ORG_NAME'),
  country text OPTIONS (variable '?COUNTRY'),
  expr_col1 text OPTIONS (variable '?foo', expression '(CONCAT(UCASE(?COUNTRY), " - ", UCASE(?ORG_NAME)) AS ?foo)'),
  expr_col2 text OPTIONS (variable '?bar', expression '(STRLEN(?COUNTRY) + STRLEN(?ORG_NAME) AS ?bar)')
) SERVER seadatanet OPTIONS 
  (log_sparql 'true',
   sparql '
    PREFIX skos:<http://www.w3.org/2004/02/skos/core#>
    PREFIX rdf:<http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    SELECT *
    WHERE {
	    ?EDMO_URL rdf:type <http://www.w3.org/ns/org#Organization>.
  	  ?EDMO_URL <http://www.w3.org/ns/org#name> ?ORG_NAME.
	    ?EDMO_URL skos:notation ?EDMO_CODE.
	    ?EDMO_URL <http://www.w3.org/2006/vcard/ns#country-name> ?COUNTRY.
    }
  ');

  SELECT * FROM edmo_country 
  FETCH FIRST 15 ROWS ONLY; 