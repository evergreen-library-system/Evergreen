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

/**
  Returns the string value for field 'field' in the given object.
  This method calls jsonObjectToSimpleString so numbers will be
  returned as strings.
  @param object The object to inspect
  @param field The field whose value is requsted
  @return The string at the given position, if none exists, 
  then NULL is returned.  The caller must free the returned string
  */
char* oilsFMGetString( const jsonObject* object, const char* field );


/**
  Returns the jsonObject found at the specified field in the
  given object.
  @param object The object to inspect
  @param field The field whose value is requsted
  @return The found object or NULL if none exists.  Do NOT free the 
  returned object.
  */
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

jsonObject* oilsUtilsStorageReq( const char* method, const jsonObject* params );

jsonObject* oilsUtilsCStoreReq( const char* method, const jsonObject* params );

/**
 * Searches the storage server for a user with the given username 
 * Caller is responsible for freeing the returned object
 */
jsonObject* oilsUtilsFetchUserByUsername( const char* name );


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

jsonObject* oilsUtilsFetchUserByBarcode(const char* barcode);

jsonObject* oilsUtilsFetchWorkstationByName( const char* name );


int oilsUtilsIsDBTrue( const char* val );

#ifdef __cplusplus
}
#endif

#endif
