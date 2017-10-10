/**
 * Transits, yo
 */

angular.module('egCoreMod')

.factory('egTransits',

       ['$uibModal','$q','egCore','egConfirmDialog','egAlertDialog',
function($uibModal , $q , egCore , egConfirmDialog , egAlertDialog) {

    var service = {};

    service.abort_transits = function(transits,callback) {
       
        return $uibModal.open({
            templateUrl : './circ/share/t_abort_transit_dialog',
            backdrop: 'static',
            controller : 
                ['$scope', '$uibModalInstance',
                function($scope, $uibModalInstance) {

                    $scope.num_transits = transits.length;
                    $scope.num_hold_transits = 0;
                    angular.forEach(transits, function(t) {
                        if (t['hold_transit_copy.hold.id']) {
                            $scope.num_hold_transits++;
                        }
                    });
                    
                    $scope.cancel = function($event) {
                        $uibModalInstance.dismiss();
                        $event.preventDefault();
                    }

                    $scope.ok = function() {

                        function abort_one() {
                            var transit = transits.pop();
                            if (!transit) {
                                $uibModalInstance.close();
                                return;
                            }
                            egCore.net.request(
                                'open-ils.circ', 'open-ils.circ.transit.abort',
                                egCore.auth.token(), { 'transitid' : transit['id'] }
                            ).then(function(resp) {
                                if (evt = egCore.evt.parse(resp)) {
                                    egCore.audio.play('warning.transit.abort_failed');
                                    console.error('unable to abort transit: ' 
                                        + evt.toString());
                                }
                                abort_one();
                            });
                        }

                        abort_one();
                    }
                }
            ]
        }).result.then(
            function() {
                callback();
            }
        );
    }

    return service;
}])
;
