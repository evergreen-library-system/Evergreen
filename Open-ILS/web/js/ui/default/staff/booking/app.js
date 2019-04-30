angular.module('egBooking',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    var eframe_template = 
        '<eg-embed-frame url="booking_url" handlers="funcs"></eg-embed-frame>';

    $routeProvider.when('/booking/legacy/:noun/:verb', {
        template: eframe_template,
        controller: 'EmbedBookingCtl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : './t_splash',
        resolve : resolver
    });
}])

.controller('EmbedBookingCtl', 
       ['$scope','$routeParams','$location','egCore',
function($scope , $routeParams , $location , egCore) {

    $scope.funcs = {
        ses : egCore.auth.token(),
    }

    var booking_path = '/eg/' + 
        $routeParams.noun + '/' + $routeParams.verb + location.search;

    // embed URL must include protocol/domain or it will be loaded via
    // push-state, resulting in an infinitely nested pages.
    $scope.booking_url = 
        $location.absUrl().replace(/\/eg\/staff.*/, booking_path);

    console.log('Loading Booking URL: ' + $scope.booking_url);

}])

