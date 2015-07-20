/**
 * List of patron items checked out
 */

angular.module('egPatronApp')

.controller('PatronItemsOutCtrl',
       ['$scope','$q','$routeParams','$timeout','egCore','egUser','patronSvc','$location',
        'egGridDataProvider','$modal','egCirc','egConfirmDialog','egBilling','$window',
function($scope,  $q,  $routeParams,  $timeout,  egCore , egUser,  patronSvc , $location, 
         egGridDataProvider , $modal , egCirc , egConfirmDialog , egBilling , $window) {

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
    $scope.show_main_list = function() {
        // don't need a full reset_page() to swap tabs
        $scope.items_out_display = 'main';
        patronSvc.items_out = [];
        provider.refresh();
    }

    $scope.show_alt_list = function() {
        // don't need a full reset_page() to swap tabs
        $scope.items_out_display = 'alt';
        patronSvc.items_out = [];
        provider.refresh();
    }

    $scope.show_noncat_list = function() {
        // don't need a full reset_page() to swap tabs
        $scope.items_out_display = 'noncat';
        patronSvc.items_out = [];
        provider.refresh();
    }

    // Reload the user to pick up changes in items out, fines, etc.
    // Reload circs since the contents of the main vs. alt list may
    // have changed.
    function reset_page() {
        patronSvc.refreshPrimary();
        patronSvc.items_out = []; 
        $scope.main_list = [];
        $scope.alt_list = [];
        provider.refresh() 
    }

    var provider = egGridDataProvider.instance({});
    $scope.gridDataProvider = provider;

    function fetch_circs(id_list, offset, count) {
        if (!id_list.length) return $q.when();

        // fetch the lot of circs and stream the results back via notify
        return egCore.pcrud.search('circ', {id : id_list},
            {   flesh : 4,
                flesh_fields : {
                    circ : ['target_copy', 'workstation', 'checkin_workstation'],
                    acp : ['call_number', 'holds_count'],
                    acn : ['record'],
                    bre : ['simple_record']
                },
                // avoid fetching the MARC blob by specifying which 
                // fields on the bre to select.  More may be needed.
                // note that fleshed fields are explicitly selected.
                select : { bre : ['id'] },
                limit  : count,
                offset : offset,
                // we need an order-by to support paging
                order_by : {circ : ['xact_start']} 

        }).then(null, null, function(circ) {
            circ.circ_lib(egCore.org.get(circ.circ_lib())); // local fleshing

            if (circ.target_copy().call_number().id() == -1) {
                // dummy-up a record for precat items
                circ.target_copy().call_number().record().simple_record({
                    title : function() {return circ.target_copy().dummy_title()},
                    author : function() {return circ.target_copy().dummy_author()},
                    isbn : function() {return circ.target_copy().dummy_isbn()}
                })
            }

            patronSvc.items_out.push(circ); // toss it into the cache
            return circ;
        });
    }

    function fetch_noncat_circs(id_list, offset, count) {
        if (!id_list.length) return $q.when();

        return egCore.pcrud.search('ancc', {id : id_list},
            {   flesh : 1,
                flesh_fields : {ancc : ['item_type','staff']},
                limit  : count,
                offset : offset,
                // we need an order-by to support paging
                order_by : {circ : ['circ_time']} 

        }).then(null, null, function(noncat_circ) {

            // calculate the virtual due date from the item type duration
            var seconds = egCore.date.intervalToSeconds(
                noncat_circ.item_type().circ_duration());
            var d = new Date(Date.parse(noncat_circ.circ_time()));
            d.setSeconds(d.getSeconds() + seconds);
            noncat_circ.duedate(d.toISOString());

            // local flesh org unit
            noncat_circ.circ_lib(egCore.org.get(noncat_circ.circ_lib()));

            patronSvc.items_out.push(noncat_circ); // cache it
            return noncat_circ;
        });
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

        $modal.open({
            templateUrl : './circ/patron/t_edit_due_date_dialog',
            controller : [
                        '$scope','$modalInstance',
                function($scope , $modalInstance) {

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
                        // toISOString gives us Zulu time, so
                        // adjust for that before truncating to date
                        var adjust_date = new Date( $scope.args.date );
                        adjust_date.setMinutes(
                            $scope.args.date.getMinutes() - adjust_date.getTimezoneOffset()
                        );
                        var due = adjust_date.toISOString().replace(/T.*/,'');
                        console.debug("applying due date of " + due);

                        var promises = [];
                        angular.forEach(items, function(circ) {
                            promises.push(
                                egCore.net.request(
                                    'open-ils.circ',
                                    'open-ils.circ.circulation.due_date.update',
                                    egCore.auth.token(), circ.id(), due

                                ).then(function(new_circ) {
                                    // update the grid circ with the canonical 
                                    // date from the modified circulation.
                                    circ.due_date(new_circ.due_date());
                                })
                            );
                        });

                        $q.all(promises).then(function() {
                            $modalInstance.close();
                            provider.refresh();
                        });
                    }
                    $scope.cancel = function($event) {
                        $modalInstance.dismiss();
                        $event.preventDefault();
                    }
                }
            ]
        });
    }

    $scope.print_receipt = function(items) {
        if (items.length == 0) return $q.when();
        var print_data = {circulations : []}

        angular.forEach(patronSvc.items_out, function(circ) {
            print_data.circulations.push({
                circ : egCore.idl.toHash(circ),
                copy : egCore.idl.toHash(circ.target_copy()),
                call_number : egCore.idl.toHash(circ.target_copy().call_number()),
                title : circ.target_copy().call_number().record().simple_record().title(),
                author : circ.target_copy().call_number().record().simple_record().author(),
            })
        });

        return egCore.print.print({
            context : 'default', 
            template : 'items_out', 
            scope : print_data,
        });
    }

    function batch_action_with_barcodes(items, action) {
        if (!items.length) return;
        var barcodes = items.map(function(circ) 
            { return circ.target_copy().barcode() });
        action(barcodes).then(reset_page);
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
            var url = egCore.env.basePath +
                      '/cat/item/' +
                      item.target_copy().id() +
                      '/triggered_events';
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
            function do_one() {
                var bc = barcodes.pop();
                if (!bc) { reset_page(); return }
                // finally -> continue even when one fails
                egCirc.renew({copy_barcode : bc}).finally(do_one);
            }
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

        return $modal.open({
            templateUrl : './circ/patron/t_edit_due_date_dialog',
            templateUrl : './circ/patron/t_renew_with_date_dialog',
            controller : [
                        '$scope','$modalInstance',
                function($scope , $modalInstance) {
                    $scope.args = {
                        barcodes : barcodes,
                        date : new Date()
                    }
                    $scope.cancel = function() {$modalInstance.dismiss()}

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
                                $modalInstance.close(); 
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
        var barcodes = items.map(function(circ) 
            { return circ.target_copy().barcode() });

        return egConfirmDialog.open(
            egCore.strings.CHECK_IN_CONFIRM, barcodes.join(' '), {

        }).result.then(function() {
            function do_one() {
                if (bc = barcodes.pop()) {
                    egCirc.checkin({copy_barcode : bc})
                    .finally(do_one);
                } else {
                    reset_page();
                }
            }
            do_one(); // kick it off
        });
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

