angular.module('egPendingPatronsApp', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {delay : 
        ['egStartup', function(egStartup) {return egStartup.go()}]}

    $routeProvider.when('/circ/patron/pending/list', {
        templateUrl: './circ/patron/t_pending_list',
        controller: 'PendingPatronsCtrl',
        resolve : resolver
    });

    $routeProvider.otherwise({redirectTo : '/circ/patron/pending/list'});
})

.controller('PendingPatronsCtrl',
       ['$scope','$q','$routeParams','$window','$location','egCore','egGridDataProvider',
function($scope , $q , $routeParams , $window , $location , egCore , egGridDataProvider) {

    console.log('HERE');

    var pending_patrons = [];
    var provider = egGridDataProvider.instance({});
    $scope.grid_data_provider = provider;

    function load_patron(item) {
        if (angular.isArray(item)) item = item[0];
        if (!item) return;
        $window.open(
            $location.path(
                '/circ/patron/register/stage/' + item.user.usrname()).absUrl(),
            '_blank'
        ).focus();
    }

    $scope.load_patron = function(action, data, items) {
        load_patron(items);
    }

    $scope.grid_controls = {
        activateItem : load_patron
    }

    function refresh_page() {
        pending_patrons = [];
        provider.refresh();
    }

    provider.get = function(offset, count) {
        var deferred = $q.defer();
        var recv_index = 0;

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.user.stage.retrieve.by_org',
            egCore.auth.token(), $scope.context_org.id()

        ).then(
            deferred.resolve, null, 
            function(user) {
                user.id = user.user.row_id();
                user.user.home_ou(egCore.org.get(user.user.home_ou()));

                // only one (mailing) address is captured during patron
                // self-registration
                user.mailing_address = user.mailing_addresses[0];
                pending_patrons[offset + recv_index++] = user;
                deferred.notify(user);
            }
        );

        return deferred.promise;
    }

    $scope.context_org = egCore.org.get(egCore.auth.user().ws_ou())
    $scope.$watch('context_org', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) refresh_page();
    });
}])

