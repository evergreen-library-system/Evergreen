angular.module('egSerialsApp', ['ui.bootstrap','ngRoute','egCoreMod','egGridMod','ngToast','egSerialsMod','egMfhdMod','egMarcMod','egSerialsAppDep']);
angular.module('egSerialsAppDep', []);

angular.module('egSerialsApp')
.config(['ngToastProvider', function(ngToastProvider) {
  ngToastProvider.configure({
    verticalPosition: 'bottom',
    animation: 'fade'
  });
}])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/serials/:bib_id', {
        templateUrl: './serials/t_manage',
        controller: 'ManageCtrl',
        resolve : resolver
    });

    $routeProvider.when('/serials/:bib_id/:active_tab', {
        templateUrl: './serials/t_manage',
        controller: 'ManageCtrl',
        resolve : resolver
    });

    $routeProvider.when('/serials/:bib_id/:active_tab/:subscription_id', {
        templateUrl: './serials/t_manage',
        controller: 'ManageCtrl',
        resolve : resolver
    });
})

.controller('ManageCtrl',
       ['$scope','$routeParams','$location','egSerialsCoreSvc',
function($scope , $routeParams , $location , egSerialsCoreSvc) {
    $scope.bib_id = $routeParams.bib_id;
    $scope.active_tab = $routeParams.active_tab ?  $routeParams.active_tab : 'manage-subscriptions';
    $scope.ssub = {id : null};
    if ($routeParams.subscription_id) {
        egSerialsCoreSvc.verify_subscription_id($scope.bib_id, $routeParams.subscription_id)
        .then(function(verified) {
            if (verified) {
                $scope.ssub.id = $routeParams.subscription_id;
            } else {
                // subscription ID is no good, so drop it from the URL
                $location.path('/serials/' + $scope.bib_id + '/' + $scope.active_tab);
            }
        });
    }
    $scope.$watch('ssub.id', function(newVal, oldVal) {
        if (oldVal != newVal) {
            $location.path('/serials/' + $scope.bib_id + '/' + $scope.active_tab +
                           '/' + $scope.ssub.id);
        }
    });
    $scope.$watch('active_tab', function(newVal, oldVal) {
        if (oldVal != newVal) {
                var new_path = '/serials/' + $scope.bib_id + '/' + $scope.active_tab;
                if ($scope.ssub.id && $scope.active_tab != 'manage-subscriptions') {
                    new_path += '/' + $scope.ssub.id;
                }
                $location.path(new_path);
        }
    });
}])
