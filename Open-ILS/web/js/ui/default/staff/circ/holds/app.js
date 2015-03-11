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

.factory('holdUiSvc', function() {
    return {
        holds : [] // cache
    }
})

.controller('HoldsShelfCtrl',
       ['$scope','$q','$routeParams','$window','$location','egCore','egHolds','egHoldGridActions','egCirc','egGridDataProvider',
function($scope , $q , $routeParams , $window , $location , egCore , egHolds , egHoldGridActions , egCirc , egGridDataProvider)  {
    $scope.detail_hold_id = $routeParams.hold_id;

    var hold_ids = [];
    var holds = [];
    var clear_mode = false;
    $scope.gridControls = {};
    $scope.grid_actions = egHoldGridActions;

    function fetch_holds(offset, count) {
        var ids = hold_ids.slice(offset, offset + count);
        return egHolds.fetch_holds(ids).then(null, null,
            function(hold_data) { 
                holds.push(hold_data);
                return hold_data; // to the grid
            }
        );
    }

    var provider = egGridDataProvider.instance({});
    $scope.gridDataProvider = provider;

    function refresh_page() {
        holds = [];
        hold_ids = [];
        provider.refresh();
    }
    // called after any egHoldGridActions action occurs
    $scope.grid_actions.refresh = refresh_page;

    provider.get = function(offset, count) {

        // see if we have the requested range cached
        if (holds[offset]) {
            return provider.arrayNotifier(holds, offset, count);
        }

        // see if we have the holds IDs for this range already loaded
        if (hold_ids[offset]) {
            return fetch_holds(offset, count);
        }

        var deferred = $q.defer();
        hold_ids = [];
        holds = [];

        var method = 'open-ils.circ.captured_holds.id_list.on_shelf.retrieve.authoritative.atomic';
        if (clear_mode) 
            method = 'open-ils.circ.captured_holds.id_list.expired_on_shelf_or_wrong_shelf.retrieve.atomic';

        egCore.net.request(
            'open-ils.circ', method,
            egCore.auth.token(), $scope.pickup_ou.id()

        ).then(function(ids) {
            if (!ids.length) { 
                deferred.resolve(); 
                return; 
            }

            hold_ids = ids;
            fetch_holds(offset, count)
            .then(deferred.resolve, null, deferred.notify);
        });

        return deferred.promise;
    }

    // re-draw the grid when user changes the org selector
    $scope.pickup_ou = egCore.org.get(egCore.auth.user().ws_ou());
    $scope.$watch('pickup_ou', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) 
            refresh_page();
    });

    $scope.detail_view = function(action, user_data, items) {
        if (h = items[0]) {
            $location.path('/circ/holds/shelf/' + h.hold.id());
        }
    }

    $scope.list_view = function(items) {
        $location.path('/circ/holds/shelf');
    }

    // when the detail hold is fetched (and updated), update the bib
    // record summary display record id.
    $scope.set_hold = function(hold_data) {
        $scope.detail_hold_record_id = hold_data.mvr.doc_id();
    }

    // manage active vs. clearable holds display
    var clearing = false; // true if actively clearing holds (below)
    $scope.is_clearing = function() { return clearing };
    $scope.active_mode = function() {return !clear_mode}
    $scope.clear_mode = function() {return clear_mode}
    $scope.show_clearable = function() { clear_mode = true; refresh_page() }
    $scope.show_active = function() { clear_mode = false; refresh_page() }
    $scope.disable_clear = function() { return clearing || !clear_mode }

    // udpate the in-grid hold with the clear-shelf cached response info.
    function handle_clear_cache_resp(resp) {
        if (!angular.isArray(resp)) resp = [resp];
        angular.forEach(resp, function(info) {
            if (info.action) {
                var grid_item = holds.filter(function(item) {
                    return item.hold.id() == info.hold_details.id
                })[0];

                // there will be no grid item if the hold is off-page
                if (grid_item) {
                    grid_item.post_clear = 
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

    $scope.print_list_progress = null;
    $scope.print_shelf_list = function() {
        var print_holds = [];
        $scope.print_list_loading = true;
        $scope.print_list_progress = 0;

        // collect the full list of holds
        egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.captured_holds.id_list.on_shelf.retrieve.authoritative.atomic',
            egCore.auth.token(), $scope.pickup_ou.id()
        ).then( function(idlist) {

            egHolds.fetch_holds(idlist).then(
                function () {
                    console.debug('printing ' + print_holds.length + ' holds');
                    // holds fetched, send to print
                    egCore.print.print({
                        context : 'default', 
                        template : 'hold_shelf_list', 
                        scope : {holds : print_holds}
                    })
                },
                null,
                function(hold_data) {
                    $scope.print_list_progress++;
                    egHolds.local_flesh(hold_data);
                    print_holds.push(hold_data);
                    hold_data.title = hold_data.mvr.title();
                    hold_data.author = hold_data.mvr.author();
                    hold_data.hold = egCore.idl.toHash(hold_data.hold);
                    hold_data.copy = egCore.idl.toHash(hold_data.copy);
                    hold_data.volume = egCore.idl.toHash(hold_data.volume);
                    hold_data.part = egCore.idl.toHash(hold_data.part);
                }
            )
        }).finally(function() {
            $scope.print_list_loading = false;
            $scope.print_list_progress = null;
        });
    }

    refresh_page();

}])

.controller('HoldsPullListCtrl',
       ['$scope','$q','$routeParams','$window','$location','egCore','egHolds','egCirc','egGridDataProvider','egHoldGridActions','holdUiSvc',
function($scope , $q , $routeParams , $window , $location , egCore , egHolds , egCirc , egGridDataProvider , egHoldGridActions , holdUiSvc)  {
    $scope.detail_hold_id = $routeParams.hold_id;

    var provider = egGridDataProvider.instance({});
    $scope.gridDataProvider = provider;

    $scope.grid_actions = egHoldGridActions;
    $scope.grid_actions.refresh = function() {
        holdUiSvc.holds = [];
        provider.refresh();
    }

    provider.get = function(offset, count) {

        if (holdUiSvc.holds[offset]) {
            return provider.arrayNotifier(holdUiSvc.holds, offset, count);
        }

        var deferred = $q.defer();
        var recv_index = 0;

        // fetch the IDs
        egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.hold_pull_list.fleshed.stream',
            egCore.auth.token(), count, offset
        ).then(
            deferred.resolve, null, 
            function(hold_data) {
                egHolds.local_flesh(hold_data);
                holdUiSvc.holds[offset + recv_index++] = hold_data;
                deferred.notify(hold_data);
            }
        );

        return deferred.promise;
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
        $scope.detail_hold_record_id = hold_data.mvr.doc_id();
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

    $scope.print_list_progress = null;
    $scope.print_full_list = function() {
        var print_holds = [];
        $scope.print_list_loading = true;
        $scope.print_list_progress = 0;

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
                $scope.print_list_progress++;
                egHolds.local_flesh(hold_data);
                print_holds.push(hold_data);
                hold_data.title = hold_data.mvr.title();
                hold_data.author = hold_data.mvr.author();
                hold_data.hold = egCore.idl.toHash(hold_data.hold);
                hold_data.copy = egCore.idl.toHash(hold_data.copy);
                hold_data.volume = egCore.idl.toHash(hold_data.volume);
                hold_data.part = egCore.idl.toHash(hold_data.part);
            }
        ).finally(function() {
            $scope.print_list_loading = false;
            $scope.print_list_progress = null;
        });
    }

}])

