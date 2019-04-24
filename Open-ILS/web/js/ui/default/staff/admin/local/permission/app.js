angular.module('egAdminPermGrpTreeApp',
    ['ngRoute','ui.bootstrap','egCoreMod','egUiMod','treeControl'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/);

    var resolver = {delay :
        ['egStartup', function(egStartup) {return egStartup.go()}]}

    $routeProvider.when('/admin/local/permission/grp_tree_display_entry', {
        templateUrl : './admin/local/permission/t_grp_tree_display_entry',
        controller : 'PermGrpTreeCtrl',
        resolve : resolver
    });

    // catch admin/local/permission/grp_penalty_threshold
    var eframe_template = 
        '<eg-embed-frame allow-escape="true" min-height="min_height" url="local_admin_url" handlers="funcs"></eg-embed-frame>';
    $routeProvider.when('/admin/local/:schema/:page', {
        template: eframe_template,
        controller: 'EmbedConifyCtl',
        resolve : resolver
    });

    $routeProvider.otherwise({redirectTo : '/admin/local/permission/grp_tree'});
})

.factory('egPermGrpTreeSvc',
        ['$q','egCore', function($q , egCore) {
    var service = {
        pgtde_array: [],
        display_entries: [],
        disabled_entries: [],
        profiles: [],
        edit_profiles: []
    };

    // determine which user groups our user is not allowed to modify
    service.set_edit_profiles = function() {
        var all_app_perms = [];
        var failed_perms = [];

        // extract the application permissions
        angular.forEach(service.profiles, function(grp) {
            if (grp.application_perm())
                all_app_perms.push(grp.application_perm());
        }); 

        // fill in service.edit_profiles by inspecting failed_perms
        function traverse_grp_tree(grp, failed) {
            failed = failed || 
                failed_perms.indexOf(grp.application_perm()) > -1;

            if (!failed) service.edit_profiles.push(grp);

            angular.forEach(
                service.profiles.filter( // children of grp
                    function(p) { return p.parent() == grp.id() }),
                function(child) {traverse_grp_tree(child, failed)}
            );
        }

        return egCore.perm.hasPermAt(all_app_perms, true).then(
            function(perm_orgs) {
                angular.forEach(all_app_perms, function(p) {
                    if (perm_orgs[p].length == 0)
                        failed_perms.push(p);
                });

                traverse_grp_tree(egCore.env.pgt.tree);
            }
        );
    }

    service.get_perm_groups = function() {
        if (egCore.env.pgt) {
            service.profiles = egCore.env.pgt.list;
            return service.set_edit_profiles();
        } else {
            return egCore.pcrud.search('pgt', {parent : null}, 
                {flesh : -1, flesh_fields : {pgt : ['children']}}
            ).then(
                function(tree) {
                    egCore.env.absorbTree(tree, 'pgt')
                    service.profiles = egCore.env.pgt.list;
                    return service.set_edit_profiles();
                }
            );
        }
    }

    service.fetchDisplayEntries = function(ou_id) {
        service.edit_profiles = [];
        service.get_perm_groups();
        return egCore.pcrud.search('pgtde',
            {org : egCore.org.ancestors(ou_id, true)},
            { flesh : 1,
              flesh_fields : {
                  pgtde: ['grp', 'org']
              },
              order_by: {pgtde : 'id'}
            },
            {atomic: true}
        ).then(function(entries) {
            service.pgtde_array = [];
            service.disabled_entries = [];
            angular.forEach(entries, function(entry) {
                service.pgtde_array.push(entry);
            });
        });
    }

    service.organizeDisplayEntries = function(selectedOrg) {
        service.display_entries = [];

        angular.forEach(service.pgtde_array, function(pgtde) {
            if (pgtde.org().id() == selectedOrg) {
                if (!pgtde.child_entries) pgtde.child_entries = [];
                var isChild = false;
                angular.forEach(service.display_entries, function(entry) {
                    if (pgtde.parent() && pgtde.parent() == entry.id()) {
                        entry.child_entries.push(pgtde);
                        isChild = true;
                        return;
                    } else {
                        if (service.iterateChildEntries(pgtde, entry)) {
                            isChild = true;
                            return;
                        }
                    }
                });
                if (!pgtde.parent() || !isChild) {
                    service.display_entries.push(pgtde);
                }
            }
        });
    }

    service.iterateChildEntries = function(pgtde, entry) {
        if (entry.child_entries.length) {
            return angular.forEach(entry.child_entries, function(child) {
                if (pgtde.parent() == child.id()) {
                    child.child_entries.push(pgtde);
                    return true;
                } else {
                    return service.iterateChildEntries(pgtde, child);
                }
            });
        }
    }

    service.updateDisplayEntries = function(tree, ou_id) {
        return egCore.pcrud.search('pgtde',
            {org : ou_id},
            { flesh : 1,
              flesh_fields : {
                  pgtde: ['grp', 'org']
              },
              order_by: {pgtde : 'id'}
            },
            {atomic: true}
        ).then(function(entries) {
            return egCore.pcrud.update(tree).then(function(res) {
                return res;
            });
        });
    }

    service.removeDisplayEntries = function(entries) {
        return egCore.pcrud.remove(entries).then(function(res) {
            return res;
        });
    }

    service.addDisplayEntries = function(entries) {
        return egCore.pcrud.create(entries).then(function(res) {
            return res;
        });
    }

    service.findEntry = function(id, entries) {
        var match;
        angular.forEach(entries, function(entry) {
            if (!match) {
                if (!entry.child_entries) entry.child_entries = [];
                if (id == entry.id()) {
                    match = entry;
                } else if (entry.child_entries.length) {
                    match = service.findEntry(id, entry.child_entries);
                }
            }
        });

        return match;
    }

    return service;
}])

.controller('PermGrpTreeCtrl',
    ['$scope','$q','$timeout','$location','$uibModal','egCore','egPermGrpTreeSvc', 'ngToast', 'egProgressDialog',
function($scope , $q , $timeout , $location , $uibModal , egCore , egPermGrpTreeSvc, ngToast, egProgressDialog) {
    $scope.perm_tree = [{
        grp: function() {
            return {
                name: function() {return egCore.strings.ROOT_NODE_NAME;}
            }
        },
        child_entries: [],
        permanent: 'true'
    }];
    $scope.display_entries = [];
    $scope.new_entries = [];
    $scope.tree_options = {nodeChildren: 'child_entries'};
    $scope.selected_entry;
    $scope.expanded_nodes = [];
    $scope.orderby = ['position()','grp().name()'];

    if (!$scope.selectedOrg)
        $scope.selectedOrg = egCore.org.get(egCore.auth.user().ws_ou());

    $scope.updateSelection = function(node, selected) {
        $scope.selected_entry = node;
        if (!selected) $scope.selected_entry = null;
    }

    $scope.setPosition = function(node, direction) {
        var newPos = node.position();
        var siblings;
        if (node.parent()) {
            siblings = egPermGrpTreeSvc.findEntry(node.parent(), $scope.perm_tree[0].child_entries).child_entries;
        } else {
            siblings = $scope.perm_tree[0].child_entries;
        }
        if (direction == 'up' && newPos < siblings.length) newPos++;
        if (direction == 'down' && newPos > 1) newPos--;

        angular.forEach(siblings, function(entry) {
            if (entry.position() == newPos) entry.position(node.position());
            angular.forEach($scope.display_entries, function(display_entry) {
                if (display_entry.id() == entry.id()) {
                    if (display_entry.position() == newPos) {
                        display_entry.position(node.position);
                    };
                }
            });
        });

        angular.forEach($scope.display_entries, function(display_entry) {
            if (display_entry.id() == node.id()) {
                display_entry.position(newPos);
            }
        });

        node.position(newPos);
    }

    $scope.addChildEntry = function(node) {

        $scope.openAddDialog(node, $scope.disabled_entries, $scope.edit_profiles, $scope.display_entries, $scope.selectedOrg)
        .then(function(res) {
            if (res) {

                var siblings = []
                var new_entry = new egCore.idl.pgtde();
                new_entry.org($scope.selectedOrg.id());
                new_entry.grp(res.selected_grp);
                new_entry.position(1);
                new_entry.child_entries = [];
                var is_expanded;
                if (res.selected_parent) {
                    new_entry.parent(res.selected_parent);
                    angular.forEach($scope.expanded_nodes, function(expanded_node) {
                        if (expanded_node == res.selected_parent) is_expanded = true;
                    });
                    if (!is_expanded) $scope.expanded_nodes.push(res.selected_parent);
                } else {
                    angular.forEach($scope.expanded_nodes, function(expanded_node) {
                        if (expanded_node == $scope.perm_tree[0]) is_expanded = true;
                    });
                    if (!is_expanded) $scope.expanded_nodes.push($scope.perm_tree[0]);
                }

                $scope.display_entries.push(new_entry);
                egPermGrpTreeSvc.addDisplayEntries([new_entry]).then(function(addRes) {
                    if (addRes) {
                        if (res.is_root || !res.selected_parent) {
                            angular.forEach($scope.perm_tree[0].child_entries, function(entry) {
                                var newPos = entry.position();
                                newPos++;
                                entry.position(newPos);
                                siblings.push(entry);
                            });
                        } else {
                            var parent = egPermGrpTreeSvc.findEntry(res.selected_parent.id(), $scope.perm_tree[0].child_entries);
                            angular.forEach(parent.child_entries, function(entry) {
                                var newPos = entry.position();
                                newPos++;
                                entry.position(newPos);
                                siblings.push(entry);
                            });
                        }

                        egPermGrpTreeSvc.updateDisplayEntries(siblings).then(function(updateRes) {
                            ngToast.create(egCore.strings.ADD_SUCCESS);
                            $scope.refreshTree($scope.selectedOrg, $scope.selected_entry);
                        });
                    } else {
                        ngToast.create(egCore.strings.ADD_FAILURE);
                    }
                });
            }
        });
    }

    $scope.openAddDialog = function(node, disabled_entries, edit_profiles, display_entries, selected_org) {

        return $uibModal.open({
            templateUrl : './admin/local/permission/t_pgtde_add_dialog',
            backdrop: 'static',
            controller : [
                        '$scope','$uibModalInstance',
                function($scope , $uibModalInstance) {
                    var getIsRoot = function() {
                        if (!node || node.permanent) return true;
                        return false;
                    }

                    var getSelectedParent = function() {
                        if (!node || node.permanent) return $scope.perm_tree;
                        return node;
                    }

                    var available_profiles = [];
                    angular.forEach(edit_profiles, function(grp) {
                        grp._filter_grp = false;
                        angular.forEach(display_entries, function(entry) {
                            if (entry.org().id() == selected_org.id()) {
                                if (entry.grp().id() == grp.id()) grp._filter_grp = true;
                            }
                        });
                        if (!grp._filter_grp) available_profiles.push(grp);
                    });

                    $scope.context = {
                        is_root : getIsRoot(),
                        selected_parent : getSelectedParent(),
                        edit_profiles : available_profiles,
                        display_entries : display_entries,
                        selected_org : selected_org
                    }

                    $scope.context.selected_grp = $scope.context.edit_profiles[0];

                    $scope.ok = function() {
                        $uibModalInstance.close($scope.context);
                    }

                    $scope.cancel = function() {
                        $uibModalInstance.dismiss();
                    }
                }
            ]
        }).result;
    }

    var iteratePermTree = function(arr1, arr2) {
        angular.forEach(arr1, function(entry) {
            arr2.push(entry);
            if (entry.child_entries) iteratePermTree(entry.child_entries, arr2);
        });
    }

    $scope.removeEntry = function(node) {
        $scope.disabled_entries.push(node);
        iteratePermTree(node.child_entries, $scope.disabled_entries);

        var siblings;
        if (node.parent()) {
            siblings = egPermGrpTreeSvc.findEntry(node.parent(), $scope.perm_tree[0].child_entries).child_entries;
        } else {
            siblings = $scope.perm_tree[0].child_entries;
        }
        angular.forEach(siblings, function(sibling) {
            var newPos = sibling.position();
            if (node.position() < sibling.position()) {
                newPos--;
            }
            sibling.position(newPos);
        });

        $scope.selected_entry = null;

        egPermGrpTreeSvc.removeDisplayEntries($scope.disabled_entries).then(function(res) {
            if (res) {
                ngToast.create(egCore.strings.REMOVE_SUCCESS);
                $scope.refreshTree($scope.selectedOrg);
            } else {
                ngToast.create(egCore.strings.REMOVE_FAILURE);
            }
        })
    }

    var getDisplayEntries = function() {
        $scope.edit_profiles = egPermGrpTreeSvc.edit_profiles;
        egPermGrpTreeSvc.organizeDisplayEntries($scope.selectedOrg.id());
        $scope.perm_tree[0].child_entries = egPermGrpTreeSvc.display_entries;
        $scope.display_entries = egPermGrpTreeSvc.pgtde_array;
        $scope.new_entries = [];
        $scope.disabled_entries = [];
        $scope.selected_entry = $scope.perm_tree[0];
        if (!$scope.expanded_nodes.length) iteratePermTree($scope.perm_tree, $scope.expanded_nodes);
    }

    $scope.saveEntries = function() {
        egProgressDialog.open();

        // Save Remaining Display Entries
        egPermGrpTreeSvc.updateDisplayEntries($scope.display_entries, $scope.selectedOrg.id())
        .then(function(res) {
            if (res) {
                ngToast.create(egCore.strings.UPDATE_SUCCESS);
                $scope.refreshTree($scope.selectedOrg, $scope.selected_entry);
            } else {
                ngToast.create(egCore.strings.UPDATE_FAILURE);
            }
        }).finally(egProgressDialog.close);
    }

    $scope.org_changed = function(org) {
        $scope.refreshTree(org.id());
    }

    $scope.refreshTree = function(ou_id, node) {
        egPermGrpTreeSvc.fetchDisplayEntries(ou_id).then(function() {
            getDisplayEntries();
            if (node) $scope.selected_entry = node;
        });
    }

    egCore.startup.go(function() {
        $scope.refreshTree(egCore.auth.user().ws_ou());
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
