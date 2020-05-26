angular.module('egCurbsideAppDep')

.directive('egCurbsideToBeStagedManager', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: { },
        templateUrl: './circ/curbside/t_to_be_staged_manager',
        controller:
       ['$scope','$q','egCurbsideCoreSvc','egCore','egGridDataProvider',
        '$uibModal','$timeout','$location','egConfirmDialog','ngToast','$interval',
function($scope , $q , egCurbsideCoreSvc , egCore , egGridDataProvider ,
         $uibModal , $timeout , $location , egConfirmDialog , ngToast , $interval) {

    $scope.gridControls = {};

    $scope.wasHandled = {};
    $scope.refreshNeeded = false;

    latestTime = undefined;
    var checkRefresh = undefined;
    function startRefreshCheck() {
        if (!angular.isDefined(checkRefresh)) {
            checkRefresh = $interval(function() {
                egCurbsideCoreSvc.get_latest_to_be_staged().then(function(latest) {
                    if (angular.isDefined(latest)) {
                        if (angular.isDefined(latestTime) && latestTime != latest) {
                            $scope.refreshNeeded = true;
                            stopRefreshCheck();
                        }
                        latestTime = latest;
                    }
                });
            }, 5000);
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
            return egCurbsideCoreSvc.get_to_be_staged(offset, count);
        }
    });

    $scope.refresh_staging = function() {
        $scope.gridControls.refresh();
    }

    $scope.gridCellHandlers = { };
    $scope.gridCellHandlers.mark_staged = function(id) {
        egCurbsideCoreSvc.mark_staged(id).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                ngToast.danger(egCore.strings.$replace(
                    egCore.strings.FAILED_CURBSIDE_MARK_STAGED,
                    { slot_id : id, evt_code : evt.code }
                ));
                return;
            } 
            if (!angular.isDefined(resp)) {
                ngToast.warning(egCore.strings.$replace(
                    egCore.strings.NOTFOUND_CURBSIDE_MARK_STAGED,
                    { slot_id : id }
                ));
                return;
            }
            ngToast.success(egCore.strings.$replace(
                egCore.strings.SUCCESS_CURBSIDE_MARK_STAGED,
                { slot_id : id }
            ));
            $scope.wasHandled[id] = true;
            $timeout(function() { $scope.refresh_staging() }, 500);
        });
    }
    $scope.gridCellHandlers.wasHandled = function(id) {
        return $scope.wasHandled[id];
    }
    $scope.gridCellHandlers.patronIsBlocked = function(usr) {
        return egCurbsideCoreSvc.patron_blocked(usr);
    }
    $scope.gridCellHandlers.canClaimStaging = function(item) {
        if ($scope.wasHandled[item.slot_id]) return false;
        if (!item.slot.stage_staff()) return true;
        if (item.slot.stage_staff().id() == egCore.auth.user().id()) return false;
        return true;
    }
    $scope.gridCellHandlers.canUnclaimStaging = function(item) {
        if ($scope.wasHandled[item.slot_id]) return false;
        if (!item.slot.stage_staff()) return false;
        if (item.slot.stage_staff().id() == egCore.auth.user().id()) return true;
        return false;
    }
    $scope.gridCellHandlers.claim_staging = function(item) {
        console.debug('claim');
    }
    doClaimStaging = function(item) {
        var id = item.slot_id;
        egCurbsideCoreSvc.claim_staging(id).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                ngToast.danger(egCore.strings.$replace(
                    egCore.strings.FAILED_CURBSIDE_CLAIM_STAGING,
                    { slot_id : id, evt_code : evt.code }
                ));
                return;
            }
            if (!angular.isDefined(resp)) {
                ngToast.warning(egCore.strings.$replace(
                    egCore.strings.NOTFOUND_CURBSIDE_CLAIM_STAGING,
                    { slot_id : id }
                ));
                return;
            }

            item.slot = resp;

            // attempt to avoid a spurious refresh prompt
            egCurbsideCoreSvc.get_latest_to_be_staged().then(function(latest) {
                if (angular.isDefined(latest)) {
                    latestTime = latest
                }
            });

            ngToast.success(egCore.strings.$replace(
                egCore.strings.SUCCESS_CURBSIDE_CLAIM_STAGING,
                { slot_id : id }
            ));
        });
    }
    $scope.gridCellHandlers.claim_staging = function(item) {
        if (item.slot.stage_staff() &&
            item.slot.stage_staff().id() !== egCore.auth.user().id()) {
            egConfirmDialog.open(
                egCore.strings.CONFIRM_TAKE_OVER_STAGING_TITLE,
                egCore.strings.CONFIRM_TAKE_OVER_STAGING_BODY,
                {   slot_id : item.slot_id,
                    other_staff : item.slot.stage_staff().usrname(),
                    ok : function() { doClaimStaging(item) },
                    cancel : function() {}
                }
            );
        } else {
            doClaimStaging(item);
        }
    }
    $scope.gridCellHandlers.unclaim_staging = function(item) {
        var id = item.slot_id;
        egCurbsideCoreSvc.unclaim_staging(id).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                ngToast.danger(egCore.strings.$replace(
                    egCore.strings.FAILED_CURBSIDE_UNCLAIM_STAGING,
                    { slot_id : id, evt_code : evt.code }
                ));
                return;
            }
            if (!angular.isDefined(resp)) {
                ngToast.warning(egCore.strings.$replace(
                    egCore.strings.NOTFOUND_CURBSIDE_UNCLAIM_STAGING,
                    { slot_id : id }
                ));
                return;
            }

            item.slot = resp;

            // attempt to avoid a spurious refresh prompt
            egCurbsideCoreSvc.get_latest_to_be_staged().then(function(latest) {
                if (angular.isDefined(latest)) {
                    latestTime = latest
                }
            });

            ngToast.success(egCore.strings.$replace(
                egCore.strings.SUCCESS_CURBSIDE_UNCLAIM_STAGING,
                { slot_id : id }
            ));
        });
    }

}]}});
