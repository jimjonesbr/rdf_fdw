\set VERBOSITY terse
--------------------------------- Wikidata (Blazegraph) ---------------------------------
CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://query.wikidata.org/sparql',
        connect_retry '0');

-- IRI description
SELECT subject, predicate, object
FROM sparql.describe('wikidata', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>')
ORDER BY object::text COLLATE "C";

-- graph pattern description
SELECT subject, predicate, object
FROM sparql.describe('wikidata','
  PREFIX wdt: <http://www.wikidata.org/prop/direct/>
  PREFIX wd:  <http://www.wikidata.org/entity/>
  DESCRIBE ?s
  WHERE { 
    ?s wdt:P734 wd:Q59853; 
	   wdt:P19 wd:Q84 ;
	   schema:description ?d
    FILTER(STR(?d) = "British astronomer")   
  }')
WHERE 
  predicate = '<http://www.w3.org/2000/01/rdf-schema#label>' AND
  object = '"Harold Spencer Jones"@en'
ORDER BY object::text COLLATE "C";

SELECT subject, predicate, object
FROM sparql.describe('wikidata', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>', false)
WHERE predicate IN ('<http://www.w3.org/2000/01/rdf-schema#label>','<http://schema.org/dateModified>')
ORDER BY object::text COLLATE "C";

SELECT subject, predicate, object
FROM sparql.describe('wikidata', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>', true)
WHERE predicate IN ('<http://www.w3.org/2000/01/rdf-schema#label>','<http://schema.org/dateModified>')
ORDER BY object::text COLLATE "C";

SELECT subject, predicate, object
FROM sparql.describe(
    query =>'describe wd:Q471896',
    server => 'wikidata', 
    base_uri => 'http://test.base.uri/',
    raw_literal => false)
WHERE predicate = '<http://www.w3.org/2000/01/rdf-schema#label>'
ORDER BY object::text COLLATE "C";

-- empty server
SELECT * FROM sparql.describe('', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>');
-- empty DESCRIBE pattern
SELECT * FROM sparql.describe('wikidata', '');
-- empty SERVER and DESCRIBE pattern
SELECT * FROM sparql.describe('', '');
-- NULL DESCRIBE pattern
SELECT * FROM sparql.describe('wikidata', NULL);
-- NULL SERVER
SELECT * FROM sparql.describe(NULL, 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>');
-- NULL SERVER and DESCRIBE pattern
SELECT * FROM sparql.describe(NULL, NULL);
-- invalid SERVER
SELECT * FROM sparql.describe('invalid', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>');
SELECT * FROM sparql.describe('    ', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>');
-- invalid DESCRIBE pattern
SELECT * FROM sparql.describe('wikidata', 'invalid');
SELECT * FROM sparql.describe('wikidata', '   ');
SELECT * FROM sparql.describe('wikidata', 'DESCRIBE http://www.wikidata.org/entity/Q61308849'); -- missing < >
-- DESCRIBE pattern with a blank node
SELECT * FROM sparql.describe('wikidata', '_:bnode1');
SELECT * FROM sparql.describe('wikidata', 'DESCRIBE _:bnode1');
-- malformed entity IRI
SELECT * FROM sparql.describe('wikidata', 'DESCRIBE <htt://i.am.malformed>');
-- SELECT query
SELECT * FROM sparql.describe('wikidata', 'SELECT ?s ?p ?o WHERE {?s ?p ?o}');

DROP SERVER wikidata;

----------------------------------- Virtuoso (DBpedia) -----------------------------------

CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

-- IRI description
SELECT subject, predicate, object 
FROM sparql.describe('dbpedia','dEsCrIBe <http://dbpedia.org/resource/Alien_Blood>') 
ORDER BY subject::text, object::text COLLATE "C";

DROP SERVER dbpedia;