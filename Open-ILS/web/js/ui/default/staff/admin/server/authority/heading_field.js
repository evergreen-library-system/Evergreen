angular.module('egAdminConfig',
    ['ngRoute','ui.bootstrap','egCoreMod','egUiMod','egGridMod','egFmRecordEditorMod'])

.controller('AuthorityHeadingField',
       ['$scope','$q','$timeout','$location','$window','$uibModal','egCore','egGridDataProvider',
        'egConfirmDialog',
function($scope , $q , $timeout , $location , $window , $uibModal , egCore , egGridDataProvider ,
         egConfirmDialog) {

    egCore.startup.go(); // standalone mode requires manual startup

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
            templ = '<eg-edit-fm-record idl-class="ahf" mode="update" record-id="id" on-save="ok" on-cancel="cancel"></eg-edit-fm-record>';
        } else {
            templ = '<eg-edit-fm-record idl-class="ahf" mode="create" on-save="ok" on-cancel="cancel"></eg-edit-fm-record>';
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

        egCore.pcrud.retrieve('ahf', selected[0].id).then(function(rec) {
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

    function generateQuery() {
        return {
            'id' : { '!=' : null }
        }
    }

    $scope.gridControls = {
        setQuery : function() {
            return generateQuery();
        },
        setSort : function() {
            return ['heading_type','heading_purpose'];
        }
    }
}])
