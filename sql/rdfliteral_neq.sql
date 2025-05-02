\pset null NULL
\set VERBOSITY terse
-- Tests for equality (=) operator on rdf_literal type

-- Language-tagged literals (case-insensitive)
SELECT '"foo"@EN'::rdf_literal <> '"foo"@en'::rdf_literal;
SELECT '"foo"@en-us'::rdf_literal <> '"foo"@EN-US'::rdf_literal;
SELECT '"foo"@en'::rdf_literal <> '"foo"@en-us'::rdf_literal;
SELECT '"café"@fr'::rdf_literal <> '"café"@fr'::rdf_literal;
SELECT '"café"@fr'::rdf_literal <> '"cafe"@fr'::rdf_literal;
SELECT '"foo"^^xsd:string'::rdf_literal <> '" foo "^^xsd:string'::rdf_literal;

-- Unicode escapes
SELECT '"\u0020"^^xsd:string'::rdf_literal <> '" "^^xsd:string'::rdf_literal;
SELECT '"\U0001F600"^^xsd:string'::rdf_literal <> '"😀"^^xsd:string'::rdf_literal;
SELECT '"\U0001F600"^^xsd:string'::rdf_literal <> '"😀"'::rdf_literal;
SELECT '"\uD834\uDD1E"^^xsd:string'::rdf_literal <> '𝄞'::rdf_literal;
SELECT '"\""'::rdf_literal <> '"'::rdf_literal;  -- False, first has quote escaped
SELECT '"\\\\u0020"'::rdf_literal <> '"\\u0020"'::rdf_literal;  -- False, first is two literal backslashes
SELECT '"\u0020"'::rdf_literal <> '" "'::rdf_literal;  -- True
SELECT '"\u0009"'::rdf_literal <> E'\t'::rdf_literal;  -- True

SELECT '"\uD834"^^xsd:string'::rdf_literal;  -- Invalid alone
SELECT '"\uDD1E"^^xsd:string'::rdf_literal;  -- Invalid alone
SELECT '"\u12"^^xsd:string'::rdf_literal;  -- Too short
SELECT '"\u12GZ"^^xsd:string'::rdf_literal;  -- Invalid hex digits
SELECT '"\u123456"^^xsd:string'::rdf_literal;  -- Overflow (only 4 digits allowed for \u)
SELECT '"\U000110000"'::rdf_literal;  -- Invalid (codepoints above U+10FFFF)

-- Typed literals, same datatype IRI
SELECT '"foo"^^<http://example.org/custom>'::rdf_literal <> '"foo"^^<http://example.org/custom>'::rdf_literal;
SELECT '"foo"^^<http://example.org/custom>'::rdf_literal <> '"foo"^^xsd:string'::rdf_literal;
SELECT '"foo"^^<http://invalid>'::rdf_literal <> '"foo"^^<http://invalid>'::rdf_literal;

-- Integer comparisons
SELECT '"42"^^xsd:int'::rdf_literal <> '"42"^^<http://www.w3.org/2001/XMLSchema#int>'::rdf_literal;
SELECT '"-42"^^xsd:int'::rdf_literal <> '"-42"^^xsd:int'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal <> '"-42"^^xsd:int'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal <> '"42.00"^^xsd:decimal'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal <> '"42"^^xsd:integer'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal <> '"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal <> '"42.0000000000"^^xsd:double'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal <> '"42"^^xsd:short'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal <> '"42.73"^^xsd:decimal'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal <> '"42.0000000001"^^xsd:double'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal <> '"foo"^^xsd:string'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal <> '"42"^^xsd:string'::rdf_literal;
SELECT '"42"^^xsd:int'::rdf_literal <> '"42"^^xsd:date'::rdf_literal;
SELECT '"-0"^^xsd:int'::rdf_literal <> '"0"^^xsd:int'::rdf_literal;
SELECT '"999999999999999999"^^xsd:integer'::rdf_literal <> '"999999999999999999.0"^^xsd:decimal'::rdf_literal;

-- Date and time comparisons
SELECT '"2011-10-08"^^xsd:date'::rdf_literal <> '"2011-10-08"^^xsd:date'::rdf_literal;
SELECT '"2011-10-08"^^xsd:date'::rdf_literal <> '"2011-10-08"^^xsd:string'::rdf_literal;
SELECT '"2011-10-08"^^xsd:date'::rdf_literal <> '"2011-10-08"'::rdf_literal;
SELECT '"2011-10-08"^^xsd:date'::rdf_literal <> '"2011-10-11"^^xsd:date'::rdf_literal;
SELECT '"2011-10-08"^^xsd:date'::rdf_literal <> '""^^xsd:date'::rdf_literal;
SELECT '"0001-01-01"^^xsd:date'::rdf_literal <> '"0001-01-01"^^xsd:date'::rdf_literal;

-- Invalid datetime
SELECT '"2025-13-01T12:00:00"^^xsd:dateTime'::rdf_literal <> '"2025-13-01T12:00:00"^^xsd:dateTime'::rdf_literal;
SELECT '"2025-04-25T25:00:00Z"^^xsd:dateTime'::rdf_literal <> '"2025-04-25T25:00:00Z"^^xsd:dateTime'::rdf_literal;
SELECT '"1.0E308"^^xsd:double'::rdf_literal <> '"1.0E308"^^xsd:double'::rdf_literal;
SELECT '"invalid"^^xsd:dateTime'::rdf_literal <> '"invalid"^^xsd:dateTime'::rdf_literal;

-- Time
SELECT '"18:44:38"^^xsd:time'::rdf_literal <> '"18:44:38"^^xsd:time'::rdf_literal;
SELECT '"18:44:38"^^xsd:time'::rdf_literal <> '"18:44:38"^^<http://www.w3.org/2001/XMLSchema#time>'::rdf_literal;
SELECT '"18:44:38"^^xsd:time'::rdf_literal <> '"20:44:38"^^xsd:time'::rdf_literal;
SELECT '"18:44:38"^^xsd:time'::rdf_literal <> '"18:44:38"'::rdf_literal;

-- String comparison fallbacks
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal <> '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal;
SELECT '"2025-04-25 18:44:38"^^xsd:dateTime'::rdf_literal <> '"2025-04-25 18:44:38"^^<http://www.w3.org/2001/XMLSchema#time>'::rdf_literal;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal <> '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal;
SELECT '"2025-04-25T18:44:38.149101Z"^^xsd:dateTime'::rdf_literal <> '"2025-04-25T18:44:38.149101Z"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdf_literal;
SELECT '"2025-04-25T18:44:38"^^xsd:dateTime'::rdf_literal <> '"2025-04-25T18:44:38Z"^^xsd:dateTime'::rdf_literal;
