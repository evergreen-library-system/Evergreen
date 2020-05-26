angular.module('egCurbsideAppDep')

.directive('egCurbsideDeliveredManager', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: { },
        templateUrl: './circ/curbside/t_delivered_manager',
        controller:
       ['$scope','$q','egCurbsideCoreSvc','egCore','egGridDataProvider',
        '$uibModal','$timeout','$location','egConfirmDialog','ngToast','$interval',
function($scope , $q , egCurbsideCoreSvc , egCore , egGridDataProvider ,
         $uibModal , $timeout , $location , egConfirmDialog , ngToast , $interval) {

    $scope.gridControls = {};

    $scope.refreshNeeded = false;

    latestTime = undefined;
    var checkRefresh = undefined;
    function startRefreshCheck() {
        if (!angular.isDefined(checkRefresh)) {
            checkRefresh = $interval(function() {
                egCurbsideCoreSvc.get_latest_delivered().then(function(latest) {
                    if (angular.isDefined(latest)) {
                        if (angular.isDefined(latestTime) && latestTime != latest) {
                            $scope.refreshNeeded = true;
                            stopRefreshCheck();
                        }
                        latestTime = latest;
                    }
                });
            }, 15000);
        }
    }
    function stopRefreshCheck() {
        if (angular.isDefined(checkRefresh)) {
            $interval.cancel(checkRefresh);
            checkRefresh = undefined;
        }
    }
    this.$onInit = function() {
        startRefreshCheck();
    }
    this.$onDestroy = function() {
        stopRefreshCheck();
    }

    $scope.gridDataProvider = egGridDataProvider.instance({
        get : function(offset, count) {
            $scope.refreshNeeded = false;
            startRefreshCheck();
            return egCurbsideCoreSvc.get_delivered(offset, count);
        }
    });

    $scope.refresh_delivered = function() {
        $scope.gridControls.refresh();
    }

    $scope.gridCellHandlers = { };

}]}});
