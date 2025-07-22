
-- Prefix Management
CREATE TABLE sparql.prefix_contexts (
    context text PRIMARY KEY CHECK (context <> ''),
    description text,
    modified_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE sparql.prefixes (
    prefix text NOT NULL CHECK (prefix <> ''),
    uri text NOT NULL,
    context text NOT NULL REFERENCES sparql.prefix_contexts(context) ON DELETE CASCADE,
    modified_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (prefix, context)
);

CREATE OR REPLACE FUNCTION sparql.add_context(
    context_name TEXT,
    context_description TEXT DEFAULT NULL,
    override BOOLEAN DEFAULT FALSE
) RETURNS void AS $$
BEGIN
    IF override THEN
        INSERT INTO sparql.prefix_contexts (context, description)
        VALUES (context_name, context_description)
        ON CONFLICT (context) DO UPDATE
        SET description = EXCLUDED.description,
            modified_at = now();
    ELSE
        INSERT INTO sparql.prefix_contexts (context, description)
        VALUES (context_name, context_description);
    END IF;
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'prefix context "%" already exists', context_name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sparql.drop_context(
    context_name TEXT,
    cascade BOOLEAN DEFAULT FALSE
) RETURNS void AS $$
BEGIN
    IF cascade THEN
        DELETE FROM sparql.prefixes
        WHERE context = context_name;
    ELSE
        -- Check if context has dependent prefixes
        IF EXISTS (
            SELECT 1 FROM sparql.prefixes
            WHERE context = context_name
        ) THEN
            RAISE EXCEPTION 'prefix context "%" has associated prefixes', context_name;
        END IF;
    END IF;

    -- Now delete the context
    DELETE FROM sparql.prefix_contexts
    WHERE context = context_name;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Prefix context "%" does not exist.', context_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sparql.add_prefix(
    context_name TEXT,
    prefix_name TEXT,
    uri TEXT,
    override BOOLEAN DEFAULT FALSE
) RETURNS void AS $$
BEGIN
    IF override THEN
        INSERT INTO sparql.prefixes (context, prefix, uri)
        VALUES ($1, $2, $3)
        ON CONFLICT (context, prefix) DO UPDATE
        SET uri = EXCLUDED.uri,
            modified_at = now();
    ELSE
        INSERT INTO sparql.prefixes (context, prefix, uri)
        VALUES ($1, $2, $3);
    END IF;
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'prefix "%" already exists in context "%"', $1, $2;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sparql.drop_prefix(
    context_name TEXT,
    prefix_name TEXT
) RETURNS void AS $$
BEGIN
    DELETE FROM sparql.prefixes
    WHERE context = $1 AND prefix = $2;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'prefix "%" not found in context "%".', $1, $2;
    END IF;
END;
$$ LANGUAGE plpgsql;

SELECT sparql.add_context('default', 'Default context for SPARQL prefixes');

SELECT sparql.add_prefix('default', 'rdf', 'http://www.w3.org/1999/02/22-rdf-syntax-ns#');
SELECT sparql.add_prefix('default', 'rdfs', 'http://www.w3.org/2000/01/rdf-schema#');
SELECT sparql.add_prefix('default', 'owl', 'http://www.w3.org/2002/07/owl#');
SELECT sparql.add_prefix('default', 'xsd', 'http://www.w3.org/2001/XMLSchema#');
SELECT sparql.add_prefix('default', 'foaf', 'http://xmlns.com/foaf/0.1/');
SELECT sparql.add_prefix('default', 'dc', 'http://purl.org/dc/elements/1.1/');