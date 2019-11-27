/**
 * Core Service - egOrg
 *
 * This provides access to the organizational unit tree and
 * caches it in browser session storage.
 *
 * Methods include:
 *   get()  - retrieve OU based on ID or aou object
 *   list() - retrieve flattened list of OUs
 *   tree() - retrieve OU as tree
 *   root() - get aou object representing root of the OU tree
 *   ancestors() - get ancestors of supplied OU
 *   descendants() - get descendants of supplied OU
 * 
 * TODO more to document
 * 
 */
angular.module('egCoreMod')

.factory('egOrg', 
       ['$q','egEnv','egAuth','egNet','$injector',
function($q,  egEnv,  egAuth,  egNet , $injector) { 

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

    // get the root OU
    service.root = function() {
        return egEnv.aou.list[0];
    }

    // list of org_unit objects or IDs for ancestors + me
    service.ancestors = function(node_or_id, as_id) {
        var node = service.get(node_or_id);
        if (!node) return [];
        var nodes = [node];
        while( (node = service.get(node.parent_ou())))
            nodes.push(node);
        if (as_id) 
            return nodes.map(function(n){return Number(n.id())});
        return nodes;
    };

    // tests that a node can have users
    service.CanHaveUsers = function(node_or_id) {
	return service
            .get(node_or_id)
            .ou_type()
            .can_have_users() == 't';
    }

    // tests that a node can have volumes
    service.CanHaveVolumes = function(node_or_id) {
        return service
            .get(node_or_id)
            .ou_type()
            .can_have_vols() == 't';
    }

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
            return nodes.map(function(n){return Number(n.id())});
        return nodes;
    }

    // list of org_unit objects or IDs for ancestors + me + descendants
    service.fullPath = function(node_or_id, as_id) {
        var list = service.ancestors(node_or_id).concat(
          service.descendants(node_or_id).slice(1));
        if (as_id) 
            return list.map(function(n){return Number(n.id())});
        return list;
    }

    var egLovefield = null;
    // returns a promise, resolved with a hash of setting name =>
    // setting value for the selected org unit.  Org unit defaults to 
    // auth workstation org unit.
    service.settings = function(names, ou_id) {
        if (!egLovefield) {
            egLovefield = $injector.get('egLovefield');
        }

        // allow non-array
        if (!angular.isArray(names)) names = [names];

        if (lf.isOffline) {
            // for offline, just use whatever we have managed to cache,
            // even if the value is expired (since we can't refresh it
            // from the server)
            return egLovefield.getSettingsCache(names).then(
                function(settings) {
                    var hash = {};
                    angular.forEach(settings, function (s) {
                        hash[s.name] = s.value;
                    });
                    return $q.when(hash);
                },
                function() {return $q.when({})} // Not Supported
            );
        }


        if (!egAuth.user()) return $q.when();

        ou_id = ou_id || egAuth.user().ws_ou();
        if (ou_id != egAuth.user().ws_ou()) {
            // we only cache settings for the current working location;
            // if we have requested settings for some other org unit,
            // skip the cache and pull settings directly from the server
            return service.settingsFromServer(names, ou_id);
        }

        var deferred = $q.defer();
        
        var newNames = [];
        angular.forEach(names, function(name) {
            if (!angular.isDefined(service.cachedSettings[name]))
                // we don't have a value for this setting yet 
                newNames.push(name)
        });

        // only retrieve uncached values
        names = newNames;
        if (names.length == 0)
            return $q.when(service.cachedSettings);

        // get settings from offline cache where possible;
        // otherwise, get settings from server
        egLovefield.getSettingsCache(names)
        .then(function(settings) {

            // populate values from offline cache
            angular.forEach(settings, function (s) {
                service.cachedSettings[s.name] = s.value;
            });

            // check if any requested settings were not in offline cache
            var uncached = [];
            angular.forEach(names, function(name) {
                if (!angular.isDefined(service.cachedSettings[name]))
                    uncached.push(name);
            });

            if (uncached.length == 0) {
                // all requested settings were in the offline cache already
                deferred.resolve(service.cachedSettings);
            } else {
                // cache was missing some settings; grab those from the server
                service.settingsFromServer(uncached, ou_id)
                .then(function() {
                    deferred.resolve(service.cachedSettings);
                });
            }
        });
        return deferred.promise;
    }

    service.settingsFromServer = function(names, ou_id) {
        if (!egLovefield) {
            egLovefield = $injector.get('egLovefield');
        }

        // allow non-array
        if (!angular.isArray(names)) names = [names];

        var deferred = $q.defer();
        ou_id = ou_id || egAuth.user().ws_ou();
        var here = (ou_id == egAuth.user().ws_ou());

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

            return egLovefield.setSettingsCache(settings).then(
                function() {
                    // resolve with cached settings if 'here', since 'settings'
                    // will only contain settings we had to retrieve
                    deferred.resolve(here ? service.cachedSettings : settings);
                },
                function() {
                    deferred.resolve(here ? service.cachedSettings : settings);
                }
            );
        });
        return deferred.promise;
    }

    return service;
}]);
 
