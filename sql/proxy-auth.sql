CREATE SERVER fuseki
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint   'http://fuseki:3030/dt/sparql',
  update_url 'http://fuseki:3030/dt/update',
  http_proxy 'http://172.19.42.101:3128',
  connect_timeout '1');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER fuseki OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * WHERE {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .'
);

CREATE USER MAPPING FOR postgres
SERVER fuseki OPTIONS (
  user 'admin', password 'secret',
  proxy_user 'proxyuser', proxy_password 'proxypass');

/* Correct proxy settings */

INSERT INTO ft (subject, predicate, object)
VALUES  ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Westfälische Wilhelms-Universität Münster"@de');
SELECT * FROM ft;

SELECT *
FROM sparql.describe('fuseki', 'DESCRIBE <https://www.uni-muenster.de>');

CALL rdf_fdw_clone_table(
        create_table => true,
        foreign_table => 'public.ft',
        target_table  => 'public.t1'
     );
SELECT * FROM public.t1;

UPDATE ft SET object = '"University of Münster"@en'
WHERE subject = '<https://www.uni-muenster.de>';
SELECT * FROM ft;

DELETE FROM ft;
SELECT * FROM ft;

/*
 * A cached plan uses the user mapping current at execution, not the one
 * of the role that planned it.
 */
\set VERBOSITY terse
CREATE ROLE proxy_role;
GRANT USAGE ON FOREIGN SERVER fuseki TO proxy_role;
GRANT SELECT ON ft TO proxy_role;
CREATE USER MAPPING FOR proxy_role
SERVER fuseki OPTIONS (proxy_user 'proxyuser', proxy_password 'wrongpass');

PREPARE ft_count AS SELECT count(*) FROM ft;
EXECUTE ft_count;
SET ROLE proxy_role;
EXECUTE ft_count; -- must fail: proxy_role's mapping
RESET ROLE;
ALTER USER MAPPING FOR postgres SERVER fuseki OPTIONS (SET proxy_password 'wrongpass');
EXECUTE ft_count; -- must fail: altered mapping
ALTER USER MAPPING FOR postgres SERVER fuseki OPTIONS (SET proxy_password 'proxypass');
EXECUTE ft_count;
DEALLOCATE ft_count;

/*
 * A foreign table queried through a view uses the user mapping of the
 * view owner, as the permissions are checked as that role.
 */
CREATE VIEW ft_view AS SELECT * FROM ft;
GRANT SELECT, INSERT, UPDATE, DELETE ON ft_view TO proxy_role;
SET ROLE proxy_role;
INSERT INTO ft_view (subject, predicate, object)
VALUES ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Universität Münster"@de');
SELECT * FROM ft_view;
UPDATE ft_view SET object = '"University of Münster"@en'
WHERE subject = '<https://www.uni-muenster.de>';
SELECT * FROM ft_view;
DELETE FROM ft_view;
SELECT * FROM ft_view;
SELECT * FROM ft; -- must fail: proxy_role's mapping
RESET ROLE;
DROP VIEW ft_view;

DROP USER MAPPING FOR proxy_role SERVER fuseki;
REVOKE ALL ON ft FROM proxy_role;
REVOKE ALL ON FOREIGN SERVER fuseki FROM proxy_role;
DROP ROLE proxy_role;
\set VERBOSITY default

/* Wrong user - must fail */

ALTER USER MAPPING FOR postgres SERVER fuseki OPTIONS (SET proxy_user 'wronguser');
SELECT * FROM ft;
SELECT * FROM sparql.describe('fuseki', 'DESCRIBE <https://www.uni-muenster.de>');
CALL rdf_fdw_clone_table(
        foreign_table => 'public.ft',
        target_table  => 'public.t1'
     );

/* Wrong password - must fail */

ALTER USER MAPPING FOR postgres SERVER fuseki OPTIONS (SET proxy_user 'proxyuser', SET proxy_password 'wrongpass');
SELECT * FROM ft;
SELECT * FROM sparql.describe('fuseki', 'DESCRIBE <https://www.uni-muenster.de>');
CALL rdf_fdw_clone_table(
        foreign_table => 'public.ft',
        target_table  => 'public.t1'
     );

/* No password - must fail */
ALTER USER MAPPING FOR postgres SERVER fuseki OPTIONS (DROP proxy_password);
SELECT * FROM ft;
SELECT * FROM sparql.describe('fuseki', 'DESCRIBE <https://www.uni-muenster.de>');
CALL rdf_fdw_clone_table(
        foreign_table => 'public.ft',
        target_table  => 'public.t1'
     );

/*
 * HTTPS endpoint: the proxy refuses the CONNECT tunnel itself, so the 407 is
 * the proxy's answer, not the endpoint's. It must fail at once, as over HTTP,
 * rather than be retried as if no answer had come.
 */
CREATE SERVER fuseki_https
FOREIGN DATA WRAPPER rdf_fdw
OPTIONS (
  endpoint   'https://fuseki:3030/dt/sparql',
  http_proxy 'http://172.19.42.101:3128',
  connect_timeout '1');

CREATE USER MAPPING FOR postgres
SERVER fuseki_https OPTIONS (proxy_user 'proxyuser', proxy_password 'wrongpass');

CREATE FOREIGN TABLE ft_https (s rdfnode OPTIONS (variable '?s'))
SERVER fuseki_https OPTIONS (sparql 'SELECT ?s WHERE {?s ?p ?o}');

SELECT * FROM ft_https;

/* Cleanup */
DROP TABLE public.t1;
DROP SERVER fuseki CASCADE;
DROP SERVER fuseki_https CASCADE;