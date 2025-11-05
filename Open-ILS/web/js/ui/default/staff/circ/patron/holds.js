/**
 * List of patron holds
 */

angular.module('egPatronApp').controller('PatronHoldsCtrl',

       ['$scope','$q','$routeParams','egCore','egUser','patronSvc',
        'egGridDataProvider','egHolds','$window','$location','egCirc','egHoldGridActions',
function($scope,  $q,  $routeParams,  egCore,  egUser,  patronSvc,  
        egGridDataProvider , egHolds , $window , $location , egCirc, egHoldGridActions) {

    $scope.initTab('holds', $routeParams.id);
    $scope.holds_display = 'main';
    $scope.detail_hold_id = $routeParams.hold_id;
    $scope.gridControls = {};
    $scope.grid_actions = egHoldGridActions;

    function refresh_all() {
        patronSvc.refreshPrimary();
        patronSvc.holds = [];
        patronSvc.hold_ids = [];
        provider.refresh() 
    }
    $scope.grid_actions.refresh = refresh_all;

    $scope.show_main_list = function() {
        // don't need a full reset_page() to swap tabs
        $scope.holds_display = 'main';
        patronSvc.holds = [];
        patronSvc.hold_ids = [];
        provider.refresh();
    }

    $scope.show_alt_list = function() {
        // don't need a full reset_page() to swap tabs
        $scope.holds_display = 'alt';
        patronSvc.holds = [];
        patronSvc.hold_ids = [];
        provider.refresh();
    }

    $scope.hide_cancel_hold = function(action) { 
        return $scope.holds_display == 'alt';
    }

    $scope.hide_uncancel_hold = function(action) {
        return !$scope.hide_cancel_hold();
    }

    var provider = egGridDataProvider.instance({});
    $scope.gridDataProvider = provider;

    function fetchHolds(offset, count) {
        // TODO: LP#1697954 Fetch all holds on grid render to support
        // client-side sorting.  Migrate to server-side sorting to avoid
        // the need for fetching all items.

        // we're going to just fetch all the holds up front
        //var ids = patronSvc.hold_ids.slice(offset, offset + count); 
        return egHolds.fetch_holds(patronSvc.hold_ids).then(null, null,
            function(hold_data) { 
                console.log('fetchHolds, hold_data',hold_data);
                egCirc.flesh_copy_circ_library(hold_data.copy);
                patronSvc.holds.push(hold_data);
                return hold_data;
            }
        );
    }

    /*provider.get = function(offset, count) {

        // see if we have the requested range cached
        if (patronSvc.holds[offset]) {
            return provider.arrayNotifier(patronSvc.holds, offset, count);
        }

        // see if we have the holds IDs for this range already loaded
        if (patronSvc.hold_ids[offset]) {
            return fetchHolds(offset, count);
        }

        var deferred = $q.defer();
        patronSvc.hold_ids = [];

        var method = 'open-ils.circ.holds.id_list.retrieve.authoritative';
        if ($scope.holds_display == 'alt')
            method = 'open-ils.circ.holds.canceled.id_list.retrieve.authoritative';

        var current = 0;
        egCore.net.request(
            'open-ils.circ', method,
            egCore.auth.token(), $scope.patron_id

        ).then(function(hold_ids) {
            
            if (!hold_ids.length || hold_ids.length < offset + 1)
            {
                deferred.resolve();
                return;
            }

            $scope.gridDataProvider.grid.totalCount = hold_ids.length;

            patronSvc.hold_ids = hold_ids;
            fetchHolds(offset, count)
            .then(deferred.resolve, null, function (data) {
                if (data) {
                    if (current >= offset && current < count) {
                        deferred.notify(data);
                    }
                    current++;
                }
            });
        });

        return deferred.promise;
    }*/
    provider.get = function(offset, count) {
        console.log('get, this', this);
        console.log('$scope', $scope);

        // see if we have the requested range cached
        if (patronSvc.holds[offset]) {
            return provider.arrayNotifier(patronSvc.holds, offset, count);
        }

        hold_count = 0;
        patronSvc.holds = [];
        var restrictions = {
                cancel_time      : null,
                fulfillment_time  : null,
                'h.usr': $scope.patron_id
        };
        if ($scope.holds_display == 'alt') {
            restrictions['cancel_time'] = { not : null };
        }
        console.log('restrictions',restrictions);

        var order_by = [{ shelf_expire_time : null }];

        // NOTE: Server sorting is currently disabled entirely by the 
        // first clause in this 'if'.   This is perfectly fine because
        // clientsort always runs inside the arrayNotifier implementation
        // in the egGrid code.   However, in order to retain the memory
        // of sorting constraints placed on us by the current server-side
        // code, an initial "cannot sort these" array and test is added
        // here.  An alternate implementation might be to map fields to
        // query positions, thus allowing positional ORDER BY clauses.
        // With as many fields as the wide hold object has, this is
        // non-trivial at the moment.
        if (false && provider.sort && provider.sort.length) {
            // A list of fields we can't sort on the server side.  That's ok, because
            // the grid is marked clientsort, so it always re-sorts in the browser.
            var cannot_sort = [
                'global_queue_position',
                'relative_queue_position',
                'default_estimated_wait',
                'min_estimated_wait',
                'potentials',
                'other_holds',
                'total_wait_time',
                'notification_count',
                'last_notification_time',
                'is_staff_hold',
                'copy_location_order_position',
                'hold_status',
                'clear_me',
                'usr_alias_or_display_name',
                'usr_display_name',
                'usr_alias_or_first_given_name'
            ];

            order_by = [];
            angular.forEach(provider.sort, function (c) {
                if (!angular.isObject(c)) {
                    if (c.match(/^hold\./)) {
                        var i = c.replace('hold.','');
                        if (cannot_sort.includes(i)) return;
                        var ob = {};
                        ob[i] = null;
                        order_by.push(ob);
                    }
                } else {
                    var i = Object.keys(c)[0];
                    var direction = c[i];
                    if (i.match(/^hold\./)) {
                        i = i.replace('hold.','');
                        if (cannot_sort.includes(i)) return;
                        var ob = {}
                        ob[i] = {dir:direction};
                        order_by.push(ob);
                    }
                }
            });
        }

        // egProgressDialog.open({max : 1, value : 0});
        var first = true;
        return egHolds.fetch_wide_holds(
            restrictions,
            order_by
        ).then(function () {
                return provider.arrayNotifier(patronSvc.holds, offset, count);
            },
            null,
            function(hold_data) { 
                if (first) {
                    hold_count = hold_data;
                    first = false;
                    // egProgressDialog.update({max:hold_count});
                } else {
                    // egProgressDialog.increment();
                    var new_item = { id : hold_data.id, hold : hold_data };
                    new_item.hold.tr_source = egCore.org.get(new_item.hold.tr_source)?.shortname();
                    new_item.hold.tr_dest = egCore.org.get(new_item.hold.tr_dest)?.shortname();
                    new_item.status_string =
                        egCore.strings['HOLD_STATUS_' + hold_data.hold_status]
                        || hold_data.hold_status;

                    patronSvc.holds.push(new_item);
                }
            }
        )/*.finally(egProgressDialog.close)*/;
    }

    $scope.print = function() {
        var holds = [];
        angular.forEach(patronSvc.holds, function(item) {
            holds.push({
                hold : egCore.idl.toHash(item.hold),
                copy : egCore.idl.toHash(item.copy),
                volume : egCore.idl.toHash(item.volume),
                title : item.hold.title,
                author : item.hold.author
            });
        });

        egCore.print.print({
            context : 'receipt', 
            template : 'holds_for_patron', 
            scope : {patron : egCore.idl.toHash(patronSvc.current), holds : holds}
        });
    }

    $scope.detail_view = function(action, user_data, items) {
        if (h = items[0]) {
            $location.path('/circ/patron/' + 
                $scope.patron_id + '/holds/' + h.id);
        }
    }

    $scope.list_view = function(items) {
        $location.path('/circ/patron/' + $scope.patron_id + '/holds');
    }

    $scope.place_hold = function() {

        egCore.hatch.setLoginSessionItem(
            'eg.circ.patron_hold_target', patronSvc.current.card().barcode());

        $window.location.href = '/eg2/staff/catalog';
    }

    // when the detail hold is fetched (and updated), update the bib
    // record summary display record id.
    $scope.set_hold = function(hold_data) {
        $scope.detail_hold_record_id = hold_data.bre_id;
    }

}])


.controller('PatronHoldsCreateCtrl',
       ['$scope','$routeParams','$location','egCore','egWorkLog','patronSvc','$cookies',
function($scope , $routeParams , $location , egCore , egWorkLog , patronSvc , $cookies) {

    // set preferred and search library cookies
    egCore.hatch.getItem('eg.search.pref_lib').then(function(lib) {
        $cookies.put('eg_pref_lib', lib, {path: '/'});
    });
    egCore.hatch.getItem('eg.search.search_lib').then(function(lib) {
        $cookies.put('eg_search_lib', lib, {path: '/'});
    });

    $scope.handlers = {
        opac_hold_placed : function(hold) {
            patronSvc.fetchUserStats(); // update hold counts
            egWorkLog.record(
                egCore.strings.EG_WORK_LOG_REQUESTED_HOLD,{
                    'action' : 'requested_hold',
                    'patron_id' : patronSvc.current.id(),
                    'hold_id' : hold
                }
            );
        }
    }

    $scope.initTab('holds', $routeParams.id).then(function(isAlert) {
        if (isAlert) return;
        // not guarenteed to have a barcode until init fetches the user
        $scope.handlers.patron_barcode = patronSvc.current.card().barcode();
    });

    $scope.catalog_url = 
        $location.absUrl().replace(/\/staff\/.*/, '/opac/advanced');

    $scope.handle_page = function(url) {
    }

}])
 
