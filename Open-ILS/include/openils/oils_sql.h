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

void oilsSetSQLOptions( const char* module_name, int do_pcrud );
void oilsSetDBConnection( dbi_conn conn );
int oilsExtendIDL( void );
int str_is_true( const char* str );
char* buildQuery( osrfMethodContext* ctx, jsonObject* query, int flags );

int beginTransaction ( osrfMethodContext* );
int commitTransaction ( osrfMethodContext* );
int rollbackTransaction ( osrfMethodContext* );

int setSavepoint ( osrfMethodContext* );
int releaseSavepoint ( osrfMethodContext* );
int rollbackSavepoint ( osrfMethodContext* );

int doJSONSearch ( osrfMethodContext* ctx );

int doCreate( osrfMethodContext* ctx );
int doRetrieve( osrfMethodContext* ctx );
int doUpdate( osrfMethodContext* ctx );
int doDelete( osrfMethodContext* ctx );
int doSearch( osrfMethodContext* ctx );
int doIdList( osrfMethodContext* ctx );

#ifdef __cplusplus
}
#endif

#endif
