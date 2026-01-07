/* DEBUG1 */

SET client_min_messages to DEBUG1;

CREATE SERVER fuseki
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint   'http://fuseki:3030/dt/sparql',
  update_url 'http://fuseki:3030/dt/update');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER fuseki OPTIONS (
  sparql 'SELECT * WHERE {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .'
);

CREATE USER MAPPING FOR postgres
SERVER fuseki OPTIONS (user 'admin', password 'secret');

INSERT INTO ft (subject, predicate, object)
VALUES ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Westfälische Wilhelms-Universität Münster"@de'),
       ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/founded>', '"1780-10-02"^^<http://www.w3.org/2001/XMLSchema#date>');

SELECT DISTINCT subject, predicate, object FROM ft
WHERE
  subject = sparql.iri('https://www.uni-muenster.de') AND
  object BETWEEN '1780-01-01'::date AND sparql.strdt('1780-12-31', '<http://www.w3.org/2001/XMLSchema#date>')
ORDER BY object ASC, predicate DESC
FETCH FIRST 2 ROWS ONLY;

UPDATE ft
SET object = '"University of Münster"@en'
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://dbpedia.org/property/name>';

DELETE FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

DROP SERVER fuseki CASCADE;

/* DEBUG2 */

SET client_min_messages to DEBUG2;

CREATE SERVER fuseki
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint   'http://fuseki:3030/dt/sparql',
  update_url 'http://fuseki:3030/dt/update');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER fuseki OPTIONS (
  sparql 'SELECT * WHERE {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .'
);

CREATE USER MAPPING FOR postgres
SERVER fuseki OPTIONS (user 'admin', password 'secret');

INSERT INTO ft (subject, predicate, object)
VALUES ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Westfälische Wilhelms-Universität Münster"@de'),
       ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/founded>', '"1780-10-02"^^<http://www.w3.org/2001/XMLSchema#date>');

SELECT DISTINCT subject, predicate, object FROM ft
WHERE
  subject = sparql.iri('https://www.uni-muenster.de') AND
  object BETWEEN '1780-01-01'::date AND sparql.strdt('1780-12-31', '<http://www.w3.org/2001/XMLSchema#date>')
ORDER BY object ASC, predicate DESC
FETCH FIRST 2 ROWS ONLY;

UPDATE ft
SET object = '"University of Münster"@en'
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://dbpedia.org/property/name>';

DELETE FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

DROP SERVER fuseki CASCADE;

/* DEBUG3 */

SET client_min_messages to DEBUG3;

CREATE SERVER fuseki
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint   'http://fuseki:3030/dt/sparql',
  update_url 'http://fuseki:3030/dt/update');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER fuseki OPTIONS (
  sparql 'SELECT * WHERE {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .'
);

CREATE USER MAPPING FOR postgres
SERVER fuseki OPTIONS (user 'admin', password 'secret');

INSERT INTO ft (subject, predicate, object)
VALUES ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Westfälische Wilhelms-Universität Münster"@de'),
       ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/founded>', '"1780-10-02"^^<http://www.w3.org/2001/XMLSchema#date>');

SELECT DISTINCT subject, predicate, object FROM ft
WHERE
  subject = sparql.iri('https://www.uni-muenster.de') AND
  object BETWEEN '1780-01-01'::date AND sparql.strdt('1780-12-31', '<http://www.w3.org/2001/XMLSchema#date>')
ORDER BY object ASC, predicate DESC
FETCH FIRST 2 ROWS ONLY;

UPDATE ft
SET object = '"University of Münster"@en'
WHERE subject = '<https://www.uni-muenster.de>'
  AND predicate = '<http://dbpedia.org/property/name>';

DELETE FROM ft
WHERE subject = '<https://www.uni-muenster.de>';

DROP SERVER fuseki CASCADE;
