/*
 * Z39.50 search and import
 */

angular.module('egCatZ3950Search',
    ['ngRoute', 'ui.bootstrap', 'ngOrderObjectBy', 'egCoreMod', 'egUiMod', 'egGridMod', 'egZ3950Mod', 'egMarcMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
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
       ['$scope','$q','$location','$timeout','$window','egCore','egGridDataProvider','egZ3950TargetSvc','$uibModal',
        'egConfirmDialog','egAlertDialog',
function($scope , $q , $location , $timeout , $window,  egCore , egGridDataProvider,  egZ3950TargetSvc,  $uibModal,
         egConfirmDialog, egAlertDialog) {

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

    var bib_sources = null;
    egCore.pcrud.retrieveAll('cbs', {}, {atomic : true})
        .then(function(l) { bib_sources = l; });

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

    $scope.get_bibsrc_name_from_id = function(bs_id){
        // var sel_bib_src = bib_src.id ? bib_src.list.filter(s => s.id() == bib_src.id) : null;
        // TODO can we use arrow syntax yet???
        if (!bs_id) return null;
        var cbs = bib_sources.filter(function(s){ return s.id() == bs_id });

        return (cbs && cbs[0] ? cbs[0].source() : null);
    };

    $scope.showRawSearchForm = function() {
        $uibModal.open({
            templateUrl: './cat/z3950/t_raw_search',
            backdrop: 'static',
            size: 'md',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                egZ3950TargetSvc.setRawSearch('');
                $scope.focusMe = true;
                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
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
        var url = '/eg2/staff/catalog/record/' + items[0].tcn();
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
        var items = $scope.gridControls.selectedItems();
        return $scope._import(items[0]['marcxml']);
    };

    $scope._import = function(marc_xml,bib_source) {

        var bibsrc_name = $scope.get_bibsrc_name_from_id(bib_source);

        var deferred = $q.defer();
        egCore.net.request(
            'open-ils.cat',
            'open-ils.cat.biblio.record.xml.import',
            egCore.auth.token(),
            marc_xml,
            bibsrc_name,
            null,
            null,
            $scope.selectFieldStripGroups()
        ).then(
            function(result) { deferred.resolve(result) },
            null, // onerror
            function(result) {
                var evt = egCore.evt.parse(result);
                if (evt) {
                     if (evt.textcode == 'TCN_EXISTS') {
                       egAlertDialog.open(
                            egCore.strings.TCN_EXISTS
                      );
                     } else {
                       // we shouldn't get here
                       egAlertDialog.open(egCore.strings.TCN_EXISTS_ERR);
                     }
                } else {
                    egConfirmDialog.open(
                        egCore.strings.IMPORTED_RECORD_FROM_Z3950,
                        egCore.strings.IMPORTED_RECORD_FROM_Z3950_AS_ID,
                        { id : result.id() },
                        egCore.strings.GO_TO_RECORD,
                        egCore.strings.GO_BACK
                    ).result.then(function() {
                        $window.open('/eg2/staff/catalog/record/' + result.id());
                    });
                }
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
        var _import = $scope._import;
        $uibModal.open({
            templateUrl: './cat/z3950/t_marc_edit',
            backdrop: 'static',
            size: 'lg',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.record_id = recId;
                $scope.dirty_flag = false;
                $scope.args = {};
                $scope.args.marc_xml = items[0]['marcxml'];
                $scope.args.bib_source = null;
                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
                $scope.save_label = egCore.strings.IMPORT_BUTTON_LABEL;
                // Wiring up angular inPlaceMode for editing later
                $scope.in_place_mode = true;
                $scope.import_record_callback = function () {
                    if($scope.in_place_mode) {
                        // This timeout is required to allow angular to finish variable assignments
                        // in the marcediter app. Allowing marc_xml to propigate here.
                        $timeout( function() {
                            _import($scope.args.marc_xml, $scope.args.bib_source).then( function(record_obj) {
                                if( record_obj.id ) {
                                    $scope.record_id = record_obj.id();
                                    $scope.save_label = egCore.strings.SAVE_BUTTON_LABEL;
                                    // Successful import, no longer want this special z39.50 callback to execute.
                                    $scope.in_place_mode = undefined;
                                }
                            });
                        });
                    }
                };
            }]
        }).result.then(function () {
            if (recId) {
                $window.location.href = '/eg2/staff/catalog/record/' + recId;
            }
        });
    }

    $scope.view_marc = function() {
        var items = $scope.gridControls.selectedItems();
        $uibModal.open({
            templateUrl: './cat/z3950/t_marc_html',
            backdrop: 'static',
            size: 'lg',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.marc_xml = items[0]['marcxml'];
                $scope.isbn = (items[0].isbn() || '').replace(/ .*/, '');
                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        }).result.then(function (args) {
            if (!args || !args.name) return;
        });
    }

    $scope.overlay_record = function() {
        var items = $scope.gridControls.selectedItems();
        var overlay_target = $scope.local_overlay_target;
        var live_overlay_target = egCore.hatch.getLocalItem('eg.cat.marked_overlay_record') || 0;
        var args = {
            'marc_xml' : items[0]['marcxml'],
            'bib_source' : null
        };

        $uibModal.open({
            templateUrl: './cat/z3950/t_overlay',
            backdrop: 'static',
            size: 'lg',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {

                $scope.immediate_merge = function () {
                    $scope.overlay_target.marc_xml = args.marc_xml;
                    egCore.pcrud.retrieve('bre', $scope.overlay_target.id)
                    .then(function(rec) {
                        $scope.overlay_target.orig_marc_xml = rec.marc();
                        $scope.merge_marc(); // in case a sticky value was already set
                    });
                }

                $scope.merge_marc = function() {
                    if (!$scope.merge_profile) return;
                    egCore.net.request(
                        'open-ils.cat',
                        'open-ils.cat.merge.marc.per_profile',
                        egCore.auth.token(),
                        $scope.merge_profile,
                        [ args.marc_xml, $scope.overlay_target.orig_marc_xml ]
                    ).then(function(merged) {
                        if (merged) {
                            $scope.overlay_target.marc_xml = merged;
                            $scope.overlay_target.merged = true;
                        }
                    });
                }

                $scope.editOverlayRecord = function() {
                    $uibModal.open({
                        templateUrl: './cat/z3950/t_edit_overlay_record',
                        backdrop: 'static',
                        size: 'lg',
                        controller:
                            ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                            $scope.focusMe = true;
                            $scope.record_id = 0;
                            $scope.dirty_flag = false;
                            $scope.args = args;
                            $scope.ok = function() { $uibModalInstance.close($scope.args) }
                            $scope.cancel = function () { $uibModalInstance.dismiss() }
                        }]
                    }).result.then(function (args) {
                        $scope.merge_marc();
                        if (!args || !args.name) return;
                    });
                };

                $scope.focusMe = true;
                $scope.merge_profile = null;
                $scope.overlay_target = {
                    id : overlay_target,
                    live_id : live_overlay_target,
                    merged : false
                };

                $scope.$watch('merge_profile', function(newVal, oldVal) {
                    if (newVal && newVal !== oldVal) {
                        $scope.merge_marc();
                    }
                });

                $scope.args = args;
                args.overlay_target = $scope.overlay_target;
                $scope.ok = function(args) { $uibModalInstance.close(args) };
                $scope.cancel = function () { $uibModalInstance.dismiss() };
                
                if (overlay_target != live_overlay_target) {
                    var confirm_title = egCore.strings.OVERLAY_CHANGED_TITLE;
                    var confirm_msg = egCore.strings.OVERLAY_CHANGED;

                    if (live_overlay_target == 0) { // someone unset the target...
                        confirm_title = egCore.strings.OVERLAY_REMOVED_TITLE;
                        confirm_msg = egCore.strings.OVERLAY_REMOVED;
                    }

                    egConfirmDialog.open(
                        confirm_title,
                        confirm_msg,
                        { id : overlay_target, live_id : live_overlay_target }
                    ).result.then(
                        function () { // proceed -- but check live overlay for unset-ness
                            if (live_overlay_target != 0) {
                                $scope.overlay_target.id = $scope.overlay_target.live_id;
                                overlay_target = live_overlay_target;
                            }
                            $scope.immediate_merge();
                        },
                        function () {
                            $scope.cancel();
                        }
                    );
                } else {
                    $scope.immediate_merge();
                }

            }]
        }).result.then(function (args) {
            var bibsrc_name = $scope.get_bibsrc_name_from_id(args.bib_source);
            egCore.net.request(
                'open-ils.cat',
                'open-ils.cat.biblio.record.marc.replace',
                egCore.auth.token(),
                overlay_target,
                (args.overlay_target.merged ? args.overlay_target.marc_xml : args.marc_xml),
                bibsrc_name,
                null,
                $scope.selectFieldStripGroups()
            ).then(
                function(result) {
                    $scope.local_overlay_target = 0;
                    egCore.hatch.removeLocalItem('eg.cat.marked_overlay_record');
                    console.debug('overlay complete, target removed');
                    $window.open('/eg2/staff/catalog/record/' + overlay_target);
                }
            );            
        });
    }
}])
