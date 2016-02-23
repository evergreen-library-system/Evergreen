#include "opensrf/osrf_json.h"
#include "opensrf/log.h"

#ifndef OILS_UTILS_H
#define OILS_UTILS_H

// XXX replacing this with liboils_idl implementation
// #include "openils/fieldmapper_lookup.h"

#include "openils/idl_fieldmapper.h"

#include "oils_event.h"
#include "oils_constants.h"
#include "opensrf/osrf_app_session.h"
#include "opensrf/osrf_settings.h"
#include "opensrf/osrf_application.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
  Loads the IDL. Returns NULL on failure
  or a pointer to the IDL data structure on success.
  @param idl_filename If not provided, we'll fetch the 
  filename from the settings server
 */
osrfHash* oilsInitIDL( const char* idl_filename );

const char* oilsFMGetStringConst( const jsonObject* object, const char* field );

char* oilsFMGetString( const jsonObject* object, const char* field );

const jsonObject* oilsFMGetObject( const jsonObject* object, const char* field );

/**
  Sets the given field in the given object to the given string
  @param object The object to update
  @param field The field to change
  @param string The new data
  @return 0 if the field was updated successfully, -1 on error
  */
int oilsFMSetString( jsonObject* object, const char* field, const char* string );

/**
 * Returns the data stored in the id field of the object if it exists
 * returns -1 if the id field or the id value is not found
 */
long oilsFMGetObjectId( const jsonObject* obj );


/**
 * Checks if the user has each permission at the given org unit
 * Passing in a -1 for the orgid means to use the top level org unit
 * The first permission that fails causes the corresponding permission
 * failure event to be returned
 * returns NULL if all permissions succeed
 */
oilsEvent* oilsUtilsCheckPerms( int userid, int orgid, char* permissions[], int size );


/**
 * Performs a single request and returns the resulting data
 * Caller is responsible for freeing the returned response object
 */
jsonObject* oilsUtilsQuickReq( const char* service, const char* method,
		const jsonObject* params );

jsonObject* oilsUtilsQuickReqCtx( osrfMethodContext* ctx, const char* service,
		const char* method, const jsonObject* params );

jsonObject* oilsUtilsStorageReq( const char* method, const jsonObject* params );
jsonObject* oilsUtilsStorageReqCtx( osrfMethodContext* ctx, const char* method, const jsonObject* params );

jsonObject* oilsUtilsCStoreReq( const char* method, const jsonObject* params );
jsonObject* oilsUtilsCStoreReqCtx( osrfMethodContext* ctx, const char* method, const jsonObject* params );

/**
 * Searches the storage server for a user with the given username 
 * Caller is responsible for freeing the returned object
 */
jsonObject* oilsUtilsFetchUserByUsername( osrfMethodContext* ctx, const char* name );


/**
 * Returns the setting value
 * Caller must free the returned string
 */
char* oilsUtilsFetchOrgSetting( int orgid, const char* setting );


/**
 * Logs into the auth server with the given username and password
 * @return The authtoken string which must be de-allocated by the caller
 */
char* oilsUtilsLogin( const char* uname, const char* passwd, const char* type, int orgId );


/**
 * Fetches the requested workstation object by id
 */
jsonObject* oilsUtilsFetchWorkstation( long id );

jsonObject* oilsUtilsFetchUserByBarcode(osrfMethodContext* ctx, const char* barcode);

jsonObject* oilsUtilsFetchWorkstationByName( const char* name );


int oilsUtilsIsDBTrue( const char* val );

long oilsUtilsIntervalToSeconds( const char* interval );

/**
 * Creates actor.usr_activity entries
 * @return The number of rows created.  0 or 1.
 */
int oilsUtilsTrackUserActivity( osrfMethodContext* ctx, long usr, const char* ewho, const char* ewhat, const char* ehow );

/**
 * Returns the ID of the root org unit (parent_ou = NULL)
 */
int oilsUtilsGetRootOrgId();

#ifdef __cplusplus
}
#endif

#endif
