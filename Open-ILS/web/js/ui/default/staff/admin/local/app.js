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
        controller: 'EmbedXHTMLCtl', // non-conify
        resolve : resolver
    });
   
    // non-conify routes come first
    $routeProvider.when('/admin/local/actor/closed_dates', {
        template: eframe_template,
        controller: 'EmbedXHTMLCtl', // non-conify
        resolve : resolver
    });
    
    // non-conify routes come first
    $routeProvider.when('/admin/local/asset/copy_locations', {
        template: eframe_template,
        controller: 'EmbedXHTMLCtl', // non-conify
        resolve : resolver
    });

    // non-conify routes come first
    $routeProvider.when('/admin/local/asset/org_unit_settings', {
        template: eframe_template,
        controller: 'EmbedXHTMLCtl', // non-conify
        resolve : resolver
    });

    $routeProvider.when('/admin/local/config/non_cat_types', {
        template: eframe_template,
        controller: 'EmbedXHTMLCtl', // non-conify
        resolve : resolver
    });

    $routeProvider.when('/admin/local/asset/stat_cat_editor', {
        template: eframe_template,
        controller: 'EmbedXHTMLCtl', // non-conify
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

.controller('EmbedXHTMLCtl', 
       ['$scope','$location','egCore','$timeout',
function($scope , $location , egCore , $timeout) {

    $scope.funcs = {};

    var xul_base = '/xul/server/admin/';
    var page_parts = $location.path().split(/\//);
    var url = xul_base + page_parts[page_parts.length - 1] + '.xhtml';

    // old-school XUL admin UI's only want CGI ses values.
    url += '?ses=' + egCore.auth.token();
    
    console.log('Loading local admin URL: ' + $scope.local_admin_url);

    $scope.local_admin_url = $location.absUrl().replace(/\/.*/, url);
}])

