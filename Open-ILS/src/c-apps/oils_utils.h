#include "objson/object.h"
#include "opensrf/log.h"
#include "openils/fieldmapper_lookup.h"
#include "oils_event.h"
#include "oils_constants.h"
#include "opensrf/osrf_app_session.h"

/**
  Returns the string value for field 'field' in the given object.
  This method calls jsonObjectToSimpleString so numbers will be
  returned as strings.
  @param object The object to inspect
  @param field The field whose value is requsted
  @return The string at the given position, if none exists, 
  then NULL is returned.  The caller must free the returned string
  */
char* oilsFMGetString( jsonObject* object, char* field );


/**
  Returns the jsonObject found at the specified field in the
  given object.
  @param object The object to inspect
  @param field The field whose value is requsted
  @return The found object or NULL if none exists.  Do NOT free the 
  returned object.
  */
jsonObject* oilsFMGetObject( jsonObject* object, char* field );

/**
  Sets the given field in the given object to the given string
  @param object The object to update
  @param field The field to change
  @param string The new data
  @return 0 if the field was updated successfully, -1 on error
  */
int oilsFMSetString( jsonObject* object, char* field, char* string );

/**
 * Returns the data stored in the id field of the object if it exists
 * returns -1 if the id field or the id value is not found
 */
long oilsFMGetObjectId( jsonObject* obj );


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
jsonObject* oilsUtilsQuickReq( char* service, char* method, jsonObject* params );

/**
 * Searches the storage server for a user with the given username 
 * Caller is responsible for freeing the returned object
 */
jsonObject* oilsUtilsFetchUserByUsername( char* name );


/**
 * Returns the setting value
 * Caller must free the returned string
 */
char* oilsUtilsFetchOrgSetting( int orgid, char* setting );


/**
 * Logs into the auth server with the given username and password
 * @return The authtoken string which must be de-allocated by the caller
 */
char* oilsUtilsLogin( char* uname, char* passwd, char* type, int orgId );

