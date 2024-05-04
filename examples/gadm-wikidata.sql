/*
 * This example shows how to harvest Wikidata to retrieve the identidiers of
 * German cities. It assumes the GADM data for Germany is downloaded and imported
 * into PostgreSQL - with PostGIS the extension.
 *
 * GADM data for Germany: https://geodata.ucdavis.edu/gadm/gadm4.1/gpkg/gadm41_DEU.gpkg
 * 
 * The GADM GeoPackage can be imported into a PostgreSQL using ogr2ogr as follows:
 *
 * $ ogr2ogr -f PostgreSQL "PG:dbname=db host=pgserver user=postgres" gadm41_DEU.gpkg
 *
 * To map the GADM data to Wikidata, GeoNames or DNB identifiers we first create two tables
 * to store the source and the mapping itself:
 */
CREATE TABLE external_source (
    source_id text,
    base_url text,
    PRIMARY KEY (source_id)
);

INSERT INTO external_source 
VALUES 
  ('wikidata', 'http://www.wikidata.org/entity/'),
  ('gnd',      'https://www.dnb.de'),
  ('geonames', 'https://www.geonames.org/');

CREATE TABLE gadm_mapping (
  gadm_id text,
  source_id text REFERENCES external_source (source_id),
  external_id text,
  PRIMARY KEY (gadm_id, source_id)
);

/*
 * Now we create a FOREIGN TABLE with a SPARQL query that searches for
 * German cities and municipalites.
 */
CREATE SERVER wikidata
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://query.wikidata.org/sparql');

CREATE FOREIGN TABLE wikidata_german_cities (
  wikidataid text            OPTIONS (variable '?wikidataid', nodetype 'iri'),
  geonamesid text            OPTIONS (variable '?geonamesid', nodetype 'iri'),
  gndid text                 OPTIONS (variable '?gndid', nodetype 'iri'),
  name text                  OPTIONS (variable '?label', nodetype 'literal', language 'de'),
  geom geometry(point, 4326) OPTIONS (variable '?geo', nodetype 'literal')
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


/*
 * Finally we iterate over all records of the GADM data set and look for matches in 
 * Wikipedia using the just created FOREIGN TABLE.
 */
DO $$
DECLARE 
  g record; 
  w record;
  match boolean := false;
BEGIN
  -- Iterate over all cities / municipalities from Germany
  FOR g IN 
    SELECT DISTINCT gid_4, name_4, type_4, geom
    FROM adm_adm_4 j
    WHERE gid_0 = 'DEU' AND NOT EXISTS (SELECT 1 FROM gadm_mapping WHERE gadm_id = j.gid_4)
    ORDER BY name_4
  LOOP
    -- Look in Wikidata for cities that match the GADM city name
    FOR w IN
      EXECUTE format('SELECT * FROM wikidata_german_cities WHERE name = %s', quote_literal(g.name_4))
    LOOP
      -- Is the retrieved geometry at least 5km away from the GADM geometry?
      IF ST_Distance(w.geom::geography, g.geom::geography) < 5000 THEN 
	      INSERT INTO gadm_mapping VALUES (g.gid_4, 'wikidata', replace(w.wikidataid,'http://www.wikidata.org/entity/',''));
	      RAISE INFO '[OK] GADM "% (%)" mapped to Wikidata "% (%)"',g.name_4, g.gid_4, w.name, w.wikidataid;
        match := true;

        -- Store the GND identifier, if the match has any.
        IF w.gndid IS NOT NULL THEN
          INSERT INTO gadm_mapping VALUES (g.gid_4, 'gnd', w.gndid);
        END IF;

        -- Store the GeoNames identifier, if the match has any.
        IF w.geonamesid IS NOT NULL THEN
          INSERT INTO gadm_mapping VALUES (g.gid_4, 'geonames', w.geonamesid);
        END IF;

        -- Leaving loop, as at this point we've already found a match.
        EXIT;
      END IF;      

    END LOOP;

    IF NOT match THEN
      RAISE WARNING 'No match found for % (%).',g.name_4, g.gid_4;
    END IF;

    COMMIT;
  END LOOP;
END;
$$;
