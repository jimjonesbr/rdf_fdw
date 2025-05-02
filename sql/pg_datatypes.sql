SHOW datestyle;
SHOW timezone;

/* rdf_literal <-> rdf_literal */
SELECT '""'::rdf_literal = '""'::rdf_literal;
SELECT '""@en'::rdf_literal = '""@pt'::rdf_literal;
SELECT '"foo"'::rdf_literal = '"foo"'::rdf_literal;
SELECT '"foo"^^xsd:string'::rdf_literal = '"foo"^^xsd:string'::rdf_literal;
SELECT '"foo"^^xsd:string'::rdf_literal = '"foo"^^<http://www.w3.org/2001/XMLSchema#string>'::rdf_literal;
SELECT '"foo"@es'::rdf_literal = '"foo"@es'::rdf_literal;
SELECT '"foo"'::rdf_literal = '"foo"@de'::rdf_literal;
SELECT '"foo"@pt'::rdf_literal = '"foo"@de'::rdf_literal;
SELECT '"foo"@en'::rdf_literal = '"foo"@en-US'::rdf_literal;
SELECT '""'::rdf_literal <> '""'::rdf_literal;
SELECT '""@en'::rdf_literal <> '""@pt'::rdf_literal;
SELECT '"foo"'::rdf_literal <> '"foo"'::rdf_literal;
SELECT '"foo"^^xsd:string'::rdf_literal <> '"foo"^^xsd:string'::rdf_literal;
SELECT '"foo"@es'::rdf_literal <> '"foo"@es'::rdf_literal;
SELECT '"foo"'::rdf_literal <> '"foo"@de'::rdf_literal;
SELECT '"foo"@pt'::rdf_literal <> '"foo"@de'::rdf_literal;
SELECT '"foo"@en'::rdf_literal <> '"foo"@en-US'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal = '"42"^^xsd:int'::rdf_literal;
SELECT '"foo"@EN'::rdf_literal = '"foo"@en'::rdf_literal; -- Should return t (case-insensitive)
SELECT '"foo"@en-us'::rdf_literal = '"foo"@EN-US'::rdf_literal; -- Should return t
SELECT '"foo"@en'::rdf_literal = '"foo"@en-us'::rdf_literal; -- Should return f
SELECT '"café"@fr'::rdf_literal = '"café"@fr'::rdf_literal; -- Should return t
SELECT '"café"@fr'::rdf_literal = '"cafe"@fr'::rdf_literal; -- Should return f
SELECT '"\u0020"^^xsd:string'::rdf_literal = '" "^^xsd:string'::rdf_literal; -- Should return t (Unicode space)
SELECT '"foo"^^<http://example.org/custom>'::rdf_literal = '"foo"^^<http://example.org/custom>'::rdf_literal; -- Should return t (lexical comparison)
SELECT '"foo"^^<http://example.org/custom>'::rdf_literal = '"foo"^^xsd:string'::rdf_literal; -- Should return f
SELECT '"foo"^^<http://invalid>'::rdf_literal = '"foo"^^<http://invalid>'::rdf_literal; -- Should error or return t
SELECT '"42"^^xsd:int'::rdf_literal = '"42"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT '"-42"^^xsd:int'::rdf_literal = '"-42"^^xsd:int'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal = '"-42"^^xsd:int'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal = '"42.00"^^xsd:decimal'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal = '"42"^^xsd:integer'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal = '"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal = '"42.0000000000"^^xsd:double'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal = '"42"^^xsd:short'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal = '"42.73"^^xsd:decimal'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal = '"42.0000000001"^^xsd:double'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal = '"foo"^^xsd:string'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal = '"42"^^xsd:string'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal = '"42"^^xsd:date'::rdf_literal;
SELECT '"-0"^^xsd:int'::rdf_literal = '"0"^^xsd:int'::rdf_literal; -- Should return t (numeric zero)
SELECT '"999999999999999999"^^xsd:integer'::rdf_literal = '"999999999999999999.0"^^xsd:decimal'::rdf_literal; -- Should return t
SELECT '"2011-10-08"^^xsd:date'::rdf_literal = '"2011-10-08"^^xsd:date'::rdf_literal;
SELECT '"2011-10-08"^^xsd:date'::rdf_literal = '"2011-10-08"^^xsd:string'::rdf_literal;
SELECT '"2011-10-08"^^xsd:date'::rdf_literal = '"2011-10-08"'::rdf_literal;
SELECT '"2011-10-08"^^xsd:date'::rdf_literal = '"2011-10-08"'::rdf_literal;
SELECT '"2011-10-08"^^xsd:date'::rdf_literal = '"2011-10-11"^^xsd:date'::rdf_literal;
SELECT '"2011-10-08"^^xsd:date'::rdf_literal = '""^^xsd:date'::rdf_literal;
SELECT '"2011-10-08"^^xsd:date'::rdf_literal = '""'::rdf_literal;
SELECT '"2011-10-08"^^xsd:date'::rdf_literal = ''::rdf_literal;
SELECT '"0001-01-01"^^xsd:date'::rdf_literal = '"0001-01-01"^^xsd:date'::rdf_literal; -- Should return t
SELECT '"2025-13-01T12:00:00"^^xsd:dateTime'::rdf_literal = '"2025-13-01T12:00:00"^^xsd:dateTime'::rdf_literal; -- Should error (invalid month)
SELECT '"2025-04-25T25:00:00Z"^^xsd:dateTime'::rdf_literal = '"2025-04-25T25:00:00Z"^^xsd:dateTime'::rdf_literal; -- Should error (invalid hour)
SELECT '"1.0E308"^^xsd:double'::rdf_literal = '"1.0E308"^^xsd:double'::rdf_literal; -- Should return t or error if overflow
SELECT '"invalid"^^xsd:dateTime'::rdf_literal = '"invalid"^^xsd:dateTime'::rdf_literal; -- Should error
SELECT '"18:44:38"^^xsd:time'::rdf_literal = '"18:44:38"^^xsd:time'::rdf_literal;
SELECT '"18:44:38"^^xsd:time'::rdf_literal = '"18:44:38"^^<http://www.w3.org/2001/XMLSchema#time>'::rdf_literal;
SELECT '"18:44:38"^^xsd:time'::rdf_literal = '"20:44:38"^^xsd:time'::rdf_literal;
SELECT '"18:44:38"^^xsd:time'::rdf_literal = '"18:44:38"'::rdf_literal;
SELECT '"18:44:38"^^xsd:time'::rdf_literal = '"18:44:38"^^xsd:string'::rdf_literal;
SELECT '"18:44:38"^^xsd:time'::rdf_literal = '"foo"^^xsd:string'::rdf_literal;
SELECT '"18:44:38"^^xsd:time'::rdf_literal = '"foo"'::rdf_literal;
SELECT '"18:44:38"^^xsd:time'::rdf_literal = '""^^xsd:time'::rdf_literal;
SELECT '"18:44:38"^^xsd:time'::rdf_literal = '""'::rdf_literal;
SELECT '"18:44:38"^^xsd:time'::rdf_literal = ''::rdf_literal;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal = '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal = '"2025-04-25 18:44:38"^^<http://www.w3.org/2001/XMLSchema#time>'::rdf_literal;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal = '"2025-04-29 08:48:33"^^<http://www.w3.org/2001/XMLSchema#time>'::rdf_literal;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal = '"2025-04-25 18:44:38"'::rdf_literal;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal = '"2025-04-25 18:44:38"^^xsd:string'::rdf_literal;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal = '"foo"^^xsd:string'::rdf_literal;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal = '""^^xsd:dateTime'::rdf_literal;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal = '""'::rdf_literal;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal = ''::rdf_literal;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal = '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal = '"2025-04-25T18:44:38.149101Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdf_literal;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal = '"2025-04-29T18:44:38.149101Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdf_literal;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal = '"2025-04-25T18:44:38.149101Z"'::rdf_literal;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal = '"2025-04-25T18:44:38.149101Z"^^xsd:string'::rdf_literal;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal = '"foo"^^xsd:string'::rdf_literal;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal = '""^^xsd:string'::rdf_literal;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal = '""'::rdf_literal;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal = ''::rdf_literal;
SELECT '"2025-04-25T18:44:38"^^xsd:dateTime'::rdf_literal = '"2025-04-25T18:44:38Z"^^xsd:dateTime'::rdf_literal; -- Should return t (missing timezone as UTC)
SELECT '"2025-04-25T18:44:38+01:00"^^xsd:dateTime'::rdf_literal = '"2025-04-25T17:44:38Z"^^xsd:dateTime'::rdf_literal; -- Should return t (same UTC moment)
SELECT '"2025-04-25T18:44:38-04:00"^^xsd:dateTime'::rdf_literal = '"2025-04-25T22:44:38Z"^^xsd:dateTime'::rdf_literal; -- Should return t
SELECT '"2025-04-25T18:44:38"^^xsd:dateTime'::rdf_literal = '"2025-04-25T18:44:38+01:00"^^xsd:dateTime'::rdf_literal; -- Should return f (UTC vs. +01:00)
SELECT '"0001-01-01T00:00:00Z"^^xsd:dateTime'::rdf_literal = '"0001-01-01T00:00:00Z"^^xsd:dateTime'::rdf_literal; -- Should return t
SELECT '"9999-12-31T23:59:59Z"^^xsd:dateTime'::rdf_literal = '"9999-12-31T23:59:59Z"^^xsd:dateTime'::rdf_literal; -- Should return t
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal = '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal = '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal = '"P5Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal = '"P1Y2M3DT4H5M6S"^^xsd:string'::rdf_literal;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal = '"P1Y2M3DT4H5M6S"'::rdf_literal;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal = '"foo"^^xsd:string'::rdf_literal;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal = '""^^xsd:string'::rdf_literal;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal = '""'::rdf_literal;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal = ''::rdf_literal;
SELECT '"P12M"^^xsd:duration'::rdf_literal = '"P1Y"^^xsd:duration'::rdf_literal;
SELECT '"PT3600S"^^xsd:duration'::rdf_literal = '"PT1H"^^xsd:duration'::rdf_literal;
SELECT '"P1DT24H"^^xsd:duration'::rdf_literal = '"P2D"^^xsd:duration'::rdf_literal;
SELECT '"P1Y"^^xsd:duration'::rdf_literal = '"P2Y"^^xsd:duration'::rdf_literal;

/* numeric <-> rdf_literal*/
SELECT '"9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal::numeric;
SELECT '"-9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal::numeric;
SELECT '"9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal::numeric::rdf_literal;
SELECT '"-9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal::numeric::rdf_literal;
SELECT '"9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal = 9223372036854775.807;
SELECT '"9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal <> 9223372036854775.807;
SELECT '"-9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal <> -9223372036854775.807;
SELECT '"9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal != 9223372036854775.807;
SELECT '"9223372036854776"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal > 9223372036854775.999;
SELECT '"9223372036854776"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal < 9223372036854775.999;
SELECT '"42.000000000000000000"^^xsd:decimal'::rdf_literal = 42::numeric;
SELECT '"0.000000000000000001"^^xsd:decimal'::rdf_literal > 0::numeric;
SELECT '"-0.000000000000000001"^^xsd:decimal'::rdf_literal < 0::numeric;
SELECT '"-0.0"^^xsd:decimal'::rdf_literal = 0::numeric;
SELECT 9223372036854775.807 = '"9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal;
SELECT -9223372036854775.807 = '"-9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal;
SELECT 9223372036854775.807 <> '"9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal;
SELECT 9223372036854775.807 != '"9223372036854775.807"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal;
SELECT 9223372036854775.999 > '"9223372036854776.000"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal;
SELECT 9223372036854775.999 < '"9223372036854776.000"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdf_literal;
SELECT 42::numeric = '"42.000000000000000000"^^xsd:decimal'::rdf_literal;
SELECT 0::numeric > '"0.000000000000000001"^^xsd:decimal'::rdf_literal;
SELECT 0::numeric < '"-0.000000000000000001"^^xsd:decimal'::rdf_literal;
SELECT 0::numeric ='"-0.0"^^xsd:decimal'::rdf_literal;

/* double precision (float8) <-> rdf_literal */
SELECT '"42.73"^^xsd:double'::rdf_literal::double precision = 42.73000::double precision;
SELECT '"42.73"^^xsd:double'::rdf_literal::double precision <> 42.73000::double precision;
SELECT '"42.73"^^xsd:double'::rdf_literal::double precision > 42.999999::double precision;
SELECT '"42.73"^^xsd:double'::rdf_literal::double precision < 42.999999::double precision;
SELECT '"4.2E1"^^xsd:double'::rdf_literal = 42.0::double precision;
SELECT '"4.2000001E1"^^xsd:double'::rdf_literal > 42.0::double precision;
SELECT '"4.1999999E1"^^xsd:double'::rdf_literal < 42.0::double precision;
SELECT '"0.0"^^xsd:double'::rdf_literal = '-0.0'::double precision;
SELECT '"NaN"^^xsd:double'::rdf_literal != 0::double precision;
SELECT '"Infinity"^^xsd:double'::rdf_literal > 1e308::double precision;
SELECT '"-Infinity"^^xsd:double'::rdf_literal < -1e308::double precision;
SELECT 42.73000::double precision = '"42.73"^^xsd:double'::rdf_literal::double precision;
SELECT 42.73000::double precision <> '"42.73"^^xsd:double'::rdf_literal::double precision;
SELECT 42.999999::double precision >'"42.73"^^xsd:double'::rdf_literal::double precision;
SELECT 42.999999::double precision < '"42.73"^^xsd:double'::rdf_literal::double precision;
SELECT 42.0::double precision = '"4.2E1"^^xsd:double'::rdf_literal;
SELECT 42.0::double precision > '"4.2000001E1"^^xsd:double'::rdf_literal;
SELECT 42.0::double precision < '"4.1999999E1"^^xsd:double'::rdf_literal;
SELECT '-0.0'::double precision = '"0.0"^^xsd:double'::rdf_literal;
SELECT 0::double precision != '"NaN"^^xsd:double'::rdf_literal;
SELECT 1e308::double precision > '"Infinity"^^xsd:double'::rdf_literal;
SELECT -1e308::double precision < '"-Infinity"^^xsd:double'::rdf_literal;

/* real (float4) <-> rdf_literal */
SELECT '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal = 42.73::real;
SELECT '"42.00"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal = 42::real;
SELECT '"42.0000000000000000"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal = 42::real;
SELECT '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal = -42.73::real;
SELECT '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal <> 42.73::real;
SELECT '"42.00"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal <> 42::real;
SELECT '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal > 43.00::real;
SELECT '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal > -43.00::real;
SELECT '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal < 43.00::real;
SELECT '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal < -43.00::real;
SELECT '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal >= 43.00::real;
SELECT '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal >= -43.00::real;
SELECT '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal <= 43.00::real;
SELECT '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal <= -43.00::real;
SELECT 42.73::real = '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT 42::real = '"42.00"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT 42::real = '"42.0000000000000000"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT -42.73::real = '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT 42.73::real <> '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT 42::real <>'"42.00"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT 43.00::real > '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT -43.00::real > '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT 43.00::real < '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT -43.00::real < '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT 43.00::real >= '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT -43.00::real >= '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT 43.00::real <= '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;
SELECT -43.00::real <= '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdf_literal;

/* bigint (int8) <-> rdf_literal */
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal = 42746357267238768;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal = -42746357267238768;
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal <> 42746357267238768;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal <> -42746357267238768;
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal != 42746357267238768;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal != -42746357267238768;
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal > 42746357267238799;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal > -42746357267238799;
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal < 42746357267238799;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal < -42746357267238799;
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal >= 42746357267238799;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal >= -42746357267238799;
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal <= 42746357267238799;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal <= -42746357267238799;
SELECT 42746357267238768 ='"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT -42746357267238768 = '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT 42746357267238768 <> '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT -42746357267238768 <> '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT 42746357267238768 != '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT -42746357267238768 != '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT 42746357267238799 > '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT -42746357267238799 > '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT 42746357267238799 < '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT -42746357267238799 < '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT 42746357267238799 >= '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT -42746357267238799 >= '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT 42746357267238799 <= '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;
SELECT -42746357267238799 <= '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdf_literal;

/* int (int4) <-> rdf_literal */
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal = 427463::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal = -427463::int;
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal <> 427463::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal <> -427463::int;
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal != 427463::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal != -427463::int;
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal > 427464::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal > -427464::int;
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal < 427464::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal < -427464::int;
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal >= 427464::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal >= -427464::int;
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal <= 427464::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal <= -427464::int;
SELECT 427463::int = '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT -427463::int = '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT 427463::int <> '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT -427463::int <> '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT 427463::int != '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT -427463::int != '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT 427464::int > '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT -427464::int > '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT 427464::int <'"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT -427464::int < '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT 427464::int >= '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT -427464::int >= '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT 427464::int <='"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT -427464::int <= '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT '"2147483648"^^xsd:int'::rdf_literal::int; -- must fail: out of range for type integer

/* smallint (int2) <-> rdf_literal */
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal = 4273::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal = -4273::smallint;
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal <> 4273::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal <> -4273::smallint;
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal != 4273::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal != -4273::smallint;
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal > 4274::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal > -4274::smallint;
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal < 4274::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal < -4274::smallint;
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal >= 4274::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal >= -4274::smallint;
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal <= 4274::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal <= -4274::smallint;
SELECT 4273::smallint = '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT -4273::smallint = '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT 4273::smallint <> '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT -4273::smallint <> '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT 4273::smallint != '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT -4273::smallint != '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT 4274::smallint > '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT -4274::smallint > '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT 4274::smallint <'"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT -4274::smallint < '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT 4274::smallint >= '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT -4274::smallint >= '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT 4274::smallint <='"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT -4274::smallint <= '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdf_literal;
SELECT '"32767"^^xsd:short'::rdf_literal = 32767::smallint;
SELECT '"-32768"^^xsd:short'::rdf_literal = -32768::smallint;
SELECT '"32768"^^xsd:short'::rdf_literal::smallint;

/* timestamptz (timestamp with time zone) <-> rdf_literal */
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal = '2025-04-25 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal <> '2025-04-26 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal != '2025-04-26 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal > '2025-04-26 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal < '2025-04-26 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal >= '2025-04-26 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal <= '2025-04-26 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz = '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal;
SELECT '2025-04-26 18:44:38.149101+00'::timestamptz <> '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal;
SELECT '2025-04-26 18:44:38.149101+00'::timestamptz != '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal;
SELECT '2025-04-26 18:44:38.149101+00'::timestamptz > '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal;
SELECT '2025-04-26 18:44:38.149101+00'::timestamptz < '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal;
SELECT '2025-04-26 18:44:38.149101+00'::timestamptz >= '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal;
SELECT '2025-04-26 18:44:38.149101+00'::timestamptz <= '2025-04-25 18:44:38.149101+00'::timestamptz::rdf_literal;

/* timestamp (timestamp with time zone) <-> rdf_literal */
SELECT '2025-04-25 18:44:38'::timestamp::rdf_literal = '2025-04-25 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdf_literal <> '2025-04-26 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdf_literal != '2025-04-26 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdf_literal > '2025-04-26 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdf_literal < '2025-04-26 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdf_literal >= '2025-04-26 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdf_literal <= '2025-04-26 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp = '2025-04-25 18:44:38'::timestamp::rdf_literal;
SELECT '2025-04-26 18:44:38'::timestamp <> '2025-04-25 18:44:38'::timestamp::rdf_literal;
SELECT '2025-04-26 18:44:38'::timestamp != '2025-04-25 18:44:38'::timestamp::rdf_literal;
SELECT '2025-04-26 18:44:38'::timestamp > '2025-04-25 18:44:38'::timestamp::rdf_literal;
SELECT '2025-04-26 18:44:38'::timestamp < '2025-04-25 18:44:38'::timestamp::rdf_literal;
SELECT '2025-04-26 18:44:38'::timestamp >= '2025-04-25 18:44:38'::timestamp::rdf_literal;
SELECT '2025-04-26 18:44:38'::timestamp <= '2025-04-25 18:44:38'::timestamp::rdf_literal;

/* date <-> rdf_literal */
SELECT '2020-05-12'::date::rdf_literal = '2020-05-12'::date;
SELECT '2020-05-12'::date::rdf_literal <> '2020-05-12'::date;
SELECT '2020-05-12'::date::rdf_literal != '2020-05-12'::date;
SELECT '2020-05-12'::date::rdf_literal > '2020-05-13'::date;
SELECT '2020-05-12'::date::rdf_literal < '2020-05-13'::date;
SELECT '2020-05-12'::date::rdf_literal >= '2020-05-13'::date;
SELECT '2020-05-12'::date::rdf_literal <= '2020-05-13'::date;
SELECT '2020-05-12'::date = '2020-05-12'::date::rdf_literal;
SELECT '2020-05-12'::date <> '2020-05-12'::date::rdf_literal;
SELECT '2020-05-12'::date != '2020-05-12'::date::rdf_literal;
SELECT '2020-05-13'::date > '2020-05-12'::date::rdf_literal;
SELECT '2020-05-13'::date < '2020-05-12'::date::rdf_literal;
SELECT '2020-05-13'::date >= '2020-05-12'::date::rdf_literal;
SELECT '2020-05-13'::date <= '2020-05-12'::date::rdf_literal;
SELECT '"invalid"^^xsd:date'::rdf_literal::date;
SELECT '"2020-13-01"^^xsd:date'::rdf_literal::date;
SELECT '0001-01-01'::date::rdf_literal = '0001-01-01'::date;
SELECT '9999-12-31'::date::rdf_literal = '9999-12-31'::date;

/* time (without time zone) <-> rdf_literal */
SELECT '18:44:38'::time::rdf_literal = '18:44:38'::time;
SELECT '18:44:38'::time::rdf_literal <> '18:44:38'::time;
SELECT '18:44:38'::time::rdf_literal != '18:44:38'::time;
SELECT '18:44:38'::time::rdf_literal > '18:44:59'::time;
SELECT '18:44:38'::time::rdf_literal < '18:44:59'::time;
SELECT '18:44:38'::time::rdf_literal >= '18:44:59'::time;
SELECT '18:44:38'::time::rdf_literal <= '18:44:59'::time;
SELECT '18:44:38'::time = '18:44:38'::time::rdf_literal;
SELECT '18:44:38'::time <> '18:44:38'::time::rdf_literal;
SELECT '18:44:38'::time != '18:44:38'::time::rdf_literal;
SELECT '18:44:59'::time > '18:44:38'::time::rdf_literal;
SELECT '18:44:59'::time < '18:44:38'::time::rdf_literal;
SELECT '18:44:59'::time >= '18:44:38'::time::rdf_literal;
SELECT '18:44:59'::time <= '18:44:38'::time::rdf_literal;
SELECT '-18:44:38'::time::rdf_literal;
SELECT 'invalid'::time::rdf_literal;

/* timetz (with time zone) <-> rdf_literal */
SELECT '04:05:06-08:00'::timetz::rdf_literal = '04:05:06-08:00'::timetz;
SELECT '04:05:06-08:00'::timetz::rdf_literal <> '04:05:06-08:00'::timetz;
SELECT '04:05:06-08:00'::timetz::rdf_literal != '04:05:06-08:00'::timetz;
SELECT '12:05:06-08:00'::timetz::rdf_literal > '04:05:06-08:00'::timetz;
SELECT '12:05:06-08:00'::timetz::rdf_literal < '04:05:06-08:00'::timetz;
SELECT '12:05:06-08:00'::timetz::rdf_literal >= '04:05:06-08:00'::timetz;
SELECT '12:05:06-08:00'::timetz::rdf_literal <= '04:05:06-08:00'::timetz;
SELECT '04:05:06-08:00'::timetz = '04:05:06-08:00'::timetz::rdf_literal;
SELECT '04:05:06-08:00'::timetz <> '04:05:06-08:00'::timetz::rdf_literal;
SELECT '04:05:06-08:00'::timetz != '04:05:06-08:00'::timetz::rdf_literal;
SELECT '04:05:06-08:00'::timetz > '12:05:06-08:00'::timetz::rdf_literal;
SELECT '04:05:06-08:00'::timetz < '12:05:06-08:00'::timetz::rdf_literal;
SELECT '04:05:06-08:00'::timetz >= '12:05:06-08:00'::timetz::rdf_literal;
SELECT '04:05:06-08:00'::timetz <= '12:05:06-08:00'::timetz::rdf_literal;

/* boolean <-> rdf_literal */
SELECT true::rdf_literal;
SELECT false::rdf_literal;
SELECT true::rdf_literal::boolean;
SELECT false::rdf_literal::boolean;
SELECT (1=1)::rdf_literal::boolean;
SELECT (1<>1)::rdf_literal::boolean;

/* interval <-> rdf_literal */
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal = '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal = '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1"^^xsd:duration'::rdf_literal <> '12 months'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal <> '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal <> '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1"^^xsd:duration'::rdf_literal != '12 months'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal != '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal != '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1"^^xsd:duration'::rdf_literal > '12 months'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal > '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal > '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1"^^xsd:duration'::rdf_literal < '12 months'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal < '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal < '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1"^^xsd:duration'::rdf_literal >= '12 months'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal >= '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal >= '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1"^^xsd:duration'::rdf_literal <= '12 months'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal <= '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal <= '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '12 months'::interval = '"P1"^^xsd:duration'::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval = '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval = '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal;
SELECT '12 months'::interval <> '"P1"^^xsd:duration'::rdf_literal;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal <> '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval <> '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal;
SELECT '12 months'::interval != '"P1"^^xsd:duration'::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval != '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval != '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal;

SELECT '12 months'::interval > '"P1"^^xsd:duration'::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval > '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval > '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal;
SELECT '12 months'::interval < '"P1"^^xsd:duration'::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval <'"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval < '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal;
SELECT '12 months'::interval >= '"P1"^^xsd:duration'::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval >= '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval >= '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal;
SELECT '12 months'::interval <= '"P1"^^xsd:duration'::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval <= '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdf_literal;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval <= '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdf_literal;
