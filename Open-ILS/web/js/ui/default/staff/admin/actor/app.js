/**
 * App to drive the base page. 
 * Login Form
 * Splash Page
 */

angular.module('egAdminActor',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/admin/actor/address_alert', {
        templateUrl: './admin/actor/t_address_alert',
        controller: 'AddressAlertCtl',
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

.controller('AddressAlertCtl',
       ['$scope','$routeParams','$window','$location','egCore',
function($scope , $routeParams , $window , $location , egCore) {

    $scope.funcs = {
        ses : egCore.auth.token(),
    }

    // have to use the full URL, not just the path, to ensure
    // the embeded page is not a nested version of this page (ad infinitum)
    $scope.address_alert_url = $location.absUrl().replace(
        /\/eg\/staff.*/, '/eg/conify/global/actor/address_alert');

    console.log($scope.address_alert_url);

}])
