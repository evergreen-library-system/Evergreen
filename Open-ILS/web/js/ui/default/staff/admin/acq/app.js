angular.module('egAcqAdmin',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    var eframe_template = 
        '<eg-embed-frame allow-escape="true" min-height="min_height" url="acq_admin_url" handlers="funcs"></eg-embed-frame>';

    $routeProvider.when('/admin/acq/:noun/:verb/:extra?', {
        template: eframe_template,
        controller: 'EmbedAcqCtl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : './admin/acq/t_splash',
        resolve : resolver
    });
}])

.controller('EmbedAcqCtl',
       ['$scope','$routeParams','$location','egCore',
function($scope , $routeParams , $location , egCore) {

    $scope.funcs = {
        ses : egCore.auth.token(),
    }

    var acq_path = '/eg/';

    if ($routeParams.noun == 'conify') {
        acq_path += 'conify/global/acq/' + $routeParams.verb
            + (typeof $routeParams.extra != 'undefined'
                ? '/' + $routeParams.extra
                : '')
            + location.search;
    } else {
        acq_path += 'acq/'
            + $routeParams.noun + '/' + $routeParams.verb
            + (typeof $routeParams.extra != 'undefined'
                ? '/' + $routeParams.extra
                : '')
            + location.search;
    }

    $scope.min_height = 2000; // give lots of space to start

    // embed URL must include protocol/domain or it will be loaded via
    // push-state, resulting in an infinitely nested pages.
    $scope.acq_admin_url =
        $location.absUrl().replace(/\/eg\/staff.*/, acq_path);

    console.log('Loading Admin Acq URL: ' + $scope.acq_admin_url);

}])

