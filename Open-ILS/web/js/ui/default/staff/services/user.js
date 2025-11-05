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
}])

.factory('egUserSummarySettings',
        ['$q','egAuth','egOrg','egEnv','egPCRUD',
function( $q , egAuth , egOrg , egEnv , egPCRUD) {
    var service = {};

    var common_user_setting_names = [
        'opac.default_phone',
        'opac.default_pickup_location',
        'circ.holds_behind_desk',
        'circ.collections.exempt',
        'opac.hold_notify',
        'opac.default_sms_notify',
        'opac.default_sms_carrier'
    ];

    service.getUserSettingTypes = function() {
        // try cache first
        if (egEnv.cust) { return $q.when(egEnv.cust.list); }

        // load common and workstation relevant user setting types
        var org_ids = egOrg.ancestors(egAuth.user().ws_ou(), true);
        return egPCRUD.search('cust', {
            '-or' : [
                { name : common_user_setting_names },
                { name : {
                    'in': {
                        select : { atevdef : ['opt_in_setting'] },
                        from : 'atevdef',
                        where : { '+atevdef' : { owner : org_ids } }
                    }
                } }
            ]
        }, {}, { atomic : true }

        ).then(function(types) {
            egEnv.absorbList(types, 'cust');
            return types;
        });
    };

    service.getSmsCarriers = function() {
        // short-circuit if SMS is disabled
        if (!egEnv.aous['sms.enable']) {
            return $q.when([]);
        }

        // try cache first
        if (egEnv.csc) {
            return $q.when(egEnv.csc.list);
        }

        // load SMS carriers
        return egPCRUD.search('csc',
            { active: 'true' }, {}, { atomic : true }
        ).then(function(carriers) {
            egEnv.absorbList(carriers, 'csc');
            return carriers;
        });
    };

    service.getSmsCarrierName = function(carrier_id) {
        if (!egEnv.aous['sms.enable'] || !(carrier_id+'').match(/^\d+$/)) {
            return null;
        }
        var carrier = egEnv.csc && egEnv.csc.map
            ? egEnv.csc.map[carrier_id]
            : null;
        return carrier ? carrier.name() : null;
    };

    service.formatNotify = function(notify_string) {
        var notify = [];
        notify_string = notify_string+'';
        if (notify_string.match(/phone/)) {
            notify.push('Phone');
        }
        if (notify_string.match(/email/)) {
            notify.push('Email');
        }
        if (egEnv.aous['sms.enable'] && notify_string.match(/sms/)) {
            notify.push('SMS');
        }
        return notify.join(', ');
    }

    // format common user settings for display (patron summary)
    service.formatSupportedSettings = function(settings) {
        return $q.all([
            // ensure setting types and SMS carriers are loaded
            service.getUserSettingTypes(),
            service.getSmsCarriers()

        ]).then(function() {
            // set up maps for lookups
            var types = (egEnv.cust || {}).map || {};
            var settings_map = {};
            if (angular.isArray(settings)) {
                angular.forEach(settings, function(setting) {
                    settings_map[setting.name()] = setting;
                });
            }

            // format each setting
            var formatted = [];
            angular.forEach(common_user_setting_names, function(name) {
                var value = null;
                var type = types[name];
                if (!type) { return; }

                // check if patron has a setting value
                try {
                    if (settings_map[name]) {
                        value = JSON.parse(settings_map[name].value());
                    }
                } catch (e) {
                    console.error(
                        'Error parsing user setting value for ' + name
                    );
                    value = null;
                }

                // skip unsupported settings
                if (name.match(/_sms/)) {
                    if (!egEnv.aous['sms.enable']) {
                        return;
                    }
                }
                if (name === 'circ.holds_behind_desk') {
                    if (!egEnv.aous[
                        'circ.holds.behind_desk_pickup_supported'
                    ]) { return; }
                }

                // format specific settings
                if (name === 'opac.default_sms_carrier') {
                    value = service.getSmsCarrierName(value);

                } else if (name === 'opac.default_pickup_location') {
                    var aou = egOrg.get(value);
                    value = aou ? aou.shortname() : null;

                } else if (name === 'opac.hold_notify') {
                    value = service.formatNotify(value);

                } else if (type.datatype() === 'bool') {
                    value = (value+'').match(/^t/i) ? 'Yes' : 'No';
                }

                formatted.push({ label: type.label(), value: value });
            });

            return formatted;
        });
    };

    return service;
}]);

