CREATE SERVER linkedgeodata 
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'http://linkedgeodata.org/sparql');

CREATE FOREIGN TABLE hbf (
  label         	text OPTIONS (variable '?label', language 'fr'),
  modified      	timestamp OPTIONS (variable '?modified', literaltype 'xsd:dateTime'),
  version       	bigint OPTIONS (variable '?version', literaltype 'xsd:int'),
  wheelchair    	boolean OPTIONS (variable '?wc', literaltype 'xsd:boolean'),
  lat           	numeric OPTIONS (variable '?lat'),
  lon           	numeric OPTIONS (variable '?lon'),
  type              text OPTIONS (variable '?type', nodetype 'iri'),
  fake_string       text  OPTIONS (variable '?str', expression 'STRDT("foo",<http://www.w3.org/2001/XMLSchema#string>)', literaltype 'xsd:string'),
  fake_date     	date  OPTIONS (variable '?dt', expression '"2018-05-01"^^xsd:date'),
  fake_time     	time  OPTIONS (variable '?tm', expression '"T11:30:42"^^xsd:time'),
  fake_timetz   	timetz  OPTIONS (variable '?tmtz', expression '"T14:45:13-05:00"^^xsd:time'),
  fake_timestamptz	timestamptz  OPTIONS (variable '?tstz', expression '"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime')
)
SERVER linkedgeodata OPTIONS (
  log_sparql 'true',
  sparql '
  SELECT * {
    ?s <http://www.w3.org/2000/01/rdf-schema#label> ?label .
    ?s <http://purl.org/dc/terms/modified> ?modified .
    ?s <http://linkedgeodata.org/ontology/version> ?version .
    ?s <http://linkedgeodata.org/ontology/wheelchair> ?wc .
    ?s <http://www.w3.org/2003/01/geo/wgs84_pos#lat> ?lat .
    ?s <http://www.w3.org/2003/01/geo/wgs84_pos#long> ?lon .
    ?s <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> ?type
    FILTER(?s = <http://linkedgeodata.org/triplify/node376142577>)
    }
 ');

/* SPARQL 17.4.1.7 - RDFterm-equal */
SELECT * FROM hbf
WHERE label = 'Gare centrale de Leipzig';

/* SPARQL 17.4.1.9 - IN */
SELECT * FROM hbf
WHERE label IN ('Leipzig Hbf', 'Gare centrale de Leipzig');

SELECT label, type FROM hbf
WHERE label = ANY(ARRAY['Leipzig Hbf', 'Gare centrale de Leipzig']);

SELECT * FROM hbf
WHERE fake_string IN ('Leipzig Hbf', 'Gare centrale de Leipzig');

/* SPARQL 17.4.1.10 - NOT IN*/
SELECT * FROM hbf
WHERE label NOT IN ('foo','bar');

/* SPARQL 15.5 - LIMIT */
SELECT * FROM hbf
LIMIT 1;

SELECT * FROM hbf
FETCH FIRST ROW ONLY;

SELECT * FROM hbf
FETCH FIRST 2 ROWS ONLY;

/* SPARQL 15.4 - OFFSET */
SELECT * FROM hbf
OFFSET 1
LIMIT 1;

SELECT * FROM hbf
OFFSET 1
FETCH FIRST ROW ONLY;

/* SPARQL 15.1 - ORDER BY */
SELECT * FROM hbf
ORDER BY label ASC
LIMIT 2;

SELECT * FROM hbf
ORDER BY label DESC
LIMIT 2;

SELECT * FROM hbf
ORDER BY label ASC, type DESC
LIMIT 3;

/* SPARQL 18.2.5.3 - DISTINCT*/
SELECT DISTINCT label, modified FROM hbf;
SELECT DISTINCT ON (label, modified) label, modified, version FROM hbf;

/* SPARQL - 17.3 Operator Mapping (pgtypes) */
SELECT * FROM hbf
WHERE
  label = 'Gare centrale de Leipzig' AND
  modified = '2015-07-12 20:41:25'::timestamp AND
  wheelchair IS true AND
  version = 19 AND
  type = 'http://linkedgeodata.org/ontology/RailwayStation'::varchar AND
  fake_timestamptz = '2011-01-10 14:45:13.815-05:00'::timestamptz AND
  fake_date = '2018-05-01'::date AND
  fake_string = 'foo';

SELECT DISTINCT * FROM hbf
WHERE
  label <> 'foo' AND
  modified <> '2020-07-12 20:41:25'::timestamp AND
  wheelchair IS NOT false AND
  version <> 99 AND
  lat <> 99 AND
  lon <> 99 AND
  type <> 'http://linkedgeodata.org/ontology/RailwayStation'::varchar AND
  fake_timestamptz <> '2020-01-10 14:45:13.815-05:00'::timestamptz AND
  fake_date <> '2020-05-01'::date AND
  fake_string <> 'bar'
ORDER BY type;

SELECT DISTINCT label, modified, version, lat, lon, fake_timestamptz, fake_date FROM hbf
WHERE
  modified > '2014-07-12 20:41:25'::timestamp AND
  version > 01 AND
  lat > 01 AND
  lon > 01 AND
  fake_timestamptz > '2010-01-10 14:45:13.815-05:00'::timestamptz AND
  fake_date > '2017-05-01'::date;

SELECT DISTINCT label, modified, version, lat, lon, fake_timestamptz, fake_date FROM hbf
WHERE
  modified < '2016-07-12 20:41:25'::timestamp AND
  version < 99 AND
  lat < 99 AND
  lon < 99 AND
  fake_timestamptz < '2012-01-10 14:45:13.815-05:00'::timestamptz AND
  fake_date < '2019-05-01'::date;

SELECT DISTINCT label, modified, version, lat, lon, fake_timestamptz, fake_date FROM hbf
WHERE
  modified >= '2015-07-12 20:41:25'::timestamp AND
  version >= 19 AND
  fake_timestamptz >= '2011-01-10 14:45:13.815-05:00'::timestamptz AND
  fake_date >= '2018-05-01'::date AND
  fake_timestamptz >= '2011-01-10 14:45:13.815-05:00'::timestamptz AND
  fake_date >= '2018-05-01'::date;

SELECT DISTINCT label, modified, version, lat, lon, fake_timestamptz, fake_date FROM hbf
WHERE
  modified <= '2015-07-12 20:41:25'::timestamp AND
  version <= 19 AND
  fake_timestamptz <= '2011-01-10 14:45:13.815-05:00'::timestamptz AND
  fake_date <= '2018-05-01'::date AND
  fake_timestamptz <= '2011-01-10 14:45:13.815-05:00'::timestamptz AND
  fake_date <= '2018-05-01'::date;

SELECT DISTINCT label, modified, version, lat, lon, fake_timestamptz, fake_date FROM hbf
WHERE
  modified BETWEEN '2014-07-12 20:41:25'::timestamp AND '2016-07-12 20:41:25'::timestamp AND
  version BETWEEN 17 AND 20 AND
  fake_timestamptz BETWEEN '2010-01-10 14:45:13.815-05:00'::timestamptz AND '2012-01-10 14:45:13.815-05:00'::timestamptz AND
  fake_date BETWEEN '2017-05-01'::date AND '2019-05-01'::date AND
  fake_timestamptz BETWEEN '2010-01-10 14:45:13.815-05:00'::timestamptz AND '2012-01-10 14:45:13.815-05:00'::timestamptz AND
  fake_date BETWEEN '2017-05-01'::date AND '2019-05-01'::date;

/* pushdown - PostgreSQL length */
SELECT label, type FROM hbf
WHERE 
  length(label) = 24 AND
  length(label) <> 1 AND
  length(label) < 99 AND
  length(label) <= 24 AND
  length(label) >= 24 AND
  length(label) BETWEEN 10 AND 88;

/* pushdown - PostgreSQL abs */
SELECT DISTINCT label, abs(version) FROM hbf
WHERE 
  abs(version) = 19 AND
  abs(version) > 01 AND
  abs(version) >= 19 AND
  abs(version) <  99 AND
  abs(version) <=  19 AND
  abs(version) BETWEEN 01 AND 99;

/* pushdown - PostgreSQL round */
SELECT DISTINCT label, round(lat)
FROM hbf 
WHERE 
  round(lat) = 51 AND
  round(lat) > 01 AND
  round(lat) >= 51 AND
  round(lat) < 99 AND
  round(lat) <= 51 AND
  round(lat) BETWEEN 01 AND 99;

/* pushdown - PostgreSQL ceil */
SELECT DISTINCT label, ceil(lat)
FROM hbf 
WHERE 
  ceil(lat) = 52 AND
  ceil(lat) > 01 AND
  ceil(lat) >= 52 AND
  ceil(lat) < 99 AND
  ceil(lat) <= 52 AND
  ceil(lat) BETWEEN 01 AND 99;

/* pushdown - PostgreSQL floor */
SELECT DISTINCT label, floor(lat)
FROM hbf 
WHERE 
  floor(lat) = 51 AND
  floor(lat) > 01 AND
  floor(lat) >= 51 AND
  floor(lat) < 99 AND
  floor(lat) <= 51 AND
  floor(lat) BETWEEN 01 AND 99;

/* pushdown - PostgreSQL substring */
SELECT DISTINCT label, modified
FROM hbf
WHERE substring(label,1,7) = 'Leipzig';

/* pushdown - PostgreSQL extract */
ALTER FOREIGN TABLE hbf OPTIONS (SET log_sparql 'false');
SELECT label, modified 
FROM hbf
WHERE
  EXTRACT(year FROM modified) = 2015 AND
  EXTRACT(month FROM modified) = 07 AND
  EXTRACT(days FROM modified) = 12 AND
  EXTRACT(hours FROM modified) = 20  AND
  EXTRACT(minutes FROM modified) = 41  AND
  EXTRACT(seconds FROM modified) = 25
FETCH FIRST ROW ONLY;
ALTER FOREIGN TABLE hbf OPTIONS (SET log_sparql 'true');

/* pushdown - PostgreSQL md5 */
SELECT DISTINCT label, md5(label) 
FROM hbf
WHERE md5(label) = '0ef548c961d447732b145dc39df17df4';

/* non-pushable query (MINUS) */
CREATE FOREIGN TABLE hbf_np1 (
  p text OPTIONS (variable '?p'),
  o text OPTIONS (variable '?o')
)
SERVER linkedgeodata OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX dc: <http://purl.org/dc/terms/>

    SELECT * WHERE {
      <http://linkedgeodata.org/triplify/node376142577> ?p ?o
      MINUS {<http://linkedgeodata.org/triplify/node376142577> dc:modified ?o}
    }
');

SELECT * FROM hbf_np1
WHERE p = 'http://linkedgeodata.org/ontology/operator';

/* non-pushable query (UNION) */
CREATE FOREIGN TABLE hbf_np2 (
  p text OPTIONS (variable '?p'),
  o text OPTIONS (variable '?o')
)
SERVER linkedgeodata OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX dc: <http://purl.org/dc/terms/>

    SELECT * WHERE {
    {<http://linkedgeodata.org/triplify/node376142577> ?p ?o}
    UNION
    {<http://linkedgeodata.org/triplify/node376142577> dc:modified ?o}
    }
');

SELECT * FROM hbf_np2
WHERE p = 'http://geovocab.org/geometry#geometry';

/* non-pushable quer (LIMIT) */
CREATE FOREIGN TABLE hbf_np3 (
  p text OPTIONS (variable '?p'),
  o text OPTIONS (variable '?o')
)
SERVER linkedgeodata OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * WHERE {<http://linkedgeodata.org/triplify/node376142577> ?p ?o} LIMIT 10');

SELECT * FROM hbf_np3
WHERE p = 'http://www.w3.org/2000/01/rdf-schema#label';

/* non-pushable quer (ORDER BY) */
CREATE FOREIGN TABLE hbf_np4 (
  p text OPTIONS (variable '?p'),
  o text OPTIONS (variable '?o')
)
SERVER linkedgeodata OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * WHERE {<http://linkedgeodata.org/triplify/node376142577> ?p ?o} ORDER BY ?o');

SELECT * FROM hbf_np4
WHERE p = 'http://www.w3.org/2000/01/rdf-schema#label';

/* non-pushable quer (GROUP BY) */
CREATE FOREIGN TABLE hbf_np5 (
  p text OPTIONS (variable '?p'),
  c int OPTIONS (variable '?c')
)
SERVER linkedgeodata OPTIONS (
  log_sparql 'true',
  sparql 'SELECT ?p (count(?o) AS ?c) WHERE {<http://linkedgeodata.org/triplify/node376142577> ?p ?o} GROUP BY ?p');

SELECT * FROM hbf_np5
WHERE p = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#type' AND c > 1;

DROP SERVER linkedgeodata CASCADE;