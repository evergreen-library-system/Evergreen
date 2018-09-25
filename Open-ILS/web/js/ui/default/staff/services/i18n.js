/**
 * egI18N : service for I18N and L10N functions
 *
 * This is a grab-bag of stuff related to I18N.
 *
 */

angular.module('egCoreMod')
.factory('egI18N', ['egStrings',
            function(egStrings) {
    return {
        ou_qualified_location_name : function(loc) {
            return egStrings.$replace(
                egStrings.LOCATION_NAME_OU_QUALIFIED,
                {
                    location_name : loc.name(),
                    owning_lib_shortname : loc.owning_lib().shortname()
                }
            );
        }        
    }
}]);
