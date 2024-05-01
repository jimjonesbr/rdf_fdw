/*
 ogr2ogr -f PostgreSQL "PG:dbname=gadm host=172.17.0.2 user=postgres" gadm41_DEU.gpkg
*/

CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://query.wikidata.org/sparql');

CREATE TABLE external_source (
    source_id text,
    source_url text,
    PRIMARY KEY (source_id)
);

INSERT INTO external_source VALUES ('wikidata', 'https://query.wikidata.org/');

CREATE TABLE gadm_mapping (
  gadm_id text,
  source_id text REFERENCES external_source (source_id),
  external_id text,
  PRIMARY KEY (gadm_id, source_id)
);


CREATE FOREIGN TABLE wikidata_german_cities (
  uri text                   OPTIONS (variable '?id'),
  name text                  OPTIONS (variable '?label', language 'de'),
  geom geometry(point, 4326) OPTIONS (variable '?geo')
)
SERVER wikidata OPTIONS (
  sparql '
  SELECT * 
  {
    VALUES ?type {wd:Q515 wd:Q15284}
    ?id wdt:P17 wd:Q183 ;
        wdt:P1705 ?label ;
	      wdt:P625 ?geo ;
        p:P31/ps:P31/wdt:P279* ?type
    SERVICE wikibase:label { bd:serviceParam wikibase:language "[AUTO_LANGUAGE]". }
  }
');


DO $$
DECLARE 
  g record; 
  w record;
BEGIN
  -- Iterate over all cities / municipalities from Germany
  FOR g IN 
    SELECT DISTINCT gid_4, name_4, type_4, geom
    FROM adm_adm_4 
    WHERE gid_0 = 'DEU' 
    ORDER BY name_4
  LOOP
    -- Look in Wikidata for cities that match the GADM city name
	  SELECT * INTO w FROM wikidata_german_cities 
	  WHERE name = g.name_4 
	  FETCH FIRST ROW ONLY;
    
	  IF w IS NOT NULL THEN
      -- If the wikidata geometry is at least 5km away from the GADM geometry
      -- we consider it a match. 
      IF ST_Distance(w.geom::geography, g.geom::geography) < 5000 THEN 
	      INSERT INTO gadm_mapping VALUES (g.gid_4, 'wikidata', w.uri);
	      RAISE INFO '[OK] GADM "% (%)" mapped to Wikidata "% (%)"',g.name_4, g.gid_4, w.name, w.uri;
      ELSE
        RAISE WARNING '"% (%)" is too far from the GADM geometry: % km',g.name_4, g.gid_4,  ST_Distance(w.geom::geography, g.geom::geography) / 1000;
      END IF;
	  ELSE
	    RAISE WARNING '% % (%) not found', g.type_4, g.name_4, g.gid_4;
	  END IF;

  END LOOP;
END;
$$;



-- DROP FOREIGN TABLE IF EXISTS german_cities; 
-- SELECT * FROM german_cities limit 11;
-- DROP TABLE IF EXISTS external_source CASCADE;
