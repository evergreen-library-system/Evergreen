angular.module('egAdminConfig',
    ['ngRoute','ui.bootstrap','egCoreMod','egUiMod','egGridMod','egFmRecordEditorMod'])

.controller('MetabibFieldVirtualMap',
       ['$scope','$q','$timeout','$location','$window','$uibModal','egCore','egGridDataProvider',
        'egConfirmDialog',
function($scope , $q , $timeout , $location , $window , $uibModal , egCore , egGridDataProvider ,
         egConfirmDialog) {

    egCore.startup.go(); // standalone mode requires manual startup

    $scope.cmf = null;

    $scope.virt_field = $location.search().cmf || '';
    if ($scope.virt_field) egCore.pcrud.retrieve('cmf', $scope.virt_field).then(function(c) { $scope.cmf = c });

    $scope.$watch('virt_field', function(newVal, oldVal) {
        if (newVal != oldVal) {
            egCore.pcrud.retrieve('cmf', newVal).then(function(c) { $scope.cmf = c });
            $scope.gridControls.setQuery(generateQuery($scope.virt_field));
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
            templ = '<eg-edit-fm-record idl-class="cmfvm" mode="update" record-id="id" on-save="ok" on-cancel="cancel"></eg-edit-fm-record>';
        } else {
            templ = '<eg-edit-fm-record idl-class="cmfvm" mode="create" on-save="ok" on-cancel="cancel"></eg-edit-fm-record>';
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

        egCore.pcrud.retrieve('cmfvm', selected[0].id).then(function(rec) {
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

    function generateQuery(virt_field) {
        var q = { 'id' : { '!=' : null } };

        if (virt_field) {
            q.virtual = virt_field;
        }

        return q;
    }

    $scope.gridControls = {
        activateItem : function (i) { return $scope.edit_record([i]) },
        setQuery : function() {
            return generateQuery($scope.virt_field);
        },
        setSort : function() {
            return ['label'];
        }
    }
}])
