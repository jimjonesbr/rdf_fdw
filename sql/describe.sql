--------------------------------- Wikidata (Blazegraph) ---------------------------------
CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://query.wikidata.org/sparql',
        connect_retry '0');

-- IRI description
SELECT subject, predicate, object
FROM rdf_fdw_describe('wikidata', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>')
ORDER BY object COLLATE "C";

-- graph pattern description
SELECT subject, predicate, object
FROM rdf_fdw_describe('wikidata','
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
ORDER BY object COLLATE "C";

SELECT subject, predicate, object
FROM rdf_fdw_describe('wikidata', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>', false)
WHERE predicate IN ('<http://www.w3.org/2000/01/rdf-schema#label>','<http://schema.org/dateModified>')
ORDER BY object COLLATE "C";

SELECT subject, predicate, object
FROM rdf_fdw_describe('wikidata', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>', true)
WHERE predicate IN ('<http://www.w3.org/2000/01/rdf-schema#label>','<http://schema.org/dateModified>')
ORDER BY object COLLATE "C";

SELECT subject, predicate, object
FROM rdf_fdw_describe(
    query =>'describe wd:Q471896',
    server => 'wikidata', 
    base_uri => 'http://test.base.uri/',
    raw_literal => false)
WHERE predicate = '<http://www.w3.org/2000/01/rdf-schema#label>'
ORDER BY object COLLATE "C";

-- empty server
SELECT * FROM rdf_fdw_describe('', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>');
-- empty DESCRIBE pattern
SELECT * FROM rdf_fdw_describe('wikidata', '');
-- empty SERVER and DESCRIBE pattern
SELECT * FROM rdf_fdw_describe('', '');
-- NULL DESCRIBE pattern
SELECT * FROM rdf_fdw_describe('wikidata', NULL);
-- NULL SERVER
SELECT * FROM rdf_fdw_describe(NULL, 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>');
-- NULL SERVER and DESCRIBE pattern
SELECT * FROM rdf_fdw_describe(NULL, NULL);
-- invalid SERVER
SELECT * FROM rdf_fdw_describe('invalid', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>');
SELECT * FROM rdf_fdw_describe('    ', 'DESCRIBE <http://www.wikidata.org/entity/Q61308849>');
-- invalid DESCRIBE pattern
SELECT * FROM rdf_fdw_describe('wikidata', 'invalid');
SELECT * FROM rdf_fdw_describe('wikidata', '   ');
SELECT * FROM rdf_fdw_describe('wikidata', 'DESCRIBE http://www.wikidata.org/entity/Q61308849'); -- missing < >
-- DESCRIBE pattern with a blank node
SELECT * FROM rdf_fdw_describe('wikidata', '_:bnode1');
SELECT * FROM rdf_fdw_describe('wikidata', 'DESCRIBE _:bnode1');
-- malformed entity IRI
SELECT * FROM rdf_fdw_describe('wikidata', 'DESCRIBE <htt://i.am.malformed>');
-- SELECT query
SELECT * FROM rdf_fdw_describe('wikidata', 'SELECT ?s ?p ?o WHERE {?s ?p ?o}');

DROP SERVER wikidata;

----------------------------------- Virtuoso (DBpedia) -----------------------------------

CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

-- IRI description
SELECT subject, predicate, object 
FROM rdf_fdw_describe('dbpedia','dEsCrIBe <http://dbpedia.org/resource/Alien_Blood>') 
ORDER BY subject, object COLLATE "C";

DROP SERVER dbpedia;

------------------------------- Getty Thesaurus (GraphDB) -------------------------------
CREATE SERVER getty
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
    endpoint 'http://vocab.getty.edu/sparql',
    base_uri 'http://rdf_fdw.regress.tests/'
);

-- IRI description
SELECT 
  CASE WHEN subject LIKE 'r%' THEN 'bnode' ELSE subject END AS subject, 
  predicate,
  CASE WHEN object LIKE 'r%' THEN 'bnode' ELSE object END AS object
FROM rdf_fdw_describe('getty','DESCRIBE <http://vocab.getty.edu/ulan/500033638>')
ORDER BY object COLLATE "C";

DROP SERVER getty;
