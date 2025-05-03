\pset null NULL

SELECT '<http://www.w3.org/2001/XMLSchema#int>'::rdf_iri;
SELECT 'http://www.w3.org/2001/XMLSchema#string'::rdf_iri;
SELECT 'xsd:anyURI'::rdf_iri;
SELECT 'http://example/'::rdf_iri;
SELECT '<http://example/>'::rdf_iri;
SELECT 'mailto:foo@example.com'::rdf_iri;
SELECT '"mailto:foo@example.com"'::rdf_iri;
SELECT '<mailto:foo@example.com>'::rdf_iri;
SELECT '"urn:uuid:123e4567-e89b-12d3-a456-426614174000"'::rdf_iri;
SELECT '<urn:uuid:123e4567-e89b-12d3-a456-426614174000>'::rdf_iri;
SELECT 'urn:uuid:123e4567-e89b-12d3-a456-426614174000'::rdf_iri;
SELECT '"42"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_iri;
SELECT '"foo"@en'::rdf_iri;
SELECT '"foo:bar"'::rdf_iri;
SELECT 'foo:bar'::rdf_iri;
SELECT '<foo:bar>'::rdf_iri;
SELECT '"foo"'::rdf_iri;
SELECT 'foo'::rdf_iri;
SELECT '<foo>'::rdf_iri;
SELECT '"a:b:c"'::rdf_iri;
SELECT 'a:b:c'::rdf_iri;
SELECT '<a:b:c>'::rdf_iri;
SELECT '"http:/not-a-scheme"'::rdf_iri; 
SELECT 'http:/not-a-scheme'::rdf_iri;
SELECT '<http:/not-a-scheme>'::rdf_iri;
SELECT '"foo"@en'::rdf_iri;
SELECT '"42"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_iri;
SELECT 'http://example.com:80/foo'::rdf_iri;
SELECT 'HTTP://example.com/'::rdf_iri;
SELECT 'http://例え.テスト/こんにちは'::rdf_iri;
SELECT 'http://example.org/\u00E9'::rdf_iri;
SELECT '"foo@en'::rdf_iri;
SELECT '""^^<http://example.org/>'::rdf_iri;
SELECT '"foo"^^bar'::rdf_iri;
SELECT '_:bnode'::rdf_iri;
SELECT ''::rdf_iri;
SELECT '""'::rdf_iri;
SELECT NULL::rdf_iri;


