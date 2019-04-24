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
            'settings',
            'standing_penalties',                                                  
            'addresses',                                                           
            'billing_address',                                                     
            'mailing_address',                                                     
            'stat_cat_entries',                                                    
            'waiver_entries',
            'usr_activity',
            'notes'
        ]
    };

    service.format_name = function(patron_obj) {
        var patron_name = ( patron_obj.prefix() ? patron_obj.prefix() + ' ' : '') +
            patron_obj.family_name() + ', ' +
            patron_obj.first_given_name() + ' ' +
            ( patron_obj.second_given_name() ? patron_obj.second_given_name() + ' ' : '' ) +
            ( patron_obj.suffix() ? patron_obj.suffix() : '');
        return patron_name;
    };

    service.get = function(userId, args) {
        var deferred = $q.defer();

        if (!userId) deferred.reject();

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

    service.getByBarcode = function(barcode, args) {
        return egNet.request(
            'open-ils.pcrud',
            'open-ils.pcrud.search.ac.atomic',
            egAuth.token(), {barcode:barcode}
        ).then( function(card) {
            if (card && angular.isArray(card) && card[0] && card[0].classname == 'ac') {
                return service.get(card[0].usr(), args)
            }
            return service.get(null);
        }) 
    };

    return service;
}]);

