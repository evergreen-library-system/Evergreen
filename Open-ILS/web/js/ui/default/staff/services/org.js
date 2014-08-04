/**
 * Core Service - egOrg
 *
 * TODO: more docs
 */
angular.module('egCoreMod')

.factory('egOrg', 
       ['$q','egEnv','egAuth','egNet',
function($q,  egEnv,  egAuth,  egNet) { 

    var service = {};

    // org unit settings cache.
    // This allows the caller to avoid local caches
    service.cachedSettings = {};

    service.get = function(node_or_id) {
        if (typeof node_or_id == 'object')
            return node_or_id;
        return egEnv.aou.map[node_or_id];
    };

    service.list = function() {
        return egEnv.aou.list;
    };

    service.tree = function() {
        return egEnv.aou.tree;
    }

    // list of org_unit objects or IDs for ancestors + me
    service.ancestors = function(node_or_id, as_id) {
        var node = service.get(node_or_id);
        if (!node) return [];
        var nodes = [node];
        while( (node = service.get(node.parent_ou())))
            nodes.push(node);
        if (as_id) 
            return nodes.map(function(n){return n.id()});
        return nodes;
    };

    // list of org_unit objects  or IDs for me + descendants
    service.descendants = function(node_or_id, as_id) {
        var node = service.get(node_or_id);
        if (!node) return [];
        var nodes = [];
        function descend(n) {
            nodes.push(n);
            angular.forEach(n.children(), descend);
        }
        descend(node);
        if (as_id) 
            return nodes.map(function(n){return n.id()});
        return nodes;
    }

    // list of org_unit objects or IDs for ancestors + me + descendants
    service.fullPath = function(node_or_id, as_id) {
        var list = service.ancestors(node_or_id).concat(
          service.descendants(node_or_id).slice(1));
        if (as_id) 
            return list.map(function(n){return n.id()});
        return list;
    }

    // returns a promise, resolved with a hash of setting name =>
    // setting value for the selected org unit.  Org unit defaults to 
    // auth workstation org unit.
    service.settings = function(names, ou_id) {
        var deferred = $q.defer();
        ou_id = ou_id || egAuth.user().ws_ou();
        var here = (ou_id == egAuth.user().ws_ou());

        // allow non-array
        if (!angular.isArray(names)) names = [names];
        
        if (here) { 
            // only cache org settings retrieved for the current 
            // workstation org unit.
            var newNames = [];
            angular.forEach(names, function(name) {
                if (!angular.isDefined(service.cachedSettings[name]))
                    newNames.push(name)
            });

            // only retrieve uncached values
            names = newNames;
            if (names.length == 0)
                return $q.when(service.cachedSettings);
        }

        egNet.request(
            'open-ils.actor',
            'open-ils.actor.ou_setting.ancestor_default.batch',
            ou_id, names, egAuth.token()
        ).then(function(blob) {
            var settings = {};
            angular.forEach(blob, function(val, key) {
                // val is either null or a structure containing the value
                settings[key] = val ? val.value : null;
                if (here) service.cachedSettings[key] = settings[key];
            });

            // resolve with cached settings if 'here', since 'settings'
            // will only contain settings we had to retrieve
            deferred.resolve(here ? service.cachedSettings : settings);
        });
        return deferred.promise;
    }

    return service;
}]);
 
