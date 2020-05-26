angular.module('egCurbsideAppDep')

.directive('egCurbsideArrivedManager', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: { },
        templateUrl: './circ/curbside/t_arrived_manager',
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
                egCurbsideCoreSvc.get_latest_arrived().then(function(latest) {
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
            return egCurbsideCoreSvc.get_arrived(offset, count);
        }
    });

    $scope.refresh_arrived = function() {
        $scope.gridControls.refresh();
    }

    $scope.gridCellHandlers = { };
    $scope.gridCellHandlers.mark_delivered = function(id) {
        var events_to_handle_later = [];
        egProgressDialog.open();
        egCurbsideCoreSvc.mark_delivered(id).then(function(resp) {
            egProgressDialog.close();

            events_to_handle_later.pop(); // last element is resp, our param
            if (events_to_handle_later.length) { // this means we got at least one CO attempt

                var bad_event;
                angular.forEach(events_to_handle_later, function (evt) {
                    if (bad_event) return; // already warned staff, leave
                    if (angular.isArray(evt)) evt = evt[0]; // we only need to look at the first event from each CO response

                    evt = egCore.evt.parse(evt);
                    if (!bad_event && evt && evt.textcode != 'SUCCESS') { // at least one non-success event, show the first event.
                        bad_event = evt;
                        ngToast.danger(egCore.strings.$replace(
                            egCore.strings.FAILED_CURBSIDE_CHECKOUT,
                            { slot_id : id, evt_code : bad_event.code }
                        ));
                    }
                });
            }

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
            $timeout(function() { $scope.refresh_arrived() }, 500);
        },null, function (resp) {
            events_to_handle_later.push(resp);
        });
    }
    $scope.gridCellHandlers.wasHandled = function(id) {
        return $scope.wasHandled[id];
    }
    $scope.gridCellHandlers.patronIsBlocked = function(usr) {
        return egCurbsideCoreSvc.patron_blocked(usr);
    }

}]}});
