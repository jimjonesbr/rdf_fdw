SET timezone TO 'Etc/UTC';

/*
 * Pushdown regression tests.
 * All queries use EXPLAIN (VERBOSE, COSTS OFF) - no network calls are made.
 * This validates SQL-to-SPARQL translation for every pushable construct
 * without depending on any external triple store.
 */

CREATE SERVER test_server
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (endpoint 'http://localhost/sparql');

/* ----------------------------------------------------------------
 * rdfnode_ft  — rdfnode column pushdown tests
 * ---------------------------------------------------------------- */
CREATE FOREIGN TABLE rdfnode_ft (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER test_server OPTIONS (
  sparql 'SELECT * WHERE {<http://example.org/s> ?p ?o}');

/* rdfnode_opt_ft — BOUND / COALESCE tests (needs OPTIONAL binding) */
CREATE FOREIGN TABLE rdfnode_opt_ft (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o'),
  x rdfnode OPTIONS (variable '?x')
)
SERVER test_server OPTIONS (
  sparql 'SELECT * WHERE {<http://example.org/s> ?p ?o OPTIONAL {?o <http://foo.bar> ?x}}');

/* ----------------------------------------------------------------
 * pgtypes_ft  — pg-typed column pushdown tests
 * ---------------------------------------------------------------- */
CREATE FOREIGN TABLE pgtypes_ft (
  label        text             OPTIONS (variable '?label',   language '*'),
  version      bigint           OPTIONS (variable '?version', literaltype 'xsd:integer'),
  num_smallint smallint         OPTIONS (variable '?sint',    literaltype 'xsd:short'),
  num_int      int              OPTIONS (variable '?int',     literaltype 'xsd:int'),
  num_real     real             OPTIONS (variable '?real',    literaltype 'xsd:float'),
  num_double   double precision OPTIONS (variable '?double',  literaltype 'xsd:double'),
  num_numeric  numeric          OPTIONS (variable '?numeric', literaltype 'xsd:decimal'),
  modified     timestamp        OPTIONS (variable '?modified',literaltype 'xsd:dateTime'),
  tstz         timestamptz      OPTIONS (variable '?tstz',    literaltype 'xsd:dateTime'),
  dt           date             OPTIONS (variable '?dt',      literaltype 'xsd:date'),
  ttz          timetz           OPTIONS (variable '?ttz',     literaltype 'xsd:time'),
  bl           boolean          OPTIONS (variable '?bl',      literaltype 'xsd:boolean'),
  type         text             OPTIONS (variable '?type',    nodetype 'iri')
)
SERVER test_server OPTIONS (
  sparql 'SELECT * WHERE {<http://example.org/s> ?p ?o}');


/* ================================================================
 * SPARQL 15.5 - LIMIT
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
LIMIT 5;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
FETCH FIRST 5 ROWS ONLY;

/* ================================================================
 * SPARQL 15.4 - OFFSET
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
OFFSET 5 LIMIT 10;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
OFFSET 5 ROWS FETCH FIRST 10 ROWS ONLY;

/* ================================================================
 * SPARQL 15.1 - ORDER BY
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
ORDER BY p DESC
LIMIT 3;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
ORDER BY o ASC
LIMIT 3;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
ORDER BY p DESC, o ASC
LIMIT 3;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
ORDER BY p DESC, o ASC
OFFSET 5 LIMIT 2;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
ORDER BY 1 DESC, 2 ASC
OFFSET 5 LIMIT 10;

/* ================================================================
 * SPARQL 18.2.5.3 - DISTINCT
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT DISTINCT p FROM rdfnode_ft
WHERE p = '<http://www.w3.org/2000/01/rdf-schema#label>';

-- DISTINCT ON is not supported and won't be pushed down
EXPLAIN (VERBOSE, COSTS OFF)
SELECT DISTINCT ON (p) p, o FROM rdfnode_ft
WHERE p = '<http://www.w3.org/2000/01/rdf-schema#label>';

/* ================================================================
 * SPARQL 17.4.1.7 - RDFterm-equal
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  o = '"hello"@en';

/* ================================================================
 * SPARQL 17.4.1.9 - IN
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  o IN ('"hello"@en'::rdfnode, '"hello"@fr', sparql.strlang('hello', 'de'));

/* ================================================================
 * SPARQL 17.4.1.10 - NOT IN
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  o NOT IN ('"hello"@en'::rdfnode, '"hello"@fr', sparql.strlang('hello', 'de'))
LIMIT 5;

/* ================================================================
 * SPARQL 17.3 - Operator Mapping (text op rdfnode)
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  o > '"a"' AND
  o < '"z"' AND
  o >= '"a"' AND
  o <= '"z"' AND
  o <> '"foo"' AND
  sparql.str(o) BETWEEN '"a"' AND '"z"'
LIMIT 3;

/* SPARQL 17.3 - Operator Mapping (rdfnode op rdfnode) */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://www.w3.org/2000/01/rdf-schema#label>'::rdfnode AND
  o > '"a"'::rdfnode AND
  o < '"z"'::rdfnode AND
  o >= '"a"'::rdfnode AND
  o <= '"z"'::rdfnode AND
  o <> '"foo"'::rdfnode AND
  sparql.str(o) BETWEEN '"a"'::rdfnode AND '"z"'::rdfnode
LIMIT 3;

/* SPARQL 17.3 - Operator Mapping (smallint op rdfnode) */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://example.org/count>'::rdfnode AND
  o = 100::smallint AND
  o <> 999::smallint AND
  o > 10::smallint AND
  o < 999::smallint AND
  o >= 100::smallint AND
  o <= 100::smallint AND
  o BETWEEN 10::smallint AND 200::smallint AND
  100::smallint = o;

/* SPARQL 17.3 - Operator Mapping (int op rdfnode) */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://example.org/count>'::rdfnode AND
  o = 100::int AND
  o <> 999::int AND
  o > 10::int AND
  o < 999::int AND
  o >= 100::int AND
  o <= 100::int AND
  o BETWEEN 10::int AND 200::int AND
  100::int = o;

/* SPARQL 17.3 - Operator Mapping (bigint op rdfnode) */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://example.org/count>'::rdfnode AND
  o = 100::bigint AND
  o <> 999::bigint AND
  o > 10::bigint AND
  o < 999::bigint AND
  o >= 100::bigint AND
  o <= 100::bigint AND
  o BETWEEN 10::bigint AND 200::bigint AND
  100::bigint = o;

/* SPARQL 17.3 - Operator Mapping (real op rdfnode) */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://example.org/measure>'::rdfnode AND
  o = 1.5::real AND
  o <> 9.9::real AND
  o > 1.0::real AND
  o < 9.9::real AND
  o >= 1.5::real AND
  o <= 1.5::real AND
  o BETWEEN 1.0::real AND 2.0::real AND
  1.5::real = o;

/* SPARQL 17.3 - Operator Mapping (double precision op rdfnode) */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://example.org/measure>'::rdfnode AND
  o = 1.5::double precision AND
  o <> 9.9::double precision AND
  o > 1.0::double precision AND
  o < 9.9::double precision AND
  o >= 1.5::double precision AND
  o <= 1.5::double precision AND
  o BETWEEN 1.0::double precision AND 2.0::double precision AND
  1.5::double precision = o;

/* SPARQL 17.3 - Operator Mapping (numeric op rdfnode) */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://example.org/measure>'::rdfnode AND
  o = 1.5::numeric AND
  o <> 9.9::numeric AND
  o > 1.0::numeric AND
  o < 9.9::numeric AND
  o >= 1.5::numeric AND
  o <= 1.5::numeric AND
  o BETWEEN 1.0::numeric AND 2.0::numeric AND
  1.5::numeric = o;

/* SPARQL 17.3 - Operator Mapping (timestamp op rdfnode) */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://example.org/date>'::rdfnode AND
  o = '2015-01-01 00:00:00'::timestamp AND
  o <> '2020-01-01 00:00:00'::timestamp AND
  o > '2010-01-01 00:00:00'::timestamp AND
  o < '2020-01-01 00:00:00'::timestamp AND
  o >= '2015-01-01 00:00:00'::timestamp AND
  o <= '2015-01-01 00:00:00'::timestamp AND
  o BETWEEN '2010-01-01 00:00:00'::timestamp AND '2020-01-01 00:00:00'::timestamp AND
  '2015-01-01 00:00:00'::timestamp = o;

/* SPARQL 17.3 - Operator Mapping (timestamptz op rdfnode) */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://example.org/date>'::rdfnode AND
  o = '2015-01-01 00:00:00'::timestamptz AND
  o <> '2020-01-01 00:00:00'::timestamptz AND
  o > '2010-01-01 00:00:00'::timestamptz AND
  o < '2020-01-01 00:00:00'::timestamptz AND
  o >= '2015-01-01 00:00:00'::timestamptz AND
  o <= '2015-01-01 00:00:00'::timestamptz AND
  o BETWEEN '2010-01-01 00:00:00'::timestamptz AND '2020-01-01 00:00:00'::timestamptz AND
  '2015-01-01 00:00:00'::timestamptz = o;

/* SPARQL 17.3 - Operator Mapping (date op rdfnode, via strdt/substr/str) */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://example.org/date>'::rdfnode AND
  '2015-01-01'::date =  sparql.strdt(sparql.substr(sparql.str(o), 1, 10), 'xsd:date') AND
  '2015-01-01'::date >= sparql.strdt(sparql.substr(sparql.str(o), 1, 10), 'xsd:date') AND
  '2020-01-01'::date >  sparql.strdt(sparql.substr(sparql.str(o), 1, 10), 'xsd:date');

/* SPARQL 17.3 - Operator Mapping (timetz op rdfnode, via strdt/substr/str) */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://example.org/date>'::rdfnode AND
  '12:00:00 UTC'::timetz =  sparql.strdt(sparql.substr(sparql.str(o), 12, 8), 'xsd:time') AND
  '12:00:00 UTC'::timetz >= sparql.strdt(sparql.substr(sparql.str(o), 12, 8), 'xsd:time') AND
  '23:00:00 UTC'::timetz >  sparql.strdt(sparql.substr(sparql.str(o), 12, 8), 'xsd:time');

/* SPARQL 17.3 - Operator Mapping (boolean op rdfnode) */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM rdfnode_ft
WHERE
  p = '<http://example.org/flag>'::rdfnode AND
  true <> o AND
  false <> o;

/* ================================================================
 * SPARQL 17.3 - Operator Mapping (pg-typed columns)
 * ================================================================ */

/* text: =, <>, IN, NOT IN */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT label FROM pgtypes_ft
WHERE
  label = 'hello' AND
  label <> 'foo' AND
  label IN ('hello', 'world') AND
  label NOT IN ('foo', 'bar');

/* bigint: all operators */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT version FROM pgtypes_ft
WHERE
  version = 42 AND
  version <> 99 AND
  version > 10 AND
  version < 99 AND
  version >= 42 AND
  version <= 42 AND
  version BETWEEN 10 AND 100 AND
  version IN (42, 43) AND
  version NOT IN (0, 99);

/* smallint: all operators */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT num_smallint FROM pgtypes_ft
WHERE
  num_smallint = 42::smallint AND
  num_smallint <> 99::smallint AND
  num_smallint > 10::smallint AND
  num_smallint < 99::smallint AND
  num_smallint >= 42::smallint AND
  num_smallint <= 42::smallint AND
  num_smallint BETWEEN 10::smallint AND 100::smallint;

/* int: all operators */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT num_int FROM pgtypes_ft
WHERE
  num_int = 42 AND
  num_int <> 99 AND
  num_int > 10 AND
  num_int < 99 AND
  num_int >= 42 AND
  num_int <= 42 AND
  num_int BETWEEN 10 AND 100;

/* real: all operators */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT num_real FROM pgtypes_ft
WHERE
  num_real = 1.5::real AND
  num_real <> 9.9::real AND
  num_real > 1.0::real AND
  num_real < 9.9::real AND
  num_real >= 1.5::real AND
  num_real <= 1.5::real AND
  num_real BETWEEN 1.0::real AND 2.0::real;

/* double precision: all operators */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT num_double FROM pgtypes_ft
WHERE
  num_double = 1.5::double precision AND
  num_double <> 9.9::double precision AND
  num_double > 1.0::double precision AND
  num_double < 9.9::double precision AND
  num_double >= 1.5::double precision AND
  num_double <= 1.5::double precision AND
  num_double BETWEEN 1.0::double precision AND 2.0::double precision;

/* numeric: all operators */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT num_numeric FROM pgtypes_ft
WHERE
  num_numeric = 1.5::numeric AND
  num_numeric <> 9.9::numeric AND
  num_numeric > 1.0::numeric AND
  num_numeric < 9.9::numeric AND
  num_numeric >= 1.5::numeric AND
  num_numeric <= 1.5::numeric AND
  num_numeric BETWEEN 1.0::numeric AND 2.0::numeric;

/* timestamp: all operators */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT modified FROM pgtypes_ft
WHERE
  modified = '2015-07-12 20:41:25'::timestamp AND
  modified <> '2020-07-12 20:41:25'::timestamp AND
  modified > '2014-07-12 20:41:25'::timestamp AND
  modified < '2016-07-12 20:41:25'::timestamp AND
  modified >= '2015-07-12 20:41:25'::timestamp AND
  modified <= '2015-07-12 20:41:25'::timestamp AND
  modified BETWEEN '2014-07-12 20:41:25'::timestamp AND '2016-07-12 20:41:25'::timestamp;

/* timestamptz: all operators */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT tstz FROM pgtypes_ft
WHERE
  tstz = '2011-01-10 14:45:13.815-05:00'::timestamptz AND
  tstz <> '2020-01-10 14:45:13.815-05:00'::timestamptz AND
  tstz > '2010-01-10 14:45:13.815-05:00'::timestamptz AND
  tstz < '2012-01-10 14:45:13.815-05:00'::timestamptz AND
  tstz >= '2011-01-10 14:45:13.815-05:00'::timestamptz AND
  tstz <= '2011-01-10 14:45:13.815-05:00'::timestamptz AND
  tstz BETWEEN '2010-01-10 14:45:13.815-05:00'::timestamptz AND '2012-01-10 14:45:13.815-05:00'::timestamptz;

/* date: all operators */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT dt FROM pgtypes_ft
WHERE
  dt = '2018-05-01'::date AND
  dt <> '2020-05-01'::date AND
  dt > '2017-05-01'::date AND
  dt < '2019-05-01'::date AND
  dt >= '2018-05-01'::date AND
  dt <= '2018-05-01'::date AND
  dt BETWEEN '2017-05-01'::date AND '2019-05-01'::date AND
  dt IN ('2018-05-01', '2019-05-01') AND
  dt NOT IN ('2000-01-01', '2020-01-01');

/* timetz: all operators */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT ttz FROM pgtypes_ft
WHERE
  ttz = '12:00:00 UTC'::timetz AND
  ttz <> '23:00:00 UTC'::timetz AND
  ttz > '10:00:00 UTC'::timetz AND
  ttz < '23:00:00 UTC'::timetz AND
  ttz >= '12:00:00 UTC'::timetz AND
  ttz <= '12:00:00 UTC'::timetz AND
  ttz BETWEEN '10:00:00 UTC'::timetz AND '14:00:00 UTC'::timetz;

/* boolean: IS / IS NOT (pushable) */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT bl FROM pgtypes_ft
WHERE
  bl IS true AND
  bl IS NOT false;

EXPLAIN (VERBOSE, COSTS OFF)
SELECT bl FROM pgtypes_ft
WHERE
  bl IS false AND
  bl IS NOT true;

/* boolean: = / <> (NOT pushable) */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT bl FROM pgtypes_ft
WHERE
  bl = true AND
  bl <> false;

/* iri column */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT type FROM pgtypes_ft
WHERE type = 'http://example.org/SomeType';

/* ================================================================
 * pg function pushdown (length, abs, round, ceil, floor,
 *                        substring, extract, md5)
 * ================================================================ */

/* length */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT label FROM pgtypes_ft
WHERE
  length(label) = 5 AND
  length(label) <> 1 AND
  length(label) > 1 AND
  length(label) < 99 AND
  length(label) >= 5 AND
  length(label) <= 5 AND
  length(label) BETWEEN 1 AND 99;

/* abs */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT version FROM pgtypes_ft
WHERE
  abs(version) = 42 AND
  abs(version) > 10 AND
  abs(version) >= 42 AND
  abs(version) < 99 AND
  abs(version) <= 42 AND
  abs(version) BETWEEN 10 AND 100;

/* round */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT num_numeric FROM pgtypes_ft
WHERE
  round(num_numeric) = 2 AND
  round(num_numeric) > 1 AND
  round(num_numeric) >= 2 AND
  round(num_numeric) < 99 AND
  round(num_numeric) <= 2 AND
  round(num_numeric) BETWEEN 1 AND 99;

/* ceil */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT num_numeric FROM pgtypes_ft
WHERE
  ceil(num_numeric) = 2 AND
  ceil(num_numeric) > 1 AND
  ceil(num_numeric) >= 2 AND
  ceil(num_numeric) < 99 AND
  ceil(num_numeric) <= 2 AND
  ceil(num_numeric) BETWEEN 1 AND 99;

/* floor */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT num_numeric FROM pgtypes_ft
WHERE
  floor(num_numeric) = 1 AND
  floor(num_numeric) > 0 AND
  floor(num_numeric) >= 1 AND
  floor(num_numeric) < 99 AND
  floor(num_numeric) <= 1 AND
  floor(num_numeric) BETWEEN 1 AND 99;

/* substring */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT label FROM pgtypes_ft
WHERE substring(label, 1, 5) = 'hello';

/* extract */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT modified FROM pgtypes_ft
WHERE
  EXTRACT(year    FROM modified) = 2015 AND
  EXTRACT(month   FROM modified) = 07 AND
  EXTRACT(days    FROM modified) = 12 AND
  EXTRACT(hours   FROM modified) = 20 AND
  EXTRACT(minutes FROM modified) = 41 AND
  EXTRACT(seconds FROM modified) = 25;

/* md5 */
EXPLAIN (VERBOSE, COSTS OFF)
SELECT label FROM pgtypes_ft
WHERE md5(label) = '5d41402abc4b2a76b9719d911017c592';

/* ================================================================
 * SPARQL 17.4.1.1 - BOUND
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.bound(p), sparql.bound(x)
FROM rdfnode_opt_ft
WHERE
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.bound(o) AND
  NOT sparql.bound(x);

/* ================================================================
 * SPARQL 17.4.1.3 - COALESCE
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, x, sparql.coalesce(x, o, p)
FROM rdfnode_opt_ft
WHERE
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.coalesce(x, x, p) = '<http://www.w3.org/2000/01/rdf-schema#label>';

/* ================================================================
 * SPARQL 17.4.1.8 - sameTerm
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.sameterm(o, '"hello"@fr')
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.sameterm(p, '<http://www.w3.org/2000/01/rdf-schema#label>');

/* ================================================================
 * SPARQL 17.4.2.1 - isIRI
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.isIRI(p), sparql.isIRI(o)
FROM rdfnode_ft
WHERE
  p = '<http://example.org/property>' AND
  sparql.isIRI(p) AND
  NOT sparql.isIRI(o);

/* ================================================================
 * SPARQL 17.4.2.2 - isBlank
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.isblank(o)
FROM rdfnode_ft
WHERE sparql.isblank(o);

/* ================================================================
 * SPARQL 17.4.2.3 - isLiteral
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.isliteral(o), sparql.isliteral(p)
FROM rdfnode_ft
WHERE
  p = '<http://example.org/property>' AND
  sparql.isliteral(o) AND
  NOT sparql.isliteral(p);

/* ================================================================
 * SPARQL 17.4.2.4 - isNumeric
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.isnumeric(o), sparql.isnumeric(p)
FROM rdfnode_ft
WHERE
  p = '<http://example.org/count>' AND
  sparql.isnumeric(o) AND
  NOT sparql.isnumeric(p);

/* ================================================================
 * SPARQL 17.4.2.5 - str
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.str(o)
FROM rdfnode_ft
WHERE
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.str(o) = sparql.str('"hello"@en');

/* ================================================================
 * SPARQL 17.4.2.6 - lang
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.lang(o)
FROM rdfnode_ft
WHERE
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.lang(o) = sparql.lang('"hello"@en');

/* ================================================================
 * SPARQL 17.4.2.7 - datatype
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.datatype(o)
FROM rdfnode_ft
WHERE
  p = '<http://example.org/count>' AND
  sparql.datatype(o) = sparql.datatype('"42"^^<http://www.w3.org/2001/XMLSchema#integer>');

/* ================================================================
 * SPARQL 17.4.2.8 - IRI
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.iri(p)
FROM rdfnode_ft
WHERE
  sparql.iri(p) = sparql.iri('http://example.org/property') AND
  sparql.iri('http://example.org/property') = sparql.iri(p) AND
  p = sparql.iri('http://example.org/property');

/* ================================================================
 * SPARQL 17.4.2.9 - BNODE
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.bnode(o)
FROM rdfnode_ft
WHERE
  p = '<http://example.org/property>' AND
  sparql.isblank(sparql.bnode(o));

/* ================================================================
 * SPARQL 17.4.2.10 - STRDT
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.strdt(o, 'xsd:string')
FROM rdfnode_ft
WHERE
  p = sparql.iri('<http://example.org/count>') AND
  '"42"^^xsd:string'::rdfnode = sparql.strdt(sparql.str(o), 'xsd:string') AND
  sparql.strdt(sparql.str(o), 'xsd:string') = '"42"^^xsd:string'::rdfnode AND
  sparql.strdt(sparql.str('"42"^^xsd:integer'), 'xsd:string') = sparql.strdt(sparql.str(o), 'xsd:string') AND
  sparql.strdt(sparql.str(o), 'xsd:string') = sparql.strdt(sparql.str('"42"^^xsd:integer'), 'xsd:string');

/* ================================================================
 * SPARQL 17.4.2.11 - STRLANG
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.strlang(o, 'en')
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o), 'en') AND
  sparql.strlang(sparql.str(o), 'en') = sparql.strlang('"hello"', 'en') AND
  sparql.strlang('"hello"', 'en') = sparql.strlang(sparql.str(o), 'en') AND
  sparql.strlang('"hello"', 'en') = '"hello"@en' AND
  '"hello"@en' = sparql.strlang('"hello"', 'en');

/* ================================================================
 * SPARQL 17.4.3.2 - STRLEN
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.strlen(o)
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o), 'en') AND
  sparql.strlen(o) = sparql.strlen('"hello"@en') AND
  sparql.strlen(o) = 5 AND
  5 = sparql.strlen(o);

/* ================================================================
 * SPARQL 17.4.3.3 - SUBSTR
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.substr(o, 1, 3)
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o), 'en') AND
  sparql.substr(o, 1, 3) = sparql.substr('"hello"@en', 1, 3) AND
  sparql.substr('"hello"@en', 1, 3) = sparql.substr(o, 1, 3);

/* ================================================================
 * SPARQL 17.4.3.4 - UCASE
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.ucase(o)
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.ucase(o) = sparql.ucase('"hello"@en') AND
  sparql.ucase(o) = '"HELLO"@en' AND
  '"HELLO"@en' = sparql.ucase(o);

/* ================================================================
 * SPARQL 17.4.3.5 - LCASE
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.lcase(o)
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.lcase(o) = sparql.lcase('"HELLO"@en') AND
  sparql.lcase(o) = '"hello"@en' AND
  '"hello"@en' = sparql.lcase(o);

/* ================================================================
 * SPARQL 17.4.3.6 - STRSTARTS
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.strstarts(o, sparql.str('"hel"@en'))
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o), 'en') AND
  sparql.strstarts(o, '"hel"@en');

/* ================================================================
 * SPARQL 17.4.3.7 - STRENDS
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.strends(o, sparql.str('"llo"@en'))
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o), 'en') AND
  sparql.strends(o, '"llo"');

/* ================================================================
 * SPARQL 17.4.3.8 - CONTAINS
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.contains(o, '"ell"@en')
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o), 'en') AND
  sparql.contains(o, '"ell"') AND
  sparql.contains(o, '"hel"');

/* ================================================================
 * SPARQL 17.4.3.9 - STRBEFORE
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.strbefore(sparql.str(o), '"llo"')
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o), 'en') AND
  sparql.strbefore(sparql.str(o), '"llo"') = sparql.strbefore(sparql.str('"hello"@en'), '"llo"') AND
  sparql.strbefore(sparql.str(o), '"llo"') = '"he"' AND
  '"he"' = sparql.strbefore(sparql.str(o), '"llo"');

/* ================================================================
 * SPARQL 17.4.3.10 - STRAFTER
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.strafter(sparql.str(o), '"hel"')
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o), 'en') AND
  sparql.strafter(sparql.str(o), '"hel"') = sparql.strafter(sparql.str('"hello"@en'), '"hel"') AND
  sparql.strafter(sparql.str(o), '"hel"') = '"lo"'::rdfnode AND
  '"lo"' = sparql.strafter(sparql.str(o), '"hel"');

/* ================================================================
 * SPARQL 17.4.3.11 - ENCODE_FOR_URI
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.encode_for_uri(o)
FROM rdfnode_ft
WHERE
  p = sparql.iri('<http://schema.org/description>') AND
  sparql.langmatches(sparql.lang(o), 'en') AND
  sparql.encode_for_uri(o) = '"hello%20world"' AND
  '"hello%20world"' = sparql.encode_for_uri(o);

/* ================================================================
 * SPARQL 17.4.3.12 - CONCAT
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.concat(o, sparql.strlang(' world', 'en'))
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o), 'en') AND
  sparql.concat(o, '" world"') = sparql.concat('"hello"@en', '" world"') AND
  sparql.concat('"hello"@en', '" world"') = sparql.concat(o, '" world"');

/* ================================================================
 * SPARQL 17.4.3.13 - langMatches
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.langmatches(sparql.lang(o), '*'), sparql.langmatches(sparql.lang(o), 'en')
FROM rdfnode_ft
WHERE sparql.langmatches(sparql.lang(o), 'en')
ORDER BY p, o;

/* ================================================================
 * SPARQL 17.4.3.15 - REPLACE
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.replace(o, 'hel', 'HEL')
FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o), 'en') AND
  sparql.replace(sparql.str(o), 'hel', 'HEL') = '"HELlo"'::rdfnode AND
  '"HELlo"' = sparql.replace(sparql.str(o), 'hel', 'HEL') AND
  sparql.replace(sparql.str(o), 'HEL', 'hel', 'i') = sparql.replace('"hello"', 'HEL', 'hel', 'i');

/* ================================================================
 * SPARQL 17.4.4.1 - abs
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.abs(o) FROM rdfnode_ft
WHERE
  p = '<http://example.org/count>'::rdfnode AND
  sparql.abs(o) = 42::bigint AND
  sparql.abs(o) <> 99::bigint AND
  sparql.abs(o) >= 42::bigint AND
  sparql.abs(o) <= 42::bigint AND
  sparql.abs(o) BETWEEN 10::bigint AND 99::bigint AND
  sparql.abs(o) =  '"42"^^xsd:long'::rdfnode AND
  sparql.abs(o) >  '"10"^^xsd:long'::rdfnode AND
  sparql.abs(o) >= '"42"^^xsd:long'::rdfnode AND
  sparql.abs(o) <  '"99"^^xsd:long'::rdfnode AND
  sparql.abs(o) <= '"42"^^xsd:long'::rdfnode AND
  42::bigint = sparql.abs(o) AND
  '"42"^^xsd:long'::rdfnode = sparql.abs(o);

/* ================================================================
 * SPARQL 17.4.4.2 - round
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.round(o) FROM rdfnode_ft
WHERE
  p = '<http://example.org/measure>'::rdfnode AND
  sparql.round(o) = sparql.round(1.5) AND
  sparql.round(o) > 1.0 AND
  sparql.round(o) >= sparql.round(1.5) AND
  sparql.round(o) < 9.9 AND
  sparql.round(o) <= sparql.round(1.5) AND
  sparql.round(o) = '"2"^^xsd:decimal'::rdfnode AND
  sparql.round(o) > '"1"^^xsd:decimal'::rdfnode AND
  sparql.round(o) >= '"2"^^xsd:decimal'::rdfnode AND
  sparql.round(o) < '"9"^^xsd:decimal'::rdfnode AND
  sparql.round(o) <= '"2"^^xsd:decimal'::rdfnode AND
  sparql.round(1.5) = sparql.round(o) AND
  sparql.round('"1.5"^^xsd:decimal'::rdfnode) = sparql.round(o);

/* ================================================================
 * SPARQL 17.4.4.3 - ceil
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.ceil(o) FROM rdfnode_ft
WHERE
  p = '<http://example.org/measure>'::rdfnode AND
  sparql.ceil(o) = sparql.ceil(1.5) AND
  sparql.ceil(o) > 1.0 AND
  sparql.ceil(o) >= sparql.ceil(1.5) AND
  sparql.ceil(o) < 9.9 AND
  sparql.ceil(o) <= sparql.ceil(1.5) AND
  sparql.ceil(o) = '"2"^^xsd:decimal'::rdfnode AND
  sparql.ceil(o) > '"1"^^xsd:decimal'::rdfnode AND
  sparql.ceil(o) >= '"2"^^xsd:decimal'::rdfnode AND
  sparql.ceil(o) < '"9"^^xsd:decimal'::rdfnode AND
  sparql.ceil(o) <= sparql.ceil('"1.5"^^xsd:decimal'::rdfnode) AND
  sparql.ceil(1.5) = sparql.ceil(o) AND
  sparql.ceil('"1.5"^^xsd:decimal'::rdfnode) = sparql.ceil(o);

/* ================================================================
 * SPARQL 17.4.4.4 - floor
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.floor(o) FROM rdfnode_ft
WHERE
  p = '<http://example.org/measure>'::rdfnode AND
  sparql.floor(o) = sparql.floor(1.5) AND
  sparql.floor(o) > 1.0 AND
  sparql.floor(o) >= sparql.floor(1.5) AND
  sparql.floor(o) < 9.9 AND
  sparql.floor(o) <= sparql.floor(1.5) AND
  sparql.floor(o) = '"1"^^xsd:decimal'::rdfnode AND
  sparql.floor(o) > '"0"^^xsd:decimal'::rdfnode AND
  sparql.floor(o) >= '"1"^^xsd:decimal'::rdfnode AND
  sparql.floor(o) < '"9"^^xsd:decimal'::rdfnode AND
  sparql.floor(o) <= sparql.floor('"1.5"^^xsd:decimal'::rdfnode) AND
  sparql.floor(1.5) = sparql.floor(o) AND
  sparql.floor('"1.5"^^xsd:decimal'::rdfnode) = sparql.floor(o);

/* ================================================================
 * SPARQL 17.4.5.2 - year
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.year(o) FROM rdfnode_ft
WHERE
  p = sparql.iri('http://example.org/date') AND
  sparql.year(o) = 2015 AND
  sparql.year(o) > 2000 AND
  sparql.year(o) < 2020 AND
  sparql.year(o) >= 2015 AND
  sparql.year(o) <= 2015 AND
  sparql.year(o) = sparql.year('"2015-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.year(o) > sparql.year('"2000-01-01T00:00:00Z"^^xsd:dateTime') AND
  sparql.year(o) < sparql.year('"2020-01-01T00:00:00Z"^^xsd:dateTime') AND
  sparql.year(o) >= sparql.year('"2015-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.year(o) <= sparql.year('"2015-07-08T00:00:00Z"^^xsd:dateTime');

/* ================================================================
 * SPARQL 17.4.5.3 - month
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.month(o) FROM rdfnode_ft
WHERE
  p = sparql.iri('http://example.org/date') AND
  sparql.month(o) = 7 AND
  sparql.month(o) > 1 AND
  sparql.month(o) < 12 AND
  sparql.month(o) >= 7 AND
  sparql.month(o) <= 7 AND
  sparql.month(o) = sparql.month('"2015-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.month(o) > sparql.month('"2015-01-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.month(o) < sparql.month('"2015-12-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.month(o) >= sparql.month('"2015-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.month(o) <= sparql.month('"2015-07-08T00:00:00Z"^^xsd:dateTime');

/* ================================================================
 * SPARQL 17.4.5.4 - day
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.day(o) FROM rdfnode_ft
WHERE
  p = sparql.iri('http://example.org/date') AND
  sparql.day(o) = 8 AND
  sparql.day(o) > 1 AND
  sparql.day(o) < 30 AND
  sparql.day(o) >= 8 AND
  sparql.day(o) <= 8 AND
  sparql.day(o) = sparql.day('"2015-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.day(o) > sparql.day('"2015-07-01T00:00:00Z"^^xsd:dateTime') AND
  sparql.day(o) < sparql.day('"2015-07-30T00:00:00Z"^^xsd:dateTime') AND
  sparql.day(o) >= sparql.day('"2015-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.day(o) <= sparql.day('"2015-07-08T00:00:00Z"^^xsd:dateTime');

/* ================================================================
 * SPARQL 17.4.5.5 - hours
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.hours(o) FROM rdfnode_ft
WHERE
  p = sparql.iri('http://example.org/date') AND
  sparql.hours(o) = 20 AND
  sparql.hours(o) > 0 AND
  sparql.hours(o) < 23 AND
  sparql.hours(o) >= 20 AND
  sparql.hours(o) <= 20 AND
  sparql.hours(o) = sparql.hours('"2015-07-08T20:41:25Z"^^xsd:dateTime') AND
  sparql.hours(o) < sparql.hours('"2015-07-08T23:00:00Z"^^xsd:dateTime') AND
  sparql.hours(o) >= sparql.hours('"2015-07-08T20:41:25Z"^^xsd:dateTime') AND
  sparql.hours(o) <= sparql.hours('"2015-07-08T20:41:25Z"^^xsd:dateTime');

/* ================================================================
 * SPARQL 17.4.5.6 - minutes
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.minutes(o) FROM rdfnode_ft
WHERE
  p = sparql.iri('http://example.org/date') AND
  sparql.minutes(o) = 41 AND
  sparql.minutes(o) > 0 AND
  sparql.minutes(o) < 59 AND
  sparql.minutes(o) >= 41 AND
  sparql.minutes(o) <= 41 AND
  sparql.minutes(o) = sparql.minutes('"2015-07-08T20:41:25Z"^^xsd:dateTime') AND
  sparql.minutes(o) < sparql.minutes('"2015-07-08T20:59:00Z"^^xsd:dateTime') AND
  sparql.minutes(o) >= sparql.minutes('"2015-07-08T20:41:25Z"^^xsd:dateTime') AND
  sparql.minutes(o) <= sparql.minutes('"2015-07-08T20:41:25Z"^^xsd:dateTime');

/* ================================================================
 * SPARQL 17.4.5.7 - seconds
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.seconds(o) FROM rdfnode_ft
WHERE
  p = sparql.iri('http://example.org/date') AND
  sparql.seconds(o) = 25 AND
  sparql.seconds(o) > 0 AND
  sparql.seconds(o) < 59 AND
  sparql.seconds(o) >= 25 AND
  sparql.seconds(o) <= 25 AND
  sparql.seconds(o) = sparql.seconds('"2015-07-08T20:41:25Z"^^xsd:dateTime') AND
  sparql.seconds(o) < sparql.seconds('"2015-07-08T20:41:59Z"^^xsd:dateTime') AND
  sparql.seconds(o) >= sparql.seconds('"2015-07-08T20:41:25Z"^^xsd:dateTime') AND
  sparql.seconds(o) <= sparql.seconds('"2015-07-08T20:41:25Z"^^xsd:dateTime');

/* ================================================================
 * SPARQL 17.4.6.1 - MD5
 * ================================================================ */

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o, sparql.md5(o) FROM rdfnode_ft
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o), 'en') AND
  sparql.md5(o) = sparql.md5('"hello"@en');

/* ================================================================
 * Non-pushable tables
 * (SPARQL query contains MINUS, UNION, LIMIT, ORDER BY, GROUP BY)
 * ================================================================ */

CREATE FOREIGN TABLE np_minus (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER test_server OPTIONS (
  sparql 'SELECT * WHERE {<http://example.org/s> ?p ?o MINUS {<http://example.org/s> <http://example.org/p> ?o}}');

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM np_minus
WHERE p = '<http://example.org/p>';

CREATE FOREIGN TABLE np_union (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER test_server OPTIONS (
  sparql 'SELECT * WHERE {{<http://example.org/s> ?p ?o} UNION {<http://example.org/s2> ?p ?o}}');

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM np_union
WHERE p = '<http://example.org/p>';

CREATE FOREIGN TABLE np_limit (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER test_server OPTIONS (
  sparql 'SELECT * WHERE {<http://example.org/s> ?p ?o} LIMIT 10');

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM np_limit
WHERE p = '<http://example.org/p>';

CREATE FOREIGN TABLE np_orderby (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER test_server OPTIONS (
  sparql 'SELECT * WHERE {<http://example.org/s> ?p ?o} ORDER BY ?o');

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, o FROM np_orderby
WHERE p = '<http://example.org/p>';

CREATE FOREIGN TABLE np_groupby (
  p rdfnode OPTIONS (variable '?p'),
  c int      OPTIONS (variable '?c')
)
SERVER test_server OPTIONS (
  sparql 'SELECT ?p (COUNT(?o) AS ?c) WHERE {<http://example.org/s> ?p ?o} GROUP BY ?p');

EXPLAIN (VERBOSE, COSTS OFF)
SELECT p, c FROM np_groupby
WHERE c > 1;

DROP SERVER test_server CASCADE;
