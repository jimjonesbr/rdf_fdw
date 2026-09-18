/*
 * Tests against the stub SPARQL endpoint deployed by
 * scripts/postgres-env/stub-endpoint/deploy-stub-endpoint.sh.
 *
 * A conforming triplestore cannot produce the responses exercised here, so
 * these cases are not reachable through the other local tests: what rdf_fdw
 * does with a malformed or hostile answer has to be driven by an endpoint we
 * control.
 */

CREATE SERVER stub
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'http://stub-endpoint/single-binding.xml',
  connect_timeout '5');

CREATE SERVER stub_repeated
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'http://stub-endpoint/repeated-binding.xml',
  connect_timeout '5');

CREATE SERVER stub_split
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'http://stub-endpoint/split-text.xml',
  connect_timeout '5');

CREATE SERVER stub_describe
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'http://stub-endpoint/describe-bnode.xml',
  connect_timeout '5');

/* 4294967396 is 2^32 + 100: a limit that is nowhere near any response here,
 * but whose low 32 bits are 100, which is smaller than every one of them */
CREATE SERVER stub_wide_limit
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint 'http://stub-endpoint/single-binding.xml',
  max_response_size '4294967396',
  connect_timeout '5');

CREATE SERVER stub_redirect
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint   'http://stub-endpoint/redirect',
  update_url 'http://stub-endpoint/not-modified',
  connect_timeout '5');

CREATE FOREIGN TABLE ft_single (
  s rdfnode OPTIONS (variable '?s')
) SERVER stub OPTIONS (sparql 'SELECT ?s WHERE {?s ?p ?o}');

CREATE FOREIGN TABLE ft_split (
  cdata     rdfnode OPTIONS (variable '?cdata'),
  commented rdfnode OPTIONS (variable '?commented'),
  empty     rdfnode OPTIONS (variable '?empty'),
  tagged    rdfnode OPTIONS (variable '?tagged')
) SERVER stub_split OPTIONS (sparql 'SELECT * WHERE {?s ?p ?o}');

CREATE FOREIGN TABLE ft_repeated (
  s rdfnode OPTIONS (variable '?s')
) SERVER stub_repeated OPTIONS (sparql 'SELECT ?s WHERE {?s ?p ?o}');

/* control: a well formed single-binding response */
SELECT * FROM ft_single;

/*
 * A response that repeats a variable inside one <result>. InsertRetrievedData()
 * sizes its type, value and null arrays by the number of foreign table
 * columns, but used to advance the index it writes them at once per matching
 * binding instead of once per column: the inner loop walked every binding of
 * the row and did not stop at the first match. 400 bindings against a
 * one-column table therefore wrote an Oid, a char and a full 8-byte Datum
 * past the end of all three allocations, 399 times over, with both the length
 * and the contents chosen by whoever answered the request. The allocator
 * noticed the smashed chunk header:
 *
 *   ERROR:  repalloc called with invalid pointer 0x... (header 0x00007f...)
 *
 * A <result> may bind a variable once, so a record that binds one twice is
 * refused before any of it is read and the shape that overran the arrays
 * cannot be built. The scan still stops at the first match for a column,
 * which is what makes the overrun unreachable even where a record is not
 * validated.
 */
CREATE TABLE cloned_repeated (s rdfnode);

CALL rdf_fdw_clone_table(
  foreign_table => 'ft_repeated',
  target_table  => 'cloned_repeated',
  fetch_size    => 1,
  max_records   => 1,
  create_table  => false,
  verbose       => false);

SELECT count(*) AS rows_cloned, min(s::text) AS value FROM cloned_repeated;

/* the same response through an ordinary foreign scan, which takes a different
 * path and was never affected */
SELECT * FROM ft_repeated;

/*
 * A term's text is the whole of its element's character data. A CDATA section
 * or a comment inside a <literal> splits that data into several child nodes,
 * so a term read from the first child alone stops at the split: "abcdefghi"
 * arrives as "abc", and a language tag survives while the text it belongs to
 * does not. The empty literal is the control - it has no children at all, and
 * is an empty term rather than an unbound variable either way.
 */
SELECT cdata, commented, empty, tagged FROM ft_split;

SELECT sparql.lex(tagged) AS lexical_form,
       sparql.lang(tagged) AS language_tag,
       sparql.isliteral(empty) AS empty_is_a_literal
FROM ft_split;

/*
 * The subject of an rdf:Description is an IRI when the element carries
 * rdf:about and a blank node when it carries rdf:nodeID, and the two are
 * different kinds of term: <b1> names a resource, _:b1 names an unnamed one.
 * Reading both as IRIs turns every statement a DESCRIBE makes about a blank
 * node into a statement about an IRI that no store holds. The object side
 * tells them apart already, so the same label has to come back the same way
 * whether it stands as subject or object - here it appears as both.
 *
 * A node element carrying neither attribute describes a blank node the
 * document did not name, and RDF/XML 7.2.16 asks the reader to generate an
 * identifier for it. One written at the top level was skipped whole, so its
 * statements went missing; one written inside a property element -- the object
 * spelled out in place rather than referred to -- was read as character data,
 * so a described node arrived as a literal made of its own property values,
 * "Alice42". Generated labels are numeric, which an rdf:nodeID cannot be, so
 * they cannot collide with a label the document wrote.
 */
SELECT * FROM sparql.describe('stub_describe', 'DESCRIBE <http://example.org/s>');

/*
 * A server's settings have to survive being carried from planning to
 * execution. The five that libcurl takes as a long are wider than an int, so
 * one written out as an int arrives as its low 32 bits: a max_response_size of
 * 2^32 + 100 becomes a limit of 100 bytes and refuses a response it was never
 * meant to bound. The scan below returns its row when the whole value is
 * carried, and fails with the size limit when it is not.
 */
CREATE FOREIGN TABLE ft_wide_limit (
  s rdfnode OPTIONS (variable '?s')
) SERVER stub_wide_limit OPTIONS (sparql 'SELECT ?s WHERE {?s ?p ?o}');

SELECT * FROM ft_wide_limit;

DROP FOREIGN TABLE ft_wide_limit;

/*
 * A transfer that completed is not a request that succeeded. With redirects
 * refused, which is the default, an endpoint answering 3xx returns a status
 * and no result, and libcurl reports the transfer as fine.
 *
 * A read notices eventually, because nothing it can parse comes back. A write
 * does not: it sends its statement, reads no answer, and had nothing left to
 * object to - so an INSERT against an endpoint that never performed it was
 * reported as having inserted the row.
 */
CREATE FOREIGN TABLE ft_redirect (
  s rdfnode OPTIONS (variable '?s'),
  p rdfnode OPTIONS (variable '?p'),
  o rdfnode OPTIONS (variable '?o')
) SERVER stub_redirect OPTIONS (
  sparql 'SELECT * WHERE {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .');

SELECT * FROM ft_redirect;

INSERT INTO ft_redirect VALUES
  ('<http://example.org/s>', '<http://example.org/p>', '"v"');

DROP FOREIGN TABLE ft_redirect;

/*
 * A variable in an update template is a token, not a piece of text. Replacing
 * "?s" by matching characters also rewrites the "?s" that begins "?subject",
 * leaving a statement built out of half a variable name - which an endpoint
 * accepts as some other term and stores. A value is not template either: a
 * "?s" written inside a literal stays in the literal.
 */
CREATE SERVER stub_tokens
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint   'http://stub-endpoint/single-binding.xml',
  update_url 'http://stub-endpoint/single-binding.xml',
  connect_timeout '5');

CREATE FOREIGN TABLE ft_tokens (
  s       rdfnode OPTIONS (variable '?s'),
  subject rdfnode OPTIONS (variable '?subject')
) SERVER stub_tokens OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * {?s ?p ?o}',
  sparql_update_pattern '?s <http://example.org/p> ?subject .');

INSERT INTO ft_tokens (s, subject)
VALUES ('<http://example.org/a>', '"a literal holding ?s"');

DROP FOREIGN TABLE ft_tokens;

/*
 * A dropped column keeps its place in the foreign table's tuple descriptor,
 * which the scan and the clone are both indexed by, but it is mapped to no
 * SPARQL variable. Both handed that absent mapping straight to strcmp() and
 * pstrdup(), which is strlen(NULL), so any query returning a row terminated
 * the backend and took the cluster into crash recovery with it. The dropped
 * column here is the first one, which is also the one the clone reaches for
 * when it has to pick something to order by.
 */
CREATE FOREIGN TABLE ft_dropped (
  gone rdfnode OPTIONS (variable '?gone'),
  s    rdfnode OPTIONS (variable '?s')
) SERVER stub OPTIONS (sparql 'SELECT ?s WHERE {?s ?p ?o}');

ALTER FOREIGN TABLE ft_dropped DROP COLUMN gone;

SELECT * FROM ft_dropped;

CREATE TABLE cloned_dropped (s rdfnode);

CALL rdf_fdw_clone_table(
  foreign_table => 'ft_dropped',
  target_table  => 'cloned_dropped',
  fetch_size    => 1,
  max_records   => 1,
  create_table  => false,
  verbose       => false);

SELECT * FROM cloned_dropped;

DROP FOREIGN TABLE ft_dropped;
DROP TABLE cloned_dropped;

/*
 * A foreign table is allowed to have no columns, and a scan of one still has
 * something to report: the request is made, the endpoint answers, and each
 * record it returns is a row. count(*) is about the only question such a table
 * can be asked, and it was answered with zero however many records came back,
 * because the scan gave up before reading any of them.
 */
CREATE FOREIGN TABLE ft_columnless ()
  SERVER stub OPTIONS (sparql 'SELECT ?s WHERE {?s ?p ?o}');

SELECT count(*) AS records_counted FROM ft_columnless;

DROP FOREIGN TABLE ft_columnless;

/*
 * A clone commits each page as it goes, which ends the transaction that held
 * the lock on the source and the moment its privileges were checked against.
 * Every page after the first was therefore read without either: the caller
 * could lose SELECT on the foreign table and the clone would carry on reading
 * it. The check and the lock are taken again for each page.
 *
 * The revoke is issued from a trigger on the target so that it lands inside
 * the first page's transaction and is committed with it, which is what a
 * concurrent session would achieve without needing one here.
 */
CREATE SERVER stub_pages FOREIGN DATA WRAPPER rdf_fdw
  OPTIONS (endpoint 'http://stub-endpoint/single-binding.xml', connect_timeout '5');
CREATE FOREIGN TABLE ft_pages (s rdfnode OPTIONS (variable '?s'))
  SERVER stub_pages OPTIONS (sparql 'SELECT ?s WHERE {?s ?p ?o}');
CREATE TABLE cloned_pages (s rdfnode);
CREATE ROLE stub_cloner NOSUPERUSER;

GRANT SELECT ON ft_pages TO stub_cloner;
GRANT USAGE ON FOREIGN SERVER stub_pages TO stub_cloner;
GRANT INSERT, SELECT ON cloned_pages TO stub_cloner;

CREATE FUNCTION revoke_mid_clone() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  EXECUTE 'REVOKE SELECT ON ft_pages FROM stub_cloner';
  RETURN NEW;
END $$;
CREATE TRIGGER revoke_mid_clone BEFORE INSERT ON cloned_pages
  FOR EACH ROW EXECUTE PROCEDURE revoke_mid_clone();

SET ROLE stub_cloner;
CALL rdf_fdw_clone_table(
  foreign_table => 'ft_pages',
  target_table  => 'cloned_pages',
  fetch_size    => 1,
  max_records   => 3,
  create_table  => false,
  verbose       => false);
RESET ROLE;

/* the first page, and nothing after it */
SELECT count(*) AS pages_cloned FROM cloned_pages;

DROP TRIGGER revoke_mid_clone ON cloned_pages;
DROP FUNCTION revoke_mid_clone();
DROP TABLE cloned_pages;
DROP SERVER stub_pages CASCADE;
DROP ROLE stub_cloner;

/* clean up */
DROP TABLE cloned_repeated;
DROP SERVER stub CASCADE;
DROP SERVER stub_repeated CASCADE;
DROP SERVER stub_split CASCADE;
DROP SERVER stub_describe CASCADE;
DROP SERVER stub_wide_limit CASCADE;
DROP SERVER stub_redirect CASCADE;
DROP SERVER stub_tokens CASCADE;
