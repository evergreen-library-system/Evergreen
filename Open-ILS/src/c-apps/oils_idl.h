#include "opensrf/log.h"
#include "opensrf/utils.h"
#include "opensrf/osrf_hash.h"

osrfHash* oilsIDLInit( char* );
osrfHash* oilsIDL();
osrfHash* oilsIDLFindPath( char*, ... );

/* The oilsIDL hash looks like this:

{ aws : {
        classname       : "aws",
        fieldmapper     : "actor::workstation",
        tablename       : "actor.workstation",          optional
        sequence        : "actor.workstation_id_seq",   optional
        primarykey      : "id",
        virtual         : "true",                       optional, "true" | "false"
        fields          : {
                isnew : {
                        name            : "isnew",
                        array_position  : "0",
                        virtual         : "true",       "true" | "false"
                        primitive       : "number"      optional, JSON primitive (number, string, array,
                                                        object, bool)
                },
                ...
        },
        links           : {
                record : {
                        field           : "owning_lib", field above that links to another class
                        rel_type        : "has_a",      link type, "has_a" | "has_many" | "might_have"
                        class           : "aou",        the foreign class that is linked
                        key             : "id",         the foreign class's key that creates the link to "field"
                        map             : []            osrfStringArray used by cstore in "has_many" rel_types to
                                                        point through a linking class
                },
                ...
        },
        ...
}

*/

