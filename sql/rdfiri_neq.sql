\pset null NULL

SELECT '<http://foo.bar#1>'::rdf_iri <> '<http://foo.bar#1>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri <> '<http://foo.bar#2>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri <> NULL;
SELECT '<http://foo.bar#1>'::rdf_iri <> '<http://foo.bar#1>'::text;
SELECT '<http://foo.bar#1>'::rdf_iri <> '<http://foo.bar#2>'::text;
SELECT '<http://foo.bar#1>'::text <> '<http://foo.bar#1>'::rdf_iri;
SELECT '<http://foo.bar#1>'::text <> '<http://foo.bar#2>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri <> '<http://foo.bar#1>'::rdf_literal;
SELECT '<http://foo.bar#1>'::rdf_literal <> '<http://foo.bar#1>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri != '<http://foo.bar#1>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri != '<http://foo.bar#2>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri != NULL;
SELECT '<http://foo.bar#1>'::rdf_iri != '<http://foo.bar#1>'::text;
SELECT '<http://foo.bar#1>'::rdf_iri != '<http://foo.bar#2>'::text;
SELECT '<http://foo.bar#1>'::text != '<http://foo.bar#1>'::rdf_iri;
SELECT '<http://foo.bar#1>'::text != '<http://foo.bar#2>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri != '<http://foo.bar#1>'::rdf_literal;
SELECT '<http://foo.bar#1>'::rdf_literal != '<http://foo.bar#1>'::rdf_iri;