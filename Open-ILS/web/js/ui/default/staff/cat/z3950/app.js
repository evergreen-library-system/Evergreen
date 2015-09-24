/*
 * Z39.50 search and import
 */

angular.module('egCatZ3950Search',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod', 'egZ3950Mod', 'egMarcMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    // search page shows the list view by default
    $routeProvider.when('/cat/z3950/search', {
        templateUrl: './cat/z3950/t_list',
        controller: 'Z3950SearchCtrl',
        resolve : resolver
    });

    // default page / bucket view
    $routeProvider.otherwise({redirectTo : '/cat/z3950/search'});
})

/**
 * List view - grid stuff
 */
.controller('Z3950SearchCtrl',
       ['$scope','$q','$location','$timeout','$window','egCore','egGridDataProvider','egZ3950TargetSvc','$modal',
        'egConfirmDialog',
function($scope , $q , $location , $timeout , $window,  egCore , egGridDataProvider,  egZ3950TargetSvc,  $modal,
         egConfirmDialog) {

    // get list of targets
    egZ3950TargetSvc.loadTargets();
    egZ3950TargetSvc.loadActiveSearchFields();

    $scope.field_strip_groups = [];
    egCore.startup.go().then(function() {
        // and list of field strip groups; need to ensure
        // that enough of the startup has happened so that
        // we have the user WS
        egCore.pcrud.search('vibtg',
            {
                always_apply : 'f',
                owner : {
                    'in' : {
                        select : {
                            aou : [{
                                column : 'id',
                                transform : 'actor.org_unit_ancestors',
                                result_field : 'id'
                            }]
                        },
                        from : 'aou',
                        where : {
                            id : egCore.auth.user().ws_ou()
                        }
                    }
                }
            },
            { order_by : { vibtq : ['label'] } }
        ).then(null, null, function(strip_group) {
            strip_group.selected = false;
            $scope.field_strip_groups.push(strip_group);
        });
    });

    $scope.total_hits = 0;

    var provider = egGridDataProvider.instance({});

    provider.get = function(offset, count) {
        var deferred = $q.defer();

        var query = egZ3950TargetSvc.currentQuery();
        if (!query.raw_search && Object.keys(query.search).length == 0) {
            return $q.when();
        }

        var method = query.raw_search ?
                       'open-ils.search.z3950.search_service' :
                       'open-ils.search.z3950.search_class';

        if (query.raw_search) {
            query.query = query.raw_search;
            delete query['search'];
            delete query['raw_search'];
            query.service = query.service[0];
            query.username = query.username[0];
            query.password = query.password[0];
        }

        query['limit'] = count;
        query['offset'] = offset;

        var resultIndex = offset;
        $scope.total_hits = 0;
        $scope.searchInProgress = true;
        egCore.net.request(
            'open-ils.search',
            method,
            egCore.auth.token(),
            query
        ).then(
            function() { $scope.searchInProgress = false; deferred.resolve() },
            null, // onerror
            function(result) {
                // FIXME when the search offset is > 0, the
                // total hits count can be wrong if one of the
                // Z39.50 targets has fewer than $offset hits; in that
                // case, result.count is not supplied.
                $scope.total_hits += (result.count || 0);
                for (var i in result.records) {
                    result.records[i].mvr['service'] = result.service;
                    result.records[i].mvr['index'] = resultIndex++;
                    result.records[i].mvr['marcxml'] = result.records[i].marcxml;
                    deferred.notify(result.records[i].mvr);
                }
            }
        );

        return deferred.promise;
    };

    $scope.z3950SearchGridProvider = provider;
    $scope.gridControls = {};

    $scope.search = function() {
        $scope.z3950SearchGridProvider.refresh();
    };
    $scope.clearForm = function() {
        egZ3950TargetSvc.clearSearchFields();
    };

    $scope.saveDefaultZ3950Targets = function() {
        egZ3950TargetSvc.saveDefaultZ3950Targets();
    }

    var display_form = true;
    $scope.show_search_form = function() {
        return display_form;
    }
    $scope.toggle_search_form = function() {
        display_form = !display_form;
    }

    $scope.raw_search_impossible = function() {
        return egZ3950TargetSvc.rawSearchImpossible();
    }
    $scope.showRawSearchForm = function() {
        $modal.open({
            templateUrl: './cat/z3950/t_raw_search',
            size: 'md',
            controller:
                ['$scope', '$modalInstance', function($scope, $modalInstance) {
                egZ3950TargetSvc.setRawSearch('');
                $scope.focusMe = true;
                $scope.ok = function(args) { $modalInstance.close(args) }
                $scope.cancel = function () { $modalInstance.dismiss() }
            }]
        }).result.then(function (args) {
            if (!args || !args.raw_search) return;
            $scope.clearForm();
            egZ3950TargetSvc.setRawSearch(args.raw_search);
            $scope.z3950SearchGridProvider.refresh();
        });
    }

    $scope.showInCatalog = function() {
        var items = $scope.gridControls.selectedItems();
        // relying on cant_showInCatalog to protect us
        var url = egCore.env.basePath +
                  'cat/catalog/record/' + items[0].tcn();
        $timeout(function() { $window.open(url, '_blank') });        
    };
    $scope.cant_showInCatalog = function() {
        var items = $scope.gridControls.selectedItems();
        if (items.length != 1) return true;
        if (items[0]['service'] == 'native-evergreen-catalog') return false;
        return true;
    };

    $scope.local_overlay_target = egCore.hatch.getLocalItem('eg.cat.marked_overlay_record') || 0;
    $scope.mark_as_overlay_target = function() {
        var items = $scope.gridControls.selectedItems();
        if ($scope.local_overlay_target == items[0].tcn()) {
            $scope.local_overlay_target = 0;
        } else {
            $scope.local_overlay_target = items[0].tcn();
        }
        egCore.hatch.setLocalItem('eg.cat.marked_overlay_record',$scope.local_overlay_target);
    }
    $scope.cant_overlay = function() {
        if (!$scope.local_overlay_target) return true;
        var items = $scope.gridControls.selectedItems();
        if (items.length != 1) return true;
        if (
                items[0]['service'] == 'native-evergreen-catalog' &&
                items[0].tcn() == $scope.local_overlay_target
           ) return true;
        return false;
    }

    $scope.selectFieldStripGroups = function() {
        var groups = [];
        angular.forEach($scope.field_strip_groups, function(grp, idx) {
            if (grp.selected) {
                groups.push(grp.id());
            }
        });
        return groups;
    };
    $scope.import = function() {
        var deferred = $q.defer();
        var items = $scope.gridControls.selectedItems();
        egCore.net.request(
            'open-ils.cat',
            'open-ils.cat.biblio.record.xml.import',
            egCore.auth.token(),
            items[0]['marcxml'],
            null, // FIXME bib source
            null,
            null,
            $scope.selectFieldStripGroups()
        ).then(
            function() { deferred.resolve() },
            null, // onerror
            function(result) {
                egConfirmDialog.open(
                    egCore.strings.IMPORTED_RECORD_FROM_Z3950,
                    egCore.strings.IMPORTED_RECORD_FROM_Z3950_AS_ID,
                    { id : result.id() },
                    egCore.strings.GO_TO_RECORD,
                    egCore.strings.GO_BACK
                ).result.then(function() {
                    // NOTE: $location.path('/cat/catalog/record/' + result.id()) did not work
                    // for some reason
                    $window.location.href = egCore.env.basePath + 'cat/catalog/record/' + result.id();
                });
            }
        );

        return deferred.promise;
    };
    $scope.need_one_selected = function() {
        var items = $scope.gridControls.selectedItems();
        if (items.length == 1) return false;
        return true;
    };

    $scope.spawn_editor = function() {
        var items = $scope.gridControls.selectedItems();
        var recId = 0;
        $modal.open({
            templateUrl: './cat/z3950/t_marc_edit',
            size: 'lg',
            controller:
                ['$scope', '$modalInstance', function($scope, $modalInstance) {
                $scope.focusMe = true;
                $scope.record_id = recId;
                $scope.dirty_flag = false;
                $scope.marc_xml = items[0]['marcxml'];
                $scope.ok = function(args) { $modalInstance.close(args) }
                $scope.cancel = function () { $modalInstance.dismiss() }
                $scope.save_label = egCore.strings.IMPORT_BUTTON_LABEL;
                $scope.import_record_callback = function (record_id) {
                    recId = record_id;
                    $scope.save_label = egCore.strings.SAVE_BUTTON_LABEL;
                };
            }]
        }).result.then(function () {
            if (recId) {
                $window.location.href = egCore.env.basePath + 'cat/catalog/record/' + recId;
            }
        });
    }

    $scope.view_marc = function() {
        var items = $scope.gridControls.selectedItems();
        $modal.open({
            templateUrl: './cat/z3950/t_marc_html',
            size: 'lg',
            controller:
                ['$scope', '$modalInstance', function($scope, $modalInstance) {
                $scope.focusMe = true;
                $scope.marc_xml = items[0]['marcxml'];
                $scope.isbn = (items[0].isbn() || '').replace(/ .*/, '');
                $scope.ok = function(args) { $modalInstance.close(args) }
                $scope.cancel = function () { $modalInstance.dismiss() }
            }]
        }).result.then(function (args) {
            if (!args || !args.name) return;
        });
    }

    $scope.overlay_record = function() {
        var items = $scope.gridControls.selectedItems();
        var overlay_target = $scope.local_overlay_target;
        var args = {
            'marc_xml' : items[0]['marcxml']
        };
        $modal.open({
            templateUrl: './cat/z3950/t_overlay',
            size: 'lg',
            controller:
                ['$scope', '$modalInstance', function($scope, $modalInstance) {
                $scope.focusMe = true;
                $scope.overlay_target = overlay_target;
                $scope.args = args;
                $scope.ok = function(args) { $modalInstance.close(args) };
                $scope.cancel = function () { $modalInstance.dismiss() };
                $scope.editOverlayRecord = function() {
                    $modal.open({
                        templateUrl: './cat/z3950/t_edit_overlay_record',
                        size: 'lg',
                        controller:
                            ['$scope', '$modalInstance', function($scope, $modalInstance) {
                            $scope.focusMe = true;
                            $scope.record_id = 0;
                            $scope.dirty_flag = false;
                            $scope.args = args;
                            $scope.ok = function(args) { $modalInstance.close(args) }
                            $scope.cancel = function () { $modalInstance.dismiss() }
                        }]
                    }).result.then(function (args) {
                        if (!args || !args.name) return;
                    });
                };
            }]
        }).result.then(function (args) {
            egCore.net.request(
                'open-ils.cat',
                'open-ils.cat.biblio.record.marc.replace',
                egCore.auth.token(),
                overlay_target,
                args.marc_xml,
                null, // FIXME bib source
                null,
                $scope.selectFieldStripGroups()
            ).then(
                function(result) {
                    console.debug('overlay complete');
                }
            );            
        });
    }
}])
