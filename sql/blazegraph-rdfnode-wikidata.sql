SET timezone TO 'Etc/UTC';

CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://query.wikidata.org/sparql');

CREATE FOREIGN TABLE rdbms (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER wikidata OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * {wd:Q192490 ?p ?o}');

/* SPARQL 17.4.1.7 - RDFterm-equal */
SELECT p, o FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  o = '"PostgreSQL"@de';

/* SPARQL 17.4.1.9 - IN */
SELECT p, o FROM rdbms
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  o IN ('"PostgreSQL"@de', 
        '"PostgreSQL"@es',
		'"PostgreSQL"@fr');

/* SPARQL 17.4.1.10 - NOT IN*/
SELECT p, o FROM rdbms
WHERE
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  o NOT IN ('"PostgreSQL"@de', 
            '"PostgreSQL"@es',
		    '"PostgreSQL"@fr')
LIMIT 5;

/* SPARQL 15.5 - LIMIT */
SELECT p, o FROM rdbms
WHERE p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label')
LIMIT 5;

SELECT p, o FROM rdbms
WHERE p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label')
FETCH FIRST 5 ROWS ONLY;

/* SPARQL 15.4 - OFFSET */
SELECT p, o FROM rdbms
WHERE p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label')
OFFSET 5 ROWS
FETCH FIRST 10 ROWS ONLY;

SELECT p, o FROM rdbms
WHERE p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label')
OFFSET 5 ROWS
LIMIT 10;

/* SPARQL 15.1 - ORDER BY */
SELECT p FROM rdbms
WHERE p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label')
ORDER BY p DESC
LIMIT 3;

SELECT p FROM rdbms
WHERE p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label')
ORDER BY p ASC
LIMIT 3;

SELECT p, o FROM rdbms
WHERE p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label')
ORDER BY p DESC, o ASC
LIMIT 3;

SELECT p, o FROM rdbms
WHERE p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label')
ORDER BY p DESC, o ASC
OFFSET 5
LIMIT 2;

SELECT p, o FROM rdbms
WHERE p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label')
ORDER BY 1 DESC, 2 ASC
OFFSET 5
LIMIT 10;

/* SPARQL 18.2.5.3 - DISTINCT */
SELECT DISTINCT p FROM rdbms
WHERE p = '<http://www.w3.org/2000/01/rdf-schema#label>';

-- DISTINCT ON is not supported, therefore it won't be pushed down.
SELECT DISTINCT ON (p) p,o FROM rdbms
WHERE p = '<http://www.w3.org/2000/01/rdf-schema#label>';

/* SPARQL - 17.3 Operator Mapping (text) */
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  p <> '<foo.bar>' AND
  sparql.str(o) >= '"Postgre"' AND
  sparql.str(o) <= '"PostgreSQL Europe"' AND
  sparql.str(o) BETWEEN '"Postgre"' AND '"PostgreSQL Europe"'
LIMIT 3;

/* SPARQL - 17.3 Operator Mapping (rdfnode) */
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>'::rdfnode AND
  p <> '<foo.bar>'::rdfnode AND
  sparql.str(o) >= 'Postgre'::rdfnode AND
  sparql.str(o) <= '"PostgreSQL Europe"'::rdfnode AND
  sparql.str(o) BETWEEN 'Postgre'::rdfnode AND '"PostgreSQL Europe"'::rdfnode
LIMIT 3;

/* SPARQL - 17.3 Operator Mapping (smallint) */
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P8687>'::rdfnode AND
  o = 31360::smallint AND
  o <> 10000::smallint AND
  o >= 31360::smallint AND
  o <= 31360::smallint AND
  o BETWEEN 31000 AND 31999 AND
  31360::smallint = o AND
  10000::smallint <> o AND
  31360::smallint >= o AND
  31360::smallint <= o;

/* SPARQL - 17.3 Operator Mapping (int) */
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P8687>'::rdfnode AND
  o = 31360::int AND
  o <> 10000::int AND
  o >= 31360::int AND
  o <= 31360::int AND
  o BETWEEN 31000 AND 31999 AND
  31360::int = o AND
  10000::int <> o AND
  31360::int >= o AND
  31360::int <= o;

/* SPARQL - 17.3 Operator Mapping (bigint) */
SELECT p, o FROM rdbms
WHERE 
  p = '<http://schema.org/version>'::rdfnode AND
  o = 2441109372::bigint AND
  o <> 9999999999::bigint AND
  o >= 2441109372::bigint AND
  o <= 2441109372::bigint AND
  o BETWEEN 2346087000::bigint AND 9999999999::bigint AND
  2441109372::bigint = o AND
  9999999999::bigint <> o AND
  2441109372::bigint >= o AND
  2441109372::bigint <= o;

/* SPARQL - 17.3 Operator Mapping (real) */
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P8687>'::rdfnode AND
  o = 31360.0::real AND
  o <> 10000::real AND
  o >= 31359.5::real AND
  o <= 31360.5::real AND
  o BETWEEN 31359.5::real AND 31360.5::real AND
  31360.0::real = o AND
  10000::real <> o AND
  31360.5::real >= o AND
  31359.5::real <= o;

/* SPARQL - 17.3 Operator Mapping (double precision) */
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P8687>'::rdfnode AND
  o = 31360.0::double precision AND
  o <> 10000.99::double precision AND
  o >= 31359.5::double precision AND
  o <= 31360.5::double precision AND
  o BETWEEN 31359.5::double precision AND 31360.5::double precision AND
  31360.0::double precision = o AND
  10000.99::double precision <> o AND
  31360.5::double precision >= o AND
  31359.5::double precision <= o;

/* SPARQL - 17.3 Operator Mapping (numeric) */
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P8687>'::rdfnode AND
  o = 31360.0::numeric AND
  o <> 10000.99::numeric AND
  o >= 31359.5::numeric AND
  o <= 31360.5::numeric AND
  o BETWEEN 31359.5::numeric AND 31360.5::numeric AND
  31360.0::numeric = o AND
  10000.99::numeric <> o AND
  31360.5::numeric >= o AND
  31359.5::numeric <= o;

/* SPARQL - 17.3 Operator Mapping (timestamp) */
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P571>'::rdfnode AND
  o = '1996-01-01 00:00:00'::timestamp AND
  o <> '2000-01-31 18:30:00'::timestamp AND
  o >= '1996-01-01 00:00:00'::timestamp AND
  o <= '1996-01-01 00:00:00'::timestamp AND
  o BETWEEN '1990-01-01 00:00:00'::timestamp AND '2000-01-01 00:00:00'::timestamp AND
  '1996-01-01 00:00:00'::timestamp = o AND
  '2000-01-31 18:30:00'::timestamp <> o AND
  '1996-01-01 00:00:00'::timestamp <= o AND
  '1996-01-01 00:00:00'::timestamp >= o;

/* SPARQL - 17.3 Operator Mapping (timestamptz) */
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P571>'::rdfnode AND
  o = '1996-01-01 00:00:00'::timestamptz AND
  o <> '2000-01-31 18:30:00'::timestamptz AND
  o >= '1996-01-01 00:00:00'::timestamptz AND
  o <= '1996-01-01 00:00:00'::timestamptz AND
  o BETWEEN '1990-01-01 00:00:00'::timestamptz AND '2000-01-01 00:00:00'::timestamptz AND
  '1996-01-01 00:00:00'::timestamptz = o AND
  '2000-01-31 18:30:00'::timestamptz <> o AND
  '1996-01-01 00:00:00'::timestamptz <= o AND
  '1996-01-01 00:00:00'::timestamptz >= o;

/* SPARQL - 17.3 Operator Mapping (date) */
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P571>'::rdfnode AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') = '1996-01-01'::date AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') <> '2000-01-01'::date AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') >= '1996-01-01'::date AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') <= '1996-01-01'::date AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') BETWEEN '1990-01-01'::date AND '2000-01-01'::date AND
  '1996-01-01'::date =  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') AND
  '2000-01-01'::date <> sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') AND
  '1996-01-01'::date <= sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') AND
  '1996-01-01'::date >= sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date');

/* SPARQL - 17.3 Operator Mapping (timetz) */
SELECT p, o, sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P571>'::rdfnode AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') = '00:00:00 PST'::timetz AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') <> '23:00:00 PST'::timetz AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') >= '00:00:00 PST'::timetz AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') <= '00:00:00 PST'::timetz AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') BETWEEN '00:00:00 PST'::timetz AND '23:59:00 PST'::timetz AND
  '00:00:00 PST'::timetz =  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') AND
  '23:00:00 PST'::timetz <> sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') AND
  '00:00:00 PST'::timetz <= sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') AND
  '00:00:00 PST'::timetz >= sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time');

/* SPARQL - 17.3 Operator Mapping (boolean) */
SELECT p, o FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P571>'::rdfnode AND
  o <> false AND
  o <> true AND
  false <> o AND
  true <> o;

/* SPARQL 17.4.1.1 - BOUND */
CREATE FOREIGN TABLE rdbms2 (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o'),
  x rdfnode OPTIONS (variable '?x')
)
SERVER wikidata OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * {wd:Q192490 ?p ?o OPTIONAL { ?o <http://foo.bar> ?x }}');

SELECT p, o, sparql.bound(p), sparql.bound(x)
FROM rdbms2
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.langmatches(sparql.lang(o),'es') AND
  sparql.bound(o) AND
  NOT sparql.bound(x);

/* SPARQL 17.4.1.3 - COALESCE */
SELECT p, o, x, sparql.coalesce(x, o, p)
FROM rdbms2
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.coalesce(x, o) = '"PostgreSQL"@de' AND
  sparql.coalesce(x, x, o) = '"PostgreSQL"@de' AND
  sparql.coalesce(x, p) = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.coalesce(x, x, p) = '<http://www.w3.org/2000/01/rdf-schema#label>';

/* SPARQL 17.4.1.8 - sameTerm */
SELECT p, o, sparql.sameterm(o,'"PostgreSQL"@fr')
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.sameterm(o,'"PostgreSQL"@fr') AND
  sparql.sameterm(p,'<http://www.w3.org/2000/01/rdf-schema#label>');

/* SPARQL 17.4.1.9 - IN */
SELECT p, o
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  o IN ('"PostgreSQL"@de'::rdfnode, '"PostgreSQL"@en', sparql.strlang('PostgreSQL','es'));

/* SPARQL 17.4.1.10 - NOT IN */
SELECT p, o
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  o NOT IN ('"PostgreSQL"@de'::rdfnode, '"PostgreSQL"@en', sparql.strlang('PostgreSQL','es'))
FETCH FIRST 3 ROWS ONLY;

/* SPARQL 17.4.2.1 - isIRI */
SELECT p, o, sparql.isIRI(p), sparql.isIRI(o) FROM rdbms 
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P8408>' AND
  sparql.isIRI(p) AND
  NOT sparql.isIRI(o);

/* SPARQL 17.4.2.2 - isBlank */
SELECT p, o, sparql.isblank(o) FROM rdbms
WHERE sparql.isblank(o);

/* SPARQL 17.4.2.3 - isLiteral */
SELECT p, o, sparql.isliteral(o), sparql.isliteral(p) FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P8408>' AND
  sparql.isliteral(o) AND 
  NOT sparql.isliteral(p);

/* SPARQL 17.4.2.4 - isNumeric */
SELECT p, o, sparql.isnumeric(o), sparql.isnumeric(p) FROM rdbms
WHERE 
  p = '<http://schema.org/version>' AND
  sparql.isnumeric(o) AND
  NOT sparql.isnumeric(p);

/* SPARQL 17.4.2.5 - str */
SELECT p, o, sparql.str(o)
FROM rdbms
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.str(o) = sparql.str('"PostgreSQL"@fr')
FETCH FIRST ROW ONLY;

/* SPARQL 17.4.2.6 - lang */
SELECT p, o, sparql.lang(o)
FROM rdbms
WHERE 
  p = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  sparql.lang(o) = sparql.lang('"PostgreSQL"@pt');

/* SPARQL 17.4.2.7 - datatype */
SELECT p, o, sparql.datatype(o)
FROM rdbms
WHERE
  p = '<http://wikiba.se/ontology#statements>' AND
  sparql.datatype(o) = sparql.datatype('"2441109372"^^<http://www.w3.org/2001/XMLSchema#integer>');

/* SPARQL 17.4.2.8 - IRI */
SELECT p, o, sparql.iri(p)
FROM rdbms
WHERE 
  sparql.iri(p) = sparql.iri('http://www.wikidata.org/prop/direct/P13337') AND
  sparql.iri('<http://www.wikidata.org/prop/direct/P13337>') = sparql.iri(p) AND
  sparql.iri('http://www.wikidata.org/prop/direct/P13337') = p AND
  p = sparql.iri('http://www.wikidata.org/prop/direct/P13337');

/* SPARQL 17.4.2.9 - BNODE */
SELECT p, o, sparql.bnode(o)
FROM rdbms
WHERE 
  p = '<http://www.wikidata.org/prop/direct/P13337>' AND
  sparql.isblank(sparql.bnode(o));

/* SPARQL 17.4.2.10 - STRDT */
SELECT p, o, sparql.strdt(o,'xsd:string')
FROM rdbms
WHERE 
  p = sparql.iri('<http://schema.org/version>') AND
  '"2441109372"^^xsd:string'::rdfnode = sparql.strdt(sparql.str(o),'xsd:string') AND
  sparql.strdt(sparql.str(o),'xsd:string') = '"2441109372"^^xsd:string'::rdfnode  AND
  sparql.strdt(sparql.str('"2441109372"^^xsd:integer'),'xsd:string') = sparql.strdt(sparql.str(o),'xsd:string') AND
  sparql.strdt(sparql.str(o),'xsd:string') = sparql.strdt(sparql.str('"2441109372"^^xsd:integer'),'xsd:string');

/* SPARQL 17.4.2.11 - STRLANG */
SELECT p, o, sparql.strlang(o,'en')
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o),'en') AND
  sparql.strlang(sparql.str(o),'en') = sparql.strlang('"PostgreSQL"', 'en') AND
  sparql.strlang('"PostgreSQL"', 'en') = sparql.strlang(sparql.str(o),'en') AND
  sparql.strlang('"PostgreSQL"', 'en') = '"PostgreSQL"@en' AND
  '"PostgreSQL"@en' = sparql.strlang('"PostgreSQL"', 'en');

/* SPARQL 17.4.2.12 - UUID (not pushable) */
SELECT sparql.uuid()::text ~ '^<urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}>$';

/*SPARQL 17.4.2.13 - STRUUID (not pushable) */
SELECT sparql.struuid()::text ~ '^"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"$';

/* SPARQL 17.4.3.2 - STRLEN */
SELECT p, o, sparql.strlen(o)
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o),'de') AND
  sparql.strlen(o) = sparql.strlen('"PostgreSQL"@de') AND
  sparql.strlen(o) = 10 AND
  10 = sparql.strlen(o);

/* SPARQL 17.4.3.3 - SUBSTR */
SELECT p, o, sparql.substr(o, 8, 3)
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o),'es') AND
  sparql.substr(o, 8, 3) = sparql.substr('"PostgreSQL"@es', 8, 3) AND
  sparql.substr('"PostgreSQL"@es', 8, 3) = sparql.substr(o, 8, 3);

/* SPARQL 17.4.3.4 - UCASE */
SELECT p, o, sparql.ucase(o)
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.ucase(o) = sparql.ucase('"PostgreSQL"@fr') AND
  sparql.ucase(o) = '"POSTGRESQL"@fr' AND
  '"POSTGRESQL"@fr' = sparql.ucase(o);

/* SPARQL 17.4.3.5 - LCASE */
SELECT p, o, sparql.lcase(o)
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.lcase(o) = sparql.lcase('"PostgreSQL"@es') AND
  sparql.lcase(o) = '"postgresql"@es' AND
  '"postgresql"@es' = sparql.lcase(o);

/* SPARQL 17.4.3.6 - STRSTARTS */
SELECT p, o, sparql.strstarts(o, sparql.str('"Postgre"@de'))
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o),'de') AND
  sparql.strstarts(o,'"Postgre"@de');

/* SPARQL 17.4.3.7 - STRENDS */
SELECT p, o, sparql.strends(o, sparql.str('"SQL"@fr'))
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o),'fr') AND
  sparql.strends(o,'"SQL"');

/* SPARQL 17.4.3.8 - CONTAINS */
SELECT p, o, sparql.contains(o,'"SQL"@it'), sparql.contains(o,'"SQL"^^xsd:string')
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND  
  sparql.langmatches(sparql.lang(o),'it') AND
  sparql.contains(o,'"SQL"@') AND
  sparql.contains(o,'"Postgre"');

/* SPARQL 17.4.3.9 - STRBEFORE */
SELECT p, o, sparql.strbefore(sparql.str(o), '"SQL"')
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o),'fr') AND
  sparql.strbefore(sparql.str(o), '"SQL"') = sparql.strbefore(sparql.str('"PostgreSQL"@fr'),'"SQL"') AND
  sparql.strbefore(sparql.str(o), '"SQL"') = '"Postgre"' AND
  '"Postgre"' = sparql.strbefore(sparql.str(o), '"SQL"');

/* SPARQL 17.4.3.10 - STRAFTER */
SELECT p, o, sparql.strafter(sparql.str(o), '"Postgre"')
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o),'es') AND
  sparql.strafter(sparql.str(o), '"Postgre"') = sparql.strafter(sparql.str('"PostgreSQL"@es'),'"Postgre"') AND
  sparql.strafter(sparql.str(o), '"Postgre"') = '"SQL"'::rdfnode AND
  '"SQL"' = sparql.strafter(sparql.str(o), '"Postgre"');

/* SPARQL 17.4.3.11 - ENCODE_FOR_URI */
SELECT p, o, sparql.encode_for_uri(o)
FROM rdbms
WHERE 
  p = sparql.iri('<http://schema.org/description>') AND
  sparql.langmatches(sparql.lang(o),'de') AND
  sparql.encode_for_uri(o) = sparql.encode_for_uri('"relationales Datenbankmanagementsystem"@de') AND
  sparql.encode_for_uri(o) = '"relationales%20Datenbankmanagementsystem"' AND 
  '"relationales%20Datenbankmanagementsystem"' = sparql.encode_for_uri(o);

/* 17.4.3.12 - CONCAT */
SELECT p, o, sparql.concat(o,sparql.strlang(' Global','es')), sparql.concat(o,'" Global"^^xsd:string')
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o),'es') AND
  sparql.concat(o,' Global') = sparql.concat('"PostgreSQL"@es','" Global"') AND
  sparql.concat('"PostgreSQL"@es','" Global"') = sparql.concat(o,' Global');

/* SPARQL 17.4.3.13 - langMatches */
SELECT p, o, sparql.langmatches(sparql.lang(o),'*'),  sparql.langmatches(sparql.lang(o),'fr'),  sparql.langmatches(sparql.lang(o),'de')
FROM rdbms 
WHERE sparql.langmatches(sparql.lang(o),'fr')
ORDER BY p, o;

/* SPARQL 17.4.3.14 - REGEX */
SELECT p, o
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o),'it') AND
  sparql.regex(o, sparql.ucase('postgres'), 'i') AND 
  sparql.regex(o, '^pOs','i') ;

/* SPARQL 17.4.3.15 - REPLACE */
SELECT p, o, sparql.replace(o,'Postgre','My'), sparql.replace(o,'"Postgre"@fr',''), sparql.replace(o,'Postgre','My') = sparql.replace(sparql.strlang('PostgreSQL','fr'),'Postgre','My')
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o),'es') AND
  sparql.replace(sparql.str(o),'Postgre','My') = '"MySQL"'::rdfnode AND
  '"MySQL"' = sparql.replace(sparql.str(o),'Postgre','My') AND
  sparql.replace(sparql.str(o), 'POSTGRE', 'My','i') = sparql.replace('"PostgreSQL"', 'POSTGRE', 'My','i');

/* SPARQL 17.4.4.1 - abs */
SELECT p, o, sparql.abs(o) FROM rdbms
WHERE 
  p = '<http://schema.org/version>'::rdfnode AND
  sparql.abs(o) = 2441109372::bigint AND
  sparql.abs(o) <> 9999999999::bigint AND
  sparql.abs(o) >= 2441109372::bigint AND
  sparql.abs(o) <= 2441109372::bigint AND
  sparql.abs(o) BETWEEN 2346087000::bigint AND 9999999999::bigint AND
  sparql.abs(o) =  '"2441109372"^^xsd:long'::rdfnode AND
  sparql.abs(o) >  '"1111111111"^^xsd:long'::rdfnode AND
  sparql.abs(o) >= '"2441109372"^^xsd:long'::rdfnode AND
  sparql.abs(o) <  '"9999999999"^^xsd:long'::rdfnode AND
  sparql.abs(o) <= '"2441109372"^^xsd:long'::rdfnode AND
  2441109372::bigint = sparql.abs(o) AND
  '"2441109372"^^xsd:long'::rdfnode = sparql.abs(o);

/* SPARQL 17.4.4.2 - round */
SELECT p, o, sparql.round(o)
FROM rdbms
WHERE 
  p = sparql.iri('<http://www.wikidata.org/prop/direct/P8687>') AND
  sparql.round(o) = sparql.round(31359.9) AND
  sparql.round(o) > 10000.9 AND
  sparql.round(o) >= sparql.round(31359.9) AND
  sparql.round(o) < 99999.9 AND
  sparql.round(o) <= sparql.round(31359.9) AND
  sparql.round(o) = '"31360"^^xsd:decimal'::rdfnode AND
  sparql.round(o) > '"10000.9"^^xsd:decimal'::rdfnode AND
  sparql.round(o) >= '"31360"^^xsd:decimal'::rdfnode AND
  sparql.round(o) < '"99999.9"^^xsd:decimal'::rdfnode AND
  sparql.round(o) <= '"31360"^^xsd:decimal'::rdfnode AND
  sparql.round(31359.9) = sparql.round(o) AND
  sparql.round('"31359.9"^^xsd:decimal'::rdfnode) = sparql.round(o);

/* SPARQL 17.4.4.3 - ceil */
SELECT p, o, sparql.round(o)
FROM rdbms
WHERE 
  p = sparql.iri('<http://www.wikidata.org/prop/direct/P8687>') AND
  sparql.ceil(o) = sparql.ceil(31359.5) AND
  sparql.ceil(o) > 10000 AND
  sparql.ceil(o) >= sparql.ceil(31359.5) AND
  sparql.ceil(o) < 99999.9 AND
  sparql.ceil(o) <= sparql.ceil(31359.5) AND
  sparql.ceil(o) = '"31360"^^xsd:decimal'::rdfnode AND
  sparql.ceil(o) > '"10000"^^xsd:decimal'::rdfnode AND
  sparql.ceil(o) >= '"31360"^^xsd:decimal'::rdfnode AND
  sparql.ceil(o) < '"99999"^^xsd:decimal'::rdfnode AND
  sparql.ceil(o) <= sparql.ceil('"31359.5"^^xsd:decimal'::rdfnode)  AND
  sparql.ceil(31359.5) = sparql.ceil(o) AND
  sparql.ceil('"31359.5"^^xsd:decimal'::rdfnode) = sparql.ceil(o);

/* SPARQL 17.4.4.4 - floor */
SELECT p, o, sparql.round(o)
FROM rdbms
WHERE 
  p = sparql.iri('<http://www.wikidata.org/prop/direct/P8687>') AND
  sparql.floor(o) = sparql.floor(31360.5) AND
  sparql.floor(o) > 10000 AND
  sparql.floor(o) >= sparql.floor(31360.5) AND
  sparql.floor(o) < 99999.9 AND
  sparql.floor(o) <= sparql.floor(31360.5) AND
  sparql.floor(o) = '"31360"^^xsd:decimal'::rdfnode AND
  sparql.floor(o) > '"10000"^^xsd:decimal'::rdfnode AND
  sparql.floor(o) >= '"31360"^^xsd:decimal'::rdfnode AND
  sparql.floor(o) < '"99999"^^xsd:decimal'::rdfnode AND
  sparql.floor(o) <= sparql.floor('"31360.5"^^xsd:decimal'::rdfnode)  AND
  sparql.floor(31360.5) = sparql.floor(o) AND
  sparql.floor('"31360.5"^^xsd:decimal'::rdfnode) = sparql.floor(o);

/* SPARQL 17.4.4.5 - RAND */
SELECT setseed(0.42);
SELECT 
  sparql.lex(sparql.rand())::numeric BETWEEN 0.0 AND 1.0, 
  sparql.datatype(sparql.rand()) = '<http://www.w3.org/2001/XMLSchema#double>';

/* SPARQL 17.4.5.2 - year*/
SELECT p, o, sparql.year(o)
FROM rdbms
WHERE 
  p = sparql.iri('http://www.wikidata.org/prop/direct/P571') AND
  sparql.year(o) = 1996 AND
  sparql.year(o) > 1990 AND
  sparql.year(o) < 2000 AND
  sparql.year(o) >= 1996 AND
  sparql.year(o) <= 1996 AND
  sparql.year(o) = sparql.year('"1996-01-01T00:00:00Z"^^xsd:dateTime') AND
  sparql.year(o) > sparql.year('"1990-01-12T20:00:00"^^xsd:dateTime') AND
  sparql.year(o) < sparql.year('"2000-01-12T20:00:00"^^xsd:dateTime') AND
  sparql.year(o) >= sparql.year('"1996-01-01T00:00:00Z"^^xsd:dateTime') AND
  sparql.year(o) <= sparql.year('"1996-01-01T00:00:00Z"^^xsd:dateTime');

/* SPARQL 17.4.5.3 - month */
SELECT p, o, sparql.month(o)
FROM rdbms
WHERE 
  p = sparql.iri('<http://www.wikidata.org/prop/direct/P577>') AND
  sparql.month(o) = 07 AND
  sparql.month(o) > 01 AND
  sparql.month(o) < 12 AND
  sparql.month(o) >= 07 AND
  sparql.month(o) <= 07 AND
  sparql.month(o) = sparql.month('"1996-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.month(o) > sparql.month('"1999-01-12T20:00:00"^^xsd:dateTime') AND
  sparql.month(o) < sparql.month('"2000-12-12T20:00:00"^^xsd:dateTime') AND
  sparql.month(o) >= sparql.month('"1996-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.month(o) <= sparql.month('"1996-07-08T00:00:00Z"^^xsd:dateTime');

/* SPARQL 17.4.5.4 - day */
SELECT p, o, sparql.day(o)
FROM rdbms
WHERE 
  p = sparql.iri('<http://www.wikidata.org/prop/direct/P577>') AND
  sparql.day(o) = 08 AND
  sparql.day(o) > 01 AND
  sparql.day(o) < 30 AND
  sparql.day(o) >= 08 AND
  sparql.day(o) <= 08 AND
  sparql.day(o) = sparql.day('"1996-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.day(o) > sparql.day('"1999-01-01T20:00:00"^^xsd:dateTime') AND
  sparql.day(o) < sparql.day('"2000-12-30T20:00:00"^^xsd:dateTime') AND
  sparql.day(o) >= sparql.day('"1996-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.day(o) <= sparql.day('"1996-07-08T00:00:00Z"^^xsd:dateTime');


/* SPARQL 7.4.5.5 - hours */
SELECT p, o, sparql.hours(o)
FROM rdbms
WHERE 
  p = sparql.iri('<http://www.wikidata.org/prop/direct/P577>') AND
  sparql.hours(o) = 0 AND
  sparql.hours(o) > -1 AND
  sparql.hours(o) < 23 AND
  sparql.hours(o) >= 0 AND
  sparql.hours(o) <= 0 AND
  sparql.hours(o) = sparql.hours('"1996-07-08T00:00:00Z"^^xsd:dateTime') AND
  --sparql.hours(o) > sparql.hours('"1999-01-01T20:00:00"^^xsd:dateTime') AND
  sparql.hours(o) < sparql.hours('"2000-12-30T23:00:00"^^xsd:dateTime') AND
  sparql.hours(o) >= sparql.hours('"1996-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.hours(o) <= sparql.hours('"1996-07-08T00:00:00Z"^^xsd:dateTime');

/* SPARQL 17.4.5.6 - minutes */
SELECT p, o, sparql.minutes(o)
FROM rdbms
WHERE 
  p = sparql.iri('<http://www.wikidata.org/prop/direct/P577>') AND
  sparql.minutes(o) = 0 AND
  sparql.minutes(o) > -1 AND
  sparql.minutes(o) < 59 AND
  sparql.minutes(o) >= 0 AND
  sparql.minutes(o) <= 0 AND
  sparql.minutes(o) = sparql.minutes('"1996-07-08T00:00:00Z"^^xsd:dateTime') AND
  --sparql.minutes(o) > sparql.minutes('"1999-01-01T20:00:00"^^xsd:dateTime') AND
  sparql.minutes(o) < sparql.minutes('"2000-12-30T23:59:59"^^xsd:dateTime') AND
  sparql.minutes(o) >= sparql.minutes('"1996-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.minutes(o) <= sparql.minutes('"1996-07-08T00:00:00Z"^^xsd:dateTime');

/* SPARQL 17.4.5.7 - seconds */
SELECT p, o, sparql.ceil(sparql.seconds(o))
FROM rdbms
WHERE 
  p = sparql.iri('<http://www.wikidata.org/prop/direct/P577>') AND
  sparql.seconds(o) = 0 AND
  sparql.seconds(o) > -1 AND
  sparql.seconds(o) < 59 AND
  sparql.seconds(o) >= 0 AND
  sparql.seconds(o) <= 0 AND
  sparql.seconds(o) = sparql.seconds('"1996-07-08T00:00:00Z"^^xsd:dateTime') AND
  --sparql.seconds(o) > sparql.seconds('"1999-01-01T20:00:00"^^xsd:dateTime') AND
  sparql.seconds(o) < sparql.seconds('"2000-12-30T23:59:59"^^xsd:dateTime') AND
  sparql.seconds(o) >= sparql.seconds('"1996-07-08T00:00:00Z"^^xsd:dateTime') AND
  sparql.seconds(o) <= sparql.seconds('"1996-07-08T00:00:00Z"^^xsd:dateTime');


/* SPARQL 17.4.5.8 - timezone */
SELECT sparql.timezone('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');

/* SPARQL 7.4.5.9 - tz */
SELECT sparql.tz('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');

/* SPARQL 17.4.6.1 - MD5 */
SELECT p, o, sparql.md5(o)
FROM rdbms
WHERE 
  p = sparql.iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  sparql.langmatches(sparql.lang(o),'en') AND
  sparql.md5(o) = sparql.md5('"PostgreSQL"@en');

DROP SERVER wikidata CASCADE;