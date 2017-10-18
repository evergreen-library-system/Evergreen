angular.module('egAdminRating',
    ['ngRoute','ui.bootstrap','egCoreMod','egUiMod','egGridMod'])

.controller('Badges',
       ['$scope','$q','$timeout','$location','$window','$uibModal',
        'egCore','egGridDataProvider','egConfirmDialog',
function($scope , $q , $timeout , $location , $window , $uibModal ,
         egCore , egGridDataProvider , egConfirmDialog) {

    egCore.startup.go();

    function get_record_label() {
        return egCore.idl.classes['rb'].label;
    }

    function flatten_linked_values(cls, list) {
        var results = [];
        var fields = egCore.idl.classes[cls].fields;
        var id_field;
        var selector;
        angular.forEach(fields, function(fld) {
            if (fld.datatype == 'id') {
                id_field = fld.name;
                selector = fld.selector ? fld.selector : id_field;
                return;
            }
        });
        angular.forEach(list, function(item) {
            var rec = egCore.idl.toHash(item);
            results.push({
                id : rec[id_field],
                name : rec[selector]
            });
        });
        return results;
    }

    horizon_required = {};
    percentile_required = {};
    function get_popularity_with_required() {
        egCore.pcrud.retrieveAll(
            'rp', {}, {atomic : true}
        ).then(function(list) {
            angular.forEach(list, function(item) {
                horizon_required[item.id()] = item.require_horizon();
                percentile_required[item.id()] = item.require_percentile();
            });
        });
    }

    function get_field_list(rec) {
        var fields = egCore.idl.classes['rb'].fields;

        var promises = [];
        // flesh selectors
        angular.forEach(fields, function(fld) {
            if (fld.datatype == 'link') {
                egCore.pcrud.retrieveAll(
                    fld.class, {}, {atomic : true}
                ).then(function(list) {
                    fld.linked_values = flatten_linked_values(fld.class, list);
                });
            }
            if (fld.datatype == 'org_unit') {
                rec[fld.name + '_ou'] = {};
                rec[fld.name + '_ou']['org'] = egCore.org.get(rec[fld.name]);
                rec[fld.name + '_ou']['update_org'] = function(org) {
                    rec[fld.name] = org.id();
                };
            }
            if (fld.name == 'last_calc') {
                fld['readonly'] = true;
            }
            fld.is_required = function(record) {
                return false;
            };
            if (fld.name == 'name') {
                fld.is_required = function(record) {
                    return true;
                };
            }
            if (fld.name == 'horizon_age') {
                fld.is_required = function(record) {
                    return horizon_required[record['popularity_parameter']] == 't';
                };
            }
            if (fld.name == 'percentile') {
                fld.is_required = function(record) {
                    return percentile_required[record['popularity_parameter']] == 't';
                };
            }
        });
        return fields;
    }

    function spawn_editor(rb, action) {
        var deferred = $q.defer();
        $uibModal.open({
            templateUrl: './admin/local/rating/edit_badge',
            backdrop: 'static',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.record = egCore.idl.toHash(rb);
                // non-integer numeric field require parseFloat
                $scope.record.percentile = parseFloat($scope.record.percentile);
                $scope.record_label = get_record_label();
                $scope.fields = get_field_list($scope.record);
                get_popularity_with_required();
                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        }).result.then(function(args) {
            var rb = new egCore.idl.rb();
            if (action == 'update') rb.id(args.id);
            rb.name(args.name);
            rb.description(args.description);
            rb.scope(args.scope);
            rb.weight(args.weight);
            rb.horizon_age(args.horizon_age);
            rb.importance_age(args.importance_age);
            rb.importance_interval(args.importance_interval);
            rb.importance_scale(args.importance_scale);
            rb.recalc_interval(args.recalc_interval);
            rb.attr_filter(args.attr_filter);
            rb.src_filter(args.src_filter);
            rb.circ_mod_filter(args.circ_mod_filter);
            rb.loc_grp_filter(args.loc_grp_filter);
            rb.popularity_parameter(args.popularity_parameter);
            rb.fixed_rating(args.fixed_rating);
            rb.percentile(args.percentile);
            rb.discard(args.discard);
            rb.last_calc(args.last_calc);
            if (action == 'create') {
                egCore.pcrud.create(rb).then(function() { deferred.resolve(); });
            } else {
                egCore.pcrud.update(rb).then(function() { deferred.resolve(); });
            }
        });
        return deferred.promise;
    }

    $scope.create_rb = function() {
        var rb = new egCore.idl.rb();

        // make sure an OU is selected by default
        rb.scope(egCore.auth.user().ws_ou());

        spawn_editor(rb, 'create').then(function() {
            $scope.gridControls.refresh();
        });
    }

    $scope.update_rb = function(selected) {
        if (!selected || !selected.length) return;

        egCore.pcrud.retrieve('rb', selected[0].id).then(function(rb) {
            spawn_editor(rb, 'update').then(function() {
                $scope.gridControls.refresh();
            });
        });
    }

    $scope.delete_rb = function(selected) {
        if (!selected || !selected.length) return;

        egCore.pcrud.retrieve('rb', selected[0].id).then(function(rb) {
            egConfirmDialog.open(
                egCore.strings.CONFIRM_DELETE_BADGE_TITLE,
                egCore.strings.CONFIRM_DELETE_BADGE_BODY,
                { name : rb.name(), id : rb.id() }
            ).result.then(function() {
                egCore.pcrud.remove(rb).then(function() {
                    $scope.gridControls.refresh();
                });
            });            
        });
    }

    $scope.gridControls = {
        activateItem : function (item) {
            $scope.update_rb([item]);
        },
        setQuery : function() {
            return {
                'id' : {'!=' : null}
            }
        }
    }
}])
