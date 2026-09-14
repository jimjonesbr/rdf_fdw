/*
 * RDFNODEOID is a cached type OID that every other rdf_fdw entry point
 * refreshes on the way in. rdf_fdw_clone_table() did not, so when the
 * procedure was the first rdf_fdw call of a session it ran with the cache
 * still InvalidOid and nothing matched an rdfnode column: the <uri>, <bnode>
 * and <literal> branches were skipped and the raw XML content was stored as a
 * bare string, losing the IRI brackets, the blank node label and the language
 * tag. A clone must return exactly what selecting from the same foreign table
 * returns.
 *
 * This lives in a file of its own on purpose. pg_regress runs each test file
 * in one session, and any earlier rdf_fdw call -- a foreign scan, a sparql.*
 * function -- initialises the cache as a side effect and masks the defect
 * entirely. Keeping the procedure as the first thing the session does is what
 * makes this test able to fail; a statement added above it would silently
 * turn it into a no-op.
 *
 * It uses the stub SPARQL endpoint deployed by
 * scripts/postgres-env/stub-endpoint/deploy-stub-endpoint.sh, which serves a
 * row containing one node of each kind.
 */

CREATE SERVER stub_node_types
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'http://stub-endpoint/node-types.xml',
  connect_timeout '5');

CREATE FOREIGN TABLE ft_node_types (
  iri    rdfnode OPTIONS (variable '?iri'),
  bnode  rdfnode OPTIONS (variable '?bnode'),
  tagged rdfnode OPTIONS (variable '?tagged')
) SERVER stub_node_types
  OPTIONS (sparql 'SELECT ?iri ?bnode ?tagged WHERE {?iri ?p ?o}');

CREATE TABLE cloned_node_types (iri rdfnode, bnode rdfnode, tagged rdfnode);

/* the first rdf_fdw call of this session, and it must stay that way */
CALL rdf_fdw_clone_table(
  foreign_table => 'ft_node_types',
  target_table  => 'cloned_node_types',
  fetch_size    => 1,
  max_records   => 1,
  create_table  => false,
  verbose       => false);

SELECT 'clone' AS source, * FROM cloned_node_types
UNION ALL
SELECT 'direct', * FROM ft_node_types;

SELECT sparql.isiri(iri)         AS iri_preserved,
       sparql.isblank(bnode)     AS bnode_preserved,
       sparql.lang(tagged)::text AS language_tag
FROM cloned_node_types;

/* clean up */
DROP TABLE cloned_node_types;
DROP SERVER stub_node_types CASCADE;
