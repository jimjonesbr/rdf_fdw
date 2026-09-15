\set VERBOSITY terse

/*
 * rdf_fdw_describe() and rdf_fdw_clone_table() take the *name* of an object
 * rather than the object itself, so the executor never builds a range table
 * entry for it and none of the permission checks a plain query would get ever
 * run. Both entry points therefore have to check for themselves.
 *
 * Nothing here contacts the endpoint: the checks happen before the request is
 * built, which is the point -- the server option may name any host at all.
 */

CREATE SERVER priv_srv
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (endpoint 'http://127.0.0.1:9/sparql', connect_timeout '1');

CREATE FOREIGN TABLE priv_ft (
  s rdfnode OPTIONS (variable '?s')
) SERVER priv_srv OPTIONS (sparql 'SELECT ?s WHERE {?s ?p ?o}');

CREATE TABLE priv_stolen (s rdfnode);

CREATE ROLE priv_role LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;

SET ROLE priv_role;

/* the SPARQL function API is reachable without any grant of its own:
 * the extension grants USAGE on its schema to PUBLIC */
SELECT sparql.ucase('"hi"');

/* no privileges at all: selecting from the table is refused by PostgreSQL */
SELECT * FROM priv_ft;

/* EXECUTE on the procedure is granted to PUBLIC, since the extension script
 * issues no REVOKE, so without a check of its own rdf_fdw_clone_table() would
 * read straight through a foreign table the caller was explicitly denied */
CALL rdf_fdw_clone_table(
  foreign_table => 'priv_ft',
  target_table  => 'priv_stolen',
  create_table  => false,
  verbose       => false);

/* rdf_fdw_describe() has the same gap for its SERVER argument, and nothing
 * shields it: schema "sparql" is reachable by PUBLIC, so the check has to
 * be its own. */
SELECT * FROM sparql.describe('priv_srv', 'DESCRIBE <http://example.org/x>');

RESET ROLE;

/* SELECT on the table alone is not enough: reaching the endpoint also uses
 * whatever credentials the DBA put in the server's user mapping, so USAGE on
 * the server is required as well */
GRANT SELECT ON priv_ft TO priv_role;
SET ROLE priv_role;

CALL rdf_fdw_clone_table(
  foreign_table => 'priv_ft',
  target_table  => 'priv_stolen',
  create_table  => false,
  verbose       => false);

RESET ROLE;

/* with both privileges held the checks pass and the call proceeds to the
 * endpoint, which is what the unreachable address below then reports */
GRANT USAGE ON FOREIGN SERVER priv_srv TO priv_role;
SET ROLE priv_role;

SELECT * FROM sparql.describe('priv_srv', 'DESCRIBE <http://example.org/x>');

RESET ROLE;

/* clean up */
DROP TABLE priv_stolen;
DROP SERVER priv_srv CASCADE;
DROP ROLE priv_role;
