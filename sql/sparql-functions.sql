\set VERBOSITY terse
\pset null NULL

--SET search_path TO sparql, pg_catalog;

SELECT sparql.rdf_fdw_arguments_compatible('"abc"','"b"');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"','"b"^^<xsd:string>');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"^^<xsd:string>','"b"');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"^^<xsd:string>','"b"^^<xsd:string>');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"@en','"b"');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"@en','"b"^^xsd:string');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"@en','"b"@en');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"@fr','"b"@ja');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"','"b"@ja');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"','"b"@en');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"^^xsd:string','"b"@en');

/* LEX */  
SELECT sparql.lex('"foo"');
SELECT sparql.lex('foo');
SELECT sparql.lex('"foo"@en');
SELECT sparql.lex('"foo"^^xsd:string');
SELECT sparql.lex(''); 
SELECT sparql.lex('""');
SELECT sparql.lex('"\""');
SELECT sparql.lex(NULL);

/* STRDT */
SELECT sparql.strdt(NULL, 'http://www.w3.org/2001/XMLSchema#string');
SELECT sparql.strdt('foo', NULL);
SELECT sparql.strdt('', '<http://example.org/type>');
SELECT sparql.strdt('foo', '');
SELECT sparql.strdt('foo', ' ');
SELECT sparql.strdt('foo', ' xsd:boolean ');
SELECT sparql.strdt('foo', 'http://www.w3.org/2001/XMLSchema#string');
SELECT sparql.strdt('f"oo', 'http://example.org/type');
SELECT sparql.strdt('"foo"@en', 'http://www.w3.org/2001/XMLSchema#int');
SELECT sparql.strdt('"f\"oo"^^xsd:string', 'http://example.org/newtype');
SELECT sparql.strdt('foo', '<http://example.org/type>');
SELECT sparql.strdt('foo', 'foo:bar');
SELECT sparql.strdt('foo', 'xsd:string');
SELECT sparql.strdt('foo', '<nonsense>');

/* STRLANG */
SELECT sparql.strlang('foo',NULL);
SELECT sparql.strlang(NULL,'de');
SELECT sparql.strlang('','es');
SELECT sparql.strlang(' ','en');
SELECT sparql.strlang('foo','pt');
SELECT sparql.strlang('"foo"@en','fr');
SELECT sparql.strlang('"foo"','it');
SELECT sparql.strlang('"foo"^^xsd:string','pt');
SELECT sparql.strlang('"foo"^^<http://www.w3.org/2001/XMLSchema#string>','es');
SELECT sparql.strlang(sparql.strlang('"foo"^^<http://www.w3.org/2001/XMLSchema#string>','es'),'de');
SELECT sparql.strlang(sparql.strlang('f"o"o','en'),'de');
SELECT sparql.strlang(sparql.strlang('x\"y','pl'),'it');
SELECT sparql.strlang('foo', 'xyz');

/* STR */
SELECT sparql.str('foo');
SELECT sparql.str('"foo"');
SELECT sparql.str('"foo"@en');
SELECT sparql.str('"foo"^^xsd:string');
SELECT sparql.str('f"oo');
SELECT sparql.str('"f\"oo"');
SELECT sparql.str('<http://example.org/foo>');
SELECT sparql.str('');
SELECT sparql.str(' ');
SELECT sparql.str(NULL);

/* LANG */
SELECT sparql.lang('"foo"@en');
SELECT sparql.lang(sparql.strlang('foo','fr'));
SELECT sparql.lang(sparql.strdt('foo','xsd:string'));
SELECT sparql.lang('"f"oo"@it');
SELECT sparql.lang('');
SELECT sparql.lang(' ');
SELECT sparql.lang(NULL);
SELECT sparql.lang('<http://example.org>'); 

/* DATATYPE */
SELECT sparql.datatype('"foo"^^xsd:string');
SELECT sparql.datatype('"foo"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT sparql.datatype(sparql.strdt('foo','xsd:string'));
SELECT sparql.datatype('"42"^^<xsd:int>');
SELECT sparql.datatype(sparql.strdt('foo','bar:xyz'));
SELECT sparql.datatype('<http://example.de>');
SELECT sparql.datatype('_:bnode42');
SELECT sparql.datatype('"foo"@es');
SELECT sparql.datatype('"foo"@es'::name);
SELECT sparql.datatype('');
SELECT sparql.datatype(''::name);
SELECT sparql.datatype(' ');
SELECT sparql.datatype('"foo"^<xsd:string>');
SELECT sparql.datatype('"foo"^^xsd:string>');
SELECT sparql.datatype('"foo"^^<xsd:string');
SELECT sparql.datatype(cast('2018-05-01' AS date));
SELECT sparql.datatype(cast('2018-05-01 11:30:00' AS timestamp without time zone));
SELECT sparql.datatype(cast('2018-05-01 11:30:00' AS timestamp with time zone));
SELECT sparql.datatype(cast('11:30:00' AS time));
SELECT sparql.datatype(42);
SELECT sparql.datatype(42.73);
SELECT sparql.datatype(cast(42 AS smallint));
SELECT sparql.datatype(cast(42 AS bigint));
SELECT sparql.datatype(cast(42.73 AS double precision));
SELECT sparql.datatype(cast(42.73 AS numeric));
SELECT sparql.datatype(cast(42.73 AS real));
SELECT sparql.datatype(true);
SELECT sparql.datatype(NULL);

  /* ENCODE_FOR_URI */
SELECT sparql.encode_for_uri('"Los Angeles"');
SELECT sparql.encode_for_uri('"Los Angeles"@en');
SELECT sparql.encode_for_uri('"Los Angeles"^^xsd:string');
SELECT sparql.encode_for_uri('"Los Angeles"^^<xsd:string>');
SELECT sparql.encode_for_uri('"Los Angeles"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT sparql.encode_for_uri('foo! *''();:@&=+$,/?#[]');
SELECT sparql.encode_for_uri('foo');
SELECT sparql.encode_for_uri('');
SELECT sparql.encode_for_uri(NULL);

/* IRI / URI */
SELECT sparql.iri('"http://example/"'), sparql.iri('http://example/'), sparql.iri('<http://example/>');
SELECT sparql.iri('"mailto:foo@example.com"'), sparql.iri('mailto:foo@example.com'), sparql.iri('<mailto:foo@example.com>');
SELECT sparql.iri('"urn:uuid:123e4567-e89b-12d3-a456-426614174000"'), sparql.iri('urn:uuid:123e4567-e89b-12d3-a456-426614174000'), sparql.iri('<urn:uuid:123e4567-e89b-12d3-a456-426614174000>');
SELECT sparql.iri('"file://etc/passwd"'), sparql.iri('file://etc/passwd'), sparql.iri('<file://etc/passwd>');
SELECT sparql.iri('"foo:bar"'), sparql.iri('foo:bar'), sparql.iri('<foo:bar>');
SELECT sparql.iri('"foo"'), sparql.iri('foo'), sparql.iri('<foo>');
SELECT sparql.iri('"a:b:c"'), sparql.iri('a:b:c'), sparql.iri('<a:b:c>');
SELECT sparql.iri('"http:/not-a-scheme"'), sparql.iri('http:/not-a-scheme'), sparql.iri('<http:/not-a-scheme>');
SELECT sparql.iri('"foo"@en');
SELECT sparql.iri('"42"^^<http://www.w3.org/2001/XMLSchema#int>');

  /* isIRI / isURI */
SELECT sparql.isIRI('<https://example/>'); 
SELECT sparql.isIRI('<mailto:foo@example.com>');
SELECT sparql.isIRI('http://example/');
SELECT sparql.isIRI('"http://example/"');
SELECT sparql.isIRI('path');
SELECT sparql.isIRI('"path"');
SELECT sparql.isIRI('"foo"^^xsd:string');
SELECT sparql.isIRI('"foo"^^<http://www.w3.org/2001/XMLSchema#string>'); 
SELECT sparql.isIRI(sparql.strdt('foo', 'xsd:string'));
SELECT sparql.isIRI('"foo"@en');
SELECT sparql.isIRI('');
SELECT sparql.isIRI(NULL);
SELECT sparql.isIRI('<not-an-iri');
SELECT sparql.isURI('<http://example/>');
SELECT sparql.isURI('path');

  /* STRSTARTS */
SELECT sparql.strstarts('"foobar"','"foo"'), sparql.strstarts('foobar','foo');
SELECT sparql.strstarts('"foobar"@en','"foo"@en');
SELECT sparql.strstarts('"foobar"^^<xsd:string>','"foo"^^<xsd:string>');
SELECT sparql.strstarts('"foobar"^^<xsd:string>','"foo"');
SELECT sparql.strstarts('"foobar"','"foo"^^<xsd:string>');
SELECT sparql.strstarts('"foobar"@en','"foo"');
SELECT sparql.strstarts('"foobar"@en','"foo"^^<xsd:string>');
SELECT sparql.strstarts('foobar','');
SELECT sparql.strstarts('','xyz');
SELECT sparql.strstarts('foobar',NULL);
SELECT sparql.strstarts(NULL,'xyz');
SELECT sparql.strstarts(NULL, NULL);
SELECT sparql.strstarts(sparql.strlang('foobar','en'),'"foo"@fr');
SELECT sparql.strstarts(sparql.strlang('foobar','en'), sparql.strlang('foo','fr'));
SELECT sparql.strstarts(sparql.strlang('foobar','en'), '"foo"^^<xsd:string>');
SELECT sparql.strstarts(sparql.strlang('foobar','en'), sparql.strdt('foo','xsd:string'));
SELECT sparql.strstarts('foobar', sparql.strdt('foo','xsd:string'));
SELECT sparql.strstarts('foobar','"foo"^^<xsd:string>');
SELECT sparql.strstarts('foobar', sparql.strlang('foo','it'));
SELECT sparql.strstarts('foobar','"foo"@de');

  /* STRENDS */
SELECT sparql.strends('"foobar"','"bar"'), sparql.strends('foobar','bar');
SELECT sparql.strends('"foobar"@en','"bar"@en');
SELECT sparql.strends('"foobar"^^xsd:string', '"bar"^^xsd:string');
SELECT sparql.strends('"foobar"^^xsd:string', '"bar"');
SELECT sparql.strends('"foobar"', '"bar"^^xsd:string');
SELECT sparql.strends('"foobar"@en', '"bar"');
SELECT sparql.strends('"foobar"@en', '"bar"^^xsd:string');
SELECT sparql.strends('foobar','xyz');
SELECT sparql.strends('foobar','');
SELECT sparql.strends('','xyz');
SELECT sparql.strends('foobar',NULL);
SELECT sparql.strends(NULL,'xyz');
SELECT sparql.strends(NULL, NULL);
SELECT sparql.strends('"foobar"@en','"bar"@fr');
SELECT sparql.strends(sparql.strlang('foobar','en'),'"bar"@fr');
SELECT sparql.strends(sparql.strlang('foobar','en'), '"bar"^^<xsd:string>');
SELECT sparql.strends(sparql.strlang('foobar','en'), sparql.strdt('bar','xsd:string'));
SELECT sparql.strends('foobar', sparql.strdt('bar','xsd:string'));
SELECT sparql.strends('foobar','"bar"^^<xsd:string>');
SELECT sparql.strends('foobar','"bar"@de');

  /* STRBEFORE */
SELECT sparql.strbefore('abc','b'), sparql.strbefore('"abc"','"b"');
SELECT sparql.strbefore('"abc"@en','bc');
SELECT sparql.strbefore('"abc"@en','"b"@cy');
SELECT sparql.strbefore('"abc"^^xsd:string',''), sparql.strbefore('"abc"^^xsd:string','""');
SELECT sparql.strbefore('abc','xyz'), sparql.strbefore('"abc"','"xyz"');
SELECT sparql.strbefore('"abc"@en', '"z"@en');
SELECT sparql.strbefore('"abc"@en', '"z"'), sparql.strbefore('"abc"@en', 'z');
SELECT sparql.strbefore('"abc"@en', '""@en');
SELECT sparql.strbefore('"abc"@en', '""');
SELECT sparql.strbefore('"abc"^^<http://www.w3.org/2001/XMLSchema#string>','c');
SELECT sparql.strbefore('"abc"^^<http://www.w3.org/2001/XMLSchema#string>','"c"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT sparql.strbefore('"abc"^^<http://www.w3.org/2001/XMLSchema#string>','"c"^^xsd:string');
SELECT sparql.strbefore('"abc"^^http://www.w3.org/2001/XMLSchema#string','"c"^^<xsd:string>');
SELECT sparql.strbefore('"abc"^^xsd:string','"c"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT sparql.strbefore('"abc"@fr','"b"^^xsd:string');
SELECT sparql.strbefore('"abc"^^<xsd:string>','"b"@de');
SELECT sparql.strbefore('"abc"@en','"b"^^<foo:bar>');
SELECT sparql.strbefore('abc', NULL);
SELECT sparql.strbefore(NULL, 'xyz');
SELECT sparql.strbefore(NULL, NULL);
SELECT sparql.strbefore('abc', '');
SELECT sparql.strbefore('"abc"', '');
SELECT sparql.strbefore('', 'xyz');
SELECT sparql.strbefore('', '');
SELECT sparql.strbefore('""','""');

/* STRAFTER */
SELECT sparql.strafter('"abc"','"b"');
SELECT sparql.strafter('"abc"@en','ab');
SELECT sparql.strafter('"abc"@en','"b"@cy');
SELECT sparql.strafter('"abc"^^xsd:string','""');
SELECT sparql.strafter('"abc"^^<http://www.w3.org/2001/XMLSchema#string>','b');
SELECT sparql.strafter('"abc"^^<http://www.w3.org/2001/XMLSchema#string>','"b"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT sparql.strafter('"abc"^^<http://www.w3.org/2001/XMLSchema#string>','"b"^^xsd:string');
SELECT sparql.strafter('"abc"^^http://www.w3.org/2001/XMLSchema#string','"b"^^<xsd:string>');
SELECT sparql.strafter('"abc"^^xsd:string','"b"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT sparql.strafter('"abc"@fr','"b"^^xsd:string');
SELECT sparql.strafter('"abc"','"xyz"');
SELECT sparql.strafter('"abc"@en', '"z"@en');
SELECT sparql.strafter('"abc"@en', '"z"');
SELECT sparql.strafter('"abc"@en', '""@en');
SELECT sparql.strafter('"abc"@en', '""');
SELECT sparql.strafter('abc','b');
SELECT sparql.strafter('abc','xyz');
SELECT sparql.strafter('abc', NULL);
SELECT sparql.strafter(NULL, 'xyz');
SELECT sparql.strafter(NULL, NULL);
SELECT sparql.strafter('abc', '');
SELECT sparql.strafter('', 'xyz');
SELECT sparql.strafter('', '');

/* CONTAINS */
SELECT sparql.contains('"foobar"', '"bar"'), sparql.contains('foobar', 'bar');
SELECT sparql.contains('"foobar"@en', '"foo"@en'), sparql.contains(sparql.strlang('"foobar"','en'), sparql.strlang('foo','en'));
SELECT sparql.contains('"foobar"^^xsd:string', '"bar"^^xsd:string'), sparql.contains(sparql.strdt('"foobar"','xsd:string'), sparql.strdt('"bar"','xsd:string'));
SELECT sparql.contains('"foobar"^^xsd:string', '"foo"'), sparql.contains('"foobar"^^xsd:string', 'foo');
SELECT sparql.contains('"foobar"', '"bar"^^xsd:string'), sparql.contains('foobar', '"bar"^^xsd:string');
SELECT sparql.contains('"foobar"@en', '"foo"'), sparql.contains('"foobar"@en', 'foo');
SELECT sparql.contains('"foobar"@en', '"bar"^^xsd:string');
SELECT sparql.contains('"foobar"', '""'), sparql.contains('foobar', '');
SELECT sparql.contains('""', '"foo"'), sparql.contains('', 'foo');
SELECT sparql.contains('"foobar"', NULL), sparql.contains('foobar', NULL);
SELECT sparql.contains(NULL, '"foo"'), sparql.contains(NULL, 'foo');
SELECT sparql.contains(NULL, NULL);
SELECT sparql.contains('"foobar"@en', '"foo"@fr');
SELECT sparql.contains('"123"^^<http://example.com/int>', '"2"');
SELECT sparql.contains('"abc"', '"def"@en');

/* LANGMATCHES */
SELECT sparql.langmatches(sparql.lang('"hello"@en'), '"en"');
SELECT sparql.langmatches(sparql.lang('"hello"@EN-US'), '"en-us"');
SELECT sparql.langmatches(sparql.lang('"hello"@fr'), '"FR"');
SELECT sparql.langmatches(sparql.lang('"hello"@en'), '"*"');
SELECT sparql.langmatches(sparql.lang('"hello"@fr-ca'), '"*"');
SELECT sparql.langmatches(sparql.lang('"hello"@en-us'), '"en-*"');
SELECT sparql.langmatches(sparql.lang('"hello"@en'), '"en-*"');
SELECT sparql.langmatches(sparql.lang('"hello"@fr-ca'), '"fr-*"');
SELECT sparql.langmatches(sparql.lang('"hello"@fr'), '"en"');
SELECT sparql.langmatches(sparql.lang('"hello"@en-us'), '"fr-*"');
SELECT sparql.langmatches(sparql.lang('"hello"@en'), '"en-us-*"');
SELECT sparql.langmatches(sparql.lang('"hello"'), '"en"');
SELECT sparql.langmatches(sparql.lang('"hello"'), '"*"');
SELECT sparql.langmatches(sparql.lang('""@en'), '"en"');
SELECT sparql.langmatches(sparql.lang('""'), '"*"');
SELECT sparql.langmatches(sparql.lang('"hello"^^xsd:string'), '"en"');
SELECT sparql.langmatches(sparql.lang('"hello"^^xsd:string'), '"*"');
SELECT sparql.langmatches(sparql.lang('"hello"@en'), '"en"^^xsd:string');
SELECT sparql.langmatches(sparql.lang('"hello"@en'), '"*"^^xsd:string');
SELECT sparql.langmatches(sparql.lang('"hello"@en-us'), '"EN-*"^^xsd:string');
SELECT sparql.langmatches('', '"en"');
SELECT sparql.langmatches('en', '"en"');
SELECT sparql.langmatches(sparql.lang('"hello"@en'), '');
SELECT sparql.langmatches('', '"*"');
SELECT sparql.langmatches('en-US', 'en');

/* ISBLANK */
SELECT sparql.isblank('_:b1');
SELECT sparql.isblank('_:node123');
SELECT sparql.isblank('<http://example.org/a>');
SELECT sparql.isblank('"hello"');
SELECT sparql.isblank('"hello"@en');
SELECT sparql.isblank('"42"^^xsd:integer');
SELECT sparql.isblank('_notblank');
SELECT sparql.isblank('');
SELECT sparql.isblank('b1');
SELECT sparql.isblank('_:');
SELECT sparql.isblank('_');
SELECT sparql.isblank(' ');
SELECT sparql.isblank('');
SELECT sparql.isblank(NULL);

/* ISNUMERIC */
SELECT sparql.isnumeric('12');
SELECT sparql.isnumeric('"12"');
SELECT sparql.isnumeric('"12"^^xsd:nonNegativeInteger');
SELECT sparql.isnumeric('"1200"^^xsd:byte');
SELECT sparql.isnumeric('<http://example/>');
SELECT sparql.isnumeric('"12"^^xsd:integer');
SELECT sparql.isnumeric('"12"^^xsd:positiveInteger');
SELECT sparql.isnumeric('"12"^^xsd:negativeInteger');
SELECT sparql.isnumeric('"12"^^xsd:nonPositiveInteger');
SELECT sparql.isnumeric('"12"^^xsd:long');
SELECT sparql.isnumeric('"12"^^xsd:int');
SELECT sparql.isnumeric('"12"^^xsd:short');
SELECT sparql.isnumeric('"12"^^xsd:unsignedLong');
SELECT sparql.isnumeric('"12"^^xsd:unsignedInt');
SELECT sparql.isnumeric('"12"^^xsd:unsignedShort');
SELECT sparql.isnumeric('"12"^^xsd:unsignedByte');
SELECT sparql.isnumeric('"12"^^xsd:double');
SELECT sparql.isnumeric('"12"^^xsd:float');
SELECT sparql.isnumeric('"12"^^xsd:decimal');
SELECT sparql.isnumeric('');
SELECT sparql.isnumeric(' ');
SELECT sparql.isnumeric('""');
SELECT sparql.isnumeric('" "');
SELECT sparql.isnumeric(NULL);

/* ISLITERAL */
SELECT sparql.isliteral('"hello"');
SELECT sparql.isliteral('"123"');
SELECT sparql.isliteral('"12"^^xsd:integer');
SELECT sparql.isliteral('"12"^^xsd:nonNegativeInteger');
SELECT sparql.isliteral('"12.34"^^xsd:double');
SELECT sparql.isliteral('"true"^^xsd:boolean');
SELECT sparql.isliteral('"abc"^^<http://example.org/custom>'); -- true
SELECT sparql.isliteral('"hello"@en');
SELECT sparql.isliteral('"bonjour"@fr');
SELECT sparql.isliteral('12');
SELECT sparql.isliteral('<http://example.org>');
SELECT sparql.isliteral('_:bnode');
SELECT sparql.isliteral('');
SELECT sparql.isliteral('" "');
SELECT sparql.isliteral('""');
SELECT sparql.isliteral(NULL);

  /* BNODE */
SELECT sparql.isblank(sparql.bnode());
SELECT sparql.bnode('xyz');
SELECT sparql.bnode('xyz');
SELECT sparql.bnode('"xyz"');
SELECT sparql.bnode('"xyz"@en');
SELECT sparql.bnode('"xyz"^^xsd:string');
SELECT sparql.bnode('hello world');
SELECT sparql.bnode('123!');
SELECT sparql.bnode('<http://example.org>');
SELECT sparql.bnode('_:bnode');
SELECT sparql.bnode('');
SELECT sparql.bnode(NULL);

/* UUID (not pushable) */
SELECT sparql.uuid()::text ~ '^<urn:uuid:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}>$';

/* STRUUID() (not pushable) */
SELECT sparql.struuid()::text ~ '^"[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"$' AS struuid_format;

/* LCASE */
SELECT sparql.lcase('BAR');
SELECT sparql.lcase('"BAR"');
SELECT sparql.lcase('"BAR"@en'), sparql.lcase(sparql.strlang('BAR','en'));
SELECT sparql.lcase('"BAR"^^xsd:string'), sparql.lcase(sparql.strdt('BAR','xsd:string'));
SELECT sparql.lcase('"ŁÓÒÁÀÂÆÄÉÈÊÍÌÎÓÒØÔÖÚÙÛÜÞ"@de');
SELECT sparql.lcase('<http://example.org>');
SELECT sparql.lcase('_:xyz');
SELECT sparql.lcase(sparql.bnode('foo'));
SELECT sparql.lcase('123');
SELECT sparql.lcase('"123"');
SELECT sparql.lcase('"123"^^xsd:integer');
SELECT sparql.lcase('"1990-10-03"^^xsd:date');
SELECT sparql.lcase('"!§$%&/()?ß}{}[]°^|<>*"');
SELECT sparql.lcase(NULL);
SELECT sparql.lcase('');
SELECT sparql.lcase('""');
SELECT sparql.lcase('" "');
SELECT sparql.lcase(' ');

/* UCASE */
SELECT sparql.ucase('bar');
SELECT sparql.ucase('"bar"');
SELECT sparql.ucase('"bar"@en'), sparql.ucase(sparql.strlang('bar','en'));
SELECT sparql.ucase('"bar"^^xsd:string'), sparql.ucase(sparql.strdt('bar','xsd:string'));
SELECT sparql.ucase('"łóòáàâæäéèêíìîóòøôöúùûüþ"@de');
SELECT sparql.ucase('<http://example.org>');
SELECT sparql.ucase('_:xyz');
SELECT sparql.ucase(sparql.bnode('foo'));
SELECT sparql.ucase('123');
SELECT sparql.ucase('"123"');
SELECT sparql.ucase('"123"^^xsd:integer');
SELECT sparql.ucase('"1990-10-03"^^xsd:date');
SELECT sparql.ucase('"!§$%&/()?ß}{}[]°^|<>*"');
SELECT sparql.ucase(NULL);
SELECT sparql.ucase('');
SELECT sparql.ucase('""');
SELECT sparql.ucase('" "');
SELECT sparql.ucase(' ');

/* STRLEN */
SELECT sparql.strlen('chat'), sparql.strlen('"chat"');
SELECT sparql.strlen('"chat"@en'), sparql.strlen(sparql.strlang('chat','en'));
SELECT sparql.strlen('"chat"^^xsd:string'), sparql.strlen(sparql.strdt('chat','xsd:string'));
SELECT sparql.strlen('""'), sparql.strlen('');
SELECT sparql.strlen('" "'), sparql.strlen(' ');
SELECT sparql.strlen('"łø"'), sparql.strlen('łø');
SELECT sparql.strlen(NULL);

/* SUBSTR */
SELECT sparql.substr('"foobar"', 4), sparql.substr('foobar', 4);
SELECT sparql.substr('"foobar"@en', 4), sparql.substr(sparql.strlang('foobar','en'), 4);
SELECT sparql.substr('"foobar"^^xsd:string', 4), sparql.substr(sparql.strdt('foobar','xsd:string'), 4);
SELECT sparql.substr('"foobar"', 4, 1), sparql.substr('foobar', 4, 1);
SELECT sparql.substr('"foobar"@en', 4, 1), sparql.substr(sparql.strlang('foobar','en'), 4, 1);
SELECT sparql.substr('"foobar"^^xsd:string', 4, 1), sparql.substr(sparql.strdt('foobar','xsd:string'), 4, 1);
SELECT sparql.substr('""', 42);
SELECT sparql.substr('', 42);
SELECT sparql.substr(NULL, 42);
SELECT sparql.substr('"foo"', NULL);

/* CONCAT */
SELECT sparql.concat('"foo"', '"bar"'), sparql.concat('foo', 'bar');
SELECT sparql.concat('"foo"@en', '"bar"@en'), sparql.concat(sparql.strlang('foo','en'), sparql.strlang('bar','en'));
SELECT sparql.concat('"foo"^^xsd:string', '"bar"^^xsd:string'), sparql.concat(sparql.strdt('foo','xsd:string'), sparql.strdt('bar','xsd:string'));
SELECT sparql.concat('"foo"', '"bar"^^xsd:string'), sparql.concat('foo', sparql.strdt('bar','xsd:string'));
SELECT sparql.concat('"foo"@en', '"bar"'), sparql.concat(sparql.strlang('foo','en'), 'bar');
SELECT sparql.concat('"foo"@en', '"bar"^^xsd:string'), sparql.concat(sparql.strlang('foo','en'), sparql.strdt('bar','xsd:string'));
SELECT sparql.concat(NULL, 'bar'), sparql.concat('foo', NULL), sparql.concat(NULL, NULL);
SELECT sparql.concat('foo', ''), sparql.concat('', 'bar'), sparql.concat('', ''), sparql.concat('""', '""');
SELECT sparql.concat('"foo"^^foo:bar', 'bar'), sparql.concat('"foo"', '"bar"^^foo:bar');
SELECT sparql.concat('"foo"@en','"&"@en', '"bar"@en');
SELECT sparql.concat('"foo"^^xsd:string','"&"^^xsd:string', '"bar"^^xsd:string');
SELECT sparql.concat('"foo"','"&"', '"bar"');
SELECT sparql.concat('"foo"^^xsd:string','"&"^^xsd:string', NULL);

  /* REPLACE */
SELECT sparql.replace('"abcd"', '"b"', '"Z"'), sparql.replace('abcd', 'b', 'Z');
SELECT sparql.replace('"abab"', '"B"', '"Z"','"i"'), sparql.replace('abab', 'B', 'Z','i');
SELECT sparql.replace('"abab"', '"B."', '"Z"','"i"'), sparql.replace('abab', 'B.', 'Z','i');
SELECT sparql.replace('"abcd"@en', '"b"', '"Z"'), sparql.replace(sparql.strlang('abcd','en'), 'b', 'Z');
SELECT sparql.replace('"abab"^^xsd:string', '"B"', '"Z"','"i"'), sparql.replace(sparql.strdt('abab','xsd:string'), 'B', 'Z','i');
SELECT sparql.replace('"abcd"', '"b"@en', '"Z"'), sparql.replace('abcd', sparql.strlang('b','en'), 'Z');
SELECT sparql.replace('"abab"', '"B"^^xsd:string', '"Z"','"i"'), sparql.replace('abab', sparql.strdt('B','xsd:string'), 'Z','i');
SELECT sparql.replace('""', '"b"', '"Z"'), sparql.replace('', 'b', 'Z');
SELECT sparql.replace('"abcd"', '""', '"Z"'), sparql.replace('abcd', '', 'Z');
SELECT sparql.replace('"abcd"', '"b"', '""'), sparql.replace('abcd', 'b', '');
SELECT sparql.replace('"ab\"cd"', '"b"', '"Z"'), sparql.replace('ab\"cd', 'b', 'Z');
SELECT sparql.replace(NULL, 'b', 'Z'), sparql.replace('abcd', NULL, 'Z'), sparql.replace('abcd', 'b', NULL), sparql.replace('abcd', 'b', 'Z', NULL);
SELECT sparql.replace('', 'a', 'Z');                -- Empty input string
SELECT sparql.replace('abcd', '', 'Z');             -- Empty pattern
SELECT sparql.replace('abcd', 'a', '');             -- Empty replacement
SELECT sparql.replace('', '', 'Z');                 -- Empty pattern and replacement
SELECT sparql.replace('abcd', 'a', 'Z');            -- Pattern at the beginning
SELECT sparql.replace('abcd', 'd', 'Z');            -- Pattern at the end
SELECT sparql.replace('abcd', 'bc', 'Z');           -- Pattern in the middle
SELECT sparql.replace('aabbcc', 'b', 'Z');          -- Multiple occurrences of the pattern
SELECT sparql.replace('Abcd', 'a', 'Z');            -- Case mismatch pattern
SELECT sparql.replace('abcd', 'A', 'Z');            -- Case mismatch pattern (uppercase in input)
SELECT sparql.replace('abcd', 'A', 'Z','i');        -- Case-insensitive replacement
SELECT sparql.replace('"abcd"', '"b"', '"Z"');      -- Special characters inside quotes
SELECT sparql.replace('ab\cd', 'b\\', 'Z');         -- Escaped backslashes
SELECT sparql.replace('ab"cd', '"b"', '"Z"');       -- Quotes in the input
SELECT sparql.replace('ab"cd', 'b"', 'Z');          -- Quotes in pattern
SELECT sparql.replace('abcdef', 'bc', 'ZY');        -- Multi-character pattern in the middle
SELECT sparql.replace('abc abc', 'abc', 'XYZ');     -- Multiple occurrences of a multi-character pattern
SELECT sparql.replace('abcd', 'a', 'Z');            -- Pattern at the start
SELECT sparql.replace('abcd', 'd', 'Z');            -- Pattern at the end
SELECT sparql.replace('abcdabcd', 'abcd', 'XYZ');   -- Pattern at the start and repeated
SELECT sparql.replace(NULL, 'a', 'Z');              -- Input is NULL
SELECT sparql.replace('abcd', NULL, 'Z');           -- Pattern is NULL
SELECT sparql.replace('abcd', 'a', NULL);           -- Replacement is NULL
SELECT sparql.replace(NULL, NULL, NULL);             -- All NULLs
SELECT sparql.replace('"ab\"cd"', '"b"', '"Z"');    -- Escaped double quotes
SELECT sparql.replace('"ab\"cd"', 'b', 'Z');         -- Escaped double quotes, no pattern
SELECT sparql.replace('"abcd"@en', 'a', 'Z');       -- Language-tagged literal
SELECT sparql.replace('"abcd"^^xsd:string', 'a', 'Z'); -- Datatype-literal (xsd:string)
SELECT sparql.replace('"abcd"^^xsd:date', 'a', 'Z'); -- Datatype-literal (xsd:date)
SELECT sparql.replace('ababab', 'ab', 'XY', 'g');   -- Global replacement
SELECT sparql.replace('ababab', 'ab', 'XY');         -- Non-global replacement (should only replace first occurrence)
SELECT sparql.replace('abcd', '', 'Z', 'g');         -- Empty pattern with global flag
SELECT sparql.replace('abcd', '', 'Z');              -- Empty pattern without global flag
SELECT sparql.replace('abcd', 'z', 'Z');             -- No pattern match
SELECT sparql.replace('abcd', 'xy', 'Z');            -- No match for multi-character pattern
SELECT sparql.replace('a' || repeat('b', 1000) || 'c', 'b'::text, 'Z'::text);  -- Long string with repeated pattern
SELECT sparql.replace('abcd', 'abcd', 'XYZ');       -- Pattern matches the entire string
SELECT sparql.replace('abcdabcd', 'abcd', 'XYZ');   -- Pattern matches at the start
SELECT sparql.replace('""', '"b"', '"Z"');           -- Empty literal as input
SELECT sparql.replace('"b"', '""', '"Z"');            -- Empty pattern in replacement
SELECT sparql.replace('abcd', 'a.b', 'Z', 'g');      -- Dot in pattern (regex)
SELECT sparql.replace('abcd', '[a-b]', 'Z', 'g');     -- Range in regex pattern
SELECT sparql.replace('abcd', '(ab)', 'Z', 'g');      -- Group in regex pattern

/* REGEX */
SELECT sparql.regex('"abcd"', '"bc"');
SELECT sparql.regex('"abcd"', '"xy"');
SELECT sparql.regex('"abcd"', '"BC"', '"i"');
SELECT sparql.regex('"abcd"', '"^bc"');
SELECT sparql.regex('"abcd"', '"^ab"');
SELECT sparql.regex('"abc\ndef"', '"^def$"', '"m"');
SELECT sparql.regex('"abc\ndef"', '"c.d"', '"s"');
SELECT sparql.regex('"abcd"@en', '"bc"');
SELECT sparql.regex('"123"^^xsd:int', '"23"');
SELECT sparql.regex('""', '"a"');
SELECT sparql.regex('""', '"(.*)"');
SELECT sparql.regex('"abcd"', '""');
SELECT sparql.regex(NULL, '"a"'), sparql.regex('"abcd"', NULL), sparql.regex('"abcd"', '"a"', NULL);
SELECT sparql.regex('"abcd"', '"[a"');

/* ABS */
SELECT sparql.abs('"-1"^^xsd:int');
SELECT sparql.abs('"-1.42"^^xsd:double');
SELECT sparql.abs(sparql.strdt('-1.42','xsd:double'));
SELECT sparql.abs(sparql.strdt('-1.42238','xsd:double'));
SELECT sparql.abs('');
SELECT sparql.abs(' ');
SELECT sparql.abs(NULL);
SELECT sparql.abs(CAST(-1.42 AS numeric));
SELECT sparql.abs(CAST(-1.42 AS double precision));
--SELECT sparql.abs(CAST(-1.42 AS real));
SELECT sparql.abs(CAST(-1 AS bigint));
SELECT sparql.abs(CAST(-1 AS smallint));
SELECT sparql.abs(CAST(-1 AS int));

/* ROUND */
SELECT sparql.round('"2.4999"^^xsd:double');
SELECT sparql.round('"2.5"^^xsd:double');
SELECT sparql.round('"-2.5"^^xsd:decimal');
SELECT sparql.round('');
SELECT sparql.round('""');
SELECT sparql.round(' ');
SELECT sparql.round('" "');
SELECT sparql.round(NULL);
SELECT sparql.round(CAST(2.49999 AS numeric));
SELECT sparql.round(CAST(2.5 AS double precision));
--SELECT sparql.round(CAST(-2.5 AS real));
SELECT sparql.round(CAST(42 AS bigint));
SELECT sparql.round(CAST(42 AS smallint));
SELECT sparql.round(CAST(42 AS int));

/* CEIL */
SELECT sparql.ceil('"10.5"^^xsd:double');
SELECT sparql.ceil('"-10.5"^^xsd:decimal');
SELECT sparql.ceil(NULL);
SELECT sparql.ceil(CAST(10.5 AS numeric));
SELECT sparql.ceil(CAST(-10.5 AS double precision));
SELECT sparql.ceil(CAST(10.5 AS real));
SELECT sparql.ceil(CAST(-42 AS bigint));
SELECT sparql.ceil(CAST(42 AS smallint));
SELECT sparql.ceil(CAST(-42 AS int));

/* FLOOR */
SELECT sparql.floor('"10.5"^^xsd:double');
SELECT sparql.floor('"-10.5"^^xsd:decimal');
SELECT sparql.floor(CAST(10.5 AS numeric));
SELECT sparql.floor(CAST(-10.5 AS double precision));
SELECT sparql.floor(CAST(10.5 AS real));
SELECT sparql.floor(CAST(-42 AS bigint));
SELECT sparql.floor(CAST(42 AS smallint));
SELECT sparql.floor(CAST(-42 AS int));

/* YEAR */
SELECT sparql.year('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.year('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.year('2011-01-10T14:45:13.815-05:00');
SELECT sparql.year('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.year('2011-01-10T14:45:13.815-05:00'::timestamp);

/* MONTH */
SELECT sparql.month('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.month('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.month('2011-01-10T14:45:13.815-05:00');
SELECT sparql.month('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.month('2011-01-10T14:45:13.815-05:00'::timestamp);

/* DAYS */
SELECT sparql.day('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.day('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.day('2011-01-10T14:45:13.815-05:00');
SELECT sparql.day('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.day('2011-01-10T14:45:13.815-05:00'::timestamp);

/* HOURS */
SELECT sparql.hours('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.hours('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.hours('2011-01-10T14:45:13.815-05:00');
SELECT sparql.hours('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.hours('2011-01-10T14:45:13.815-05:00'::timestamp);

/* MINUTES */
SELECT sparql.minutes('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.minutes('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.minutes('2011-01-10T14:45:13.815-05:00');
SELECT sparql.minutes('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.minutes('2011-01-10T14:45:13.815-05:00'::timestamp);

/* SECONDS */
SELECT pg_catalog.round(sparql.seconds('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime'),3);
SELECT pg_catalog.round(sparql.seconds('"2011-01-10T14:45:13.815-05:00"'),3);
SELECT pg_catalog.round(sparql.seconds('2011-01-10T14:45:13.815-05:00'),3);
SELECT pg_catalog.round(sparql.seconds('2011-01-10T14:45:13.815-05:00'::date),3);
SELECT pg_catalog.round(sparql.seconds('2011-01-10T14:45:13.815-05:00'::timestamp),3);

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

/*BOUND */
SELECT sparql.bound(NULL);
SELECT sparql.bound('abc');

/* SAMETERM */
SELECT sparql.sameterm('"abc"', '"abc"');
SELECT sparql.sameterm('"abc"@en', '"abc"@en');
SELECT sparql.sameterm('"abc"@en', '"abc"');
SELECT sparql.sameterm('"abc"^^xsd:string', '"abc"');
SELECT sparql.sameterm(NULL, '"abc"');
SELECT sparql.sameterm(NULL, NULL);

/* COALESCE */
SELECT sparql.coalesce(NULL, NULL, 'foo');
SELECT sparql.coalesce(NULL, NULL, '"foo"');
SELECT sparql.coalesce(NULL, NULL, '"foo"^^xsd:string');
SELECT sparql.coalesce(NULL, NULL, '"foo"@fr');
SELECT sparql.coalesce(NULL, NULL, '<http://example/>');
SELECT sparql.coalesce(NULL, NULL, sparql.iri('"http://example/"'));
SELECT sparql.coalesce(NULL, NULL, sparql.bnode('foo'));

/* MD5 */
SELECT sparql.md5('abc');
SELECT sparql.md5('"abc"');
SELECT sparql.md5('"abc"^^xsd:string');
SELECT sparql.md5('"abc"^^xsd:string') = sparql.md5('abc');
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
