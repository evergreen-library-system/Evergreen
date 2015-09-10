/**
 * Holds, yo
 */

angular.module('egCoreMod')

.factory('egHolds',

       ['$modal','$q','egCore','egConfirmDialog','egAlertDialog',
function($modal , $q , egCore , egConfirmDialog , egAlertDialog) {

    var service = {};

    service.fetch_holds = function(hold_ids) {
        var deferred = $q.defer();

        // FIXME: large batches using .authoritative result in many 
        // stranded cstore backends on the server.  Needs investigation.
        // For now, collect holds in a series of small batches.
        // Fetch them serially both to avoid the above problem and
        // to maintain order.
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
                egCore.auth.token(), ids

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
       
        return $modal.open({
            templateUrl : './circ/share/t_cancel_hold_dialog',
            controller : 
                ['$scope', '$modalInstance', 'cancel_reasons',
                function($scope, $modalInstance, cancel_reasons) {
                    $scope.args = {
                        cancel_reason : 5,
                        cancel_reasons : cancel_reasons,
                        num_holds : hold_ids.length
                    };
                    
                    $scope.cancel = function($event) {
                        $modalInstance.dismiss();
                        $event.preventDefault();
                    }

                    $scope.ok = function() {

                        function cancel_one() {
                            var hold_id = hold_ids.pop();
                            if (!hold_id) {
                                $modalInstance.close();
                                return;
                            }
                            egCore.net.request(
                                'open-ils.circ', 'open-ils.circ.hold.cancel',
                                egCore.auth.token(), hold_id,
                                $scope.args.cancel_reason,
                                $scope.args.note
                            ).then(function(resp) {
                                if (evt = egCore.evt.parse(resp)) {
                                    console.error('unable to cancel hold: ' 
                                        + evt.toString());
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
                    return service.get_cancel_reasons();
                }
            }
        }).result;
    }

    service.uncancel_holds = function(hold_ids) {
       
        return $modal.open({
            templateUrl : './circ/share/t_uncancel_hold_dialog',
            controller : 
                ['$scope', '$modalInstance',
                function($scope, $modalInstance) {
                    $scope.args = {
                        num_holds : hold_ids.length
                    };
                    
                    $scope.cancel = function($event) {
                        $modalInstance.dismiss();
                        $event.preventDefault();
                    }

                    $scope.ok = function() {

                        function uncancel_one() {
                            var hold_id = hold_ids.pop();
                            if (!hold_id) {
                                $modalInstance.close();
                                return;
                            }
                            egCore.net.request(
                                'open-ils.circ', 'open-ils.circ.hold.uncancel',
                                egCore.auth.token(), hold_id
                            ).then(function(resp) {
                                if (evt = egCore.evt.parse(resp)) {
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
            egCore.auth.token(), null, new_values);
    }

    service.set_copy_quality = function(hold_ids) {
        if (!hold_ids.length) return $q.when();
        return $modal.open({
            templateUrl : './circ/share/t_hold_copy_quality_dialog',
            controller : 
                ['$scope', '$modalInstance',
                function($scope, $modalInstance) {

                    function update(val) {
                        var vals = hold_ids.map(function(hold_id) {
                            return {id : hold_id, mint_condition : val}})
                        service.update_holds(vals).finally(function() {
                            $modalInstance.close();
                        });
                    }
                    $scope.good = function() { update(true) }
                    $scope.any = function() { update(false) }
                    $scope.cancel = function() { $modalInstance.dismiss() }
                }
            ]
        }).result;
    }

    service.edit_pickup_lib = function(hold_ids) {
        if (!hold_ids.length) return $q.when();
        return $modal.open({
            templateUrl : './circ/share/t_hold_edit_pickup_lib',
            controller : 
                ['$scope', '$modalInstance',
                function($scope, $modalInstance) {
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
                            $modalInstance.close();
                        });
                    }
                    $scope.cancel = function() { $modalInstance.dismiss() }
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
        return $modal.open({
            templateUrl : './circ/share/t_hold_notification_prefs',
            controller : 
                ['$scope', '$modalInstance', 'sms_carriers',
                function($scope, $modalInstance, sms_carriers) {
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
                            $modalInstance.close();
                        });
                    }
                    $scope.cancel = function() { $modalInstance.dismiss() }
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
                        if (modal_scope.args['modify_' + field]) 
                            val[field] = modal_scope.args[field].toISOString();
                    }
                );

                return val;
            });

            console.log(JSON.stringify(vals,null,2));
            return service.update_holds(vals);
        }

        return $modal.open({
            templateUrl : './circ/share/t_hold_dates',
            controller : 
                ['$scope', '$modalInstance',
                function($scope, $modalInstance) {
                    var today = new Date();
                    $scope.args = {
                        thaw_date : today,
                        request_time : today,
                        expire_time : today,
                        shelf_expire_time : today
                    }
                    $scope.num_holds = hold_ids.length;
                    $scope.ok = function() { 
                        relay_to_update($scope).then($modalInstance.close);
                    }
                    $scope.cancel = function() { $modalInstance.dismiss() }
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
        hold.pickup_lib(egCore.org.get(hold.pickup_lib()));
        hold.current_shelf_lib(egCore.org.get(hold.current_shelf_lib()));
        hold_data.id = hold.id();

        if (hold.requestor() && typeof hold.requestor() != 'object')
            egCore.pcrud.retrieve('au',hold.requestor()).then(function(u) { hold.requestor(u) });

        if (hold.cancel_cause() && typeof hold.cancel_cause() != 'object')
            egCore.pcrud.retrieve('ahrcc',hold.cancel_cause()).then(function(c) { hold.cancel_cause(c) });

        if (hold.usr() && typeof hold.usr() != 'object')
            egCore.pcrud.retrieve('au',hold.usr()).then(function(u) { hold.usr(u) });

        // current_copy is not always fleshed in the API
        if (hold.current_copy() && typeof hold.current_copy() != 'object')
            hold.current_copy(hold_data.copy);
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

    service.uncancel_hold = function(items) {
        var hold_ids = items.filter(function(item) {
            return item.hold.cancel_time();
        }).map(function(item) {return item.hold.id()});

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

    service.show_holds_for_title = function(items) {
        var focus = items.length == 1;
        angular.forEach(items, function(item) {
            var url = egCore.env.basePath +
                      'cat/catalog/record/' +
                      item.mvr.doc_id() +
                      '/holds';
            $timeout(function() { var x = $window.open(url, '_blank'); if (focus) x.focus() });
        });
    }


    function generic_update(items, action) {
        if (!items.length) return $q.when();
        var hold_ids = items.map(function(item) {return item.hold.id()});
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

    service.mark_damaged = function(items) {
        var copy_ids = items
            .filter(function(item) { return Boolean(item.copy) })
            .map(function(item) { return item.copy.id() });
        if (copy_ids.length) 
            egCirc.mark_damaged(copy_ids).then(service.refresh);
    }

    service.mark_missing = function(items) {
        var copy_ids = items
            .filter(function(item) { return Boolean(item.copy) })
            .map(function(item) { return item.copy.id() });
        if (copy_ids.length) 
            egCirc.mark_missing(copy_ids).then(service.refresh);
    }

    service.retarget = function(items) {
        var hold_ids = items.map(function(item) { return item.hold.id() });
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
                    '$scope','$modal','egCore','egHolds','egCirc',
            function($scope , $modal , egCore , egHolds , egCirc) {

                function draw() {
                    if (!$scope.holdId) return;

                    egCore.net.request(
                        'open-ils.circ',
                        'open-ils.circ.hold.details.retrieve.authoritative',
                        egCore.auth.token(), $scope.holdId

                    ).then(function(hold_data) { 
                        egHolds.local_flesh(hold_data);
    
                        angular.forEach(hold_data, 
                            function(val, key) { $scope[key] = val });

                        // fetch + flesh the cancel_cause if needed
                        if ($scope.hold.cancel_time()) {
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
                    return $modal.open({
                        templateUrl : './circ/share/t_hold_note_dialog',
                        controller : 
                            ['$scope', '$modalInstance',
                            function($scope, $modalInstance) {
                                $scope.args = {};
                                $scope.ok = function() {
                                    $modalInstance.close($scope.args)
                                },
                                $scope.cancel = function($event) {
                                    $modalInstance.dismiss();
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
                    return $modal.open({
                        templateUrl : './circ/share/t_hold_notification_dialog',
                        controller : 
                            ['$scope', '$modalInstance',
                            function($scope, $modalInstance) {
                                $scope.args = {};
                                $scope.ok = function() {
                                    $modalInstance.close($scope.args)
                                },
                                $scope.cancel = function($event) {
                                    $modalInstance.dismiss();
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

 
