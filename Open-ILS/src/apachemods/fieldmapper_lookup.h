
#include <string.h>
#include <stdio.h>
#include "opensrf/osrf_list.h"
#include "opensrf/osrf_hash.h"

int isFieldmapper(char*);
char * fm_pton(char *, int);
int fm_ntop(char *, char *);

/** 
 * Returns a list of class names with the 
 * form [ hint, apiname, hint, apiname, ...]
 * This list is static and should *not* be freed by the caller
 */
osrfList* fm_classes();
