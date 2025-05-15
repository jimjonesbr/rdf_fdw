SET timezone TO 'Etc/UTC';

CREATE SERVER agrovoc
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://agrovoc.fao.org/sparql',
  format 'application/sparql-results+xml',
  query_param 'query'
);

CREATE FOREIGN TABLE country (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
)
SERVER agrovoc OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * {<http://aims.fao.org/aos/agrovoc/c_3963> ?p ?o}');

/* SPARQL 17.4.1.7 - RDFterm-equal */
SELECT p, o FROM country
WHERE 
  p = sparql.iri('http://www.w3.org/2004/02/skos/core#prefLabel') AND
  o = '"Isle of Man"@de';

/* SPARQL 17.4.1.9 - IN */
SELECT p, o FROM country
WHERE
  p = sparql.iri('http://www.w3.org/2004/02/skos/core#prefLabel') AND
  o IN ('"Isle of Man"@de', '"Isla de Man"@es', '"Île de Man"@fr');

/* SPARQL 17.4.1.10 - NOT IN*/
SELECT p, o FROM country
WHERE
  p = sparql.iri('http://www.w3.org/2004/02/skos/core#prefLabel') AND
  o NOT IN ('"Isle of Man"@de', '"Isla de Man"@es', '"Île de Man"@fr')
LIMIT 5;

/* SPARQL 15.5 - LIMIT */
SELECT p, o FROM country
WHERE p = sparql.iri('<http://www.w3.org/2004/02/skos/core#broader>')
LIMIT 5;

SELECT p, o FROM country
WHERE p = sparql.iri('<http://www.w3.org/2004/02/skos/core#broader>')
FETCH FIRST 5 ROWS ONLY;

/* SPARQL 15.4 - OFFSET */
SELECT p, o FROM country
WHERE p = sparql.iri('<http://www.w3.org/2008/05/skos-xl#prefLabel>')
OFFSET 5
LIMIT 10;

SELECT p, o FROM country
WHERE p = sparql.iri('<http://www.w3.org/2008/05/skos-xl#prefLabel>')
OFFSET 5 ROWS
FETCH FIRST 10 ROWS ONLY;

/* SPARQL 15.1 - ORDER BY */
SELECT p, o FROM country
WHERE p = sparql.iri('http://www.w3.org/2004/02/skos/core#prefLabel')
ORDER BY p DESC
FETCH FIRST 3 ROWS ONLY;

SELECT p, o FROM country
WHERE p = sparql.iri('http://www.w3.org/2004/02/skos/core#prefLabel')
ORDER BY o DESC
FETCH FIRST 3 ROWS ONLY;

SELECT p, o FROM country
WHERE p = sparql.iri('http://www.w3.org/2004/02/skos/core#prefLabel')
ORDER BY p DESC, o ASC
FETCH FIRST 3 ROWS ONLY;

SELECT p, o FROM country
WHERE p = sparql.iri('http://www.w3.org/2004/02/skos/core#prefLabel')
ORDER BY p DESC, o ASC
OFFSET 10 ROWS
FETCH FIRST 3 ROWS ONLY;

SELECT p, o FROM country
WHERE p = sparql.iri('http://www.w3.org/2004/02/skos/core#prefLabel')
ORDER BY 1 DESC, 2 ASC
OFFSET 5 ROWS
FETCH FIRST 3 ROWS ONLY;

/* SPARQL 18.2.5.3 - DISTINCT */
SELECT DISTINCT p FROM country
WHERE p = '<http://www.w3.org/2004/02/skos/core#prefLabel>';

SELECT DISTINCT ON (p) p, o FROM country
WHERE p = '<http://www.w3.org/2004/02/skos/core#prefLabel>';

/* SPARQL - 17.3 Operator Mapping (text) */
SELECT p, o FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  p <> '<foo.bar>' AND
  sparql.str(o) >= '"Isle"' AND
  sparql.str(o) <= '"Isle of Man (GB)"' AND
  sparql.str(o) BETWEEN '"Isle"' AND '"Isle of Man (GB)"'
LIMIT 3;

/* SPARQL - 17.3 Operator Mapping (rdfnode) */
SELECT p, o FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  p <> '<foo.bar>' AND
  sparql.str(o) >= '"Isle"'::rdfnode AND
  sparql.str(o) <= '"Isle of Man (GB)"'::rdfnode AND
  sparql.str(o) BETWEEN '"Isle"'::rdfnode AND '"Isle of Man (GB)"'::rdfnode
LIMIT 3;

/* SPARQL - 17.3 Operator Mapping (smallint) */
SELECT p, o FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#m49Code>'::rdfnode AND
  sparql.strdt(o,'xsd:short') = 833::smallint AND
  sparql.strdt(o,'xsd:short') <> 100::smallint AND
  sparql.strdt(o,'xsd:short') >= 833::smallint AND
  sparql.strdt(o,'xsd:short') <= 833::smallint AND
  sparql.strdt(o,'xsd:short') BETWEEN 100 AND 1000 AND
  833::smallint = sparql.strdt(o,'xsd:short') AND
  100::smallint <> sparql.strdt(o,'xsd:short') AND
  833::smallint >= sparql.strdt(o,'xsd:short') AND
  833::smallint <= sparql.strdt(o,'xsd:short');

/* SPARQL - 17.3 Operator Mapping (smallint) */
SELECT p, o FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#m49Code>'::rdfnode AND
  sparql.strdt(o,'xsd:int') = 833::int AND
  sparql.strdt(o,'xsd:int') <> 100::int AND
  sparql.strdt(o,'xsd:int') >= 833::int AND
  sparql.strdt(o,'xsd:int') <= 833::int AND
  sparql.strdt(o,'xsd:int') BETWEEN 100 AND 1000 AND
  833::int = sparql.strdt(o,'xsd:int') AND
  100::int <> sparql.strdt(o,'xsd:int') AND
  833::int >= sparql.strdt(o,'xsd:int') AND
  833::int <= sparql.strdt(o,'xsd:int');

/* SPARQL - 17.3 Operator Mapping (bigint) */
SELECT p, o FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#m49Code>'::rdfnode AND
  sparql.strdt(o,'xsd:long') = 833::bigint AND
  sparql.strdt(o,'xsd:long') <> 100::bigint AND
  sparql.strdt(o,'xsd:long') >= 833::bigint AND
  sparql.strdt(o,'xsd:long') <= 833::bigint AND
  sparql.strdt(o,'xsd:long') BETWEEN 100 AND 1000 AND
  833::bigint = sparql.strdt(o,'xsd:long') AND
  100::bigint <> sparql.strdt(o,'xsd:long') AND
  833::bigint >= sparql.strdt(o,'xsd:long') AND
  833::bigint <= sparql.strdt(o,'xsd:long');

/* SPARQL - 17.3 Operator Mapping (real) */
SELECT p, o FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#m49Code>'::rdfnode AND
  sparql.strdt(o,'xsd:float') = 833.0::real AND
  sparql.strdt(o,'xsd:float') <> 100::real AND
  sparql.strdt(o,'xsd:float') >= 833.0::real AND
  sparql.strdt(o,'xsd:float') <= 833.0::real AND
  sparql.strdt(o,'xsd:float') BETWEEN 100 AND 1000 AND
  833.0::real = sparql.strdt(o,'xsd:float') AND
  100::real <> sparql.strdt(o,'xsd:float') AND
  833.0::real >= sparql.strdt(o,'xsd:float') AND
  833.0::real <= sparql.strdt(o,'xsd:float');

/* SPARQL - 17.3 Operator Mapping (double precision) */
SELECT p, o FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#m49Code>'::rdfnode AND
  sparql.strdt(o,'xsd:double') = 833.0::double precision AND
  sparql.strdt(o,'xsd:double') <> 100::double precision AND
  sparql.strdt(o,'xsd:double') >= 833.0::double precision AND
  sparql.strdt(o,'xsd:double') <= 833.0::double precision AND
  sparql.strdt(o,'xsd:double') BETWEEN 100 AND 1000 AND
  833.0::double precision = sparql.strdt(o,'xsd:double') AND
  100::double precision <> sparql.strdt(o,'xsd:double') AND
  833.0::double precision >= sparql.strdt(o,'xsd:double') AND
  833.0::double precision <= sparql.strdt(o,'xsd:double');

/* SPARQL - 17.3 Operator Mapping (numeric) */
SELECT p, o FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#m49Code>'::rdfnode AND
  sparql.strdt(o,'xsd:decimal') = 833.0::numeric AND
  sparql.strdt(o,'xsd:decimal') <> 100::numeric AND
  sparql.strdt(o,'xsd:decimal') >= 833.0::numeric AND
  sparql.strdt(o,'xsd:decimal') <= 833.0::numeric AND
  sparql.strdt(o,'xsd:decimal') BETWEEN 100 AND 1000 AND
  833.0::numeric = sparql.strdt(o,'xsd:decimal') AND
  100::numeric <> sparql.strdt(o,'xsd:decimal') AND
  833.0::numeric >= sparql.strdt(o,'xsd:decimal') AND
  833.0::numeric <= sparql.strdt(o,'xsd:decimal');

/* SPARQL - 17.3 Operator Mapping (timestamp) */
SELECT p, o FROM country
WHERE 
  p = '<http://purl.org/dc/terms/modified>'::rdfnode AND
  o = '2024-02-13 14:30:39'::timestamp AND
  o <> '1990-11-20 20:44:42'::timestamp AND
  o >= '2024-02-13 14:30:39'::timestamp AND
  o <= '2024-02-13 14:30:39'::timestamp AND
  o BETWEEN '2000-01-01 00:00:00'::timestamp AND '2025-01-01 00:00:00'::timestamp AND
  '2024-02-13 14:30:39'::timestamp = o AND
  '2000-01-31 18:30:00'::timestamp <> o AND
  '2024-02-13 14:30:39'::timestamp <= o AND
  '2024-02-13 14:30:39'::timestamp >= o;

/* SPARQL - 17.3 Operator Mapping (timestamptz) */
SELECT p, o FROM country
WHERE 
  p = '<http://purl.org/dc/terms/created>'::rdfnode AND
  o = '2011-11-20 20:44:42'::timestamptz AND
  o <> '2000-01-31 18:30:00'::timestamptz AND
  o >= '2011-11-20 20:44:42'::timestamptz AND
  o <= '2011-11-20 20:44:42'::timestamptz AND
  o BETWEEN '2000-01-01 00:00:00'::timestamptz AND '2025-01-01 00:00:00'::timestamptz AND
  '2011-11-20 20:44:42'::timestamptz = o AND
  '2000-01-31 18:30:00'::timestamptz <> o AND
  '2011-11-20 20:44:42'::timestamptz <= o AND
  '2011-11-20 20:44:42'::timestamptz >= o;

/* SPARQL - 17.3 Operator Mapping (date) */
SELECT p, o FROM country
WHERE 
  p = '<http://purl.org/dc/terms/created>'::rdfnode AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') = '2011-11-20'::date AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') <> '2000-01-01'::date AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') >= '2011-11-20'::date AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') <= '2011-11-20'::date AND
  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') BETWEEN '1990-01-01'::date AND '2011-11-20'::date AND
  '2011-11-20'::date =  sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') AND
  '2000-01-01'::date <> sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') AND
  '2011-11-20'::date <= sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date') AND
  '2011-11-20'::date >= sparql.strdt(sparql.substr(sparql.str(o), 1, 10),'xsd:date');

/* SPARQL - 17.3 Operator Mapping (timetz) */
SELECT p, o, sparql.timezone(o), sparql.tz(o) FROM country
WHERE 
  p = '<http://purl.org/dc/terms/created>'::rdfnode AND
  sparql.tz(o) = 'Z' AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') = '20:44:42'::time AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') <> '23:00:00'::time AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') >='20:44:42'::time AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') <= '20:44:42'::time AND
  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') BETWEEN '00:00:00'::time AND '23:44:42'::time AND
  '20:44:42'::time =  sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') AND
  '23:00:00'::time <> sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') AND
  '20:44:42'::time <= sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time') AND
  '20:44:42'::time >= sparql.strdt(sparql.substr(sparql.str(o), 12, 8),'xsd:time');

/* SPARQL - 17.3 Operator Mapping (boolean) */
SELECT p, o FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#broader>'::rdfnode AND
  o = false AND
  false = o;

/* SPARQL 17.4.1.1 - BOUND */
CREATE FOREIGN TABLE country2 (
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o'),
  x rdfnode OPTIONS (variable '?x')
)
SERVER agrovoc OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * {<http://aims.fao.org/aos/agrovoc/c_3963> ?p ?o OPTIONAL { ?o <http://foo.bar> ?x }}');

SELECT p, o, sparql.bound(p), sparql.bound(x)
FROM country2
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.langmatches(sparql.lang(o),'es') AND
  sparql.bound(o) AND
  NOT sparql.bound(x);

/* SPARQL 17.4.1.3 - COALESCE */
SELECT p, o, x, sparql.coalesce(x, o, p)
FROM country2
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.coalesce(x, o) = '"Isle of Man"@de' AND
  sparql.coalesce(x, x, o) = '"Isle of Man"@de' AND
  sparql.coalesce(x, p) = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.coalesce(x, x, p) = '<http://www.w3.org/2004/02/skos/core#prefLabel>';

/* SPARQL 17.4.1.8 - sameTerm */
SELECT p, o, sparql.sameterm(o,'"Île de Man"@fr')
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.sameterm(o,'"Île de Man"@fr') AND
  sparql.sameterm(p,'<http://www.w3.org/2004/02/skos/core#prefLabel>');

/* SPARQL 17.4.1.9 - IN */
SELECT p, o
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  o IN ('"Isle of Man"@de'::rdfnode, '"Île de Man"@fr', sparql.strlang('Isla de Man','es'));

/* SPARQL 17.4.1.10 - NOT IN */
SELECT p, o
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  o NOT IN ('"Isle of Man"@de'::rdfnode, '"Île de Man"@fr', sparql.strlang('Isla de Man','es'))
FETCH FIRST 3 ROWS ONLY;

/* SPARQL 17.4.2.1 - isIRI */
SELECT p, o, sparql.isIRI(p), sparql.isIRI(o) FROM country 
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#isPartOfSubvocabulary>' AND
  sparql.isIRI(p) AND
  NOT sparql.isIRI(o);

/* SPARQL 17.4.2.2 - isBlank */
SELECT p, o, sparql.bnode(o), sparql.isblank(o) FROM country
WHERE sparql.isblank(sparql.bnode(o));

/* SPARQL 17.4.2.3 - isLiteral */
SELECT p, o, sparql.isliteral(o), sparql.isliteral(p) FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#isPartOfSubvocabulary>' AND
  sparql.isliteral(o) AND 
  NOT sparql.isliteral(p);

/* SPARQL 17.4.2.4 - isNumeric */
SELECT p, o, sparql.strdt(o,'xsd:short'), sparql.isnumeric(o), sparql.isnumeric(p) FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#m49Code>'::rdfnode AND
  sparql.isnumeric(sparql.strdt(o,'xsd:short')) AND
  NOT sparql.isnumeric(p);

/* SPARQL 17.4.2.5 - str */
SELECT p, o, sparql.str(o)
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.str(o) = sparql.str('"Ilha de Man"@pt');

/* SPARQL 17.4.2.6 - lang */
SELECT p, o, sparql.lang(o)
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.lang(o) = sparql.lang('"Isla de Man"@es');

/* SPARQL 17.4.2.7 - datatype */
SELECT p, o, sparql.datatype(o)
FROM country
WHERE
  p = '<http://purl.org/dc/terms/created>' AND
  sparql.datatype(o) = sparql.datatype('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.datatype('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') = sparql.datatype(o);

/* SPARQL 17.4.2.8 - IRI */
SELECT p, o, sparql.iri(p)
FROM country
WHERE 
  sparql.iri(p) = sparql.iri('http://purl.org/dc/terms/created') AND
  sparql.iri('<http://purl.org/dc/terms/created>') = sparql.iri(p) AND
  sparql.iri('http://purl.org/dc/terms/created') = p AND
  p = sparql.iri('http://purl.org/dc/terms/created');

/* SPARQL 17.4.2.9 - BNODE */
SELECT p, o, sparql.bnode(o)
FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#isPartOfSubvocabulary>' AND
  sparql.isblank(sparql.bnode(o));

/* SPARQL 17.4.2.10 - STRDT */
SELECT p, o, sparql.strdt(o,'xsd:string')
FROM country
WHERE 
  p = sparql.iri('<http://aims.fao.org/aos/agrontology#m49Code>') AND
  '"833"^^xsd:string'::rdfnode = sparql.strdt(sparql.str(o),'xsd:string') AND
  sparql.strdt(sparql.str(o),'xsd:string') = '"833"^^xsd:string'::rdfnode  AND
  sparql.strdt(sparql.str('"833"^^xsd:integer'),'xsd:string') = sparql.strdt(sparql.str(o),'xsd:string') AND
  sparql.strdt(sparql.str(o),'xsd:string') = sparql.strdt(sparql.str('"833"^^xsd:integer'),'xsd:string');

/* SPARQL 17.4.2.11 - STRLANG */
SELECT p, o, sparql.strlang(o,'en')
FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#isPartOfSubvocabulary>' AND
  sparql.strlang(sparql.str(o),'en') = sparql.strlang('"Geographical below country level"', 'en') AND
  sparql.strlang('"Geographical below country level"', 'en') = sparql.strlang(sparql.str(o),'en') AND
  sparql.strlang('"Geographical below country level"', 'en') = '"Geographical below country level"@en' AND
  '"Geographical below country level"@en' = sparql.strlang('"Geographical below country level"', 'en');

/* SPARQL 17.4.2.12 - UUID (not pushable) */
SELECT sparql.uuid()::text ~ '^<urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}>$';

/*SPARQL 17.4.2.13 - STRUUID (not pushable) */
SELECT sparql.struuid()::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

/* SPARQL 17.4.3.2 - STRLEN */
SELECT p, o, sparql.strlen(o)
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.langmatches(sparql.lang(o),'de') AND
  sparql.strlen(o) = sparql.strlen('"Isle of Man"@de') AND
  sparql.strlen(o) = 11 AND
  11 = sparql.strlen(o);

/* SPARQL 17.4.3.3 - SUBSTR */
SELECT p, o, sparql.substr(o, 9, 3)
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.langmatches(sparql.lang(o),'es') AND
  sparql.substr(o, 9, 3) = sparql.substr('"Isla de Man"@es', 9, 3) AND
  sparql.substr('"Isla de Man"@es', 9, 3) = sparql.substr(o, 9, 3);

/* SPARQL 17.4.3.4 - UCASE */
SELECT p, o, sparql.ucase(o)
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.ucase(o) = sparql.ucase('"Île de Man"@fr') AND
  sparql.ucase(o) = '"ÎLE DE MAN"@fr' AND
  '"ÎLE DE MAN"@fr' = sparql.ucase(o);

/* SPARQL 17.4.3.5 - LCASE */
SELECT p, o, sparql.lcase(o)
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.lcase(o) = sparql.lcase('"Ilha de Man"@pt') AND
  sparql.lcase(o) = '"ilha de man"@pt' AND
  '"ilha de man"@pt' = sparql.lcase(o);

/* SPARQL 17.4.3.6 - STRSTARTS */
SELECT p, o, sparql.strstarts(o, sparql.str('"Isle"@de'))
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.langmatches(sparql.lang(o),'de') AND
  sparql.strstarts(o,'"Isle"@de');

/* SPARQL 17.4.3.7 - STRENDS */
SELECT p, o, sparql.strends(o, sparql.str('"de Man"@pt'))
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.langmatches(sparql.lang(o),'pt') AND
  sparql.strends(o,'"de Man"@pt');

/* SPARQL 17.4.3.8 - CONTAINS */
SELECT p, o, sparql.contains(o,'"Isla"@es'), sparql.contains(o,'"Isla"^^xsd:string')
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.langmatches(sparql.lang(o),'es') AND
  sparql.contains(o,'"Isla"@') AND
  sparql.contains(o,'"Man"');

/* SPARQL 17.4.3.9 - STRBEFORE */
SELECT p, o, sparql.strbefore(sparql.str(o), '"of Man"')
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.langmatches(sparql.lang(o),'en') AND
  sparql.strbefore(sparql.str(o), '" of Man"') = sparql.strbefore(sparql.str('"Isle of Man"@en'),'" of Man"') AND
  sparql.strbefore(sparql.str(o), '" of Man"') = '"Isle"' AND
  '"Isle"' = sparql.strbefore(sparql.str(o), '" of Man"');

/* SPARQL 17.4.3.10 - STRAFTER */
SELECT p, o, sparql.strafter(sparql.str(o), '"Isla "')
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.langmatches(sparql.lang(o),'es') AND
  sparql.strafter(sparql.str(o), '"Isla "') = sparql.strafter(sparql.str('"Isla de Man"@es'),'"Isla "') AND
  sparql.strafter(sparql.str(o), '"Isla "') = '"de Man"'::rdfnode AND
  '"de Man"' = sparql.strafter(sparql.str(o), '"Isla "');

/* SPARQL 17.4.3.11 - ENCODE_FOR_URI */
SELECT p, o, sparql.encode_for_uri(o)
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.langmatches(sparql.lang(o),'de') AND
  sparql.encode_for_uri(o) = sparql.encode_for_uri('"Isle of Man"@de') AND
  sparql.encode_for_uri(o) = '"Isle%20of%20Man"' AND 
  '"Isle%20of%20Man"' = sparql.encode_for_uri(o);

/* 17.4.3.12 - CONCAT */
SELECT p, o, sparql.concat(o,sparql.strlang(' (GB)','pt')), sparql.concat(o,'" (GB)"^^xsd:string')
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.langmatches(sparql.lang(o),'pt') AND
  sparql.concat(o,' (GB)') = sparql.concat('"Ilha de Man"@pt','" (GB)"') AND
  sparql.concat('"Ilha de Man"@pt','" (GB)"') = sparql.concat(o,' (GB)');

/* SPARQL 17.4.3.13 - langMatches */
SELECT p, o, sparql.langmatches(sparql.lang(o),'*'),  sparql.langmatches(sparql.lang(o),'fr'),  sparql.langmatches(sparql.lang(o),'de')
FROM country
WHERE sparql.langmatches(sparql.lang(o),'fr');

/* SPARQL 17.4.3.14 - REGEX */
SELECT p, o
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.langmatches(sparql.lang(o),'en') AND
  sparql.regex(o, sparql.ucase('isle'), 'i') AND 
  sparql.regex(o, '^iSl','i');

/* SPARQL 17.4.3.15 - REPLACE */
SELECT p, o, sparql.replace(o,'Isla','La Isla'), sparql.replace(o,'"Isla"@fr','La Isla')
FROM country
WHERE 
  p = '<http://www.w3.org/2004/02/skos/core#prefLabel>' AND
  sparql.langmatches(sparql.lang(o),'es') AND
  sparql.replace(sparql.str(o),'Isla','La Isla') = '"La Isla de Man"'::rdfnode AND
  '"La Isla de Man"' = sparql.replace(sparql.str(o),'Isla','La Isla') AND
  sparql.replace(sparql.str(o), 'ISLA', 'La Isla','i') = sparql.replace('"Isla de Man"', 'ISLA', 'La Isla','i');

/* SPARQL 17.4.4.1 - abs */
SELECT p, o, sparql.abs(sparql.strdt(o,'xsd:long')) FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#m49Code>'::rdfnode AND
  sparql.abs(sparql.strdt(o,'xsd:long')) = 833::bigint AND
  sparql.abs(sparql.strdt(o,'xsd:long')) <> 100::bigint AND
  sparql.abs(sparql.strdt(o,'xsd:long')) >= 833::bigint AND
  sparql.abs(sparql.strdt(o,'xsd:long')) <= 833::bigint AND
  sparql.abs(sparql.strdt(o,'xsd:long')) BETWEEN 100::bigint AND 1000::bigint AND
  sparql.abs(sparql.strdt(o,'xsd:long')) =  '"833"^^xsd:long'::rdfnode AND
  sparql.abs(sparql.strdt(o,'xsd:long')) >  '"100"^^xsd:long'::rdfnode AND
  sparql.abs(sparql.strdt(o,'xsd:long')) >= '"833"^^xsd:long'::rdfnode AND
  sparql.abs(sparql.strdt(o,'xsd:long')) <  '"999"^^xsd:long'::rdfnode AND
  sparql.abs(sparql.strdt(o,'xsd:long')) <= '"833"^^xsd:long'::rdfnode AND
  833::bigint = sparql.abs(sparql.strdt(o,'xsd:long')) AND
  '"833"^^xsd:long'::rdfnode = sparql.abs(sparql.strdt(o,'xsd:long'));

/* SPARQL 17.4.4.2 - round */
SELECT p, o, sparql.round(o)
FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#m49Code>'::rdfnode AND
  sparql.round(sparql.strdt(o,'xsd:long')) = sparql.round(832.9::bigint) AND
  sparql.round(sparql.strdt(o,'xsd:long')) <> 100::bigint AND
  sparql.round(sparql.strdt(o,'xsd:long')) >= sparql.round(832.9::bigint) AND
  sparql.round(sparql.strdt(o,'xsd:long')) <= sparql.round(832.9::bigint) AND
  sparql.round(sparql.strdt(o,'xsd:long')) BETWEEN 100::bigint AND 1000::bigint AND
  sparql.round(sparql.strdt(o,'xsd:long')) =  sparql.round('"832.9"^^xsd:long'::rdfnode) AND
  sparql.round(sparql.strdt(o,'xsd:long')) >  '"100"^^xsd:long'::rdfnode AND
  sparql.round(sparql.strdt(o,'xsd:long')) >= sparql.round('"832.9"^^xsd:long'::rdfnode) AND
  sparql.round(sparql.strdt(o,'xsd:long')) <  '"999"^^xsd:long'::rdfnode AND
  sparql.round(sparql.strdt(o,'xsd:long')) <= sparql.round('"832.9"^^xsd:long'::rdfnode)AND
  sparql.round(832.9::bigint) = sparql.round(sparql.strdt(o,'xsd:long')) AND
  sparql.round('"832.9"^^xsd:long'::rdfnode) = sparql.round(sparql.strdt(o,'xsd:long'));

/* SPARQL 17.4.4.3 - ceil */
SELECT p, o, sparql.ceil(o)
FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#m49Code>'::rdfnode AND
  sparql.ceil(sparql.strdt(o,'xsd:long')) = sparql.ceil(832.9) AND
  sparql.ceil(sparql.strdt(o,'xsd:long')) <> 100 AND
  sparql.ceil(sparql.strdt(o,'xsd:long')) >= sparql.ceil(832.9) AND
  sparql.ceil(sparql.strdt(o,'xsd:long')) <= sparql.ceil(832.9) AND
  sparql.ceil(sparql.strdt(o,'xsd:long')) BETWEEN 100 AND 1000 AND
  sparql.ceil(sparql.strdt(o,'xsd:long')) =  sparql.ceil('"832.9"^^xsd:long'::rdfnode) AND
  sparql.ceil(sparql.strdt(o,'xsd:long')) >  '"100"^^xsd:long'::rdfnode AND
  sparql.ceil(sparql.strdt(o,'xsd:long')) >= sparql.ceil('"832.9"^^xsd:long'::rdfnode) AND
  sparql.ceil(sparql.strdt(o,'xsd:long')) <  '"999"^^xsd:long'::rdfnode AND
  sparql.ceil(sparql.strdt(o,'xsd:long')) <= sparql.ceil('"832.9"^^xsd:long'::rdfnode)AND
  sparql.ceil(832.9) = sparql.ceil(sparql.strdt(o,'xsd:long')) AND
  sparql.ceil('"832.9"^^xsd:long'::rdfnode) = sparql.ceil(sparql.strdt(o,'xsd:long'));

/* SPARQL 17.4.4.4 - floor */
SELECT p, o, sparql.floor(o)
FROM country
WHERE 
  p = '<http://aims.fao.org/aos/agrontology#m49Code>'::rdfnode AND
  sparql.floor(sparql.strdt(o,'xsd:long')) = sparql.floor(833.5) AND
  sparql.floor(sparql.strdt(o,'xsd:long')) <> 100 AND
  sparql.floor(sparql.strdt(o,'xsd:long')) >= sparql.floor(833.5) AND
  sparql.floor(sparql.strdt(o,'xsd:long')) <= sparql.floor(833.5) AND
  sparql.floor(sparql.strdt(o,'xsd:long')) BETWEEN 100 AND 1000 AND
  sparql.floor(sparql.strdt(o,'xsd:long')) =  sparql.floor('"833.5"^^xsd:long'::rdfnode) AND
  sparql.floor(sparql.strdt(o,'xsd:long')) >  '"100"^^xsd:long'::rdfnode AND
  sparql.floor(sparql.strdt(o,'xsd:long')) >= sparql.floor('"833.5"^^xsd:long'::rdfnode) AND
  sparql.floor(sparql.strdt(o,'xsd:long')) <  '"999"^^xsd:long'::rdfnode AND
  sparql.floor(sparql.strdt(o,'xsd:long')) <= sparql.floor('"833.5"^^xsd:long'::rdfnode)AND
  sparql.floor(833.5) = sparql.floor(sparql.strdt(o,'xsd:long')) AND
  sparql.floor('"833.5"^^xsd:long'::rdfnode) = sparql.floor(sparql.strdt(o,'xsd:long'));

/* SPARQL 17.4.4.5 - RAND */
SELECT setseed(0.42);
SELECT 
  sparql.lex(sparql.rand())::numeric BETWEEN 0.0 AND 1.0, 
  sparql.datatype(sparql.rand()) = '<http://www.w3.org/2001/XMLSchema#double>';

/* SPARQL 17.4.5.2 - year*/
SELECT p, o, sparql.year(o)
FROM country
WHERE 
  p = '<http://purl.org/dc/terms/created>' AND
  sparql.year(o) = 2011 AND
  sparql.year(o) > 2000 AND
  sparql.year(o) < 2020 AND
  sparql.year(o) >= 2011 AND
  sparql.year(o) <= 2011 AND
  sparql.year(o) = sparql.year('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.year(o) > sparql.year('"1990-01-12T20:00:00"^^xsd:dateTime') AND
  sparql.year(o) < sparql.year('"2020-01-12T20:00:00"^^xsd:dateTime') AND
  sparql.year(o) >= sparql.year('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.year(o) <= sparql.year('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>');

/* SPARQL 17.4.5.3 - month */
SELECT p, o, sparql.month(o)
FROM country
WHERE 
  p = '<http://purl.org/dc/terms/created>' AND
  sparql.month(o) = 11 AND
  sparql.month(o) > 01 AND
  sparql.month(o) < 12 AND
  sparql.month(o) >= 11 AND
  sparql.month(o) <= 11 AND
  sparql.month(o) = sparql.month('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.month(o) > sparql.month('"1990-01-12T20:00:00"^^xsd:dateTime') AND
  sparql.month(o) < sparql.month('"2020-12-12T20:00:00"^^xsd:dateTime') AND
  sparql.month(o) >= sparql.month('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.month(o) <= sparql.month('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>');

/* SPARQL 17.4.5.4 - day */
SELECT p, o, sparql.day(o)
FROM country
WHERE 
  p = '<http://purl.org/dc/terms/created>' AND
  sparql.day(o) = 20 AND
  sparql.day(o) > 01 AND
  sparql.day(o) < 30 AND
  sparql.day(o) >= 20 AND
  sparql.day(o) <= 20 AND
  sparql.day(o) = sparql.day('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.day(o) > sparql.day('"1990-01-01T20:00:00"^^xsd:dateTime') AND
  sparql.day(o) < sparql.day('"2020-12-30T20:00:00"^^xsd:dateTime') AND
  sparql.day(o) >= sparql.day('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.day(o) <= sparql.day('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>');

/* SPARQL 7.4.5.5 - hours */
SELECT p, o, sparql.hours(o)
FROM country
WHERE 
  p = '<http://purl.org/dc/terms/created>' AND
  sparql.hours(o) = 20 AND
  sparql.hours(o) > 01 AND
  sparql.hours(o) < 23 AND
  sparql.hours(o) >= 20 AND
  sparql.hours(o) <= 20 AND
  sparql.hours(o) = sparql.hours('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.hours(o) > sparql.hours('"1990-01-01T01:00:00"^^xsd:dateTime') AND
  sparql.hours(o) < sparql.hours('"2020-12-30T23:00:00"^^xsd:dateTime') AND
  sparql.hours(o) >= sparql.hours('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.hours(o) <= sparql.hours('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>');

/* SPARQL 7.4.5.5 - minutes */
SELECT p, o, sparql.minutes(o)
FROM country
WHERE 
  p = '<http://purl.org/dc/terms/created>' AND
  sparql.minutes(o) = 44 AND
  sparql.minutes(o) > 01 AND
  sparql.minutes(o) < 60 AND
  sparql.minutes(o) >= 44 AND
  sparql.minutes(o) <= 44 AND
  sparql.minutes(o) = sparql.minutes('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.minutes(o) > sparql.minutes('"1990-01-01T01:01:00"^^xsd:dateTime') AND
  sparql.minutes(o) < sparql.minutes('"2020-12-30T23:59:00"^^xsd:dateTime') AND
  sparql.minutes(o) >= sparql.minutes('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.minutes(o) <= sparql.minutes('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>');

/* SPARQL 17.4.5.7 - seconds */
SELECT p, o, sparql.ceil(sparql.seconds(o))
FROM country
WHERE 
  p = '<http://purl.org/dc/terms/created>' AND
  sparql.seconds(o) = 42 AND
  sparql.seconds(o) > 01 AND
  sparql.seconds(o) < 59 AND
  sparql.seconds(o) >= 42 AND
  sparql.seconds(o) <= 42 AND
  sparql.seconds(o) = sparql.seconds('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.seconds(o) > sparql.seconds('"1990-01-01T01:01:01"^^xsd:dateTime') AND
  sparql.seconds(o) < sparql.seconds('"2020-12-30T23:59:59"^^xsd:dateTime') AND
  sparql.seconds(o) >= sparql.seconds('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>') AND
  sparql.seconds(o) <= sparql.seconds('"2011-11-20T20:44:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>');


/* SPARQL 17.4.5.8 - timezone */
SELECT sparql.timezone('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');

/* SPARQL 7.4.5.9 - tz */
SELECT sparql.tz('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');

/* SPARQL 17.4.6.1 - MD5 */
SELECT p, o, sparql.md5(o)
FROM country
WHERE 
  p = sparql.iri('http://www.w3.org/2004/02/skos/core#prefLabel') AND
  sparql.langmatches(sparql.lang(o),'en') AND
  sparql.md5(sparql.str(o)) = sparql.md5('"Isle of Man"');

DROP SERVER wikidata CASCADE;