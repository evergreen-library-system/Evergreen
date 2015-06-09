angular.module('egZ3950Mod', ['egCoreMod', 'ui.bootstrap'])
.factory('egZ3950TargetSvc',
       ['$q', 'egCore', 'egAuth',
function($q,   egCore,   egAuth) {
    
    var service = {
        targets : [ ],
        searchFields : { }
    };
    
    service.loadTargets = function() {
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
                this.push({
                    code:       key,
                    settings:   value,
                    selected:   false,
                    username:   '',
                    password:   ''
                });
            }, service.targets);
            service.targets.sort(function (a, b) {
                a = a.settings.label;
                b = b.settings.label;
                return a < b ? -1 : (a > b ? 1 : 0);
            }); 
            service.targets.unshift({
                code:       'native-evergreen-catalog',
                settings:   localTarget,
                selected:   false,
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
        angular.forEach(service.searchFields, function(value, key) {
            if (value.query && value.query.trim()) {
                query.search[key] = value.query.trim();
            }
        });

        return query;
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
            }
        };
    }
]);
