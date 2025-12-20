CREATE SERVER testserver
FOREIGN DATA WRAPPER rdf_fdw 
OPTIONS (    
  endpoint 'https://dbpedia.org/sparql'
);

CREATE USER u1;

/* empty user name */
CREATE USER MAPPING FOR u1 SERVER testserver OPTIONS (user '', password 'foo');

/* empty password */
CREATE USER MAPPING FOR u1 SERVER testserver OPTIONS (user 'foo', password '');

/* invalid option */
CREATE USER MAPPING FOR u1 SERVER testserver OPTIONS (user 'jim', foo 'bar');

/* clean up */
DROP SERVER testserver CASCADE;
DROP USER u1;