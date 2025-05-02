
SELECT '"foo"'::rdf_literal;
SELECT '"foo"^^xsd:string'::rdf_literal;
SELECT '"foo"@es'::rdf_literal;
SELECT '"foo"@es'::rdf_literal::text;
SELECT '"foo"@es'::rdf_literal::text::rdf_literal;
SELECT '"foo"^^xsd:string'::rdf_literal::text::rdf_literal;
SELECT '"nan"^^xsd:double'::rdf_literal;
SELECT '"NAN"^^xsd:double'::rdf_literal;
SELECT '"nAn"^^xsd:double'::rdf_literal;
SELECT '"forty-two"^^xsd:int'::rdf_literal;
SELECT '"invalid"^^xsd:dateTime'::rdf_literal;
SELECT '"25:00:00"^^xsd:time'::rdf_literal;
SELECT '"2025-13-01"^^xsd:date'::rdf_literal;
SELECT '"abc"^^invalid:datatype'::rdf_literal;
SELECT '"abc"@invalid_lang'::rdf_literal;
SELECT '"foo'::rdf_literal;
SELECT 'f"o"o'::rdf_literal;
SELECT '𝄞'::rdf_literal;
SELECT ''::rdf_literal;
SELECT '"'::rdf_literal; 
SELECT '"\""'::rdf_literal;
SELECT '😀'::rdf_literal;
SELECT '"x^^y"'::rdf_literal;           -- → "x^^y"
SELECT '"a\\"b"@en'::rdf_literal;       -- → "a\"b"@en
SELECT '"𝄞"^^<http://example.org/dt>'::rdf_literal;


SELECT '"9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal::numeric;
SELECT '"-9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal::numeric;
SELECT '"9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal::numeric::rdf_literal;
SELECT '"-9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal::numeric::rdf_literal;

SELECT '"42.73"^^xsd:double'::rdf_literal::double precision;
SELECT '"-42.73"^^xsd:double'::rdf_literal::double precision;
SELECT '"42.73"^^xsd:double'::rdf_literal::double precision::rdf_literal;
SELECT '"-42.73"^^xsd:double'::rdf_literal::double precision::rdf_literal;
SELECT '"4.2E1"^^xsd:double'::rdf_literal::double precision;
SELECT '"-4.2E1"^^xsd:double'::rdf_literal::double precision;

SELECT 42.73::real::rdf_literal;
SELECT 42.73::real::rdf_literal::real;
SELECT (-42.73)::real::rdf_literal;
SELECT (-42.73)::real::rdf_literal::real;
SELECT 'INF'::real::rdf_literal;
SELECT 'INF'::real::rdf_literal::real;
SELECT '-INF'::real::rdf_literal;
SELECT '-INF'::real::rdf_literal::real;
SELECT 'NaN'::real::rdf_literal;
SELECT 'NaN'::real::rdf_literal::real;

SELECT 42::bigint::rdf_literal;
SELECT 42::bigint::rdf_literal::bigint;
SELECT (-42)::bigint::rdf_literal;
SELECT (-42)::bigint::rdf_literal::bigint;
SELECT 42746357267238767::bigint::rdf_literal;
SELECT 42746357267238767::bigint::rdf_literal::bigint;
SELECT (-42746357267238767)::bigint::rdf_literal;
SELECT (-42746357267238767)::bigint::rdf_literal::bigint;

SELECT 42::int::rdf_literal;
SELECT 42::int::rdf_literal::int;
SELECT (-42)::int::rdf_literal;
SELECT (-42)::int::rdf_literal::int;
SELECT 427463::int::rdf_literal;
SELECT 427463::int::rdf_literal::int;
SELECT (-427463)::int::rdf_literal;
SELECT (-427463)::int::rdf_literal::int;

SELECT 42::smallint::rdf_literal;
SELECT 42::smallint::rdf_literal::smallint;
SELECT (-42)::smallint::rdf_literal;
SELECT (-42)::smallint::rdf_literal::smallint;
SELECT 4273::smallint::rdf_literal;
SELECT 4273::smallint::rdf_literal::smallint;
SELECT (-4273)::smallint::rdf_literal;
SELECT (-4273)::smallint::rdf_literal::smallint;

SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal::timestamptz;
SELECT '2025-04-25 18:44:38'::timestamptz::rdf_literal;
SELECT '2025-04-25 18:44:38'::timestamptz::rdf_literal::timestamptz;

SELECT '2025-04-25 18:44:38'::timestamp::rdf_literal;
SELECT '2025-04-25 18:44:38'::timestamp::rdf_literal::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdf_literal;
SELECT '2025-04-25 18:44:38'::timestamp::rdf_literal::timestamp;

SELECT '2020-05-12'::date::rdf_literal;
SELECT '2020-05-12'::date::rdf_literal::date;

SELECT '18:44:38'::time::rdf_literal;
SELECT '18:44:38'::time::rdf_literal::time;
SELECT '00:00:00'::time::rdf_literal;
SELECT '00:00:00'::time::rdf_literal::time;

SELECT '04:05:06-08:00'::timetz::rdf_literal;
SELECT '04:05:06-08:00'::timetz::rdf_literal::timetz;
SELECT '04:05:06 PST'::timetz::rdf_literal;
SELECT '04:05:06 PST'::timetz::rdf_literal::timetz;

SELECT true::rdf_literal;
SELECT false::rdf_literal;
SELECT true::rdf_literal::boolean;
SELECT false::rdf_literal::boolean;
SELECT (1=1)::rdf_literal::boolean;
SELECT (1<>1)::rdf_literal::boolean;

SELECT '1 day'::interval::rdf_literal;
SELECT '1 hour 30 minutes'::interval::rdf_literal;
SELECT '2 years 3 months'::interval::rdf_literal;
SELECT '5 days 12 hours'::interval::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval::rdf_literal;
SELECT '5.123456 seconds'::interval::rdf_literal;
SELECT '0.000001 seconds'::interval::rdf_literal;
SELECT '1 minute 0.5 seconds'::interval::rdf_literal;
SELECT '-1 year -2 months'::interval::rdf_literal;
SELECT '-3 days -4 hours'::interval::rdf_literal;
SELECT '0 seconds'::interval::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval::rdf_literal::interval;
SELECT '-1 year -2 months'::interval::rdf_literal::interval;
SELECT '5.123456 seconds'::interval::rdf_literal::interval;
SELECT '0 seconds'::interval::rdf_literal::interval;
SELECT '0.000001 seconds'::interval::rdf_literal::interval;