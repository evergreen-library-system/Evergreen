angular.module('egCoreMod')

.factory('egPatronMerge',
       ['$uibModal','$q','egCore',
function($uibModal , $q , egCore) {

    var service = {};

    service.do_merge = function(patron_ids) {
        var deferred = $q.defer();
        $uibModal.open({
            templateUrl: './circ/share/t_merge_patrons',
            backdrop: 'static',
            size: 'lg',
            windowClass: 'eg-wide-modal',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                    $scope.lead_id = 0;
                    $scope.patron_ids = patron_ids;
                    $scope.ok = function() {
                        $uibModalInstance.close({ lead_id : $scope.lead_id });
                    }
                    $scope.cancel = function () { $uibModalInstance.dismiss() }
                }]
        }).result.then(function (args) {
            if (args.lead_id == 0) return;
            var sub_id = (args.lead_id == patron_ids[0]) ?
                patron_ids[1] :
                patron_ids[0];
            egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.user.merge',
                egCore.auth.token(),
                args.lead_id,
                [ sub_id ]
            ).then(function(resp) {
                var evt = egCore.evt.parse(resp);
                if (evt) {
                    console.debug(evt);
                    deferred.reject(evt);
                    return;
                } else {
                    deferred.resolve(); 
                }
            });
        });
        return deferred.promise;
    }

    return service;

}])

.directive('egPatronSummary', ['egUser','patronSvc', function(egUser, patronSvc) {
    return {
        restrict : 'E',
        transclude: true,
        templateUrl : './circ/patron/t_summary',
        scope : {
            patronId : '='
        },
        controller : [
                    '$scope','egCore',
            function($scope , egCore) {
                var user;
                var user_stats;
                egUser.get($scope.patronId).then(function(u) {
                    user = u;
                    patronSvc.localFlesh(user);
                });
                patronSvc.getUserStats($scope.patronId).then(function(s) {
                    user_stats = s;
                });
                $scope.patron = function() {
                    return user;
                }
                $scope.patron_stats = function() {
                    return user_stats;
                }

                // show/obscure DOB logic copied from the circ patron app
                $scope._show_dob = {};
                $scope.show_dob = function (val) {
                    if ($scope.patron()) {
                        if (typeof val != 'undefined') $scope._show_dob[$scope.patron().id()] = val;
                        return $scope._show_dob[$scope.patron().id()];
                    }
                    return !egCore.env.aous['circ.obscure_dob'];
                }

                $scope.obscure_dob = function() {
                    return egCore.env.aous && egCore.env.aous['circ.obscure_dob'];
                }
                $scope.now_show_dob = function() {
                    return egCore.env.aous && egCore.env.aous['circ.obscure_dob'] ?
                        $scope.show_dob() : true;
                }

                // needed because this directive shares a template with
                // the patron summary in circ app, but the circ app
                // displays the patron name elsewhere. 
                $scope.show_name = function() {
                    return true;
                }
            }
        ]
    }
}]);
