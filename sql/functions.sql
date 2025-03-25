\pset null NULL

SELECT strstarts('foobar','foo');
SELECT strstarts('foobar','xyz');
SELECT strstarts('foobar','');
SELECT strstarts('','xyz');
SELECT strstarts('foobar',NULL);
SELECT strstarts(NULL,'xyz');
SELECT strstarts(NULL, NULL);

SELECT strends('foobar','bar');
SELECT strends('foobar','xyz');
SELECT strends('foobar','');
SELECT strends('','xyz');
SELECT strends('foobar',NULL);
SELECT strends(NULL,'xyz');
SELECT strends(NULL, NULL);

SELECT strbefore('abc','b');
SELECT strbefore('abc','xyz');
SELECT strbefore('abc', NULL);
SELECT strbefore(NULL, 'xyz');
SELECT strbefore(NULL, NULL);
SELECT strbefore('abc', '');
SELECT strbefore('', 'xyz');
SELECT strbefore('', '');

SELECT strafter('abc','b');
SELECT strafter('abc','xyz');
SELECT strafter('abc', NULL);
SELECT strafter(NULL, 'xyz');
SELECT strafter(NULL, NULL);
SELECT strafter('abc', '');
SELECT strafter('', 'xyz');
SELECT strafter('', '');


CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://query.wikidata.org/sparql');

CREATE FOREIGN TABLE ft (
  o text    OPTIONS (variable '?o', language 'de')
)
SERVER wikidata OPTIONS (
  log_sparql 'true',
  sparql 'SELECT * WHERE {
    wd:Q192490 rdfs:label ?o
  }
'); 

SELECT DISTINCT o FROM ft
WHERE
  strbefore(o, 'SQL') = 'Postgre' AND
  strbefore(o, '') = '' AND
  strbefore('', '') = '' AND
  strbefore(o, 'SQL') <> 'My' AND

  strafter(o, 'Postgre') = 'SQL' AND
  strafter(o, '') = 'PostgreSQL' AND
  strafter('', '') = '' AND 
  strafter(o, 'Postgre') <> 's' AND
  
  strends(o, 'SQL') AND
  strends(o, '') AND

  strstarts(o, 'Postgre') AND
  strstarts(o, '');

DROP SERVER wikidata CASCADE;