CREATE EXTENSION IF NOT EXISTS rdf_fdw;

CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://dbpedia.org/sparql',
  format 'application/sparql-results+xml',
  enable_pushdown 'true'
);

/* ################### DBpedia Films ################### */

CREATE FOREIGN TABLE film (
  film_id text    OPTIONS (variable '?film'),
  name text       OPTIONS (variable '?name', language 'en'),
  released date   OPTIONS (variable '?released', literaltype 'xsd:date'),
  runtime int     OPTIONS (variable '?runtime'),
  abstract text   OPTIONS (variable '?abstract')
)
SERVER dbpedia OPTIONS (
  log_sparql 'tRuE',
  sparql '
    PREFIX dbr: <http://dbpedia.org/resource/>
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>

    SELECT DISTINCT ?film ?name ?released ?runtime ?abstract
    WHERE
    {
      ?film a dbo:Film ;
            rdfs:comment ?abstract ;
            dbp:name ?name ;
            dbp:released ?released ;
            dbp:runtime ?runtime .
      FILTER (LANG ( ?abstract ) = "en")
      FILTER (datatype(?released) = xsd:date)
      FILTER (datatype(?runtime) = xsd:integer)
     }
'); 

-- GROUP BY columns by their aliases and index in the
-- SELECT clause
SELECT film_id AS id, name, runtime, released AS rel
FROM film
ORDER BY rel DESC, 1 ASC
LIMIT 5;

-- FETCH FIRST x ROWS ONLY is not pushed down, as the
-- query contains aggregates
SELECT count(runtime),avg(runtime)
FROM film
ORDER BY count(runtime),avg(runtime)
FETCH FIRST 5 ROWS ONLY;

-- OFFSET x ROWS + FETCH FIRST x ROWS ONLY are pushed down. 
-- ORDER BY is pushed down.
SELECT name, released
FROM film
ORDER BY released DESC, name ASC
OFFSET 5 ROWS
FETCH FIRST 10 ROW ONLY; 

-- OFFSET x AND LIMIT x are pushed down
-- ORDER BY is pushed down.
SELECT name, released
FROM film
ORDER BY released DESC, name ASC
OFFSET 5 
LIMIT 10;

-- LIMIT + OFFSET won't be pushed down, as this is not
-- safe to do so with DISTINCT.
SELECT DISTINCT name, released
FROM film
ORDER BY released DESC, name ASC
OFFSET 5 
LIMIT 10;

-- LIMIT + OFFSET won't be pushed down, as this is not
-- safe to do so with DISTINCT ON expressions.
SELECT DISTINCT ON (released) name, released
FROM film
ORDER BY released DESC, name ASC
OFFSET 5 
LIMIT 10;


-- All three conditions in the WHERE clause are pushed down
-- as SPARQL FILTER clauses. The ORDER BY name isn't pushed 
-- down because of the 'name = 'condition. The FETCH FIRST 3 
-- ROWS ONLY is pushed down.
SELECT name, released, runtime
FROM film
WHERE 
  name = 'The Life of Adam Lindsay Gordon' AND 
  runtime < 10 AND
  released < '1930-03-25'
ORDER BY name
FETCH FIRST 3 ROWS ONLY;


/*
  All three conditions in the WHERE clause are pushed down.
  The lower() function call will be translated to LCASE in a
  SPARQL FILTER expression.
*/ 

SELECT name, released, runtime
FROM film
WHERE 
  lower(name) = 'the life of adam lindsay gordon' AND 
  runtime < 10 AND
  released < '1930-03-25'
ORDER BY released
FETCH FIRST 3 ROWS ONLY;

/*
  All three conditions in the WHERE clause are pushed down.
  The upper() function call will be translated to UCASE in a
  SPARQL FILTER expression.
*/ 

SELECT name, released, runtime
FROM film
WHERE 
  upper(name) = 'THE LIFE OF ADAM LINDSAY GORDON' AND 
  runtime < 10 AND
  released < '1930-03-25'
ORDER BY released
FETCH FIRST 3 ROWS ONLY;

/*
 IS NOT NULL isn't supported in SPARQL.
 OR conditions won't be pushed down.
*/
SELECT name, released, runtime
FROM film
WHERE   
  name IS NOT NULL AND 
  (runtime < 10 OR
  released < '1930-03-25')
ORDER BY released ASC, name DESC
FETCH FIRST 3 ROWS ONLY;


/*
  Operator <> will be translated to !=
*/
SELECT name, released, runtime
FROM film
WHERE   
  name = 'The Life of Adam Lindsay Gordon' AND 
  released <> '1930-03-25';


/* ################### DBpedia Politicians ################### */

CREATE FOREIGN TABLE politicians (
  uri text        OPTIONS (variable '?person', nodetype 'iri'),
  name text       OPTIONS (variable '?personname', nodetype 'literal', literaltype 'xsd:string'),
  name_upper text OPTIONS (variable '?name_ucase', nodetype 'literal', expression 'UCASE(?personname)'),
  name_len int    OPTIONS (variable '?name_len', nodetype 'literal', expression 'STRLEN(?personname)'),
  birthdate date  OPTIONS (variable '?birthdate', nodetype 'literal', literaltype 'xsd:date'),
  party text      OPTIONS (variable '?partyname', nodetype 'literal', literaltype 'xsd:string'),
  wikiid int      OPTIONS (variable '?pageid', nodetype 'literal', literaltype 'xsd:nonNegativeInteger'),
  country text    OPTIONS (variable '?country', nodetype 'literal', language 'en')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>

    SELECT *
    WHERE {
      ?person 
          a dbo:Politician;
          dbo:birthDate ?birthdate;
          dbp:name ?personname;
          dbo:party ?party ;   
          dbo:wikiPageID ?pageid .
        ?party 
          dbp:country ?country;
          rdfs:label ?partyname .
        FILTER NOT EXISTS {?person dbo:deathDate ?died}
        FILTER(LANG(?partyname) = "de")
      } 
');

/*
 * DISTINCT and WHERE clause will be pushed down.
 * LIMIT won't be pushed down, as the SQL contains ORDER BY
 */
SELECT DISTINCT 
  name, 
  birthdate,  
  party, 
  country
FROM politicians
WHERE country = 'Germany'
ORDER BY birthdate DESC, party ASC
LIMIT 10;


/*
 * DISTINCT ON won't be pushed - SPARQL does not support it.
 * WHERE clause will be pushed down.
 * LIMIT won't be pushed down, as the SQL contains ORDER BY
 */
SELECT DISTINCT ON (birthdate)
  name, 
  birthdate
FROM politicians
WHERE country = 'Germany'
ORDER BY birthdate
LIMIT 3;

/*
 * SELECT does not contain the column 'country' but it is
 * used in the WHERE clause. We automatically add it to the 
 * SPARQL SELECT clause, so that it can be also filtered locally
*/
SELECT name, birthdate, party
FROM politicians
WHERE country = 'Germany' AND birthdate > '1995-12-31'
ORDER BY birthdate DESC, party ASC
FETCH FIRST 5 ROWS ONLY;

/* 
 * SELECT does not contain all columns used in the 
 * WHERE clause (column 'name') and this column is 
 * used in a function call "WHERE lower(country)". 
 * All available columns / variables will be used in
 * the SPARQL SELECT.
 */

SELECT name, birthdate, party
FROM politicians
WHERE lower(country) = 'germany' AND 
      birthdate > '1995-12-31'
ORDER BY birthdate DESC, party ASC
FETCH FIRST 5 ROWS ONLY;


/*
 * "WHERE country IN " is going to be pushed down in a 
 * FILTER expression.
 */
SELECT name, birthdate, party
FROM politicians
WHERE country IN ('Germany','France','Portugal')
ORDER BY birthdate DESC, party ASC
FETCH FIRST 5 ROWS ONLY;

/*
 * "WHERE country NOT IN " is going to be pushed down in a 
 * FILTER expression.
 */
SELECT name, birthdate, party, country
FROM politicians
WHERE country NOT IN ('Germany','France','Portugal')
ORDER BY birthdate DESC, party ASC
FETCH FIRST 5 ROWS ONLY;

/*
 * "= ANY(ARRAY[])" is going to be pushed down in a 
 * FILTER expression.
 */
SELECT name, birthdate, party
FROM politicians
WHERE country = ANY(ARRAY['Germany','France','Portugal'])
ORDER BY birthdate DESC, party ASC
FETCH FIRST 5 ROWS ONLY;

/*
 * "<> ANY(ARRAY[])" is not going to be pushed down!
 */
SELECT name, birthdate, party, country
FROM politicians
WHERE country <> ANY(ARRAY['Germany','France','Portugal'])
ORDER BY birthdate DESC, party ASC
FETCH FIRST 5 ROWS ONLY;


/*
 * "~~* ANY(ARRAY[])" is not going to be pushed down!
 */
SELECT name, birthdate, party, country
FROM politicians
WHERE country ~~* ANY(ARRAY['%UsTr%','%TugA%'])
ORDER BY birthdate DESC, party ASC
FETCH FIRST 5 ROWS ONLY;

/* 
 * "~~ ANY(ARRAY[])" is not going to be pushed down! 
 */

SELECT name, birthdate, party, country
FROM politicians
WHERE country ~~ ANY(ARRAY['__land%','%GERMAN%'])
ORDER BY birthdate DESC, party ASC
FETCH FIRST 5 ROWS ONLY;

/* 
 * "NOT country ~~* ANY(ARRAY[])" is not going to be pushed down! 
 */
SELECT name, birthdate, party, country
FROM politicians
WHERE NOT country ~~* ANY(ARRAY['%UnItEd%','%land%'])
ORDER BY birthdate DESC, party ASC
FETCH FIRST 5 ROWS ONLY;

/*
 * Pushdown test for UPPER and LOWER 
 */
SELECT * 
FROM politicians 
WHERE 
  upper(name) = 'WILL' || ' BOND' AND 
  'will bond' = lower(name) AND
  lower(name_upper) = lower(name)
FETCH FIRST ROW ONLY;

/*
 * Pushdown test for LENGTH
 */
SELECT * FROM politicians 
WHERE 
  47035308 = wikiid AND 
  length(name) = 9  AND 
  length(name) < (9+1)  AND 
  length(name_upper) < (40+2)  AND 
  13 <= LENGTH(country) AND
  5 < LENGTH(name_upper) AND
  LENGTH(name) <= LENGTH(country) 
FETCH FIRST ROW ONLY;

/*
 * Pushdown test for STARTS_WITH
 */
SELECT * FROM politicians 
WHERE 
  47035308 = wikiid AND 
  starts_with(party,'Demokratisch') AND
  starts_with(name_upper,'WILL')
FETCH FIRST ROW ONLY;

/*
 * Pushdown test for ABS
 */
SELECT * FROM politicians 
WHERE 
  47035308 = wikiid AND 
  abs(wikiid) <> 42.73 AND
  abs(wikiid) <> abs(-300) AND  
  wikiid = abs(-47035308) AND
  wikiid > abs(name_len)
FETCH FIRST ROW ONLY;

/*
 * Pushdown test for CEIL
 */
SELECT * FROM politicians 
WHERE
  47035308 = wikiid AND  
  CEIL(wikiid) = ceil(47035307.1) AND
  ceil(name_len) <> ceil(wikiid)
FETCH FIRST ROW ONLY;

/*
 * Pushdown test for ROUND
 */
SELECT * FROM politicians 
WHERE
  47035308 = wikiid AND 
  round(wikiid) = ROUND(47035308.4) AND
  round(name_len) <> round(wikiid)
FETCH FIRST ROW ONLY;

/*
 * Pushdown test for FLOOR
 */
SELECT * FROM politicians 
WHERE
  47035308 = wikiid AND 
  Floor(wikiid) < 47035308.99999  AND
  floor(name_len) <> floor(wikiid)
FETCH FIRST ROW ONLY;

/*
 * Pushdown test for SUBSTRING
 */
SELECT * FROM politicians 
WHERE
  47035308 = wikiid AND 
  SUBstring(name,1,4) = 'Will' AND
  'Bond' = subSTRING(name, 6,4) AND
  lower(SUBstring(name,1,4)) = 'will' AND
  SUBSTRING(lower(name_upper),1,4) = 'will'
FETCH FIRST ROW ONLY;

/* ################### SPARQL  Aggregators ################### */

CREATE FOREIGN TABLE party_members (
  country text  OPTIONS (variable '?country'),
  party text    OPTIONS (variable '?partyname'),
  nmembers int  OPTIONS (variable '?qt')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>
    
    SELECT ?country ?partyname COUNT(?person) AS ?qt 
    WHERE
    {
      ?person 
        a dbo:Politician ;
          dbo:party ?party .
        ?party 
          dbp:country ?country ;
          dbp:name ?partyname .
      FILTER NOT EXISTS {?person dbo:deathDate ?died}      
  }
  GROUP BY ?country ?partyname
  ORDER BY DESC (?qt)
'); 


/*
 * All filters (WHERE, FETCH and ILIKE) will be applied locally,
 * as the raw SPARQL cannot be parsed - it contains aggregators.
 */
SELECT party, nmembers 
FROM party_members
WHERE country ~~* '%isle of man%'
ORDER BY nmembers ASC
FETCH FIRST 5 ROWS ONLY;


/* ################### SPARQL UNION ################### */

CREATE FOREIGN TABLE chanceler_candidates (
  name text  OPTIONS (variable '?name'),
  party text    OPTIONS (variable '?partyname'),
  birthdate date  OPTIONS (variable '?birthdate', literaltype 'xsd:date')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>
    
    SELECT ?name ?partyname ?birthdate
    WHERE {
       ?person rdfs:label ?name
       { ?person rdfs:label "Friedrich Merz"@de }      
       UNION
       { ?person rdfs:label "Markus Söder"@de }            
       ?person dbo:birthDate ?birthdate .
       ?person dbo:party ?party .
       ?party dbp:name ?partyname 
      FILTER(LANG(?name) = "de") 
    } 
'); 

/* ################### Expression Check ################### */

/*
 * All filters (WHERE and ORDER BY) will be applied locally,
 * as the raw SPARQL cannot be parsed - it contains UNION.
 */
SELECT name, party, birthdate
FROM chanceler_candidates
WHERE party <> ''
ORDER BY birthdate DESC;

CREATE FOREIGN TABLE german_public_universities (
  id text      OPTIONS (variable '?uri'),
  name text    OPTIONS (variable '?name'),
  lon numeric  OPTIONS (variable '?lon'),
  lat numeric  OPTIONS (variable '?lat'),
  wkt text     OPTIONS (variable '?wkt',
                        expression 'CONCAT("POINT(",?lon," ",?lat,")")')
) SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>
    PREFIX dbr:  <http://dbpedia.org/resource/>
    SELECT ?uri ?name ?lon ?lat
    WHERE {
      ?uri dbo:type dbr:Public_university ;
        dbp:name ?name;
        geo:lat ?lat; 
        geo:long ?lon; 
        dbp:country dbr:Germany
      }'
  ); 

/*
 * This will return a WKT representation of geo coordinates, although not 
 * previously defined in the SPARQL query. The variables '?lon' and 'uri' 
 * are removed from the SPARQL SELECT clause, as they were not used in the 
 * SQL query.
 */
SELECT name, wkt 
FROM german_public_universities 
ORDER BY lat DESC 
LIMIT 10;

/*
 * WHERE clause containing a column with 'expression' OPTION.
 */
SELECT name, wkt 
FROM german_public_universities 
WHERE 
  id <> '' AND 
  lat > 52 AND 
  lon < 9 AND
  wkt = 'POINT(8.49305534362793 52.03777694702148)';


/*
 * WHERE conditions with expressions
 */
SELECT name, lon < 9, lat > 52
FROM german_public_universities 
WHERE 
  id <> '' AND 
  lat - 1 > 52 AND -- conditions with expressions in the left side won't be pushed down.
  lon < 8+1; -- the expression in the right side will be computed before pushdown.
  

/*
 * SPARQL contains a LIMIT. Nothing will be pushed down.
 */
 CREATE FOREIGN TABLE person1 (
  person text OPTIONS (variable '?person'),
  birthdate text OPTIONS (variable '?birthdate')
) SERVER dbpedia OPTIONS 
  (sparql '
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>
    SELECT *
    WHERE
    { 
      ?person a dbo:Politician;
          dbo:birthDate ?birthdate
      } 
    LIMIT 1
  ', 
  log_sparql 'true');

SELECT birthdate FROM person1 WHERE person = 'foo'; 

/*
 * SPARQL contains ORDER BY. Nothing will be pushed down.
 */
 CREATE FOREIGN TABLE person2 (
  person text OPTIONS (variable '?person'),
  birthdate text OPTIONS (variable '?birthdate')
) SERVER dbpedia OPTIONS 
  (sparql '
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>
    SELECT *
    WHERE
    { 
      ?person a dbo:Politician;
          dbo:birthDate ?birthdate
    } 
    ORDER BY DESC(?birthdate)
  ', 
  log_sparql 'true');

SELECT birthdate FROM person2 WHERE person = 'foo';


/*
 * SPARQL contains no explicit WHERE clause.
 */
 CREATE FOREIGN TABLE person3 (
  person text OPTIONS (variable '?person'),
  birthdate text OPTIONS (variable '?birthdate')
) SERVER dbpedia OPTIONS 
  (sparql '
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>
    SELECT *
    { 
      ?person a dbo:Politician;
        dbo:birthDate ?birthdate
    } 
  ', 
  log_sparql 'true');

SELECT birthdate FROM person3 
WHERE person <> '' 
LIMIT 5;


/* ===================== Pushdown Check =====================
 * Tests the result set for filter applied localy and remotely. 
 * The result sets must be identical.
 */

  CREATE FOREIGN TABLE politicians_germany (
  uri text        OPTIONS (variable '?person'),
  name text       OPTIONS (variable '?personname'),
  birthdate date  OPTIONS (variable '?birthdate', literaltype 'xsd:date'),
  party text      OPTIONS (variable '?partyname'),
  country text    OPTIONS (variable '?country')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>
    
    SELECT *
    WHERE
      {
        ?person 
          a dbo:Politician;
          dbo:birthDate ?birthdate;
          dbp:name ?personname;
          dbo:party ?party .       
        ?party 
          dbp:country ?country;
          rdfs:label ?partyname .
        FILTER NOT EXISTS {?person dbo:deathDate ?died}
        FILTER(LANG(?partyname) = "de")
        FILTER(STR(?country) = "Germany")
      } 
'); 


CREATE TABLE t_film_remotefilters AS 
SELECT name, released, runtime
FROM film
WHERE 
  name = 'The Life of Adam Lindsay Gordon' AND 
  runtime < 10 AND
  released < '1930-03-25'
ORDER BY name
FETCH FIRST 3 ROWS ONLY;

CREATE TABLE t_politicians_remotefilters AS
SELECT DISTINCT 
  name, 
  birthdate,  
  party, 
  country
FROM politicians_germany
WHERE birthdate > '1990-12-01'
ORDER BY birthdate DESC, party ASC
LIMIT 10;

/* Disabling enable_pushdown OPTION */
ALTER FOREIGN TABLE film                OPTIONS (ADD enable_pushdown 'false');
ALTER FOREIGN TABLE politicians_germany OPTIONS (ADD enable_pushdown 'false');

CREATE TABLE t_film_localfilters AS 
SELECT name, released, runtime
FROM film
WHERE 
  name = 'The Life of Adam Lindsay Gordon' AND 
  runtime < 10 AND
  released < '1930-03-25'
ORDER BY name
FETCH FIRST 3 ROWS ONLY;

CREATE TABLE t_politicians_localfilters AS
SELECT DISTINCT 
  name, 
  birthdate,  
  party, 
  country
FROM politicians_germany
WHERE birthdate > '1990-12-01'
ORDER BY birthdate DESC, party ASC
LIMIT 10;


SELECT * FROM t_film_remotefilters        EXCEPT SELECT * FROM t_film_localfilters;
SELECT * FROM t_politicians_remotefilters EXCEPT SELECT * FROM t_politicians_localfilters;


/* 
 * Test SPARQL containing LIMIT keyword in a literal
 */
CREATE FOREIGN TABLE dbpedia_limit (
  name text        OPTIONS (variable '?name'),
  description text OPTIONS (variable '?abstract')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX dbr: <http://dbpedia.org/resource/>
  PREFIX dbp: <http://dbpedia.org/property/>
  PREFIX dbo: <http://dbpedia.org/ontology/>

  SELECT *
  {
    dbr:Cacilhas_Lighthouse dbo:abstract ?abstract ;
      dbp:name ?name
    FILTER(REGEX(STR(?abstract), " limit "))
  }
'); 

SELECT name
FROM dbpedia_limit
LIMIT 2;


/*
 * Test SPARQL containing ORDER BY keyword in a literal
 */
CREATE FOREIGN TABLE dbpedia_orderby (
  name text        OPTIONS (variable '?name'),
  description text OPTIONS (variable '?abstract')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX dbr: <http://dbpedia.org/resource/>
  PREFIX dbp: <http://dbpedia.org/property/>
  PREFIX dbo: <http://dbpedia.org/ontology/>

  SELECT *
  {
    dbr:List_of_flag_names dbo:abstract ?abstract ;
      dbp:name ?name
    FILTER(REGEX(STR(?abstract), " order by "))
  }
'); 

SELECT name
FROM dbpedia_orderby
ORDER BY name DESC
LIMIT 2;

/*
 * Test SPARQL containing DISTINCT keyword in a literal
 */
CREATE FOREIGN TABLE dbpedia_distinct (
  name text        OPTIONS (variable '?name'),
  description text OPTIONS (variable '?abstract')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX dbr: <http://dbpedia.org/resource/>
  PREFIX dbp: <http://dbpedia.org/property/>
  PREFIX dbo: <http://dbpedia.org/ontology/>

  SELECT *
  {
    dbr:Cadillac_Eldorado dbo:abstract ?abstract ;
      dbp:name ?name
    FILTER(REGEX(STR(?abstract), " distinct "))
  }
'); 

SELECT DISTINCT name
FROM dbpedia_distinct
LIMIT 1;

/*
 * Test SPARQL containing GROUP BY keyword in a literal
 */
CREATE FOREIGN TABLE dbpedia_groupby (
  name text        OPTIONS (variable '?name'),
  description text OPTIONS (variable '?abstract')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX dbr: <http://dbpedia.org/resource/>
  PREFIX dbp: <http://dbpedia.org/property/>
  PREFIX dbo: <http://dbpedia.org/ontology/>

  SELECT *
  {
    dbr:Only_for_Love dbo:abstract ?abstract ;
      dbp:name ?name
    FILTER(REGEX(STR(?abstract), " group by "))
  }
'); 

SELECT name
FROM dbpedia_groupby
LIMIT 1;


/*
 * Test SPARQL containing a REDUCED modifier
 */
CREATE FOREIGN TABLE musical_artists (
  uri text   OPTIONS (variable '?uri'),
  name text  OPTIONS (variable '?name')  
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX dbp: <http://dbpedia.org/property/>
  PREFIX dbo: <http://dbpedia.org/ontology/>
  SELECT REDUCED ?uri ?name {
    ?uri a dbo:MusicalArtist;
      dbp:name ?name
  }
'); 

SELECT name
FROM musical_artists
LIMIT 10;


/*
 * Test SPARQL containing multiple FROM clauses
 */
CREATE FOREIGN TABLE generic_rdf_table (
  uri text   OPTIONS (variable '?s', nodetype 'iri'),
  name text  OPTIONS (variable '?o')  
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX dbr: <http://dbpedia.org/resource/>
  PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  SELECT *
  FROM <http://dbpedia.org>
  FROM <http://foo.bar>
  FROM <http://xyz.int>
  FROM <http://abc.def>
  WHERE {
    ?s rdfs:label ?o .    
    FILTER (LANG(?o)="de" ) 
  }
'); 

SELECT name
FROM generic_rdf_table
WHERE uri = 'http://dbpedia.org/resource/Isle_of_Man'
LIMIT 10;


/*
 * Test SPARQL containing a FROM clause
 */
CREATE FOREIGN TABLE generic_rdf_table2 (
  uri text   OPTIONS (variable '?s', nodetype 'iri'),
  name text  OPTIONS (variable '?o')  
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX dbr: <http://dbpedia.org/resource/>
  PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  SELECT *
  FROM <http://dbpedia.org>
  WHERE {
    ?s rdfs:label ?o .    
    FILTER (LANG(?o)="pl" ) 
  }
'); 

SELECT name
FROM generic_rdf_table2
WHERE uri = 'http://dbpedia.org/resource/Brazil'
LIMIT 10;

/*
 * Test SPARQL containing FROM and FROM NAMED clauses
 */
CREATE FOREIGN TABLE generic_rdf_table3 (
  uri text   OPTIONS (variable '?s', nodetype 'iri'),
  name text  OPTIONS (variable '?o')  
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX dbr: <http://dbpedia.org/resource/>
  PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  SELECT *
  FROM <http://dbpedia.org>
  FROM NAMED    <http://foo.bar>
  FROM NAMED            <http://xyz.abc>
  WHERE {
    ?s rdfs:label ?o .    
    FILTER (LANG(?o)="es" ) 
  }
'); 

SELECT name
FROM generic_rdf_table3
WHERE uri = 'http://dbpedia.org/resource/Japan'
LIMIT 10;


CREATE FOREIGN TABLE generic_rdf_table4 (
  uri text   OPTIONS (variable '?s', nodetype 'iri'),
  name text  OPTIONS (variable '?o')  
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX dbr: <http://dbpedia.org/resource/>
  PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
  SELECT *
  FROM<http://dbpedia.org>FROM                      NAMED<http://foo.bar>FROM NAMED            <http://xyz.abc>
  WHERE {
    ?s rdfs:label ?o .    
    FILTER (LANG(?o)="es" ) 
  }
'); 

SELECT name
FROM generic_rdf_table4
WHERE uri = 'http://dbpedia.org/resource/Japan'
LIMIT 10;



CREATE FOREIGN TABLE public.regex_test1 (
  txt text OPTIONS (variable '?o', nodetype 'literal')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX foaf: <http://xmlns.com/foaf/0.1/>
  SELECT * {<http://dbpedia.org/resource/%5Etxt2regex$> foaf:name ?o}
');


/*
 ILIKE expression containing "^" and "$"
 */
SELECT txt FROM public.regex_test1
WHERE txt ~~* '%^___2reGeX$';



CREATE FOREIGN TABLE public.regex_test (
  name     text OPTIONS (variable '?name', nodetype 'literal'),
  abstract text OPTIONS (variable '?abstract', expression 'STR(?abs)')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
   PREFIX foaf: <http://xmlns.com/foaf/0.1/>
   PREFIX dbo:  <http://dbpedia.org/ontology/>
   PREFIX dbr: <http://dbpedia.org/resource/>
   SELECT *
   {?s a dbo:WrittenWork ;
     dbo:genre dbr:Computer_magazine;
     dbo:abstract ?abs ;
     foaf:name ?name .
    FILTER(LANG(?abs) = "en")
   }');

/*
 LIKE and ILIKE expressions containing  "." 
 */
SELECT name FROM regex_test
WHERE name LIKE '%P.P.%' AND abstract ILIKE '%wITh_MAC__.';

/*
 LIKE and ILIKE expressions containing "(" and "["
 */
SELECT name FROM regex_test
WHERE abstract ~~ '%(IT)%' AND abstract ~~* '%(ABBREVIATED AS cw)%' ;

/*
 LIKE and ILIKE expressions containing "-"
 */
SELECT name FROM regex_test
WHERE abstract ~~ '%VIC-_0%' AND abstract ~~* '%__-MoNtHlY%' AND name ~~ 'Your___';

/*
 LIKE and ILIKE expressions containing single and double quotes
 */
SELECT name FROM regex_test
WHERE abstract ~~ '%"went digital."%' AND abstract ~~* E'%cOuNtRy\'s%' ;


DROP SERVER dbpedia CASCADE;