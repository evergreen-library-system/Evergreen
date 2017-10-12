/**
 * egStrings : service for tracking page-specific string translations.
 *
 * Convience functions embedded herein are prefixed with "$" to avoid
 * collisions with string keys, which are linked directly to the 
 * service.
 *
 * egStrings.A_STRING = 'hello, world {{foo}';
 *
 * egStrings.$replace(egStrings.A_STRING, {foo : 'bar'})
 *
 */

angular.module('egCoreMod').factory('egStrings', 
['$interpolate', '$rootScope', function($interpolate, $rootScope) { 
    var service = {

        '$replace' : function(str, args) {
            if (!str) return '';
            return $interpolate(str)(args);
        },

        /**
         * Sets the page <title> value.  
         *
         * The title is composed of a dynamic and static component.
         * The dynamic component may optionally be compiled via
         * $interpolate'ion.  
         *
         * The dynamic component is subject to truncation if it exceeds 
         * titleTruncLevel length and a context value is also applied.
         *
         * Only components that have values applied are used.  When
         * both have a value, they are combined into a single string
         * separated by a - (by default).
         */
        titleTruncLevel : 12,
        setPageTitle : function(dynamic, context, dynargs) {

            if (!dynamic) {
                $rootScope.pageTitle = context || service.PAGE_TITLE_DEFAULT;
                return;
            }

            if (dynargs) dynamic = service.$replace(dynamic, dynargs);

            if (!context) {
                $rootScope.pageTitle = dynamic;
                return;
            }

            // only truncate when it's competing with a context value
            dynamic = dynamic.substring(0, service.titleTruncLevel);

            $rootScope.pageTitle = service.$replace(
                service.PAGE_TITLE_DYNAMIC_AND_CONTEXT, {
                    dynamic : dynamic,
                    context : context
                }
            );
        }
    };

    return service;
}]);
