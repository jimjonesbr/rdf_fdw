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

/* Cleanup */
DROP TABLE public.t1;
DROP SERVER fuseki CASCADE;