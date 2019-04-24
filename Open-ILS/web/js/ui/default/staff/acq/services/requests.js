/**
 * AcqRequests, yo
 */

angular.module('egCoreMod')

.factory('egAcqRequests',

       ['$uibModal','$q','egCore','egOrg','ngToast',
function($uibModal , $q , egCore , egOrg , ngToast) {

    var service = {};

    var aur_fleshing = {

        flesh : 2,
        // aur   ->  cancel_reason
        // aur   ->  lineitem
        // aur   ->  pickup_lib
        // aur   ->  request_type
        // aur   ->  usr
        // aur   ->  usr            -> card

        flesh_fields : {
             'aur' : [
                 'cancel_reason'
                ,'lineitem'
                ,'pickup_lib'
                ,'request_type'
                ,'usr'
            ]
            ,'au'  : [
                 'card'
                ,'home_ou'
                ,'mailing_address'
                ,'billing_address'
                ,'settings'
            ]
        }
    };

    var aurs_fleshing = {

        flesh : 2,
        // aurs   ->  cancel_reason
        // aurs   ->  lineitem
        // aurs   ->  pickup_lib
        // aurs   ->  request_type
        // aurs   ->  request_status
        // aurs   ->  usr
        // aurs   ->  usr            -> card

        flesh_fields : {
             'aurs' : [
                 'cancel_reason'
                ,'lineitem'
                ,'pickup_lib'
                ,'request_type'
                ,'request_status'
                ,'usr'
            ]
            ,'au'  : [
                 'card'
                ,'home_ou'
                ,'mailing_address'
                ,'billing_address'
                ,'settings'
            ]
        }
    };

    service.aur_fleshing = function(newvalue) {
        if (newvalue) {
            aur_fleshing = newvalue;
        }
        return angular.copy(aur_fleshing);
    }

    service.aurs_fleshing = function(newvalue) {
        if (newvalue) {
            aurs_fleshing = newvalue;
        }
        return angular.copy(aurs_fleshing);
    }

    service.fetch_request = function(aur_id) {
        var deferred = $q.defer();
        egCore.pcrud.search(
            'aur', { id : aur_id }, aur_fleshing, { atomic : true, authoritative : true }
        ).then(function(requests) {
            deferred.resolve(requests[0]);
        });
        return deferred.promise;
    }

    service.fetch_request_with_status = function(aur_id) {
        var deferred = $q.defer();
        egCore.pcrud.search(
            'aurs', { id : aur_id }, aurs_fleshing, { atomic : true, authoritative : true }
        ).then(function(requests) {
            deferred.resolve(requests[0]);
        });
        return deferred.promise;
    }

    service.fetch_cancel_reasons = function() {
        var deferred = $q.defer();
        egCore.pcrud.retrieveAll(
            'acqcr', {}, {atomic : true, authoritative : true}
        ).then(function(cancel_reasons) {
            deferred.resolve(cancel_reasons);
        });
        return deferred.promise;
    }

    service.fetch_request_types = function() {
        var deferred = $q.defer();
        egCore.pcrud.retrieveAll(
            'aurt', {}, {atomic : true, authoritative : true}
        ).then(function(request_types) {
            deferred.resolve(request_types);
        });
        return deferred.promise;
    }

    service.fetch_request_status_types = function() {
        var deferred = $q.defer();
        egCore.pcrud.retrieveAll(
            'aurst', {}, {atomic : true, authoritative : true}
        ).then(function(request_status_types) {
            deferred.resolve(request_status_types);
        });
        return deferred.promise;
    }

    service.add_request_to_picklist = function (row) {
        egCore.pcrud.search('aurs', {
                id : row['id']
            }, aurs_fleshing, {
                atomic : true
            }
        ).then(function(requests) {
            var aur_obj = requests[0];
            var prepop = { // based on acq.lineitem_marc_attr_definition
                "1": [aur_obj.title(), aur_obj.article_title(), aur_obj.volume()].join(' '),
                "2": aur_obj.author(),
                "4": aur_obj.article_pages(),
                "7": aur_obj.upc(),
                "10": aur_obj.publisher(),
                "11": aur_obj.pubdate()
            }
            if (aur_obj.request_type().id() == "2") { /* Articles */
                prepop["6"] = aur_obj.isxn();
            } else {
                prepop["5"] = aur_obj.isxn();
            }
            location.href = "/eg/staff/acq/legacy/picklist/brief_record?ur="
                + aur_obj.id() + "&prepop=" + encodeURIComponent(js2JSON(prepop));
        });
    }

    service.view_picklist = function (row) {
        location.href = "/eg/staff/acq/legacy/picklist/view/" + row['lineitem.picklist'];
    }

    service.handle_request = function(row,mode,context_ou,callback) {
        if (mode!='create' && !row) { return; }
        return $uibModal.open({
            templateUrl: './acq/requests/t_edit',
            backdrop: 'static',
            controller: ['$scope',  '$uibModalInstance','egCore',
                         'request_and_extra','request_types','request_status_types',
                 function($m_scope , $uibModalInstance , egCore ,
                          request_and_extra , request_types , request_status_types ) {
                    var request = request_and_extra.request;
                    var extra = request_and_extra.extra || {};
                    var today = new Date();
                    today.setHours(0);
                    today.setMinutes(0);
                    today.setSeconds(0);
                    today.setMilliseconds(0);
                    $m_scope.minDate = today;
                    $m_scope.mode = mode;
                    $m_scope.request = request;
                    $m_scope.request_types = request_types;
                    $m_scope.extra = extra;
                    $m_scope.extra.user_obj = request.usr;
                    angular.forEach(['hold', 'email_notify'], function(field) {
                        if (request[field] == 't') {
                            request[field] = true;
                        } else if (request[field] == 'f' || typeof request[field] == 'undefined') {
                            request[field] = false;
                        }
                    });
                    if (request.request_type) {
                        if (typeof request.request_type.id != 'undefined') {
                            request.request_type = request.request_type.id;
                        }
                        angular.forEach(request_types,function(v,k) {
                            if (v.id() == request.request_type) {
                                $m_scope.extra.selected_request_type = v;
                            }
                        });
                    }
                    if (request.need_before) {
                        request.need_before = new Date(request.need_before);
                    }
                    if (request.pickup_lib) {
                        $m_scope.request.pickup_lib =
                            egCore.idl.fromHash('aou',request.pickup_lib);
                    } else {
                        $m_scope.request.pickup_lib =
                            egOrg.CanHaveVolumes(context_ou)
                            ? context_ou
                            : egOrg.get( egCore.auth.user().ws_ou() );
                    }
                    if (request.cancel_reason) {
                        $m_scope.request.cancel_reason =
                            egCore.idl.fromHash('acqcr',request.cancel_reason);
                        $m_scope.mode = 'view'; // TODO: want explicit uncancel?
                    }
                    if (request.request_status && request.request_status.id != 1) { // New
                        $m_scope.mode = 'view';
                    }
                    if (request.usr) {
                        if (typeof request.usr.id != 'undefined') {
                            $m_scope.extra.barcode = request.usr.card.barcode;
                            request.usr = request.usr.id;
                        }
                    }
                    $m_scope.cancel = function () {
                        $uibModalInstance.dismiss('canceled');
                    }
                    $m_scope.ok = function(request2,extra2) {
                        $uibModalInstance.close({
                             'request':request2
                            ,'extra':extra2
                        });
                    }
                    $m_scope.model_has_changed = false;
                    $m_scope.cant_have_vols = function (id) {
                        return !egCore.org.CanHaveVolumes(id);
                    }
                    $m_scope.find_user = function () {

                        $m_scope.request.usr = null;
                        $m_scope.extra.user_obj = null;
                        if (!$m_scope.extra.barcode) return;

                        egCore.net.request(
                            'open-ils.actor',
                            'open-ils.actor.get_barcodes',
                            egCore.auth.token(), egCore.auth.user().ws_ou(),
                            'actor', $m_scope.extra.barcode)

                        .then(function(resp) { // get_barcodes

                            if (evt = egCore.evt.parse(resp)) {
                                console.error(evt.toString());
                                return;
                            }

                            if (!resp || !resp[0]) {
                                $m_scope.request.usr = null;
                                return;
                            }

                            egCore.pcrud.search('au', {
                                    id : resp[0].id
                                }, {
                                    flesh : 1,
                                    flesh_fields : {
                                        'au'  : [
                                             'card'
                                            ,'home_ou'
                                            ,'mailing_address'
                                            ,'billing_address'
                                            ,'settings'
                                        ]
                                    }
                                },
                                { atomic : true }
                            ).then(function(users) {
                                var usr = egCore.idl.toHash(users[0]);
                                $m_scope.extra.user_obj = usr;
                                $m_scope.request.usr = usr.id;
                                $m_scope.request.pickup_lib = egOrg.get(usr.home_ou.id);
                                $m_scope.request.phone_notify = usr.day_phone;
                                angular.forEach(usr.settings, function(s) {
                                    if (s.name == 'opac.hold_notify') {
                                        if (s.value.match('phone')) {
                                            $m_scope.extra.phone_notify = true;
                                        }
                                        if (s.value.match('email')) {
                                            $m_scope.request.email_notify = true;
                                        }
                                    }
                                    if (s.name == 'opac.default_phone') {
                                        $m_scope.request.phone_notify = s.value.replace(/^"/,'').replace(/"$/,'');
                                    }
                                    if (s.name == 'opac.default_pickup_location') {
                                        $m_scope.request.pickup_lib =
                                            egOrg.get(s.value);
                                    }
                                });
                                return $m_scope.request;
                            });
                        });
                    }
                    $m_scope.$watch("extra.barcode", function(newVal, oldVal) {
                        if (newVal && newVal != oldVal) {
                            $m_scope.find_user();
                        }
                    });
                    $m_scope.$watch("extra.selected_request_type",
                        function(newVal, oldVal) {
                            if (newVal && newVal != oldVal) {
                                $m_scope.request.request_type = newVal.id();
                            }
                        }
                    );
            }],
            resolve : {
                 request_and_extra : function() {
                    if (mode=='create') {
                        var aur_obj = egCore.idl.toHash(new egCore.idl.aurs());
                        var extra = {};
                        if (row['usr']) {
                            return egCore.pcrud.search('au', {
                                    id : row['usr']
                                }, {
                                    flesh : 1,
                                    flesh_fields : {
                                        'au'  : [
                                             'card'
                                            ,'home_ou'
                                            ,'mailing_address'
                                            ,'billing_address'
                                            ,'settings'
                                        ]
                                    }
                                },
                                { atomic : true }
                            ).then(function(users) {
                                if (users.length > 0) {
                                    var usr = egCore.idl.toHash(users[0]);
                                    aur_obj.usr = usr.id;
                                    aur_obj.pickup_lib = egCore.idl.toHash(
                                        egOrg.get(usr.home_ou.id)
                                    );
                                    aur_obj.phone_notify = usr.day_phone;
                                    angular.forEach(usr.settings, function(s) {
                                        if (s.name == 'opac.hold_notify') {
                                            if (s.value.match('phone')) {
                                                extra.phone_notify = true;
                                            }
                                            if (s.value.match('email')) {
                                                aur_obj.email_notify = true;
                                            }
                                        }
                                        if (s.name == 'opac.default_phone') {
                                            aur_obj.phone_notify = s.value.replace(/^"/,'').replace(/"$/,'');
                                        }
                                        if (s.name == 'opac.default_pickup_location') {
                                            aur_obj.pickup_lib = egCore.idl.toHash(
                                                egOrg.get(s.value)
                                            );
                                        }
                                    });
                                }
                                return { 'request' : aur_obj, 'extra' : extra };
                            });
                        } else {
                            console.log('here');
                            return { 'request' : aur_obj, 'extra': extra };
                        }
                    } else {
                        return egCore.pcrud.search('aurs', {
                                id : row['id']
                            }, aurs_fleshing, {
                                atomic : true
                            }
                        ).then(function(requests) {
                            var aur_obj = egCore.idl.toHash(requests[0]);
                            var extra = {};
                            if (aur_obj.phone_notify) {
                                extra.phone_notify = true;
                            }
                            return { 'request' : aur_obj, 'extra' : extra };
                        });
                    }
                }
                ,request_types : function() {
                    return service.fetch_request_types();
                }
                ,request_status_types : function() {
                    return service.fetch_request_status_types();
                }
            }
        }).result.then(function(data) {
            delete data.request.request_status;
            delete data.request.home_ou;
            var aur_obj = new egCore.idl.fromHash('aur',data.request);
            if (aur_obj.need_before() && typeof aur_obj.need_before() == 'object') {
                aur_obj.need_before( aur_obj.need_before().toISOString() );
            }
            if (!data.extra.phone_notify) {
                aur_obj.phone_notify(null);
            }
            if (mode=='create') {
                aur_obj.isnew('t');
                aur_obj.pickup_lib( aur_obj.pickup_lib().id() );
                return egCore.net.request(
                    'open-ils.acq',
                    'open-ils.acq.user_request.create',
                    egCore.auth.token(), egCore.idl.toHash(aur_obj)
                ).then(function(resp) {
                    var evt = egCore.evt.parse(resp);
                    if (evt) {
                        ngToast.danger(egCore.strings.CREATE_USER_REQUEST_FAIL + ' : ' + evt.desc);
                    } else {
                        ngToast.success(egCore.strings.CREATE_USER_REQUEST_SUCCESS);
                    }
                    callback(resp);
                });
            } else {
                aur_obj.ischanged('t');
                return egCore.pcrud.apply(aur_obj).then(function(resp) {
                    var evt = egCore.evt.parse(resp);
                    if (evt) {
                        ngToast.danger(egCore.strings.EDIT_USER_REQUEST_FAIL + ' : ' + evt.desc);
                    } else {
                        ngToast.success(egCore.strings.EDIT_USER_REQUEST_SUCCESS);
                    }
                    callback(resp);
                });
            }
        }).catch(function(e) {
            console.log('caught',e);
        });
    }

    service.set_no_hold_requests = function(rows,callback) {
        var ids = rows.map(function(v,i,a) {
            return v.id;
        });
        return $uibModal.open({
            templateUrl: './acq/requests/t_set_no_hold',
            backdrop: 'static',
            controller: ['$scope',  '$uibModalInstance','egCore',
                 function($m_scope , $uibModalInstance , egCore ) {
                    $m_scope.ids = ids;
                    $m_scope.cancel = function () {
                        $uibModalInstance.dismiss('canceled');
                    }
                    $m_scope.ok = function(doit) {
                        $uibModalInstance.close(doit);
                    }
            }],
            resolve : {}
        }).result.then(function(cancel_reason) {
            return egCore.net.request(
                'open-ils.acq',
                'open-ils.acq.user_request.set_no_hold.batch',
                egCore.auth.token(), ids
            ).then(function(obj) {
                if (callback) {
                    callback(obj);
                }
            });
        }).catch(function(e) {
            console.log('caught',e);
        });
    }

    service.set_yes_hold_requests = function(rows,callback) {
        var ids = rows.map(function(v,i,a) {
            return v.id;
        });
        return $uibModal.open({
            templateUrl: './acq/requests/t_set_yes_hold',
            backdrop: 'static',
            controller: ['$scope',  '$uibModalInstance','egCore',
                 function($m_scope , $uibModalInstance , egCore ) {
                    $m_scope.ids = ids;
                    $m_scope.cancel = function () {
                        $uibModalInstance.dismiss('canceled');
                    }
                    $m_scope.ok = function(doit) {
                        $uibModalInstance.close(doit);
                    }
            }],
            resolve : {}
        }).result.then(function(cancel_reason) {
            return egCore.net.request(
                'open-ils.acq',
                'open-ils.acq.user_request.set_yes_hold.batch',
                egCore.auth.token(), ids
            ).then(function(obj) {
                if (callback) {
                    callback(obj);
                }
            });
        }).catch(function(e) {
            console.log('caught',e);
        });
    }

    service.cancel_requests = function(rows,callback) {
        var ids = rows.map(function(v,i,a) {
            return v.id;
        });
        return $uibModal.open({
            templateUrl: './acq/requests/t_cancel',
            backdrop: 'static',
            controller: ['$scope',  '$uibModalInstance','egCore','cancel_reasons',
                 function($m_scope , $uibModalInstance , egCore , cancel_reasons ) {
                    $m_scope.ids = ids;
                    $m_scope.cancel_reasons = cancel_reasons;
                    $m_scope.cancel = function () {
                        $uibModalInstance.dismiss('canceled');
                    }
                    $m_scope.ok = function(cancel_reason) {
                        $uibModalInstance.close(cancel_reason);
                    }
            }],
            resolve : {
                cancel_reasons : function() {
                    return service.fetch_cancel_reasons();
                }
            }
        }).result.then(function(cancel_reason) {
            return egCore.net.request(
                'open-ils.acq',
                'open-ils.acq.user_request.cancel.batch.atomic',
                egCore.auth.token(), ids, cancel_reason.id()
            ).then(function(obj) {
                if (callback) {
                    callback(obj);
                }
            });
        }).catch(function(e) {
            console.log('caught',e);
        });
    }

    service.clear_requests = function(rows,callback) {
        var ids = rows.map(function(v,i,a) {
            return v.id;
        });
        return $uibModal.open({
            templateUrl: './acq/requests/t_clear',
            backdrop: 'static',
            controller: ['$scope',  '$uibModalInstance','egCore',
                 function($m_scope , $uibModalInstance , egCore) {
                    $m_scope.ids = ids;
                    $m_scope.cancel = function () {
                        $uibModalInstance.dismiss('canceled');
                    }
                    $m_scope.ok = function(cancel_reason) {
                        $uibModalInstance.close(true);
                    }
            }],
            resolve : {}
        }).result.then(function(doit) {
            return egCore.net.request(
                'open-ils.acq',
                'open-ils.acq.clear_completed_user_requests',
                egCore.auth.token(), ids
            ).then(function(obj) {
                if (callback) {
                    callback(obj);
                }
            });
        }).catch(function(e) {
            console.log('caught',e);
        });
    }

    return service;
}])
;
