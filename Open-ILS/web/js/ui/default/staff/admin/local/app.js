angular.module('egLocalAdmin',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod','egGridMod'])

.config(['$routeProvider','$locationProvider','$compileProvider', 
 function($routeProvider , $locationProvider , $compileProvider) {

    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); 
	
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    var eframe_template = 
        '<eg-embed-frame allow-escape="true" min-height="min_height" url="local_admin_url" handlers="funcs"></eg-embed-frame>';

    // non-conify routes come first
    $routeProvider.when('/admin/local/money/cash_reports', {
        template: eframe_template,
        controller: 'EmbedXHTMLCtl', // non-conify
        resolve : resolver
    });
   
    // non-conify routes come first
    $routeProvider.when('/admin/local/actor/closed_dates', {
        template: eframe_template,
        controller: 'EmbedXHTMLCtl', // non-conify
        resolve : resolver
    });
    
    // non-conify routes come first
    $routeProvider.when('/admin/local/asset/copy_locations', {
        template: eframe_template,
        controller: 'EmbedXHTMLCtl', // non-conify
        resolve : resolver
    });

    // non-conify routes come first
    $routeProvider.when('/admin/local/asset/org_unit_settings', {
        template: eframe_template,
        controller: 'EmbedXHTMLCtl', // non-conify
        resolve : resolver
    });

    $routeProvider.when('/admin/local/config/non_cat_types', {
        template: eframe_template,
        controller: 'EmbedXHTMLCtl', // non-conify
        resolve : resolver
    });

    $routeProvider.when('/admin/local/asset/stat_cat_editor', {
        template: eframe_template,
        controller: 'EmbedXHTMLCtl', // non-conify
        resolve : resolver
    });

    $routeProvider.when('/admin/local/config/copy_alert_types', {
        templateUrl: './admin/local/t_grid_editor',
        controller: 'AutoGridEditorCtl',
        fmBase: 'ccat',
        createEditPrefetch: {
            ccs : { id : {'!=' : null} }
        },
        createDefaults : { 'in_renew' : 'f', 'next_status' : [] },
        createEditOrgExpand: ['scope_org'],
        createEditIntarray: ['next_status'],
        createEditNullableBool : ['in_renew', 'at_circ', 'at_owning']
    });

    $routeProvider.when('/admin/local/actor/copy_alert_suppress', {
        templateUrl: './admin/local/t_grid_editor',
        controller: 'AutoGridEditorCtl',
        fmBase: 'acas',
        createEditPrefetch: {
            ccat : { active: 't' }
        },
        createEditOrgExpand: ['org']
    });

    // Conify page handler
    $routeProvider.when('/admin/local/:schema/:page', {
        template: eframe_template,
        controller: 'EmbedConifyCtl',
        resolve : resolver
    });

    // default page 
    $routeProvider.otherwise({
        templateUrl : './admin/local/t_splash',
        resolve : resolver
    });
}])

.controller('EmbedConifyCtl', 
       ['$scope','$routeParams','$location','egCore',
function($scope , $routeParams , $location , egCore) {

    $scope.funcs = {
        ses : egCore.auth.token(),
    }

    var conify_path = '/eg/conify/global/' + 
        $routeParams.schema + '/' + $routeParams.page;

    $scope.min_height = 800;

    // embed URL must include protocol/domain or it will be loaded via
    // push-state, resulting in an infinitely nested pages.
    $scope.local_admin_url = 
        $location.absUrl().replace(/\/eg\/staff.*/, conify_path);

    console.log('Loading local admin URL: ' + $scope.local_admin_url);

}])

.controller('EmbedXHTMLCtl', 
       ['$scope','$location','egCore','$timeout',
function($scope , $location , egCore , $timeout) {

    $scope.funcs = {};

    var xul_base = '/xul/server/admin/';
    var page_parts = $location.path().split(/\//);
    var url = xul_base + page_parts[page_parts.length - 1] + '.xhtml';

    // old-school XUL admin UI's only want CGI ses values.
    url += '?ses=' + egCore.auth.token();
    
    console.log('Loading local admin URL: ' + $scope.local_admin_url);

    $scope.local_admin_url = $location.absUrl().replace(/\/.*/, url);
}])

.controller('AutoGridEditorCtl',
       ['$scope','$route','$location','egCore','$timeout','egConfirmDialog','$uibModal',
function($scope , $route , $location , egCore , $timeout , egConfirmDialog , $uibModal) {

    $scope.funcs = {};

    $scope.baseFmClass = $route.current.$$route.fmBase;
    $scope.createEditPrefetch = $route.current.$$route.createEditPrefetch || {};
    $scope.createEditOrgExpand = $route.current.$$route.createEditOrgExpand || [];
    $scope.createEditNullableBool = $route.current.$$route.createEditNullableBool || [];
    $scope.createEditIntarray = $route.current.$$route.createEditIntarray || [];
    $scope.createDefaults = $route.current.$$route.createDefaults || {};
    $scope.gridControls = {
        setQuery : function(q) {
            if (q) query = q;
            return query;
        },
        activateItem : function (item) {
            $scope.editHandler([item])
        }
    };
    $scope.gridControls.setQuery({id : {'!=' : null}});

    function openCreateEditDialog(id) {
        return $uibModal.open({
            templateUrl : './admin/local/autoGridEditor/' + $scope.baseFmClass,
            scope : $scope,
            controller :
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.creating = id ? false : true;
                angular.forEach($scope.$parent.createEditPrefetch, function(where, fmClass) {
                    egCore.pcrud.search(
                        fmClass, where, {},
                        {atomic : true, authoritative : true}
                    ).then(function(vals) {
                        $scope[fmClass] = vals;
                    });
                });
                if ($scope.creating) {
                    $scope.record = $scope.createDefaults;
                } else {
                    egCore.pcrud.retrieve($scope.baseFmClass, id).then(function(to_edit) {
                        $scope.record = egCore.idl.toHash(to_edit);
                        angular.forEach($scope.createEditOrgExpand, function(ou_field) {
                            $scope.record[ou_field] = egCore.org.get($scope.record[ou_field]);
                        });
                        angular.forEach($scope.createEditIntarray, function(intarray_field) {
                            if (!($scope.record[intarray_field] == null) && $scope.record[intarray_field] != "") {
                                $scope.record[intarray_field] = $scope.record[intarray_field]
                                                    .replace('{', '')
                                                    .replace('}', '')
                                                    .split(',');
                            } else {
                                $scope.record[intarray_field] = [];
                            }
                        });
                    });
                }
                $scope.ok = function(record) { $uibModalInstance.close(record) };
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        });
    }

    $scope.createHandler = function() {
        openCreateEditDialog().result.then(function(record) {
            var newRec = new egCore.idl[$scope.baseFmClass]();
            angular.forEach(record, function(val, key) {
                if (typeof(val) === 'object' && !angular.isArray(val)) {
                    newRec[key](val.id());
                } else {
                    newRec[key](val);
                }
            });
            angular.forEach($scope.createEditNullableBool, function(nb_field) {
                if (!(record[nb_field] == null) && record[nb_field] == "")
                    newRec[nb_field](null);
            });
            angular.forEach($scope.createEditIntarray, function(intarray_field) {
                if (newRec[intarray_field]().length > 0) {
                    newRec[intarray_field]('{' + newRec[intarray_field]().join(',') + '}');
                } else {
                    newRec[intarray_field](null);
                }
            });
            return egCore.pcrud.create(newRec);
        }).then(function(){
            $scope.gridControls.refresh();
        });
    };
    $scope.editHandler = function(items) {
        openCreateEditDialog(items[0].id).result.then(function(record) {
            var editedRec = new egCore.idl[$scope.baseFmClass]();
            angular.forEach(record, function(val, key) {
                if (angular.isObject(val) && !angular.isArray(val)) {
                    editedRec[key](val.id());
                } else {
                    editedRec[key](val);
                }
            });
            angular.forEach($scope.createEditNullableBool, function(nb_field) {
                if (!(record[nb_field] == null) && record[nb_field] == "")
                    editedRec[nb_field](null);
            });
            angular.forEach($scope.createEditIntarray, function(intarray_field) {
                if (editedRec[intarray_field]().length > 0) {
                    editedRec[intarray_field]('{' + editedRec[intarray_field]().join(',') + '}');
                } else {
                    editedRec[intarray_field](null);
                }
            });
            return egCore.pcrud.update(editedRec);
        }).then(function(){
            $scope.gridControls.refresh();
        });
    };
    $scope.deleteHandler = function(items) {
        egConfirmDialog.open(
            egCore.strings.REMOVE_ITEM_CONFIRM,
            '',
            {}
        ).result.then(function() {
            var ids = items.map(function(s){ return s.id });
            egCore.pcrud.search(
                $scope.baseFmClass, {id : ids}, {},
                {atomic : true, authoritative : true}
            ).then(function(to_delete) {
                return egCore.pcrud.remove(to_delete);
            }).then(function() {
                $scope.gridControls.refresh();
            });
        });
    };
}])

