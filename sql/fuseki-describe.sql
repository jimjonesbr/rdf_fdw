\pset null '(null)'

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
  log_sparql 'true',
  sparql 'SELECT * WHERE {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .'
);

CREATE USER MAPPING FOR postgres
SERVER fuseki OPTIONS (user 'admin', password 'secret');

INSERT INTO ft (subject, predicate, object)
VALUES  ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Westfälische Wilhelms-Universität Münster"@de'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"University of Münster"@en'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Univerrrsity of Münsterrr"@en-US'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Univêrsity of Münsta"@en-GB'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#time>', '"18:18:42"^^<http://www.w3.org/2001/XMLSchema#time>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/established>', '"1780-04-16"^^<http://www.w3.org/2001/XMLSchema#date>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/modified>', '"2025-12-24T18:30:42"^^<http://www.w3.org/2001/XMLSchema#dateTime>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/ontology/wikiPageExtracted>', '"2025-12-24T13:00:42Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2003/01/geo/wgs84_pos#lat>', '"51.9636"^^<http://www.w3.org/2001/XMLSchema#float>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2003/01/geo/wgs84_pos#long>', '"7.6136"^^<http://www.w3.org/2001/XMLSchema#float>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/rector>', '"Johannes Wessels"'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/state>', '<http://dbpedia.org/resource/North_Rhine-Westphalia>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/city>', '<http://dbpedia.org/resource/Münster>'),
        ('<http://dbpedia.org/resource/Münster>', '<http://dbpedia.org/property/name>', '"Münster"@de'),
        ('<http://dbpedia.org/resource/North_Rhine-Westphalia>', '<http://dbpedia.org/property/name>', '"Nordrhein-Westfalen"@de'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"Hello 👋 PostgreSQL 🐘"@en'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"unknown literal type"^^<http://www.w3.org/2001/XMLSchema#UNKNOWN>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"explicit string literal"^^<http://www.w3.org/2001/XMLSchema#string>'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '""'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '". <= pontos => ."@pt'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"\n <= salto de línea => \n"@es'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"\" <= double-quotes => \""@en'),
        ('<https://www.uni-muenster.de>', '<http://www.w3.org/2000/01/rdf-schema#comment>', '"\t <= Tabulatorzeichen => \t"@de'),        
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/administrativeStaff>', '"1924"^^<http://www.w3.org/2001/XMLSchema#short>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/students>', '"49098"^^<http://www.w3.org/2001/XMLSchema#int>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/academicStaff>', '"4956"^^<http://www.w3.org/2001/XMLSchema#int>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/budget>', '"803600000"^^<http://www.w3.org/2001/XMLSchema#long>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/tuition>', '"1500.00"^^<http://www.w3.org/2001/XMLSchema#double>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/veryLargeNumber>', '"9999999999999999999"^^<http://www.w3.org/2001/XMLSchema#decimal>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/verySmallNumber>', '"0.000000000000001"^^<http://www.w3.org/2001/XMLSchema#decimal>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/ontology/restingDate>', '"2024-02-29"^^<http://www.w3.org/2001/XMLSchema#date>'),
        ('<https://www.uni-muenster.de>', '<http://dbpedia.org/ontology/internationally>', '"true"^^<http://www.w3.org/2001/XMLSchema#boolean>');

/* IRI description */
SELECT subject, predicate, object
FROM sparql.describe('fuseki', 'DESCRIBE <https://www.uni-muenster.de>')
ORDER BY object::text COLLATE "C";

/* graph pattern description */
SELECT subject, predicate, object
FROM sparql.describe('fuseki','
  PREFIX dbp: <http://dbpedia.org/property/>
  DESCRIBE ?s
  WHERE { 
    ?s dbp:name ?o .
  }')
WHERE subject = '<https://www.uni-muenster.de>'
ORDER BY object::text COLLATE "C";

/* IN clause to filter results */
SELECT subject, predicate, object
FROM sparql.describe('fuseki', 'DESCRIBE <https://www.uni-muenster.de>')
WHERE predicate IN ('<http://dbpedia.org/property/name>','<http://schema.org/dateModified>')
ORDER BY object::text COLLATE "C";

/* using named prefixes and base URI */
SELECT subject, predicate, object
FROM sparql.describe(
    query =>'describe <http://dbpedia.org/resource/Münster>',
    server => 'fuseki', 
    base_uri => 'http://test.base.uri/')
WHERE predicate = '<http://dbpedia.org/property/name>'
ORDER BY object::text COLLATE "C";

/* empty server */
SELECT * FROM sparql.describe('', 'DESCRIBE <https://www.uni-muenster.de>');

/* empty DESCRIBE pattern */
SELECT * FROM sparql.describe('fuseki', '');

/* empty SERVER and DESCRIBE pattern */
SELECT * FROM sparql.describe('', '');

/* NULL DESCRIBE pattern */
SELECT * FROM sparql.describe('fuseki', NULL);

/* NULL SERVER */
SELECT * FROM sparql.describe(NULL, 'DESCRIBE <https://www.uni-muenster.de>');

/* NULL SERVER and DESCRIBE pattern */
SELECT * FROM sparql.describe(NULL, NULL);

/* invalid SERVER */
SELECT * FROM sparql.describe('invalid', 'DESCRIBE <https://www.uni-muenster.de>');
SELECT * FROM sparql.describe('    ', 'DESCRIBE <https://www.uni-muenster.de>');

/* invalid DESCRIBE pattern */
SELECT * FROM sparql.describe('fuseki', 'invalid');
SELECT * FROM sparql.describe('fuseki', '   ');
SELECT * FROM sparql.describe('fuseki', 'DESCRIBE https://www.uni-muenster.de'); -- missing < >

/* DESCRIBE pattern with a blank node */
SELECT * FROM sparql.describe('fuseki', '_:bnode1');
SELECT * FROM sparql.describe('fuseki', 'DESCRIBE _:bnode1');

/* malformed entity IRI */
SELECT * FROM sparql.describe('fuseki', 'DESCRIBE <htt://i.am.malformed>');

/* SELECT query */
SELECT * FROM sparql.describe('fuseki', 'SELECT ?s ?p ?o WHERE {?s ?p ?o}');

/* cleanup */
DELETE FROM ft;
DROP SERVER fuseki CASCADE;