angular.module('egSerialsAppDep')

.directive('egItemManager', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            bibId  : '=',
            ssubId : '='
        },
        templateUrl: './serials/t_item_manager',
        controller:
       ['$scope','$q','egSerialsCoreSvc','egCore','$uibModal',
function($scope , $q , egSerialsCoreSvc , egCore , $uibModal) {

    egSerialsCoreSvc.fetch($scope.bibId);

}]
    }
})
