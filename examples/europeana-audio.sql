
CREATE SERVER europeana
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (endpoint 'https://sparql.europeana.eu/');

/*
 * Finding Europeana audio with SPARQL
 * 
 * Source: Bob DuCharme (https://www.bobdc.com/blog/finding-europeana-audio-with-s/)
 */

CREATE FOREIGN TABLE audio (
  uri text     OPTIONS (variable '?mediaURL'),
  title text   OPTIONS (variable '?title'),
  creator text OPTIONS (variable '?creator'),
  source text  OPTIONS (variable '?source')
)
SERVER europeana OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX edm: <http://www.europeana.eu/schemas/edm/>
  PREFIX ore: <http://www.openarchives.org/ore/terms/>
  PREFIX dc: <http://purl.org/dc/elements/1.1/> 

  SELECT ?title ?mediaURL ?creator ?source WHERE {
    ?resource edm:type "SOUND" ;
              ore:proxyIn ?proxy ;
              dc:title ?title ;
              dc:creator ?creator ;
              dc:source ?source . 
    ?proxy edm:isShownBy ?mediaURL . 
   }
'); 

SELECT * FROM audio
WHERE source = 'Austrian National Library';