
DROP EXTENSION IF EXISTS rdf_fdw CASCADE;
CREATE EXTENSION rdf_fdw;

CREATE SERVER linkegeodata 
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'http://linkedgeodata.org/sparql');

CREATE FOREIGN TABLE hbf (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER linkegeodata OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * WHERE {<http://linkedgeodata.org/triplify/node376142577> ?p ?o}');

/* SPARQL 17.4.1.7 - RDFterm-equal */
SELECT p, o FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  o = '"Leipzig Hbf"';

/* SPARQL 17.4.1.9 - IN */
SELECT p, o FROM hbf
WHERE
  o IN ('"Leipzig Hbf"', 
        '"Gare centrale de Leipzig"@fr');

/* SPARQL 17.4.1.10 - NOT IN*/
SELECT p, o FROM hbf
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.lang(o) NOT IN ('de','es');

/* SPARQL 15.5 - LIMIT */
SELECT p, o FROM hbf
WHERE p = '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>'
LIMIT 5;

SELECT p, o FROM hbf
WHERE p = '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>'
FETCH FIRST 5 ROWS ONLY;

SELECT p, o FROM hbf
WHERE p = '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>'
OFFSET 5 ROWS
FETCH FIRST 10 ROWS ONLY;

SELECT p, o FROM hbf
WHERE p = '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>'
OFFSET 5 ROWS
LIMIT 10;

/* SPARQL 15.1 - ORDER BY */
SELECT p FROM hbf
ORDER BY p DESC
OFFSET 5
LIMIT 2;












SELECT p, o FROM hbf
ORDER BY p, o DESC--, o ASC
--OFFSET 5
LIMIT 2;






--SET client_min_messages to DEBUG4;
--RESET client_min_messages;

SELECT * FROM hbf ORDER BY p::text LIMIT 2;

SELECT p,o FROM ft
ORDER BY 1 DESC, 2 ASC
OFFSET 5
LIMIT 10;

/* SPARQL 18.2.5.3 - DISTINCT*/
SELECT DISTINCT p,o FROM ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.lang(o) IN ('de','es','fr','pt','en');

-- DISTINCT ON is not supported, therefore it won't be pushed down.
SELECT DISTINCT ON (p) p,o FROM ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.lang(o) IN ('de','es','fr','pt','en');
