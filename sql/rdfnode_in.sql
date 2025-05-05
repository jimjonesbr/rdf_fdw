
SELECT '"foo"'::rdfnode;
SELECT '"foo"^^xsd:string'::rdfnode;
SELECT '"foo"@es'::rdfnode;
SELECT '"foo"@es'::rdfnode::text;
SELECT '"foo"@es'::rdfnode::text::rdfnode;
SELECT '"foo"^^xsd:string'::rdfnode::text::rdfnode;
SELECT '"nan"^^xsd:double'::rdfnode;
SELECT '"NAN"^^xsd:double'::rdfnode;
SELECT '"nAn"^^xsd:double'::rdfnode;
SELECT '"forty-two"^^xsd:int'::rdfnode;
SELECT '"invalid"^^xsd:dateTime'::rdfnode;
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
SELECT '"x^^y"'::rdfnode;           -- → "x^^y"
SELECT '"a\\"b"@en'::rdfnode;       -- → "a\"b"@en
SELECT '"𝄞"^^<http://example.org/dt>'::rdfnode;


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

SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode::timestamptz;
SELECT '2025-04-25 18:44:38'::timestamptz::rdfnode;
SELECT '2025-04-25 18:44:38'::timestamptz::rdfnode::timestamptz;

SELECT '2025-04-25 18:44:38'::timestamp::rdfnode;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode::timestamp;

SELECT '2020-05-12'::date::rdfnode;
SELECT '2020-05-12'::date::rdfnode::date;

SELECT '18:44:38'::time::rdfnode;
SELECT '18:44:38'::time::rdfnode::time;
SELECT '00:00:00'::time::rdfnode;
SELECT '00:00:00'::time::rdfnode::time;

SELECT '04:05:06-08:00'::timetz::rdfnode;
SELECT '04:05:06-08:00'::timetz::rdfnode::timetz;
SELECT '04:05:06 PST'::timetz::rdfnode;
SELECT '04:05:06 PST'::timetz::rdfnode::timetz;

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