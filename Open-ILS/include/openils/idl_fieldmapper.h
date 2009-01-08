/* This set of macros will emulate the old style libfieldmapper api
 * using the new liboils_idl interface.  You MUST initiallize liboils_idl!
 */ 

#ifndef FIELDMAPPER_API

#ifdef __cplusplus
extern "C" {
#endif

#ifndef OILS_IDL_API
#include "oils_idl.h"
#endif

#define FIELDMAPPER_API

#define fm_pton(x,y) oilsIDL_pton(x,y)
#define fm_ntop(x,y) oilsIDL_ntop(x,y)
#define isFieldmapper(x) oilsIDL_classIsFieldmapper(x)

#ifdef __cplusplus
}
#endif

#endif

