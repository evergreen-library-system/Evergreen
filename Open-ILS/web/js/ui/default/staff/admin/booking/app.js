angular.module('egBookingAdmin',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); 
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    var eframe_template = 
        '<eg-embed-frame url="booking_admin_url" handlers="funcs"></eg-embed-frame>';

    $routeProvider.when('/admin/booking/:noun/:verb/:extra?', {
        template: eframe_template,
        controller: 'EmbedBookingCtl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : './admin/booking/t_splash',
        resolve : resolver
    });
}])

.controller('EmbedBookingCtl',
       ['$scope','$routeParams','$location','egCore',
function($scope , $routeParams , $location , egCore) {

    $scope.funcs = {
        ses : egCore.auth.token(),
    }

    var booking_path = '/eg/';

    if ($routeParams.noun == 'conify') {
        booking_path += 'conify/global/booking/' + $routeParams.verb
            + (typeof $routeParams.extra != 'undefined'
                ? '/' + $routeParams.extra
                : '')
            + location.search;
    } else {
        booking_path += 'booking/'
            + $routeParams.noun + '/' + $routeParams.verb
            + (typeof $routeParams.extra != 'undefined'
                ? '/' + $routeParams.extra
                : '')
            + location.search;
    }

    // embed URL must include protocol/domain or it will be loaded via
    // push-state, resulting in an infinitely nested pages.
    $scope.booking_admin_url =
        $location.absUrl().replace(/\/eg\/staff.*/, booking_path);

    console.log('Loading Admin Booking URL: ' + $scope.booking_admin_url);

}])

