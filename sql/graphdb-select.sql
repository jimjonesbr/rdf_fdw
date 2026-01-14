\pset null '(null)'

CREATE SERVER graphdb
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint   'http://graphdb:7200/repositories/test',
  update_url 'http://graphdb:7200/repositories/test/statements');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER graphdb OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * WHERE {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .'
);

CREATE USER MAPPING FOR postgres
SERVER graphdb OPTIONS (user 'admin', password 'secret');

INSERT INTO ft (subject, predicate, object)
VALUES  ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Westfälische Wilhelms-Universität Münster"@de'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"University of Münster"@en'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Univerrrsity of Münsterrr"@en-US'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Univêrsity of Münsta"@en-GB'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#time>', '"18:18:42"^^<http://www.w3.org/2001/XMLSchema#time>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/established>', '"1780-04-16"^^<http://www.w3.org/2001/XMLSchema#date>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/modified>', '"2025-12-24T18:30:42"^^<http://www.w3.org/2001/XMLSchema#dateTime>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/ontology/wikiPageExtracted>', '"2025-12-24T13:00:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2003/01/geo/wgs84_pos#lat>', '"51.9636"^^<http://www.w3.org/2001/XMLSchema#float>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2003/01/geo/wgs84_pos#long>', '"7.6136"^^<http://www.w3.org/2001/XMLSchema#float>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/rector>', '"Johannes Wessels"'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/state>', '<http://dbpedia.org/resource/North_Rhine-Westphalia>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/city>', '<http://dbpedia.org/resource/Münster>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"Hello 👋 PostgreSQL 🐘"@en'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"unknown literal type"^^<http://www.w3.org/2001/XMLSchema#UNKNOWN>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"explicit string literal"^^<http://www.w3.org/2001/XMLSchema#string>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '""'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '". <= pontos => ."@pt'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"\n <= salto de línea => \n"@es'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"\" <= double-quotes => \""@en'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"\t <= Tabulatorzeichen => \t"@de'),        
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/administrativeStaff>', '"1924"^^<http://www.w3.org/2001/XMLSchema#short>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/students>', '"49098"^^<http://www.w3.org/2001/XMLSchema#int>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/academicStaff>', '"4956"^^<http://www.w3.org/2001/XMLSchema#int>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/budget>', '"803600000"^^<http://www.w3.org/2001/XMLSchema#long>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/tuition>', '"1500.00"^^<http://www.w3.org/2001/XMLSchema#double>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/veryLargeNumber>', '"9999999999999999999"^^<http://www.w3.org/2001/XMLSchema#decimal>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/verySmallNumber>', '"0.000000000000001"^^<http://www.w3.org/2001/XMLSchema#decimal>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/ontology/restingDate>', '"2024-02-29"^^<http://www.w3.org/2001/XMLSchema#date>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/ontology/internationally>', '"true"^^<http://www.w3.org/2001/XMLSchema#boolean>');

SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>'
ORDER BY predicate;

/* SPARQL 17.4.1.7 - RDFterm-equal */
SELECT * FROM ft
WHERE sparql.sameterm(object, sparql.iri('http://dbpedia.org/resource/North_Rhine-Westphalia'));

/* SPARQL 17.4.1.9 - IN */
SELECT * FROM ft
WHERE object IN (sparql.iri('http://dbpedia.org/resource/North_Rhine-Westphalia'),
                 sparql.iri('http://dbpedia.org/resource/Münster'));

CREATE TEMPORARY TABLE tmp (c rdfnode, o rdfnode);
INSERT INTO tmp (c, o)
VALUES (8036::rdfnode,'<http://dbpedia.org/resource/North_Rhine-Westphalia>');

SELECT * FROM ft
WHERE object IN (SELECT o FROM tmp);

SELECT ft.* FROM ft, tmp
WHERE object IN (tmp.o, 
                 'Some Other Literal'::rdfnode,
                 sparql.strdt(sparql.concat(tmp.c, '00000'::rdfnode), 'http://www.w3.org/2001/XMLSchema#long')) AND
      subject = '<https://www.uni-muenster.de>';

/* SPARQL 17.4.1.10 - NOT IN */
SELECT * FROM ft
WHERE 
  subject = '<https://www.uni-muenster.de>' AND
  predicate NOT IN ('<http://www.w3.org/2000/01/rdf-schema#comment>',
                        '<http://dbpedia.org/property/name>');

/* SPARQL 18.2.5.3 - DISTINCT */
SELECT DISTINCT predicate
FROM ft
ORDER BY predicate;

SELECT DISTINCT object
FROM ft
WHERE sparql.lang(object) = 'de';

/* SPARQL 15.5 - LIMIT */
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>'
FETCH FIRST ROW ONLY;

SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>'
FETCH FIRST 3 ROWS ONLY;

SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>'
LIMIT 3;

/* SPARQL 15.4 - OFFSET */
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>'
OFFSET 2
FETCH FIRST 3 ROWS ONLY;

SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>'
OFFSET 2
LIMIT 3;

/* SPARQL 15.1 - ORDER BY */
SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>'
ORDER BY object ASC
FETCH FIRST 3 ROWS ONLY;

SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>'
ORDER BY object DESC
FETCH FIRST 3 ROWS ONLY;

SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>'
ORDER BY object, predicate
FETCH FIRST 3 ROWS ONLY;

SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>'
ORDER BY object DESC, predicate ASC
FETCH FIRST 3 ROWS ONLY;

/* SPARQL 18.2.5.3 - DISTINCT */
SELECT DISTINCT subject
FROM ft
WHERE subject = sparql.iri('https://www.uni-muenster.de');

SELECT DISTINCT ON (predicate) predicate, object -- DISTINCT ON not supported in SPARQL
FROM ft
WHERE subject = sparql.iri('https://www.uni-muenster.de');

/* SPARQL - 17.3 Operator Mapping (text) */
SELECT * FROM ft
WHERE
  predicate = '<http://dbpedia.org/property/name>' AND
  sparql.str(object) >= 'Westfälische' AND
  sparql.str(object) <= 'Westfälische ZZZ' AND
  sparql.str(object) BETWEEN 'Westfälische' AND 'Westfälische ZZZ';

/* SPARQL - 17.3 Operator Mapping (rdfnode) */
SELECT * FROM ft
WHERE
  predicate = '<http://dbpedia.org/property/name>'::rdfnode AND
  sparql.str(object) >= 'Westfälische'::rdfnode AND
  sparql.str(object) <= 'Westfälische ZZZ'::rdfnode AND
  sparql.str(object) BETWEEN 'Westfälische'::rdfnode AND 'Westfälische ZZZ'::rdfnode;

/* SPARQL - 17.3 Operator Mapping (rdfnode, plain literal) */
SELECT * FROM ft
WHERE object = 'Johannes Wessels'::rdfnode;

/* SPARQL - 17.3 Operator Mapping (rdfnode, typed literal) */
SELECT * FROM ft
WHERE object = sparql.strdt('Johannes Wessels', 'http://www.w3.org/2001/XMLSchema#string');

/* SPARQL - 17.3 Operator Mapping (smallint) */
SELECT * FROM ft
WHERE object = 1924::smallint;

SELECT * FROM ft
WHERE object > 1900::smallint;

SELECT * FROM ft
WHERE object < 2000::smallint;

SELECT * FROM ft
WHERE object BETWEEN 1900::smallint AND 2000::smallint;

/* SPARQL - 17.3 Operator Mapping (int) */
SELECT * FROM ft
WHERE object = 49098::int;

SELECT * FROM ft
WHERE object > 40000::int;

SELECT * FROM ft
WHERE object < 60000::int;

SELECT * FROM ft
WHERE object BETWEEN 40000::int AND 60000::int;

/* SPARQL - 17.3 Operator Mapping (bigint) */
SELECT * FROM ft
WHERE object = 803600000::bigint;

SELECT * FROM ft
WHERE object > 800000000::bigint;

SELECT * FROM ft
WHERE object < 900000000::bigint;

SELECT * FROM ft
WHERE object BETWEEN 800000000::bigint AND 900000000::bigint;

/* SPARQL - 17.3 Operator Mapping (real) */
SELECT * FROM ft
WHERE object = 51.9636::real;

SELECT * FROM ft
WHERE object > 50.0::real;

SELECT * FROM ft
WHERE object < 52.0::real;

SELECT * FROM ft
WHERE object BETWEEN 50.0::real AND 52.0::real;

/* SPARQL - 17.3 Operator Mapping (double precision) */
SELECT * FROM ft
WHERE object = 51.9636::double precision;

SELECT * FROM ft
WHERE object > 50.0::double precision;

SELECT * FROM ft
WHERE object < 52.0::double precision;

SELECT * FROM ft
WHERE object BETWEEN 50.0::double precision AND 52.0::double precision;

/* SPARQL - 17.3 Operator Mapping (numeric) */
SELECT * FROM ft
WHERE object = 51.9636::numeric::rdfnode;

SELECT * FROM ft
WHERE object > 50.0::numeric::rdfnode;

SELECT * FROM ft
WHERE object < 52.0::numeric::rdfnode;

SELECT * FROM ft
WHERE object BETWEEN 50.0::numeric::rdfnode AND 52.0::numeric::rdfnode;

/* SPARQL - 17.3 Operator Mapping (timestamp) */
SELECT * FROM ft
WHERE object = '2025-12-24 18:30:42'::timestamp;

SELECT * FROM ft
WHERE object > '2025-01-01 00:00:00'::timestamp;

SELECT * FROM ft
WHERE object < '2025-12-31 23:59:59'::timestamp;

SELECT * FROM ft
WHERE object BETWEEN '2025-01-01 00:00:00'::timestamp AND '2025-12-31 23:59:59'::timestamp;

/* SPARQL - 17.3 Operator Mapping (timestamptz) */
SELECT * FROM ft
WHERE object = '"2025-12-24T13:00:42+00:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode;

SELECT * FROM ft
WHERE object > '"2025-01-01T00:00:00+00:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode;

SELECT * FROM ft
WHERE object < '"2025-12-31T23:59:59+00:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode;

SELECT * FROM ft
WHERE object BETWEEN '"2025-01-01T00:00:00+00:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode AND '"2025-12-31T23:59:59+00:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode;

/* SPARQL - 17.3 Operator Mapping (date) */
SELECT * FROM ft
WHERE object = '1780-04-16'::date;

SELECT * FROM ft
WHERE object > '1780-01-01'::date;

SELECT * FROM ft
WHERE object < '1780-12-31'::date;

SELECT * FROM ft
WHERE object BETWEEN '1780-01-01'::date AND '1780-12-31'::date;

/* SPARQL - 17.3 Operator Mapping (time) */
SELECT * FROM ft
WHERE object = '18:18:42'::time;

SELECT * FROM ft
WHERE object > '12:00:00'::time;

SELECT * FROM ft
WHERE object < '23:59:59'::time;

SELECT * FROM ft
WHERE object BETWEEN '12:00:00'::time AND '23:59:59'::time;

/* SPARQL - 17.3 Operator Mapping (timetz) */

/* SPARQL - 17.3 Operator Mapping (boolean) */
SELECT * FROM ft
WHERE
  predicate = '<http://dbpedia.org/ontology/internationally>' AND
  object = '"true"^^<http://www.w3.org/2001/XMLSchema#boolean>'::rdfnode;

SELECT * FROM ft 
WHERE
  predicate = '<http://dbpedia.org/ontology/internationally>' AND
  object <> '"false"^^<http://www.w3.org/2001/XMLSchema#boolean>'::rdfnode;

SELECT * FROM ft
WHERE
  predicate = '<http://dbpedia.org/ontology/internationally>' AND
  object = true;

SELECT * FROM ft
WHERE
  predicate = '<http://dbpedia.org/ontology/internationally>' AND
  object <> false;

--===================================================================================--

/* SPARQL 17.4.1.1 - BOUND */
/* Note: Testing NOT BOUND requires OPTIONAL patterns, skipping for simple triple pattern */
-- SELECT * FROM ft
-- WHERE NOT sparql.bound(object);

/* SPARQL 17.4.1.3 - COALESCE */
SELECT * FROM ft
WHERE sparql.coalesce(object, '"Default Value"') = '"Westfälische Wilhelms-Universität Münster"@de';

/* SPARQL 17.4.1.8 - sameTerm */
SELECT * FROM ft
WHERE sparql.sameterm(object, '1780-04-16'::date::rdfnode);

/* SPARQL 17.4.2.1 - isIRI */
SELECT * FROM ft
WHERE 
  sparql.isiri(object) AND
  predicate = '<http://dbpedia.org/property/state>';

/* SPARQL 17.4.2.2 - isBlank */
SELECT * FROM ft
WHERE sparql.isblank(subject);

/* SPARQL 17.4.2.3 - isLiteral */
SELECT * FROM ft
WHERE sparql.isliteral(object)
ORDER BY predicate;

/* SPARQL 17.4.2.4 - isNumeric */
SELECT * FROM ft
WHERE sparql.isnumeric(object);

/* SPARQL 17.4.2.5 - str */
SELECT * FROM ft
WHERE sparql.str(object) = 'Westfälische Wilhelms-Universität Münster';

/* SPARQL 17.4.2.6 - lang */
SELECT * FROM ft
WHERE sparql.lang(object) = 'de';

/* SPARQL 17.4.2.7 - datatype */
SELECT * FROM ft
WHERE sparql.datatype(object) = '<http://www.w3.org/2001/XMLSchema#date>';

/* SPARQL 17.4.2.8 - IRI */
SELECT * FROM ft
WHERE sparql.iri('http://dbpedia.org/resource/Münster') = object;

/* SPARQL 17.4.2.9 - BNODE */
SELECT * FROM ft
WHERE sparql.bnode('_:bnode1') != subject
LIMIT 1; 

/* SPARQL 17.4.2.10 - STRDT */
SELECT * FROM ft
WHERE sparql.strdt('1780-04-16', 'http://www.w3.org/2001/XMLSchema#date') = object;

/* SPARQL 17.4.2.11 - STRLANG */
SELECT * FROM ft
WHERE sparql.strlang('Westfälische Wilhelms-Universität Münster', 'de') = object;

/* SPARQL 17.4.3.2 - STRLEN */
SELECT * FROM ft
WHERE 
  predicate = '<http://www.w3.org/2000/01/rdf-schema#comment>' AND
  sparql.strlen(sparql.str(object)) >= 25;

SELECT * FROM ft
WHERE 
  predicate = '<http://www.w3.org/2000/01/rdf-schema#comment>' AND
  sparql.strlen(object) = 20;  -- emoji counts as 1 char each

/* SPARQL 17.4.3.3 - SUBSTR */
SELECT * FROM ft
WHERE sparql.substr(sparql.str(object), 1, 9) = 'Westfälis';

SELECT * FROM ft
WHERE sparql.substr(object, 7, 2) = sparql.strlang('👋 ','en');

/* SPARQL 17.4.3.4 - UCASE */
SELECT * FROM ft
WHERE sparql.ucase(object) = sparql.strlang('WESTFÄLISCHE WILHELMS-UNIVERSITÄT MÜNSTER', 'de');

/* SPARQL 17.4.3.5 - LCASE */
SELECT * FROM ft
WHERE sparql.lcase(object) = sparql.strlang('westfälische wilhelms-universität münster', 'de');

/* SPARQL 17.4.3.6 - STRSTARTS */
SELECT * FROM ft
WHERE sparql.strstarts(sparql.str(object), 'Westfäl');

/* SPARQL 17.4.3.7 - STRENDS */
SELECT * FROM ft
WHERE sparql.strends(sparql.str(object), 'Münster');

/* SPARQL 17.4.3.8 - CONTAINS */
SELECT * FROM ft
WHERE sparql.contains(object, '"Wilhelms"@de');

SELECT * FROM ft
WHERE sparql.contains(object, E'"\t <= Tabulator"@de');

SELECT * FROM ft
WHERE sparql.contains(object, '". <= pontos"@pt');

SELECT * FROM ft
WHERE sparql.contains(object, E'"\n <= salto"@es');

SELECT * FROM ft
WHERE sparql.contains(object, '"\" <= double"@en');

/* SPARQL 17.4.3.9 - STRBEFORE */
SELECT * FROM ft
WHERE sparql.strbefore(sparql.str(object), ' Wilhelms') = 'Westfälische';

SELECT * FROM ft 
WHERE 
  predicate = '<http://www.w3.org/2000/01/rdf-schema#comment>' AND
  sparql.strbefore(object, 'NOTFOUND') = '""'::rdfnode;

/* SPARQL 17.4.3.10 - STRAFTER */
SELECT * FROM ft
WHERE sparql.strafter(sparql.str(object), 'Westfälische ') = 'Wilhelms-Universität Münster';

SELECT * FROM ft 
WHERE 
  predicate = '<http://www.w3.org/2000/01/rdf-schema#comment>' AND
  sparql.strafter(object, 'NOTFOUND') = '""'::rdfnode;

/* SPARQL 17.4.3.11 - ENCODE_FOR_URI */
SELECT * FROM ft
WHERE sparql.encode_for_uri(sparql.str(object)) = 'Westf%C3%A4lische%20Wilhelms-Universit%C3%A4t%20M%C3%BCnster';

/* SPARQL 17.4.3.12 - CONCAT */
SELECT * FROM ft
WHERE sparql.concat(sparql.str(object), ', Deutschland') = 'Westfälische Wilhelms-Universität Münster, Deutschland';

SELECT *, sparql.concat(object, ', ', '"Cześć"@pl') FROM ft
WHERE
  predicate = '<http://www.w3.org/2000/01/rdf-schema#comment>' AND
  sparql.concat(object, ', ', '"Cześć"@pl'::rdfnode) = '"Hello 👋 PostgreSQL 🐘, Cześć"';

/* Note: CONCAT on unknown datatype doesn't preserve the datatype in SPARQL */
SELECT sparql.concat(object, ', ', 'after concat'::rdfnode) FROM ft
WHERE
  predicate = '<http://www.w3.org/2000/01/rdf-schema#comment>' AND
  sparql.datatype(object) = '<http://www.w3.org/2001/XMLSchema#UNKNOWN>';

SELECT *, sparql.concat(object, ', ', 'after concat'::rdfnode) FROM ft
WHERE
  predicate = '<http://www.w3.org/2000/01/rdf-schema#comment>' AND
  sparql.datatype(object) = '<http://www.w3.org/2001/XMLSchema#string>';

SELECT object, sparql.datatype(object) FROM ft
WHERE
  predicate = '<http://www.w3.org/2000/01/rdf-schema#comment>';

/* SPARQL 17.4.3.13 - langMatches */
SELECT * FROM ft
WHERE sparql.langmatches(sparql.lang(object), 'de');

SELECT * FROM ft
WHERE sparql.langmatches(sparql.lang(object), 'en');

SELECT * FROM ft
WHERE sparql.langmatches(sparql.lang(object), 'en-US');

SELECT * FROM ft
WHERE sparql.langmatches(sparql.lang(object), 'en-*');

/* SPARQL 17.4.3.15 - REPLACE */
SELECT * FROM ft
WHERE sparql.replace(sparql.str(object), 'Westfälische Wilhelms-Universität', 'WWU') = 'WWU Münster';

/* SPARQL 17.4.4.1 - abs */
SELECT * FROM ft
WHERE sparql.abs(object) = 51.9636::numeric::rdfnode;

/* SPARQL 17.4.4.2 - round */
SELECT * FROM ft
WHERE sparql.round(object) = 52::numeric::rdfnode;

/* SPARQL 17.4.4.3 - ceil */
SELECT * FROM ft
WHERE sparql.ceil(object) = 52::numeric::rdfnode;

/* SPARQL 17.4.4.4 - floor */
SELECT * FROM ft
WHERE sparql.floor(object) = 51::numeric::rdfnode;

/* SPARQL 17.4.4.5 - RAND */
SELECT setseed(0.42);
SELECT 
  sparql.lex(sparql.rand())::numeric BETWEEN 0.0 AND 1.0, 
  sparql.datatype(sparql.rand()) = '<http://www.w3.org/2001/XMLSchema#double>';

/* SPARQL 17.4.5.2 - year */
SELECT * FROM ft
WHERE sparql.year(object) = 1780::numeric::rdfnode;

SELECT * FROM ft
WHERE sparql.year(object) + 1 = 2026;

/* SPARQL 17.4.5.3 - month */
SELECT * FROM ft
WHERE sparql.month(object) = 4::numeric::rdfnode;

/* SPARQL 17.4.5.4 - day */
SELECT * FROM ft
WHERE sparql.day(object) = 16::numeric::rdfnode;

/* SPARQL 7.4.5.5 - hours */
SELECT * FROM ft
WHERE sparql.hours(object) = 18::numeric::rdfnode;

/* SPARQL 17.4.5.6 - minutes */
SELECT * FROM ft
WHERE sparql.minutes(object) = 30::numeric::rdfnode;

/* SPARQL 17.4.5.7 - seconds */
SELECT * FROM ft
WHERE sparql.seconds(object) = 42::numeric::rdfnode;

/* SPARQL 17.4.5.8 - timezone */
SELECT * FROM ft
WHERE sparql.timezone(object) = '"PT0S"^^<http://www.w3.org/2001/XMLSchema#dayTimeDuration>';

/* SPARQL 17.4.5.9 - tz */
SELECT * FROM ft
WHERE sparql.tz(object) = 'Z'::rdfnode;

/* SPARQL 17.4.6.1 - MD5 */
SELECT * FROM ft
WHERE sparql.md5(sparql.str(object)) = '6c0bdbd38fc0772abda6fa1c98b74990'::rdfnode;

/* SPARQL Aggregate SUM */
SELECT sparql.sum(object) AS obj_count
FROM ft
WHERE sparql.isnumeric(object);

/* SPARQL Aggregate AVG */
SELECT sparql.avg(object) AS obj_avg
FROM ft
WHERE sparql.isnumeric(object);

/* SPARQL Aggregate MIN */
SELECT sparql.min(object) AS obj_min
FROM ft
WHERE sparql.isnumeric(object);

/* SPARQL Aggregate MAX */
SELECT sparql.max(object) AS obj_max
FROM ft
WHERE sparql.isnumeric(object);

/* SPARQL Aggregate GROUP_CONCAT */
SELECT sparql.group_concat(object, ' | ') AS obj_list
FROM ft
WHERE sparql.isliteral(object);

SELECT sparql.group_concat(object, '') AS obj_list
FROM ft
WHERE sparql.isliteral(object);

/* SPARQL Aggregate SAMPLE */
SELECT sparql.sample(object) AS obj_sample
FROM ft
WHERE sparql.isliteral(object);

/* Custom Function LEX */
SELECT subject, predicate, sparql.lex(object)
FROM ft
WHERE sparql.isliteral(object);

-- Empty literals in various contexts
SELECT * FROM ft WHERE object = '""'::rdfnode;
SELECT * FROM ft WHERE sparql.strlen(object) = 0;
SELECT * FROM ft WHERE sparql.substr(object, 1, 0) = '""'::rdfnode;

-- Very large/small decimals
SELECT * FROM ft
WHERE object = 9999999999999999999::numeric::rdfnode
ORDER BY predicate;

SELECT * FROM ft
WHERE object = 0.000000000000001::numeric::rdfnode
ORDER BY predicate;

SELECT * FROM ft
WHERE object BETWEEN 0.000000000000001::numeric::rdfnode AND 1000000000000000000::numeric::rdfnode
ORDER BY predicate;

-- Leap year dates
SELECT * FROM ft
WHERE sparql.month(object) = 2 AND sparql.day(object) = 29;

-- NOT conditions
SELECT * FROM ft
WHERE NOT sparql.isiri(object) AND
      NOT sparql.isblank(object) AND
      NOT sparql.isnumeric(object) AND
      NOT sparql.langmatches(sparql.lang(object), 'en');

-- SELECT ... INTO TEMPORARY TABLE
SELECT subject, predicate, object
INTO TEMPORARY TABLE tmp2
FROM ft
WHERE subject = '<https://www.uni-muenster.de>';
SELECT count(*) FROM tmp2;

-- SELECT ... INTO TABLE
SELECT subject, predicate, object
INTO TABLE t2
FROM ft
WHERE subject = '<https://www.uni-muenster.de>';
SELECT count(*) FROM t2;
DROP TABLE t2;

-- Nested function calls
SELECT * FROM ft
WHERE 
  predicate = '<http://dbpedia.org/property/name>' AND
  object = '"Westfälische Wilhelms-Universität Münster"@de' AND
  sparql.isnumeric(
    sparql.round(
      sparql.strlen(
        sparql.substr(
          sparql.str(object), 1, 9))));

-- EXPLAIN of a query
EXPLAIN (COSTS OFF)
SELECT * FROM ft
WHERE 
  predicate = '<http://dbpedia.org/property/name>' AND
  object = '"Westfälische Wilhelms-Universität Münster"@de' AND
  subject::text = '<https://www.uni-muenster.de>';

/* Invalid SPARQL query test */
CREATE FOREIGN TABLE ft_invalid_sparql (
  s rdfnode OPTIONS (variable '?s'),
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o') 
)
SERVER graphdb OPTIONS (
  sparql 'SELECT * WHERE {?s ?p }' -- missing object in triple pattern
);

SELECT * FROM ft_invalid_sparql;

/* invalid SERVER url */
CREATE SERVER server_invalid_url
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint   'http://10.10.70.80:9999/repositories/test',
  update_url 'http://10.10.70.80:9999/repositories/test/statements',
  connect_timeout '1'
);

CREATE FOREIGN TABLE ft_server_invalid_url (
  s rdfnode OPTIONS (variable '?s'),
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o') 
)
SERVER server_invalid_url OPTIONS (
  sparql 'SELECT * WHERE {?s ?p ?o}'
);

SELECT * FROM ft_server_invalid_url;

/* cleanup */
DELETE FROM ft;
DROP SERVER server_invalid_url CASCADE;
DROP SERVER graphdb CASCADE;