\set VERBOSITY terse
SHOW datestyle;
SHOW timezone;

/* rdfnode <-> rdfnode */
SELECT '""'::rdfnode = '""'::rdfnode;
SELECT '""@en'::rdfnode = '""@pt'::rdfnode;
SELECT '"foo"'::rdfnode = '"foo"'::rdfnode;
SELECT '"foo"^^xsd:string'::rdfnode = '"foo"^^xsd:string'::rdfnode;
SELECT '"foo"^^xsd:string'::rdfnode = '"foo"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode;
SELECT '"foo"@es'::rdfnode = '"foo"@es'::rdfnode;
SELECT '"foo"'::rdfnode = '"foo"@de'::rdfnode;
SELECT '"foo"@pt'::rdfnode = '"foo"@de'::rdfnode;
SELECT '"foo"@en'::rdfnode = '"foo"@en-US'::rdfnode;
SELECT '""'::rdfnode <> '""'::rdfnode;
SELECT '""@en'::rdfnode <> '""@pt'::rdfnode;
SELECT '"foo"'::rdfnode <> '"foo"'::rdfnode;
SELECT '"foo"^^xsd:string'::rdfnode <> '"foo"^^xsd:string'::rdfnode;
SELECT '"foo"@es'::rdfnode <> '"foo"@es'::rdfnode;
SELECT '"foo"'::rdfnode <> '"foo"@de'::rdfnode;
SELECT '"foo"@pt'::rdfnode <> '"foo"@de'::rdfnode;
SELECT '"foo"@en'::rdfnode <> '"foo"@en-US'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode = '"42"^^xsd:int'::rdfnode;
SELECT '"foo"@EN'::rdfnode = '"foo"@en'::rdfnode; -- Should return t (case-insensitive)
SELECT '"foo"@en-us'::rdfnode = '"foo"@EN-US'::rdfnode; -- Should return t
SELECT '"foo"@en'::rdfnode = '"foo"@en-us'::rdfnode; -- Should return f
SELECT '"café"@fr'::rdfnode = '"café"@fr'::rdfnode; -- Should return t
SELECT '"café"@fr'::rdfnode = '"cafe"@fr'::rdfnode; -- Should return f
SELECT '"\u0020"^^xsd:string'::rdfnode = '" "^^xsd:string'::rdfnode; -- Should return t (Unicode space)
SELECT '"foo"^^<http://example.org/custom>'::rdfnode = '"foo"^^<http://example.org/custom>'::rdfnode; -- Should return t (lexical comparison)
SELECT '"foo"^^<http://example.org/custom>'::rdfnode = '"foo"^^xsd:string'::rdfnode; -- Should return f
SELECT '"foo"^^<http://invalid>'::rdfnode = '"foo"^^<http://invalid>'::rdfnode; -- Should error or return t
SELECT '"42"^^xsd:int'::rdfnode = '"42"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT '"-42"^^xsd:int'::rdfnode = '"-42"^^xsd:int'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode = '"-42"^^xsd:int'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode = '"42.00"^^xsd:decimal'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode = '"42"^^xsd:integer'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode = '"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode = '"42.0000000000"^^xsd:double'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode = '"42"^^xsd:short'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode = '"42.73"^^xsd:decimal'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode = '"42.0000000001"^^xsd:double'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode = '"foo"^^xsd:string'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode = '"42"^^xsd:string'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode = '"42"^^xsd:date'::rdfnode;
SELECT '"-0"^^xsd:int'::rdfnode = '"0"^^xsd:int'::rdfnode; -- Should return t (numeric zero)
SELECT '"999999999999999999"^^xsd:integer'::rdfnode = '"999999999999999999.0"^^xsd:decimal'::rdfnode; -- Should return t
SELECT '"2011-10-08"^^xsd:date'::rdfnode = '"2011-10-08"^^xsd:date'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode = '"2011-10-08"^^xsd:string'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode = '"2011-10-08"'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode = '"2011-10-08"'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode = '"2011-10-11"^^xsd:date'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode = '""^^xsd:date'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode = '""'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode = ''::rdfnode;
SELECT '"0001-01-01"^^xsd:date'::rdfnode = '"0001-01-01"^^xsd:date'::rdfnode; -- Should return t
SELECT '"2025-13-01T12:00:00"^^xsd:dateTime'::rdfnode = '"2025-13-01T12:00:00"^^xsd:dateTime'::rdfnode; -- Should error (invalid month)
SELECT '"2025-04-25T25:00:00Z"^^xsd:dateTime'::rdfnode = '"2025-04-25T25:00:00Z"^^xsd:dateTime'::rdfnode; -- Should error (invalid hour)
SELECT '"1.0E308"^^xsd:double'::rdfnode = '"1.0E308"^^xsd:double'::rdfnode; -- Should return t or error if overflow
SELECT '"invalid"^^xsd:dateTime'::rdfnode = '"invalid"^^xsd:dateTime'::rdfnode; -- Should error
SELECT '"18:44:38"^^xsd:time'::rdfnode = '"18:44:38"^^xsd:time'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode = '"18:44:38"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode = '"20:44:38"^^xsd:time'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode = '"18:44:38"'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode = '"18:44:38"^^xsd:string'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode = '"foo"^^xsd:string'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode = '"foo"'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode = '""^^xsd:time'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode = '""'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode = ''::rdfnode;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode = '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode = '"2025-04-25 18:44:38"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode = '"2025-04-29 08:48:33"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode = '"2025-04-25 18:44:38"'::rdfnode;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode = '"2025-04-25 18:44:38"^^xsd:string'::rdfnode;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode = '"foo"^^xsd:string'::rdfnode;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode = '""^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode = '""'::rdfnode;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode = ''::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode = '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode = '"2025-04-25T18:44:38.149101Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode = '"2025-04-29T18:44:38.149101Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode = '"2025-04-25T18:44:38.149101Z"'::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode = '"2025-04-25T18:44:38.149101Z"^^xsd:string'::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode = '"foo"^^xsd:string'::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode = '""^^xsd:string'::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode = '""'::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode = ''::rdfnode;
SELECT '"2025-04-25T18:44:38"^^xsd:dateTime'::rdfnode = '"2025-04-25T18:44:38Z"^^xsd:dateTime'::rdfnode; -- Should return t (missing timezone as UTC)
SELECT '"2025-04-25T18:44:38+01:00"^^xsd:dateTime'::rdfnode = '"2025-04-25T17:44:38Z"^^xsd:dateTime'::rdfnode; -- Should return t (same UTC moment)
SELECT '"2025-04-25T18:44:38-04:00"^^xsd:dateTime'::rdfnode = '"2025-04-25T22:44:38Z"^^xsd:dateTime'::rdfnode; -- Should return t
SELECT '"2025-04-25T18:44:38"^^xsd:dateTime'::rdfnode = '"2025-04-25T18:44:38+01:00"^^xsd:dateTime'::rdfnode; -- Should return f (UTC vs. +01:00)
SELECT '"0001-01-01T00:00:00Z"^^xsd:dateTime'::rdfnode = '"0001-01-01T00:00:00Z"^^xsd:dateTime'::rdfnode; -- Should return t
SELECT '"9999-12-31T23:59:59Z"^^xsd:dateTime'::rdfnode = '"9999-12-31T23:59:59Z"^^xsd:dateTime'::rdfnode; -- Should return t
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode = '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode = '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode = '"P5Y2M3DT4H5M6S"^^xsd:duration'::rdfnode;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode = '"P1Y2M3DT4H5M6S"^^xsd:string'::rdfnode;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode = '"P1Y2M3DT4H5M6S"'::rdfnode;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode = '"foo"^^xsd:string'::rdfnode;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode = '""^^xsd:string'::rdfnode;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode = '""'::rdfnode;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode = ''::rdfnode;
SELECT '"P12M"^^xsd:duration'::rdfnode = '"P1Y"^^xsd:duration'::rdfnode;
SELECT '"PT3600S"^^xsd:duration'::rdfnode = '"PT1H"^^xsd:duration'::rdfnode;
SELECT '"P1DT24H"^^xsd:duration'::rdfnode = '"P2D"^^xsd:duration'::rdfnode;
SELECT '"P1Y"^^xsd:duration'::rdfnode = '"P2Y"^^xsd:duration'::rdfnode;

/* numeric <-> rdfnode*/
SELECT '"123456789.123"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode::numeric;
SELECT '"-123456789.123"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode::numeric;
SELECT '"123456789.123"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode::numeric::rdfnode;
SELECT '"-123456789.123"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode::numeric::rdfnode;
SELECT '"123456789.123"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode = 123456789.123;
SELECT '"123456789.123"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode <> 123456789.123;
SELECT '"-123456789.123"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode <> -123456789.123;
SELECT '"123456789.123"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode != 123456789.123;
SELECT '"922337"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode > 922337203.999;
SELECT '"922337"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode < 922337203.999;
SELECT '"42.000000"^^xsd:decimal'::rdfnode = 42::numeric;
SELECT '"0.0000001"^^xsd:decimal'::rdfnode > 0::numeric;
SELECT '"-0.000001"^^xsd:decimal'::rdfnode < 0::numeric;
SELECT '"-0.0"^^xsd:decimal'::rdfnode = 0::numeric;
SELECT 123456789.123 = '"123456789.123"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode;
SELECT -123456789.123 = '"-123456789.123"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode;
SELECT 123456789.123 <> '"123456789.123"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode;
SELECT 123456789.123 != '"123456789.123"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode;
SELECT 922337203.999 > '"922337203.000"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode;
SELECT 922337203.999 < '"922337203.000"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode;
SELECT 42::numeric = '"42.00000"^^xsd:decimal'::rdfnode;
SELECT 0::numeric > '"0.0001"^^xsd:decimal'::rdfnode;
SELECT 0::numeric < '"-0.0001"^^xsd:decimal'::rdfnode;
SELECT 0::numeric ='"-0.0"^^xsd:decimal'::rdfnode;

/* double precision (float8) <-> rdfnode */
SELECT '"42.73"^^xsd:double'::rdfnode::double precision = 42.73000::double precision;
SELECT '"42.73"^^xsd:double'::rdfnode::double precision <> 42.73000::double precision;
SELECT '"42.73"^^xsd:double'::rdfnode::double precision > 42.999999::double precision;
SELECT '"42.73"^^xsd:double'::rdfnode::double precision < 42.999999::double precision;
SELECT '"4.2E1"^^xsd:double'::rdfnode = 42.0::double precision;
SELECT '"4.2000001E1"^^xsd:double'::rdfnode > 42.0::double precision;
SELECT '"4.1999999E1"^^xsd:double'::rdfnode < 42.0::double precision;
SELECT '"0.0"^^xsd:double'::rdfnode = '-0.0'::double precision;
SELECT '"NaN"^^xsd:double'::rdfnode != 0::double precision;
SELECT '"Infinity"^^xsd:double'::rdfnode > 1e308::double precision;
SELECT '"-Infinity"^^xsd:double'::rdfnode < -1e308::double precision;
SELECT 42.73000::double precision = '"42.73"^^xsd:double'::rdfnode::double precision;
SELECT 42.73000::double precision <> '"42.73"^^xsd:double'::rdfnode::double precision;
SELECT 42.999999::double precision >'"42.73"^^xsd:double'::rdfnode::double precision;
SELECT 42.999999::double precision < '"42.73"^^xsd:double'::rdfnode::double precision;
SELECT 42.0::double precision = '"4.2E1"^^xsd:double'::rdfnode;
SELECT 42.0::double precision > '"4.2000001E1"^^xsd:double'::rdfnode;
SELECT 42.0::double precision < '"4.1999999E1"^^xsd:double'::rdfnode;
SELECT '-0.0'::double precision = '"0.0"^^xsd:double'::rdfnode;
SELECT 0::double precision != '"NaN"^^xsd:double'::rdfnode;
SELECT 1e308::double precision > '"Infinity"^^xsd:double'::rdfnode;
SELECT -1e308::double precision < '"-Infinity"^^xsd:double'::rdfnode;

/* real (float4) <-> rdfnode */
SELECT '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode = 42.73::real;
SELECT '"42.00"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode = 42::real;
SELECT '"42.0000000000000000"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode = 42::real;
SELECT '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode = -42.73::real;
SELECT '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode <> 42.73::real;
SELECT '"42.00"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode <> 42::real;
SELECT '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode > 43.00::real;
SELECT '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode > -43.00::real;
SELECT '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode < 43.00::real;
SELECT '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode < -43.00::real;
SELECT '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode >= 43.00::real;
SELECT '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode >= -43.00::real;
SELECT '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode <= 43.00::real;
SELECT '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode <= -43.00::real;
SELECT 42.73::real = '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT 42::real = '"42.00"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT 42::real = '"42.0000000000000000"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT -42.73::real = '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT 42.73::real <> '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT 42::real <>'"42.00"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT 43.00::real > '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT -43.00::real > '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT 43.00::real < '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT -43.00::real < '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT 43.00::real >= '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT -43.00::real >= '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT 43.00::real <= '"42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;
SELECT -43.00::real <= '"-42.73"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode;

/* bigint (int8) <-> rdfnode */
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode = 42746357267238768;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode = -42746357267238768;
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode <> 42746357267238768;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode <> -42746357267238768;
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode != 42746357267238768;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode != -42746357267238768;
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode > 42746357267238799;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode > -42746357267238799;
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode < 42746357267238799;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode < -42746357267238799;
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode >= 42746357267238799;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode >= -42746357267238799;
SELECT '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode <= 42746357267238799;
SELECT '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode <= -42746357267238799;
SELECT 42746357267238768 ='"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT -42746357267238768 = '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT 42746357267238768 <> '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT -42746357267238768 <> '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT 42746357267238768 != '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT -42746357267238768 != '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT 42746357267238799 > '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT -42746357267238799 > '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT 42746357267238799 < '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT -42746357267238799 < '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT 42746357267238799 >= '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT -42746357267238799 >= '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT 42746357267238799 <= '"42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;
SELECT -42746357267238799 <= '"-42746357267238768"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode;

/* int (int4) <-> rdfnode */
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode = 427463::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode = -427463::int;
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode <> 427463::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode <> -427463::int;
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode != 427463::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode != -427463::int;
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode > 427464::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode > -427464::int;
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode < 427464::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode < -427464::int;
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode >= 427464::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode >= -427464::int;
SELECT '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode <= 427464::int;
SELECT '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode <= -427464::int;
SELECT 427463::int = '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT -427463::int = '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT 427463::int <> '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT -427463::int <> '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT 427463::int != '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT -427463::int != '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT 427464::int > '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT -427464::int > '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT 427464::int <'"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT -427464::int < '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT 427464::int >= '"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT -427464::int >= '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT 427464::int <='"427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT -427464::int <= '"-427463"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT '"2147483648"^^xsd:int'::rdfnode::int; -- must fail: out of range for type integer

/* smallint (int2) <-> rdfnode */
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode = 4273::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode = -4273::smallint;
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode <> 4273::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode <> -4273::smallint;
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode != 4273::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode != -4273::smallint;
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode > 4274::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode > -4274::smallint;
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode < 4274::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode < -4274::smallint;
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode >= 4274::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode >= -4274::smallint;
SELECT '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode <= 4274::smallint;
SELECT '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode <= -4274::smallint;
SELECT 4273::smallint = '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT -4273::smallint = '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT 4273::smallint <> '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT -4273::smallint <> '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT 4273::smallint != '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT -4273::smallint != '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT 4274::smallint > '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT -4274::smallint > '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT 4274::smallint <'"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT -4274::smallint < '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT 4274::smallint >= '"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT -4274::smallint >= '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT 4274::smallint <='"4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT -4274::smallint <= '"-4273"^^<http://www.w3.org/2001/XMLSchema#short>'::rdfnode;
SELECT '"32767"^^xsd:short'::rdfnode = 32767::smallint;
SELECT '"-32768"^^xsd:short'::rdfnode = -32768::smallint;
SELECT '"32768"^^xsd:short'::rdfnode::smallint;

/* timestamptz (timestamp with time zone) <-> rdfnode */
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode = '2025-04-25 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode <> '2025-04-26 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode != '2025-04-26 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode > '2025-04-26 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode < '2025-04-26 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode >= '2025-04-26 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode <= '2025-04-26 18:44:38.149101+00'::timestamptz;
SELECT '2025-04-25 18:44:38.149101+00'::timestamptz = '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode;
SELECT '2025-04-26 18:44:38.149101+00'::timestamptz <> '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode;
SELECT '2025-04-26 18:44:38.149101+00'::timestamptz != '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode;
SELECT '2025-04-26 18:44:38.149101+00'::timestamptz > '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode;
SELECT '2025-04-26 18:44:38.149101+00'::timestamptz < '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode;
SELECT '2025-04-26 18:44:38.149101+00'::timestamptz >= '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode;
SELECT '2025-04-26 18:44:38.149101+00'::timestamptz <= '2025-04-25 18:44:38.149101+00'::timestamptz::rdfnode;

/* timestamp (timestamp with time zone) <-> rdfnode */
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode = '2025-04-25 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode <> '2025-04-26 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode != '2025-04-26 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode > '2025-04-26 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode < '2025-04-26 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode >= '2025-04-26 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp::rdfnode <= '2025-04-26 18:44:38'::timestamp;
SELECT '2025-04-25 18:44:38'::timestamp = '2025-04-25 18:44:38'::timestamp::rdfnode;
SELECT '2025-04-26 18:44:38'::timestamp <> '2025-04-25 18:44:38'::timestamp::rdfnode;
SELECT '2025-04-26 18:44:38'::timestamp != '2025-04-25 18:44:38'::timestamp::rdfnode;
SELECT '2025-04-26 18:44:38'::timestamp > '2025-04-25 18:44:38'::timestamp::rdfnode;
SELECT '2025-04-26 18:44:38'::timestamp < '2025-04-25 18:44:38'::timestamp::rdfnode;
SELECT '2025-04-26 18:44:38'::timestamp >= '2025-04-25 18:44:38'::timestamp::rdfnode;
SELECT '2025-04-26 18:44:38'::timestamp <= '2025-04-25 18:44:38'::timestamp::rdfnode;

/* date <-> rdfnode */
SELECT '2020-05-12'::date::rdfnode = '2020-05-12'::date;
SELECT '2020-05-12'::date::rdfnode <> '2020-05-12'::date;
SELECT '2020-05-12'::date::rdfnode != '2020-05-12'::date;
SELECT '2020-05-12'::date::rdfnode > '2020-05-13'::date;
SELECT '2020-05-12'::date::rdfnode < '2020-05-13'::date;
SELECT '2020-05-12'::date::rdfnode >= '2020-05-13'::date;
SELECT '2020-05-12'::date::rdfnode <= '2020-05-13'::date;
SELECT '2020-05-12'::date = '2020-05-12'::date::rdfnode;
SELECT '2020-05-12'::date <> '2020-05-12'::date::rdfnode;
SELECT '2020-05-12'::date != '2020-05-12'::date::rdfnode;
SELECT '2020-05-13'::date > '2020-05-12'::date::rdfnode;
SELECT '2020-05-13'::date < '2020-05-12'::date::rdfnode;
SELECT '2020-05-13'::date >= '2020-05-12'::date::rdfnode;
SELECT '2020-05-13'::date <= '2020-05-12'::date::rdfnode;
SELECT '"invalid"^^xsd:date'::rdfnode::date;
SELECT '"2020-13-01"^^xsd:date'::rdfnode::date;
SELECT '0001-01-01'::date::rdfnode = '0001-01-01'::date;
SELECT '9999-12-31'::date::rdfnode = '9999-12-31'::date;

/* time (without time zone) <-> rdfnode */
SELECT '18:44:38'::time::rdfnode = '18:44:38'::time;
SELECT '18:44:38'::time::rdfnode <> '18:44:38'::time;
SELECT '18:44:38'::time::rdfnode != '18:44:38'::time;
SELECT '18:44:38'::time::rdfnode > '18:44:59'::time;
SELECT '18:44:38'::time::rdfnode < '18:44:59'::time;
SELECT '18:44:38'::time::rdfnode >= '18:44:59'::time;
SELECT '18:44:38'::time::rdfnode <= '18:44:59'::time;
SELECT '18:44:38'::time = '18:44:38'::time::rdfnode;
SELECT '18:44:38'::time <> '18:44:38'::time::rdfnode;
SELECT '18:44:38'::time != '18:44:38'::time::rdfnode;
SELECT '18:44:59'::time > '18:44:38'::time::rdfnode;
SELECT '18:44:59'::time < '18:44:38'::time::rdfnode;
SELECT '18:44:59'::time >= '18:44:38'::time::rdfnode;
SELECT '18:44:59'::time <= '18:44:38'::time::rdfnode;
SELECT '-18:44:38'::time::rdfnode;
SELECT 'invalid'::time::rdfnode;

/* timetz (with time zone) <-> rdfnode */
SELECT '04:05:06-08:00'::timetz::rdfnode = '04:05:06-08:00'::timetz;
SELECT '04:05:06-08:00'::timetz::rdfnode <> '04:05:06-08:00'::timetz;
SELECT '04:05:06-08:00'::timetz::rdfnode != '04:05:06-08:00'::timetz;
SELECT '12:05:06-08:00'::timetz::rdfnode > '04:05:06-08:00'::timetz;
SELECT '12:05:06-08:00'::timetz::rdfnode < '04:05:06-08:00'::timetz;
SELECT '12:05:06-08:00'::timetz::rdfnode >= '04:05:06-08:00'::timetz;
SELECT '12:05:06-08:00'::timetz::rdfnode <= '04:05:06-08:00'::timetz;
SELECT '04:05:06-08:00'::timetz = '04:05:06-08:00'::timetz::rdfnode;
SELECT '04:05:06-08:00'::timetz <> '04:05:06-08:00'::timetz::rdfnode;
SELECT '04:05:06-08:00'::timetz != '04:05:06-08:00'::timetz::rdfnode;
SELECT '04:05:06-08:00'::timetz > '12:05:06-08:00'::timetz::rdfnode;
SELECT '04:05:06-08:00'::timetz < '12:05:06-08:00'::timetz::rdfnode;
SELECT '04:05:06-08:00'::timetz >= '12:05:06-08:00'::timetz::rdfnode;
SELECT '04:05:06-08:00'::timetz <= '12:05:06-08:00'::timetz::rdfnode;

/* boolean <-> rdfnode */
SELECT true::rdfnode;
SELECT false::rdfnode;
SELECT true::rdfnode::boolean;
SELECT false::rdfnode::boolean;
SELECT (1=1)::rdfnode::boolean;
SELECT (1<>1)::rdfnode::boolean;

/* interval <-> rdfnode */
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode = '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode = '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1"^^xsd:duration'::rdfnode <> '12 months'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode <> '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode <> '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1"^^xsd:duration'::rdfnode != '12 months'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode != '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode != '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1"^^xsd:duration'::rdfnode > '12 months'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode > '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode > '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1"^^xsd:duration'::rdfnode < '12 months'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode < '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode < '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1"^^xsd:duration'::rdfnode >= '12 months'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode >= '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode >= '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1"^^xsd:duration'::rdfnode <= '12 months'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode <= '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode <= '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '12 months'::interval = '"P1"^^xsd:duration'::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval = '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval = '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode;
SELECT '12 months'::interval <> '"P1"^^xsd:duration'::rdfnode;
SELECT '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode <> '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval <> '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode;
SELECT '12 months'::interval != '"P1"^^xsd:duration'::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval != '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval != '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode;

SELECT '12 months'::interval > '"P1"^^xsd:duration'::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval > '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval > '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode;
SELECT '12 months'::interval < '"P1"^^xsd:duration'::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval <'"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval < '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode;
SELECT '12 months'::interval >= '"P1"^^xsd:duration'::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval >= '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval >= '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode;
SELECT '12 months'::interval <= '"P1"^^xsd:duration'::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval <= '"P1Y2M3DT4H5M6S"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode;
SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds'::interval <= '"P1Y2M3DT4H5M6S"^^xsd:duration'::rdfnode;
