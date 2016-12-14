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


	service.changeOperator = function(calledFromNavbar, failedRequest) {
		var _op_changed = false;
        $uibModal.open({
            templateUrl: './share/t_opchange',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.args = {username : '', password : '', type : 'temp'};
                $scope.displayTypeField = calledFromNavbar;
                $scope.title = egStrings.OP_CHANGE_TITLE;
                if(failedRequest) {
                    $scope.title = failedRequest.perm_evt.desc + ": "
                        + failedRequest.perm_evt.ilsperm;
                    $scope.message = egStrings.OP_CHANGE_PERM_MESSAGE;
                    console.log($scope.message);
                }
                $scope.focus = true;
                $scope.ok = function() { $uibModalInstance.close($scope.args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        }).result.then(function (args) {
            if (!args || !args.username || !args.password) return;
            args.type = args.type || 'temp';
            args.workstation = egAuth.workstation();
            egAuth.opChange(args).then(
                function() {
                    _op_changed = true;
                    if(failedRequest) {
                        console.log(js2JSON(failedRequest));
                        egNet.request(
                            failedRequest.service,
                            failedRequest.method,
                            egAuth.token(),
                            failedRequest.params[1]
                        ).then(service.changeOperatorUndo());
                    } else {
                        ngToast.create(egStrings.OP_CHANGE_SUCCESS);
                    }
                },
                function() {
                    ngToast.warning(egStrings.OP_CHANGE_FAILURE);
                }
            );
        });
        return _op_changed;
    }

    service.changeOperatorUndo = function() {
        egAuth.opChangeUndo();
        var _op_changed = false;
        ngToast.create(egStrings.OP_CHANGE_SUCCESS);
        return _op_changed;
    }

    //Check for any permission failure broadcasts. then call changeOperator and retry the action
    $rootScope.$on('egNetPermFailure', function(args, request_info) {
        var op_changed = service.changeOperator(false, request_info);
    })

	return service;
}])
