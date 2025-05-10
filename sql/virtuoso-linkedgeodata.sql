
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

/* SPARQL 15.4 - OFFSET */
SELECT p, o FROM hbf
WHERE p = '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>'
OFFSET 5 ROWS
FETCH FIRST 10 ROWS ONLY;

SELECT p, o FROM hbf
WHERE p = '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>'
OFFSET 5 ROWS
LIMIT 10;

/* SPARQL 15.1 - ORDER BY */
SELECT o FROM hbf
ORDER BY p DESC
LIMIT 3;

SELECT p FROM hbf
ORDER BY o DESC
LIMIT 3;

SELECT p, o FROM hbf
ORDER BY p DESC, o ASC
LIMIT 3;

SELECT p, o FROM hbf
ORDER BY p DESC, o ASC
OFFSET 5
LIMIT 2;

SELECT p,o FROM hbf
ORDER BY 1 DESC, 2 ASC
OFFSET 5
LIMIT 10;

/* SPARQL 18.2.5.3 - DISTINCT*/
SELECT DISTINCT p FROM hbf
WHERE p = '<http://www.w3.org/2000/01/rdf-schema#label>';

-- DISTINCT ON is not supported, therefore it won't be pushed down.
SELECT DISTINCT ON (p) p,o FROM hbf
WHERE p = '<http://www.w3.org/2000/01/rdf-schema#label>';

/* SPARQL - 17.3 Operator Mapping (text) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  p <> '<foo.bar>' AND
  p >= '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  p <= '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  p BETWEEN '<http://www.w3.org/2000/01/rdf-schema#label>' AND '<http://www.w3.org/2000/01/rdf-schema#label>';

/* SPARQL - 17.3 Operator Mapping (rdfnode) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>'::rdfnode AND
  p <> '<foo.bar>' AND
  p >= '<http://www.w3.org/2000/01/rdf-schema#label>'::rdfnode AND
  p <= '<http://www.w3.org/2000/01/rdf-schema#label>'::rdfnode AND
  p BETWEEN '<http://www.w3.org/2000/01/rdf-schema#label>'::rdfnode AND '<http://www.w3.org/2000/01/rdf-schema#label>'::rdfnode;

/* SPARQL - 17.3 Operator Mapping (smallint) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://linkedgeodata.org/ontology/version>'::rdfnode AND
  o = 19::smallint AND
  o <> 20::smallint AND
  o >= 19::smallint AND
  o <= 19::smallint AND
  o BETWEEN 18 AND 20 AND
  19::smallint = o AND
  20::smallint <> o AND
  19::smallint >= o AND
  19::smallint <= o;


/* SPARQL - 17.3 Operator Mapping (int) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://linkedgeodata.org/ontology/changeset>'::rdfnode AND
  o = 32586907::int AND
  o <> 999999::int AND
  o >= 32586907::int AND
  o <= 32586907::int AND
  o BETWEEN 32586900::int AND 32586909::int AND
  32586907::int = o AND
  999999::int <> o AND
  32586907::int >= o AND
  32586907::int <= o;

/* SPARQL - 17.3 Operator Mapping (bigint) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://linkedgeodata.org/ontology/changeset>'::rdfnode AND
  o = 32586907::bigint AND
  o <> 999999::bigint AND
  o >= 32586907::bigint AND
  o <= 32586907::bigint AND
  o BETWEEN 32586900::bigint AND 32586909::bigint AND
  32586907::bigint = o AND
  999999::bigint <> o AND
  32586907::bigint >= o AND
  32586907::bigint <= o;

/* SPARQL - 17.3 Operator Mapping (real) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://www.w3.org/2003/01/geo/wgs84_pos#long>'::rdfnode AND
  o <> 13.40::real AND
  o >= 12.01::real AND
  o <= 14.01::real AND
  o BETWEEN 12::real AND 14::real AND
  13.40::real <> o AND
  12.01::real <= o AND
  14.01::real >= o;

/* SPARQL - 17.3 Operator Mapping (double precision) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://www.w3.org/2003/01/geo/wgs84_pos#long>'::rdfnode AND
  o <> 13.40::double precision AND
  o >= 12.01::double precision AND
  o <= 14.01::double precision AND
  o BETWEEN 12::double precision AND 14::double precision AND
  13.40::double precision <> o AND
  12.01::double precision <= o AND
  14.01::double precision >= o;

/* SPARQL - 17.3 Operator Mapping (numeric) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://www.w3.org/2003/01/geo/wgs84_pos#long>'::rdfnode AND
  o <> 13.40::numeric AND
  o >= 12.01::numeric AND
  o <= 14.01::numeric AND
  o BETWEEN 12::numeric AND 14::numeric AND
  13.40::numeric <> o AND
  12.01::numeric <= o AND
  14.01::numeric >= o;

/* SPARQL - 17.3 Operator Mapping (timestamp) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://purl.org/dc/terms/modified>'::rdfnode AND
  o <> '2020-01-31 18:30:00'::timestamp AND
  o >= '2015-07-12 20:40:00'::timestamp AND
  o <= '2015-07-12 21:00:00'::timestamp AND
  o BETWEEN '2014-01-01 12:30:00'::timestamp AND '2016-01-01 12:30:00'::timestamp AND
  '2020-01-31 18:30:00'::timestamp <> o AND
  '2015-07-12 20:40:00'::timestamp <= o AND
  '2015-07-12 21:00:00'::timestamp >= o;

/* SPARQL - 17.3 Operator Mapping (timestamptz) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://purl.org/dc/terms/modified>'::rdfnode AND
  o <> '2020-01-31 18:30:00'::timestamptz AND
  o >= '2015-07-12 08:40:00'::timestamptz AND
  o <= '2015-07-13 21:00:00'::timestamptz AND
  o BETWEEN '2014-01-01 12:30:00'::timestamptz AND '2016-01-01 12:30:00'::timestamptz AND
  '2020-01-31 18:30:00'::timestamptz <> o AND
  '2015-07-12 08:40:00'::timestamptz <= o AND
  '2015-07-13 21:00:00'::timestamptz >= o;

/* SPARQL - 17.3 Operator Mapping (date) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://purl.org/dc/terms/modified>'::rdfnode AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') = '2015-07-12'::date AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') <> '2025-02-02'::date AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') >= '2015-07-12'::date AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') <= '2015-07-13'::date AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') BETWEEN '2014-01-01'::date AND '2016-01-01'::date AND
  '2015-07-12'::date =  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') AND
  '2025-02-02'::date <> sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') AND
  '2015-07-12'::date <= sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') AND
  '2015-07-13'::date >= sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date');

-- /* SPARQL - 17.3 Operator Mapping (time) */
-- SELECT p, o FROM hbf
-- WHERE 
--   p = '<http://purl.org/dc/terms/modified>'::rdfnode AND
--   sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') = '20:41:25'::time AND
--   sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') <> '23:00:00'::time AND
--   sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') >= '20:41:25'::time AND
--   sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') <= '20:41:25'::time AND
--   sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') BETWEEN '18:41:25'::time AND '20:41:25'::time;  

/* SPARQL - 17.3 Operator Mapping (timetz) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://purl.org/dc/terms/modified>'::rdfnode AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') = '20:41:25'::timetz AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') <> '23:00:00'::timetz AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') >= '20:41:25'::timetz AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') <= '20:41:25'::timetz AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') BETWEEN '18:41:25'::timetz AND '20:41:25'::timetz AND
  '20:41:25'::timetz =  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') AND
  '23:00:00'::timetz <> sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') AND
  '20:41:25'::timetz <= sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') AND
  '20:41:25'::timetz >= sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time');


/* SPARQL - 17.3 Operator Mapping (boolean) */
SELECT p, o FROM hbf
WHERE 
  p = '<http://linkedgeodata.org/ontology/wheelchair>'::rdfnode AND
  o = true AND
  o <> false AND
  true = o AND
  false <> o;