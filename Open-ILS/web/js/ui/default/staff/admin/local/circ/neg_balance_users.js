
angular.module('egAdminCirc',
    ['ngRoute','ui.bootstrap','egCoreMod','egUiMod','egGridMod'])

.controller('NegBalances',
       ['$scope','$q','$timeout','$location','$window','egCore',
        'egGridDataProvider','egProgressDialog',
function($scope , $q , $timeout , $location , $window , egCore , 
         egGridDataProvider , egProgressDialog) {

    $scope.grid_provider = egGridDataProvider.instance({});

    // API does not currenlty support paging, so it's all or none.
    $scope.grid_provider.get = function(offset, count) {
        if (!$scope.context_org) return $q.when();
        egProgressDialog.open();

        var deferred = $q.defer();

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.users.negative_balance',
            egCore.auth.token(), $scope.context_org.id())
        .then(deferred.resolve, null, function(blob) {
            egProgressDialog.increment();
            // Give the grid a top-level identifier field
            blob.usr_id = blob.usr.id();
            deferred.notify(blob)
        }).finally(egProgressDialog.close);

        return deferred.promise;
    }

    $scope.org_changed = function(org) {
        $scope.grid_provider.refresh();
    }

    $scope.disable_org = function(org_id) {
        if (!org_id) return true;
        return egCore.org.get(org_id).ou_type().can_have_users() != 't';
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

    $scope.grid_controls = {
        activateItem : function(selected) { 
            // activateItem returns a single row.
            $scope.get_user([selected]) 
        }
    }

}])
