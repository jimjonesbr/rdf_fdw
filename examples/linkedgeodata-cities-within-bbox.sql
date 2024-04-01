
CREATE SERVER linkedgeodata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'http://linkedgeodata.org/sparql');

/*
 * LinkedGeoData Cities
 * List all <http://linkedgeodata.org/ontology/City> that contain a WKT literal and a
 * label written in English. This example requires the extension PostGIS!
 */

CREATE FOREIGN TABLE cities (
  uri text                  OPTIONS (variable '?city'),
  city text                 OPTIONS (variable '?label'),
  country_code text         OPTIONS (variable '?countryCode'),
  geom geometry(point,4326) OPTIONS (variable '?wkt'),
  geog geography            OPTIONS (variable '?wkt')

)
SERVER linkedgeodata OPTIONS (
  log_sparql 'true',
  sparql '
    SELECT *
    WHERE {        
        ?city a <http://linkedgeodata.org/ontology/City> .
        ?city <http://www.w3.org/2000/01/rdf-schema#label> ?label .        
        ?city <http://geovocab.org/geometry#geometry> ?geo .
        ?geo <http://www.opengis.net/ont/geosparql#asWKT> ?wkt .
        FILTER(LANG(?label) = "en")
        OPTIONAL { ?city <http://linkedgeodata.org/ontology/is_in%3Acountry_code> ?countryCode } 
    }
');


/*
 * Select all records that overlap with a given bbox
 */
SELECT uri, city, country_code, geom, geog
FROM cities 
WHERE 
  ST_Contains(
    'SRID=4326;POLYGON ((-8.613281 52.268157, -8.613281 56.218923, 0.878906 56.218923, 0.878906 52.268157, -8.613281 52.268157))',
    ST_SetSRID(geom,4326));