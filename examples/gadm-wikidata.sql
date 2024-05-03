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

INSERT INTO external_source 
VALUES 
  ('wikidata', 'https://query.wikidata.org'),
  ('gnd',      'https://www.dnb.de'),
  ('geonames', 'https://www.geonames.org/');

CREATE TABLE gadm_mapping (
  gadm_id text,
  source_id text REFERENCES external_source (source_id),
  external_id text,
  PRIMARY KEY (gadm_id, source_id)
);

CREATE FOREIGN TABLE wikidata_german_cities (
  wikidataid text            OPTIONS (variable '?wikidataid'),
  geonamesid text            OPTIONS (variable '?geonamesid'),
  gndid text                 OPTIONS (variable '?gndid'),
  name text                  OPTIONS (variable '?label', language 'de'),
  geom geometry(point, 4326) OPTIONS (variable '?geo')
)
SERVER wikidata OPTIONS (
  log_sparql 'false',
  sparql '
  SELECT DISTINCT * 
  {
    VALUES ?type {wd:Q515 wd:Q15284}
    ?wikidataid 
        wdt:P17 wd:Q183 ;
        wdt:P1705 ?label ;
	      wdt:P625 ?geo ;
        p:P31/ps:P31/wdt:P279* ?type
    OPTIONAL {?wikidataid wdt:P227 ?gndid}
    OPTIONAL {?wikidataid wdt:P1566 ?geonamesid}
    SERVICE wikibase:label { bd:serviceParam wikibase:language "[AUTO_LANGUAGE]". }
  }
');


DO $$
DECLARE 
  g record; 
  w record;
  match boolean := false;
BEGIN
  -- Iterate over all cities / municipalities from Germany
  FOR g IN 
    SELECT DISTINCT gid_4, name_4, type_4, geom
    FROM adm_adm_4 
    WHERE gid_0 = 'DEU' 
    ORDER BY name_4
  LOOP
    -- Look in Wikidata for cities that match the GADM city name
    FOR w IN
      EXECUTE FORMAT('SELECT * FROM wikidata_german_cities WHERE name = %s',quote_literal(g.name_4))
    LOOP
      -- Is the retrieved geometry at least 5km away from the GADM geometry?
      IF ST_Distance(w.geom::geography, g.geom::geography) < 5000 THEN 
	      INSERT INTO gadm_mapping VALUES (g.gid_4, 'wikidata', w.wikidataid);
	      RAISE INFO '[OK] GADM "% (%)" mapped to Wikidata "% (%)"',g.name_4, g.gid_4, w.name, w.wikidataid;
        match := true;

        IF w.gndid IS NOT NULL THEN
          INSERT INTO gadm_mapping VALUES (g.gid_4, 'gnd', w.gndid);
        END IF;

        IF w.geonamesid IS NOT NULL THEN
          INSERT INTO gadm_mapping VALUES (g.gid_4, 'geonames', w.geonamesid);
        END IF;
        -- Leaving loop, as at this point we've already found a match.
        EXIT;
      END IF;      

    END LOOP;

    IF NOT match THEN
      RAISE WARNING 'No match found for % (%)',g.name_4, g.gid_4;
    END IF;

  END LOOP;
END;
$$;



-- DROP FOREIGN TABLE IF EXISTS german_cities; 
-- SELECT * FROM german_cities limit 11;
-- DROP TABLE IF EXISTS external_source CASCADE;
