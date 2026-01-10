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
  uri       rdfnode OPTIONS (variable '?x'),
  name      rdfnode OPTIONS (variable '?name'),
  bio       rdfnode OPTIONS (variable '?bio'),
  startyear rdfnode OPTIONS (variable '?start'),
  endyear   rdfnode OPTIONS (variable '?end')
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

SELECT * FROM popes
WHERE startyear BETWEEN 
  sparql.strdt('1000','<http://www.w3.org/2001/XMLSchema#gYear>') AND 
  sparql.strdt('1500','<http://www.w3.org/2001/XMLSchema#gYear>') AND
  sparql.lang(name) = 'en'
ORDER BY startyear, name;