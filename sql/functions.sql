\pset null NULL

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

SELECT p, o, strbefore(o, strlang('SQL','fr')), strbefore(o, strdt('SQL','xsd:string'))
FROM ftdbp
WHERE 
  p = iri('http://www.w3.org/2000/01/rdf-schema#label') AND
  strbefore(o, '"SQL"@fr') = '"Postgre"@fr' AND
  strbefore(o, '"SQL"@fr') = strlang('Postgre','fr') AND
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
  strafter(o, '"Postgre"@fr') = '"SQL"@fr' AND
  strafter(o, '"Postgre"@fr') = strlang('SQL','fr');

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
  langmatches(lang(o),'fr') AND
  contains(o,'ostg') AND
  contains(o,'"ostg"@fr') AND
  contains(o, strlang('ostg','fr')) AND
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

DROP SERVER dbpedia CASCADE;