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
['$interpolate', function($interpolate) { 
    return {
        '$replace' : function(str, args) {
            if (!str) return '';
            return $interpolate(str)(args);
        }
    } 
}]);
