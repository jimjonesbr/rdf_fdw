/* invalid foreign server - option 'foo' ins't a valid endpoint URL */
CREATE SERVER rdfserver_error1 
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint 'foo'
);

/* empty foreign server option - empty endpoints are not allowed */
CREATE SERVER rdfserver_error2
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (
  endpoint ''
);

/* invalid enable_pushdown value */
CREATE SERVER rdfserver_error3
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  enable_pushdown 'foo'
);

/* invalid fetch_size - negative fetch_size */
CREATE SERVER rdfserver_error4
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  fetch_size '-1'
);

/* invalid fetch_size - empty string */
CREATE SERVER rdfserver_error5
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  fetch_size ''
);

/* invalid enable_xml_huge value */
CREATE SERVER rdfserver_error6
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  enable_xml_huge 'foo'
);

/* invalid batch_size - non-numeric value */
CREATE SERVER rdfserver_error7
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  batch_size 'foo'
);

/* invalid batch_size - zero value */
CREATE SERVER rdfserver_error8
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  batch_size '0'
);

/* invalid batch_size - negative value */
CREATE SERVER rdfserver_error9
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  batch_size '-10'
);

/* invalid batch_size - empty string */
CREATE SERVER rdfserver_error10
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  batch_size ''
);

/* invalid batch_size - white space */
CREATE SERVER rdfserver_error11
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql',
  batch_size ' '
);