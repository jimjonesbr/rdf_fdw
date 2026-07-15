SET datestyle = 'ISO, YMD';
SET timezone = 'UTC';

SELECT '"foo"'::rdfnode;
SELECT '"foo"^^xsd:string'::rdfnode;
SELECT '"foo"@es'::rdfnode;
SELECT '"foo"@es'::rdfnode::text;
SELECT '"foo"@es'::rdfnode::text::rdfnode;
SELECT '"foo"^^xsd:string'::rdfnode::text::rdfnode;
SELECT '"nan"^^xsd:double'::rdfnode;
SELECT '"NAN"^^xsd:double'::rdfnode;
SELECT '"nAn"^^xsd:double'::rdfnode;
SELECT '"forty-two"^^xsd:int'::rdfnode;    -- works despite invalid lexical form for int
SELECT '"invalid"^^xsd:dateTime'::rdfnode; -- works despite invalid lexical form for dateTime
SELECT '"25:00:00"^^xsd:time'::rdfnode;
SELECT '"2025-13-01"^^xsd:date'::rdfnode;
SELECT '"abc"^^invalid:datatype'::rdfnode;
SELECT '"abc"@invalid_lang'::rdfnode;
SELECT '"foo'::rdfnode;
SELECT 'f"o"o'::rdfnode;
SELECT '𝄞'::rdfnode;
SELECT ''::rdfnode;
SELECT '"'::rdfnode; 
SELECT '"\""'::rdfnode;
SELECT '😀'::rdfnode;
SELECT '"x^^y"'::rdfnode;                       -- "x^^y"
SELECT '"a\\"b"@en'::rdfnode;                   -- "a\"b"@en
SELECT '"𝄞"^^<http://example.org/dt>'::rdfnode;


/* language tags (BCP 47) */
SELECT '"foo"@'::rdfnode;                       -- invalid: empty tag
SELECT '"foo"@en-US'::rdfnode;                  -- valid
SELECT '"foo"@en-Latn-US-valencia'::rdfnode;    -- valid extended BCP 47
SELECT '"foo"@123'::rdfnode;                    -- invalid: must start with letter
SELECT '"foo"@EN'::rdfnode;                     -- valid; canonical form lowercases primary tag
SELECT '"foo"@en-us'::rdfnode;                  -- subtags after the primary are stored as-is (no region canonicalization)
SELECT '"foo"@en-'::rdfnode;                    -- invalid trailing hyphen

/* IRIs and blank nodes */
SELECT '<http://example.org/foo>'::rdfnode;
SELECT '<urn:isbn:0451450523>'::rdfnode;
SELECT '<http://example.org/foo bar>'::rdfnode; -- invalid: spaces in IRI
SELECT '<>'::rdfnode;                           -- relative empty IRI
SELECT '_:b1'::rdfnode;                         -- blank node
SELECT '_:'::rdfnode;                           -- invalid blank node label

/* numeric edge cases */
SELECT '"+42"^^xsd:int'::rdfnode;               -- explicit plus (valid)
SELECT '"042"^^xsd:int'::rdfnode;               -- leading zeros (valid lex, non-canonical)
SELECT '"2147483647"^^xsd:int'::rdfnode::int;   -- INT_MAX
SELECT '"2147483648"^^xsd:int'::rdfnode;        -- works despite overflow
SELECT '"-2147483648"^^xsd:int'::rdfnode::int;  -- INT_MIN
SELECT '"3.14e0"^^xsd:double'::rdfnode;         -- exponent
SELECT '"3."^^xsd:decimal'::rdfnode;            -- XSD 1.1: invalid; XSD 1.0: valid
SELECT '"-0"^^xsd:integer'::rdfnode;            -- valid lex, canonical is "0"
SELECT '"1.0"^^xsd:integer'::rdfnode;           -- works despite invalid lexical form for integer

/* xsd:boolean alternative lexical forms */
SELECT '"1"^^xsd:boolean'::rdfnode::boolean;     -- true
SELECT '"0"^^xsd:boolean'::rdfnode::boolean;     -- false
SELECT '"TRUE"^^xsd:boolean'::rdfnode;           -- invalid (case-sensitive)
SELECT '"yes"^^xsd:boolean'::rdfnode;            -- invalid

/* date/time variations */
SELECT '"2025-04-25T18:44:38+02:00"^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25T18:44:38.123Z"^^xsd:dateTime'::rdfnode;
SELECT '"-0044-03-15T12:00:00Z"^^xsd:dateTime'::rdfnode;   -- BCE
SELECT '"2025-04-25Z"^^xsd:date'::rdfnode;
SELECT '"2025-04-25-08:00"^^xsd:date'::rdfnode;
SELECT '"24:00:00"^^xsd:time'::rdfnode;          -- XSD 1.1: valid; XSD 1.0: invalid
SELECT '"2025-02-29"^^xsd:date'::rdfnode;        -- works despite not being a leap year
SELECT '"2024-02-29"^^xsd:date'::rdfnode;        -- leap year

/* gYear / gMonth / gDay */
SELECT '"2025"^^<http://www.w3.org/2001/XMLSchema#gYear>'::rdfnode;
SELECT '"--04"^^<http://www.w3.org/2001/XMLSchema#gMonth>'::rdfnode;
SELECT '"---25"^^<http://www.w3.org/2001/XMLSchema#gDay>'::rdfnode;
SELECT '"2025-04"^^<http://www.w3.org/2001/XMLSchema#gYearMonth>'::rdfnode;

/* escape sequences inside literals */
SELECT E'"line1\\nline2"'::rdfnode;              -- \n inside literal
SELECT E'"tab\\there"'::rdfnode;                 -- \t
SELECT E'"\\u00E9"'::rdfnode;                    -- é
SELECT E'"\\U0001F600"'::rdfnode;                -- 😀
SELECT E'"backslash\\\\test"'::rdfnode;          -- \\
SELECT E'"quote\\""'::rdfnode;                   -- \"

/* whitespace handling */
SELECT '  "foo"@en  '::rdfnode;                  -- leading/trailing with language tag
SELECT '  "foo"^^xsd:int  '::rdfnode;            -- leading/trailing with data type
SELECT '"foo" @en'::rdfnode;                     -- space before @ -> invalid
SELECT '"foo"^^ xsd:string'::rdfnode;            -- space after ^^ -> invalid
SELECT E'"foo"\n@en'::rdfnode;                   -- newline before @ -> invalid
SELECT 'foo"bar"@en'::rdfnode;                   -- embedded quote + lang-looking suffix: keep verbatim
SELECT 'x\"y'::rdfnode;                          -- already-escaped text, must NOT double-escape

/* datatype IRI variants */
SELECT '"abc"^^<>'::rdfnode;                     -- empty datatype IRI
SELECT '"abc"^^<not an uri>'::rdfnode;           -- invalid IRI
SELECT '"abc"^^xsd:'::rdfnode;                   -- empty local part
SELECT '"abc"^^:bar'::rdfnode;                   -- empty prefix

/* interval with mixed signs */ 
SELECT '1 year -3 days'::interval::rdfnode;
SELECT '-1 day 12 hours'::interval::rdfnode;
SELECT '3 days -4 hours'::interval::rdfnode;
SELECT '-2 months 5 days'::interval::rdfnode;
SELECT '1 month -30 minutes'::interval::rdfnode;
SELECT '-4 hours'::interval::rdfnode;
SELECT '-1 day -0.5 seconds'::interval::rdfnode;
SELECT '1 day -0.5 seconds'::interval::rdfnode;
SELECT '-1 month 30 minutes'::interval::rdfnode;
SELECT '1 day -1.5 seconds'::interval::rdfnode; 
SELECT '-1 day -1.5 seconds'::interval::rdfnode;
SELECT '-1 day 0.5 seconds'::interval::rdfnode;

/* NULL handling */
SELECT NULL::rdfnode;
SELECT NULL::text::rdfnode;
SELECT ''::rdfnode IS NOT NULL;                  -- empty string != NULL

/* equality / ordering (RDF term equality vs value equality) */
SELECT '"1"^^xsd:int'::rdfnode = '"1"^^xsd:integer'::rdfnode;  -- term !=, value =
SELECT '"foo"@en'::rdfnode = '"foo"@EN'::rdfnode;              -- lang tag case
SELECT '"foo"'::rdfnode = '"foo"^^xsd:string'::rdfnode;        -- RDF 1.1: equal

/* long literals */
SELECT length(repeat('a', 1000000)::rdfnode::text);            -- large literal
SELECT length(sparql.strdt(repeat('a', 1000000)::rdfnode,'<http://www.w3.org/2001/XMLSchema#string>')::text); -- large literal with data type
SELECT length(sparql.strlang(repeat('a', 1000000)::rdfnode,'de')::text); -- large literal with data type

/* literals with malicious trailing content */
SELECT  '"x"@en } ; INSERT DATA {<http://fake.object> <http://fake.predicate> "foo" }'::rdfnode;
SELECT  '"x" } ; INSERT DATA {<http://fake.object> <http://fake.predicate> "foo"'::rdfnode;
SELECT  '"42"^^xsd:long } ; INSERT DATA {<http://fake.object> <http://fake.predicate> "foo"'::rdfnode;
SELECT  '"42"^^<http://www.w3.org/2001/XMLSchema#long> } ; INSERT DATA {<http://fake.object> <http://fake.predicate> "foo"'::rdfnode;

SELECT '"9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode::numeric;
SELECT '"-9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode::numeric;
SELECT '"9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode::numeric::rdfnode;
SELECT '"-9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode::numeric::rdfnode;

SELECT '"42.73"^^xsd:double'::rdfnode::double precision;
SELECT '"-42.73"^^xsd:double'::rdfnode::double precision;
SELECT '"42.73"^^xsd:double'::rdfnode::double precision::rdfnode;
SELECT '"-42.73"^^xsd:double'::rdfnode::double precision::rdfnode;
SELECT '"4.2E1"^^xsd:double'::rdfnode::double precision;
SELECT '"-4.2E1"^^xsd:double'::rdfnode::double precision;

SELECT 42.73::real::rdfnode;
SELECT 42.73::real::rdfnode::real;
SELECT (-42.73)::real::rdfnode;
SELECT (-42.73)::real::rdfnode::real;
SELECT 'INF'::real::rdfnode;
SELECT 'INF'::real::rdfnode::real;
SELECT '-INF'::real::rdfnode;
SELECT '-INF'::real::rdfnode::real;
SELECT 'NaN'::real::rdfnode;
SELECT 'NaN'::real::rdfnode::real;

SELECT 42::bigint::rdfnode;
SELECT 42::bigint::rdfnode::bigint;
SELECT (-42)::bigint::rdfnode;
SELECT (-42)::bigint::rdfnode::bigint;
SELECT 42746357267238767::bigint::rdfnode;
SELECT 42746357267238767::bigint::rdfnode::bigint;
SELECT (-42746357267238767)::bigint::rdfnode;
SELECT (-42746357267238767)::bigint::rdfnode::bigint;

SELECT 42::int::rdfnode;
SELECT 42::int::rdfnode::int;
SELECT (-42)::int::rdfnode;
SELECT (-42)::int::rdfnode::int;
SELECT 427463::int::rdfnode;
SELECT 427463::int::rdfnode::int;
SELECT (-427463)::int::rdfnode;
SELECT (-427463)::int::rdfnode::int;

SELECT 42::smallint::rdfnode;
SELECT 42::smallint::rdfnode::smallint;
SELECT (-42)::smallint::rdfnode;
SELECT (-42)::smallint::rdfnode::smallint;
SELECT 4273::smallint::rdfnode;
SELECT 4273::smallint::rdfnode::smallint;
SELECT (-4273)::smallint::rdfnode;
SELECT (-4273)::smallint::rdfnode::smallint;

/* timestamp <-> rdfnode round-trip */
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode::timestamptz;
SELECT '2025-04-25 18:44:38'::timestamptz::rdfnode;
SELECT '2025-04-25 18:44:38'::timestamptz::rdfnode::timestamptz;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode::timestamp;
SELECT '"0000-01-01T00:00:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode::timestamp;
SELECT '"-0043-03-15T00:00:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode::timestamp;
SELECT '"0000-12-31T23:59:59.999999"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode::timestamp::rdfnode;
SELECT '0044-03-15 BC'::timestamp::rdfnode;
SELECT '0044-03-15 BC'::timestamp::rdfnode::timestamp;
SELECT '0044-03-15 18:33:45 BC'::timestamp::rdfnode;
SELECT '0001-01-01 AD'::timestamp::rdfnode;
SELECT '0001-01-01 BC'::timestamp::rdfnode;
SELECT '0002-01-01 BC'::timestamp::rdfnode;
SELECT '0003-01-01 BC'::timestamp::rdfnode;
SELECT '0044-03-15 BC'::timestamp::rdfnode;
SELECT '0044-03-15 BC'::timestamp::rdfnode::timestamp;
SELECT '0044-03-15 18:33:45 BC'::timestamp::rdfnode::timestamp;
SELECT '0001-01-01 AD'::timestamp::rdfnode::timestamp;
SELECT '0001-01-01 BC'::timestamp::rdfnode::timestamp;
SELECT '0002-01-01 BC'::timestamp::rdfnode::timestamp;
SELECT '0003-01-01 BC'::timestamp::rdfnode::timestamp;
SELECT '0044-03-15 BC'::timestamp::rdfnode::timestamp;
SELECT '0044-03-15 18:33:45.123456 BC'::timestamp::rdfnode::timestamp;

/* timestamptz <-> rdfnode round-trip */
SET timezone = 'America/New_York';
SELECT '2025-04-25 18:44:38'::timestamptz::rdfnode;
SELECT '2025-04-25 18:44:38'::timestamptz::rdfnode::timestamptz;
SET timezone = 'UTC';
SELECT '"0000-01-01T00:00:00Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode::timestamptz;
SELECT '"-0001-01-01T00:00:00Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode::timestamptz;
SELECT '"-0043-03-15T12:34:56+02:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode::timestamptz;
SELECT '"-0043-03-15T12:34:56-05:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode::timestamptz;
SELECT '"0000-01-01T00:00:00Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode::timestamptz::rdfnode;
SELECT '0044-03-15 BC'::timestamptz::rdfnode;
SELECT '0044-03-15 18:33:45 BC'::timestamptz::rdfnode;
SELECT '0001-01-01 AD'::timestamptz::rdfnode;
SELECT '0001-01-01 BC'::timestamptz::rdfnode;
SELECT '0002-01-01 BC'::timestamptz::rdfnode;
SELECT '0003-01-01 BC'::timestamptz::rdfnode;
SELECT '0044-03-15 BC'::timestamptz::rdfnode;
SELECT '0044-03-15 BC'::timestamptz::rdfnode::timestamptz;
SELECT '0044-03-15 18:33:45 BC'::timestamptz::rdfnode::timestamptz;
SELECT '0001-01-01 AD'::timestamptz::rdfnode::timestamptz;
SELECT '0001-01-01 BC'::timestamptz::rdfnode::timestamptz;
SELECT '0002-01-01 BC'::timestamptz::rdfnode::timestamptz;
SELECT '0003-01-01 BC'::timestamptz::rdfnode::timestamptz;
SELECT '0044-03-15 BC'::timestamptz::rdfnode::timestamptz;
SELECT '0044-03-15 18:33:45.123456 BC'::timestamptz::rdfnode::timestamptz;

/* date <-> rdfnode round-trip */
SELECT '2020-05-12'::date::rdfnode;
SELECT '0001-01-01 AD'::date::rdfnode;
SELECT '0001-01-01 BC'::date::rdfnode;
SELECT '0002-01-01 BC'::date::rdfnode;
SELECT '0003-01-01 BC'::date::rdfnode;
SELECT '0044-03-15 BC'::date::rdfnode;
SELECT '2020-05-12'::date::rdfnode::date;
SELECT '0001-01-01 AD'::date::rdfnode::date;
SELECT '0001-01-01 BC'::date::rdfnode::date;
SELECT '0002-01-01 BC'::date::rdfnode::date;
SELECT '0003-01-01 BC'::date::rdfnode::date;
SELECT '0044-03-15 BC'::date::rdfnode::date;
SELECT '"0000-01-01"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode::date;
SELECT '"-0043-03-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode::date;
SELECT '"0000-01-01"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode::date::rdfnode;

SELECT '18:44:38'::time::rdfnode;
SELECT '18:44:38'::time::rdfnode::time;
SELECT '00:00:00'::time::rdfnode;
SELECT '00:00:00'::time::rdfnode::time;

SELECT '04:05:06-08:00'::timetz::rdfnode;
SELECT '04:05:06-08:00'::timetz::rdfnode::timetz;
SELECT '04:05:06 PST'::timetz::rdfnode;
SELECT '04:05:06 PST'::timetz::rdfnode::timetz;
SELECT '18:30:25.123456+02:00'::timetz::rdfnode;

SELECT true::rdfnode;
SELECT false::rdfnode;
SELECT true::rdfnode::boolean;
SELECT false::rdfnode::boolean;
SELECT (1=1)::rdfnode::boolean;
SELECT (1<>1)::rdfnode::boolean;

SELECT '1 day'::interval::rdfnode;
SELECT '1 hour 30 minutes'::interval::rdfnode;
SELECT '2 years 3 months'::interval::rdfnode;
SELECT '5 days 12 hours'::interval::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval::rdfnode;
SELECT '5.123456 seconds'::interval::rdfnode;
SELECT '0.000001 seconds'::interval::rdfnode;
SELECT '1 minute 0.5 seconds'::interval::rdfnode;
SELECT '-1 year -2 months'::interval::rdfnode;
SELECT '-3 days -4 hours'::interval::rdfnode;
SELECT '0 seconds'::interval::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval::rdfnode::interval;
SELECT '-1 year -2 months'::interval::rdfnode::interval;
SELECT '5.123456 seconds'::interval::rdfnode::interval;
SELECT '0 seconds'::interval::rdfnode::interval;
SELECT '0.000001 seconds'::interval::rdfnode::interval;

/* backslash runs of every parity, 0 through 8, immediately preceding
 * the closing quote of an otherwise plain literal */
SELECT n, (('"' || repeat('\', n) || '"'))::rdfnode = ((('"' || repeat('\', n) || '"'))::rdfnode)::text::rdfnode AS stable_roundtrip
FROM generate_series(0, 8) AS n
ORDER BY n;

/* the exact payload from the original report: a lexical value that is
 * two literal backslash characters */
SELECT (('"' || repeat('\', 4) || '"'))::rdfnode;

/* same backslash run, but immediately followed by a language tag --
 * must not be confused with part of the escape run */
SELECT (('"' || repeat('\', 4) || '"@en'))::rdfnode;

/* trailing content after a closing quote + language tag is rejected, not silently accepted */
SELECT '"x"@en } ; INSERT DATA { <http://evil/p> <http://evil/p> <http://evil/p> } #'::rdfnode;

/* already-escaped text must still not be double-escaped */
SELECT 'x\"y'::rdfnode;