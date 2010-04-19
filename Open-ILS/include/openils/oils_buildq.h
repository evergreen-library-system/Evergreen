/**
	@file buildquery.h
	@brief Header for routines for building database queries.
*/

#ifndef OILS_BUILDQ_H
#define OILS_BUILDQ_H

#ifdef __cplusplus
extern "C" {
#endif

struct StoredQ_;
typedef struct StoredQ_ StoredQ;

struct FromRelation_;
typedef struct FromRelation_ FromRelation;

struct SelectItem_;
typedef struct SelectItem_ SelectItem;

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
	
	This struct carries around various bits and scraps of context for constructing an SQL
	query.  It also provides a way for buildSQLQuery() to return more than one kind of thing
	to its caller.  In particular it can return a status code, a list of error messages, and
	(if there is no error) an SQL string.
*/
struct BuildSQLState_ {
	dbi_conn dbhandle;            /**< Handle for the database connection */
	int error;                    /**< Boolean; true if an error has occurred */
	osrfStringArray* error_msgs;  /**< Descriptions of errors, if any */
	growing_buffer* sql;          /**< To hold the constructed query */
	IdNode* query_stack;          /**< For avoiding infinite recursion of nested queries */
	IdNode* expr_stack;           /**< For avoiding infinite recursion of nested expressions */
	IdNode* from_stack;           /**< For avoiding infinite recursion of from clauses */
	int indent;                   /**< For prettifying output: level of indentation */
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
	OrderItem*    order_by_list;
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
	EXP_BETWEEN,
	EXP_BOOL,
	EXP_CASE,
	EXP_CAST,
	EXP_COLUMN,
	EXP_EXIST,
	EXP_FIELD,
	EXP_FUNCTION,
	EXP_IN,
	EXP_NOT_BETWEEN,
	EXP_NOT_EXIST,
	EXP_NOT_IN,
	EXP_NULL,
	EXP_NUMBER,
	EXP_OPERATOR,
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
	char*       op;
	Expression* right_operand;
	int         function_id;
	int         subquery_id;
	StoredQ*    subquery;
	int         cast_type_id;
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

void pop_id( IdNode** stack );

void storedQFree( StoredQ* sq );

void storedQCleanup( void );

int buildSQL( BuildSQLState* state, StoredQ* query );

void oilsStoredQSetVerbose( void );

#ifdef __cplusplus
}
#endif

#endif
