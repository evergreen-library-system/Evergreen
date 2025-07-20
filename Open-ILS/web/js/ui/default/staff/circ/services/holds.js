/**
 * Holds, yo
 */

angular.module('egCoreMod')

.factory('egHolds',

       ['$uibModal','$q','egCore','egConfirmDialog','egAlertDialog','egWorkLog',
function($uibModal , $q , egCore , egConfirmDialog , egAlertDialog , egWorkLog) {

    var service = {};

    service.fetch_wide_holds = function(restrictions, order_by, limit, offset, options) {
        return egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.hold.wide_hash.stream',
            egCore.auth.token(),
            restrictions, order_by, limit, offset, options
        );
    }

    service.fetch_holds = function(hold_ids) {
        var deferred = $q.defer();

        // Fetch hold details in batches for better UI responsiveness.
        var batch_size = 5;
        var index = 0;

        function one_batch() {
            var ids = hold_ids.slice(index, index + batch_size)
                .filter(function(id) {return Boolean(id)}) // avoid nulls

            console.debug('egHolds.fetch_holds => ' + ids);
            index += batch_size;

            if (!ids.length) {
                deferred.resolve();
                return;
            }

            egCore.net.request(
                'open-ils.circ',
                'open-ils.circ.hold.details.batch.retrieve.authoritative',
                egCore.auth.token(), ids, {
                    include_current_copy : true,
                    include_usr          : true,
                    include_cancel_cause : true,
                    include_sms_carrier  : true,
                    include_requestor    : true
                }

            ).then(
                one_batch,  // kick off the next batch
                null, 
                function(hold_data) {
                    var hold = hold_data.hold;
                    hold_data.id = hold.id();
                    service.local_flesh(hold_data);
                    deferred.notify(hold_data);
                }
            );
        }

        one_batch(); // kick it off
        return deferred.promise;
    }


    service.cancel_holds = function(hold_ids) {
       
        return $uibModal.open({
            templateUrl : './circ/share/t_cancel_hold_dialog',
            backdrop: 'static',
            controller : 
                ['$scope', '$uibModalInstance', 'cancel_reasons',
                function($scope, $uibModalInstance, cancel_reasons) {
                    $scope.args = {
                        cancel_reason : 5,
                        cancel_reasons : cancel_reasons,
                        num_holds : hold_ids.length
                    };
                    
                    $scope.cancel = function($event) {
                        $uibModalInstance.dismiss();
                        $event.preventDefault();
                    }

                    $scope.ok = function() {

                        function cancel_one() {
                            var hold_id = hold_ids.pop();
                            if (!hold_id) {
                                $uibModalInstance.close();
                                return;
                            }
                            egCore.net.request(
                                'open-ils.circ', 'open-ils.circ.hold.cancel',
                                egCore.auth.token(), hold_id,
                                $scope.args.cancel_reason,
                                $scope.args.note
                            ).then(function(resp) {
                                if (evt = egCore.evt.parse(resp)) {
                                    egCore.audio.play(
                                        'warning.hold.cancel_failed');
                                    console.error('unable to cancel hold: ' 
                                        + evt.toString());
                                } else {
                                    egCore.net.request(
                                        'open-ils.circ', 'open-ils.circ.hold.details.retrieve',
                                        egCore.auth.token(), hold_id, {
                                            'suppress_notices': true,
                                            'suppress_transits': true,
                                            'suppress_mvr' : true,
                                            'include_usr' : true
                                    }).then(function(details) {
                                        //console.log('details', details);
                                        egWorkLog.record(
                                            egCore.strings.EG_WORK_LOG_CANCELED_HOLD
                                            ,{
                                                'action' : 'canceled_hold',
                                                'method' : 'open-ils.circ.hold.cancel',
                                                'hold_id' : hold_id,
                                                'patron_id' : details.hold.usr().id(),
                                                'user' : details.patron_last,
                                                'item' : details.copy ? details.copy.barcode() : null,
                                                'item_id' : details.copy ? details.copy.id() : null
                                            }
                                        );
                                    });
                                }
                                cancel_one();
                            });
                        }

                        cancel_one();
                    }
                }
            ],
            resolve : {
                cancel_reasons : function() {
                    return service.get_cancel_reasons().then(function(reasons) {
                        // only display reasons for manually canceling holds
                        return reasons.filter(function(r) {
                            return 't' === r.manual();
                        });
                    });
                }
            }
        }).result;
    }

    service.uncancel_holds = function(hold_ids) {
       
        return $uibModal.open({
            templateUrl : './circ/share/t_uncancel_hold_dialog',
            backdrop: 'static',
            controller : 
                ['$scope', '$uibModalInstance',
                function($scope, $uibModalInstance) {
                    $scope.args = {
                        num_holds : hold_ids.length
                    };
                    
                    $scope.cancel = function($event) {
                        $uibModalInstance.dismiss();
                        $event.preventDefault();
                    }

                    $scope.ok = function() {

                        function uncancel_one() {
                            var hold_id = hold_ids.pop();
                            if (!hold_id) {
                                $uibModalInstance.close();
                                return;
                            }
                            egCore.net.request(
                                'open-ils.circ', 'open-ils.circ.hold.uncancel',
                                egCore.auth.token(), hold_id
                            ).then(function(resp) {
                                if (evt = egCore.evt.parse(resp)) {
                                    egCore.audio.play(
                                        'warning.hold.uncancel_failed');
                                    console.error('unable to uncancel hold: ' 
                                        + evt.toString());
                                }
                                uncancel_one();
                            });
                        }

                        uncancel_one();
                    }
                }
            ]
        }).result;
    }

    service.get_cancel_reasons = function() {
        if (egCore.env.ahrcc) return $q.when(egCore.env.ahrcc.list);
        return egCore.pcrud.retrieveAll('ahrcc', {}, {atomic : true})
        .then(function(list) { return egCore.env.absorbList(list, 'ahrcc').list });
    }

    // Updates a batch of holds, notifies on each response.
    // new_values = array of hashes describing values to change,
    // including the id of the hold to change.
    // e.g. {id : 1, mint_condition : true}
    service.update_holds = function(new_values) {
        return egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.hold.update.batch',
            egCore.auth.token(), null, new_values).then(
            function(resp) {
                if (evt = egCore.evt.parse(resp)) {
                    egCore.audio.play(
                        'warning.hold.batch_update');
                    console.error('unable to batch update holds: '
                        + evt.toString());
                } else {
                    egCore.audio.play(
                        'success.hold.batch_update');
                }
            }
        );
    }

    service.set_copy_quality = function(hold_ids) {
        if (!hold_ids.length) return $q.when();
        return $uibModal.open({
            templateUrl : './circ/share/t_hold_copy_quality_dialog',
            backdrop: 'static',
            controller : 
                ['$scope', '$uibModalInstance',
                function($scope, $uibModalInstance) {

                    function update(val) {
                        var vals = hold_ids.map(function(hold_id) {
                            return {id : hold_id, mint_condition : val}})
                        service.update_holds(vals).finally(function() {
                            $uibModalInstance.close();
                        });
                    }
                    $scope.good = function() { update(true) }
                    $scope.any = function() { update(false) }
                    $scope.cancel = function() { $uibModalInstance.dismiss() }
                }
            ]
        }).result;
    }

    service.edit_pickup_lib = function(hold_ids) {
        if (!hold_ids.length) return $q.when();
        return $uibModal.open({
            templateUrl : './circ/share/t_hold_edit_pickup_lib',
            backdrop: 'static',
            controller : 
                ['$scope', '$uibModalInstance',
                function($scope, $uibModalInstance) {
                    $scope.cant_be_pickup = function (id) { return !egCore.org.CanHaveUsers(id); };
                    $scope.args = {};
                    $scope.ok = function() { 
                        var vals = hold_ids.map(function(hold_id) {
                            return {
                                id : hold_id, 
                                pickup_lib : $scope.args.org_unit.id()
                            }
                        });
                        service.update_holds(vals).finally(function() {
                            $uibModalInstance.close();
                        });
                    }
                    $scope.cancel = function() { $uibModalInstance.dismiss() }
                }
            ]
        }).result;
    }

    service.get_sms_carriers = function() {
        if (egCore.env.csc) return $q.when(egCore.env.csc.list);
        return egCore.pcrud.retrieveAll('csc', {}, {atomic : true})
        .then(function(list) { return egCore.env.absorbList(list, 'csc').list });
    }

    service.edit_notify_prefs = function(hold_ids) {
        if (!hold_ids.length) return $q.when();
        return $uibModal.open({
            templateUrl : './circ/share/t_hold_notification_prefs',
            backdrop: 'static',
            controller : 
                ['$scope', '$uibModalInstance', 'sms_carriers',
                function($scope, $uibModalInstance, sms_carriers) {
                    $scope.args = {}
                    $scope.sms_carriers = sms_carriers;
                    $scope.num_holds = hold_ids.length;
                    $scope.ok = function() { 

                        var vals = hold_ids.map(function(hold_id) {
                            var val = {id : hold_id};
                            angular.forEach(
                                ['email', 'phone', 'sms'],
                                function(type) {
                                    var key = type + '_notify';
                                    if ($scope.args['update_' + key]) 
                                        val[key] = $scope.args[key];
                                }
                            );
                            if ($scope.args.update_sms_carrier)
                                val.sms_carrier = $scope.args.sms_carrier.id();
                            return val;
                        });

                        service.update_holds(vals).finally(function() {
                            $uibModalInstance.close();
                        });
                    }
                    $scope.cancel = function() { $uibModalInstance.dismiss() }
                }
            ],
            resolve : {
                sms_carriers : service.get_sms_carriers
            }
        }).result;
    }

    service.edit_dates = function(hold_ids) {
        if (!hold_ids.length) return $q.when();

        // collects the fields from the dialog the user wishes to modify
        function relay_to_update(modal_scope) {
            var vals = hold_ids.map(function(hold_id) {
                var val = {id : hold_id};
                angular.forEach(
                    ['thaw_date', 'request_time', 'expire_time', 'shelf_expire_time'], 
                    function(field) {
                        if (modal_scope.args['modify_' + field]) { 
                            val[field] = modal_scope.args[field].toISOString();
                            if (field === 'thaw_date') {
                            //If we are setting the thaw_date, freeze the hold.
                                val['frozen'] = true;
                            }
                        }
                    }
                );

                return val;
            });

            console.log(JSON.stringify(vals,null,2));
            return service.update_holds(vals);
        }

        return $uibModal.open({
            templateUrl : './circ/share/t_hold_dates',
            backdrop: 'static',
            controller : 
                ['$scope', '$uibModalInstance',
                function($scope, $uibModalInstance) {
                    var today = new Date();
                    $scope.args = {
                        thaw_date : today,
                        request_time : today,
                        expire_time : today,
                        shelf_expire_time : today
                    }
                    $scope.num_holds = hold_ids.length;
                    $scope.ok = function() { 
                        relay_to_update($scope).then($uibModalInstance.close);
                    }
                    $scope.cancel = function() { $uibModalInstance.dismiss() }
                    $scope.minDate = new Date();
                    //watch for changes to the hold dates, and perform validations
                    $scope.$watch('args', function(newValue,oldValue,scope) {
                        if (newValue['thaw_date'] && newValue['thaw_date'] < today) {
                            $scope.args['thaw_date'] = today;
                            $scope.args.thaw_date_error = true;
                        }
                        if (newValue['thaw_date'] && newValue['thaw_date'] > today) {
                            $scope.args.thaw_date_error = false;
                        }
                    }, true);
                }
            ],
        }).result;
    }

    service.update_field_with_confirm = function(hold_ids, msg_key, field, value) {
        if (!hold_ids.length) return $q.when();

        return egConfirmDialog.open(
            egCore.strings[msg_key], '', {num_holds : hold_ids.length})
        .result.then(function() {

            var vals = hold_ids.map(function(hold_id) {
                val = {id : hold_id};
                val[field] = value;
                return val;
            });
            return service.update_holds(vals);
        });
    }

    service.suspend_holds = function(hold_ids) {
        return service.update_field_with_confirm(
            hold_ids, 'SUSPEND_HOLDS', 'frozen', true);
    }

    service.activate_holds = function(hold_ids) {
        return service.update_field_with_confirm(
            hold_ids, 'ACTIVATE_HOLDS', 'frozen', false);
    }

    service.set_top_of_queue = function(hold_ids) {
        return service.update_field_with_confirm(
            hold_ids, 'SET_TOP_OF_QUEUE', 'cut_in_line', true);
    }

    service.clear_top_of_queue = function(hold_ids) {
        return service.update_field_with_confirm(
            hold_ids, 'CLEAR_TOP_OF_QUEUE', 'cut_in_line', null);
    }

    service.transfer_to_marked_title = function(hold_ids) {
        if (!hold_ids.length) return $q.when();

        var bib_id = egCore.hatch.getLocalItem(
            'eg.circ.hold.title_transfer_target');

        if (!bib_id) {
            // no target marked
            return egAlertDialog.open(
                egCore.strings.NO_HOLD_TRANSFER_TITLE_MARKED).result;
        }

        return egConfirmDialog.open(
            egCore.strings.TRANSFER_HOLD_TO_TITLE, '', {
                num_holds : hold_ids.length,
                bib_id : bib_id
            }
        ).result.then(function() {
            return egCore.net.request(
                'open-ils.circ',
                'open-ils.circ.hold.change_title.specific_holds',
                egCore.auth.token(), bib_id, hold_ids);
        });
    }

    service.transfer_all_bib_holds_to_marked_title = function(bib_ids) {
        if (!bib_ids.length) return $q.when();

        var target_bib_id = egCore.hatch.getLocalItem(
            'eg.circ.hold.title_transfer_target');

        if (!target_bib_id) {
            // no target marked
            return egAlertDialog.open(
                egCore.strings.NO_HOLD_TRANSFER_TITLE_MARKED).result;
        }

        return egConfirmDialog.open(
            egCore.strings.TRANSFER_ALL_BIB_HOLDS_TO_TITLE, '', {
                num_bibs : bib_ids.length,
                bib_id : target_bib_id
            }
        ).result.then(function() {
            return egCore.net.request(
                'open-ils.circ',
                'open-ils.circ.hold.change_title',
                egCore.auth.token(), target_bib_id, bib_ids);
        });
    }

    // serially retargets each hold
    service.retarget = function(hold_ids) {
        if (!hold_ids.length) return $q.when();
        var deferred = $q.defer();

        egConfirmDialog.open(
            egCore.strings.RETARGET_HOLDS, '', 
            {hold_ids : hold_ids.join(',')}

        ).result.then(function() {

            function do_one() {
                var hold_id = hold_ids.pop();
                if (!hold_id) {
                    deferred.resolve();
                    return;
                }

                egCore.net.request(
                    'open-ils.circ',
                    'open-ils.circ.hold.reset',
                    egCore.auth.token(), hold_id).finally(do_one);
            }

            do_one(); // kick it off
        });

        return deferred.promise;
    }

    // fleshes orgs, etc. for hold data blobs retrieved from
    // open-ils.circ.hold.details[.batch].retrieve
    service.local_flesh = function(hold_data) {

        hold_data.status_string = 
            egCore.strings['HOLD_STATUS_' + hold_data.status] 
            || hold_data.status;

        var hold = hold_data.hold;
        var volume = hold_data.volume;
        hold.pickup_lib(egCore.org.get(hold.pickup_lib()));
        hold.current_shelf_lib(egCore.org.get(hold.current_shelf_lib()));
        hold_data.id = hold.id();

        // TODO: LP#1697954 fleshing calls below are deprecated in favor
        // of API fleshing.

        if (hold.requestor() && typeof hold.requestor() != 'object') {
            console.debug('fetching hold requestor');
            egCore.pcrud.retrieve('au',hold.requestor()).then(function(u) { hold.requestor(u) });
        }

        if (hold.canceled_by() && typeof hold.canceled_by() != 'object') {
            console.debug('fetching hold canceled_by');
            egCore.pcrud.retrieve('au',hold.canceled_by()).then(function(u) { hold.canceled_by(u) });
        }

        if (hold.cancel_cause() && typeof hold.cancel_cause() != 'object') {
            console.debug('fetching hold cancel cause');
            egCore.pcrud.retrieve('ahrcc',hold.cancel_cause()).then(function(c) { hold.cancel_cause(c) });
        }

        if (hold.usr() && typeof hold.usr() != 'object') {
            console.debug('fetching hold user');
            egCore.pcrud.retrieve('au',hold.usr()).then(function(u) { hold.usr(u) });
        }

        if (hold.sms_carrier() && typeof hold.sms_carrier() != 'object') {
            console.debug('fetching sms carrier');
            egCore.pcrud.retrieve('csc',hold.sms_carrier()).then(function(c) { hold.sms_carrier(c) });
        }

        // current_copy is not always fleshed in the API
        if (hold.current_copy() && typeof hold.current_copy() != 'object') {
            hold.current_copy(hold_data.copy);
        }

        if (hold.current_copy()) {
            // likewise, current_copy's status isn't fleshed in the API
            if(hold.current_copy().status() !== null &&
               typeof hold.current_copy().status() != 'object')
                egCore.pcrud.retrieve('ccs',hold.current_copy().status()
                    ).then(function(c) { hold.current_copy().status(c) });
        
            // current_copy's shelving location position isn't always accessible
            if (hold.current_copy().location()) {
                //console.debug('fetching hold copy location order');
                var location_id;
                if (typeof hold.current_copy().location() != 'object') {
                    location_id = hold.current_copy().location();
                } else {
                    location_id = hold.current_copy().location().id();
                }
                egCore.pcrud.search(
                    'acplo',
                    {location: location_id, org: egCore.auth.user().ws_ou()},
                    null,
                    {atomic:true}
                ).then(function(orders) {
                    if(orders[0]){
                        hold_data.hold._copy_location_position = orders[0].position();
                    } else {
                        hold_data.hold._copy_location_position = 999;
                    }
                });
            }

            //Call number affixes are not always fleshed in the API
            if (hold_data.volume.prefix) {
                //console.debug('fetching call number prefix');
                //console.log(hold_data.volume.prefix());
                egCore.pcrud.retrieve('acnp',hold_data.volume.prefix())
                .then(function(p) {hold_data.volume.prefix = p.label(); hold_data.volume.prefix_sortkey = p.label_sortkey()});
            }
            if (hold_data.volume.suffix) {
                //console.debug('fetching call number suffix');
                //console.log(hold_data.volume.suffix());
                egCore.pcrud.retrieve('acns',hold_data.volume.suffix())
                .then(function(s) {hold_data.volume.suffix = s.label(); hold_data.volume.suffix_sortkey = s.label_sortkey()});
            }
        }
    }

    return service;
}])

/**  
 * Action handlers for the common Hold grid UI.
 * These generally scrub the data for valid input then pass the
 * holds / copies / etc. off to the relevant action in egHolds or egCirc.
 *
 * Caller must apply a reset_page function, which is called after 
 * most actionis are performed.
 */
.factory('egHoldGridActions', 
       ['$window','$location','$timeout','egCore','egHolds','egCirc',
function($window , $location , $timeout , egCore , egHolds , egCirc) {
    
    var service = {};

    service.refresh = function() {
        console.error('egHoldGridActions.refresh not defined!');
    }

    service.cancel_hold = function(items) {
        var hold_ids = items.filter(function(item) {
            return !item.hold.cancel_time();
        }).map(function(item) {return item.hold.id()});

        return egHolds.cancel_holds(hold_ids).then(service.refresh);
    }

    service.cancel_hold_wide = function(items) {
        var hold_ids = items.filter(function(item) {
            return !item.hold.cancel_time;
        }).map(function(item) {return item.hold.id});

        return egHolds.cancel_holds(hold_ids).then(service.refresh);
    }

    service.uncancel_hold = function(items) {
        var hold_ids = items.filter(function(item) {
            return item.hold.cancel_time();
        }).map(function(item) {return item.hold.id()});

        return egHolds.uncancel_holds(hold_ids).then(service.refresh);
    }

    service.uncancel_hold_wide = function(items) {
        var hold_ids = items.filter(function(item) {
            return item.hold.cancel_time;
        }).map(function(item) {return item.hold.id});

        return egHolds.uncancel_holds(hold_ids).then(service.refresh);
    }

    // jump to circ list for either 1) the targeted copy or
    // 2) the hold target copy for copy-level holds
    service.show_recent_circs = function(items) {
        var focus = items.length == 1;
        angular.forEach(items, function(item) {
            if (item.copy) {
                var url = egCore.env.basePath +
                          '/cat/item/' +
                          item.copy.id() +
                          '/circ_list';
                $timeout(function() { var x = $window.open(url, '_blank'); if (focus) x.focus() });
            }
        });
    }

    // jump to circ list for either 1) the targeted copy or
    // 2) the hold target copy for copy-level holds
    service.show_recent_circs_wide = function(items) {
        var focus = items.length == 1;
        angular.forEach(items, function(item) {
            if (item.hold.cp_id) {
                var url = egCore.env.basePath +
                          '/cat/item/' +
                          item.hold.cp_id +
                          '/circ_list';
                $timeout(function() { var x = $window.open(url, '_blank'); if (focus) x.focus() });
            }
        });
    }

    service.show_patrons = function(items) {
        var focus = items.length == 1;
        angular.forEach(items, function(item) {
            var url = egCore.env.basePath +
                      'circ/patron/' +
                      item.hold.usr().id() +
                      '/holds';
            $timeout(function() { var x = $window.open(url, '_blank'); if (focus) x.focus() });
        });
    }

    service.show_patrons_wide = function(items) {
        var focus = items.length == 1;
        angular.forEach(items, function(item) {
            var url = egCore.env.basePath +
                      'circ/patron/' +
                      item.hold.usr_id +
                      '/holds';
            $timeout(function() { var x = $window.open(url, '_blank'); if (focus) x.focus() });
        });
    }

    service.show_holds_for_title = function(items) {
        var focus = items.length == 1;
        angular.forEach(items, function(item) {
            var url = '/eg2/staff/catalog/record/' + item.mvr.doc_id() + '/holds';
            $timeout(function() { var x = $window.open(url, '_blank'); if (focus) x.focus() });
        });
    }

    service.show_holds_for_title_wide = function(items) {
        var focus = items.length == 1;
        angular.forEach(items, function(item) {
            var url = '/eg2/staff/catalog/record/' + item.hold.record_id + '/holds';
            $timeout(function() { var x = $window.open(url, '_blank'); if (focus) x.focus() });
        });
    }


    function generic_update(items, action) {
        if (!items.length) return $q.when();
        var hold_ids = items.map(function(item) {return item.hold.id()});
        return egHolds[action](hold_ids).then(service.refresh);
    }

    function generic_update_wide(items, action) {
        if (!items.length) return $q.when();
        var hold_ids = items.map(function(item) {return item.hold.id});
        return egHolds[action](hold_ids).then(service.refresh);
    }

    service.set_copy_quality = function(items) {
        generic_update(items, 'set_copy_quality'); }
    service.edit_pickup_lib = function(items) {
        generic_update(items, 'edit_pickup_lib'); }
    service.edit_notify_prefs = function(items) {
        generic_update(items, 'edit_notify_prefs'); }
    service.edit_dates = function(items) {
        generic_update(items, 'edit_dates'); }
    service.suspend = function(items) {
        generic_update(items, 'suspend_holds'); }
    service.activate = function(items) {
        generic_update(items, 'activate_holds'); }
    service.set_top_of_queue = function(items) {
        generic_update(items, 'set_top_of_queue'); }
    service.clear_top_of_queue = function(items) {
        generic_update(items, 'clear_top_of_queue'); }
    service.transfer_to_marked_title = function(items) {
        generic_update(items, 'transfer_to_marked_title'); }

    service.set_copy_quality_wide = function(items) {
        generic_update_wide(items, 'set_copy_quality'); }
    service.edit_pickup_lib_wide = function(items) {
        generic_update_wide(items, 'edit_pickup_lib'); }
    service.edit_notify_prefs_wide = function(items) {
        generic_update_wide(items, 'edit_notify_prefs'); }
    service.edit_dates_wide = function(items) {
        generic_update_wide(items, 'edit_dates'); }
    service.suspend_wide = function(items) {
        generic_update_wide(items, 'suspend_holds'); }
    service.activate_wide = function(items) {
        generic_update_wide(items, 'activate_holds'); }
    service.set_top_of_queue_wide = function(items) {
        generic_update_wide(items, 'set_top_of_queue'); }
    service.clear_top_of_queue_wide = function(items) {
        generic_update_wide(items, 'clear_top_of_queue'); }
    service.transfer_to_marked_title_wide = function(items) {
        generic_update_wide(items, 'transfer_to_marked_title'); }

    service.mark_damaged = function(items) {
        angular.forEach(items, function(item) {
            if (item.copy) {
                egCirc.mark_damaged({
                    id: item.copy.id(),
                    barcode: item.copy.barcode()
                }).then(service.refresh);
            }
        });
    }

    service.mark_damaged_wide = function(items) {
        angular.forEach(items, function(item) {
            if (item.copy) {
                egCirc.mark_damaged({
                    id: item.hold.cp_id,
                    barcode: item.hold.cp_barcode
                }).then(service.refresh);
            }
        });
    }

    service.mark_discard = function(items) {
        var copies = items
            .filter(function(item) { return Boolean(item.copy) })
            .map(function(item) {
                return {id: item.copy.id(), barcode: item.copy.barcode()}
            });
        if (copies.length)
            egCirc.mark_discard(copies).then(service.refresh);
    }

    service.mark_missing = function(items) {
        var copies = items
            .filter(function(item) { return Boolean(item.copy) })
            .map(function(item) {
                return {id: item.copy.id(), barcode: item.copy.barcode()}
            });
        if (copies.length)
            egCirc.mark_missing(copies).then(service.refresh);
    }

    service.mark_missing_wide = function(items) {
        var copies = items
            .filter(function(item) { return Boolean(item.hold.cp_id) })
            .map(function(item) { return {id: item.hold.cp_id, barcode: item.hold.cp_barcode}; });
        if (copies.length)
            egCirc.mark_missing(copies).then(service.refresh);
    }

    service.mark_discard_wide = function(items) {
        var copies = items
            .filter(function(item) { return Boolean(item.hold.cp_id) })
            .map(function(item) { return {id: item.hold.cp_id, barcode: item.hold.cp_barcode}; });
        if (copies.length)
            egCirc.mark_discard(copies).then(service.refresh);
    }

    service.retarget = function(items) {
        var hold_ids = items.map(function(item) { return item.hold.id() });
        egHolds.retarget(hold_ids).then(service.refresh);
    }

    service.retarget_wide = function(items) {
        var hold_ids = items.map(function(item) { return item.hold.id });
        egHolds.retarget(hold_ids).then(service.refresh);
    }

    return service;
}])

/**
 * Hold details interface 
 */
.directive('egHoldDetails', function() {
    return {
        restrict : 'AE',
        templateUrl : './circ/share/t_hold_details',
        scope : {
            holdId : '=',
            // if set, called whenever hold details are retrieved.  The
            // argument is the hold blob returned from hold.details.retrieve
            holdRetrieved : '=',
            showPatron : '='
        },
        controller : [
                    '$scope','$uibModal','egCore','egHolds','egCirc',
            function($scope , $uibModal , egCore , egHolds , egCirc) {

                function draw() {
                    if (!$scope.holdId) return;

                    egCore.net.request(
                        'open-ils.circ',
                        'open-ils.circ.hold.details.retrieve.authoritative',
                        egCore.auth.token(), $scope.holdId, {
                            include_current_copy : true,
                            include_usr          : true,
                            include_cancel_cause : true,
                            include_sms_carrier  : true,
                            include_requestor    : true
                        }
                    ).then(function(hold_data) { 
                        egHolds.local_flesh(hold_data);
    
                        angular.forEach(hold_data, 
                            function(val, key) { $scope[key] = val });

                        // fetch + flesh the cancel_cause if needed
                        if ($scope.hold.cancel_cause() && typeof $scope.hold.cancel_cause() != 'object') {
                            egHolds.get_cancel_reasons().then(function() {
                                // egHolds caches the causes in egEnv
                                $scope.hold.cancel_cause(
                                    egCore.env.ahrcc.map[$scope.hold.cancel_cause()]);
                            })
                        }

                        if ($scope.hold.current_copy()) {
                            egCirc.flesh_copy_location($scope.hold.current_copy());
                        }

                        if ($scope.holdRetrieved)
                            $scope.holdRetrieved(hold_data);

                    });
                }

                $scope.resetPage = 1;
                $scope.resetsPerPage = 10;
                $scope.maximumPages = 25;
                $scope.resetsLoaded = false;
                $scope.reverseResetOrder = false;

                $scope.show_resets_tab = function() {
                    $scope.detail_tab = 'resets';
                    egCore.pcrud.search('ahrrre',
                        {hold : $scope.hold.id()},
                        {
                            flesh : 1,
                            flesh_fields : {ahrrre : ['reset_reason','requestor','requestor_workstation','previous_copy']},
                            limit : $scope.resetsPerPage * $scope.maximumPages
                        },
                        {atomic : true}
                    ).then(function(ents) {
                        // sort the reset notes by date
                        ents.sort(
                            function(a,b){
                                return Date.parse(a.reset_time()) - Date.parse(b.reset_time());
                            }
                        );
                        $scope.hold.reset_entries(ents);
                        $scope.filter_resets();
                        $scope.resetsLoaded = true;
                    });
                }

                $scope.filter_resets = function() {
                    if(
                        typeof($scope.hold) === 'undefined' ||
                        typeof($scope.hold.reset_entries) === 'undefined' ||
                        $scope.hold.reset_entries() === null
                    )
                        return;
                    var begin = (($scope.resetPage - 1) * $scope.resetsPerPage),
                        end = begin + $scope.resetsPerPage;
                    $scope.filteredResets = $scope.hold
                                                .reset_entries()
                                                .slice(begin,end);
                }

                $scope.reverse_reset_order = function() {
                    $scope.hold.reset_entries().reverse()
                    $scope.reverseResetOrder = !$scope.reverseResetOrder;
                    $scope.first_rs_page();
                }

                $scope.on_first_rs_page = function() {
                    return $scope.resetPage == 1;
                }

                $scope.has_next_rs_page = function() {
                    return $scope.resetPage < $scope.max_rs_pages();
                }

                $scope.max_rs_pages = function() {
                    if(typeof($scope.hold.reset_entries) === 'undefined' || $scope.hold.reset_entries() === null)
                        return 0;
                    return $scope.hold.reset_entries().length/$scope.resetsPerPage;
                }

                $scope.first_rs_page = function() {
                    $scope.resetPage = 1;
                }

                $scope.increment_rs_page = function() {
                    $scope.resetPage++;
                }

                $scope.decrement_rs_page = function() {
                    $scope.resetPage--;
                }

                $scope.$watch('resetPage',$scope.filter_resets);
                $scope.$watch('reverseResetOrder',$scope.filter_resets);

                $scope.show_notify_tab = function() {
                    $scope.detail_tab = 'notify';
                    egCore.pcrud.search('ahn',
                        {hold : $scope.hold.id()}, 
                        {flesh : 1, flesh_fields : {ahn : ['notify_staff']}}, 
                        {atomic : true}
                    ).then(function(nots) {
                        $scope.hold.notifications(nots);
                    });
                }

                $scope.delete_note = function(note) {
                    egCore.pcrud.remove(note).then(function() {
                        // remove the deleted note from the locally fleshed notes
                        $scope.hold.notes(
                            $scope.hold.notes().filter(function(n) {
                                return n.id() != note.id()
                            })
                        );
                    });
                }

                $scope.new_note = function() {
                    return $uibModal.open({
                        templateUrl : './circ/share/t_hold_note_dialog',
                        backdrop: 'static',
                        controller : 
                            ['$scope', '$uibModalInstance',
                            function($scope, $uibModalInstance) {
                                $scope.args = {};
                                $scope.ok = function() {
                                    $uibModalInstance.close($scope.args)
                                },
                                $scope.cancel = function($event) {
                                    $uibModalInstance.dismiss();
                                    $event.preventDefault();
                                }
                            }
                        ]
                    }).result.then(function(args) {
                        var note = new egCore.idl.ahrn();
                        note.hold($scope.hold.id());
                        note.staff(true);
                        note.slip(args.slip);
                        note.pub(args.pub); 
                        note.title(args.title);
                        note.body(args.body);
                        return egCore.pcrud.create(note).then(function(n) {
                            $scope.hold.notes().push(n);
                        });
                    });
                }

                $scope.new_notification = function() {
                    return $uibModal.open({
                        templateUrl : './circ/share/t_hold_notification_dialog',
                        backdrop: 'static',
                        controller : 
                            ['$scope', '$uibModalInstance',
                            function($scope, $uibModalInstance) {
                                $scope.args = {};
                                $scope.ok = function() {
                                    $uibModalInstance.close($scope.args)
                                },
                                $scope.cancel = function($event) {
                                    $uibModalInstance.dismiss();
                                    $event.preventDefault();
                                }
                            }
                        ]
                    }).result.then(function(args) {
                        var note = new egCore.idl.ahn();
                        note.hold($scope.hold.id());
                        note.method(args.method);
                        note.note(args.note);
                        note.notify_staff(egCore.auth.user().id());
                        note.notify_time('now');
                        return egCore.pcrud.create(note).then(function(n) {
                            n.notify_staff(egCore.auth.user());
                            $scope.hold.notifications().push(n);
                        });
                    });
                }

                $scope.$watch('holdId', function(newVal, oldVal) {
                    if (newVal != oldVal) draw();
                });

                draw();
            }
        ]
    }
})

 
