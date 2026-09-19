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

/*
 * A language tag is compared without regard to case (RDF 1.1 Concepts, 3.3),
 * so two literals carrying one tag written differently are compatible. Only
 * the part before the first hyphen is lowercased when a term is read, so a
 * region subtag reaches the comparison as it was written.
 */
SELECT sparql.rdf_fdw_arguments_compatible('"abc"@EN','"b"@en');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"@en-GB','"b"@en-gb');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"@en-gb','"b"@en-GB');
SELECT sparql.rdf_fdw_arguments_compatible('"abc"@zh-Hant-TW','"b"@ZH-HANT-tw');
/* a different tag is still a different tag */
SELECT sparql.rdf_fdw_arguments_compatible('"abc"@en-GB','"b"@en-US');

/*
 * The compatibility rule is about literals. An IRI and a blank node are not
 * literals, so a string function has nothing to apply and answers with a type
 * error. Neither carries a language tag or a datatype, which is what a rule
 * written in terms of those alone reads as a simple literal.
 */
SELECT sparql.rdf_fdw_arguments_compatible('<http://example.org/a>','"a"');
SELECT sparql.rdf_fdw_arguments_compatible('"a"','<http://example.org/a>');
SELECT sparql.rdf_fdw_arguments_compatible('<http://example.org/a>','<http://example.org/a>');
SELECT sparql.rdf_fdw_arguments_compatible('_:b1','"b"');
SELECT sparql.rdf_fdw_arguments_compatible('"b"','_:b1');
SELECT sparql.rdf_fdw_arguments_compatible('_:b1','_:b1');

/*
 * The functions themselves therefore return NULL. What they returned before
 * was computed from the way the term is written: STRBEFORE cut an IRI at the
 * first "/" and handed back a literal that began with the opening angle
 * bracket.
 */
SELECT sparql.contains('<http://example.org/abc>','"abc"');
SELECT sparql.strstarts('<http://example.org/abc>','"<ht"');
SELECT sparql.strbefore('<http://example.org/abc>','"/"');
SELECT sparql.strafter('<http://example.org/abc>','"org"');
SELECT sparql.strends('<http://example.org/abc>','"abc>"');
SELECT sparql.contains('_:b1','"b"');

/* LEX */  
SELECT sparql.lex('"foo"');
SELECT sparql.lex('foo');
SELECT sparql.lex('"foo"@en');
SELECT sparql.lex('"foo"^^xsd:string');
SELECT sparql.lex(''); 
SELECT sparql.lex('""');
SELECT sparql.lex('"\""');
SELECT sparql.lex(NULL);

/* backslash runs of both parities before the closing quote. An even-length
 * run is made of complete escape pairs and does NOT escape that quote, so the
 * literal is well formed and lex() must return the run itself, with no quotes
 * folded into it, and the plain and language-tagged forms must agree. An
 * odd-length run does escape the closing quote, leaving the literal
 * unterminated: lex() then returns the whole input, and lang() must find no
 * tag rather than reading past it. */
SELECT n,
       sparql.lex(('"' || repeat('\', n) || '"')::rdfnode)    AS plain,
       sparql.lex(('"' || repeat('\', n) || '"@en')::rdfnode) AS tagged,
       sparql.lex(('"' || repeat('\', n) || '"')::rdfnode)
         = sparql.lex(('"' || repeat('\', n) || '"@en')::rdfnode) AS agree
FROM generate_series(0, 8) AS n
ORDER BY n;

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
SELECT sparql.strdt('_:b1', 'xsd:string');

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
SELECT sparql.strlang('foo', 'EN');
SELECT sparql.strlang('foo', 'EN-GB');
SELECT sparql.strlang('foo', 'eN-gb');
SELECT sparql.strlang('foo', 'EN-Latn-US-valencia');
SELECT sparql.strlang('_:b1', 'en');

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
/*
 * STRLEN, LANG and REPLACE are defined over literals, and an IRI or a blank
 * node has no lexical form for them to work on. They used to operate on the
 * term's written shape instead: STRLEN counted the angle brackets, REPLACE
 * rewrote the IRI and handed back a literal, and LANG reported the empty tag
 * that belongs to a plain literal. Fuseki and GraphDB leave all three unbound
 * for an IRI, and UCASE, LCASE, SUBSTR and CONCAT here already refuse one.
 */
SELECT sparql.strlen('<http://example.org/abc>');
SELECT sparql.strlen('_:b1');
SELECT sparql.replace('<http://example.org/abc>', 'a', 'Z');
SELECT sparql.replace('<http://example.org/abc>'::rdfnode, 'a'::rdfnode, 'Z'::rdfnode);
SELECT sparql.replace('_:b1'::rdfnode, 'b'::rdfnode, 'Z'::rdfnode);
SELECT sparql.lang('_:b1');

/* STR is the exception and must keep taking an IRI: STR of an IRI is defined
 * and gives its string form. */
SELECT sparql.str('<http://example.org/abc>');

/* STRLEN counts code points of a string literal's lexical form, and refuses a
 * literal that is not a string -- which is what every store does with it. */
SELECT sparql.strlen('"hello"') AS plain,
       sparql.strlen('"h\u00e9llo"@en') AS tagged,
       sparql.strlen('"hello"^^xsd:string') AS typed;
SELECT sparql.strlen('"42"^^xsd:integer');

SELECT sparql.lang('<http://example.org>'); 

/* a literal whose only inner quote is escaped has no closing quote, so it is
 * malformed and simply has no language tag. lang() used to locate the tag by
 * skipping the opening quote and then advancing by the length of lex(), which
 * for this input returns the whole string -- landing one byte past the end of
 * the allocation. Whatever happened to sit there was read, and when it was
 * '@' the scan walked on and copied adjacent heap bytes into the tag. */
SELECT sparql.lang('"abc\"@en'::rdfnode) AS unterminated_has_no_tag;

/* the same read, swept across every lexical length so it is not left to one
 * allocation size to expose it: no tag may be recovered from any of them, and
 * the stored value may never grow beyond what was supplied */
SELECT count(*) AS tags_recovered_from_past_the_end
FROM generate_series(1, 255) AS k
WHERE sparql.lang(('"' || repeat('a', k) || '\"@en')::rdfnode)::text <> '';

SELECT count(*) AS values_that_grew
FROM generate_series(1, 255) AS k
WHERE length(('"' || repeat('a', k) || '\"@en')::rdfnode::text)
        <> length('"' || repeat('a', k) || '\"@en');

/* a doubled quote is an escaped quote, not the end of the lexical form, so
 * the tag after the real closing quote is still found */
SELECT sparql.lex('"a""b"@en'::rdfnode) AS doubled_quote_lex,
       sparql.lang('"a""b"@en'::rdfnode) AS doubled_quote_lang;

/* DATATYPE */
SELECT sparql.datatype('foo');
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

/* SPARQL 1.1 17.4.2.8 gives URI() as another name for IRI(), both returning an
 * iri. They must therefore agree on every input and be usable in the same
 * places -- uri() returned text, so its result went into nothing else. */
SELECT sparql.uri('http://example/') AS uri,
       sparql.uri('http://example/') = sparql.iri('http://example/') AS same_term,
       pg_typeof(sparql.uri('http://example/')) = pg_typeof(sparql.iri('http://example/')) AS same_type;

SELECT sparql.isiri(sparql.uri('http://example/')) AS composes;

SELECT bool_and(sparql.uri(v) = sparql.iri(v)) AS agree_on_every_input
FROM (VALUES ('"http://example/"'::rdfnode), ('http://example/'), ('<http://example/>'),
             ('"foo"'), ('<foo>'), ('"a:b:c"'), ('"foo"@en')) t(v);
SELECT sparql.iri('_:b1');
SELECT sparql.iri('"<https://example/>"');

  /* isIRI / isURI */
SELECT sparql.isIRI('<https://example/>'); 
SELECT sparql.isIRI('<mailto:foo@example.com>');
SELECT sparql.isIRI('http://example/');
SELECT sparql.isIRI('"http://example/"');
SELECT sparql.isIRI('"<http://example/>"');
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
SELECT sparql.isURI('"<http://example/>"');

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
SELECT sparql.strbefore('"abc"', '"b"^^xsd:integer');

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
SELECT sparql.contains('"foobar"@en', '"bar"^^xsd:string');
SELECT sparql.contains('"foobar"^^xsd:string', '"foo"');

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
SELECT sparql.langmatches('', '');
SELECT sparql.langmatches('en', '');
SELECT sparql.langmatches('', '"en"');
SELECT sparql.langmatches('en', '"en"');
SELECT sparql.langmatches(sparql.lang('"hello"@en'), '');
SELECT sparql.langmatches('', '"*"');
SELECT sparql.langmatches('en-US', 'en');
/* "*" must not match empty language tags */
SELECT sparql.langmatches('', '"*"');                                     -- f
SELECT sparql.langmatches(sparql.lang('"hello"'), '"*"');                 -- f (no lang tag)
SELECT sparql.langmatches(sparql.lang('""'), '"*"');                      -- f (empty literal, no lang)
SELECT sparql.langmatches(sparql.lang('"hello"^^xsd:string'), '"*"');     -- f (typed, no lang)
/* subtag prefix matching */
SELECT sparql.langmatches('en-Latn-US', 'en');                            -- t
SELECT sparql.langmatches('zh-Hant-TW', 'zh');                            -- t
SELECT sparql.langmatches('zh-Hant-TW', 'zh-Hant');                       -- t
SELECT sparql.langmatches('zh-Hant-TW', 'zh-Hans');                       -- f

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
SELECT sparql.isblank('"_:b1"');

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
SELECT sparql.isliteral('"<http://example.org>"');
SELECT sparql.isliteral('"_:bnode"');
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
SELECT sparql.lcase('"ŁÓÒÁÀÂÆÄÉÈÊÍÌÎÓÒØÔÖÚÙÛÜÞ"');
SELECT sparql.lcase('"ŁÓÒÁÀÂÆÄÉÈÊÍÌÎÓÒØÔÖÚÙÛÜÞ"^^<http://www.w3.org/2001/XMLSchema#string>');
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
SELECT sparql.ucase('"łóòáàâæäéèêíìîóòøôöúùûüþ"');
SELECT sparql.ucase('"łóòáàâæäéèêíìîóòøôöúùûüþ"@de');
SELECT sparql.ucase('"łóòáàâæäéèêíìîóòøôöúùûüþ"^^<http://www.w3.org/2001/XMLSchema#string>');
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
SELECT sparql.strlen('"łø"@de'), sparql.strlen(sparql.strlang('łø','de'));
SELECT sparql.strlen('"łø"@de'), sparql.strlen(sparql.strdt('łø','<http://www.w3.org/2001/XMLSchema#string>'));
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
SELECT sparql.substr('"łóòáàâæäéèêíìîóòøôöúùûüþ"@de'::rdfnode, 1, 24);
SELECT sparql.substr('"łóòáàâæäéèêíìîóòøôöúùûüþ"'::rdfnode, 1, 24);
SELECT sparql.substr('"łóòáàâæäéèêíìîóòøôöúùûüþ"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode, 1, 24);
SELECT sparql.substr('"foobar"', 0);       -- SPARQL is 1-indexed; pos 0 is defined as "" or same as pos 1 per XPath
SELECT sparql.substr('"foobar"', 1, 0);    -- zero-length -> ""
SELECT sparql.substr('"foobar"', 10);      -- beyond length -> ""
SELECT sparql.substr('"foobar"', 2, 100);  -- length beyond string end -> "oobar"
SELECT sparql.substr('"foobar"', NULL, 3); -- NULL arg

/* XPath fn:substring, which SPARQL SUBSTR follows, selects the characters whose
 * position falls in [start, start + length). A start below 1 is not an error:
 * it simply places part of that interval before the string, and only the
 * overlap is returned. Start 0 with length 2 therefore yields one character,
 * not two, and a start far enough to the left yields nothing at all. */
SELECT s AS start, l AS len, sparql.lex(sparql.substr('"foobar"', s, l)) AS result
FROM (VALUES (0,2),(0,1),(0,0),(-1,3),(-2,3),(0,7),(-5,20),(1,2)) t(s,l);

/* without a length the interval is unbounded to the right, so any start at or
 * before the first character returns the whole string */
SELECT s AS start, sparql.lex(sparql.substr('"foobar"', s)) AS result
FROM (VALUES (0),(-3),(1),(7)) t(s);

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
SELECT sparql.concat('"foo"@en','"bar"@de');
SELECT sparql.concat('"foo"^^<http://www.vocab.es#UNKNOWN>','"bar"^^<http://www.w3.org/2001/XMLSchema#string>');
SELECT sparql.concat('"foo"^^<http://www.vocab.es#UNKNOWN>','"bar"');
SELECT sparql.concat('"foo"@en', '"bar"@de');
SELECT sparql.concat('"a"@en', '"b"@en', '"c"@fr');  -- should be "abc" (plain, not @en)
SELECT sparql.concat(NULL, NULL, NULL, NULL);

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
SELECT sparql.replace('abc.def', '[.]', 'X', 'g');   -- character class containing a literal dot, matches only the .
SELECT sparql.replace('abc.def', '.', 'X', 'g');     -- regex wildcard, matches any character, so all 7 characters are replaced

/* The result is built from lexical content, so it must be quoted as a literal
 * rather than read back as a serialised term: a replacement that happens to
 * look like an IRI or to carry a language tag is still just text. Content
 * ending in a backslash needs the backslash protected, or it would escape the
 * closing quote and the literal would not end where it appears to. */
SELECT sparql.replace('"x"', 'x', '<http://example.org/a>') AS looks_like_iri;
SELECT sparql.replace('"x"', 'x', 'y"@en')                  AS looks_like_lang_tag;
SELECT sparql.replace('"x"', 'x', 'y"^^xsd:date')           AS looks_like_datatype;
SELECT sparql.replace('"a"', 'a', 'b\\')                      AS trailing_backslash;

/* the language tag and datatype of the first argument survive in every
 * overload, including the four-argument one */
SELECT sparql.replace('"HELLO"@en', 'hel', 'X', 'i')             AS four_arg_lang;
SELECT sparql.replace('"ABCD"^^xsd:date', 'ab', 'Z', 'i')        AS four_arg_datatype;
SELECT sparql.replace('"abcd"^^xsd:string', 'a', 'Z')            AS xsd_string_becomes_simple;

/* cstring_to_rdfliteral() ownership.
 *
 * concat(), lcase(), ucase(), substr() and strafter() all pfree() the buffer
 * they hand to cstring_to_rdfliteral() right after storing its return value.
 * That is only correct if the result is always freshly allocated. It used not
 * to be: empty input returned a string constant, and an input that already
 * looked like a complete literal was returned as-is, so those callers freed
 * the very chunk they were about to return.
 *
 * The two inputs below take those two paths. Both lexical forms being empty
 * builds "" and used to reach the string-constant return, which pfree() then
 * read as a chunk header; '"a""@en' has no closing quote, so lex() returns
 * the whole input, which still looks like a complete literal and used to be
 * returned aliasing the buffer freed underneath it. */
SELECT sparql.concat(''::rdfnode, ''::rdfnode, 'x'::rdfnode)                 AS constant_freed;
SELECT sparql.concat(''::rdfnode, ''::rdfnode, 'x'::rdfnode, 'y'::rdfnode)   AS constant_freed_twice;
SELECT sparql.lcase('"a""@en'::rdfnode)                                      AS aliased_lcase;
SELECT sparql.ucase('"a""@en'::rdfnode)                                      AS aliased_ucase;
SELECT sparql.strafter('"a""@en'::rdfnode, ''::rdfnode)                      AS aliased_strafter;
SELECT sparql.concat('"a""@en'::rdfnode, ''::rdfnode)                        AS aliased_concat;
SELECT sparql.substr('"a""@en'::rdfnode, 1)                                  AS aliased_substr;

/* rdf_fdw_concat() keeps the returned pointer across loop iterations and
 * pfree()s it again while processing the next element, so an aliased result
 * was pushed onto the freelist twice */
SELECT sparql.concat('"a""@en'::rdfnode, ''::rdfnode, 'x'::rdfnode)          AS freed_twice;

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

/* The exact numeric datatypes must stay exact. Computing them in floating
 * point rounds large integers and small decimals, and prints the result in an
 * exponent form that the lexical space of xsd:integer and xsd:decimal does not
 * admit, so the value comes back both wrong and ill-typed. */
SELECT sparql.abs('"-9007199254740993"^^xsd:integer');
SELECT sparql.abs('"-0.000000000000001"^^xsd:decimal');
SELECT sparql.abs('"-1.50"^^xsd:decimal');          -- trailing zero is part of the value
SELECT sparql.abs('"-42"^^xsd:int');                -- integer subtypes keep their datatype

/* the floating datatypes are still computed in floating arithmetic */
SELECT sparql.abs('"-1.1234567"^^xsd:float'), sparql.abs('"-1.5"^^xsd:double');
SELECT sparql.abs('"NaN"^^xsd:double'), sparql.abs('"-INF"^^xsd:double');

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

/* SPARQL ROUND breaks ties towards positive infinity, so the result of a
 * negative argument is not the mirror image of the positive one: ROUND(-2.5)
 * is -2 while ROUND(2.5) is 3. Zero and the negative fractions above -1 are
 * the cases a sign test gets wrong. */
SELECT v AS input,
       sparql.lex(sparql.round(('"'||v||'"^^xsd:decimal')::rdfnode)) AS as_decimal,
       sparql.lex(sparql.round(('"'||v||'"^^xsd:double')::rdfnode))  AS as_double
FROM (VALUES ('-2.5'),('-1.5'),('-1.2'),('-0.6'),('-0.5'),
             ('0'),('0.5'),('1.2'),('1.5'),('2.5')) t(v);

/* the half is compared against the fractional part rather than added first:
 * in binary floating point 0.49999999999999994 + 0.5 is exactly 1 */
SELECT sparql.lex(sparql.round('"0.49999999999999994"^^xsd:double'::rdfnode));

/* the datatype of the argument survives, and the special values pass through */
SELECT sparql.round('"1.5"^^xsd:float'), sparql.round('"1.5"^^xsd:double'),
       sparql.round('"1.5"^^xsd:decimal'), sparql.round('"3"^^xsd:integer');
SELECT sparql.round('"NaN"^^xsd:double'), sparql.round('"INF"^^xsd:double'),
       sparql.round('"-INF"^^xsd:double');

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
SELECT sparql.year(NULL);


/* MONTH */
SELECT sparql.month('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.month('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.month('2011-01-10T14:45:13.815-05:00');
SELECT sparql.month('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.month('2011-01-10T14:45:13.815-05:00'::timestamp);
SELECT sparql.month(NULL);

/* DAYS */
SELECT sparql.day('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.day('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.day('2011-01-10T14:45:13.815-05:00');
SELECT sparql.day('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.day('2011-01-10T14:45:13.815-05:00'::timestamp);
SELECT sparql.day(NULL);

/* HOURS */
SELECT sparql.hours('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.hours('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.hours('2011-01-10T14:45:13.815-05:00');
SELECT sparql.hours('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.hours('2011-01-10T14:45:13.815-05:00'::timestamp);
SELECT sparql.hours('14:45:13'::time);
SELECT sparql.hours(NULL);

/* MINUTES */
SELECT sparql.minutes('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime');
SELECT sparql.minutes('"2011-01-10T14:45:13.815-05:00"');
SELECT sparql.minutes('2011-01-10T14:45:13.815-05:00');
SELECT sparql.minutes('2011-01-10T14:45:13.815-05:00'::date);
SELECT sparql.minutes('2011-01-10T14:45:13.815-05:00'::timestamp);
SELECT sparql.minutes('14:45:13'::time);
SELECT sparql.minutes(NULL);

/* SECONDS */
SELECT pg_catalog.round(sparql.seconds('"2011-01-10T14:45:13.815-05:00"^^xsd:dateTime'),3);
SELECT pg_catalog.round(sparql.seconds('"2011-01-10T14:45:13.815-05:00"'),3);
SELECT pg_catalog.round(sparql.seconds('2011-01-10T14:45:13.815-05:00'),3);
SELECT pg_catalog.round(sparql.seconds('2011-01-10T14:45:13.815-05:00'::date),3);
SELECT pg_catalog.round(sparql.seconds('2011-01-10T14:45:13.815-05:00'::timestamp),3);
SELECT pg_catalog.round(sparql.seconds('14:45:13.815'::time),3);
SELECT sparql.seconds(NULL);

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
SELECT sparql.sameterm('<http://example.org>', '<http://example.org>');   -- t (IRIs)
SELECT sparql.sameterm('_:b1', '_:b1');  -- t (same blank node label)
SELECT sparql.sameterm('_:b1', '_:b2');  -- f (different labels)
SELECT sparql.sameterm('"1"^^xsd:integer', '"01"^^xsd:integer');  -- f (different lexical form)
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

/* RAND */
SELECT sparql.rand() >= 0 AND sparql.rand() < 1;  -- should be t
SELECT sparql.rand() != sparql.rand();            -- should be t (very low probability of being f)  

/* BNODE, UUID and STRUUID generate a new value per call, so they must not be
 * folded to a single constant for the whole query, and each must keep its own
 * result shape across rows: UUID yields an IRI, STRUUID a string literal. */
SELECT count(DISTINCT u) FROM (SELECT sparql.uuid() AS u FROM generate_series(1,100)) t;
SELECT count(DISTINCT u) FROM (SELECT sparql.struuid() AS u FROM generate_series(1,100)) t;
SELECT count(DISTINCT b) FROM (SELECT sparql.bnode() AS b FROM generate_series(1,100)) t;
SELECT bool_and(sparql.isiri(sparql.uuid()))        FROM generate_series(1,100);
SELECT bool_and(sparql.isliteral(sparql.struuid())) FROM generate_series(1,100);
SELECT bool_and(sparql.isblank(sparql.bnode()))     FROM generate_series(1,100);

/* The function bodies name the schema the extension was installed into when
 * they refer to the rdfnode type, so they do not depend on the caller having
 * that schema on its search_path. */
SET search_path = pg_catalog;
SELECT sparql.round('"1.5"^^xsd:decimal'), sparql.abs('"-3"^^xsd:integer'),
       sparql.ceil('"1.2"^^xsd:decimal'), sparql.floor('"1.8"^^xsd:decimal');
SELECT sparql.year('"2025-04-16"^^xsd:date'), sparql.md5('"x"');
RESET search_path;

/* IRI() builds a term that is asked for as an IRI, so a body that the SPARQL
 * grammar (rule [139]) forbids is a type error rather than a malformed term.
 * STRDT() routes a non-IRI datatype through the same constructor. */
SELECT sparql.iri('"http://e.org/a>.<http://e.org/b"'::rdfnode);
SELECT sparql.uri('"http://e.org/a>.<http://e.org/b"'::rdfnode);
SELECT sparql.iri('"http://e.org/{x}"'::rdfnode);
SELECT sparql.strdt('"v"'::rdfnode, '"http://e.org/t>x"'::rdfnode);

/* well-formed constructions are unaffected */
SELECT sparql.iri('"http://e.org/ok"'::rdfnode);
SELECT sparql.iri('<http://e.org/already>'::rdfnode);
SELECT sparql.strdt('"v"'::rdfnode, '"xsd:integer"'::rdfnode);
SELECT sparql.strdt('"v"'::rdfnode, '<http://e.org/t>'::rdfnode);
