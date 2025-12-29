\pset null '(null)'

CREATE SERVER graphdb
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint   'http://graphdb:7200/repositories/test',
  update_url 'http://graphdb:7200/repositories/test/statements',
  batch_size '1000');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER graphdb OPTIONS (
  log_sparql 'false',
  sparql 
    $$
     SELECT * 
     WHERE {?s ?p ?o .}
    $$,
  sparql_update_pattern '?s ?p ?o .'
);

CREATE USER MAPPING FOR postgres
SERVER graphdb OPTIONS (user 'admin', password 'secret');

/* inserting a large literal (one million characters) */
INSERT INTO ft (subject, predicate, object)
VALUES  ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', repeat('x', 1000000)::rdfnode);

SELECT subject, predicate, sparql.strlen(object) 
FROM ft
WHERE
  subject = '<https://www.uni-muenster.de>' AND
  predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';

/* updating the large literal (one million characters) */
UPDATE ft SET
  object = repeat('y', 1000000)::rdfnode
WHERE
  subject = '<https://www.uni-muenster.de>' AND
  predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';

SELECT subject, predicate, sparql.strlen(object) 
FROM ft 
WHERE 
  subject = '<https://www.uni-muenster.de>' AND
  predicate = '<http://www.w3.org/2000/01/rdf-schema#label>';

/* deleting triple with large literal */
DELETE FROM ft;

/* inserting a one million triples */
INSERT INTO ft (subject, predicate, object)
SELECT '<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#label>', i::rdfnode 
FROM generate_series(1,1000000) AS g(i);

SELECT * FROM ft
LIMIT 5;

/* selecting one million triples from the foreign table */
CREATE UNLOGGED TABLE temp_ft AS SELECT * FROM ft;
SELECT count(*) FROM temp_ft;
SELECT * FROM temp_ft
WHERE 
  subject = '<https://www.uni-muenster.de>'::rdfnode AND
  object BETWEEN 500000::rdfnode AND 500010::rdfnode;
DROP TABLE temp_ft;

/* cloning one million triples from the foreign table */
CALL
    rdf_fdw_clone_table(
        foreign_table => 'public.ft',
        target_table  => 'public.ft_clone',
        fetch_size => 100000,
        create_table => true,
        verbose => true
    );
DROP TABLE ft_clone;

/* describing subject with one million triples */
CREATE UNLOGGED TABLE temp_describe AS
SELECT subject, predicate, object
FROM sparql.describe('graphdb', 'DESCRIBE <https://www.uni-muenster.de>');
SELECT count(*) FROM temp_describe;
SELECT * FROM temp_describe
WHERE 
  subject = '<https://www.uni-muenster.de>'::rdfnode AND
  object BETWEEN 500000::rdfnode AND 500010::rdfnode;
DROP TABLE temp_describe;

/* deleting a million triples */
DELETE FROM ft;

SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

DROP SERVER graphdb CASCADE;
