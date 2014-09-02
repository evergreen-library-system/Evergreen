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
        $scope.updateOK = false;

        egCore.pcrud.search('acp', 
            {deleted : 'f', barcode : $scope.barcode1})
        .then(function(copy) {

            if (!copy) {
                $scope.focusBarcode = true;
                $scope.copyNotFound = true;
                return;
            }

            $scope.copyId = copy.id();
            copy.barcode($scope.barcode2);

            egCore.pcrud.update(copy).then(function(stat) {
                $scope.updateOK = stat;
                $scope.focusBarcode = true;
            });
        });
    }
}]);

