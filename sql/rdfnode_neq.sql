\pset null NULL
\set VERBOSITY terse
-- Tests for equality (=) operator on rdfnode type

-- Language-tagged literals (case-insensitive)
SELECT '"foo"@EN'::rdfnode <> '"foo"@en'::rdfnode;
SELECT '"foo"@en-us'::rdfnode <> '"foo"@EN-US'::rdfnode;
SELECT '"foo"@en'::rdfnode <> '"foo"@en-us'::rdfnode;
SELECT '"café"@fr'::rdfnode <> '"café"@fr'::rdfnode;
SELECT '"café"@fr'::rdfnode <> '"cafe"@fr'::rdfnode;
SELECT '"foo"^^xsd:string'::rdfnode <> '" foo "^^xsd:string'::rdfnode;

-- Unicode escapes
SELECT '"\u0020"^^xsd:string'::rdfnode <> '" "^^xsd:string'::rdfnode;
SELECT '"\U0001F600"^^xsd:string'::rdfnode <> '"😀"^^xsd:string'::rdfnode;
SELECT '"\U0001F600"^^xsd:string'::rdfnode <> '"😀"'::rdfnode;
SELECT '"\uD834\uDD1E"^^xsd:string'::rdfnode <> '𝄞'::rdfnode;
SELECT '"\""'::rdfnode <> '"'::rdfnode;  -- False, first has quote escaped
SELECT '"\\\\u0020"'::rdfnode <> '"\\u0020"'::rdfnode;  -- False, first is two literal backslashes
SELECT '"\u0020"'::rdfnode <> '" "'::rdfnode;  -- True
SELECT '"\u0009"'::rdfnode <> E'\t'::rdfnode;  -- True

SELECT '"\uD834"^^xsd:string'::rdfnode;  -- Invalid alone
SELECT '"\uDD1E"^^xsd:string'::rdfnode;  -- Invalid alone
SELECT '"\u12"^^xsd:string'::rdfnode;  -- Too short
SELECT '"\u12GZ"^^xsd:string'::rdfnode;  -- Invalid hex digits
SELECT '"\u123456"^^xsd:string'::rdfnode;  -- Overflow (only 4 digits allowed for \u)
SELECT '"\U000110000"'::rdfnode;  -- Invalid (codepoints above U+10FFFF)

-- Typed literals, same datatype IRI
SELECT '"foo"^^<http://example.org/custom>'::rdfnode <> '"foo"^^<http://example.org/custom>'::rdfnode;
SELECT '"foo"^^<http://example.org/custom>'::rdfnode <> '"foo"^^xsd:string'::rdfnode;
SELECT '"foo"^^<http://invalid>'::rdfnode <> '"foo"^^<http://invalid>'::rdfnode;

-- Integer comparisons
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode;
SELECT '"-42"^^xsd:int'::rdfnode <> '"-42"^^xsd:int'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"-42"^^xsd:int'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42.00"^^xsd:decimal'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^xsd:integer'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42.0000000000"^^xsd:double'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^xsd:short'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42.73"^^xsd:decimal'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42.0000000001"^^xsd:double'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"foo"^^xsd:string'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^xsd:string'::rdfnode;
SELECT '"42"^^xsd:int'::rdfnode <> '"42"^^xsd:date'::rdfnode;
SELECT '"-0"^^xsd:int'::rdfnode <> '"0"^^xsd:int'::rdfnode;
SELECT '"999999999999999999"^^xsd:integer'::rdfnode <> '"999999999999999999.0"^^xsd:decimal'::rdfnode;

-- Date and time comparisons
SELECT '"2011-10-08"^^xsd:date'::rdfnode <> '"2011-10-08"^^xsd:date'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode <> '"2011-10-08"^^xsd:string'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode <> '"2011-10-08"'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode <> '"2011-10-11"^^xsd:date'::rdfnode;
SELECT '"2011-10-08"^^xsd:date'::rdfnode <> '""^^xsd:date'::rdfnode;
SELECT '"0001-01-01"^^xsd:date'::rdfnode <> '"0001-01-01"^^xsd:date'::rdfnode;

-- Invalid datetime
SELECT '"2025-13-01T12:00:00"^^xsd:dateTime'::rdfnode <> '"2025-13-01T12:00:00"^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25T25:00:00Z"^^xsd:dateTime'::rdfnode <> '"2025-04-25T25:00:00Z"^^xsd:dateTime'::rdfnode;
SELECT '"1.0E308"^^xsd:double'::rdfnode <> '"1.0E308"^^xsd:double'::rdfnode;
SELECT '"invalid"^^xsd:dateTime'::rdfnode <> '"invalid"^^xsd:dateTime'::rdfnode;

-- Time
SELECT '"18:44:38"^^xsd:time'::rdfnode <> '"18:44:38"^^xsd:time'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode <> '"18:44:38"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode <> '"20:44:38"^^xsd:time'::rdfnode;
SELECT '"18:44:38"^^xsd:time'::rdfnode <> '"18:44:38"'::rdfnode;

-- String comparison fallbacks
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode <> '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdfnode <> '"2025-04-25 18:44:38"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode <> '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdfnode <> '"2025-04-25T18:44:38.149101Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode;
SELECT '"2025-04-25T18:44:38"^^xsd:dateTime'::rdfnode <> '"2025-04-25T18:44:38Z"^^xsd:dateTime'::rdfnode;
