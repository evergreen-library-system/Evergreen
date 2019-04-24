angular.module('egAcqRequestsApp',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUserMod', 'egUiMod', 'egGridMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    // grid export
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/);

    var resolver = {delay :
        ['egStartup', function(egStartup) {return egStartup.go()}]}

    $routeProvider.when('/acq/requests/list', {
        templateUrl: './acq/requests/t_list',
        controller: 'AcqRequestsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/acq/requests/user/:user', {
        templateUrl: './acq/requests/t_list',
        controller: 'AcqRequestsCtrl',
        resolve : resolver
    });

    $routeProvider.when('/acq/requests/lineitem/:lineitem', {
        templateUrl: './acq/requests/t_list',
        controller: 'AcqRequestsCtrl',
        resolve : resolver
    });

    $routeProvider.otherwise({redirectTo : '/acq/requests/list'});
})

.controller('AcqRequestsCtrl',
       ['$scope','$q','$routeParams','$window','egCore','egAcqRequests','egUser',
        'egGridDataProvider','$uibModal','$timeout',
function($scope , $q , $routeParams , $window , egCore , egAcqRequests , egUser ,
         egGridDataProvider , $uibModal , $timeout) {

    var cancel_age;
    var cancel_count;
    $scope.context_user = $routeParams.user;
    $scope.context_lineitem = $routeParams.lineitem;

    egCore.startup.go().then(function() {
        // org settings for constraining display of canceled requests
        egCore.org.settings([
            'circ.holds.canceled.display_age',
            'circ.holds.canceled.display_count' // FIXME Don't know how to use this with egGrid
        ]).then(function(set) {
            cancel_age = set['circ.holds.canceled.display_age'];
            cancel_count = set['circ.holds.canceled.display_count'];
            if (!cancel_age && !cancel_count) {
                cancel_count = 10; // default to last 10 canceled requests
            }
        });
    });

    $scope.need_one_selected = function() {
        var requests = $scope.grid_controls.selectedItems();
        if (requests.length == 1) return false;
        return true;
    }

    $scope.need_one_uncanceled = function() {
        var requests = $scope.grid_controls.selectedItems();
        if (requests.length == 1) {
            return requests[0]['cancel_reason.label'] ? true : false;
        }
        return true;
    }

    $scope.need_one_lineitem = function() {
        var requests = $scope.grid_controls.selectedItems();
        if (requests.length == 1) {
            return ! requests[0]['lineitem.id'];
        }
        return true;
    }

    $scope.need_one_uncanceled_no_lineitem = function() {
        var requests = $scope.grid_controls.selectedItems();
        if (requests.length == 1) {
            if (! requests[0]['lineitem.id']) {
                return requests[0]['cancel_reason.label'] ? true : false;
            }
        }
        return true;
    }

    $scope.need_one_and_all_uncanceled = function() {
        var requests = $scope.grid_controls.selectedItems();
        if (requests.length == 0) return true;
        var found_canceled = false;
        angular.forEach(requests,function(v,k) {
            if (v['cancel_reason.label']) { found_canceled = true; }
        });
        return found_canceled;
    }

    $scope.need_one_and_all_new_or_pending = function() {
        var requests = $scope.grid_controls.selectedItems();
        if (requests.length == 0) return true;
        var found_bad = false;
        angular.forEach(requests,function(v,k) {
            if (v['request_status.id'] != 2         // Pending
                && v['request_status.id'] != 1) {   // New
                found_bad = true;
            }
        });
        return found_bad;
    }

    $scope.create_request = function(rows) {
        var row = {};
        if ($scope.context_user) {
            row.usr = $scope.context_user;
        }
        egAcqRequests.handle_request(row,'create',$scope.context_ou,refresh_page);
    }

    $scope.edit_request = function(rows) {
        if (!rows) return;
        if (!angular.isArray(rows)) rows = [rows];
        if (rows.length == 0) return;
        egAcqRequests.handle_request(rows[0],'edit',$scope.context_ou,refresh_page);
    }

    $scope.view_request = function(rows) {
        if (!rows) return;
        if (!angular.isArray(rows)) rows = [rows];
        if (rows.length == 0) return;
        egAcqRequests.handle_request(rows[0],'view',$scope.context_ou,refresh_page);
    }

    $scope.add_request_to_picklist = function(rows) {
        if (!rows) return;
        if (!angular.isArray(rows)) rows = [rows];
        if (rows.length == 0) return;
        egAcqRequests.add_request_to_picklist(rows[0]);
    }

    $scope.view_picklist = function(rows) {
        if (!rows) return;
        if (!angular.isArray(rows)) rows = [rows];
        if (rows.length == 0) return;
        egAcqRequests.view_picklist(rows[0]);
    }

    $scope.retrieve_user = function(rows) {
        if (!rows) return;
        if (!angular.isArray(rows)) rows = [rows];
        if (rows.length == 0) return;
        location.href = "/eg/staff/circ/patron/" + rows[0]['usr.id'] + "/checkout";
    }

    $scope.clear_requests = function(rows) {
        rows = $scope.grid_controls.selectedItems(); // remove this if we move the grid action into the menu
        if (!rows) return;
        if (!angular.isArray(rows)) rows = [rows];
        if (rows.length == 0) return;
        egAcqRequests.clear_requests( rows, refresh_page );
    }

    $scope.set_no_hold_requests = function(rows) {
        if (!rows) return;
        if (!angular.isArray(rows)) rows = [rows];
        if (rows.length == 0) return;
        egAcqRequests.set_no_hold_requests( rows, refresh_page );
    }

    $scope.set_yes_hold_requests = function(rows) {
        if (!rows) return;
        if (!angular.isArray(rows)) rows = [rows];
        if (rows.length == 0) return;
        egAcqRequests.set_yes_hold_requests( rows, refresh_page );
    }

    $scope.cancel_requests = function(rows) {
        if (!rows) return;
        if (!angular.isArray(rows)) rows = [rows];
        if (rows.length == 0) return;
        egAcqRequests.cancel_requests( rows, refresh_page );
    }

    $scope.canceled_requests_checkbox_handler = function (item) {
        $scope.canceled_requests_cb_changed(item.checkbox,item.checked);
    }

    $scope.canceled_requests_cb_changed = function(cb,newVal,norefresh) {
        $scope[cb] = newVal;
        egCore.hatch.setItem('eg.acq.' + cb, newVal);
        if (!norefresh) {
            refresh_page();
        }
    }

    function current_query() {
        var filter = {}
        if ($scope.context_user) {
            filter.usr = $scope.context_user;
        } else if ($scope.context_lineitem)  {
            filter.lineitem = $scope.context_lineitem;
        } else {
            filter.home_ou = egCore.org.descendants($scope.context_ou.id(), true)
        }
        if ($scope['requests_show_canceled']) {
            filter.cancel_reason = { '!=' : null };
            if (cancel_age) {
                var seconds = egCore.date.intervalToSeconds(cancel_age);
                var now_epoch = new Date().getTime();
                var cancel_date = new Date(
                    now_epoch - (seconds * 1000 /* milliseconds */)
                );
                filter.cancel_time = { '>=' : cancel_date.toISOString() };
            }

        } else {
            filter.cancel_reason = { '=' : null };
        }
        return filter;
    }

    $scope.grid_controls = {
        activateItem : $scope.view_request,
        setQuery : current_query
    }

    function refresh_page() {
        $scope.grid_controls.setQuery(current_query());
        $scope.grid_controls.refresh();
    }

    $scope.context_ou = egCore.org.get(egCore.auth.user().ws_ou());
    $scope.$watch('context_ou', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) refresh_page();
    });

}])

