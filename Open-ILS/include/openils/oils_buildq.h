/**
	@file buildquery.h
	@brief Header for routines for building database queries.
*/

#ifndef OILS_BUILDQ_H
#define OILS_BUILDQ_H

#include "opensrf/osrf_json.h"

#ifdef __cplusplus
extern "C" {
#endif

struct StoredQ_;
typedef struct StoredQ_ StoredQ;

struct FromRelation_;
typedef struct FromRelation_ FromRelation;

struct SelectItem_;
typedef struct SelectItem_ SelectItem;

struct BindVar_;
typedef struct BindVar_ BindVar;

struct CaseBranch_;
typedef struct CaseBranch_ CaseBranch;

struct Datatype_;
typedef struct Datatype_ Datatype;

struct Expression_;
typedef struct Expression_ Expression;

struct QSeq_;
typedef struct QSeq_ QSeq;

struct OrderItem_;
typedef struct OrderItem_ OrderItem;

struct BuildSQLState_;
typedef struct BuildSQLState_ BuildSQLState;

struct IdNode_;
typedef struct IdNode_ IdNode;

/**
	@brief Stores various things related to the construction of an SQL query.
	
	This struct carries around various bits and scraps of context for constructing and
	executing an SQL query.  It also provides a way for buildSQLQuery() to return more than
	one kind of thing to its caller.  In particular it can return a status code, a list of
	error messages, and (if there is no error) an SQL string.
*/
struct BuildSQLState_ {
	dbi_conn dbhandle;            /**< Handle for the database connection */
	dbi_result result;            /**< Reference to current row or result set */
	int error;                    /**< Boolean; true if an error has occurred */
	osrfStringArray* error_msgs;  /**< Descriptions of errors, if any */
	growing_buffer* sql;          /**< To hold the constructed query */
	osrfHash* bindvar_list;       /**< List of bind variables used by this query, each with
	                                   a pointer to the corresponding BindVar. */
	IdNode* query_stack;          /**< For avoiding infinite recursion of nested queries */
	IdNode* expr_stack;           /**< For avoiding infinite recursion of nested expressions */
	IdNode* from_stack;           /**< For avoiding infinite recursion of from clauses */
	int indent;                   /**< For prettifying SQL output: level of indentation */
	int defaults_usable;          /**< Boolean; if true, we can use unconfirmed default
	                                   values for bind variables */
	int values_required;          /**< Boolean: if true, we need values for a bind variables */
	int panic;                    /**< Boolean: set to true if database connection dies */
};

typedef enum {
	QT_SELECT,
	QT_UNION,
	QT_INTERSECT,
	QT_EXCEPT
} QueryType;

struct StoredQ_ {
	StoredQ*      next;
	int           id;
	QueryType     type;
	int           use_all;        /**< Boolean */
	int           use_distinct;   /**< Boolean */
	FromRelation* from_clause;
	Expression*   where_clause;
	SelectItem*   select_list;
	QSeq*         child_list;
	Expression*   having_clause;
	OrderItem*    order_by_list;
	Expression*   limit_count;
	Expression*   offset_count;
};

typedef enum {
	FRT_RELATION,
	FRT_SUBQUERY,
	FRT_FUNCTION
} FromRelationType;

typedef enum {
	JT_NONE,
	JT_INNER,
	JT_LEFT,
	JT_RIGHT,
	JT_FULL
} JoinType;

struct FromRelation_ {
	FromRelation*    next;
	int              id;
	FromRelationType type;
	char*            table_name;
	char*            class_name;
	int              subquery_id;
	StoredQ*         subquery;
	int              function_call_id;
	Expression*      function_call;
	char*            table_alias;
	int              parent_relation_id;
	int              seq_no;
	JoinType         join_type;
	Expression*      on_clause;
	FromRelation*    join_list;
};

struct SelectItem_ {
	SelectItem* next;
	int         id;
	int         stored_query_id;
	int         seq_no;
	Expression* expression;
	char*       column_alias;
	int         grouped_by;        // Boolean
};

typedef enum {
	BIND_STR,
	BIND_NUM,
	BIND_STR_LIST,
	BIND_NUM_LIST
} BindVarType;

struct BindVar_ {
	BindVar*    next;
	char*       name;
	char*       label;
	BindVarType type;
	char*       description;
	jsonObject* default_value;
	jsonObject* actual_value;
};

struct CaseBranch_ {
	CaseBranch* next;
	int id;
	Expression* condition;
	Expression* result;
};

struct Datatype_ {
	Datatype* next;
	int       id;
	char*     datatype_name;
	int       is_numeric;          // Boolean
	int       is_composite;        // Boolean
};

typedef enum {
	EXP_BETWEEN,
	EXP_BIND,
	EXP_BOOL,
	EXP_CASE,
	EXP_CAST,
	EXP_COLUMN,
	EXP_EXIST,
	EXP_FUNCTION,
	EXP_IN,
	EXP_ISNULL,
	EXP_NULL,
	EXP_NUMBER,
	EXP_OPERATOR,
    EXP_SERIES,
	EXP_STRING,
	EXP_SUBQUERY
} ExprType;

struct Expression_ {
	Expression* next;
	int         id;
	ExprType    type;
	int         parenthesize;       // Boolean
	int         parent_expr_id;
	int         seq_no;
	char*       literal;
	char*       table_alias;
	char*       column_name;
	Expression* left_operand;
	char*       op;                 // Not called "operator" because that's a keyword in C++
	Expression* right_operand;
	int         subquery_id;
	StoredQ*    subquery;
	Datatype*   cast_type;
	int         negate;             // Boolean
	BindVar*    bind;
	Expression* subexp_list;        // Linked list of subexpressions
	CaseBranch* branch_list;        // Linked list of CASE branches
	// The next column comes, not from query.expression,
	// but from query.function_sig:
	char*       function_name;
};

struct QSeq_ {
	QSeq*    next;
	int      id;
	int      parent_query_id;
	int      seq_no;
	StoredQ* child_query;
};

struct OrderItem_ {
	OrderItem* next;
	int        id;
	int        stored_query_id;
	int        seq_no;
	Expression* expression;
};

BuildSQLState* buildSQLStateNew( dbi_conn dbhandle );

void buildSQLStateFree( BuildSQLState* state );

void buildSQLCleanup( void );

const char* sqlAddMsg( BuildSQLState* state, const char* msg, ... );

StoredQ* getStoredQuery( BuildSQLState* state, int query_id );

jsonObject* oilsGetColNames( BuildSQLState* state, StoredQ* query );

void pop_id( IdNode** stack );

void storedQFree( StoredQ* sq );

void storedQCleanup( void );

int buildSQL( BuildSQLState* state, const StoredQ* query );

void oilsStoredQSetVerbose( void );

jsonObject* oilsFirstRow( BuildSQLState* state );

jsonObject* oilsNextRow( BuildSQLState* state );

jsonObject* oilsBindVarList( osrfHash* bindvar_list );

int oilsApplyBindValues( BuildSQLState* state, const jsonObject* bindings );

#ifdef __cplusplus
}
#endif

#endif
