/**
 * Patron App
 *
 * Search, checkout, items out, holds, bills, edit, etc.
 */

angular.module('egPatronRegApp', ['ui.bootstrap','ngRoute','egCoreMod'])


.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {delay : 
        ['egStartup', function(egStartup) {return egStartup.go()}]}

    $routeProvider.when('/circ/patron/register', {
        template: '<eg-embed-frame url="reg_url"></eg-embed-frame>',
        controller: 'PatronRegCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/register/stage/:stage_username', {
        template: '<eg-embed-frame url="reg_url"></eg-embed-frame>',
        controller: 'PatronRegCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/register/edit/:edit_id', {
        template: '<eg-embed-frame url="reg_url"></eg-embed-frame>',
        controller: 'PatronRegCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/register/clone/:clone_id', {
        template: '<eg-embed-frame url="reg_url"></eg-embed-frame>',
        controller: 'PatronRegCtrl',
        resolve : resolver
    });

    $routeProvider.otherwise({redirectTo : '/circ/patron/register'});
})


/**
 * */
.controller('PatronRegCtrl',
       ['$scope','$routeParams','$location','egCore',
function($scope , $routeParams , $location , egCore) {
    

    var url = $location.absUrl().replace(/\/staff.*/, '/actor/user/register');

    // since we don't store auth cookies, pass the cookie via URL
    url += '?ses=' + egCore.auth.token();

    if ($routeParams.stage_username) {
        url += '&stage=' + encodeURIComponent($routeParams.stage_username);
    }

    if ($routeParams.edit_id) {
        url += '&usr=' + encodeURIComponent($routeParams.edit_id);
    }

    if ($routeParams.clone_id) {
        url += '&clone=' + encodeURIComponent($routeParams.clone_id);
    }

    // pass the reg URL into the scope, thus into the 
    $scope.reg_url = url;
}])
 
