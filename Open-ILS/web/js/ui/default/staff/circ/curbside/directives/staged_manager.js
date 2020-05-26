angular.module('egCurbsideAppDep')

.directive('egCurbsideStagedManager', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: { },
        templateUrl: './circ/curbside/t_staged_manager',
        controller:
       ['$scope','$q','egCurbsideCoreSvc','egCore','egGridDataProvider','egProgressDialog',
        '$uibModal','$timeout','$location','egConfirmDialog','ngToast','$interval',
function($scope , $q , egCurbsideCoreSvc , egCore , egGridDataProvider , egProgressDialog ,
         $uibModal , $timeout , $location , egConfirmDialog , ngToast , $interval) {

    $scope.gridControls = {};

    $scope.wasHandled = {};
    $scope.refreshNeeded = false;

    latestTime = undefined;
    var checkRefresh = undefined;
    function startRefreshCheck() {
        if (!angular.isDefined(checkRefresh)) {
            checkRefresh = $interval(function() {
                egCurbsideCoreSvc.get_latest_staged().then(function(latest) {
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
            $scope.wasHandled = {};
            $scope.refreshNeeded = false;
            startRefreshCheck();
            return egCurbsideCoreSvc.get_staged(offset, count);
        }
    });

    $scope.refresh_staged = function() {
        $scope.gridControls.refresh();
    }

    $scope.gridCellHandlers = { };
    $scope.gridCellHandlers.mark_arrived = function(id) {
        egCurbsideCoreSvc.mark_arrived(id).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                ngToast.danger(egCore.strings.$replace(
                    egCore.strings.FAILED_CURBSIDE_MARK_ARRIVED,
                    { slot_id : id, evt_code : evt.code }
                ));
                return;
            } 
            if (!angular.isDefined(resp)) {
                ngToast.warning(egCore.strings.$replace(
                    egCore.strings.NOTFOUND_CURBSIDE_MARK_ARRIVED,
                    { slot_id : id }
                ));
                return;
            }
            ngToast.success(egCore.strings.$replace(
                egCore.strings.SUCCESS_CURBSIDE_MARK_ARRIVED,
                { slot_id : id }
            ));
            $scope.wasHandled[id] = true;
            $timeout(function() { $scope.refresh_staged() }, 500);
        });
    }
    $scope.gridCellHandlers.mark_unstaged = function(id) {
        egCurbsideCoreSvc.mark_unstaged(id).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                ngToast.danger(egCore.strings.$replace(
                    egCore.strings.FAILED_CURBSIDE_MARK_UNSTAGED,
                    { slot_id : id, evt_code : evt.code }
                ));
                return;
            } 
            if (!angular.isDefined(resp)) {
                ngToast.warning(egCore.strings.$replace(
                    egCore.strings.NOTFOUND_CURBSIDE_MARK_UNSTAGED,
                    { slot_id : id }
                ));
                return;
            }
            ngToast.success(egCore.strings.$replace(
                egCore.strings.SUCCESS_CURBSIDE_MARK_UNSTAGED,
                { slot_id : id }
            ));
            $scope.wasHandled[id] = true;
            $timeout(function() { $scope.refresh_staged() }, 500);
        });
    }
    $scope.gridCellHandlers.mark_delivered = function(id) {
        egProgressDialog.open();
        egCurbsideCoreSvc.mark_delivered(id).then(function(resp) {
            egProgressDialog.close();
            if (evt = egCore.evt.parse(resp)) {
                ngToast.danger(egCore.strings.$replace(
                    egCore.strings.FAILED_CURBSIDE_MARK_DELIVERED,
                    { slot_id : id, evt_code : evt.code }
                ));
                return;
            }
            if (!angular.isDefined(resp)) {
                ngToast.warning(egCore.strings.$replace(
                    egCore.strings.NOTFOUND_CURBSIDE_MARK_DELIVERED,
                    { slot_id : id }
                ));
                return;
            }
            ngToast.success(egCore.strings.$replace(
                egCore.strings.SUCCESS_CURBSIDE_MARK_DELIVERED,
                { slot_id : id }
            ));
            $scope.wasHandled[id] = true;
            $timeout(function() { $scope.refresh_staged() }, 500);
        });
    }
    $scope.gridCellHandlers.wasHandled = function(id) {
        return $scope.wasHandled[id];
    }
    $scope.gridCellHandlers.patronIsBlocked = function(usr) {
        return egCurbsideCoreSvc.patron_blocked(usr);
    }

}]}});
