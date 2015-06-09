/*
 * Z39.50 search and import
 */

angular.module('egCatZ3950Search',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod', 'egZ3950Mod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    // search page shows the list view by default
    $routeProvider.when('/cat/z3950/search', {
        templateUrl: './cat/z3950/t_list',
        controller: 'Z3950SearchCtrl',
        resolve : resolver
    });

    // default page / bucket view
    $routeProvider.otherwise({redirectTo : '/cat/z3950/search'});
})

/**
 * List view - grid stuff
 */
.controller('Z3950SearchCtrl',
       ['$scope','$q','$location','$timeout','$window','egCore','egGridDataProvider','egZ3950TargetSvc',
function($scope , $q , $location , $timeout , $window,  egCore , egGridDataProvider,  egZ3950TargetSvc ) {

    // get list of targets
    egZ3950TargetSvc.loadTargets();
    egZ3950TargetSvc.loadActiveSearchFields();

    var provider = egGridDataProvider.instance({});

    provider.get = function(offset, count) {
        var deferred = $q.defer();

        var query = egZ3950TargetSvc.currentQuery();
        if (Object.keys(query.search).length == 0) {
            return $q.when();
        }

        query['limit'] = count;
        query['offset'] = offset;

        var resultIndex = offset;
        egCore.net.request(
            'open-ils.search',
            'open-ils.search.z3950.search_class',
            egCore.auth.token(),
            query
        ).then(
            function() { deferred.resolve() },
            null, // onerror
            function(result) {
                for (var i in result.records) {
                    result.records[i].mvr['service'] = result.service;
                    result.records[i].mvr['index'] = resultIndex++;
                    result.records[i].mvr['marcxml'] = result.records[i].marcxml;
                    deferred.notify(result.records[i].mvr);
                }
            }
        );

        return deferred.promise;
    };

    $scope.z3950SearchGridProvider = provider;
    $scope.gridControls = {};

    $scope.search = function() {
        $scope.z3950SearchGridProvider.refresh();
    };
    $scope.clearForm = function() {
        egZ3950TargetSvc.clearSearchFields();
    };

    $scope.showInCatalog = function() {
        var items = $scope.gridControls.selectedItems();
        // relying on cant_showInCatalog to protect us
        var url = egCore.env.basePath +
                  'cat/catalog/record/' + items[0].tcn();
        $timeout(function() { $window.open(url, '_blank') });        
    };
    $scope.cant_showInCatalog = function() {
        var items = $scope.gridControls.selectedItems();
        if (items.length != 1) return true;
        if (items[0]['service'] == 'native-evergreen-catalog') return false;
        return true;
    };

    $scope.import = function() {
        var deferred = $q.defer();
        var items = $scope.gridControls.selectedItems();
        egCore.net.request(
            'open-ils.cat',
            'open-ils.cat.biblio.record.xml.import',
            egCore.auth.token(),
            items[0]['marcxml']
            // FIXME and more
        ).then(
            function() { deferred.resolve() },
            null, // onerror
            function(result) {
                console.debug('imported');
            }
        );

        return deferred.promise;
    };
    $scope.cant_import = function() {
        var items = $scope.gridControls.selectedItems();
        if (items.length == 1) return false;
        return true;
    };
}])
