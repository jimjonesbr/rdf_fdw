CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql');

CREATE FOREIGN TABLE german_public_universities (
  id text      OPTIONS (variable '?uri'),
  name text    OPTIONS (variable '?name'),
  lon numeric  OPTIONS (variable '?lon'),
  lat numeric  OPTIONS (variable '?lat'),
  wkt text     OPTIONS (variable '?wkt',
                        expression 'CONCAT("POINT(",?lon," ",?lat,")") AS ?wkt')
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

SELECT name, wkt::geometry 
FROM german_public_universities 
ORDER BY lat DESC 
FETCH FIRST 10 ROWS ONLY;