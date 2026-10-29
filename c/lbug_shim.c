// C shim between Lean and the Ladybug C API.
//
// Ownership: every native handle is a Lean external object. A child keeps a
// Lean reference to its parent (connection -> database, statement and result ->
// connection, follow-up result -> first result) and releases it in its
// finalizer after destroying the native handle, so no drop order can free a
// database or result that a child still uses.
//
// Results are copied into Lean `Value`s before the cursor moves, through
// constructor functions exported from Ladybug/Value.lean, so this file never
// depends on the memory layout of Lean inductive types.

#include <lean/lean.h>
#include <stdlib.h>
#include <string.h>
#include "lbug.h"

// --- Value constructors exported from Ladybug.Value.Export -----------------

extern lean_object* lean_lbug_mk_null(lean_object*);
extern lean_object* lean_lbug_mk_bool(uint8_t);
extern lean_object* lean_lbug_mk_int8(uint8_t);
extern lean_object* lean_lbug_mk_int16(uint16_t);
extern lean_object* lean_lbug_mk_int32(uint32_t);
extern lean_object* lean_lbug_mk_int64(uint64_t);
extern lean_object* lean_lbug_mk_uint8(uint8_t);
extern lean_object* lean_lbug_mk_uint16(uint16_t);
extern lean_object* lean_lbug_mk_uint32(uint32_t);
extern lean_object* lean_lbug_mk_uint64(uint64_t);
extern lean_object* lean_lbug_mk_int128(uint64_t, uint64_t);
extern lean_object* lean_lbug_mk_float(float);
extern lean_object* lean_lbug_mk_double(double);
extern lean_object* lean_lbug_mk_decimal(lean_object*);
extern lean_object* lean_lbug_mk_string(lean_object*);
extern lean_object* lean_lbug_mk_blob(lean_object*);
extern lean_object* lean_lbug_mk_uuid(lean_object*);
extern lean_object* lean_lbug_mk_date(uint32_t);
extern lean_object* lean_lbug_mk_timestamp(uint64_t);
extern lean_object* lean_lbug_mk_timestamp_ns(uint64_t);
extern lean_object* lean_lbug_mk_timestamp_ms(uint64_t);
extern lean_object* lean_lbug_mk_timestamp_sec(uint64_t);
extern lean_object* lean_lbug_mk_timestamp_tz(uint64_t);
extern lean_object* lean_lbug_mk_interval(uint32_t, uint32_t, uint64_t);
extern lean_object* lean_lbug_mk_internal_id(uint64_t, uint64_t);
extern lean_object* lean_lbug_mk_list(lean_object*);
extern lean_object* lean_lbug_mk_array(lean_object*);
extern lean_object* lean_lbug_mk_field(lean_object*, lean_object*);
extern lean_object* lean_lbug_mk_entry(lean_object*, lean_object*);
extern lean_object* lean_lbug_mk_struct(lean_object*);
extern lean_object* lean_lbug_mk_map(lean_object*);
extern lean_object* lean_lbug_mk_union(lean_object*, lean_object*);
extern lean_object* lean_lbug_mk_node(uint64_t, uint64_t, lean_object*, lean_object*);
extern lean_object* lean_lbug_mk_rel(uint64_t, uint64_t, uint64_t, uint64_t, uint64_t, uint64_t,
                                     lean_object*, lean_object*);
extern lean_object* lean_lbug_mk_path(lean_object*, lean_object*);

// --- Small helpers -----------------------------------------------------------

static lean_object* except_ok(lean_object* x) {
    lean_object* r = lean_alloc_ctor(1, 1, 0);
    lean_ctor_set(r, 0, x);
    return r;
}

static lean_object* except_error(const char* msg) {
    lean_object* r = lean_alloc_ctor(0, 1, 0);
    lean_ctor_set(r, 0, lean_mk_string(msg ? msg : "unknown Ladybug error"));
    return r;
}

// Take ownership of a string returned by Ladybug.
static lean_object* except_error_owned(char* msg) {
    lean_object* r = except_error(msg);
    if (msg) lbug_destroy_string(msg);
    return r;
}

static lean_object* option_some(lean_object* x) {
    lean_object* r = lean_alloc_ctor(1, 1, 0);
    lean_ctor_set(r, 0, x);
    return r;
}

static lean_object* io_ok(lean_object* x) { return lean_io_result_mk_ok(x); }

static lean_object* last_error_or(const char* fallback) {
    char* e = lbug_get_last_error();
    if (e) return except_error_owned(e);
    return except_error(fallback);
}

// Lean string from a string Ladybug allocated; frees it.
static lean_object* owned_string(char* s) {
    lean_object* r = lean_mk_string(s ? s : "");
    if (s) lbug_destroy_string(s);
    return r;
}

static void apply_to_child(b_lean_obj_arg f, lean_object* child) {
    lean_inc(f);
    lean_inc(child);
    lean_dec(lean_apply_1(f, child));
}

// --- External classes --------------------------------------------------------

typedef struct { lbug_database db; } db_box;
typedef struct { lbug_connection conn; lean_object* db; } conn_box;
typedef struct { lbug_prepared_statement stmt; lean_object* conn; } stmt_box;
typedef struct { lbug_query_result res; lean_object* parent; } result_box;
typedef struct { lbug_value* val; } value_box;

static lean_external_class* g_db_class = NULL;
static lean_external_class* g_conn_class = NULL;
static lean_external_class* g_stmt_class = NULL;
static lean_external_class* g_result_class = NULL;
static lean_external_class* g_value_class = NULL;

static void db_finalize(void* p) {
    db_box* b = p;
    lbug_database_destroy(&b->db);
    free(b);
}
static void db_foreach(void* p, b_lean_obj_arg f) { (void)p; (void)f; }

static void conn_finalize(void* p) {
    conn_box* b = p;
    lbug_connection_destroy(&b->conn);
    lean_dec(b->db);
    free(b);
}
static void conn_foreach(void* p, b_lean_obj_arg f) { apply_to_child(f, ((conn_box*)p)->db); }

static void stmt_finalize(void* p) {
    stmt_box* b = p;
    lbug_prepared_statement_destroy(&b->stmt);
    lean_dec(b->conn);
    free(b);
}
static void stmt_foreach(void* p, b_lean_obj_arg f) { apply_to_child(f, ((stmt_box*)p)->conn); }

static void result_finalize(void* p) {
    result_box* b = p;
    lbug_query_result_destroy(&b->res);
    lean_dec(b->parent);
    free(b);
}
static void result_foreach(void* p, b_lean_obj_arg f) { apply_to_child(f, ((result_box*)p)->parent); }

static void value_finalize(void* p) {
    value_box* b = p;
    lbug_value_destroy(b->val);
    free(b);
}
static void value_foreach(void* p, b_lean_obj_arg f) { (void)p; (void)f; }

// Registers the classes on first use. Pure functions such as the value
// constructors can run before module initialization finishes, so every
// allocation goes through this.
static void ensure_classes(void) {
    if (!g_value_class) {
        g_db_class = lean_register_external_class(db_finalize, db_foreach);
        g_conn_class = lean_register_external_class(conn_finalize, conn_foreach);
        g_stmt_class = lean_register_external_class(stmt_finalize, stmt_foreach);
        g_result_class = lean_register_external_class(result_finalize, result_foreach);
        g_value_class = lean_register_external_class(value_finalize, value_foreach);
    }
}

LEAN_EXPORT lean_obj_res lbug_lean_init(lean_obj_arg w) {
    (void)w;
    ensure_classes();
    return io_ok(lean_box(0));
}

static db_box* as_db(b_lean_obj_arg o) { return lean_get_external_data(o); }
static conn_box* as_conn(b_lean_obj_arg o) { return lean_get_external_data(o); }
static stmt_box* as_stmt(b_lean_obj_arg o) { return lean_get_external_data(o); }
static result_box* as_result(b_lean_obj_arg o) { return lean_get_external_data(o); }
static value_box* as_value(b_lean_obj_arg o) { return lean_get_external_data(o); }

// --- Library info ------------------------------------------------------------

LEAN_EXPORT lean_obj_res lbug_lean_version(lean_obj_arg w) {
    (void)w;
    return io_ok(owned_string(lbug_get_version()));
}

LEAN_EXPORT lean_obj_res lbug_lean_storage_version(lean_obj_arg w) {
    (void)w;
    return io_ok(lean_box_uint64(lbug_get_storage_version()));
}

// --- Database and connection -------------------------------------------------

LEAN_EXPORT lean_obj_res lbug_lean_db_open(b_lean_obj_arg path, uint64_t buffer_pool_size,
                                           uint64_t max_threads, uint8_t read_only,
                                           uint64_t max_db_size, lean_obj_arg w) {
    (void)w;
    ensure_classes();
    lbug_system_config cfg = lbug_default_system_config();
    if (buffer_pool_size > 0) cfg.buffer_pool_size = buffer_pool_size;
    if (max_threads > 0) cfg.max_num_threads = max_threads;
    if (max_db_size > 0) cfg.max_db_size = max_db_size;
    cfg.read_only = read_only != 0;
    db_box* b = calloc(1, sizeof(db_box));
    if (!b) return io_ok(except_error("out of memory"));
    if (lbug_database_init(lean_string_cstr(path), cfg, &b->db) != LbugSuccess) {
        free(b);
        return io_ok(last_error_or("cannot open database"));
    }
    return io_ok(except_ok(lean_alloc_external(g_db_class, b)));
}

LEAN_EXPORT lean_obj_res lbug_lean_conn_open(lean_obj_arg db, lean_obj_arg w) {
    (void)w;
    ensure_classes();
    conn_box* b = calloc(1, sizeof(conn_box));
    if (!b) {
        lean_dec(db);
        return io_ok(except_error("out of memory"));
    }
    if (lbug_connection_init(&as_db(db)->db, &b->conn) != LbugSuccess) {
        free(b);
        lean_dec(db);
        return io_ok(last_error_or("cannot open connection"));
    }
    b->db = db;  // the connection now owns this reference
    return io_ok(except_ok(lean_alloc_external(g_conn_class, b)));
}

// Wrap a query result, or turn a failed one into an error. `parent` is borrowed.
static lean_object* wrap_result(lbug_state st, lbug_query_result* res, b_lean_obj_arg parent) {
    ensure_classes();
    if (res->_query_result == NULL) return last_error_or("query failed");
    if (st != LbugSuccess || !lbug_query_result_is_success(res)) {
        lean_object* e = except_error_owned(lbug_query_result_get_error_message(res));
        lbug_query_result_destroy(res);
        return e;
    }
    result_box* b = malloc(sizeof(result_box));
    if (!b) {
        lbug_query_result_destroy(res);
        return except_error("out of memory");
    }
    b->res = *res;
    lean_inc(parent);
    b->parent = parent;
    return except_ok(lean_alloc_external(g_result_class, b));
}

LEAN_EXPORT lean_obj_res lbug_lean_conn_query(b_lean_obj_arg conn, b_lean_obj_arg q, lean_obj_arg w) {
    (void)w;
    lbug_query_result res = {0};
    lbug_state st = lbug_connection_query(&as_conn(conn)->conn, lean_string_cstr(q), &res);
    return io_ok(wrap_result(st, &res, conn));
}

LEAN_EXPORT lean_obj_res lbug_lean_conn_prepare(b_lean_obj_arg conn, b_lean_obj_arg q, lean_obj_arg w) {
    (void)w;
    ensure_classes();
    stmt_box* b = calloc(1, sizeof(stmt_box));
    if (!b) return io_ok(except_error("out of memory"));
    lbug_state st = lbug_connection_prepare(&as_conn(conn)->conn, lean_string_cstr(q), &b->stmt);
    if (b->stmt._prepared_statement == NULL) {
        free(b);
        return io_ok(last_error_or("prepare failed"));
    }
    if (st != LbugSuccess || !lbug_prepared_statement_is_success(&b->stmt)) {
        lean_object* e = except_error_owned(lbug_prepared_statement_get_error_message(&b->stmt));
        lbug_prepared_statement_destroy(&b->stmt);
        free(b);
        return io_ok(e);
    }
    lean_inc(conn);
    b->conn = conn;
    return io_ok(except_ok(lean_alloc_external(g_stmt_class, b)));
}

LEAN_EXPORT lean_obj_res lbug_lean_stmt_bind(b_lean_obj_arg stmt, b_lean_obj_arg name,
                                             b_lean_obj_arg val, lean_obj_arg w) {
    (void)w;
    lbug_state st = lbug_prepared_statement_bind_value(&as_stmt(stmt)->stmt, lean_string_cstr(name),
                                                       as_value(val)->val);
    if (st != LbugSuccess) return io_ok(last_error_or("cannot bind parameter"));
    return io_ok(except_ok(lean_box(0)));
}

LEAN_EXPORT lean_obj_res lbug_lean_conn_execute(b_lean_obj_arg conn, b_lean_obj_arg stmt, lean_obj_arg w) {
    (void)w;
    lbug_query_result res = {0};
    lbug_state st = lbug_connection_execute(&as_conn(conn)->conn, &as_stmt(stmt)->stmt, &res);
    return io_ok(wrap_result(st, &res, conn));
}

// --- Converting native values to Lean ------------------------------------------

static lean_object* convert(lbug_value* v, const char** err);

// Convert a list-like value's elements (list, array, recursive-rel node or rel list).
static lean_object* convert_list(lbug_value* v, const char** err) {
    uint64_t n = 0;
    if (lbug_value_get_list_size(v, &n) != LbugSuccess) {
        // Fixed-size ARRAY values: the size is part of the type.
        lbug_logical_type t;
        lbug_value_get_data_type(v, &t);
        lbug_state st = lbug_data_type_get_num_elements_in_array(&t, &n);
        lbug_data_type_destroy(&t);
        if (st != LbugSuccess) { *err = "cannot read list size"; return NULL; }
    }
    lean_object* arr = lean_mk_empty_array_with_capacity(lean_box(n));
    for (uint64_t i = 0; i < n; i++) {
        lbug_value e;
        if (lbug_value_get_list_element(v, i, &e) != LbugSuccess) {
            lean_dec(arr);
            *err = "cannot read list element";
            return NULL;
        }
        lean_object* x = convert(&e, err);
        if (!x) { lean_dec(arr); return NULL; }
        arr = lean_array_push(arr, x);
    }
    return arr;
}

static lean_object* convert_struct_fields(lbug_value* v, const char** err) {
    uint64_t n = 0;
    if (lbug_value_get_struct_num_fields(v, &n) != LbugSuccess) { *err = "cannot read struct"; return NULL; }
    lean_object* arr = lean_mk_empty_array_with_capacity(lean_box(n));
    for (uint64_t i = 0; i < n; i++) {
        char* name = NULL;
        lbug_value fv;
        if (lbug_value_get_struct_field_name(v, i, &name) != LbugSuccess ||
            lbug_value_get_struct_field_value(v, i, &fv) != LbugSuccess) {
            if (name) lbug_destroy_string(name);
            lean_dec(arr);
            *err = "cannot read struct field";
            return NULL;
        }
        lean_object* x = convert(&fv, err);
        if (!x) { lbug_destroy_string(name); lean_dec(arr); return NULL; }
        arr = lean_array_push(arr, lean_lbug_mk_field(owned_string(name), x));
    }
    return arr;
}

static int read_internal_id(lbug_value* idv, lbug_internal_id_t* out) {
    return lbug_value_get_internal_id(idv, out) == LbugSuccess;
}

static lean_object* read_label(lbug_value* lv) {
    char* s = NULL;
    if (lbug_value_get_string(lv, &s) != LbugSuccess) return lean_mk_string("");
    return owned_string(s);
}

typedef lbug_state (*prop_size_fn)(lbug_value*, uint64_t*);
typedef lbug_state (*prop_name_fn)(lbug_value*, uint64_t, char**);
typedef lbug_state (*prop_value_fn)(lbug_value*, uint64_t, lbug_value*);

static lean_object* convert_props(lbug_value* v, prop_size_fn size, prop_name_fn name_at,
                                  prop_value_fn value_at, const char** err) {
    uint64_t n = 0;
    if (size(v, &n) != LbugSuccess) { *err = "cannot read properties"; return NULL; }
    lean_object* arr = lean_mk_empty_array_with_capacity(lean_box(n));
    for (uint64_t i = 0; i < n; i++) {
        char* name = NULL;
        lbug_value pv;
        if (name_at(v, i, &name) != LbugSuccess || value_at(v, i, &pv) != LbugSuccess) {
            if (name) lbug_destroy_string(name);
            lean_dec(arr);
            *err = "cannot read property";
            return NULL;
        }
        lean_object* x = convert(&pv, err);
        if (!x) { lbug_destroy_string(name); lean_dec(arr); return NULL; }
        arr = lean_array_push(arr, lean_lbug_mk_field(owned_string(name), x));
    }
    return arr;
}

static lean_object* convert_node(lbug_value* v, const char** err) {
    lbug_value idv, lv;
    lbug_internal_id_t id;
    if (lbug_node_val_get_id_val(v, &idv) != LbugSuccess || !read_internal_id(&idv, &id) ||
        lbug_node_val_get_label_val(v, &lv) != LbugSuccess) {
        *err = "cannot read node";
        return NULL;
    }
    lean_object* props = convert_props(v, lbug_node_val_get_property_size, lbug_node_val_get_property_name_at,
                                       lbug_node_val_get_property_value_at, err);
    if (!props) return NULL;
    return lean_lbug_mk_node(id.table_id, id.offset, read_label(&lv), props);
}

static lean_object* convert_rel(lbug_value* v, const char** err) {
    lbug_value idv, sv, dv, lv;
    lbug_internal_id_t id, src, dst;
    if (lbug_rel_val_get_id_val(v, &idv) != LbugSuccess || !read_internal_id(&idv, &id) ||
        lbug_rel_val_get_src_id_val(v, &sv) != LbugSuccess || !read_internal_id(&sv, &src) ||
        lbug_rel_val_get_dst_id_val(v, &dv) != LbugSuccess || !read_internal_id(&dv, &dst) ||
        lbug_rel_val_get_label_val(v, &lv) != LbugSuccess) {
        *err = "cannot read relationship";
        return NULL;
    }
    lean_object* props = convert_props(v, lbug_rel_val_get_property_size, lbug_rel_val_get_property_name_at,
                                       lbug_rel_val_get_property_value_at, err);
    if (!props) return NULL;
    return lean_lbug_mk_rel(id.table_id, id.offset, src.table_id, src.offset, dst.table_id, dst.offset,
                            read_label(&lv), props);
}

#define GET_OR_FAIL(call, what) \
    if ((call) != LbugSuccess) { *err = "cannot read " what; return NULL; }

static lean_object* convert(lbug_value* v, const char** err) {
    if (lbug_value_is_null(v)) return lean_lbug_mk_null(lean_box(0));
    lbug_logical_type t;
    lbug_value_get_data_type(v, &t);
    lbug_data_type_id id = lbug_data_type_get_id(&t);
    lbug_data_type_destroy(&t);
    switch (id) {
    case LBUG_BOOL: { bool x; GET_OR_FAIL(lbug_value_get_bool(v, &x), "BOOL"); return lean_lbug_mk_bool(x); }
    case LBUG_SERIAL:
    case LBUG_INT64: { int64_t x; GET_OR_FAIL(lbug_value_get_int64(v, &x), "INT64"); return lean_lbug_mk_int64((uint64_t)x); }
    case LBUG_INT32: { int32_t x; GET_OR_FAIL(lbug_value_get_int32(v, &x), "INT32"); return lean_lbug_mk_int32((uint32_t)x); }
    case LBUG_INT16: { int16_t x; GET_OR_FAIL(lbug_value_get_int16(v, &x), "INT16"); return lean_lbug_mk_int16((uint16_t)x); }
    case LBUG_INT8: { int8_t x; GET_OR_FAIL(lbug_value_get_int8(v, &x), "INT8"); return lean_lbug_mk_int8((uint8_t)x); }
    case LBUG_UINT64: { uint64_t x; GET_OR_FAIL(lbug_value_get_uint64(v, &x), "UINT64"); return lean_lbug_mk_uint64(x); }
    case LBUG_UINT32: { uint32_t x; GET_OR_FAIL(lbug_value_get_uint32(v, &x), "UINT32"); return lean_lbug_mk_uint32(x); }
    case LBUG_UINT16: { uint16_t x; GET_OR_FAIL(lbug_value_get_uint16(v, &x), "UINT16"); return lean_lbug_mk_uint16(x); }
    case LBUG_UINT8: { uint8_t x; GET_OR_FAIL(lbug_value_get_uint8(v, &x), "UINT8"); return lean_lbug_mk_uint8(x); }
    case LBUG_INT128: {
        lbug_int128_t x;
        GET_OR_FAIL(lbug_value_get_int128(v, &x), "INT128");
        return lean_lbug_mk_int128(x.low, (uint64_t)x.high);
    }
    case LBUG_DOUBLE: { double x; GET_OR_FAIL(lbug_value_get_double(v, &x), "DOUBLE"); return lean_lbug_mk_double(x); }
    case LBUG_FLOAT: { float x; GET_OR_FAIL(lbug_value_get_float(v, &x), "FLOAT"); return lean_lbug_mk_float(x); }
    case LBUG_DATE: { lbug_date_t x; GET_OR_FAIL(lbug_value_get_date(v, &x), "DATE"); return lean_lbug_mk_date((uint32_t)x.days); }
    case LBUG_TIMESTAMP: {
        lbug_timestamp_t x; GET_OR_FAIL(lbug_value_get_timestamp(v, &x), "TIMESTAMP");
        return lean_lbug_mk_timestamp((uint64_t)x.value);
    }
    case LBUG_TIMESTAMP_NS: {
        lbug_timestamp_ns_t x; GET_OR_FAIL(lbug_value_get_timestamp_ns(v, &x), "TIMESTAMP_NS");
        return lean_lbug_mk_timestamp_ns((uint64_t)x.value);
    }
    case LBUG_TIMESTAMP_MS: {
        lbug_timestamp_ms_t x; GET_OR_FAIL(lbug_value_get_timestamp_ms(v, &x), "TIMESTAMP_MS");
        return lean_lbug_mk_timestamp_ms((uint64_t)x.value);
    }
    case LBUG_TIMESTAMP_SEC: {
        lbug_timestamp_sec_t x; GET_OR_FAIL(lbug_value_get_timestamp_sec(v, &x), "TIMESTAMP_SEC");
        return lean_lbug_mk_timestamp_sec((uint64_t)x.value);
    }
    case LBUG_TIMESTAMP_TZ: {
        lbug_timestamp_tz_t x; GET_OR_FAIL(lbug_value_get_timestamp_tz(v, &x), "TIMESTAMP_TZ");
        return lean_lbug_mk_timestamp_tz((uint64_t)x.value);
    }
    case LBUG_INTERVAL: {
        lbug_interval_t x; GET_OR_FAIL(lbug_value_get_interval(v, &x), "INTERVAL");
        return lean_lbug_mk_interval((uint32_t)x.months, (uint32_t)x.days, (uint64_t)x.micros);
    }
    case LBUG_INTERNAL_ID: {
        lbug_internal_id_t x; GET_OR_FAIL(lbug_value_get_internal_id(v, &x), "INTERNAL_ID");
        return lean_lbug_mk_internal_id(x.table_id, x.offset);
    }
    case LBUG_DECIMAL: {
        char* s = NULL; GET_OR_FAIL(lbug_value_get_decimal_as_string(v, &s), "DECIMAL");
        return lean_lbug_mk_decimal(owned_string(s));
    }
    case LBUG_STRING: {
        char* s = NULL; GET_OR_FAIL(lbug_value_get_string(v, &s), "STRING");
        return lean_lbug_mk_string(owned_string(s));
    }
    case LBUG_UUID: {
        char* s = NULL; GET_OR_FAIL(lbug_value_get_uuid(v, &s), "UUID");
        return lean_lbug_mk_uuid(owned_string(s));
    }
    case LBUG_BLOB: {
        uint8_t* data = NULL;
        uint64_t len = 0;
        GET_OR_FAIL(lbug_value_get_blob(v, &data, &len), "BLOB");
        lean_object* ba = lean_alloc_sarray(1, len, len);
        if (len > 0) memcpy(lean_sarray_cptr(ba), data, len);
        lbug_destroy_blob(data);
        return lean_lbug_mk_blob(ba);
    }
    case LBUG_LIST: { lean_object* a = convert_list(v, err); return a ? lean_lbug_mk_list(a) : NULL; }
    case LBUG_ARRAY: { lean_object* a = convert_list(v, err); return a ? lean_lbug_mk_array(a) : NULL; }
    case LBUG_STRUCT: { lean_object* a = convert_struct_fields(v, err); return a ? lean_lbug_mk_struct(a) : NULL; }
    case LBUG_UNION: {
        // The active member is stored at child 0. The type's fields are `tag`
        // followed by the members, and the C API does not say which member is
        // active, so the tag is known only for a single-member union.
        lbug_value member;
        if (lbug_value_get_list_element(v, 0, &member) != LbugSuccess) { *err = "cannot read UNION"; return NULL; }
        lean_object* x = convert(&member, err);
        if (!x) return NULL;
        uint64_t n = 0;
        char* tag = NULL;
        if (lbug_value_get_struct_num_fields(v, &n) != LbugSuccess || n != 2 ||
            lbug_value_get_struct_field_name(v, 1, &tag) != LbugSuccess)
            tag = NULL;
        return lean_lbug_mk_union(owned_string(tag), x);
    }
    case LBUG_MAP: {
        uint64_t n = 0;
        GET_OR_FAIL(lbug_value_get_map_size(v, &n), "MAP");
        lean_object* arr = lean_mk_empty_array_with_capacity(lean_box(n));
        for (uint64_t i = 0; i < n; i++) {
            lbug_value kv, vv;
            if (lbug_value_get_map_key(v, i, &kv) != LbugSuccess ||
                lbug_value_get_map_value(v, i, &vv) != LbugSuccess) {
                lean_dec(arr);
                *err = "cannot read map entry";
                return NULL;
            }
            lean_object* k = convert(&kv, err);
            if (!k) { lean_dec(arr); return NULL; }
            lean_object* x = convert(&vv, err);
            if (!x) { lean_dec(k); lean_dec(arr); return NULL; }
            arr = lean_array_push(arr, lean_lbug_mk_entry(k, x));
        }
        return lean_lbug_mk_map(arr);
    }
    case LBUG_NODE: return convert_node(v, err);
    case LBUG_REL: return convert_rel(v, err);
    case LBUG_RECURSIVE_REL: {
        lbug_value nl, rl;
        if (lbug_value_get_recursive_rel_node_list(v, &nl) != LbugSuccess ||
            lbug_value_get_recursive_rel_rel_list(v, &rl) != LbugSuccess) {
            *err = "cannot read path";
            return NULL;
        }
        lean_object* ns = convert_list(&nl, err);
        if (!ns) return NULL;
        lean_object* rs = convert_list(&rl, err);
        if (!rs) { lean_dec(ns); return NULL; }
        return lean_lbug_mk_path(ns, rs);
    }
    default:
        *err = "value of an unsupported Ladybug type";
        return NULL;
    }
}

// --- Query results -------------------------------------------------------------

LEAN_EXPORT lean_obj_res lbug_lean_result_columns(b_lean_obj_arg r, lean_obj_arg w) {
    (void)w;
    lbug_query_result* res = &as_result(r)->res;
    uint64_t n = lbug_query_result_get_num_columns(res);
    lean_object* arr = lean_mk_empty_array_with_capacity(lean_box(n));
    for (uint64_t i = 0; i < n; i++) {
        char* name = NULL;
        if (lbug_query_result_get_column_name(res, i, &name) != LbugSuccess) name = NULL;
        arr = lean_array_push(arr, owned_string(name));
    }
    return io_ok(arr);
}

// Except String (Option (Array Value)): the next row, copied out, or none at the end.
LEAN_EXPORT lean_obj_res lbug_lean_result_next(b_lean_obj_arg r, lean_obj_arg w) {
    (void)w;
    lbug_query_result* res = &as_result(r)->res;
    if (!lbug_query_result_has_next(res)) return io_ok(except_ok(lean_box(0)));
    lbug_flat_tuple tuple;
    if (lbug_query_result_get_next(res, &tuple) != LbugSuccess) return io_ok(last_error_or("cannot read row"));
    uint64_t n = lbug_query_result_get_num_columns(res);
    lean_object* row = lean_mk_empty_array_with_capacity(lean_box(n));
    for (uint64_t i = 0; i < n; i++) {
        lbug_value v;
        const char* err = NULL;
        lean_object* x = NULL;
        if (lbug_flat_tuple_get_value(&tuple, i, &v) == LbugSuccess) x = convert(&v, &err);
        else err = "cannot read column";
        if (!x) {
            lean_dec(row);
            lbug_flat_tuple_destroy(&tuple);
            return io_ok(except_error(err));
        }
        row = lean_array_push(row, x);
    }
    lbug_flat_tuple_destroy(&tuple);
    return io_ok(except_ok(option_some(row)));
}

// Option QueryResult: the result of the next statement of a multi-statement query.
LEAN_EXPORT lean_obj_res lbug_lean_result_next_result(b_lean_obj_arg r, lean_obj_arg w) {
    (void)w;
    lbug_query_result* res = &as_result(r)->res;
    if (!lbug_query_result_has_next_query_result(res)) return io_ok(lean_box(0));
    lbug_query_result next = {0};
    lbug_state st = lbug_query_result_get_next_query_result(res, &next);
    if (st != LbugSuccess) return io_ok(lean_box(0));
    // The follow-up result is owned by the first one; keep the first alive.
    return io_ok(option_some(wrap_result(LbugSuccess, &next, r)));
}

// --- Native values for parameters --------------------------------------------------

static lean_object* wrap_value(lbug_value* v) {
    ensure_classes();
    value_box* b = malloc(sizeof(value_box));
    b->val = v;
    return lean_alloc_external(g_value_class, b);
}

LEAN_EXPORT lean_obj_res lbug_lean_nv_null(lean_obj_arg u) { (void)u; return wrap_value(lbug_value_create_null()); }
LEAN_EXPORT lean_obj_res lbug_lean_nv_bool(uint8_t x) { return wrap_value(lbug_value_create_bool(x != 0)); }
LEAN_EXPORT lean_obj_res lbug_lean_nv_int8(uint8_t x) { return wrap_value(lbug_value_create_int8((int8_t)x)); }
LEAN_EXPORT lean_obj_res lbug_lean_nv_int16(uint16_t x) { return wrap_value(lbug_value_create_int16((int16_t)x)); }
LEAN_EXPORT lean_obj_res lbug_lean_nv_int32(uint32_t x) { return wrap_value(lbug_value_create_int32((int32_t)x)); }
LEAN_EXPORT lean_obj_res lbug_lean_nv_int64(uint64_t x) { return wrap_value(lbug_value_create_int64((int64_t)x)); }
LEAN_EXPORT lean_obj_res lbug_lean_nv_uint8(uint8_t x) { return wrap_value(lbug_value_create_uint8(x)); }
LEAN_EXPORT lean_obj_res lbug_lean_nv_uint16(uint16_t x) { return wrap_value(lbug_value_create_uint16(x)); }
LEAN_EXPORT lean_obj_res lbug_lean_nv_uint32(uint32_t x) { return wrap_value(lbug_value_create_uint32(x)); }
LEAN_EXPORT lean_obj_res lbug_lean_nv_uint64(uint64_t x) { return wrap_value(lbug_value_create_uint64(x)); }
LEAN_EXPORT lean_obj_res lbug_lean_nv_int128(uint64_t lo, uint64_t hi) {
    lbug_int128_t x = {lo, (int64_t)hi};
    return wrap_value(lbug_value_create_int128(x));
}
LEAN_EXPORT lean_obj_res lbug_lean_nv_float(float x) { return wrap_value(lbug_value_create_float(x)); }
LEAN_EXPORT lean_obj_res lbug_lean_nv_double(double x) { return wrap_value(lbug_value_create_double(x)); }
LEAN_EXPORT lean_obj_res lbug_lean_nv_string(b_lean_obj_arg s) {
    return wrap_value(lbug_value_create_string(lean_string_cstr(s)));
}
LEAN_EXPORT lean_obj_res lbug_lean_nv_uuid(b_lean_obj_arg s) {
    return wrap_value(lbug_value_create_uuid(lean_string_cstr(s)));
}
LEAN_EXPORT lean_obj_res lbug_lean_nv_decimal(b_lean_obj_arg s, uint32_t precision, uint32_t scale) {
    return wrap_value(lbug_value_create_decimal(lean_string_cstr(s), precision, scale));
}
LEAN_EXPORT lean_obj_res lbug_lean_nv_blob(b_lean_obj_arg b) {
    return wrap_value(lbug_value_create_blob(lean_sarray_cptr(b), lean_sarray_size(b)));
}
LEAN_EXPORT lean_obj_res lbug_lean_nv_date(uint32_t days) {
    lbug_date_t d = {(int32_t)days};
    return wrap_value(lbug_value_create_date(d));
}
LEAN_EXPORT lean_obj_res lbug_lean_nv_timestamp(uint64_t x) {
    lbug_timestamp_t t = {(int64_t)x};
    return wrap_value(lbug_value_create_timestamp(t));
}
LEAN_EXPORT lean_obj_res lbug_lean_nv_timestamp_ns(uint64_t x) {
    lbug_timestamp_ns_t t = {(int64_t)x};
    return wrap_value(lbug_value_create_timestamp_ns(t));
}
LEAN_EXPORT lean_obj_res lbug_lean_nv_timestamp_ms(uint64_t x) {
    lbug_timestamp_ms_t t = {(int64_t)x};
    return wrap_value(lbug_value_create_timestamp_ms(t));
}
LEAN_EXPORT lean_obj_res lbug_lean_nv_timestamp_sec(uint64_t x) {
    lbug_timestamp_sec_t t = {(int64_t)x};
    return wrap_value(lbug_value_create_timestamp_sec(t));
}
LEAN_EXPORT lean_obj_res lbug_lean_nv_timestamp_tz(uint64_t x) {
    lbug_timestamp_tz_t t = {(int64_t)x};
    return wrap_value(lbug_value_create_timestamp_tz(t));
}
LEAN_EXPORT lean_obj_res lbug_lean_nv_interval(uint32_t months, uint32_t days, uint64_t micros) {
    lbug_interval_t i = {(int32_t)months, (int32_t)days, (int64_t)micros};
    return wrap_value(lbug_value_create_interval(i));
}
LEAN_EXPORT lean_obj_res lbug_lean_nv_internal_id(uint64_t table, uint64_t offset) {
    lbug_internal_id_t i = {table, offset};
    return wrap_value(lbug_value_create_internal_id(i));
}

// A value of the template's type: NULL, or the type's default (an empty list
// for a list type). Used so that every element of a list parameter has the
// same type when some elements are NULL or empty.
LEAN_EXPORT lean_obj_res lbug_lean_nv_null_like(b_lean_obj_arg tmpl) {
    lbug_logical_type t;
    lbug_value_get_data_type(as_value(tmpl)->val, &t);
    lbug_value* v = lbug_value_create_null_with_data_type(&t);
    lbug_data_type_destroy(&t);
    return wrap_value(v);
}

LEAN_EXPORT lean_obj_res lbug_lean_nv_empty_like(b_lean_obj_arg tmpl) {
    lbug_logical_type t;
    lbug_value_get_data_type(as_value(tmpl)->val, &t);
    lbug_value* v = lbug_value_create_default(&t);
    lbug_data_type_destroy(&t);
    return wrap_value(v);
}

static lbug_value** native_values(b_lean_obj_arg arr, size_t* n) {
    *n = lean_array_size(arr);
    lbug_value** xs = malloc(sizeof(lbug_value*) * (*n > 0 ? *n : 1));
    for (size_t i = 0; i < *n; i++) xs[i] = as_value(lean_array_get_core(arr, i))->val;
    return xs;
}

// Except String NValue. An empty list has no element to take its type from, and
// Ladybug cannot bind LIST(ANY), so it is sent as an empty INT64[].
LEAN_EXPORT lean_obj_res lbug_lean_nv_list(b_lean_obj_arg arr) {
    size_t n;
    if (lean_array_size(arr) == 0) {
        lbug_logical_type elem, list;
        lbug_data_type_create(LBUG_INT64, NULL, 0, &elem);
        lbug_data_type_create(LBUG_LIST, &elem, 0, &list);
        lbug_value* v = lbug_value_create_default(&list);
        lbug_data_type_destroy(&list);
        lbug_data_type_destroy(&elem);
        return except_ok(wrap_value(v));
    }
    lbug_value** xs = native_values(arr, &n);
    lbug_value* out = NULL;
    lbug_state st = lbug_value_create_list(n, xs, &out);
    free(xs);
    if (st != LbugSuccess) return except_error("list elements must all have the same type");
    return except_ok(wrap_value(out));
}

LEAN_EXPORT lean_obj_res lbug_lean_nv_struct(b_lean_obj_arg names, b_lean_obj_arg vals) {
    size_t n;
    lbug_value** xs = native_values(vals, &n);
    const char** ns = malloc(sizeof(char*) * (n > 0 ? n : 1));
    for (size_t i = 0; i < n; i++) ns[i] = lean_string_cstr(lean_array_get_core(names, i));
    lbug_value* out = NULL;
    lbug_state st = lbug_value_create_struct(n, ns, xs, &out);
    free(xs);
    free(ns);
    if (st != LbugSuccess) return except_error("cannot create struct value");
    return except_ok(wrap_value(out));
}

LEAN_EXPORT lean_obj_res lbug_lean_nv_map(b_lean_obj_arg keys, b_lean_obj_arg vals) {
    size_t n, m;
    lbug_value** ks = native_values(keys, &n);
    lbug_value** vs = native_values(vals, &m);
    lbug_value* out = NULL;
    lbug_state st = lbug_value_create_map(n, ks, vs, &out);
    free(ks);
    free(vs);
    if (st != LbugSuccess) return except_error("map keys and values must each have one type");
    return except_ok(wrap_value(out));
}
