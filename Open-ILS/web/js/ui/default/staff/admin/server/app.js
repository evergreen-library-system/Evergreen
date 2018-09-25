angular.module('egServerAdmin',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    var eframe_template = 
        '<eg-embed-frame allow-escape="true" min-height="min_height" url="server_admin_url" handlers="funcs"></eg-embed-frame>';

    // old-style Confiy
    $routeProvider.when('/admin/server/legacy/:schema/:page', {
        template: eframe_template,
        controller: 'EmbedOldConifyCtl',
        resolve : resolver
    });
   
    // Conify page handler (some authority admin interfaces live
    // under global/cat/authority/)
    $routeProvider.when('/admin/server/:module/:schema/:page', {
        template: eframe_template,
        controller: 'EmbedConifyCtl',
        resolve : resolver
    });

    // Conify page handler
    $routeProvider.when('/admin/server/:schema/:page', {
        template: eframe_template,
        controller: 'EmbedConifyCtl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : './admin/server/t_splash',
        resolve : resolver
    });
}])

.controller('EmbedConifyCtl', 
       ['$scope','$routeParams','$location','egCore',
function($scope , $routeParams , $location , egCore) {

    $scope.funcs = {
        ses : egCore.auth.token(),
    }
    var conify_path = '/eg/conify/global/' +
        (angular.isDefined($routeParams.module) ? ($routeParams.module + '/') : '') +
        $routeParams.schema + '/' + $routeParams.page;

    $scope.min_height = 800;

    // embed URL must include protocol/domain or it will be loaded via
    // push-state, resulting in an infinitely nested pages.
    $scope.server_admin_url = 
        $location.absUrl().replace(/\/eg\/staff.*/, conify_path);

    console.log('Loading server admin URL: ' + $scope.server_admin_url);

}])

.controller('EmbedOldConifyCtl', 
       ['$scope','$routeParams','$location','egCore',
function($scope , $routeParams , $location , egCore) {

    $scope.funcs = {
        ses : egCore.auth.token(),
    }
    var conify_path = '/conify/global/' +
        $routeParams.schema + '/' + $routeParams.page + '.html';

    // embed URL must include protocol/domain or it will be loaded via
    // push-state, resulting in an infinitely nested pages.
    $scope.server_admin_url = 
        $location.absUrl().replace(/\/eg\/staff.*/, conify_path);

    console.log('Loading server admin URL: ' + $scope.server_admin_url);

}])
