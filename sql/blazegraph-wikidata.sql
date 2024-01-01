CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'https://query.wikidata.org/sparql');


CREATE FOREIGN TABLE atms_munich (
atmid text     OPTIONS (variable '?atm'),
atmwkt text    OPTIONS (variable '?geometry'),
bankid text    OPTIONS (variable '?bank'),
bankname text  OPTIONS (variable '?bankLabel')
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
  wikidata_id text   OPTIONS (variable '?place'),
  label text         OPTIONS (variable '?labelc', expression 'UCASE(?label)'),
  wkt text           OPTIONS (variable '?location'),
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
 * STRAFTER, CONCAT and LANG
 */
CREATE FOREIGN TABLE european_countries (
  uri text       OPTIONS (variable '?country'),
  label text     OPTIONS (variable '?countryLabel'),
  len_label int  OPTIONS (variable '?len', expression 'STRLEN(?nativename)'),
  uname text     OPTIONS (variable '?ucase_nativename', expression 'UCASE(?nativename)'),
  lname text     OPTIONS (variable '?lcase_nativename', expression 'LCASE(?nativename)'),
  language text  OPTIONS (variable '?language', expression 'LANG(?nativename)'),
  base_url text  OPTIONS (variable '?base', expression 'STRBEFORE(STR(?country),"Q")'),
  qid text       OPTIONS (variable '?qid', expression 'STRAFTER(STR(?country),"entity/")'),
  ctlang text    OPTIONS (variable '?ct', expression 'CONCAT(STR(?country),UCASE(?nativename))')
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

SELECT * 
FROM european_countries
ORDER by language;

SELECT * 
FROM european_countries
WHERE 
 language = 'de' AND 
 len_label <= 10 AND
 qid = 'Q32' AND
 base_url = 'http://www.wikidata.org/entity/' AND
 ctlang = 'http://www.wikidata.org/entity/Q32LUXEMBURG'
ORDER by language;