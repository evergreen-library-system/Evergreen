#include "objson/object.h"
#include "opensrf/log.h"
#include "openils/fieldmapper_lookup.h"

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
