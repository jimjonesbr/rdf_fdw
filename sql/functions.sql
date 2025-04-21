\pset null NULL

SET search_path TO sparql, pg_catalog;

CREATE SERVER dbpedia 
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

CREATE FOREIGN TABLE ftdbp (
  p text    OPTIONS (variable '?p', literal_format 'raw'),
  o text    OPTIONS (variable '?o', literal_format 'raw')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * WHERE { <http://dbpedia.org/resource/PostgreSQL> ?p ?o }');

SELECT rdf_fdw_arguments_compatible('"abc"','"b"');
SELECT rdf_fdw_arguments_compatible('"abc"','"b"^^<xsd:string>');
SELECT rdf_fdw_arguments_compatible('"abc"^^<xsd:string>','"b"');
SELECT rdf_fdw_arguments_compatible('"abc"^^<xsd:string>','"b"^^<xsd:string>');
SELECT rdf_fdw_arguments_compatible('"abc"@en','"b"');
SELECT rdf_fdw_arguments_compatible('"abc"@en','"b"^^xsd:string');
SELECT rdf_fdw_arguments_compatible('"abc"@en','"b"@en');
SELECT rdf_fdw_arguments_compatible('"abc"@fr','"b"@ja');
SELECT rdf_fdw_arguments_compatible('"abc"','"b"@ja');
SELECT rdf_fdw_arguments_compatible('"abc"','"b"@en');
SELECT rdf_fdw_arguments_compatible('"abc"^^xsd:string','"b"@en');

/* LEX */  
SELECT lex('"foo"');
SELECT lex('foo');
SELECT lex('"foo"@en');
SELECT lex('"foo"^^xsd:string');
SELECT lex(''); 
SELECT lex('""');
SELECT lex('"\""');
SELECT lex(NULL);

/* STRDT */
SELECT strdt(NULL, 'http://www.w3.org/2001/XMLSchema#string');
SELECT strdt('foo', NULL);
SELECT strdt('', '<http://example.org/type>');
SELECT strdt('foo', '');
SELECT strdt('foo', ' ');
SELECT strdt('foo', ' xsd:boolean ');
SELECT strdt('foo', 'http://www.w3.org/2001/XMLSchema#string');
SELECT strdt('f"oo', 'http://example.org/type');
SELECT strdt('"foo"@en', 'http://www.w3.org/2001/XMLSchema#int');
SELECT strdt('"f\"oo"^^xsd:string', 'http://example.org/newtype');
SELECT strdt('foo', '<http://example.org/type>');
SELECT strdt('foo', 'foo:bar');
SELECT strdt('foo', 'xsd:string');
SELECT strdt('foo', '<nonsense>');

SELECT p, o, strdt(o,'xsd:string')
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  strdt(o,'xsd:string') = strdt('PostgreSQL','xsd:string') AND
  langmatches(lang(o),'en');

/* STRLANG */
SELECT strlang('foo',NULL);
SELECT strlang(NULL,'de');
SELECT strlang('','es');
SELECT strlang(' ','en');
SELECT strlang('foo','pt');
SELECT strlang('"foo"@en','fr');
SELECT strlang('"foo"','it');
SELECT strlang('"foo"^^xsd:string','pt');
SELECT strlang('"foo"^^<http://www.w3.org/2001/XMLSchema#string>','es');
SELECT strlang(strlang('"foo"^^<http://www.w3.org/2001/XMLSchema#string>','es'),'de');
SELECT strlang(strlang('f"o"o','en'),'de');
SELECT strlang(strlang('x\"y','pl'),'it');
SELECT strlang('foo', 'xyz');

SELECT p, o, strlang(o,'fr')
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'de') AND
  lang(strlang(o,'fr')) = 'fr';

/* STR */
SELECT str('foo');
SELECT str('"foo"');
SELECT str('"foo"@en');
SELECT str('"foo"^^xsd:string');
SELECT str('f"oo');
SELECT str('"f\"oo"');
SELECT str('<http://example.org/foo>');
SELECT str('');
SELECT str(' ');
SELECT str(NULL);

SELECT p, o, str(o)
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'es') AND
  str(o) = str('PostgreSQL') AND str(o) = '"PostgreSQL"';

/* LANG */
SELECT lang('"foo"@en');
SELECT lang(strlang('foo','fr'));
SELECT lang(strdt('foo','xsd:string'));
SELECT lang('"f"oo"@it');
SELECT lang('');
SELECT lang(' ');
SELECT lang(NULL);
SELECT lang('<http://example.org>'); 

SELECT p, o, lang(o)
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  lang(o) = 'es';

/* DATATYPE */
SELECT datatype('"foo"^^xsd:string');
SELECT datatype('"foo"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT datatype(strdt('foo','xsd:string'));
SELECT datatype('"42"^^<xsd:int>');
SELECT datatype(strdt('foo','bar:xyz'));
SELECT datatype('"foo"@es');
SELECT datatype('');
SELECT datatype(' ');
SELECT datatype('"foo"^<xsd:string>');
SELECT datatype('"foo"^^xsd:string>');
SELECT datatype('"foo"^^<xsd:string');
SELECT datatype(cast('2018-05-01' AS date));
SELECT datatype(cast('2018-05-01 11:30:00' AS timestamp without time zone));
SELECT datatype(cast('2018-05-01 11:30:00' AS timestamp with time zone));
SELECT datatype(cast('11:30:00' AS time));
SELECT datatype(42);
SELECT datatype(42.73);
SELECT datatype(cast(42 AS smallint));
SELECT datatype(cast(42 AS bigint));
SELECT datatype(cast(42.73 AS double precision));
SELECT datatype(cast(42.73 AS numeric));
SELECT datatype(cast(42.73 AS real));
SELECT datatype(true);



SELECT datatype(NULL);

SELECT p, o, datatype(o)
FROM ftdbp 
WHERE 
  datatype(o) = iri('http://www.w3.org/2001/XMLSchema#nonNegativeInteger') AND
  datatype(o) = iri('"http://www.w3.org/2001/XMLSchema#nonNegativeInteger"') AND
  datatype(o) = '<http://www.w3.org/2001/XMLSchema#nonNegativeInteger>';

/* ENCODES_FOR_URI */
SELECT encode_for_uri('"Los Angeles"');
SELECT encode_for_uri('"Los Angeles"@en');
SELECT encode_for_uri('"Los Angeles"^^xsd:string');
SELECT encode_for_uri('"Los Angeles"^^<xsd:string>');
SELECT encode_for_uri('"Los Angeles"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT encode_for_uri('foo! *''();:@&=+$,/?#[]');
SELECT encode_for_uri('foo');
SELECT encode_for_uri('');
SELECT encode_for_uri(NULL);

SELECT p, o, encode_for_uri(o)
FROM ftdbp
WHERE 
  p = iri('http://dbpedia.org/property/developer') AND
  encode_for_uri(o) = encode_for_uri('PostgreSQL Global Development Group') AND
  encode_for_uri(o) = encode_for_uri(strlang('PostgreSQL Global Development Group','de'));

/* IRI / URI */
SELECT iri('"http://example/"'), iri('http://example/'), iri('<http://example/>');
SELECT iri('"mailto:foo@example.com"'), iri('mailto:foo@example.com'), iri('<mailto:foo@example.com>');
SELECT iri('"urn:uuid:123e4567-e89b-12d3-a456-426614174000"'), iri('urn:uuid:123e4567-e89b-12d3-a456-426614174000'), iri('<urn:uuid:123e4567-e89b-12d3-a456-426614174000>');
SELECT iri('"file://etc/passwd"'), iri('file://etc/passwd'), iri('<file://etc/passwd>');
SELECT iri('"foo:bar"'), iri('foo:bar'), iri('<foo:bar>');
SELECT iri('"foo"'), iri('foo'), iri('<foo>');
SELECT iri('"a:b:c"'), iri('a:b:c'), iri('<a:b:c>');
SELECT iri('"http:/not-a-scheme"'), iri('http:/not-a-scheme'), iri('<http:/not-a-scheme>');
SELECT iri('"foo"@en');
SELECT iri('"42"^^<http://www.w3.org/2001/XMLSchema#int>');

SELECT p, o, iri(p) FROM ftdbp 
WHERE 
  iri(p) = iri('http://dbpedia.org/property/released') AND
  iri(p) = iri('"http://dbpedia.org/property/released"') AND
  iri(p) = iri('"http://dbpedia.org/property/released"@en') AND
  iri(p) = iri('"http://dbpedia.org/property/released"^^xsd:string');

/* isIRI / isURI */
SELECT isIRI('<https://example/>'); 
SELECT isIRI('<mailto:foo@example.com>');
SELECT isIRI('http://example/');
SELECT isIRI('"http://example/"');
SELECT isIRI('path');
SELECT isIRI('"path"');
SELECT isIRI('"foo"^^xsd:string');
SELECT isIRI('"foo"^^<http://www.w3.org/2001/XMLSchema#string>'); 
SELECT isIRI(strdt('foo', 'xsd:string'));
SELECT isIRI('"foo"@en');
SELECT isIRI('');
SELECT isIRI(NULL);
SELECT isIRI('<not-an-iri');
SELECT isURI('<http://example/>');
SELECT isURI('path');

SELECT p, o, isiri(p) FROM ftdbp 
WHERE 
  iri(p) = iri('http://dbpedia.org/property/released') AND
  isiri(p);

/* STRSTARTS */
SELECT strstarts('"foobar"','"foo"'), strstarts('foobar','foo');
SELECT strstarts('"foobar"@en','"foo"@en');
SELECT strstarts('"foobar"^^<xsd:string>','"foo"^^<xsd:string>');
SELECT strstarts('"foobar"^^<xsd:string>','"foo"');
SELECT strstarts('"foobar"','"foo"^^<xsd:string>');
SELECT strstarts('"foobar"@en','"foo"');
SELECT strstarts('"foobar"@en','"foo"^^<xsd:string>');
SELECT strstarts('foobar','');
SELECT strstarts('','xyz');
SELECT strstarts('foobar',NULL);
SELECT strstarts(NULL,'xyz');
SELECT strstarts(NULL, NULL);
SELECT strstarts(strlang('foobar','en'),'"foo"@fr');
SELECT strstarts(strlang('foobar','en'), strlang('foo','fr'));
SELECT strstarts(strlang('foobar','en'), '"foo"^^<xsd:string>');
SELECT strstarts(strlang('foobar','en'), strdt('foo','xsd:string'));
SELECT strstarts('foobar', strdt('foo','xsd:string'));
SELECT strstarts('foobar','"foo"^^<xsd:string>');
SELECT strstarts('foobar', strlang('foo','it'));
SELECT strstarts('foobar','"foo"@de');

SELECT p, o, strstarts(o,str('Postgre'))
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'pt') AND
  strstarts(o,'Postgre') AND
  strstarts(o, '"Postgre"') AND
  strstarts(o,'"Postgre"^^xsd:string') AND
  strstarts(o, strdt('Postgre','xsd:string')) AND
  strstarts(o, '"Postgre"@pt') AND
  strstarts(o, strlang('Postgre','pt'));

/* STRENDS */
SELECT strends('"foobar"','"bar"'), strends('foobar','bar');
SELECT strends('"foobar"@en','"bar"@en');
SELECT strends('"foobar"^^xsd:string', '"bar"^^xsd:string');
SELECT strends('"foobar"^^xsd:string', '"bar"');
SELECT strends('"foobar"', '"bar"^^xsd:string');
SELECT strends('"foobar"@en', '"bar"');
SELECT strends('"foobar"@en', '"bar"^^xsd:string');
SELECT strends('foobar','xyz');
SELECT strends('foobar','');
SELECT strends('','xyz');
SELECT strends('foobar',NULL);
SELECT strends(NULL,'xyz');
SELECT strends(NULL, NULL);
SELECT strends('"foobar"@en','"bar"@fr');
SELECT strends(strlang('foobar','en'),'"bar"@fr');
SELECT strends(strlang('foobar','en'), '"bar"^^<xsd:string>');
SELECT strends(strlang('foobar','en'), strdt('bar','xsd:string'));
SELECT strends('foobar', strdt('bar','xsd:string'));
SELECT strends('foobar','"bar"^^<xsd:string>');
SELECT strends('foobar','"bar"@de');

SELECT p, o, strends(o,str('SQL'))
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'es') AND
  strends(o,'SQL') AND
  strends(o, '"SQL"') AND
  strends(o,'"SQL"^^xsd:string') AND
  strends(o, strdt('SQL','xsd:string'));

/* STRBEFORE */
SELECT strbefore('abc','b'), strbefore('"abc"','"b"');
SELECT strbefore('"abc"@en','bc');
SELECT strbefore('"abc"@en','"b"@cy');
SELECT strbefore('"abc"^^xsd:string',''), strbefore('"abc"^^xsd:string','""');
SELECT strbefore('abc','xyz'), strbefore('"abc"','"xyz"');
SELECT strbefore('"abc"@en', '"z"@en');
SELECT strbefore('"abc"@en', '"z"'), strbefore('"abc"@en', 'z');
SELECT strbefore('"abc"@en', '""@en');
SELECT strbefore('"abc"@en', '""');
SELECT strbefore('"abc"^^<http://www.w3.org/2001/XMLSchema#string>','c');
SELECT strbefore('"abc"^^<http://www.w3.org/2001/XMLSchema#string>','"c"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT strbefore('"abc"^^<http://www.w3.org/2001/XMLSchema#string>','"c"^^xsd:string');
SELECT strbefore('"abc"^^http://www.w3.org/2001/XMLSchema#string','"c"^^<xsd:string>');
SELECT strbefore('"abc"^^xsd:string','"c"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT strbefore('"abc"@fr','"b"^^xsd:string');
SELECT strbefore('"abc"^^<xsd:string>','"b"@de');
SELECT strbefore('"abc"@en','"b"^^<foo:bar>');
SELECT strbefore('abc', NULL);
SELECT strbefore(NULL, 'xyz');
SELECT strbefore(NULL, NULL);
SELECT strbefore('abc', '');
SELECT strbefore('"abc"', '');
SELECT strbefore('', 'xyz');
SELECT strbefore('', '');
SELECT strbefore('""','""');

SELECT p, o, strbefore(str(o), 'SQL')
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'de') AND
  strbefore(str(o), 'SQL') = str('Postgre');

/* STRAFTER */
SELECT strafter('"abc"','"b"');
SELECT strafter('"abc"@en','ab');
SELECT strafter('"abc"@en','"b"@cy');
SELECT strafter('"abc"^^xsd:string','""');
SELECT strafter('"abc"^^<http://www.w3.org/2001/XMLSchema#string>','b');
SELECT strafter('"abc"^^<http://www.w3.org/2001/XMLSchema#string>','"b"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT strafter('"abc"^^<http://www.w3.org/2001/XMLSchema#string>','"b"^^xsd:string');
SELECT strafter('"abc"^^http://www.w3.org/2001/XMLSchema#string','"b"^^<xsd:string>');
SELECT strafter('"abc"^^xsd:string','"b"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT strafter('"abc"@fr','"b"^^xsd:string');
SELECT strafter('"abc"','"xyz"');
SELECT strafter('"abc"@en', '"z"@en');
SELECT strafter('"abc"@en', '"z"');
SELECT strafter('"abc"@en', '""@en');
SELECT strafter('"abc"@en', '""');
SELECT strafter('abc','b');
SELECT strafter('abc','xyz');
SELECT strafter('abc', NULL);
SELECT strafter(NULL, 'xyz');
SELECT strafter(NULL, NULL);
SELECT strafter('abc', '');
SELECT strafter('', 'xyz');
SELECT strafter('', '');

SELECT p, o, strafter(o, strlang('Postgre','fr')), strafter(o, strdt('Postgre','xsd:string'))
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'fr') AND
  strafter(str(o), 'Postgre') = str('SQL');

/* CONTAINS */
SELECT contains('"foobar"', '"bar"'), contains('foobar', 'bar');
SELECT contains('"foobar"@en', '"foo"@en'), contains(strlang('"foobar"','en'), strlang('foo','en'));
SELECT contains('"foobar"^^xsd:string', '"bar"^^xsd:string'), contains(strdt('"foobar"','xsd:string'), strdt('"bar"','xsd:string'));
SELECT contains('"foobar"^^xsd:string', '"foo"'), contains('"foobar"^^xsd:string', 'foo');
SELECT contains('"foobar"', '"bar"^^xsd:string'), contains('foobar', '"bar"^^xsd:string');
SELECT contains('"foobar"@en', '"foo"'), contains('"foobar"@en', 'foo');
SELECT contains('"foobar"@en', '"bar"^^xsd:string');
SELECT contains('"foobar"', '""'), contains('foobar', '');
SELECT contains('""', '"foo"'), contains('', 'foo');
SELECT contains('"foobar"', NULL), contains('foobar', NULL);
SELECT contains(NULL, '"foo"'), contains(NULL, 'foo');
SELECT contains(NULL, NULL);
SELECT contains('"foobar"@en', '"foo"@fr');
SELECT contains('"123"^^<http://example.com/int>', '"2"');
SELECT contains('"abc"', '"def"@en');

SELECT p, o, contains(o,'"ostg"@fr'), contains(o,'"ostg"^^xsd:string')
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'de') AND
  contains(o,'ostg') AND
  contains(o,'"ostg"@de') AND
  contains(o, strlang('ostg','de')) AND
  contains(o, strdt('ostg','xsd:string'));

/* LANGMATCHES */
SELECT langmatches(lang('"hello"@en'), '"en"');
SELECT langmatches(lang('"hello"@EN-US'), '"en-us"');
SELECT langmatches(lang('"hello"@fr'), '"FR"');
SELECT langmatches(lang('"hello"@en'), '"*"');
SELECT langmatches(lang('"hello"@fr-ca'), '"*"');
SELECT langmatches(lang('"hello"@en-us'), '"en-*"');
SELECT langmatches(lang('"hello"@en'), '"en-*"');
SELECT langmatches(lang('"hello"@fr-ca'), '"fr-*"');
SELECT langmatches(lang('"hello"@fr'), '"en"');
SELECT langmatches(lang('"hello"@en-us'), '"fr-*"');
SELECT langmatches(lang('"hello"@en'), '"en-us-*"');
SELECT langmatches(lang('"hello"'), '"en"');
SELECT langmatches(lang('"hello"'), '"*"');
SELECT langmatches(lang('""@en'), '"en"');
SELECT langmatches(lang('""'), '"*"');
SELECT langmatches(lang('"hello"^^xsd:string'), '"en"');
SELECT langmatches(lang('"hello"^^xsd:string'), '"*"');
SELECT langmatches(lang('"hello"@en'), '"en"^^xsd:string');
SELECT langmatches(lang('"hello"@en'), '"*"^^xsd:string');
SELECT langmatches(lang('"hello"@en-us'), '"EN-*"^^xsd:string');
SELECT langmatches('', '"en"');
SELECT langmatches('en', '"en"');
SELECT langmatches(lang('"hello"@en'), '');
SELECT langmatches('', '"*"');

SELECT p, o, langmatches(lang(o),'*')
FROM ftdbp 
WHERE langmatches(lang(o),'pt');

/* ISBLANK */
SELECT isblank('_:b1');
SELECT isblank('_:node123');
SELECT isblank('<http://example.org/a>');
SELECT isblank('"hello"');
SELECT isblank('"hello"@en');
SELECT isblank('"42"^^xsd:integer');
SELECT isblank('_notblank');
SELECT isblank('');
SELECT isblank('b1');
SELECT isblank('_:');
SELECT isblank('_');
SELECT isblank(' ');
SELECT isblank('');
SELECT isblank(NULL);

SELECT p, o, isblank(o)
FROM ftdbp 
WHERE isblank(o);

/* ISNUMERIC */
SELECT isnumeric('12');
SELECT isnumeric('"12"');
SELECT isnumeric('"12"^^xsd:nonNegativeInteger');
SELECT isnumeric('"1200"^^xsd:byte');
SELECT isnumeric('<http://example/>');
SELECT isnumeric('"12"^^xsd:integer');
SELECT isnumeric('"12"^^xsd:positiveInteger');
SELECT isnumeric('"12"^^xsd:negativeInteger');
SELECT isnumeric('"12"^^xsd:nonPositiveInteger');
SELECT isnumeric('"12"^^xsd:long');
SELECT isnumeric('"12"^^xsd:int');
SELECT isnumeric('"12"^^xsd:short');
SELECT isnumeric('"12"^^xsd:unsignedLong');
SELECT isnumeric('"12"^^xsd:unsignedInt');
SELECT isnumeric('"12"^^xsd:unsignedShort');
SELECT isnumeric('"12"^^xsd:unsignedByte');
SELECT isnumeric('"12"^^xsd:double');
SELECT isnumeric('"12"^^xsd:float');
SELECT isnumeric('"12"^^xsd:decimal');
SELECT isnumeric('');
SELECT isnumeric(' ');
SELECT isnumeric('""');
SELECT isnumeric('" "');
SELECT isnumeric(NULL);

SELECT p, o, isnumeric(o), isnumeric(p)
FROM ftdbp
WHERE 
  p = iri('http://dbpedia.org/ontology/wikiPageLength') AND
  isnumeric(o);

/* ISLITERAL */
SELECT isliteral('"hello"');
SELECT isliteral('"123"');
SELECT isliteral('"12"^^xsd:integer');
SELECT isliteral('"12"^^xsd:nonNegativeInteger');
SELECT isliteral('"12.34"^^xsd:double');
SELECT isliteral('"true"^^xsd:boolean');
SELECT isliteral('"abc"^^<http://example.org/custom>'); -- true
SELECT isliteral('"hello"@en');
SELECT isliteral('"bonjour"@fr');
SELECT isliteral('12');
SELECT isliteral('<http://example.org>');
SELECT isliteral('_:bnode');
SELECT isliteral('');
SELECT isliteral('" "');
SELECT isliteral('""');
SELECT isliteral(NULL);

SELECT p, o, isliteral(o)
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  isliteral(o) AND 
  NOT isliteral(p);

/* BNODE */
SELECT isblank(bnode());
SELECT bnode('xyz');
SELECT bnode('xyz');
SELECT bnode('"xyz"');
SELECT bnode('"xyz"@en');
SELECT bnode('"xyz"^^xsd:string');
SELECT bnode('hello world');
SELECT bnode('123!');
SELECT bnode('<http://example.org>');
SELECT bnode('_:bnode');
SELECT bnode('');
SELECT bnode(NULL);

SELECT *
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  isblank(bnode(o));

/* UUID (not pushable) */
SELECT uuid() ~ '^<urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}>$';

/* STRUUID() (not pushable) */
SELECT struuid() ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' AS struuid_format;

/* LCASE */
SELECT lcase('BAR');
SELECT lcase('"BAR"');
SELECT lcase('"BAR"@en'), lcase(strlang('BAR','en'));
SELECT lcase('"BAR"^^xsd:string'), lcase(strdt('BAR','xsd:string'));
SELECT lcase('<http://example.org>');
SELECT lcase('_:xyz');
SELECT lcase(bnode('foo'));
SELECT lcase('123');
SELECT lcase('"123"');
SELECT lcase('"123"^^xsd:integer');
SELECT lcase('"1990-10-03"^^xsd:date');
SELECT lcase('"!§$%&/()?ß}{}[]°^|<>*"');
SELECT lcase(NULL);
SELECT lcase('');
SELECT lcase('""');
SELECT lcase('" "');
SELECT lcase(' ');

SELECT p, o, lcase(o)
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'de') AND  
  lcase(o) = lcase('"PostgreSQL"@de') AND
  lcase(o) = lcase(strlang('PostgreSQL','de'));

SELECT p, o, lcase(strdt(o,'xsd:string'))
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND   
  strstarts(lcase(strdt(o,'xsd:string')), lcase(strdt('POSTGRE','xsd:string')));

/* UCASE */
SELECT ucase('bar');
SELECT ucase('"bar"');
SELECT ucase('"bar"@en'), ucase(strlang('bar','en'));
SELECT ucase('"bar"^^xsd:string'), ucase(strdt('bar','xsd:string'));
SELECT ucase('<http://example.org>');
SELECT ucase('_:xyz');
SELECT ucase(bnode('foo'));
SELECT ucase('123');
SELECT ucase('"123"');
SELECT ucase('"123"^^xsd:integer');
SELECT ucase('"1990-10-03"^^xsd:date');
SELECT ucase('"!§$%&/()?ß}{}[]°^|<>*"');
SELECT ucase(NULL);
SELECT ucase('');
SELECT ucase('""');
SELECT ucase('" "');
SELECT ucase(' ');

SELECT p, o, ucase(o)
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'es') AND
  ucase(o) = ucase('"PostgreSQL"@es') AND
  ucase(o) = ucase(strlang('PostgreSQL','es'));

SELECT p, o, ucase(strdt(o,'xsd:string'))
FROM ftdbp
WHERE
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  strstarts(ucase(strdt(o,'xsd:string')), ucase(strdt('postgre','xsd:string')));

/* STRLEN */
SELECT strlen('chat'), strlen('"chat"');
SELECT strlen('"chat"@en'), strlen(strlang('chat','en'));
SELECT strlen('"chat"^^xsd:string'), strlen(strdt('chat','xsd:string'));
SELECT strlen('""'), strlen('');
SELECT strlen('" "'), strlen(' ');
SELECT strlen('"łø"'), strlen('łø');
SELECT strlen(NULL);

SELECT p, o, strlen(o)
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'de') AND
  strlen(o) = strlen('"PostgreSQL"@de');

/* SUBSTR */
SELECT substr('"foobar"', 4), substr('foobar', 4);
SELECT substr('"foobar"@en', 4), substr(strlang('foobar','en'), 4);
SELECT substr('"foobar"^^xsd:string', 4), substr(strdt('foobar','xsd:string'), 4);
SELECT substr('"foobar"', 4, 1), substr('foobar', 4, 1);
SELECT substr('"foobar"@en', 4, 1), substr(strlang('foobar','en'), 4, 1);
SELECT substr('"foobar"^^xsd:string', 4, 1), substr(strdt('foobar','xsd:string'), 4, 1);
SELECT substr('""', 42);
SELECT substr('', 42);
SELECT substr(NULL, 42);
SELECT substr('"foo"', NULL);

SELECT p, o, substr(o, 7, 3), substr(strdt(o,'xsd:string'), 7, 3) 
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  substr(o, 7, 3) = substr('"PostgreSQL"@es', 7, 3) AND
  substr(strdt(o,'xsd:string'), 7, 3) = substr(strdt('PostgreSQL','xsd:string'), 7, 3) AND
  substr(o, 7) = substr('"PostgreSQL"@es', 7) AND
  substr(strlang(o,'es'), 7, 3) = substr(strlang('PostgreSQL','es'), 7, 3) AND
  langmatches(lang(o), 'es');

/* CONCAT */
SELECT concat('"foo"', '"bar"'), concat('foo', 'bar');
SELECT concat('"foo"@en', '"bar"@en'), concat(strlang('foo','en'), strlang('bar','en'));
SELECT concat('"foo"^^xsd:string', '"bar"^^xsd:string'), concat(strdt('foo','xsd:string'), strdt('bar','xsd:string'));
SELECT concat('"foo"', '"bar"^^xsd:string'), concat('foo', strdt('bar','xsd:string'));
SELECT concat('"foo"@en', '"bar"'), concat(strlang('foo','en'), 'bar');
SELECT concat('"foo"@en', '"bar"^^xsd:string'), concat(strlang('foo','en'), strdt('bar','xsd:string'));
SELECT concat(NULL, 'bar'), concat('foo', NULL), concat(NULL, NULL);
SELECT concat('foo', ''), concat('', 'bar'), concat('', ''), concat('""', '""');
SELECT concat('"foo"^^foo:bar', 'bar'), concat('"foo"', '"bar"^^foo:bar');

SELECT p, o, concat(o,strlang(' Global','pt')), concat(o,strdt(' Global','xsd:string'))
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'pt') AND
  concat(o,'') = str('PostgreSQL');

/* REPLACE */
SELECT replace('"abcd"', '"b"', '"Z"'), replace('abcd', 'b', 'Z');
SELECT replace('"abab"', '"B"', '"Z"','"i"'), replace('abab', 'B', 'Z','i');
SELECT replace('"abab"', '"B."', '"Z"','"i"'), replace('abab', 'B.', 'Z','i');
SELECT replace('"abcd"@en', '"b"', '"Z"'), replace(strlang('abcd','en'), 'b', 'Z');
SELECT replace('"abab"^^xsd:string', '"B"', '"Z"','"i"'), replace(strdt('abab','xsd:string'), 'B', 'Z','i');
SELECT replace('"abcd"', '"b"@en', '"Z"'), replace('abcd', strlang('b','en'), 'Z');
SELECT replace('"abab"', '"B"^^xsd:string', '"Z"','"i"'), replace('abab', strdt('B','xsd:string'), 'Z','i');
SELECT replace('""', '"b"', '"Z"'), replace('', 'b', 'Z');
SELECT replace('"abcd"', '""', '"Z"'), replace('abcd', '', 'Z');
SELECT replace('"abcd"', '"b"', '""'), replace('abcd', 'b', '');
SELECT replace('"ab\"cd"', '"b"', '"Z"'), replace('ab\"cd', 'b', 'Z');
SELECT replace(NULL, 'b', 'Z'), replace('abcd', NULL, 'Z'), replace('abcd', 'b', NULL), replace('abcd', 'b', 'Z', NULL);
SELECT replace('', 'a', 'Z');                -- Empty input string
SELECT replace('abcd', '', 'Z');             -- Empty pattern
SELECT replace('abcd', 'a', '');             -- Empty replacement
SELECT replace('', '', 'Z');                 -- Empty pattern and replacement
SELECT replace('abcd', 'a', 'Z');            -- Pattern at the beginning
SELECT replace('abcd', 'd', 'Z');            -- Pattern at the end
SELECT replace('abcd', 'bc', 'Z');           -- Pattern in the middle
SELECT replace('aabbcc', 'b', 'Z');          -- Multiple occurrences of the pattern
SELECT replace('Abcd', 'a', 'Z');            -- Case mismatch pattern
SELECT replace('abcd', 'A', 'Z');            -- Case mismatch pattern (uppercase in input)
SELECT replace('abcd', 'A', 'Z','i');        -- Case-insensitive replacement
SELECT replace('"abcd"', '"b"', '"Z"');      -- Special characters inside quotes
SELECT replace('ab\cd', 'b\\', 'Z');         -- Escaped backslashes
SELECT replace('ab"cd', '"b"', '"Z"');       -- Quotes in the input
SELECT replace('ab"cd', 'b"', 'Z');          -- Quotes in pattern
SELECT replace('abcdef', 'bc', 'ZY');        -- Multi-character pattern in the middle
SELECT replace('abc abc', 'abc', 'XYZ');     -- Multiple occurrences of a multi-character pattern
SELECT replace('abcd', 'a', 'Z');            -- Pattern at the start
SELECT replace('abcd', 'd', 'Z');            -- Pattern at the end
SELECT replace('abcdabcd', 'abcd', 'XYZ');   -- Pattern at the start and repeated
SELECT replace(NULL, 'a', 'Z');              -- Input is NULL
SELECT replace('abcd', NULL, 'Z');           -- Pattern is NULL
SELECT replace('abcd', 'a', NULL);           -- Replacement is NULL
SELECT replace(NULL, NULL, NULL);             -- All NULLs
SELECT replace('"ab\"cd"', '"b"', '"Z"');    -- Escaped double quotes
SELECT replace('"ab\"cd"', 'b', 'Z');         -- Escaped double quotes, no pattern
SELECT replace('"abcd"@en', 'a', 'Z');       -- Language-tagged literal
SELECT replace('"abcd"^^xsd:string', 'a', 'Z'); -- Datatype-literal (xsd:string)
SELECT replace('"abcd"^^xsd:date', 'a', 'Z'); -- Datatype-literal (xsd:date)
SELECT replace('ababab', 'ab', 'XY', 'g');   -- Global replacement
SELECT replace('ababab', 'ab', 'XY');         -- Non-global replacement (should only replace first occurrence)
SELECT replace('abcd', '', 'Z', 'g');         -- Empty pattern with global flag
SELECT replace('abcd', '', 'Z');              -- Empty pattern without global flag
SELECT replace('abcd', 'z', 'Z');             -- No pattern match
SELECT replace('abcd', 'xy', 'Z');            -- No match for multi-character pattern
SELECT replace('a' || repeat('b', 1000) || 'c', 'b', 'Z');  -- Long string with repeated pattern
SELECT replace('abcd', 'abcd', 'XYZ');       -- Pattern matches the entire string
SELECT replace('abcdabcd', 'abcd', 'XYZ');   -- Pattern matches at the start
SELECT replace('""', '"b"', '"Z"');           -- Empty literal as input
SELECT replace('"b"', '""', '"Z"');            -- Empty pattern in replacement
SELECT replace('abcd', 'a.b', 'Z', 'g');      -- Dot in pattern (regex)
SELECT replace('abcd', '[a-b]', 'Z', 'g');     -- Range in regex pattern
SELECT replace('abcd', '(ab)', 'Z', 'g');      -- Group in regex pattern

SELECT p, o, replace(o,'Postgre','My'), replace(o,'"Postgre"@de','')
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'es') AND
  replace(o,'Postgre','My') = replace(strlang('PostgreSQL','es'),'Postgre','My') AND
  replace(o, 'POSTGRE', 'My','i') = replace('"PostgreSQL"@es', 'POSTGRE', 'My','i');

/* REGEX */
SELECT regex('"abcd"', '"bc"');
SELECT regex('"abcd"', '"xy"');
SELECT regex('"abcd"', '"BC"', '"i"');
SELECT regex('"abcd"', '"^bc"');
SELECT regex('"abcd"', '"^ab"');
SELECT regex('"abc\ndef"', '"^def$"', '"m"');
SELECT regex('"abc\ndef"', '"c.d"', '"s"');
SELECT regex('"abcd"@en', '"bc"');
SELECT regex('"123"^^xsd:int', '"23"');
SELECT regex('""', '"a"');
SELECT regex('""', '"(.*)"');
SELECT regex('"abcd"', '""');
SELECT regex(NULL, '"a"'), regex('"abcd"', NULL), regex('"abcd"', '"a"', NULL);
SELECT regex('"abcd"', '"[a"');

SELECT p, o
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'es') AND
  regex(o, ucase('postgres'), 'i') AND 
  regex(o, '^pOs','i') ;

/* ABS */
SELECT abs('"-1"^^xsd:int');
SELECT abs('"-1.42"^^xsd:double');
SELECT abs(strdt('-1.42','xsd:double'));
SELECT abs(strdt('-1.42238','xsd:double'));
SELECT abs('');
SELECT abs(' ');
SELECT abs(NULL);
SELECT abs(CAST(-1.42 AS numeric));
SELECT abs(CAST(-1.42 AS double precision));
--SELECT abs(CAST(-1.42 AS real));
SELECT abs(CAST(-1 AS bigint));
SELECT abs(CAST(-1 AS smallint));
SELECT abs(CAST(-1 AS int));

SELECT p, o, abs(o)
FROM ftdbp 
WHERE 
  p = iri('http://dbpedia.org/ontology/wikiPageID') AND
  abs(o) = 23824;

/* ROUND */
SELECT round('"2.4999"^^xsd:double');
SELECT round('"2.5"^^xsd:double');
SELECT round('"-2.5"^^xsd:int');
SELECT round('');
SELECT round('""');
SELECT round(' ');
SELECT round('" "');
SELECT round(NULL);
SELECT round(CAST(2.49999 AS numeric));
SELECT round(CAST(2.5 AS double precision));
--SELECT round(CAST(-2.5 AS real));
SELECT round(CAST(42 AS bigint));
SELECT round(CAST(42 AS smallint));
SELECT round(CAST(42 AS int));

SELECT p, o, round(o)
FROM ftdbp 
WHERE 
  p = iri('http://dbpedia.org/ontology/wikiPageID') AND
  round(o) = round('"23824"^^xsd:int');

/* CEIL */
SELECT ceil('"10.5"^^xsd:double');
SELECT ceil('"-10.5"^^:xsd:decimal');
SELECT ceil(NULL);
SELECT ceil(CAST(10.5 AS numeric));
SELECT ceil(CAST(-10.5 AS double precision));
SELECT ceil(CAST(10.5 AS real));
SELECT ceil(CAST(-42 AS bigint));
SELECT ceil(CAST(42 AS smallint));
SELECT ceil(CAST(-42 AS int));

SELECT p, o, ceil(o)
FROM ftdbp 
WHERE 
  p = iri('http://dbpedia.org/ontology/wikiPageID') AND
  ceil(o) = ceil('"23823.5"^^xsd:int') AND
  ceil(o) = ceil(23823.5);

/* FLOOR */
SELECT floor('"10.5"^^xsd:double');
SELECT floor('"-10.5"^^xsd:decimal');
SELECT floor(CAST(10.5 AS numeric));
SELECT floor(CAST(-10.5 AS double precision));
SELECT floor(CAST(10.5 AS real));
SELECT floor(CAST(-42 AS bigint));
SELECT floor(CAST(42 AS smallint));
SELECT floor(CAST(-42 AS int));

SELECT p, o, ceil(o)
FROM ftdbp 
WHERE 
  p = iri('http://dbpedia.org/ontology/wikiPageID') AND
  floor(o) = floor('"23824.5"^^xsd:int') AND
  floor(o) = floor(23824.5);

/* RAND */
SELECT setseed(0.42);
SELECT 
  sparql.lex(sparql.rand())::numeric BETWEEN 0 AND 1, 
  sparql.datatype(sparql.rand()) = '<http://www.w3.org/2001/XMLSchema#double>';

/* YEAR */
SELECT sparql.year('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.year('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.year('2011-01-10T14:45:13.815-05:00');
SELECT sparql.year('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.year('2011-01-10T14:45:13.815-05:00'::timestamp);

SELECT p, o, sparql.year(o)
FROM ftdbp 
WHERE 
  p = sparql.iri('http://dbpedia.org/property/released') AND
  sparql.year(o) = 1996 AND
  sparql.year(o) = sparql.year('"1996-07-08"^^xsd:date');

/* MONTH */
SELECT sparql.month('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.month('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.month('2011-01-10T14:45:13.815-05:00');
SELECT sparql.month('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.month('2011-01-10T14:45:13.815-05:00'::timestamp);

SELECT p, o, sparql.month(o)
FROM ftdbp 
WHERE 
  p = sparql.iri('http://dbpedia.org/property/released') AND
  sparql.month(o) = 7 AND
  sparql.month(o) = sparql.month('"1996-07-08"^^xsd:date');

/* DAYS */
SELECT sparql.day('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.day('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.day('2011-01-10T14:45:13.815-05:00');
SELECT sparql.day('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.day('2011-01-10T14:45:13.815-05:00'::timestamp);

SELECT p, o, sparql.day(o)
FROM ftdbp 
WHERE 
  p = sparql.iri('http://dbpedia.org/property/released') AND
  sparql.day(o) = 8 AND
  sparql.day(o) = sparql.day('"1996-07-08"^^xsd:date');

/* HOURS */
SELECT sparql.hours('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.hours('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.hours('2011-01-10T14:45:13.815-05:00');
SELECT sparql.hours('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.hours('2011-01-10T14:45:13.815-05:00'::timestamp);

SELECT p, o, sparql.hours(o)
FROM ftdbp 
WHERE 
  p = sparql.iri('http://dbpedia.org/property/released') AND
  sparql.hours(o) = 0 AND
  sparql.hours(o) = sparql.hours('"1996-07-08"^^xsd:date');

/* MINUTES */
SELECT sparql.minutes('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.minutes('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.minutes('2011-01-10T14:45:13.815-05:00');
SELECT sparql.minutes('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.minutes('2011-01-10T14:45:13.815-05:00'::timestamp);

SELECT p, o, sparql.minutes(o)
FROM ftdbp 
WHERE 
  p = sparql.iri('http://dbpedia.org/property/released') AND
  sparql.minutes(o) = 0 AND
  sparql.minutes(o) = sparql.minutes('"1996-07-08"^^xsd:date');

/* SECONDS */
SELECT pg_catalog.round(sparql.seconds('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime'),3);
SELECT pg_catalog.round(sparql.seconds('"2011-01-10T14:45:13.815-05:00"'),3);
SELECT pg_catalog.round(sparql.seconds('2011-01-10T14:45:13.815-05:00'),3);
SELECT pg_catalog.round(sparql.seconds('2011-01-10T14:45:13.815-05:00'::date),3);
SELECT pg_catalog.round(sparql.seconds('2011-01-10T14:45:13.815-05:00'::timestamp),3);

SELECT p, o, pg_catalog.round(sparql.seconds(o),3)
FROM ftdbp 
WHERE 
  p = sparql.iri('http://dbpedia.org/property/released') AND
  sparql.seconds(o) = 0 AND
  sparql.seconds(o) = sparql.seconds('"1996-07-08"^^xsd:date');

/* TIMEZONE */
SELECT sparql.timezone('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.timezone('"2011-01-10T14:45:13.815Z"^^xsd:dateTime');
SELECT sparql.timezone('"2011-01-10T14:45:13.815"^^xsd:dateTime');
SELECT sparql.timezone('"2020-12-01T08:00:00-05:00"^^xsd:dateTime');
SELECT sparql.timezone('"2020-12-01T08:00:00+02:30"^^xsd:dateTime');
SELECT sparql.timezone('"2020-12-01T08:00:00Z"^^xsd:dateTime');
SELECT sparql.timezone('"2020-12-01T08:00:00.123+00:00"^^xsd:dateTime');
SELECT sparql.timezone('"2020-12-01T08:00:00.123456-04:45"^^xsd:dateTime');
SELECT sparql.timezone('"2020-12-01T08:00:00"^^xsd:dateTime');
SELECT sparql.timezone('"2020-12-01T08:00:00+25:00"^^xsd:dateTime');
SELECT sparql.timezone('"2020-12-01T08:00:00-99:99"^^xsd:dateTime');
SELECT sparql.timezone('"invalid-date"^^xsd:dateTime');
SELECT sparql.timezone('""^^xsd:dateTime');
SELECT sparql.timezone(NULL);
SELECT sparql.timezone('"not a date"^^xsd:string');

/* TZ */
SELECT sparql.tz('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.tz('"2011-01-10T14:45:13.815Z"^^xsd:dateTime');
SELECT sparql.tz('"2011-01-10T14:45:13.815"^^xsd:dateTime');
SELECT sparql.tz('"2020-12-01T08:00:00-05:00"^^xsd:dateTime');
SELECT sparql.tz('"2020-12-01T08:00:00+02:30"^^xsd:dateTime');
SELECT sparql.tz('"2020-12-01T08:00:00Z"^^xsd:dateTime');
SELECT sparql.tz('"2020-12-01T08:00:00.123+00:00"^^xsd:dateTime');
SELECT sparql.tz('"2020-12-01T08:00:00.123456-04:45"^^xsd:dateTime');
SELECT sparql.tz('"2020-12-01T08:00:00"^^xsd:dateTime');
SELECT sparql.tz('"2020-12-01T08:00:00+25:00"^^xsd:dateTime');
SELECT sparql.tz('"2020-12-01T08:00:00-99:99"^^xsd:dateTime');
SELECT sparql.tz('"invalid-date"^^xsd:dateTime');
SELECT sparql.tz('""^^xsd:dateTime');
SELECT sparql.tz(NULL);
SELECT sparql.tz('"not a date"^^xsd:string');

/* MD5 */
SELECT sparql.md5('abc');
SELECT sparql.md5('"abc"');
SELECT sparql.md5('"abc"^^xsd:string');
SELECT sparql.md5('"abc"^^xsd:string') = md5('abc');
SELECT sparql.md5('"abc"@en') = sparql.md5('"abc"');
SELECT sparql.md5('"abc"^^xsd:normalizedString');
SELECT sparql.md5('"abc"^^xsd:anyURI');
SELECT sparql.md5('123');  -- xsd:integer
SELECT sparql.md5('"2020-01-01T00:00:00Z"^^xsd:dateTime');
SELECT sparql.md5('"not_a_uri"^^xsd:anyURI');
SELECT sparql.md5('""');
SELECT sparql.md5(NULL);
SELECT sparql.md5('"Münster"');
SELECT sparql.md5(repeat('a', 10000));

SELECT p, o, sparql.md5(o)
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  langmatches(lang(o),'pt') AND
  sparql.md5(o) = sparql.md5('"PostgreSQL"@pt');

DROP SERVER dbpedia CASCADE;