angular.module('egCurbsideApp', ['ui.bootstrap','ngRoute','egCoreMod','egGridMod','ngToast','egCurbsideMod','egCurbsideAppDep']);
angular.module('egCurbsideAppDep', ['egPatronSearchMod','egUserMod']);

angular.module('egCurbsideApp')
.config(['ngToastProvider', function(ngToastProvider) {
  ngToastProvider.configure({
    verticalPosition: 'bottom',
    animation: 'fade'
  });
}])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export

    var resolver = {delay : ['egCore', function(egCore) {
        egCore.env.classLoaders.aous = function() {
            return egCore.org.settings([
                'circ.do_not_tally_claims_returned',
                'circ.tally_lost',
            ]).then(function(settings) {
                // local settings are cached within egOrg.  Caching them
                // again in egEnv just simplifies the syntax for access.
                egCore.env.aous = settings;
            });
        };
        egCore.env.loadClasses.push('aous');

        return egCore.startup.go()
    }]};

    $routeProvider.when('/circ/curbside/index', {
        templateUrl: './circ/curbside/t_main',
        controller: 'CurbsideCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/curbside/:active_tab', {
        templateUrl: './circ/curbside/t_main',
        controller: 'CurbsideCtrl',
        resolve : resolver
    });

    // default page
    $routeProvider.otherwise({redirectTo : '/circ/curbside/index'});
})
    
.controller('CurbsideCtrl',
       ['$scope','$routeParams','$location','egCurbsideCoreSvc',
function($scope , $routeParams , $location , egCurbsideCoreSvc ) {
    $scope.active_tab = $routeParams.active_tab ?  $routeParams.active_tab : 'to-be-staged';

    $scope.$watch('active_tab', function(newVal, oldVal) {
        if (oldVal != newVal) {
            var new_path = '/circ/curbside/' + $scope.active_tab;
            $location.path(new_path);
        }
    });
}])
