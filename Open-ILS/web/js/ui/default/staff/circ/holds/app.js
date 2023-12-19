angular.module('egHoldsApp', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {delay : 
        ['egStartup', function(egStartup) {return egStartup.go()}]}

    $routeProvider.when('/circ/holds/shelf', {
        templateUrl: './circ/holds/t_shelf',
        controller: 'HoldsShelfCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/holds/shelf/:hold_id', {
        templateUrl: './circ/holds/t_shelf',
        controller: 'HoldsShelfCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/holds/pull', {
        templateUrl: './circ/holds/t_pull',
        controller: 'HoldsPullListCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/holds/pull/:hold_id', {
        templateUrl: './circ/holds/t_pull',
        controller: 'HoldsPullListCtrl',
        resolve : resolver
    });

    $routeProvider.otherwise({redirectTo : '/circ/holds/shelf'});
})


.controller('HoldsShelfCtrl',
       ['$scope','$q','$routeParams','$window','$location','egCore','egHolds','egHoldGridActions','egCirc','egGridDataProvider','egProgressDialog',
function($scope , $q , $routeParams , $window , $location , egCore , egHolds , egHoldGridActions , egCirc , egGridDataProvider , egProgressDialog)  {
    $scope.detail_hold_id = $routeParams.hold_id;

    var holds = [];
    var clear_mode = false;
    $scope.gridControls = {};
    $scope.grid_actions = egHoldGridActions;

    var provider = egGridDataProvider.instance({});
    $scope.gridDataProvider = provider;

    function refresh_page() {
        hold_count = 0;
        holds = [];
        all_holds = [];
        provider.refresh();
    }
    // called after any egHoldGridActions action occurs
    $scope.grid_actions.refresh = refresh_page;

    provider.get = function(offset, count) {

        // if in clear mode...
        if (clear_mode && holds.length) {
            if (!all_holds.length) all_holds = holds;
            holds = holds.filter(function(h) { return h.hold.clear_me });
            hold_count = holds.length;
            return provider.arrayNotifier(holds, offset, count);
        } else if (all_holds.length) {
            holds = all_holds;
            hold_count = holds.length;
            all_holds = [];
        }

        // see if we have the requested range cached
        if (holds[offset]) {
            return provider.arrayNotifier(holds, offset, count);
        }

        hold_count = 0;
        holds = [];
        var restrictions = {
                is_staff_request  : 'true',
                last_captured_hold: 'true',
                capture_time      : { not : null },
                cs_id             : 8, // on holds shelf
                cp_deleted        : 'f',
                fulfillment_time  : null,
                current_shelf_lib : $scope.pickup_ou.id()
        };

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

        egProgressDialog.open({max : 1, value : 0});
        var first = true;
        return egHolds.fetch_wide_holds(
            restrictions,
            order_by
        ).then(function () {
                return provider.arrayNotifier(holds, offset, count);
            },
            null,
            function(hold_data) { 
                if (first) {
                    hold_count = hold_data;
                    first = false;
                    egProgressDialog.update({max:hold_count});
                } else {
                    egProgressDialog.increment();
                    var new_item = { id : hold_data.id, hold : hold_data };
                    new_item.status_string =
                        egCore.strings['HOLD_STATUS_' + hold_data.hold_status]
                        || hold_data.hold_status;

                    if (clear_mode) {
                        if (hold_data.clear_me) holds.push(new_item);
                        all_holds.push(new_item);
                    } else {
                        holds.push(new_item);
                    }
                }
            }
        ).finally(egProgressDialog.close);
    }

    // re-draw the grid when user changes the org selector
    $scope.pickup_ou = egCore.org.get(egCore.auth.user().ws_ou());
    $scope.$watch('pickup_ou', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) 
            refresh_page();
    });

    $scope.detail_view = function(action, user_data, items) {
        if (h = items[0]) {
            $location.path('/circ/holds/shelf/' + h.hold.id);
        }
    }

    $scope.list_view = function(items) {
        $location.path('/circ/holds/shelf');
    }

    // when the detail hold is fetched (and updated), update the bib
    // record summary display record id.
    $scope.set_hold = function(hold_data) {
        $scope.detail_hold_record_id = hold_data.bre_id;
    }

    // manage active vs. clearable holds display
    var clearing = false; // true if actively clearing holds (below)
    $scope.is_clearing = function() { return clearing };
    $scope.active_mode = function() {return !clear_mode}
    $scope.clear_mode = function() {return clear_mode}
    $scope.show_clearable = function() { clear_mode = true; provider.refresh() }
    $scope.show_active = function() { clear_mode = false; provider.refresh() }
    $scope.disable_clear = function() { return clearing || !clear_mode }

    // udpate the in-grid hold with the clear-shelf cached response info.
    function handle_clear_cache_resp(resp) {
        if (!angular.isArray(resp)) resp = [resp];
        angular.forEach(resp, function(info) {
            if (info.action) {
                var grid_item = holds.filter(function(item) {
                    return item.hold.id == info.hold_details.id
                })[0];

                var all_hold_item = all_holds.filter(function(item) {
                    return item.hold.id == info.hold_details.id
                })[0];

                // there will be no grid item if the hold is off-page
                if (grid_item) {
                    grid_item.post_clear = 
                        egCore.strings['CLEAR_SHELF_ACTION_' + info.action];
                    all_hold_item.post_clear = 
                        egCore.strings['CLEAR_SHELF_ACTION_' + info.action];
                }
            }
        });
    }

    $scope.clear_holds = function() {
        clearing = true;
        $scope.clear_progress = {max : 0, value : 0};

        // we want to see all processed holds, so (effectively) remove
        // the grid limit.
        $scope.gridControls.setLimit(1000, true); 

        // initiate clear shelf and grab cache key
        egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.hold.clear_shelf.process',
            egCore.auth.token(), $scope.pickup_ou.id(),
            null, 1

        // request responses from the clear shelf cache
        ).then(
            
            // clear shelf done; fetch the cached results.
            function(resp) {
                clearing = false;
                egCore.net.request(
                    'open-ils.circ',
                    'open-ils.circ.hold.clear_shelf.get_cache',
                    egCore.auth.token(), resp.cache_key, 1
                ).then(null, null, handle_clear_cache_resp);
            }, 

            null,

            // handle streamed clear_shelf progress updates
            function(resp) {
                if (resp.maximum) 
                    $scope.clear_progress.max = resp.maximum;
                if (resp.progress)
                    $scope.clear_progress.value = resp.progress;
            }

        );
    }

    function map_prefix_to_subhash (h,pf) {
        var newhash = {};
        angular.forEach(Object.keys(h), function (k) {
            if (k.startsWith(pf)) {
                var nk = k.substr(pf.length);
                newhash[nk] = h[k];
            }
        });
        return newhash;
    }

    $scope.print_shelf_list = function() {
        var print_holds = [];
        angular.forEach(holds, function(hold_data) {
            var phold = {};
            print_holds.push(phold);

            phold.status_string = hold_data.status_string;

            phold.patron_first = hold_data.hold.usr_first_given_name;
            phold.patron_last = hold_data.hold.usr_family_name;
            phold.patron_alias = hold_data.hold.usr_alias;
            phold.patron_barcode = hold_data.hold.ucard_barcode;

            phold.title = hold_data.hold.title;
            phold.author = hold_data.hold.author;

            phold.hold = hold_data.hold;
            phold.copy = map_prefix_to_subhash(hold_data.hold, 'cp_');
            phold.volume = map_prefix_to_subhash(hold_data.hold, 'cn_');
            phold.part = map_prefix_to_subhash(hold_data.hold, 'p_');
        });

        console.log(print_holds);

        return egCore.print.print({
            context : 'default', 
            template : 'hold_shelf_list', 
            scope : {holds : print_holds}
        });
    }

    refresh_page();

}])

.controller('HoldsPullListCtrl',
       ['$scope','$q','$routeParams','$window','$location','egCore',
        'egHolds','egCirc','egHoldGridActions','egProgressDialog',
function($scope , $q , $routeParams , $window , $location , egCore , 
         egHolds , egCirc , egHoldGridActions , egProgressDialog) {

    $scope.detail_hold_id = $routeParams.hold_id;

    var cached_details = {};
    var details_needed = {};

    egCore.strings.setPageTitle(egCore.strings['PULL_LIST_TITLE']);

    function current_query() {
        var org_id = $scope.org_unit ? $scope.org_unit.id() :
            egCore.auth.user().ws_ou();
        return {'copy_circ_lib_id' : org_id};
    }

    $scope.gridControls = {
        setQuery : current_query,
        setSort : function() {
            return ['copy_location_order_position','call_number_sort_key']
        },
        collectStarted : function(offset) {
            // Launch an indeterminate -> semi-determinate progress
            // modal.  Using a determinate modal that starts counting
            // on the post-grid holds data retrieval results in a modal
            // that's stuck at 0% for most of its life, which is aggravating.
            egProgressDialog.open();
        },
        itemRetrieved : function(item) {
            egProgressDialog.increment();
            if (!cached_details[item.id]) {
                details_needed[item.id] = item;
            }
        },
        allItemsRetrieved : function() {
            flesh_holds().finally(egProgressDialog.close);
        }
    }


    // Fetches hold detail data for each hold in the grid and links
    // the detail data to the related grid item so egHoldGridActions 
    // and friends have access to holds data they understand.
    // Only fetch not-yet-cached data.
    function flesh_holds() {
        egProgressDialog.increment();

        // Start by fleshing hold details from our cached data.
        var items = $scope.gridControls.allItems();
        angular.forEach(items, function(item) {
            if (!cached_details[item.id]) return $q.when();
            angular.forEach(cached_details[item.id], 
                function(val, key) { item[key] = val })
        });

        // Exit if all needed details were already cached
        if (Object.keys(details_needed).length == 0) return $q.when();

        return egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.hold.details.batch.retrieve.authoritative',
            egCore.auth.token(), Object.keys(details_needed), {
                include_usr : true
            }

        ).then(null, null, function(hold_info) {
            egProgressDialog.increment();

            // check if this is a staff-created hold
            // i.e., requestor is not the same as the user
            hold_info['_is_staff_hold'] = hold_info.hold.requestor() != hold_info.hold.usr().id();

            var hold_id = hold_info.hold.id();
            cached_details[hold_id] = hold_info;
            var item = details_needed[hold_id];
            delete details_needed[hold_id];

            // flesh the grid item from the blob of hold data.
            angular.forEach(hold_info, 
                function(val, key) { item[key] = val });

        });
    }

    $scope.grid_actions = egHoldGridActions;
    $scope.grid_actions.refresh = function() {
        cached_details = {}; // un-cache details after edit actions.
        $scope.gridControls.refresh();
    }

    $scope.detail_view = function(action, user_data, items) {
        if (h = items[0]) {
            $location.path('/circ/holds/pull/' + h.hold.id());
        }
    }

    $scope.list_view = function(items) {
        $location.path('/circ/holds/pull');
    }

    // when the detail hold is fetched (and updated), update the bib
    // record summary display record id.
    $scope.set_hold = function(hold_data) {
        $scope.detail_hold_record_id = hold_data.bre_id;
    }

    // By default, this action is hidded from the UI, but leaving it
    // here in case it's needed in the future
    $scope.print_list_alt = function() {
        var url = '/opac/extras/circ/alt_holds_print.html';
        var win = $window.open(url, '_blank');
        win.ses = function() {return egCore.auth.token()};
        win.open();
        win.focus();
    }

    $scope.print_full_list = function() {
        var print_holds = [];
        egProgressDialog.open({value : 0});

        // collect the full list of holds
        egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.hold_pull_list.fleshed.stream',
            egCore.auth.token(), 10000, 0
        ).then(
            function() {
                console.debug('printing ' + print_holds.length + ' holds');

                // holds fetched, send to print
                egCore.print.print({
                    context : 'default', 
                    template : 'hold_pull_list', 
                    scope : {holds : print_holds}
                });
            },
            null, 
            function(hold_data) {
                egProgressDialog.increment();
                egHolds.local_flesh(hold_data);
                print_holds.push(hold_data);
                hold_data.title = hold_data.mvr.title();
                hold_data.author = hold_data.mvr.author();
                hold_data.hold = egCore.idl.toHash(hold_data.hold);
                hold_data.copy = egCore.idl.toHash(hold_data.copy);
                hold_data.volume = egCore.idl.toHash(hold_data.volume);
                hold_data.part = egCore.idl.toHash(hold_data.part);
            }
        ).finally(egProgressDialog.close);
    }

    $scope.update_org_unit = function (org) {
        $scope.org_unit = org;
        $scope.gridControls.setQuery(current_query());
        $scope.gridControls.refresh();
    };

    $scope.cant_have_volumes =
        function (id) { return !egCore.org.CanHaveVolumes(id); };

}])

