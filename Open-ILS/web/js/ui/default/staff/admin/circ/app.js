/**
 * App to drive the base page. 
 * Login Form
 * Splash Page
 */

angular.module('egAdminCirc',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/admin/circ/age_to_lost', {
        templateUrl: './admin/circ/t_age_to_lost',
        controller: 'AgeToLostCtl',
        resolve : resolver
    });

    // default page 
    /*
    $routeProvider.otherwise({
        templateUrl : 'user-perms-template',
        controller: 'UserPermsCtrl',
        resolve : resolver
    });
    */
}])

.controller('AgeToLostCtl',
       ['$scope','egCore',
function($scope , egCore) {
    $scope.i_am_sure = false;
    $scope.chunks_processed = 0;
    $scope.events_created = 0;

    egCore.pcrud.search('pgt', {parent : null}, 
        {flesh : -1, flesh_fields : {pgt : ['children']}}
    ).then(
        function(tree) {
            egCore.env.absorbTree(tree, 'pgt')
            $scope.profiles = egCore.env.pgt.list;
            $scope.selected_profile = tree;
        }
    );

    $scope.set_profile = function(g) {$scope.selected_profile = g}

    // determine the tree depth of the profile group
    $scope.pgt_depth = function(grp) {
        var d = 0;
        while (grp = egCore.env.pgt.map[grp.parent()]) d++;
        return d;
    }

    $scope.age_to_lost = function() {
        $scope.in_progress = true;
        $scope.i_am_sure = false; // reset
        $scope.all_done = false;

        egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.circulation.age_to_lost',
            egCore.auth.token(), {
                user_profile : $scope.selected_profile.id(),
                circ_lib : $scope.context_org.id()
            }
        ).then(
            function() {
                $scope.in_progress = false;
                $scope.all_done = true;
            },
            null, // on-error
            function(response) {
                if (!response) return;
                if (response.progress)
                    $scope.chunks_processed = response.progress;
                if (response.created)
                    $scope.events_created = response.created;
            }
        );
    }
}])
