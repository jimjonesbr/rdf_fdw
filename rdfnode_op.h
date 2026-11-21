/*---------------------------------------------------------------------
 *
 * rdfnode_op.h
 *
 * SQL-callable functions of the rdfnode data type (see rdfnode_op.c).
 *
 * Copyright (C) 2022-2026 Jim Jones <jim.jones@uni-muenster.de>
 *
 *---------------------------------------------------------------------
 */

#ifndef RDFNODE_OP_H
#define RDFNODE_OP_H

#include "postgres.h"
#include "fmgr.h"

/* rdfnode PostgreSQL data type */
extern Datum rdfnode_in(PG_FUNCTION_ARGS);
extern Datum rdfnode_out(PG_FUNCTION_ARGS);
extern Datum rdfnode_to_text(PG_FUNCTION_ARGS);
extern Datum rdfnode_cmp(PG_FUNCTION_ARGS);
extern Datum rdfnode_storage_lt(PG_FUNCTION_ARGS);
extern Datum rdfnode_storage_le(PG_FUNCTION_ARGS);
extern Datum rdfnode_storage_eq(PG_FUNCTION_ARGS);
extern Datum rdfnode_storage_ge(PG_FUNCTION_ARGS);
extern Datum rdfnode_storage_gt(PG_FUNCTION_ARGS);

/* rdfnode (custom data type)*/
extern Datum rdfnode_add_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_sub_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_mul_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_div_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_rdfnode(PG_FUNCTION_ARGS);

/* numeric data type */
extern Datum rdfnode_to_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_numeric(PG_FUNCTION_ARGS);
extern Datum numeric_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_ge_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_add_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_sub_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_mul_numeric(PG_FUNCTION_ARGS);
extern Datum rdfnode_div_numeric(PG_FUNCTION_ARGS);
extern Datum numeric_add_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_sub_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_mul_rdfnode(PG_FUNCTION_ARGS);
extern Datum numeric_div_rdfnode(PG_FUNCTION_ARGS);

/* float8 (double precision) data type */
extern Datum rdfnode_eq_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_to_float8(PG_FUNCTION_ARGS);
extern Datum float8_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_ge_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_add_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_sub_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_mul_float8(PG_FUNCTION_ARGS);
extern Datum rdfnode_div_float8(PG_FUNCTION_ARGS);
extern Datum float8_add_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_sub_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_mul_rdfnode(PG_FUNCTION_ARGS);
extern Datum float8_div_rdfnode(PG_FUNCTION_ARGS);

/* float4 (real) data type */
extern Datum rdfnode_to_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_float4(PG_FUNCTION_ARGS);
extern Datum float4_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_ge_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_add_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_sub_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_mul_float4(PG_FUNCTION_ARGS);
extern Datum rdfnode_div_float4(PG_FUNCTION_ARGS);
extern Datum float4_add_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_sub_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_mul_rdfnode(PG_FUNCTION_ARGS);
extern Datum float4_div_rdfnode(PG_FUNCTION_ARGS);

/* int8 (bigint) data type*/
extern Datum rdfnode_to_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_int8(PG_FUNCTION_ARGS);
extern Datum int8_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_ge_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_add_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_sub_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_mul_int8(PG_FUNCTION_ARGS);
extern Datum rdfnode_div_int8(PG_FUNCTION_ARGS);
extern Datum int8_add_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_sub_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_mul_rdfnode(PG_FUNCTION_ARGS);
extern Datum int8_div_rdfnode(PG_FUNCTION_ARGS);

/* int4 (int) data type */
extern Datum rdfnode_to_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_int4(PG_FUNCTION_ARGS);
extern Datum int4_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_ge_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_add_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_sub_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_mul_int4(PG_FUNCTION_ARGS);
extern Datum rdfnode_div_int4(PG_FUNCTION_ARGS);
extern Datum int4_add_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_sub_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_mul_rdfnode(PG_FUNCTION_ARGS);
extern Datum int4_div_rdfnode(PG_FUNCTION_ARGS);

/* int2 (smallint) data type */
extern Datum rdfnode_to_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_int2(PG_FUNCTION_ARGS);
extern Datum int2_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_ge_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_add_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_sub_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_mul_int2(PG_FUNCTION_ARGS);
extern Datum rdfnode_div_int2(PG_FUNCTION_ARGS);
extern Datum int2_add_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_sub_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_mul_rdfnode(PG_FUNCTION_ARGS);
extern Datum int2_div_rdfnode(PG_FUNCTION_ARGS);

/* timestamptz (timestamp with time zone) */
extern Datum rdfnode_to_timestamptz(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_timestamptz(PG_FUNCTION_ARGS);
extern Datum timestamptz_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_timestamptz(PG_FUNCTION_ARGS);
extern Datum timestamptz_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_timestamptz(PG_FUNCTION_ARGS);
extern Datum timestamptz_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_timestamptz(PG_FUNCTION_ARGS);
extern Datum timestamptz_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_timestamptz(PG_FUNCTION_ARGS);
extern Datum timestamptz_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_timestamptz(PG_FUNCTION_ARGS);
extern Datum timestamptz_ge_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamptz_to_rdfnode(PG_FUNCTION_ARGS);

/* timestamp (timestamp without time zone) */
extern Datum rdfnode_to_timestamp(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_timestamp(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_timestamp(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_timestamp(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_timestamp(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_timestamp(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_timestamp(PG_FUNCTION_ARGS);
extern Datum timestamp_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamp_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamp_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamp_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamp_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamp_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum timestamp_ge_rdfnode(PG_FUNCTION_ARGS);

/* date */
extern Datum rdfnode_to_date(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_date(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_date(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_date(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_date(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_date(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_date(PG_FUNCTION_ARGS);
extern Datum date_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum date_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum date_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum date_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum date_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum date_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum date_ge_rdfnode(PG_FUNCTION_ARGS);

/* time (time without time zone) */
extern Datum rdfnode_to_time(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_time(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_time(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_time(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_time(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_time(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_time(PG_FUNCTION_ARGS);
extern Datum time_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum time_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum time_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum time_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum time_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum time_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum time_ge_rdfnode(PG_FUNCTION_ARGS);

/* timetz (time with time zone) */
extern Datum rdfnode_to_timetz(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_timetz(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_timetz(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_timetz(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_timetz(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_timetz(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_timetz(PG_FUNCTION_ARGS);
extern Datum timetz_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum timetz_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum timetz_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum timetz_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum timetz_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum timetz_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum timetz_ge_rdfnode(PG_FUNCTION_ARGS);

/* boolean */
extern Datum rdfnode_to_boolean(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_boolean(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_boolean(PG_FUNCTION_ARGS);
extern Datum boolean_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum boolean_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum boolean_neq_rdfnode(PG_FUNCTION_ARGS);

/* interval */
extern Datum rdfnode_to_interval(PG_FUNCTION_ARGS);
extern Datum rdfnode_eq_interval(PG_FUNCTION_ARGS);
extern Datum rdfnode_neq_interval(PG_FUNCTION_ARGS);
extern Datum rdfnode_lt_interval(PG_FUNCTION_ARGS);
extern Datum rdfnode_gt_interval(PG_FUNCTION_ARGS);
extern Datum rdfnode_le_interval(PG_FUNCTION_ARGS);
extern Datum rdfnode_ge_interval(PG_FUNCTION_ARGS);
extern Datum interval_to_rdfnode(PG_FUNCTION_ARGS);
extern Datum interval_eq_rdfnode(PG_FUNCTION_ARGS);
extern Datum interval_neq_rdfnode(PG_FUNCTION_ARGS);
extern Datum interval_lt_rdfnode(PG_FUNCTION_ARGS);
extern Datum interval_gt_rdfnode(PG_FUNCTION_ARGS);
extern Datum interval_le_rdfnode(PG_FUNCTION_ARGS);
extern Datum interval_ge_rdfnode(PG_FUNCTION_ARGS);

#endif /* RDFNODE_OP_H */
