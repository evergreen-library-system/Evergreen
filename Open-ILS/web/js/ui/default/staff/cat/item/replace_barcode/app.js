/**
 * Item Display
 */

angular.module('egItemReplaceBarcode', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.controller('ReplaceItemBarcodeCtrl',
       ['$scope','egCore',
function($scope , egCore) {
    egCore.startup.go();

    $scope.focusBarcode = true;

    $scope.updateBarcode = function() {
        $scope.copyNotFound = false;
        $scope.duplicateBarcode = false;
        $scope.updateOK = false;

        egCore.pcrud.search('acp',
            {deleted : 'f', barcode : $scope.barcode1})
        .then(function(copy) {

            if (!copy) {
                $scope.focusBarcode = true;
                $scope.copyNotFound = true;
                return;
            }

            egCore.pcrud.search('acp',
                {deleted : 'f', barcode : $scope.barcode2})
            .then(function(newBarcodeCopy) {

                if (newBarcodeCopy) {
                    $scope.duplicateBarcode = true;
                    return;
                }

                $scope.copyId = copy.id();

                egCore.net.request(
                    'open-ils.cat',
                    'open-ils.cat.update_copy_barcode',
                    egCore.auth.token(), $scope.copyId, $scope.barcode2
                ).then(function(resp) {
                    var evt = egCore.evt.parse(resp);
                    if (evt) {
                        console.log('toast 0 here 2', evt);
                    } else {
                        $scope.updateOK = true;
                        $scope.focusBarcode = true;
                    }
                });

            });
        });
    }
}]);

