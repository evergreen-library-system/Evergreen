angular.module('egZ3950Mod', ['egCoreMod', 'ui.bootstrap'])
.factory('egZ3950TargetSvc',
       ['$q', 'egCore', 'egAuth',
function($q,   egCore,   egAuth) {
    
    var service = {
        targets : [ ],
        searchFields : { },
        raw_search : ''
    };
    
    service.loadTargets = function() {
        var default_targets = egCore.hatch.getLocalItem('eg.cat.z3950.default_targets') || [];
        egCore.net.request(
            'open-ils.search',
            'open-ils.search.z3950.retrieve_services',
            egAuth.token()
        ).then(function(res) {
            // keep the reference, just clear the list
            service.targets.length = 0;
            // native Evergreen search goes first
            var localTarget = res['native-evergreen-catalog'];
            delete res['native-evergreen-catalog'];
            angular.forEach(res, function(value, key) {
                var tgt = {
                    code:       key,
                    settings:   value,
                    selected:   (key in default_targets),
                    username:   '',
                    password:   ''
                };
                if (tgt.code in default_targets && tgt.settings.auth == 't') {
                    tgt['username'] = default_targets[tgt.code]['username'] || '';
                    tgt['password'] = default_targets[tgt.code]['password'] || '';
                }
                this.push(tgt);
            }, service.targets);
            service.targets.sort(function (a, b) {
                a = a.settings.label.toLowerCase();
                b = b.settings.label.toLowerCase();
                return a < b ? -1 : (a > b ? 1 : 0);
            }); 
            service.targets.unshift({
                code:       'native-evergreen-catalog',
                settings:   localTarget,
                selected:   ('native-evergreen-catalog' in default_targets),
                username:   '',
                password:   ''
            });
        });
    };

    service.loadActiveSearchFields = function() {
        // don't want to throw away the reference, otherwise
        // directives bound to searchFields won't
        // refresh
        var curFormInput = {};
        for (var field in service.searchFields) {
            curFormInput[field] = service.searchFields[field].query;
            delete service.searchFields[field];
        }
        angular.forEach(service.targets, function(target, idx) {
            if (target.selected) {
                angular.forEach(target.settings.attrs, function(attr, key) {
                    if (!(key in service.searchFields)) service.searchFields[key] = {
                        label : attr.label,
                        query : (key in curFormInput) ? curFormInput[key] : ''
                    };
                });
            }
        });
    };

    service.clearSearchFields = function() {
        for (var field in service.searchFields) {
            service.searchFields[field].query = '';
        }
    }

    // return the selected Z39.50 targets and search strings
    // in a format suitable for passing directly to
    // open-ils.search.z3950.search_class
    service.currentQuery = function() {
        var query = {
            service  : [],
            username : [],
            password : [],
            search   : {}
        };

        angular.forEach(service.targets, function(target, idx) {
            if (target.selected) {
                query.service.push(target.code);
                query.username.push(target.username);
                query.password.push(target.password);
            }
        });
        if (service.raw_search) {
            query.raw_search = service.raw_search;
        } else {
            angular.forEach(service.searchFields, function(value, key) {
                if (value.query && value.query.trim()) {
                    query.search[key] = value.query.trim();
                }
            });
        }
        return query;
    }

    // raw search can be done only if exactly one
    // (real) Z39.50 target is selected
    service.rawSearchImpossible = function() {
        var z_selected = 0;
        for (var i in service.targets) {
            if (service.targets[i].code == 'native-evergreen-catalog') {
                if (service.targets[i].selected) return true;
            } else {
                if (service.targets[i].selected) z_selected++;
            }
        }
        return !(z_selected == 1);
    }

    service.setRawSearch = function(raw_search) {
        service.raw_search = raw_search;
    }

    // store selected targets
    service.saveDefaultZ3950Targets = function() {
        var saved_targets = {};
        angular.forEach(service.targets, function(target, idx) {
            if (target.selected) {
                saved_targets[target.code] = {};
                if (target.settings.auth == 't') {
                    saved_targets[target.code]['username'] = target.username;
                    saved_targets[target.code]['password'] = target.password;
                }
            }
        }); 
        egCore.hatch.setLocalItem('eg.cat.z3950.default_targets', saved_targets);
    }

    // store default field
    service.saveDefaultField = function(default_field) {
        console.log('saveDefaultField',default_field);
        egCore.hatch.setLocalItem('eg.cat.z3950.default_field', default_field);
    }

    service.fetchDefaultField = function() {
        var default_field = egCore.hatch.getLocalItem('eg.cat.z3950.default_field') || 'isbn';
        console.log('fetchDefaultField',default_field);
        return default_field;
    }

    return service;
}])
.directive("egZ3950TargetList", function () {
    return {
        transclude: true,
        restrict:   'AE',
        scope: {
            
        },
        templateUrl: './cat/z3950/t_target',
        controller:
                   ['$scope','egZ3950TargetSvc',
            function($scope , egZ3950TargetSvc) {
                $scope.targets = egZ3950TargetSvc.targets;
                $scope.$watch('targets', function(oldVal, newVal) {
                    egZ3950TargetSvc.loadActiveSearchFields();
                }, true);
            }]
    }
})
.directive("egZ3950SearchFieldList", ['egZ3950TargetSvc',
    function(egZ3950TargetSvc) {
        return {
            restrict:   'AE',
            scope: {
            },
            templateUrl: './cat/z3950/t_search_fields',
            link: function(scope, elem, attr) {
                scope.fields = egZ3950TargetSvc.searchFields;
                scope.default_field = egZ3950TargetSvc.fetchDefaultField();
                scope.infocus = {};
                scope.infocus[scope.default_field] = true;
                scope.save = function(v) {
                    egZ3950TargetSvc.saveDefaultField(v);
                    scope.default_field = v;
                    angular.forEach(scope.infocus, function (v,k,o) { o[k]=false });
                    scope.infocus[scope.default_field] = true;
                }
            }
        };
    }
]);
