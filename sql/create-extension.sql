/*
 * The extension may be installed into a schema other than public. Nothing may
 * assume otherwise: the rdfnode type is created without a schema and so lands
 * wherever the extension went, and the C code has to find it there.
 *
 * The schema is put on the search_path to use it, which is how an extension in
 * a schema of its own is normally reached -- operators are always resolved
 * through the search_path, so rdfnode's would not be visible without it.
 */
CREATE SCHEMA rdf_alt;
CREATE EXTENSION rdf_fdw SCHEMA rdf_alt VERSION '2.8';

SET search_path = rdf_alt, public;

SELECT '"1"^^xsd:integer'::rdf_alt.rdfnode;
SELECT sparql.round('"1.5"^^xsd:decimal'), sparql.abs('"-3"^^xsd:integer');

CREATE SERVER alt_srv FOREIGN DATA WRAPPER rdf_fdw
  OPTIONS (endpoint 'http://127.0.0.1:9/sparql');
CREATE FOREIGN TABLE alt_ft (s rdf_alt.rdfnode OPTIONS (variable '?s'))
  SERVER alt_srv OPTIONS (sparql 'SELECT ?s {?s ?p ?o}');
EXPLAIN (COSTS OFF) SELECT s FROM alt_ft WHERE s = '<http://example.org/x>';

RESET search_path;
DROP SERVER alt_srv CASCADE;
DROP EXTENSION rdf_fdw;
DROP SCHEMA rdf_alt;

/* reinstate the ordinary installation for the rest of the suite */
CREATE EXTENSION rdf_fdw;
