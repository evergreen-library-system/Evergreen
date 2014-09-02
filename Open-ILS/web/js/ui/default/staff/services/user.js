/** 
 * Service for fetching fleshed user objects.
 */

angular.module('egUserMod', ['egCoreMod'])

.factory('egUser', 
       ['$q','$timeout','egNet','egAuth','egOrg',
function($q,  $timeout,  egNet,  egAuth,  egOrg) {

    var service = {
        defaultFleshFields : [
            'card',                                                                
            'standing_penalties',                                                  
            'addresses',                                                           
            'billing_address',                                                     
            'mailing_address',                                                     
            'stat_cat_entries',                                                    
            'usr_activity' 
        ]
    };

    service.get = function(userId, args) {
        var deferred = $q.defer();

        var fields = service.defaultFleshFields;
        if (args) {
            if (args.useFields) { 
                // overridde flesh fields
                fields = args.useFields; 
            }
            if (args.addFields) {
                // append flesh fields
                fields = fields.concat(args.addFields);
            }
        }
            
        egNet.request(
            'open-ils.actor',
            'open-ils.actor.user.fleshed.retrieve',
            egAuth.token(), userId, fields).then(
            function(user) {
                if (user && user.classname == 'au') {
                    deferred.resolve(user);
                } else {
                    deferred.reject(user);
                }
            }
        );

        return deferred.promise;
    };

    return service;
}]);

