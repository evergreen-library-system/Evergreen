angular.module('egAdminConfig',
    ['ngRoute','ui.bootstrap','egCoreMod','egUiMod','egGridMod','egFmRecordEditorMod','egSerialsMod','egSerialsAppDep'])

.controller('PatternTemplate',
       ['$scope','$q','$timeout','$location','$window','$uibModal','egCore','egGridDataProvider',
        'egConfirmDialog','ngToast',
function($scope , $q , $timeout , $location , $window , $uibModal , egCore , egGridDataProvider ,
         egConfirmDialog , ngToast) {

    egCore.startup.go(); // standalone mode requires manual startup

    $scope.new_record = function() {
        spawn_editor();
    }

    $scope.need_one_selected = function() {
        var items = $scope.gridControls.selectedItems();
        if (items.length == 1) return false;
        return true;
    };

    $scope.edit_record = function(items) {
        if (items.length != 1) return;
        spawn_editor(items[0].id);
    }

    spawn_editor = function(id) {
        var templ;
        if (arguments.length == 1) {
            templ = '<eg-edit-fm-record idl-class="spt" mode="update" record-id="id" on-save="ok" on-cancel="cancel" custom-field-templates="customFieldTemplates"></eg-edit-fm-record>';
        } else {
            templ = '<eg-edit-fm-record idl-class="spt" mode="create" on-save="ok" on-cancel="cancel" custom-field-templates="customFieldTemplates" org-default-allowed="owning_lib"></eg-edit-fm-record>';
        }
        gridControls = $scope.gridControls;
        $uibModal.open({
            template : templ,
            backdrop: 'static',
            controller : [
                        '$scope', '$uibModalInstance',
                function($scope ,  $uibModalInstance) {
                    $scope.id = id;

                    $scope.openPatternEditorDialog = function(pred) {
                        $uibModal.open({
                            templateUrl: './serials/t_pattern_editor_dialog',
                            size: 'lg',
                            windowClass: 'eg-wide-modal',
                            backdrop: 'static',
                            controller:
                                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                                $scope.focusMe = true;
                                $scope.showShare = false;
                                $scope.patternCode = pred.pattern_code;
                                $scope.ok = function(patternCode) { $uibModalInstance.close(patternCode) }
                                $scope.cancel = function () { $uibModalInstance.dismiss() }
                            }]
                        }).result.then(function (patternCode) {
                            if (pred.pattern_code !== patternCode) {
                                pred.pattern_code = patternCode;
                            }
                        });
                    }

                    $scope.customFieldTemplates = {
                        share_depth : {
                            template : '<eg-share-depth-selector ng-model="rec_flat[field.name]">'
                        },
                        pattern_code : {
                            handlers : {
                                openPatternEditorDialog : $scope.openPatternEditorDialog
                            },
                            template : '<button class="btn btn-default" ng-click="field.handlers.openPatternEditorDialog(rec_flat)">Pattern Wizard</button>' + // FIXME i18n
                                       // using a required hidden input as a way to ensure that
                                       // the pattern wizard has been used
                                       '<input type="hidden" required ng-model="rec_flat[field.name]">'
                        }
                    }

                    $scope.ok = function($event) {
                        $uibModalInstance.close();
                        gridControls.refresh();
                    }
    
                    $scope.cancel = function($event) {
                        $uibModalInstance.dismiss();
                    }
                }
            ]
        });
    }

    $scope.delete_selected = function(selected) {
        if (!selected || !selected.length) return;
        var ids = selected.map(function(rec) { return rec.id });

        egConfirmDialog.open(
            egCore.strings.EG_CONFIRM_DELETE_PATTERN_TEMPLATE_TITLE,
            egCore.strings.EG_CONFIRM_DELETE_PATTERN_TEMPLATE_BODY,
            { count : ids.length }
        ).result.then(function() {
            var promises = [];
            var list = [];
            angular.forEach(selected, function(rec) {
                promises.push(
                    egCore.pcrud.retrieve('spt', rec.id).then(function(r) {
                        list.push(r);
                    })
                );
            })
            $q.all(promises).then(function() {
                egCore.pcrud.remove(list).then(function() {
                    ngToast.success(egCore.strings.PATTERN_TEMPLATE_SUCCESS_DELETE);
                    $scope.gridControls.refresh();
                },
                function() {
                    ngToast.success(egCore.strings.PATTERN_TEMPLATE_FAIL_DELETE);
                });
            });
        });
    }

    function generateQuery() {
        return {
            'id' : { '!=' : null },
        }
    }

    $scope.gridControls = {
        setQuery : function() {
            return generateQuery();
        },
        setSort : function() {
            return ['owning_lib.name','name'];
        }
    }
}])
