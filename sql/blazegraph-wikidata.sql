CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://query.wikidata.org/sparql');


CREATE FOREIGN TABLE atms_munich (
atmid text     OPTIONS (variable '?atm'),
atmwkt text    OPTIONS (variable '?geometry', literaltype 'geo:wktLiteral'),
bankid text    OPTIONS (variable '?bank'),
bankname text  OPTIONS (variable '?bankLabel', literaltype 'xsd:string')
)
SERVER wikidata OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX lgdo: <http://linkedgeodata.org/ontology/>
  PREFIX geom: <http://geovocab.org/geometry#>
  PREFIX bif: <bif:>
  
  SELECT ?atm ?geometry ?bank ?bankLabel 
  WHERE {
    hint:Query hint:optimizer "None".
    SERVICE <http://linkedgeodata.org/sparql> 
    {
      {?atm a lgdo:Bank; lgdo:atm true.}
      UNION 
      {?atm a lgdo:Atm.}    
      ?atm geom:geometry [geo:asWKT ?geometry];
         lgdo:operator ?operator.
      FILTER(bif:st_intersects(?geometry, bif:st_point(11.5746898, 48.1479876), 5)) # 5 km around Munich
    }
  BIND(STRLANG(?operator, "de") as ?bankLabel) 
  ?bank rdfs:label ?bankLabel.
  { ?bank wdt:P527 wd:Q806724. }
  UNION { ?bank wdt:P1454 wd:Q5349747. }
  MINUS { wd:Q806724 wdt:P3113 ?bank. }
}
'); 

SELECT atmid, bankname, atmwkt
FROM atms_munich
WHERE bankname = 'BBBank';


CREATE FOREIGN TABLE places_below_sea_level (
  wikidata_id text   OPTIONS (variable '?placeid', expression 'STR(?place)'),
  label text         OPTIONS (variable '?labelc', expression 'UCASE(?label)'),
  wkt text           OPTIONS (variable '?location', literaltype 'geo:wktLiteral'),
  elevation numeric  OPTIONS (variable '?elev')
)
SERVER wikidata OPTIONS (
  log_sparql 'true',
  sparql '
  SELECT *
  WHERE
  {
    ?place rdfs:label ?label .
    ?place p:P2044/psv:P2044 ?placeElev.
    ?placeElev wikibase:quantityAmount ?elev.
    ?placeElev wikibase:quantityUnit ?unit.
    bind(0.01 as ?km).
    FILTER( (?elev < ?km*1000 && ?unit = wd:Q11573)
        || (?elev < ?km*3281 && ?unit = wd:Q3710)
        || (?elev < ?km      && ?unit = wd:Q828224) ).
    ?place wdt:P625 ?location.    
    FILTER(LANG(?label)="en")
    SERVICE wikibase:label { bd:serviceParam wikibase:language "[AUTO_LANGUAGE],en" }
}
'); 

SELECT wikidata_id, label, wkt
FROM places_below_sea_level
WHERE wikidata_id = 'http://www.wikidata.org/entity/Q61308849'
FETCH FIRST 5 ROWS ONLY;

/*
 * Expression pushdown tests with LCASE, UCASE, STRLEN, STRBEFORE, 
 * STRAFTER, CONCAT, STRSTARTS, STRENDS and LANG
 */
CREATE FOREIGN TABLE european_countries (
  uri text        OPTIONS (variable '?country', literaltype 'xsd:string'),
  label text      OPTIONS (variable '?label', literaltype '*'),
  nativename name OPTIONS (variable '?nativename', language '*'),
  len_label int   OPTIONS (variable '?1len2', expression 'STRLEN(?nativename)'),
  uname text      OPTIONS (variable '?ucase_nativename', expression 'UCASE(?nativename)'),
  lname text      OPTIONS (variable '?lcase_nativename', expression 'LCASE(?nativename)'),
  language text   OPTIONS (variable '?language', expression 'LANG(?nativename)', literaltype 'xsd:string'),
  base_url text   OPTIONS (variable '?b4se', expression 'STRBEFORE(STR(?country),"Q")', literaltype 'xsd:string'),
  qid text        OPTIONS (variable '?q1d', expression 'STRAFTER(STR(?country),"entity/")', literaltype 'xsd:string'),
  ctlang text     OPTIONS (variable '?ct', expression 'CONCAT(STR(?country),UCASE(?nativename))'),
  dt date         OPTIONS (variable '?det', expression '"2002-03-08"^^xsd:date', literaltype 'xsd:date'),
  ts timestamp    OPTIONS (variable '?ts', expression '"2002-03-08T14:33:42"^^xsd:dateTime', literaltype 'xsd:dateTime'),
  bt boolean      OPTIONS (variable '?but', expression 'STRSTARTS(STR(?country),"http")', literaltype 'xsd:boolean'),
  bf boolean      OPTIONS (variable '?buf', expression 'STRENDS(STR(?country),"http")', literaltype 'xsd:boolean')
)
SERVER wikidata OPTIONS (
  log_sparql 'true',
  sparql '
  SELECT *
  {
    wd:Q458 wdt:P150 ?country.
    OPTIONAL { ?country wdt:P1705 ?nativename }
    SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
  }
'); 


SELECT uri, label, language, bf, bt
FROM european_countries
WHERE 
  language = 'de' AND 
  language <> 'en' AND
  language IN ('de', 'en') AND
  language NOT IN ('es','pt') AND 
 
  len_label <= 10 AND
  len_label IN (8,9) AND
  len_label NOT IN (10,11) AND

  dt NOT IN ('2000-01-01','2000-01-02') AND
  dt IN ('2002-03-08','2000-01-02') AND
  dt = '2002-03-08' AND
  dt != '2002-03-10' AND

  ts NOT IN ('2002-03-08 12:00:00', '2002-03-08 13:00:00') AND
  ts IN ('2002-03-08T14:33:42', '2002-03-08 13:00:00') AND
  ts = '2002-03-08 14:33:42' AND
  ts <> '2002-03-08 11:30:00' AND

  qid IN ('Q32','Q35') AND
  qid NOT IN ('foo','bar') AND
  base_url = 'http://www.wikidata.org/entity/' AND
  ctlang = 'http://www.wikidata.org/entity/Q32LUXEMBURG'
ORDER by language;


/*
 * Test WHERE conditions with boolean columns using IS and IS NOT
 */
SELECT uri, nativename
FROM european_countries
WHERE
  nativename = 'Luxembourg' AND
  bf IS false AND
  bf IS NOT true AND
  bt IS true AND
  bt IS NOT false;

SELECT uri, nativename 
FROM european_countries
WHERE
  nativename = 'Luxembourg' AND
  bf IS false AND
  NOT bf IS true AND
  bt IS true AND
  NOT bt IS false;

/*
 * These boolean expressions won't be pushed down
 */
SELECT uri, nativename 
FROM european_countries
WHERE
  nativename = 'Luxembourg' AND
  bf = false AND
  bf != true AND
  bt = true AND
  bt != false;