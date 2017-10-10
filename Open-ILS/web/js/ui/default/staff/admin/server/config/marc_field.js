angular.module('egAdminConfig',
    ['ngRoute','ui.bootstrap','egCoreMod','egUiMod','egGridMod','egFmRecordEditorMod'])

.controller('MarcField',
       ['$scope','$q','$timeout','$location','$window','$uibModal','egCore','egGridDataProvider',
        'egConfirmDialog',
function($scope , $q , $timeout , $location , $window , $uibModal , egCore , egGridDataProvider ,
         egConfirmDialog) {

    egCore.startup.go(); // standalone mode requires manual startup

    $scope.marc_record_type = 'biblio';
    $scope.$watch('marc_record_type', function(newVal, oldVal) {
        if (newVal != oldVal) {
            $scope.gridControls.setQuery(generateQuery($scope.marc_record_type));
            $scope.gridControls.refresh();
        }
    });

    $scope.new_record = function() {
        spawn_editor();
    }

    $scope.edit_record = function(items) {
        if (items.length != 1) return;
        spawn_editor(items[0].id);
    }

    spawn_editor = function(id) {
        var templ;
        if (arguments.length == 1) {
            templ = '<eg-edit-fm-record idl-class="cmrcfld" mode="update" record-id="id" on-save="ok" on-cancel="cancel"></eg-edit-fm-record>';
        } else {
            templ = '<eg-edit-fm-record idl-class="cmrcfld" mode="create" on-save="ok" on-cancel="cancel"></eg-edit-fm-record>';
        }
        gridControls = $scope.gridControls;
        $uibModal.open({
            template : templ,
            backdrop: 'static',
            controller : [
                        '$scope', '$uibModalInstance',
                function($scope ,  $uibModalInstance) {
                    $scope.id = id;

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

    $scope.delete_record = function(selected) {
        if (!selected || !selected.length) return;

        egCore.pcrud.retrieve('cmrcfld', selected[0].id).then(function(rec) {
            egConfirmDialog.open(
                egCore.strings.EG_CONFIRM_DELETE_RECORD_TITLE,
                egCore.strings.EG_CONFIRM_DELETE_RECORD_BODY,
                { id : rec.id() } // TODO replace with selector if available?
            ).result.then(function() {
                egCore.pcrud.remove(rec).then(function() {
                    $scope.gridControls.refresh();
                });
            });
        });
    }

    function generateQuery(marc_record_type) {
        return {
            'id' : { '!=' : null },
            'marc_record_type' : marc_record_type
        }
    }

    $scope.gridControls = {
        setQuery : function() {
            return generateQuery($scope.marc_record_type);
        },
        setSort : function() {
            return ['tag'];
        }
    }
}])
