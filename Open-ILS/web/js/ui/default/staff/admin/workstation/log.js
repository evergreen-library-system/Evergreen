angular.module('egWorkLogApp', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
    var resolver = {delay : 
        ['egStartup', function(egStartup) {return egStartup.go()}]}

    $routeProvider.when('/admin/workstation/log', {
        templateUrl: './admin/workstation/t_log',
        controller: 'WorkLogCtrl',
        resolve : resolver
    });

    $routeProvider.otherwise({redirectTo : '/admin/workstation/log'});
})

.controller('WorkLogCtrl',
       ['$scope','$q','$routeParams','$window','$timeout','egCore','egGridDataProvider','egWorkLog',
function($scope , $q , $routeParams , $window , $timeout , egCore , egGridDataProvider , egWorkLog ) {

    var work_log_entries = [];
    var patron_log_entries = [];

    var work_log_provider = egGridDataProvider.instance({});
    var patron_log_provider = egGridDataProvider.instance({});
    $scope.grid_work_log_provider = work_log_provider;
    $scope.grid_patron_log_provider = patron_log_provider;

    function load_item(log_entries) {
        if (!log_entries) return;
        if (!angular.isArray(log_entries)) log_entries = [log_entries];
        angular.forEach(log_entries, function(log_entry) {
            $window.open(
                egCore.env.basePath + '/cat/item/' + log_entry.item_id,
                '_blank'
            ).focus();
        });
    }

    $scope.load_item = function(action, data, entries) {
        load_item(entries);
    }

    function load_patron(log_entries) {
        if (!log_entries) return;
        if (!angular.isArray(log_entries)) log_entries = [log_entries];
        angular.forEach(log_entries, function(log_entry) {
            $window.open(
                egCore.env.basePath +
                '/circ/patron/' + log_entry.patron_id + '/checkout',
                '_blank'
            ).focus();
        });
    }

    $scope.load_patron = function(action, data, entries) {
        load_patron(entries);
    }

    $scope.grid_controls = {
        activateItem : load_patron
    }

    $scope.refresh_ui = function() {
        work_log_entries = [];
        patron_log_entries = [];
        work_log_provider.refresh();
        patron_log_provider.refresh();
    }

    function fetch_hold(deferred,entry) {
        return egCore.pcrud.search('ahr',
            { 'id' : entry.hold_id }, {
                'flesh' : 2,
                'flesh_fields' : {
                    'ahr' : ['usr','current_copy'],
                },
            }
        ).then(
            function(hold) {
                entry.patron_id = hold.usr().id();
                entry.user = hold.usr().family_name();
                if (hold.current_copy()) {
                    entry.item = hold.current_copy().barcode();
                }
            }
        );
    }

    function fetch_patron(deferred,entry) {
        return egCore.pcrud.search('au',
            { 'id' : entry.patron_id }, {}
        ).then(
            function(usr) {
                entry.user = usr.family_name();
            }
        );
    }

    work_log_provider.get = function(offset, count) {
        var log_entries = egWorkLog.retrieve_all();
        console.log(log_entries);
        var deferred = $q.defer();

        var promises = [];
        var entries = count ?
                      log_entries.work_log.slice(offset, offset + count) :
                      log_entries.work_log;
        entries.forEach(
            function(el,idx) {
                el.id = idx;
                // notify right away and in order; fetch_* will
                // fill in entry later if necessary
                promises.push($timeout(function() { deferred.notify(el) }));
                if (el.action == 'requested_hold') {
                    promises.push(fetch_hold(deferred,el));
                } else if (el.action == 'registered_patron') {
                    promises.push(fetch_patron(deferred,el));
                } else if (el.action == 'edited_patron') {
                    promises.push(fetch_patron(deferred,el));
                } else if (el.action == 'paid_bill') {
                    promises.push(fetch_patron(deferred,el));
                }
            }
        );
        $q.all(promises).then(deferred.resolve);

        return deferred.promise;
    }

    patron_log_provider.get = function(offset, count) {
        var log_entries = egWorkLog.retrieve_all();
        console.log(log_entries);
        var deferred = $q.defer();

        var promises = [];
        var entries = count ?
                      log_entries.patron_log.slice(offset, offset + count) :
                      log_entries.patron_log;
        log_entries.patron_log.forEach(
            function(el,idx) {
                el.id = idx;
                // notify right away and in order; fetch_* will
                // fill in entry later if necessary
                promises.push($timeout(function() { deferred.notify(el) }));
                if (el.action == 'requested_hold') {
                    promises.push(fetch_hold(deferred,el));
                } else if (el.action == 'registered_patron') {
                    promises.push(fetch_patron(deferred,el));
                } else if (el.action == 'edited_patron') {
                    promises.push(fetch_patron(deferred,el));
                } else if (el.action == 'paid_bill') {
                    promises.push(fetch_patron(deferred,el));
                }
            }
        );
        $q.all(promises).then(deferred.resolve);

        return deferred.promise;
    }

}])

