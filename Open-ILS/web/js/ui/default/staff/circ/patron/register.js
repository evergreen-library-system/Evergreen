/**
 * Patron App
 *
 * Search, checkout, items out, holds, bills, edit, etc.
 */

angular.module('egPatronRegApp', ['ui.bootstrap','ngRoute','egCoreMod', 'egUiMod'])


.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
    var resolver = {delay : 
        ['egStartup', function(egStartup) {return egStartup.go()}]}

    $routeProvider.when('/circ/patron/register', {
        templateUrl: './circ/patron/t_edit',
        controller: 'PatronRegCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/register/stage/:stage_username', {
        templateUrl: './circ/patron/t_edit',
        controller: 'PatronRegCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/register/edit/:edit_id', {
        templateUrl: './circ/patron/t_edit',
        controller: 'PatronRegCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/register/clone/:clone_id', {
        templateUrl: './circ/patron/t_edit',
        controller: 'PatronRegCtrl',
        resolve : resolver
    });

    $routeProvider.otherwise({redirectTo : '/circ/patron/register'});
})

// dummy service so standalone patron editor can reference it
.factory('patronSvc', function() { return { /* dummy */ } });

