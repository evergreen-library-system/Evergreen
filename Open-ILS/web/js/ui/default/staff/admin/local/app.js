angular.module('egLocalAdmin',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    var eframe_template = 
        '<eg-embed-frame url="local_admin_url" handlers="funcs"></eg-embed-frame>';

    // non-conify routes come first
    $routeProvider.when('/admin/local/money/cash_reports', {
        template: eframe_template,
        controller: 'CashReportsCtl', // non-conify
        resolve : resolver
    });

    // Conify page handler
    $routeProvider.when('/admin/local/:schema/:page', {
        template: eframe_template,
        controller: 'EmbedConifyCtl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : './admin/local/t_splash',
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
        $routeParams.schema + '/' + $routeParams.page;

    // embed URL must include protocol/domain or it will be loaded via
    // push-state, resulting in an infinitely nested pages.
    $scope.local_admin_url = 
        $location.absUrl().replace(/\/eg\/staff.*/, conify_path);

    console.log('Loading local admin URL: ' + $scope.local_admin_url);

}])

.controller('CashReportsCtl', 
       ['$scope','$location','egCore',
function($scope , $location , egCore) {
    $scope.local_admin_url = $location.absUrl().replace(
        /\/.*/, '/xul/server/admin/cash_reports.xhtml');

    // old-school XUL admin UI's only want CGI ses values.
    $scope.local_admin_url += '?ses=' + egCore.auth.token();

    console.log('Loading local admin URL: ' + $scope.local_admin_url);
}])

