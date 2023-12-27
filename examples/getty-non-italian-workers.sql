CREATE SERVER getty
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'http://vocab.getty.edu/sparql.xml',
  format 'application/sparql-results+xml'
);

/*
 * Find non-Italians who worked in Italy and lived during a given time range
 * - Having event that took place in tgn:1000080 Italy or any of its descendants
 * - Birth date between 1250 and 1780
 * - Just for variety, we look for artists as descendants of facets ulan:500000003 "Corporate bodies" or ulan:500000002 "Persons, Artists", 
 *   rather than having type "artist" as we did in previous queries. In the previous query we used values{..} but we here use filter(in(..)).
 * - Not having nationality aat:300111198 Italian or any of its descendants
 * 
 * SPARQL author: Getty Thesaurus (http://vocab.getty.edu/queries#Non-Italians_Who_Worked_in_Italy)
 */

CREATE FOREIGN TABLE getty_non_italians (
  uri text   OPTIONS (variable '?x'),
  name text  OPTIONS (variable '?name'),
  bio text   OPTIONS (variable '?bio'),
  birth int  OPTIONS (variable '?birth')
)
SERVER getty OPTIONS (
  log_sparql 'true',
  sparql '
  PREFIX ontogeo: <http://www.ontotext.com/owlim/geo#>
  PREFIX geo: <http://www.w3.org/2003/01/geo/wgs84_pos#>
  PREFIX gvp: <http://vocab.getty.edu/ontology#>
  PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
  PREFIX schema: <http://schema.org/>
  PREFIX foaf: <http://xmlns.com/foaf/0.1/>

   SELECT ?x ?name ?bio ?birth {
  {SELECT DISTINCT ?x
    {?x foaf:focus/bio:event/(schema:location|(schema:location/gvp:broaderExtended)) tgn:1000080-place}}
 	 ?x gvp:prefLabelGVP/xl:literalForm ?name;
	    foaf:focus/gvp:biographyPreferred [
	    schema:description ?bio;
       	gvp:estStart ?birth].

  FILTER ("1250"^^xsd:gYear <= ?birth && ?birth <= "1780"^^xsd:gYear)
  FILTER EXISTS {?x gvp:broaderExtended ?facet.
  FILTER(?facet in (ulan:500000003, ulan:500000002))}
  FILTER NOT EXISTS {?x foaf:focus/(schema:nationality|(schema:nationality/gvp:broaderExtended)) aat:300111198}}
  '); 


SELECT name, bio, birth
FROM getty_non_italians
WHERE bio ~~* '%artist%'
ORDER BY birth 
LIMIT 10;