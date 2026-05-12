\pset null '(null)'

DROP SERVER IF EXISTS qlever CASCADE;

CREATE SERVER qlever
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint   'http://qlever:7001/sparql',
  update_url 'http://qlever:7001/update');

CREATE FOREIGN TABLE ft (
  subject   rdfnode OPTIONS (variable '?s'),
  predicate rdfnode OPTIONS (variable '?p'),
  object    rdfnode OPTIONS (variable '?o') 
)
SERVER qlever OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * WHERE {?s ?p ?o}',
  sparql_update_pattern '?s ?p ?o .'
);


INSERT INTO ft (subject, predicate, object)
VALUES  ('<https://www.uni-muenster.de>', '<http://dbpedia.org/property/name>', '"Westfälische Wilhelms-Universität Münster"@de');


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


SELECT * FROM ft
WHERE subject = '<https://www.uni-muenster.de>'
ORDER BY predicate;

