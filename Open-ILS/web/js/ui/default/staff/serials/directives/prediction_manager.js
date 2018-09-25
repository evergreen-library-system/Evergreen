angular.module('egSerialsAppDep')

.directive('egPredictionManager', function() {
    return {
        transclude: true,
        restrict:   'E',
        scope: {
            bibId  : '=',
            ssubId : '='
        },
        templateUrl: './serials/t_prediction_manager',
        controller:
       ['$scope','$q','egSerialsCoreSvc','egCore','egGridDataProvider',
        '$uibModal','$timeout','$location','egConfirmDialog','ngToast',
function($scope , $q , egSerialsCoreSvc , egCore , egGridDataProvider ,
         $uibModal , $timeout , $location , egConfirmDialog , ngToast) {

    $scope.has_pattern_to_import = false;
    $scope.forms = [];
    egSerialsCoreSvc.fetch($scope.bibId).then(function() {
        reload($scope.ssubId);
        egSerialsCoreSvc.fetch_patterns_from_bibs_mfhds($scope.bibId).then(function() {
            if (egSerialsCoreSvc.potentialPatternList.length > 0) {
                $scope.has_pattern_to_import = true;
            }
        });
    });

    function reload(ssubId) {
        if (!ssubId) return;
        var ssub = egSerialsCoreSvc.get_ssub(ssubId);
        $scope.predictions = egCore.idl.toTypedHash(ssub.scaps());
        angular.forEach($scope.predictions, function(pred) {
            pred._can_edit_or_delete = false;
            egCore.net.request(
                'open-ils.serial',
                'open-ils.serial.caption_and_pattern.safe_delete.dry_run',
                egCore.auth.token(),
                pred.id
            ).then(function(result) {
                if (result == 1) pred._can_edit_or_delete = true;
            });
        });
        egSerialsCoreSvc.fetch_spt().then(function() {
            $scope.pattern_templates = egCore.idl.toTypedHash(egSerialsCoreSvc.sptList);
            $scope.active_pattern_template = { id : null };
            if ($scope.pattern_templates.length > 0) {
                $scope.active_pattern_template.id = $scope.pattern_templates[0].id;
            }
        });
    }

    $scope.createScap = function(pred) {
        var scap = egCore.idl.fromTypedHash(pred);
        egCore.pcrud.create(scap).then(function() {
            // completely reset the model in order to reset the
            // forms; causes a blink, alas
            $scope.predictions = [];
            $scope.new_prediction = null;
            egSerialsCoreSvc.fetch($scope.bibId).then(function() {
                reload($scope.ssubId);
            });
        });
    }
    $scope.updateScap = function(pred) {
        var scap = egCore.idl.fromTypedHash(pred);
        egCore.pcrud.update(scap).then(function() {
            // completely reset the model in order to reset the
            // forms; causes a blink, alas
            $scope.predictions = [];
            egSerialsCoreSvc.fetch($scope.bibId).then(function() {
                reload($scope.ssubId);
            });
        });
    }
    $scope.deleteScap = function(pred) {
        var scap = egCore.idl.fromTypedHash(pred);
        egConfirmDialog.open(
            egCore.strings.CONFIRM_DELETE_SCAP,
            egCore.strings.CONFIRM_DELETE_SCAP_MESSAGE,
            {}
        ).result.then(function () {
            egCore.net.request(
                'open-ils.serial',
                'open-ils.serial.caption_and_pattern.safe_delete',
                egCore.auth.token(),
                scap.id()
            ).then(function(resp){
                var evt = egCore.evt.parse(resp);
                if (evt) {
                    ngToast.danger(egCore.strings.SERIALS_SCAP_FAIL_DELETE + ' : ' + evt.desc);
                } else {
                    ngToast.success(egCore.strings.SERIALS_SCAP_SUCCESS_DELETE);
                }
 
                $scope.predictions = [];
                egSerialsCoreSvc.fetch($scope.bibId).then(function() {
                    reload($scope.ssubId);
                });
            })
        });
    }
    $scope.cancelNewScap = function() {
        $scope.new_prediction = null;
    }
    $scope.startNewScap = function() {
        $scope.new_prediction = egCore.idl.toTypedHash(new egCore.idl.scap());
        $scope.new_prediction.type = 'basic';
        $scope.new_prediction.active = true;
        $scope.new_prediction.create_date = new Date();
        $scope.new_prediction.subscription = $scope.ssubId;
        $scope.new_prediction.pattern_code = null;
    }

    $scope.importScapFromBibRecord = function() {
        $uibModal.open({
            templateUrl: './serials/t_select_pattern_dialog',
            backdrop: 'static',
            size: 'md',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.potentials = egSerialsCoreSvc.potentialPatternList.slice();
                $scope.ok = function(patternCode) { $uibModalInstance.close($scope.potentials) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        }).result.then(function (potentials) {
            var marc = [];
            angular.forEach(potentials, function(pot) {
                if (pot.selected) {
                    marc.push(pot.marc);
                }
            });
            if (marc.length == 0) return;
            egCore.net.request(
                'open-ils.serial',
                'open-ils.serial.caption_and_pattern.create_from_records',
                egCore.auth.token(),
                $scope.ssubId,
                marc
            ).then(function() {
                egSerialsCoreSvc.fetch($scope.bibId).then(function() {
                    reload($scope.ssubId);
                });
            });
        });
    }
    
    $scope.importScapFromSpt = function() {
        $scope.new_prediction = egCore.idl.toTypedHash(new egCore.idl.scap());
        $scope.new_prediction.type = 'basic';
        $scope.new_prediction.active = true;
        $scope.new_prediction.create_date = new Date();
        $scope.new_prediction.subscription = $scope.ssubId;
        for (var i = 0; i < $scope.pattern_templates.length; i++) {
            if ($scope.pattern_templates[i].id == $scope.active_pattern_template.id) {
                $scope.new_prediction.pattern_code = $scope.pattern_templates[i].pattern_code;
                break;
            }
        }
        // Mark form dirty because, when it's created from a template,
        // it can be immediately saved if the user so chooses. The
        // $watch() allows this to happen after the form is bound
        // is bound to the scope.
        $scope.$watch('forms.newpredform', function(form) {
            if (form) form.$setDirty();
        });
    }

    $scope.openPatternEditorDialog = function(pred, form, viewOnly) {
        $uibModal.open({
            templateUrl: './serials/t_pattern_editor_dialog',
            backdrop: 'static',
            size: 'lg',
            windowClass: 'eg-wide-modal',
            backdrop: 'static',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.viewOnly = viewOnly;
                $scope.focusMe = true;
                $scope.patternCode = pred.pattern_code;
                $scope.ok = function(patternCode) { $uibModalInstance.close(patternCode) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        }).result.then(function (patternCode) {
            if (pred.pattern_code !== patternCode) {
                pred.pattern_code = patternCode;
                form.$setDirty();        
            }
        });
    }

    $scope.add_issuances = function() {
        return egSerialsCoreSvc.fetchItemsForSub($scope.ssubId).then(function() {
            egSerialsCoreSvc.add_issuances($scope.ssubId).then(function() {
                $location.path('/serials/' + $scope.bibId + '/issues/' +
                                $scope.ssubId);
            });
        });
    }

}]
    }
})
