\pset null NULL

SELECT '<http://foo.bar#1>'::rdf_iri <> '<http://foo.bar#1>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri <> '<http://foo.bar#2>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri <> NULL;
SELECT '<http://foo.bar#1>'::rdf_iri <> '<http://foo.bar#1>'::text;
SELECT '<http://foo.bar#1>'::rdf_iri <> '<http://foo.bar#2>'::text;
SELECT '<http://foo.bar#1>'::text <> '<http://foo.bar#1>'::rdf_iri;
SELECT '<http://foo.bar#1>'::text <> '<http://foo.bar#2>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri <> '<http://foo.bar#1>'::rdfnode;
SELECT '<http://foo.bar#1>'::rdfnode <> '<http://foo.bar#1>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri != '<http://foo.bar#1>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri != '<http://foo.bar#2>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri != NULL;
SELECT '<http://foo.bar#1>'::rdf_iri != '<http://foo.bar#1>'::text;
SELECT '<http://foo.bar#1>'::rdf_iri != '<http://foo.bar#2>'::text;
SELECT '<http://foo.bar#1>'::text != '<http://foo.bar#1>'::rdf_iri;
SELECT '<http://foo.bar#1>'::text != '<http://foo.bar#2>'::rdf_iri;
SELECT '<http://foo.bar#1>'::rdf_iri != '<http://foo.bar#1>'::rdfnode;
SELECT '<http://foo.bar#1>'::rdfnode != '<http://foo.bar#1>'::rdf_iri;