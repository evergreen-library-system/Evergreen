angular.module('egOrgUnitApp',
    ['ngRoute', 'ui.bootstrap', 'treeControl', 'egCoreMod', 'egUiMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {delay :
        ['egStartup', function(egStartup) {return egStartup.go()}]}

    $routeProvider.when('/admin/actor/org_unit/:org_id', {
        templateUrl: './admin/actor/org_unit/t_index',
        controller: 'OrgUnitCtrl',
        resolve : resolver
    });

    $routeProvider.when('/admin/actor/org_unit/', {
        templateUrl: './admin/actor/org_unit/t_index',
        controller: 'OrgUnitCtrl',
        resolve : resolver
    });

    $routeProvider.otherwise({redirectTo : '/admin/actor/org_unit/'});
})

.controller('OrgUnitCtrl',
       ['$scope','$q','$routeParams','$window','egCore','egOrg',
function($scope , $q , $routeParams , $window , egCore , egOrg  ) {

    $scope.update = function() {
        var new_org = egOrg.get($scope.org.id);
        new_org.name( $scope.org.name );
        new_org.shortname( $scope.org.shortname );
        new_org.email( $scope.org.email );
        new_org.phone( $scope.org.phone );
        egCore.pcrud.update(new_org).then(
            function(res) { // success
                console.log('handler1');
                window.handler1 = res;
            },
            function(res) { // success
                console.log('handler2');
                window.handler2 = res;
            },
            function(res) { // error
                console.log('handler3');
                window.handler3 = res;
            }
        );
    };

    $scope.reset = function() {
        $scope.org = angular.copy($scope.selectedNode);
    };

    $scope.reset();

    // the org tree

    $scope.treedata = [ egCore.idl.toHash( egOrg.tree() ) ];
    $scope.selected = $scope.treedata[0]; // FIXME -- why no work?
    $scope.expandedNodes = [ $scope.treedata[0] ];

    $scope.showSelected = function(sel) {
        $scope.selectedNode = sel;
        $scope.org = angular.copy($scope.selectedNode);
    };

    // the tabs
    $scope.org_tab = 'main';
    $scope.set_org_tab = function(tab) {
        $scope.org_tab = tab;

        switch(tab) {

            case 'main':
                break;

            case 'hours':
                break;

            case 'addresses':
                break;
        }
    }

}])

