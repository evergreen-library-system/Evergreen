angular.module('egAcquisitions',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    var eframe_template = 
        '<eg-embed-frame url="acq_url" handlers="funcs"></eg-embed-frame>';

    $routeProvider.when('/acq/legacy/:noun/:verb', {
        template: eframe_template,
        controller: 'EmbedAcqCtl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : './t_splash',
        resolve : resolver
    });
}])

.controller('EmbedAcqCtl', 
       ['$scope','$routeParams','$location','egCore',
function($scope , $routeParams , $location , egCore) {

    $scope.funcs = {
        ses : egCore.auth.token(),
    }

    var acq_path = '/eg/acq/' + 
        $routeParams.noun + '/' + $routeParams.verb + location.search;

    // embed URL must include protocol/domain or it will be loaded via
    // push-state, resulting in an infinitely nested pages.
    $scope.acq_url = 
        $location.absUrl().replace(/\/eg\/staff.*/, acq_path);

    console.log('Loading Acq URL: ' + $scope.acq_url);

}])

