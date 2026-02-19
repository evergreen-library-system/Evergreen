/*
Copyright (C) 2010 Equinox Software Inc.
Scott McKellar <scott@esilibrary.com>

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
*/

/**
	@file oils_sql.h

	@brief Utility routines for translating JSON into SQL.
*/

#ifndef OILS_SQL_H
#define OILS_SQL_H

#ifdef __cplusplus
extern "C" {
#endif

int oilsInitializeDbiInstance( dbi_inst* instance );
dbi_conn oilsConnectDB( const char* mod_name, dbi_inst* instance );
void oilsSetSQLOptions( const char* module_name, int do_pcrud, int flesh_depth, int retail_vis_test );
void oilsSetDBConnection( dbi_conn conn );
int oilsIsDBConnected( dbi_conn handle );
int oilsExtendIDL( dbi_conn handle );
int str_is_true( const char* str );
char* buildQuery( osrfMethodContext* ctx, jsonObject* query, int flags );

char* oilsGetRelation( osrfHash* classdef );

int beginTransaction ( osrfMethodContext* ctx );
int commitTransaction ( osrfMethodContext* ctx );
int rollbackTransaction ( osrfMethodContext* ctx );

int setSavepoint ( osrfMethodContext* ctx );
int releaseSavepoint ( osrfMethodContext* ctx );
int rollbackSavepoint ( osrfMethodContext* ctx );

int doJSONSearch ( osrfMethodContext* ctx );

int doCreate( osrfMethodContext* ctx );
int doRetrieve( osrfMethodContext* ctx );
int doUpdate( osrfMethodContext* ctx );
int doDelete( osrfMethodContext* ctx );
int doSearch( osrfMethodContext* ctx );
int doIdList( osrfMethodContext* ctx );
int doCount( osrfMethodContext* ctx );

int is_identifier( const char* s);
int is_good_operator( const char* op );

int setAuditInfo( osrfMethodContext* ctx );

#ifdef __cplusplus
}
#endif

#endif
