-- ==========================================
-- SPARQL SUM() Aggregate Tests
-- ==========================================

-- Test 1: Sum of integers → should return integer (not decimal)
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 2: Sum of decimals → should return decimal
WITH j (val) AS (
    VALUES
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20.3"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"30.2"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 3: Sum of integer + decimal → should return decimal (type promotion)
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"20.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 4: Sum of decimal + float → should return float (type promotion)
WITH j (val) AS (
    VALUES
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20.3"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 5: Sum of integer + decimal + double → should return double (highest type wins)
WITH j (val) AS (
    VALUES
        ('"10.4"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"30.4"^^<http://www.w3.org/2001/XMLSchema#double>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 6: Sum of single value → should preserve original type
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 7: Sum with integer subtypes (xsd:int, xsd:long, etc.) → should return integer
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#int>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#long>'::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 8: Sum with all four numeric types → should promote to double
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"5.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"2.5"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"3.0"^^<http://www.w3.org/2001/XMLSchema#double>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 9: Sum with integer + float (type promotion)
WITH j (val) AS (
    VALUES
        ('"100"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"0.1"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 10: Sum with negative integers
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-3"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 11: Sum resulting in negative value
WITH j (val) AS (
    VALUES
        ('"5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 12: Sum with zero values
WITH j (val) AS (
    VALUES
        ('"0"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"0"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 13: Sum resulting in zero
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 14: Sum with NULL values → should skip NULLs
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        (NULL::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 15: Sum of all NULLs → should return "0"^^xsd:integer per SPARQL 1.1
WITH j (val) AS (
    VALUES
        (NULL::rdfnode),
        (NULL::rdfnode),
        (NULL::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 16: Sum of empty set (no rows) → should return "0"^^xsd:integer per SPARQL 1.1
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.sum(val) FROM j WHERE val IS NULL;

-- ==========================================
-- SPARQL AVG() Aggregate Tests
-- ==========================================

-- Test 17: Average of integers → should return integer
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 18: Average of decimals → should return decimal
WITH j (val) AS (
    VALUES
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20.3"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"30.2"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 19: Average of integer + decimal → should return decimal (type promotion)
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"20.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 20: Average of single value → should preserve original type
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 21: Average with all four numeric types → should promote to double
WITH j (val) AS (
    VALUES
        ('"12"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"8.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"4.0"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"16.0"^^<http://www.w3.org/2001/XMLSchema#double>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 22: Average with negative decimals
WITH j (val) AS (
    VALUES
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"-5.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"-2.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 23: Average with zero in the mix
WITH j (val) AS (
    VALUES
        ('"0.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"10.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 24: Average with NULL values → should skip NULLs
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        (NULL::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 25: Average of all NULLs → should return "0"^^xsd:integer per SPARQL 1.1
WITH j (val) AS (
    VALUES
        (NULL::rdfnode),
        (NULL::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 26: Average of empty set (no rows) → should return "0"^^xsd:integer per SPARQL 1.1
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.avg(val) FROM j WHERE val IS NULL;

-- ==========================================
-- SPARQL MIN() Aggregate Tests
-- ==========================================

-- Test 27: Minimum of integers → should return integer
WITH j (val) AS (
    VALUES
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 28: Minimum of decimals → should return decimal
WITH j (val) AS (
    VALUES
        ('"30.2"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20.3"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 29: Minimum of integer + decimal → should preserve type of minimum value
WITH j (val) AS (
    VALUES
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 30: Minimum with float values
WITH j (val) AS (
    VALUES
        ('"30.5"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"10.1"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"20.3"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 31: Minimum with mixed types → should preserve type of minimum value
WITH j (val) AS (
    VALUES
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"5.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"10.0"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"20.0"^^<http://www.w3.org/2001/XMLSchema#double>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 32: Minimum of single value → should preserve original type
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 33: Minimum with negative integers
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"3"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 34: Minimum with all negative values
WITH j (val) AS (
    VALUES
        ('"-10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 35: Minimum with zero values
WITH j (val) AS (
    VALUES
        ('"0"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 40: Minimum with NULL values → should skip NULLs
WITH j (val) AS (
    VALUES
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        (NULL::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        (NULL::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 41: Minimum of all NULLs → should return NULL (no values to select from)
WITH j (val) AS (
    VALUES
        (NULL::rdfnode),
        (NULL::rdfnode),
        (NULL::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 42: Minimum of empty set (no rows) → should return NULL (no rows to aggregate)
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j WHERE val IS NULL;

-- Test 43: Minimum with equal values → should preserve type
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 44: MIN on multiple strings → should return lexically smallest
WITH j (val) AS (
    VALUES
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"apple"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"mango"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 45: MIN on dates → should return earliest date
WITH j (val) AS (
    VALUES
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"2021-01-01"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"2025-12-31"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 46: MIN on single non-numeric value → should return that value
WITH j (val) AS (
    VALUES
        ('"single-string"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- ==========================================
-- SPARQL MAX() Aggregate Tests
-- ==========================================

-- Test 47: Maximum of integers → should return integer
WITH j (val) AS (
    VALUES
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 48: Maximum of decimals → should return decimal
WITH j (val) AS (
    VALUES
        ('"30.2"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20.3"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 49: Maximum of integer + decimal → should preserve type of maximum value
WITH j (val) AS (
    VALUES
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 50: Maximum with float values
WITH j (val) AS (
    VALUES
        ('"30.5"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"10.1"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"20.3"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 51: Maximum with mixed types → should preserve type of maximum value
WITH j (val) AS (
    VALUES
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"5.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"10.0"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode),
        ('"20.0"^^<http://www.w3.org/2001/XMLSchema#double>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 52: Maximum of single value → should preserve original type
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 53: Maximum with negative integers
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"3"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 54: Maximum with all negative values
WITH j (val) AS (
    VALUES
        ('"-10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 55: Maximum with zero values
WITH j (val) AS (
    VALUES
        ('"0"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"-5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 56: Maximum with NULL values → should skip NULLs
WITH j (val) AS (
    VALUES
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        (NULL::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        (NULL::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 57: Maximum of all NULLs → should return NULL (no values to select from)
WITH j (val) AS (
    VALUES
        (NULL::rdfnode),
        (NULL::rdfnode),
        (NULL::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 58: Maximum of empty set (no rows) → should return NULL (no rows to aggregate)
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.max(val) FROM j WHERE val IS NULL;

-- Test 59: Maximum with equal values → should preserve type
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10.0"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 60: MAX on multiple strings → should return lexically largest
WITH j (val) AS (
    VALUES
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"apple"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"mango"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 61: MAX on dates → should return latest date
WITH j (val) AS (
    VALUES
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"2021-01-01"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"2025-12-31"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 62: MAX on single non-numeric value → should return that value
WITH j (val) AS (
    VALUES
        ('"single-string"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- ==========================================
-- SPARQL Term Ordering: Mixed-Type Tests
-- ==========================================
-- These tests verify SPARQL 1.1 Section 15.1 term ordering:
-- IRIs < lang-tagged < plain literals < numerics < temporals < xsd:string < other

-- Test 63: MIN with numeric + string → numeric comes first (typeOrder 3 < 8)
WITH j (val) AS (
    VALUES
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"mango"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 64: MAX with numeric + string → string comes last (typeOrder 8 > 3)
WITH j (val) AS (
    VALUES
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"mango"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 65: MIN with numeric + date → numeric comes first (typeOrder 3 < 5)
WITH j (val) AS (
    VALUES
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"100"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"2021-01-01"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 66: MAX with numeric + date → date comes last (typeOrder 5 > 3)
WITH j (val) AS (
    VALUES
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"100"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"2021-01-01"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 67: MIN with date + string → date comes first (typeOrder 5 < 8)
WITH j (val) AS (
    VALUES
        ('"apple"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 68: MAX with date + string → string comes last (typeOrder 8 > 5)
WITH j (val) AS (
    VALUES
        ('"apple"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 69: MIN with numeric + dateTime → numeric comes first (typeOrder 3 < 4)
WITH j (val) AS (
    VALUES
        ('"2023-06-15T10:30:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode),
        ('"5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"2021-01-01T00:00:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 70: MAX with numeric + dateTime → dateTime comes last (typeOrder 4 > 3)
WITH j (val) AS (
    VALUES
        ('"2023-06-15T10:30:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode),
        ('"5"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"2021-01-01T00:00:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 71: MIN with all category types → numeric wins
WITH j (val) AS (
    VALUES
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"10:30:00"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 72: MAX with all category types → string wins
WITH j (val) AS (
    VALUES
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"10:30:00"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 73: MIN with IRI + numeric + string → IRI comes first (typeOrder 0)
WITH j (val) AS (
    VALUES
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('<http://example.org/resource/1>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 74: MAX with IRI + numeric + string → string comes last (typeOrder 8)
WITH j (val) AS (
    VALUES
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('<http://example.org/resource/1>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 75: MIN with lang-tagged + numeric → lang-tagged comes first (typeOrder 1 < 3)
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"hello"@en'::rdfnode),
        ('"100"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 76: MAX with lang-tagged + numeric → numeric comes last (typeOrder 3 > 1)
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"hello"@en'::rdfnode),
        ('"100"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 77: MIN with plain literal + numeric → plain comes first (typeOrder 2 < 3)
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"plain-text"'::rdfnode),
        ('"100"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 78: MAX with plain literal + numeric → numeric comes last (typeOrder 3 > 2)
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"plain-text"'::rdfnode),
        ('"100"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 79: MIN with time + duration → time comes first (typeOrder 6 < 7)
WITH j (val) AS (
    VALUES
        ('"P1Y"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode),
        ('"10:30:00"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode),
        ('"P2M"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 80: MAX with time + duration → duration comes last (typeOrder 7 > 6)
WITH j (val) AS (
    VALUES
        ('"P1Y"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode),
        ('"10:30:00"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode),
        ('"P2M"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 81: MIN with comprehensive mix (IRI, lang, plain, numeric, temporal, string)
WITH j (val) AS (
    VALUES
        ('"string-value"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('<http://example.org/id>'::rdfnode),
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"labeled"@en'::rdfnode),
        ('"plain"'::rdfnode),
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 82: MAX with comprehensive mix (IRI, lang, plain, numeric, temporal, string)
WITH j (val) AS (
    VALUES
        ('"string-value"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('<http://example.org/id>'::rdfnode),
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"labeled"@en'::rdfnode),
        ('"plain"'::rdfnode),
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 83: MIN with multiple numerics of different types in mix → smallest numeric value
WITH j (val) AS (
    VALUES
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"5.5"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"100"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"2023-01-01"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 84: MAX with multiple temporals of different types → latest temporal value
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"2025-12-31"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"2021-01-01T00:00:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode),
        ('"apple"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- Test 85: MIN with NULL in mixed-type set → should skip NULL
WITH j (val) AS (
    VALUES
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        (NULL::rdfnode),
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.min(val) FROM j;

-- Test 86: MAX with NULL in mixed-type set → should skip NULL
WITH j (val) AS (
    VALUES
        ('"zebra"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        (NULL::rdfnode),
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.max(val) FROM j;

-- ==========================================
-- Error Cases: SUM() and AVG() with Non-Numeric Types
-- ==========================================
-- SPARQL 1.1 Section 18.5.1.3 (Sum) and 18.5.1.4 (Avg):
-- SUM and AVG operate on numeric values. When non-numeric values are encountered,
-- they produce type errors which are excluded from the aggregate (similar to NULL).
-- If all values are non-numeric, the aggregate returns NULL (unbound result).
-- This behavior aligns with Blazegraph and GraphDB implementations.
-- Note: Virtuoso has non-conformant behavior (returns partial sums).

-- Test 87: SUM on string → should return NULL (no numeric values)
WITH j (val) AS (
    VALUES
        ('"not-a-number"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 88: SUM on xsd:date → should return NULL
WITH j (val) AS (
    VALUES
        ('"2023-01-01"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 89: SUM on xsd:dateTime → should return NULL
WITH j (val) AS (
    VALUES
        ('"2023-01-01T10:30:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode),
        ('"2023-06-15T15:45:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 90: SUM on xsd:time → should return NULL
WITH j (val) AS (
    VALUES
        ('"10:30:00"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode),
        ('"15:45:00"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 91: SUM on xsd:duration → should return NULL
WITH j (val) AS (
    VALUES
        ('"P1Y"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode),
        ('"P2M"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 92: SUM on xsd:boolean → should return NULL
WITH j (val) AS (
    VALUES
        ('"true"^^<http://www.w3.org/2001/XMLSchema#boolean>'::rdfnode),
        ('"false"^^<http://www.w3.org/2001/XMLSchema#boolean>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 93: SUM with mixed numeric and xsd:date → should return sum of numeric only (10)
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"2023-01-01"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 94: SUM with mixed numeric and xsd:string → should return sum of numeric only (10)
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"text"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.sum(val) FROM j;

-- Test 95: AVG on xsd:date → should return NULL
WITH j (val) AS (
    VALUES
        ('"2023-01-01"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"2023-06-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 96: AVG on xsd:dateTime → should return NULL
WITH j (val) AS (
    VALUES
        ('"2023-01-01T10:30:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode),
        ('"2023-06-15T15:45:00"^^<http://www.w3.org/2001/XMLSchema#dateTime>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 97: AVG on xsd:time → should return NULL
WITH j (val) AS (
    VALUES
        ('"10:30:00"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode),
        ('"15:45:00"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 98: AVG on xsd:duration → should return NULL
WITH j (val) AS (
    VALUES
        ('"P1Y"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode),
        ('"P2M"^^<http://www.w3.org/2001/XMLSchema#duration>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 99: AVG on xsd:string → should return NULL
WITH j (val) AS (
    VALUES
        ('"apple"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"banana"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 100: AVG on xsd:boolean → should return NULL
WITH j (val) AS (
    VALUES
        ('"true"^^<http://www.w3.org/2001/XMLSchema#boolean>'::rdfnode),
        ('"false"^^<http://www.w3.org/2001/XMLSchema#boolean>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 101: AVG with mixed numeric and xsd:time → should return avg of numeric only (42)
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"10:30:00"^^<http://www.w3.org/2001/XMLSchema#time>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- Test 102: AVG with mixed numeric and xsd:string → should return avg of numeric only (10)
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"not-a-number"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.avg(val) FROM j;

-- ==========================================
-- SPARQL GROUP_CONCAT() Aggregate Tests
-- ==========================================

-- Test 103: GROUP_CONCAT with default separator (space)
WITH j (val) AS (
    VALUES
        ('"apple"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"banana"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"cherry"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.group_concat(val, ' ') FROM j;

-- Test 104: GROUP_CONCAT with custom separator (comma)
WITH j (val) AS (
    VALUES
        ('"apple"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"banana"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"cherry"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.group_concat(val, ', ') FROM j;

-- Test 105: GROUP_CONCAT with integers → should convert to strings
WITH j (val) AS (
    VALUES
        ('"10"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"20"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"30"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode)
)
SELECT sparql.group_concat(val, '-') FROM j;

-- Test 106: GROUP_CONCAT with mixed types → should handle all RDF terms
WITH j (val) AS (
    VALUES
        ('"42"^^<http://www.w3.org/2001/XMLSchema#integer>'::rdfnode),
        ('"hello"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"3.14"^^<http://www.w3.org/2001/XMLSchema#float>'::rdfnode)
)
SELECT sparql.group_concat(val, ' | ') FROM j;

-- Test 107: GROUP_CONCAT with IRIs → should extract URI
WITH j (val) AS (
    VALUES
        ('<http://example.org/resource1>'::rdfnode),
        ('<http://example.org/resource2>'::rdfnode),
        ('<http://example.org/resource3>'::rdfnode)
)
SELECT sparql.group_concat(val, '; ') FROM j;

-- Test 108: GROUP_CONCAT with language-tagged strings → should extract lexical value
WITH j (val) AS (
    VALUES
        ('"hello"@en'::rdfnode),
        ('"bonjour"@fr'::rdfnode),
        ('"hola"@es'::rdfnode)
)
SELECT sparql.group_concat(val, ', ') FROM j;

-- Test 109: GROUP_CONCAT with NULL value → should skip NULL
WITH j (val) AS (
    VALUES
        ('"apple"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        (NULL::rdfnode),
        ('"cherry"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.group_concat(val, ', ') FROM j;

-- Test 110: GROUP_CONCAT with all NULL → should return empty string
WITH j (val) AS (
    VALUES
        (NULL::rdfnode),
        (NULL::rdfnode),
        (NULL::rdfnode)
)
SELECT sparql.group_concat(val, ', ') FROM j;

-- Test 111: GROUP_CONCAT with empty set → should return empty string
SELECT sparql.group_concat(val, ', ') 
FROM (SELECT NULL::rdfnode AS val WHERE false) AS j;

-- Test 112: GROUP_CONCAT with single value
WITH j (val) AS (
    VALUES
        ('"only-one"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.group_concat(val, ', ') FROM j;

-- Test 113: GROUP_CONCAT with dates → should convert to string
WITH j (val) AS (
    VALUES
        ('"2024-01-15"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"2024-02-20"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode),
        ('"2024-03-25"^^<http://www.w3.org/2001/XMLSchema#date>'::rdfnode)
)
SELECT sparql.group_concat(val, ' to ') FROM j;

-- Test 114: GROUP_CONCAT with booleans → should convert to string
WITH j (val) AS (
    VALUES
        ('"true"^^<http://www.w3.org/2001/XMLSchema#boolean>'::rdfnode),
        ('"false"^^<http://www.w3.org/2001/XMLSchema#boolean>'::rdfnode)
)
SELECT sparql.group_concat(val, ', ') FROM j;

-- Test 115: GROUP_CONCAT with empty string separator
WITH j (val) AS (
    VALUES
        ('"a"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"b"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"c"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.group_concat(val, '') FROM j;

-- Test 116: GROUP_CONCAT with newline separator
WITH j (val) AS (
    VALUES
        ('"line1"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"line2"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"line3"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.group_concat(val, E'\n') FROM j;

-- Test 117: GROUP_CONCAT with very long separator
WITH j (val) AS (
    VALUES
        ('"first"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode),
        ('"second"^^<http://www.w3.org/2001/XMLSchema#string>'::rdfnode)
)
SELECT sparql.group_concat(val, ' --- SEPARATOR --- ') FROM j;

-- Test 118: GROUP_CONCAT with decimals → should preserve precision
WITH j (val) AS (
    VALUES
        ('"10.50"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"20.30"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode),
        ('"30.20"^^<http://www.w3.org/2001/XMLSchema#decimal>'::rdfnode)
)
SELECT sparql.group_concat(val, ', ') FROM j;
