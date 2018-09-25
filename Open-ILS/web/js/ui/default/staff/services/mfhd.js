/**
  * MFHD tools and directives.
  */
angular.module('egMfhdMod', ['egCoreMod', 'ui.bootstrap'])

.factory('egMfhdCreateDialog',
       ['$uibModal','egCore',
function($uibModal , egCore) {
    var service = {};

    service.open = function(bibId, orgId) {
        return $uibModal.open({
            templateUrl: './share/t_mfhd_create_dialog',
            backdrop: 'static',
            controller: ['$scope', '$uibModalInstance',
                function($scope, $uibModalInstance) {
                    $scope.mfhd_lib = orgId ?
                        egCore.org.get(orgId) :
                        null;
                    $scope.ok = function() {
                        egCore.net.request(
                            'open-ils.cat',
                            'open-ils.cat.serial.record.xml.create',
                            egCore.auth.token(),
                            1, // source
                            $scope.mfhd_lib.id(),
                            bibId
                        ).then(function() {
                            $uibModalInstance.close()
                        });
                    }
                    $scope.cancel = function() {
                        $uibModalInstance.dismiss();
                    }
                }
            ]
        })
    }

    return service;
}
])
