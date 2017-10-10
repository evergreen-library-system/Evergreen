angular.module('egCoreMod')

/**
 * egPermLoginDialog.open(
 *  open("some message goes {{here}}", {
 *  here : 'foo', ok : function() {}, cancel : function() {}},
 *  'OK', 'Cancel');
 */
.factory('egOpChange',

       ['$uibModal','$interpolate', '$rootScope', '$q', 'egAuth', 'egStrings', 'egNet', 'ngToast',
function($uibModal, $interpolate, $rootScope, $q, egAuth, egStrings, egNet, ngToast) {

    var service = {};

    // Returns a promise resolved upon successful op-change.
    // Rejected otherwise.
    service.changeOperator = function(permEvt) {
        return $uibModal.open({
            templateUrl: './share/t_opchange',
            backdrop: 'static',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.args = {username : '', password : '', type : 'temp'};
                $scope.title = egStrings.OP_CHANGE_TITLE;
                if (permEvt) {
                    $scope.title = permEvt.desc + ": " + permEvt.ilsperm;
                    $scope.message = egStrings.OP_CHANGE_PERM_MESSAGE;
                } else {
                    $scope.displayTypeField = true;
                }
                $scope.focus = true;
                $scope.ok = function() { $uibModalInstance.close($scope.args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        }).result.then(function (args) {
            if (!args || !args.username || !args.password)
                return $q.reject();

            args.type = args.type || 'temp';
            args.workstation = egAuth.workstation();
            return egAuth.opChange(args).then(
                function() {
                    console.debug('op-change succeeded');
                    if (permEvt) {
                        ngToast.create(egStrings.PERM_OP_CHANGE_SUCCESS);
                    } else {
                        ngToast.create(egStrings.OP_CHANGE_SUCCESS);
                    }
                },
                function() {
                    console.debug('op-change failed');
                    if (permEvt) {
                        ngToast.warning(egStrings.PERM_OP_CHANGE_FAILURE);
                    } else {
                        ngToast.warning(egStrings.OP_CHANGE_FAILURE);
                    }
                }
            );
        });
    }

    // Returns a promise resolved on successful op-change undo.
    service.changeOperatorUndo = function(hideToast) {
        return egAuth.opChangeUndo().then(
            function() {
                console.debug('op-change undo succeeded');
                if (!hideToast) ngToast.create(egStrings.OP_CHANGE_SUCCESS);
            },
            function() {
                console.debug('op-change undo failed');
                if (!hideToast) ngToast.warning(egStrings.OP_CHANGE_FAILURE);
            }
        );
    }

    // Tell egNet to use our permission failure handler,
    // since we know how to launch a login override dialog.
    //
    // 1. Launch the change-operator dialog
    // 2. If op-change succeeds, re-do the failed request using the
    //    op-change'd authtoken.
    // 3. Undo the op-change.
    //
    // Returns a promise resolved along with the re-ran request.
    egNet.handlePermFailure = function(request) {
        console.debug("perm override required for "+request.method);

        return service.changeOperator(request.evt).then(function() {

            return egNet.requestWithParamList(
                request.service,
                request.method,
                // original params, but replace the failed authtoken
                // with the op-change'd authtoken
                [egAuth.token()].concat(request.params.splice(1))

            )['finally'](function() {
                // always undo the operator change after a perm override.
                console.debug("clearing op-change after perm override redo");
                service.changeOperatorUndo(true);
            });
        });
    }

    return service;
}])
