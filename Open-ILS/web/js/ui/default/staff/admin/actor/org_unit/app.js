angular.module('egOrgUnitApp',
    ['ngRoute', 'ui.bootstrap', 'treeControl', 'egCoreMod', 'egUiMod', 'ngToast'])

.config(['ngToastProvider', function(ngToastProvider) {
  ngToastProvider.configure({
    verticalPosition: 'bottom',
    animation: 'fade'
  });
}])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
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
       ['$scope','$q','$routeParams','$window','egCore','egIDL','egOrg','ngToast',
function($scope , $q , $routeParams , $window , egCore , egIDL , egOrg , ngToast ) {

    $scope.reset = function() {
        $scope.org = angular.copy($scope.selectedNode);
    };

    $scope.reset();

    // the org tree

    function init(id) {
        $scope.treedata = [ egCore.idl.toHash( egOrg.tree() ) ];
        function find_org(tree,id) {
            if (tree.id==id) {
                return tree;
            }
            for (var i in tree.children) {
                var child = tree.children[i];
                ou = find_org( child, id );
                if (ou) { return ou; }
            }
            return null;
        }
        $scope.selected = find_org($scope.treedata,id) || $scope.treedata[0]; // FIXME -- why no work?
        $scope.expandedNodes = [ $scope.treedata[0], $scope.selected ];
    }
    init(1);

    window.phasefx = {
         'scope' : $scope
        ,'egorg' : egOrg
        ,'egcore' : egCore
    };

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

    // main tab behavior

    $scope.update = function() {
        var new_org = $scope.org.id == -1 ? new egIDL.aou() : egOrg.get($scope.org.id);
        new_org.id( $scope.org.id );
        new_org.parent_ou( $scope.org.parent_ou );
        new_org.name( $scope.org.name );
        new_org.shortname( $scope.org.shortname );
        new_org.email( $scope.org.email );
        new_org.phone( $scope.org.phone );
        new_org.ou_type( 2 ); // FIXME
        egCore.pcrud[$scope.org.id == -1 ? 'create' : 'update'](new_org).then(
            function(res) { // success
                window.sessionStorage.removeItem('eg.env.aou.tree');
                egCore.env.load();
                init(0);
                ngToast.create(egCore.strings.ORG_UPDATE_SUCCESS);
            },
            function(res) { // failure
                ngToast.create(egCore.strings.ORG_UPDATE_FAILURE);
            },
            function(res) { // progress
            }
        );
    };

    $scope.remove = function() {
        var new_org = egOrg.get($scope.org.id);
        egCore.pcrud.remove(new_org).then(
            function(res) { // success
                window.sessionStorage.removeItem('eg.env.aou.tree');
                egCore.env.load();
                init(0);
                ngToast.create(egCore.strings.ORG_DELETE_SUCCESS);
            },
            function(res) { // failure
                ngToast.create(egCore.strings.ORG_DELETE_FAILURE);
            },
            function(res) { // progress
            }
        );
    };

    $scope.new_child = function() {
        $scope.org.parent_ou = $scope.org.id;
        $scope.org.id = -1;
        $scope.org.name = '';
        $scope.org.shortname = '';
    };

}])

