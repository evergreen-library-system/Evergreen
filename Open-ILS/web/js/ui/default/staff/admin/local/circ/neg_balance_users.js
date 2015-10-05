
angular.module('egAdminCirc',
    ['ngRoute','ui.bootstrap','egCoreMod','egUiMod','egGridMod'])

.controller('NegBalances',
       ['$scope','$q','$timeout','$location','$window','egCore','egGridDataProvider',
function($scope , $q , $timeout , $location , $window , egCore , egGridDataProvider) {

    egCore.startup.go(); // standalone mode requires manual startup

    $scope.grid_provider = egGridDataProvider.instance({});

    // API does not currenlty support paging, so it's all or none.
    $scope.grid_provider.get = function(offset, count) {
        if (!$scope.context_org) return $q.when();

        var deferred = $q.defer();

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.users.negative_balance',
            egCore.auth.token(), $scope.context_org.id())
        .then(deferred.resolve, null, deferred.notify);

        return deferred.promise;
    }

    $scope.org_changed = function(org) {
        $scope.context_org = org; // hmm, why necessary.
        $scope.grid_provider.refresh();
    }

    // NOTE: Chrome only allows one tab/window to open per user
    // action.  Only the first patron will be displayed.
    $scope.get_user = function(selected) {
        if (!selected.length) return;
        angular.forEach(selected, function(data) {
            $timeout(function() {
                var url = $location.absUrl().replace(
                    /admin\/local\/.*/,
                    'circ/patron/' + data.usr.id() + '/checkout');
                $window.open(url, '_blank')
            });
        });
    }
}])
