
CREATE TABLE sparql.prefix_contexts (
    context text PRIMARY KEY,
    description text,
    modified_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO sparql.prefix_contexts (context, description) VALUES
    ('default', 'Default context for SPARQL prefixes');

CREATE TABLE sparql.prefixes (
    prefix text PRIMARY KEY,
    uri text NOT NULL,
    context text NOT NULL REFERENCES sparql.prefix_contexts(context) ON DELETE CASCADE,
    modified_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO sparql.prefixes (prefix, uri, context)
VALUES
    ('rdf', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#','default'),
    ('rdfs', 'http://www.w3.org/2000/01/rdf-schema#','default'),
    ('owl', 'http://www.w3.org/2002/07/owl#','default'),
    ('xsd', 'http://www.w3.org/2001/XMLSchema#','default'),
    ('foaf', 'http://xmlns.com/foaf/0.1/','default'),
    ('dc', 'http://purl.org/dc/elements/1.1/','default');