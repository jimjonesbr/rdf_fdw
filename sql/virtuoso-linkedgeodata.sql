
DROP EXTENSION IF EXISTS rdf_fdw CASCADE;
CREATE EXTENSION rdf_fdw;

CREATE SERVER linkedgeodata 
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'http://linkedgeodata.org/sparql');

CREATE FOREIGN TABLE hbf (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER linkedgeodata OPTIONS (
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

/* SPARQL 17.4.1.1 - BOUND */
CREATE FOREIGN TABLE hbf2 (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o'),
  x rdfnode OPTIONS (variable '?x')
)
SERVER linkedgeodata OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * WHERE {<http://linkedgeodata.org/triplify/node376142577> ?p ?o OPTIONAL { ?o <http://foo.bar> ?x }}');

SELECT p, o, sparql.bound(p), sparql.bound(x)
FROM hbf2
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.langmatches(sparql.lang(o),'fr') AND
  sparql.bound(o) AND
  NOT sparql.bound(x);

/* SPARQL 17.4.1.3 - COALESCE */
SELECT p, o, x, sparql.coalesce(x, o, p)
FROM hbf2
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.coalesce(x, o) = '"Gare centrale de Leipzig"@fr' AND
  sparql.coalesce(x, x, o) = '"Gare centrale de Leipzig"@fr' AND
  sparql.coalesce(x, p) = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.coalesce(x, x, p) = '<http://www.w3.org/2000/01/rdf-schema#label>';

/* SPARQL 17.4.1.8 - sameTerm */
SELECT p, o, sparql.sameterm(o,'"Gare centrale de Leipzig"@fr')
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.sameterm(o,'"Gare centrale de Leipzig"@fr') AND
  sparql.sameterm(p,'<http://www.w3.org/2000/01/rdf-schema#label>');

/* SPARQL 17.4.1.9 - IN */
SELECT p, o
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  o IN ('"Gare centrale de Leipzig"@fr'::rdfnode, '"Leipzig Hbf"');

/* SPARQL 17.4.1.10 - NOT IN */
SELECT p, o
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  o NOT IN ('"foo"@es'::rdfnode, '"Berlin Hbf"', '"bar"^^xsd:string');

/* SPARQL 17.4.2.1 - isIRI */
SELECT p, o, sparql.isIRI(p) FROM hbf 
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.isIRI(p);

/* SPARQL 17.4.2.2 - isBlank */
SELECT p, o, sparql.isblank(o)
FROM hbf
WHERE sparql.isblank(o);

/* SPARQL 17.4.2.3 - isLiteral */
SELECT p, o, sparql.isliteral(o), sparql.isliteral(p)
FROM hbf
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.isliteral(o) AND 
  NOT sparql.isliteral(p);

/* SPARQL 17.4.2.4 - isNumeric */
SELECT p, o, sparql.isnumeric(o), sparql.isnumeric(p)
FROM hbf
WHERE 
  p = '<http://linkedgeodata.org/ontology/changeset>' AND
  sparql.isnumeric(o) AND
  NOT sparql.isnumeric(p);

/* SPARQL 17.4.2.5 - str */
SELECT p, o, sparql.str(o)
FROM hbf
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.str(o) = sparql.str('"Gare centrale de Leipzig"@fr');

/* SPARQL 17.4.2.6 - lang */
SELECT p, o, sparql.lang(o)
FROM hbf
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.lang(o) = sparql.lang('"Gare centrale de Leipzig"@fr');

/* SPARQL 17.4.2.7 - datatype */
SELECT p, o, sparql.datatype(o)
FROM hbf
WHERE
  p = '<http://linkedgeodata.org/ontology/version>' AND
  sparql.datatype(o) = sparql.datatype('"19"^^<http://www.w3.org/2001/XMLSchema#int>');

/* SPARQL 17.4.2.8 - IRI */
SELECT p, o, sparql.iri(p)
FROM hbf
WHERE 
  sparql.iri(p) = sparql.iri('http://linkedgeodata.org/ontology/short_name');

/* SPARQL 17.4.2.9 - BNODE */
SELECT p, o, sparql.bnode(o)
FROM hbf
WHERE 
  p = '<http://linkedgeodata.org/ontology/short_name>' AND
  sparql.isblank(sparql.bnode(o));

/* SPARQL 17.4.2.10 - STRDT */
SELECT p, o, sparql.strdt(o,'xsd:string')
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.strdt(o,'xsd:string') = sparql.strdt('"Gare centrale de Leipzig"@fr', 'xsd:string');

/* SPARQL 17.4.2.11 - STRLANG */
SELECT p, o, sparql.strlang(o,'en')
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.strlang(o,'en') = sparql.strlang('"Leipzig Hbf"', 'en');

/* SPARQL 17.4.2.12 - UUID (not pushable) */
SELECT sparql.uuid()::text ~ '^<urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}>$';

/*SPARQL 17.4.2.13 - STRUUID (not pushable) */
SELECT sparql.struuid()::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

/* SPARQL 17.4.3.2 - STRLEN */
SELECT p, o, sparql.strlen(o)
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.strlen(o) = sparql.strlen('"Leipzig Hbf"');

/* SPARQL 17.4.3.3 - SUBSTR */
SELECT p, o, sparql.substr(o, 9, 3)
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.substr(o, 9, 3) = sparql.substr('"Leipzig Hbf"', 9, 3);

/* SPARQL 17.4.3.4 - UCASE */
SELECT p, o, sparql.ucase(o)
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.ucase(o) = sparql.ucase('"Gare centrale de Leipzig"@fr');

/* SPARQL 17.4.3.5 - LCASE */
SELECT p, o, sparql.lcase(o)
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.lcase(o) = sparql.lcase('"Gare centrale de Leipzig"@fr');

/* SPARQL 17.4.3.6 - STRSTARTS */
SELECT p, o, sparql.strstarts(o, sparql.str('"Gare"@fr'))
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.strstarts(o,'"Gare"');

/* SPARQL 17.4.3.7 - STRENDS */
SELECT p, o, sparql.strends(o, sparql.str('"Leipzig"@fr'))
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.strends(o,'"Leipzig"');

/* SPARQL 17.4.3.8 - CONTAINS */
SELECT p, o, sparql.contains(o,'"Gare"@fr'), sparql.contains(o,'"Leipzig"^^xsd:string')
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND  
  sparql.contains(o,'"Gare"') AND
  sparql.contains(o,'"Leipzig"');

/* SPARQL 17.4.3.9 - STRBEFORE */
SELECT p, o, sparql.strbefore(sparql.str(o), '"Leipzig"')
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.strbefore(sparql.str(o), '"centrale"') = sparql.strbefore(sparql.str('"Gare centrale de Leipzig"@fr'),'"centrale"');

/* SPARQL 17.4.3.10 - STRAFTER */
SELECT p, o, sparql.strafter(sparql.str(o), '"Gare"')
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.strafter(sparql.str(o), '"centrale"') = sparql.strafter(sparql.str('"Gare centrale de Leipzig"@fr'),'"centrale"');

/* SPARQL 17.4.3.11 - ENCODE_FOR_URI */

SELECT p, o, sparql.encode_for_uri(o)
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.encode_for_uri(o) = sparql.encode_for_uri('"Gare centrale de Leipzig"@fr');

/* 17.4.3.12 - CONCAT */
SELECT p, o, sparql.concat(o,sparql.strlang(' Noir','fr')), sparql.concat(o,sparql.strdt(' Global','xsd:string'))
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.concat(o,'') = sparql.concat('"Gare centrale de"','" Leipzig"@fr');

/* SPARQL 17.4.3.13 - langMatches */
SELECT p, o, sparql.langmatches(sparql.lang(o),'*'),  sparql.langmatches(sparql.lang(o),'fr'),  sparql.langmatches(sparql.lang(o),'de')
FROM hbf 
WHERE sparql.langmatches(sparql.lang(o),'fr');

/* SPARQL 17.4.3.14 - REGEX */
SELECT p, o
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.regex(o, sparql.ucase('leipzig'), 'i') AND 
  sparql.regex(o, '^lEi','i') ;

/* SPARQL 17.4.3.15 - REPLACE */
SELECT p, o, sparql.replace(o,'Leipzig','Münster'), sparql.replace(o,'"Gare"@fr','')
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.replace(o,'Leipzig','Münster') = sparql.replace(sparql.strlang('Gare centrale de Leipzig','fr'),'Leipzig','Münster') AND
  sparql.replace(o, 'LEIPZIG', 'Münster','i') = sparql.replace('"Gare centrale de Leipzig"@fr', 'LEIPZIG', 'Münster','i');

/* SPARQL 17.4.4.1 - abs */
SELECT p, o, sparql.abs(o)
FROM hbf 
WHERE 
  p = sparql.iri('http://linkedgeodata.org/ontology/changeset') AND
  sparql.abs(o) = 32586907 AND
  sparql.abs(o) > 11111111 AND
  sparql.abs(o) >= 32586907 AND
  sparql.abs(o) <  99999999 AND
  sparql.abs(o) <=  32586907 AND
  sparql.abs(o) = '"32586907"^^xsd:int'::rdfnode AND
  sparql.abs(o) > '"11111111"^^xsd:int'::rdfnode AND
  sparql.abs(o) >= '"32586907"^^xsd:int'::rdfnode AND
  sparql.abs(o) <  '"99999999"^^xsd:int'::rdfnode AND
  sparql.abs(o) <=  '"32586907"^^xsd:int'::rdfnode AND
  32586907 = sparql.abs(o) AND
  '"32586907"^^xsd:int'::rdfnode = sparql.abs(o);

/* SPARQL 17.4.4.2 - round */
SELECT p, o, sparql.round(o)
FROM hbf 
WHERE 
  p = sparql.iri('http://www.w3.org/2003/01/geo/wgs84_pos#lat') AND
  sparql.round(o) = 51 AND
  sparql.round(o) > 01 AND
  sparql.round(o) >= 51 AND
  sparql.round(o) < 99 AND
  sparql.round(o) <= 51 AND
  sparql.round(o) = '"51"^^xsd:int'::rdfnode AND
  sparql.round(o) > '"01"^^xsd:int'::rdfnode AND
  sparql.round(o) >= '"51"^^xsd:int'::rdfnode AND
  sparql.round(o) < '"99"^^xsd:int'::rdfnode AND
  sparql.round(o) <= '"51"^^xsd:int'::rdfnode AND
  51 = sparql.round(o) AND
  '"51"^^xsd:int'::rdfnode = sparql.round(o);

/* SPARQL 17.4.4.3 - ceil */
SELECT p, o, sparql.ceil(o)
FROM hbf 
WHERE 
  p = sparql.iri('http://www.w3.org/2003/01/geo/wgs84_pos#lat') AND
  sparql.ceil(o) = 52 AND
  sparql.ceil(o) > 01 AND
  sparql.ceil(o) >= 52 AND
  sparql.ceil(o) < 99 AND
  sparql.ceil(o) <= 52 AND
  sparql.ceil(o) = '"52"^^xsd:int'::rdfnode AND
  sparql.ceil(o) > '"01"^^xsd:int'::rdfnode AND
  sparql.ceil(o) >= '"52"^^xsd:int'::rdfnode AND
  sparql.ceil(o) < '"99"^^xsd:int'::rdfnode AND
  sparql.ceil(o) <= '"52"^^xsd:int'::rdfnode AND
  52 = sparql.ceil(o) AND
  '"52"^^xsd:int'::rdfnode = sparql.ceil(o);

/* SPARQL 17.4.4.4 - floor */
SELECT p, o, sparql.floor(o)
FROM hbf 
WHERE 
  p = sparql.iri('http://www.w3.org/2003/01/geo/wgs84_pos#lat') AND
  sparql.floor(o) = 51 AND
  sparql.floor(o) > 01 AND
  sparql.floor(o) >= 51 AND
  sparql.floor(o) < 99 AND
  sparql.floor(o) <= 51 AND
  sparql.floor(o) = '"51"^^xsd:int'::rdfnode AND
  sparql.floor(o) > '"01"^^xsd:int'::rdfnode AND
  sparql.floor(o) >= '"51"^^xsd:int'::rdfnode AND
  sparql.floor(o) < '"99"^^xsd:int'::rdfnode AND
  sparql.floor(o) <= '"51"^^xsd:int'::rdfnode AND
  51 = sparql.floor(o) AND
  '"51"^^xsd:int'::rdfnode = sparql.floor(o);

/* SPARQL 17.4.4.5 - RAND */
SELECT setseed(0.42);
SELECT 
  sparql.lex(sparql.rand())::numeric BETWEEN 0.0 AND 1.0, 
  sparql.datatype(sparql.rand()) = '<http://www.w3.org/2001/XMLSchema#double>';

/* SPARQL 17.4.5.2 - year*/
SELECT p, o, sparql.year(o)
FROM hbf
WHERE 
  p = sparql.iri('http://purl.org/dc/terms/modified') AND
  sparql.year(o) = 2015 AND
  sparql.year(o) > 1000 AND
  sparql.year(o) < 9999 AND
  sparql.year(o) >= 2015 AND
  sparql.year(o) <= 2015 AND
  sparql.year(o) = sparql.year('"2015-07-12T20:41:25"^^xsd:dateTime') AND
  sparql.year(o) > sparql.year('"1000-01-12T20:00:00"^^xsd:dateTime') AND
  sparql.year(o) < sparql.year('"9999-01-12T20:00:00"^^xsd:dateTime') AND
  sparql.year(o) >= sparql.year('"2015-07-12T20:41:25"^^xsd:dateTime') AND
  sparql.year(o) <= sparql.year('"2015-07-12T20:41:25"^^xsd:dateTime');

/* SPARQL 17.4.5.3 - month */
SELECT p, o, sparql.month(o)
FROM hbf
WHERE 
  p = sparql.iri('http://purl.org/dc/terms/modified') AND
  sparql.month(o) = 07 AND
  sparql.month(o) > 01 AND
  sparql.month(o) < 12 AND
  sparql.month(o) >= 07 AND
  sparql.month(o) <= 07 AND
  sparql.month(o) = sparql.month('"2015-07-12T20:41:25"^^xsd:dateTime') AND
  sparql.month(o) > sparql.month('"1000-01-12T20:00:00"^^xsd:dateTime') AND
  sparql.month(o) < sparql.month('"9999-12-12T20:00:00"^^xsd:dateTime') AND
  sparql.month(o) >= sparql.month('"2015-07-12T20:41:25"^^xsd:dateTime') AND
  sparql.month(o) <= sparql.month('"2015-07-12T20:41:25"^^xsd:dateTime');

/* SPARQL 17.4.5.4 - day */
SELECT p, o, sparql.day(o)
FROM hbf
WHERE 
  p = sparql.iri('http://purl.org/dc/terms/modified') AND
  sparql.day(o) = 12 AND
  sparql.day(o) > 01 AND
  sparql.day(o) < 30 AND
  sparql.day(o) >= 12 AND
  sparql.day(o) <= 12 AND
  sparql.day(o) = sparql.day('"2015-07-12T20:41:25"^^xsd:dateTime') AND
  sparql.day(o) > sparql.day('"1000-01-01T20:00:00"^^xsd:dateTime') AND
  sparql.day(o) < sparql.day('"9999-12-30T20:00:00"^^xsd:dateTime') AND
  sparql.day(o) >= sparql.day('"2015-07-12T20:41:25"^^xsd:dateTime') AND
  sparql.day(o) <= sparql.day('"2015-07-12T20:41:25"^^xsd:dateTime');

/* SPARQL 7.4.5.5 - hours */
SELECT p, o, sparql.hours(o)
FROM hbf
WHERE 
  p = sparql.iri('http://purl.org/dc/terms/modified') AND
  sparql.hours(o) = 20 AND
  sparql.hours(o) > 01 AND
  sparql.hours(o) < 23 AND
  sparql.hours(o) >= 20 AND
  sparql.hours(o) <= 20 AND
  sparql.hours(o) = sparql.hours('"2015-07-12T20:41:25"^^xsd:dateTime') AND
  sparql.hours(o) > sparql.hours('"1000-01-01T01:00:00"^^xsd:dateTime') AND
  sparql.hours(o) < sparql.hours('"9999-12-30T23:00:00"^^xsd:dateTime') AND
  sparql.hours(o) >= sparql.hours('"2015-07-12T20:41:25"^^xsd:dateTime') AND
  sparql.hours(o) <= sparql.hours('"2015-07-12T20:41:25"^^xsd:dateTime');

/* SPARQL 17.4.5.6 - minutes */
SELECT p, o, sparql.minutes(o)
FROM hbf
WHERE 
  p = sparql.iri('http://purl.org/dc/terms/modified') AND
  sparql.minutes(o) = 41 AND
  sparql.minutes(o) > 01 AND
  sparql.minutes(o) < 59 AND
  sparql.minutes(o) >= 41 AND
  sparql.minutes(o) <= 41 AND
  sparql.minutes(o) = sparql.minutes('"2015-07-12T20:41:25"^^xsd:dateTime') AND
  sparql.minutes(o) > sparql.minutes('"1000-01-01T01:01:00"^^xsd:dateTime') AND
  sparql.minutes(o) < sparql.minutes('"9999-12-30T23:59:00"^^xsd:dateTime') AND
  sparql.minutes(o) >= sparql.minutes('"2015-07-12T20:41:25"^^xsd:dateTime') AND
  sparql.minutes(o) <= sparql.minutes('"2015-07-12T20:41:25"^^xsd:dateTime');

/* SPARQL 17.4.5.7 - seconds */
SELECT p, o, sparql.minutes(o)
FROM hbf
WHERE 
  p = sparql.iri('http://purl.org/dc/terms/modified') AND
  sparql.seconds(o) = 25 AND
  sparql.seconds(o) > 01 AND
  sparql.seconds(o) < 59 AND
  sparql.seconds(o) >= 25 AND
  sparql.seconds(o) <= 25 AND
  sparql.seconds(o) = sparql.seconds('"2015-07-12T20:41:25"^^xsd:dateTime') AND
  sparql.seconds(o) > sparql.seconds('"1000-01-01T01:01:00"^^xsd:dateTime') AND
  sparql.seconds(o) < sparql.seconds('"9999-12-30T23:59:59"^^xsd:dateTime') AND
  sparql.seconds(o) >= sparql.seconds('"2015-07-12T20:41:25"^^xsd:dateTime') AND
  sparql.seconds(o) <= sparql.seconds('"2015-07-12T20:41:25"^^xsd:dateTime');

/* SPARQL 17.4.5.8 - timezone */
SELECT sparql.timezone('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');

/* SPARQL 7.4.5.9 - tz */
SELECT sparql.tz('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');

/* SPARQL 17.4.6.1 - MD5 */
SELECT p, o, sparql.md5(o)
FROM hbf
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.md5(o) = sparql.md5('"Leipzig Hbf"');