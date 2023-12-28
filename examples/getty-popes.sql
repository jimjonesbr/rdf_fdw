CREATE SERVER getty
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'http://vocab.getty.edu/sparql.xml',
  format 'application/sparql-results+xml'
);

/*
 * Popes and Their Reigns
 * 
 * Source: Getty Thesaurus (http://vocab.getty.edu/queries#Non-Italians_Who_Worked_in_Italy)
 */

CREATE FOREIGN TABLE popes (
  uri text       OPTIONS (variable '?x'),
  name text      OPTIONS (variable '?name'),
  bio text       OPTIONS (variable '?bio'),
  startyear int  OPTIONS (variable '?start'),
  endyear int    OPTIONS (variable '?end')
)
SERVER getty OPTIONS (
  log_sparql 'true',
  sparql '
  SELECT *
  {
    ?x gvp:agentTypePreferred [rdfs:label "popes"@en];
       gvp:prefLabelGVP [xl:literalForm ?name];
       foaf:focus [
            bio:event [
                dct:type [rdfs:label "reign"@en]; 
            gvp:estStart ?start; gvp:estEnd ?end];
       gvp:biographyPreferred [schema:description ?bio]]

    } 
  '); 

SELECT * 
FROM popes
ORDER BY startyear, endyear