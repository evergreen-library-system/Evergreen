angular.module('egSerialsAppDep')

.directive('egMfhdManager', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            bibId  : '=',
        },
        templateUrl: './serials/t_mfhd_manager',
        controller:
       ['$scope','$q','egSerialsCoreSvc','egCore','egGridDataProvider',
        '$uibModal','$timeout','egMfhdCreateDialog','egConfirmDialog',
function($scope , $q , egSerialsCoreSvc , egCore , egGridDataProvider ,
         $uibModal , $timeout , egMfhdCreateDialog , egConfirmDialog) {

    function reload() {
        egSerialsCoreSvc.fetch_mfhds($scope.bibId).then(function() {
            $scope.mfhdGridDataProvider.refresh();
        });
    }
    reload();

    $scope.mfhdGridControls = {
        activateItem : function (item) { } // TODO
    };
    $scope.mfhdGridDataProvider = egGridDataProvider.instance({
        get : function(offset, count) {
            return this.arrayNotifier(egSerialsCoreSvc.flatMfhdList, offset, count);
        }
    });
    $scope.need_one_selected = function() {
        var items = $scope.mfhdGridControls.selectedItems();
        if (items.length == 1) return false;
        return true;
    };

    $scope.createMfhd = function() {
        egMfhdCreateDialog.open($scope.bibId).result.then(function() {
            reload();
        });
    };

    $scope.edit_mfhd = function() {
        var items = $scope.mfhdGridControls.selectedItems();
        if (items.length != 1) return;
        var args = {
            'marc_xml' : items[0].marc_xml
        }
        $uibModal.open({
            templateUrl: './share/t_edit_mfhd',
            backdrop: 'static',
            size: 'lg',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.args = args;
                $scope.dirty_flag = false;
                $scope.ok = function() { $uibModalInstance.close($scope.args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        }).result.then(function (args) {
            egCore.pcrud.retrieve('sre', items[0].id).then(function(sre) {
                sre.marc(args.marc_xml);
                egCore.pcrud.update(sre).then(function() {
                    reload();
                });
            });
        });
    };

    $scope.delete_mfhds = function() {
        var items = $scope.mfhdGridControls.selectedItems();
        if (items.length <= 0) return;
        
        egConfirmDialog.open(
            egCore.strings.CONFIRM_DELETE_MFHDS,
            egCore.strings.CONFIRM_DELETE_MFHDS_MESSAGE,
            {items : items.length}
        ).result.then(function () {
            var promises = [];
            angular.forEach(items, function(mfhd) {
                var promise = $q.defer();
                promises.push(promise.promise);    
                egCore.pcrud.retrieve('sre', mfhd.id).then(function(sre) {
                    egCore.pcrud.remove(sre).then(function() {
                        promise.resolve();
                    });
                })
            });
            $q.all(promises).then(function() {
                reload();
            });
        });
    }
}]
    }
})
