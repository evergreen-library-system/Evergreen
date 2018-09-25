angular.module('egAdminConfig',
    ['ngRoute','ui.bootstrap','egCoreMod','egUiMod','egGridMod','egFmRecordEditorMod'])

.controller('MetabibField',
       ['$scope','$q','$timeout','$location','$window','$uibModal','egCore','egGridDataProvider',
        'egConfirmDialog',
function($scope , $q , $timeout , $location , $window , $uibModal , egCore , egGridDataProvider ,
         egConfirmDialog) {

    egCore.startup.go(); // standalone mode requires manual startup

    $scope.search_class = '';
    $scope.$watch('search_class', function(newVal, oldVal) {
        if (newVal != oldVal) {
            $scope.gridControls.setQuery(generateQuery($scope.search_class));
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
            templ = '<eg-edit-fm-record idl-class="cmf" mode="update" record-id="id" on-save="ok" on-cancel="cancel"></eg-edit-fm-record>';
        } else {
            templ = '<eg-edit-fm-record idl-class="cmf" mode="create" on-save="ok" on-cancel="cancel"></eg-edit-fm-record>';
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

        egCore.pcrud.retrieve('cmf', selected[0].id).then(function(rec) {
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

    function generateQuery(search_class) {
        var q = { 'id' : { '!=' : null } };

        if (search_class) {
            q.field_class = search_class;
        }

        return q;
    }

    $scope.gridControls = {
        activateItem : function (i) { return $scope.edit_record([i]) },
        setQuery : function() {
            return generateQuery($scope.search_class);
        },
        setSort : function() {
            return ['label'];
        }
    }
}])
