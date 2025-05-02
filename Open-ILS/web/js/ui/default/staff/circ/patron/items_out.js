/**
 * List of patron items checked out
 */

angular.module('egPatronApp')

.controller('PatronItemsOutCtrl',
       ['$scope','$q','$routeParams','$timeout','egCore','egUser','patronSvc',
        '$location','egGridDataProvider','$uibModal','egCirc','egConfirmDialog',
        'egProgressDialog','egBilling','$window','egBibDisplay',
function($scope , $q , $routeParams , $timeout , egCore , egUser , patronSvc , 
         $location , egGridDataProvider , $uibModal , egCirc , egConfirmDialog , 
         egProgressDialog , egBilling , $window , egBibDisplay) {

    // list of noncatatloged circulations. Define before initTab to 
    // avoid any possibility of race condition, since they are loaded
    // during init, but may be referenced before init completes.
    $scope.noncat_list = [];

    $scope.initTab('items_out', $routeParams.id).then(function() {
        // sort inline to support paging
        $scope.noncat_list = patronSvc.noncat_ids.sort();
    });

    // cache of circ objects for grid display
    patronSvc.items_out = [];

    // main list of checked out items
    $scope.main_list = [];

    // list of alt circs (lost, etc.) and/or check-in with fines circs
    $scope.alt_list = []; 
    
    egCore.org.settings([
        'ui.circ.suppress_checkin_popups' // add other settings as needed
    ]).then(function(set) {
        $scope.suppress_popups = set['ui.circ.suppress_checkin_popups'];
    });

    // these are fetched during startup (i.e. .configure())
    // By default, show lost/lo/cr items in the alt list
    var display_lost = Number(
        egCore.env.aous['ui.circ.items_out.lost']) || 2;
    var display_lo = Number(
        egCore.env.aous['ui.circ.items_out.longoverdue']) || 2;
    var display_cr = Number(
        egCore.env.aous['ui.circ.items_out.claimsreturned']) || 2;

    var fetch_checked_in = true;
    $scope.show_alt_circs = true;
    if (display_lost & 4 && display_lo & 4 && display_cr & 4) {
        // all special types are configured to be hidden once
        // checked in, so there's no need to fetch checked-in circs.
        fetch_checked_in = false;

        if (display_lost & 1 && display_lo & 1 && display_cr & 1) {                 
            // additionally, if all types are configured to display    
            // in the main list while checked out, nothing will         
            // ever appear in the alternate list, so we can hide          
            // the alternate list from the UI.  
            $scope.show_alt_circs = false;
        }
    }

    $scope.items_out_display = 'main';
    $scope.show_main_list = function(refresh_grid) {
        // don't need a full reset_page() to swap tabs
        $scope.items_out_display = 'main';
        patronSvc.items_out = [];
        // only refresh the grid when navigating from a tab that 
        // shares the same grid.
        if (refresh_grid) provider.refresh();
    }

    $scope.show_alt_list = function(refresh_grid) {
        // don't need a full reset_page() to swap tabs
        $scope.items_out_display = 'alt';
        patronSvc.items_out = [];
        // only refresh the grid when navigating from a tab that 
        // shares the same grid.
        if (refresh_grid) provider.refresh();
    }

    $scope.show_noncat_list = function() {
        // don't need a full reset_page() to swap tabs
        $scope.items_out_display = 'noncat';
        patronSvc.items_out = [];
        // Grid refresh is not necessary because switching to the
        // noncat_list always involves instantiating a new grid.
    }

    $scope.colorizeItemsOutList = {
        apply: function(item) {
            var duedate = new Date(item.due_date()).toISOString();
            if (duedate && duedate < new Date().toISOString()) {
                return 'overdue-row';
            }
        }
    }

    // Reload the user to pick up changes in items out, fines, etc.
    // Reload circs since the contents of the main vs. alt list may
    // have changed.
    function reset_page() {
        patronSvc.refreshPrimary();
        patronSvc.items_out = []; 
        $scope.main_list = [];
        $scope.alt_list = [];
        $timeout(provider.refresh);  // allow scope changes to propagate
    }

    var provider = egGridDataProvider.instance({});
    $scope.gridDataProvider = provider;

    function fetch_circs(id_list, offset, count) {
        if (!id_list.length || id_list.length < offset + 1) return $q.when();

        var deferred = $q.defer();
        var rendered = 0;

        egProgressDialog.open();

        // fetch the lot of circs and stream the results back via notify
        egCore.pcrud.search('circ', {id : id_list},
            {   flesh : 4,
                flesh_fields : {
                    circ : ['target_copy', 'workstation', 'checkin_workstation'],
                    acp : ['call_number', 'holds_count', 'status', 'circ_lib', 'location', 'floating', 'age_protect', 'parts'],
                    acpm : ['part'],
                    acn : ['record', 'owning_lib', 'prefix', 'suffix'],
                    bre : ['wide_display_entry']
                },
                // avoid fetching the MARC blob by specifying which 
                // fields on the bre to select.  More may be needed.
                // note that fleshed fields are explicitly selected.
                select : { bre : ['id'] },
                // TODO: LP#1697954 Fetch all circs on grid render 
                // to support client-side sorting.  Migrate to server-side
                // sorting to avoid the need for fetching all items.
                //limit  : count,
                //offset : offset,
                // we need an order-by to support paging
                order_by : {circ : ['xact_start']} 

        }).then(null, null, function(circ) {
            circ.circ_lib(egCore.org.get(circ.circ_lib())); // local fleshing

            // Translate bib display field JSON blobs to JS.
            // Collapse multi/array fields down to comma-separated strings.
            egBibDisplay.mwdeJSONToJS(
                circ.target_copy().call_number().record().wide_display_entry(), true);

            if (circ.target_copy().call_number().id() == -1) {
                // dummy-up a record for precat items
                circ.target_copy().call_number().record().wide_display_entry({
                    title : function() {return circ.target_copy().dummy_title()},
                    author : function() {return circ.target_copy().dummy_author()},
                    isbn : function() {return circ.target_copy().dummy_isbn()}
                })
            }
            circ._parts = circ.target_copy().parts().map(function(part) {
                return part.label()
            }).join(',');

           patronSvc.items_out.push(circ);

        }).then(function() {

            var circIds = patronSvc.items_out.map(function(circ) { return circ.id() });

            egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.user.itemsout.notices',
                egCore.auth.token(), circIds

            ).then(deferred.resolve, null, function(notice) {

                var circ = patronSvc.items_out.filter(
                    function(circ) {return circ.id() == notice.circ_id})[0];

                if (notice.numNotices) {
                    circ.action_trigger_event_count = notice.numNotices;
                    circ.action_trigger_latest_event_date = notice.lastDt;
                }

                if (rendered++ >= offset && rendered <= count) {
                    egProgressDialog.close();
                    deferred.notify(circ);
                };
            });
        });

        return deferred.promise;
    }

    function fetch_noncat_circs(id_list, offset, count) {
        if (!id_list.length) return $q.when();

        var deferred = $q.defer();
        var rendered = 0;

        egCore.pcrud.search('ancc', {id : id_list},
            {   flesh : 1,
                flesh_fields : {ancc : ['item_type','staff']},
                // TODO: LP#1697954 Fetch all circs on grid render 
                // to support client-side sorting.  Migrate to server-side
                // sorting to avoid the need for fetching all items.
                //limit  : count,
                //offset : offset,
                // we need an order-by to support paging
                order_by : {circ : ['circ_time']} 

        }).then(deferred.resolve, null, function(noncat_circ) {

            // calculate the virtual due date from the item type duration
            var seconds = egCore.date.intervalToSeconds(
                noncat_circ.item_type().circ_duration());
            var d = new Date(Date.parse(noncat_circ.circ_time()));
            d.setSeconds(d.getSeconds() + seconds);
            noncat_circ.duedate(d.toISOString());

            // local flesh org unit
            noncat_circ.circ_lib(egCore.org.get(noncat_circ.circ_lib()));

            patronSvc.items_out.push(noncat_circ); // cache it

            // We fetch all noncat circs for client-side sorting, but
            // only notify the caller for the page of requested circs.  
            if (rendered++ >= offset && rendered <= count)
                deferred.notify(noncat_circ);
        });

        return deferred.promise;
    }


    // decide which list each circ belongs to
    function promote_circs(list, display_code, open) {
        if (open) {                                                    
            if (1 & display_code) { // bitflag 1 == top list                   
                $scope.main_list = $scope.main_list.concat(list);
            } else {                                                   
                $scope.alt_list = $scope.alt_list.concat(list);
            }                                                          
        } else {                                                       
            if (4 & display_code) return;  // bitflag 4 == hide on checkin     
            $scope.alt_list = $scope.alt_list.concat(list);
        } 
    }

    // fetch IDs for circs we care about
    function get_circ_ids() {
        $scope.main_list = [];
        $scope.alt_list = [];

        // we can fetch these in parallel
        var promise1 = egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.checked_out.authoritative',
            egCore.auth.token(), $scope.patron_id
        ).then(function(outs) {
            $scope.main_list = outs.overdue.concat(outs.out);
            promote_circs(outs.lost, display_lost, true);                            
            promote_circs(outs.long_overdue, display_lo, true);             
            promote_circs(outs.claims_returned, display_cr, true);
        });

        // only fetched checked-in-with-bills circs if configured to display
        var promise2 = !fetch_checked_in ? $q.when() : egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.checked_in_with_fines.authoritative',
            egCore.auth.token(), $scope.patron_id
        ).then(function(outs) {
            promote_circs(outs.lost, display_lost);
            promote_circs(outs.long_overdue, display_lo);
            promote_circs(outs.claims_returned, display_cr);
        });

        return $q.all([promise1, promise2]);
    }

    provider.get = function(offset, count) {

        var id_list = $scope[$scope.items_out_display + '_list'];

        // see if we have the requested range cached
        // Note this items_out list is reset w/ each items-out tab change
        if (patronSvc.items_out[offset]) {
            return provider.arrayNotifier(
                patronSvc.items_out, offset, count);
        }

        if ($scope.items_out_display == 'noncat') {
            // if there are any noncat circ IDs, we already have them
            return fetch_noncat_circs(id_list, offset, count);
        }

        // See if we have the circ IDs for this range already loaded.
        // this would happen navigating to a subsequent page.
        if (id_list[offset]) {
            return fetch_circs(id_list, offset, count);
        }

        // avoid returning the request directly to the caller so the
        // notify()'s from egCore.net.request don't leak into the 
        // final set of notifies (i.e. the real responses);

        var deferred = $q.defer();
        get_circ_ids().then(function() {

            id_list = $scope[$scope.items_out_display + '_list'];
            $scope.gridDataProvider.grid.totalCount = id_list.length;
            // relay the notified circs back to the grid through our promise
            fetch_circs(id_list, offset, count).then(
                deferred.resolve, null, deferred.notify);
        });

        return deferred.promise;
    }


    // true if circ is overdue, false otherwise
    $scope.circIsOverdue = function(circ) {
        // circ may not exist yet for rendered row
        if (!circ) return false;

        var date = new Date();
        date.setTime(Date.parse(circ.due_date()));
        return date < new Date();
    }

    $scope.edit_due_date = function(items) {
        if (!items.length) return;

        $uibModal.open({
            templateUrl : './circ/patron/t_edit_due_date_dialog',
            backdrop: 'static',
            controller : [
                        '$scope','$uibModalInstance',
                function($scope , $uibModalInstance) {

                    // if there is only one circ, default to the due date
                    // of that circ.  Otherwise, default to today.
                    var due_date = items.length == 1 ? 
                        Date.parse(items[0].due_date()) : new Date();

                    $scope.args = {
                        num_circs : items.length,
                        due_date : due_date
                    }

                    // Fire off the due-date updater for each circ.
                    // When all is done, close the dialog
                    $scope.ok = function(args) {
                        var due = $scope.args.due_date.toISOString();
                        console.debug("applying due date of " + due);
                        egProgressDialog.open();

                        var promise = $q.when();
                        angular.forEach(items, function(circ) {
                            promise = promise.then(function() {
                                return egCore.net.request(
                                    'open-ils.circ',
                                    'open-ils.circ.circulation.due_date.update',
                                    egCore.auth.token(), circ.id(), due

                                ).then(function(new_circ) {
                                    // update the grid circ with the canonical 
                                    // date from the modified circulation.
                                    circ.due_date(new_circ.due_date());
                                })
                            });
                        });

                        promise.finally(function() {
                            egProgressDialog.close();
                            $uibModalInstance.close();
                            provider.refresh();
                        });
                    }
                    $scope.cancel = function($event) {
                        $uibModalInstance.dismiss();
                        $event.preventDefault();
                    }
                }
            ]
        });
    }

    $scope.print_receipt = function(items) {
        if (items.length == 0) return $q.when();
        var print_data = {circulations : []};
        var cusr = patronSvc.current;

        angular.forEach(items, function(circ) {
            print_data.circulations.push({
                circ : egCore.idl.toHash(circ),
                copy : egCore.idl.toHash(circ.target_copy()),
                call_number : egCore.idl.toHash(circ.target_copy().call_number()),
                title : circ.target_copy().call_number().record().wide_display_entry().title(),
                author : circ.target_copy().call_number().record().wide_display_entry().author()
            })
        });

        print_data.patron = {
            prefix : cusr.prefix(),
            first_given_name : cusr.first_given_name(),
            second_given_name : cusr.second_given_name(),
            family_name : cusr.family_name(),
            suffix : cusr.suffix(),
            pref_prefix : cusr.pref_prefix(),
            pref_first_given_name : cusr.pref_first_given_name(),
            pref_second_given_name : cusr.pref_second_given_name(),
            pref_family_name : cusr.pref_family_name(),
            pref_suffix : cusr.pref_suffix(),
            card : { barcode : cusr.card().barcode() },
            money_summary : patronSvc.patron_stats.fines,
            expire_date : cusr.expire_date(),
            alias : cusr.alias(),
            has_email : Boolean(patronSvc.current.email() && patronSvc.current.email().match(/.*@.*/)),
            has_phone : Boolean(cusr.day_phone() || cusr.evening_phone() || cusr.other_phone()),
            juvenile : cusr.juvenile()
        };

        return egCore.print.print({
            context : 'default', 
            template : 'items_out', 
            scope : print_data,
        });
    }

    function batch_action_with_flat_copies(items, action) {
        if (!items.length) return;
        var copies = items.map(function(circ) 
            { return egCore.idl.toHash(circ.target_copy()) });
        action(copies).then(reset_page);
    }
    function batch_action_with_barcodes(items, action) {
        if (!items.length) return;
        var barcodes = items.map(function(circ) 
            { return circ.target_copy().barcode() });
        action(barcodes).then(reset_page);
    }
    $scope.mark_damaged = function(items) {
        if (items.length == 0) return;

        angular.forEach(items, function(circ) {
            egCirc.mark_damaged({
                id: circ.target_copy().id(),
                barcode: circ.target_copy().barcode(),
                circ_lib: circ.target_copy().circ_lib().id()
            }).then(() => $timeout(reset_page,1000)) // reset after each, because rejecting one stops the $q.all() chain
        });
    }
    $scope.mark_lost = function(items) {
        batch_action_with_barcodes(items, egCirc.mark_lost);
    }
    $scope.mark_claims_returned = function(items) {
        batch_action_with_barcodes(items, egCirc.mark_claims_returned_dialog);
    }
    $scope.mark_claims_never_checked_out = function(items) {
        batch_action_with_barcodes(items, egCirc.mark_claims_never_checked_out);
    }

    $scope.show_recent_circs = function(items) {
        var focus = items.length == 1;
        angular.forEach(items, function(item) {
            var url = egCore.env.basePath +
                      '/cat/item/' +
                      item.target_copy().id() +
                      '/circ_list';
            $timeout(function() { var x = $window.open(url, '_blank'); if (focus) x.focus() });
        });
    }

    $scope.show_triggered_events = function(items) {
        var focus = items.length == 1;
        angular.forEach(items, function(item) {
            var url = '/eg2/staff/circ/item/event-log/' +
                      item.target_copy().id();
            $timeout(function() { var x = $window.open(url, '_blank'); if (focus) x.focus() });

        });
    }

    $scope.renew = function(items, msg) {
        if (!items.length) return;
        var barcodes = items.map(function(circ) 
            { return circ.target_copy().barcode() });

        if (!msg) msg = egCore.strings.RENEW_ITEMS;

        return egConfirmDialog.open(msg, barcodes.join(' '), {}).result
        .then(function() {
            window.oils_cancel_batch = false;
            window.oils_inside_batch = true;
            function batch_cleanup() {
                if (window.oils_inside_batch && window.oils_op_change_within_batch) {
                    window.oils_op_change_undo_func();
                }
                window.oils_inside_batch = false;
                window.oils_op_change_within_batch = false;
                egProgressDialog.close();
                reset_page();
            }
            function do_one() {
                egProgressDialog.increment();
                var bc = barcodes.pop();
                if (!bc) {
                    batch_cleanup();
                    return;
                }
                if (window.oils_op_change_within_batch) {
                    window.oils_op_change_toast_func();
                }
                // finally -> continue even when one fails
                egCirc.renew({copy_barcode : bc}).finally(function() {
                    if (!window.oils_cancel_batch) {
                        do_one();
                    } else {
                        console.log('batch cancelled');
                        batch_cleanup();
                        return;
                    }
                });
            }
            egProgressDialog.open({value : 1});
            do_one();
        });
    }

    $scope.renew_all = function() {
        var circs = patronSvc.items_out.filter(function(circ) {
            return (
                // all others will be rejected at the server
                !circ.stop_fines() ||
                circ.stop_fines() == 'MAXFINES'
            );
        });
        $scope.renew(circs, egCore.strings.RENEW_ALL_ITEMS);
    }

    $scope.renew_with_date = function(items) {
        if (!items.length) return;
        var barcodes = items.map(function(circ) 
            { return circ.target_copy().barcode() });

        return $uibModal.open({
            templateUrl : './circ/patron/t_renew_with_date_dialog',
            backdrop: 'static',
            controller : [
                        '$scope','$uibModalInstance',
                function($scope , $uibModalInstance) {
                    var now = new Date();
                    $scope.outOfRange = false;
                    $scope.minDate = new Date(now);
                    $scope.args = {
                        barcodes : barcodes,
                        date : new Date(now)
                    }
                    $scope.cancel = function() {$uibModalInstance.dismiss()}

                    // Fire off the due-date updater for each circ.
                    // When all is done, close the dialog
                    $scope.ok = function() {
                        var due = $scope.args.date.toISOString().replace(/T.*/,'');
                        console.debug("renewing with due date: " + due);

                        function do_one() {
                            if (bc = barcodes.pop()) {
                                egCirc.renew({copy_barcode : bc, due_date : due})
                                .finally(do_one);
                            } else {
                                $uibModalInstance.close(); 
                                reset_page();
                            }
                        }
                       do_one(); // kick it off
                    }
                }
            ]
        }).result;
    }

    $scope.checkin = function(items) {
        if (!items.length) return;
        var copies = items.map(function(circ) { return circ.target_copy() });
        var barcodes = copies.map(function(copy) { return copy.barcode() });
        
        var copy;
        function do_one() {
            if (copy = copies.pop()) {
                // Checkin expects a barcode, but will pass other
                // parameters too.  Passing the copy ID allows
                // for the checkin of deleted copies on the server.
                egCirc.checkin(
                    {copy_barcode: copy.barcode(), copy_id: copy.id()},
                    {suppress_popups: $scope.suppress_popups})
                .finally(do_one);
            } else {
                reset_page();
            }
        }
        if ($scope.suppress_popups) {
            do_one();
        } else {
            return egConfirmDialog.open(
                egCore.strings.CHECK_IN_CONFIRM, barcodes.join(' '), {

            }).result.then(function() {
                do_one(); // kick it off
            });
        }
    }

    $scope.add_billing = function(items) {
        if (!items.length) return;
        var circs = items.concat(); // don't pop from grid array
        function do_one() {
            var circ; // don't clobber window.circ!
            if (circ = circs.pop()) {
                egBilling.showBillDialog({
                    // let the dialog fetch the transaction, since it's
                    // not sufficiently fleshed here.
                    xact_id : circ.id(),
                    patron : patronSvc.current
                }).finally(do_one);
            } else {
                reset_page();
            }
        }
        do_one();
    }

}]);

