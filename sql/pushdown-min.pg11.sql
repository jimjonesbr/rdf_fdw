
CREATE FOREIGN TABLE politicians (
  uri text        OPTIONS (variable '?person', nodetype 'iri'),
  name text       OPTIONS (variable '?personname', nodetype 'literal', literaltype 'xsd:string'),
  name_upper text OPTIONS (variable '?name_ucase', nodetype 'literal', expression 'UCASE(?personname)'),
  name_len int    OPTIONS (variable '?name_len', nodetype 'literal', expression 'STRLEN(?personname)'),
  birthdate date  OPTIONS (variable '?birthdate', nodetype 'literal', literaltype 'xsd:date'),
  party text      OPTIONS (variable '?partyname', nodetype 'literal', literaltype 'xsd:string'),
  wikiid int      OPTIONS (variable '?pageid', nodetype 'literal', literaltype 'xsd:nonNegativeInteger'),
  ts timestamp with time zone   OPTIONS (variable '?ts', expression '"2002-03-08T14:33:42"^^xsd:dateTime', literaltype 'xsd:dateTime'),
  country text    OPTIONS (variable '?country', nodetype 'literal', language 'en')
)
SERVER dbpedia OPTIONS (
  log_sparql 'true',
  sparql '
    PREFIX dbp: <http://dbpedia.org/property/>
    PREFIX dbo: <http://dbpedia.org/ontology/>

    SELECT *
    WHERE {
      ?person 
          a dbo:Politician;
          dbo:birthDate ?birthdate;
          dbp:name ?personname;
          dbo:party ?party ;   
          dbo:wikiPageID ?pageid .
        ?party 
          dbp:country ?country;
          rdfs:label ?partyname .
        FILTER NOT EXISTS {?person dbo:deathDate ?died}
        FILTER(LANG(?partyname) = "de")
      } 
');

/*
 * Pushdown test for STARTS_WITH
 */
SELECT uri, name, name_upper FROM politicians 
WHERE 
  47035308 = wikiid AND 
  starts_with(party,'Demokratisch') AND
  starts_with(name_upper,'WILL')
FETCH FIRST ROW ONLY;

DROP FOREIGN TABLE politicians;