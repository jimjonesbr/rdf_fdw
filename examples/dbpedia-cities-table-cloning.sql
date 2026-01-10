CREATE SERVER dbpedia
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://dbpedia.org/sparql',
         enable_xml_huge 'true');

CREATE FOREIGN TABLE public.cities (
  uri       rdfnode OPTIONS (variable '?city'),
  geom      rdfnode OPTIONS (variable '?wkt'),
  city_name rdfnode OPTIONS (variable '?name'),
  area      rdfnode OPTIONS (variable '?area')
)
SERVER dbpedia OPTIONS (
  sparql '
    PREFIX dbo:  <http://dbpedia.org/ontology/>
    PREFIX foaf: <http://xmlns.com/foaf/0.1/>
    PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
    SELECT *
    {
      {
        SELECT ?city ?name ?area ?wkt
        {?city a dbo:City ;
        foaf:name ?name .
        OPTIONAL {?city dbo:areaTotal ?area}
        OPTIONAL {?city geo:geometry ?wkt}
      } ORDER BY ASC(?name)
    }
  }
');

/*
 * materilizes all records from the FOREIGN TABLE 'public.cities' in 
 * the table 'public.cities_local' - retrieving 5000 records at a time.
 */ 

CALL rdf_fdw_clone_table(
      foreign_table => 'cities',
      target_table  => 'cities_local',
      create_table => true,
      fetch_size => 5000,
      orderby_column => NULL,
      verbose => true);

SELECT count(*) FROM cities_local;