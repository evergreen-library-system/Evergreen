angular.module('egSerialsAppDep')

.directive('egSubSelector', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            bibId  : '=',
            ssubId : '='
        },
        templateUrl: './serials/t_sub_selector',
        controller:
       ['$scope','$q','egSerialsCoreSvc','egCore','egGridDataProvider',
        '$uibModal',
function($scope , $q , egSerialsCoreSvc , egCore , egGridDataProvider ,
                     $uibModal) {
    if ($scope.ssubId) {
        $scope.owning_ou = egCore.org.root();
    }
    $scope.owning_ou_changed = function(org) {
        $scope.selected_owning_ou = org.id();
        reload();
    }
    function reload() {
        egSerialsCoreSvc.fetch($scope.bibId, $scope.selected_owning_ou).then(function() {
            $scope.subscriptions = egCore.idl.toTypedHash(egSerialsCoreSvc.subTree);
            if ($scope.subscriptions.length == 1 && !$scope.ssubId) {
                $scope.ssubId = $scope.subscriptions[0].id;
            }
        });
    }
}]
    }
})
