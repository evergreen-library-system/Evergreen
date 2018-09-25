/**
 * App to drive the base page. 
 * Login Form
 * Splash Page
 */

angular.module('egUserPermsEditor',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/admin/user_perms', {
        templateUrl: './admin/t_user_perms_lookup',
        controller: 'UserPermsLookupCtrl',
        resolve : resolver
    });

    $routeProvider.when('/admin/user_perms/:user_id', {
        templateUrl: 'user-perms-template',
        controller: 'UserPermsCtrl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : 'user-perms-template',
        controller: 'UserPermsCtrl',
        resolve : resolver
    });
}])

.controller('UserPermsLookupCtrl',
       ['$scope','$window','$location','egCore',
function($scope , $window , $location , egCore) {
    
    $scope.selectMe = true; // focus text input
    $scope.args = {};

    // find the user by barcode, the jump to the editor
    $scope.submitBarcode = function(args) {

        $scope.bcNotFound = null;
        if (!args.barcode) return;

        $scope.selectMe = false;

        // lookup barcode
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            egCore.auth.token(), egCore.auth.user().ws_ou(), 
            'actor', args.barcode)

        .then(function(resp) { // get_barcodes

            if (evt = egCore.evt.parse(resp)) {
                console.error(evt.toString());
                return;
            }

            if (!resp || !resp[0]) {
                $scope.bcNotFound = args.barcode;
                $scope.selectMe = true;
                return;
            }

            // see if an opt-in request is needed
            user_id = resp[0].id;
            $location.path($location.path() + '/' + user_id);
        });
    }

}])

.controller('UserPermsCtrl',
       ['$scope','$routeParams','$window','$location','egCore',
function($scope , $routeParams , $window , $location , egCore) {
    var user_id = $routeParams.user_id;

    var url = $location.absUrl().replace(
        /\/eg\/staff.*/, '/xul/server/patron/user_edit.xhtml');

    url += '?usr=' + encodeURIComponent(user_id);

    // user_edit does not load the session via cookie.  It uses URL 
    // params or xulG instead.  Pass via xulG.
    $scope.funcs = {
        ses : egCore.auth.token(),
        on_patron_save : function() {
            $scope.funcs.reload();
        }
    }

    $scope.user_perms_url = url;
}])
