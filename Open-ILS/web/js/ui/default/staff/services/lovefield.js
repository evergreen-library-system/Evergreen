/**
 * Core Service - egLovefield
 *
 * Lovefield wrapper factory for low level offline stuff
 *
 */
angular.module('egCoreMod')

.factory('egLovefield', ['$q','$rootScope','egCore','$timeout', 
                 function($q , $rootScope , egCore , $timeout) { 

    var service = {
        autoId: 0, // each request gets a unique id.
        cannotConnect: false,
        pendingRequests: [],
        activeSchemas: ['cache'], // add 'offline' in the offline UI
        schemasInProgress: {},
        connectedSchemas: [],
        // TODO: relative path would be more portable
        workerUrl: '/js/ui/default/staff/offline-db-worker.js'
    };

    // Returns true if the connection was possible
    service.connectToWorker = function() {
        if (service.worker) return true;
        if (service.cannotConnect) return false;

        try {
            // relative path would be better...
            service.worker = new SharedWorker(service.workerUrl);
        } catch (E) {
            console.warn('SharedWorker() not supported', E);
            service.cannotConnect = true;
            return false;
        }

        service.worker.onerror = function(err) {
            // avoid spamming unit test runner on failure to connect.
            if (!navigator.userAgent.match(/PhantomJS/)) {
                console.error('Error loading shared worker', err);
            }
            service.cannotConnect = true;
        }

        // List for responses and resolve the matching pending request.
        service.worker.port.addEventListener('message', function(evt) {
            var response = evt.data;
            var reqId = response.id;
            var req = service.pendingRequests.filter(
                function(r) { return r.id === reqId})[0];

            if (!req) {
                console.error('Recieved response for unknown request ' + reqId);
                return;
            }

            if (response.status === 'OK') {
                req.deferred.resolve(response.result);
            } else {
                console.error('worker request failed with ' + response.error);
                req.deferred.reject(response.error);
            }
        });

        service.worker.port.start();
        return true;
    }

    service.connectToSchemas = function() {

        service.connectToWorker(); // no-op if already connected

        if (service.cannotConnect) { 
            // This can happen in certain environments
            return $q.reject();
        }

        var promises = [];

        service.activeSchemas.forEach(function(schema) {
            promises.push(service.connectToSchema(schema));
        });

        return $q.all(promises).then(
            function() {},
            function() {service.cannotConnect = true}
        );
    }

    // Connects if necessary to the active schemas then relays the request.
    service.request = function(args) {
        // useful, but very chatty, leaving commented out.
        // console.debug('egLovfield sending request: ', args);
        return service.connectToSchemas().then(
            function() {
                return service.relayRequest(args);
            }
        );
    }

    // Send a request to the web worker and register the request for
    // future resolution.
    // Store the request ID in the request arguments, so it's included
    // in the response, and in the pendingRequests list for linking.
    service.relayRequest = function(args) {
        var deferred = $q.defer();
        var reqId = service.autoId++;
        args.id = reqId;
        service.pendingRequests.push({id : reqId, deferred: deferred});
        service.worker.port.postMessage(args);
        return deferred.promise;
    }

    // Create and connect to the give schema
    service.connectToSchema = function(schema) {

        if (service.connectedSchemas.indexOf(schema) >= 0) {
            // already connected
            return $q.when();
        }

        if (service.schemasInProgress[schema]) {
            return service.schemasInProgress[schema];
        }

        var deferred = $q.defer();

        service.relayRequest(
            {schema: schema, action: 'createSchema'}) 
        .then(
            function() {
                return service.relayRequest(
                    {schema: schema, action: 'connect'});
            },
            deferred.reject
        ).then(
            function() { 
                service.connectedSchemas.push(schema); 
                delete service.schemasInProgress[schema];
                deferred.resolve();
            },
            deferred.reject
        );

        return service.schemasInProgress[schema] = deferred.promise;
    }

    service.isCacheGood = function (type) {
        if (lf.isOffline || !service.connectToWorker()) return $q.when(true);

        return service.request({
            schema: 'cache',
            table: 'CacheDate',
            action: 'selectWhereEqual',
            field: 'type',
            value: type
        }).then(
            function(result) {
                var row = result[0];
                if (!row) { return false; }
                // hard-coded 1 day offline cache timeout
                return (new Date().getTime() - row.cachedate.getTime()) <= 86400000;
            }
        );
    }

    // Remove all pending offline transactions and delete the cached
    // offline transactions date to indicate no transactions remain.
    service.destroyPendingOfflineXacts = function () {
        return service.request({
            schema: 'offline',
            table: 'OfflineXact',
            action: 'deleteAll'
        }).then(function() {
            return service.request({
                schema: 'cache',
                table: 'CacheDate',
                action: 'deleteWhereEqual',
                field: 'type',
                value: '_offlineXact'
            });
        });
    }

    // Returns the cache date when xacts exit, null otherwise.
    service.havePendingOfflineXacts = function () {
        return service.request({
            schema: 'cache',
            table: 'CacheDate',
            action: 'selectWhereEqual',
            field: 'type',
            value: '_offlineXact'
        }).then(function(results) {
            return results[0] ? results[0].cachedate : null;
        });
    }

    service.retrievePendingOfflineXacts = function () {
        return service.request({
            schema: 'offline',
            table: 'OfflineXact',
            action: 'selectAll'
        }).then(function(resp) {
            return resp.map(function(x) { return x.value });
        });
    }

    // Add an offline transaction and update the cache indicating
    // now() as the most recent addition of an offline xact.
    service.addOfflineXact = function (obj) {
        return service.request({
            schema: 'offline',
            table: 'OfflineXact',
            action: 'insertOrReplace',
            rows: [{value: obj}]
        }).then(function() {
            return service.request({
                schema: 'cache',
                table: 'CacheDate',
                action: 'insertOrReplace',
                rows: [{type: '_offlineXact', cachedate : new Date()}]
            });
        });
    }

    service.populateBlockList = function() {
        return service.request({
            action: 'populateBlockList',
            authtoken: egCore.auth.token()
        });
    }

    // Returns a promise with true for blocked, false for not blocked
    service.testOfflineBlock = function (barcode) {
        return service.request({
            schema: 'offline',
            table: 'OfflineBlocks',
            action: 'selectWhereEqual',
            field: 'barcode',
            value: barcode
        }).then(function(resp) {
            if (resp.length === 0) return null;
            return resp[0].reason;
        });
    }

    service.setStatCatsCache = function (statcats) {
        if (lf.isOffline || !statcats || 
            statcats.length === 0 || !service.connectToWorker()) {
            return $q.when();
        }

        var rows = statcats.map(function(cat) {
            return {id: cat.id(), value: egCore.idl.toHash(cat)}
        });

        return service.request({
            schema: 'cache',
            table: 'StatCat',
            action: 'insertOrReplace',
            rows: rows
        });
    }

    service.getStatCatsCache = function () {
        return service.request({
            schema: 'cache',
            table: 'StatCat',
            action: 'selectAll'
        }).then(function(list) {
            var result = [];
            list.forEach(function(s) {
                var sc = egCore.idl.fromHash('actsc', s.value);

                if (Array.isArray(sc.default_entries())) {
                    sc.default_entries(
                        sc.default_entries().map( function (k) {
                            return egCore.idl.fromHash('actsced', k);
                        })
                    );
                }

                if (Array.isArray(sc.entries())) {
                    sc.entries(
                        sc.entries().map( function (k) {
                            return egCore.idl.fromHash('actsce', k);
                        })
                    );
                }

                result.push(sc);
            });

            return result;
        });
    }

    service.setSettingsCache = function (settings) {
        if (lf.isOffline || !service.connectToWorker()) return $q.when();

        var rows = [];
        angular.forEach(settings, function (val, key) {
            rows.push({name  : key, value : JSON.stringify(val)});
        });

        return service.request({
            schema: 'cache',
            table: 'Setting',
            action: 'insertOrReplace',
            rows: rows
        });
    }

    service.getSettingsCache = function (settings) {
        if (lf.isOffline || !service.connectToWorker()) return $q.when([]);

        var promise;

        if (settings && settings.length) {
            promise = service.request({
                schema: 'cache',
                table: 'Setting',
                action: 'selectWhereIn',
                field: 'name',
                value: settings
            });
        } else {
            promise = service.request({
                schema: 'cache',
                table: 'Setting',
                action: 'selectAll'
            });
        }

        return promise.then(
            function(resp) {
                resp.forEach(function(s) { s.value = JSON.parse(s.value); });
                return resp;
            }
        );
    }

    service.destroySettingsCache = function () {
        if (lf.isOffline || !service.connectToWorker()) return $q.when();
        return service.request({
            schema: 'cache',
            table: 'Setting',
            action: 'deleteAll'
        });
    }

    service.setListInOfflineCache = function (type, list) {
        if (lf.isOffline || !service.connectToWorker()) return $q.when();

        return service.isCacheGood(type).then(function(good) {
            if (good) { return };  // already cached

            var pkey = egCore.idl.classes[type].pkey;
            var rows = Object.values(list).map(function(item) {
                return {
                    type: type, 
                    id: '' + item[pkey](), 
                    object: egCore.idl.toHash(item)
                };
            });

            return service.request({
                schema: 'cache',
                table: 'Object',
                action: 'insertOrReplace',
                rows: rows
            }).then(function(resp) {
                return service.request({
                    schema: 'cache',
                    table: 'CacheDate',
                    action: 'insertOrReplace',
                    rows: [{type: type, cachedate : new Date()}]
                });
            });
        });
    }

    service.getListFromOfflineCache = function(type) {
        return service.request({
            schema: 'cache',
            table: 'Object',
            action: 'selectWhereEqual',
            field: 'type',
            value: type
        }).then(function(resp) {
            return resp.map(function(item) {
                return egCore.idl.fromHash(type,item['object']);
            });
        });
    }

    service.reconstituteList = function(type) {
        if (lf.isOffline) {
            console.debug('egLovefield reading ' + type + ' list');
            return service.getListFromOfflineCache(type).then(function (list) {
                egCore.env.absorbList(list, type, true)
                return $q.when(true);
            });
        }
        return $q.when(false);
    }

    service.reconstituteTree = function(type) {
        if (lf.isOffline) {
            console.debug('egLovefield reading ' + type + ' tree');

            var pkey = egCore.idl.classes[type].pkey;
            var parent_field = 'parent';

            if (type == 'aou') {
                parent_field = 'parent_ou';
            }

            return service.getListFromOfflineCache(type).then(function (list) {
                var hash = {};
                var top = null;
                angular.forEach(list, function (item) {

                    // Special case for aou, to reconstitue ou_type
                    if (type == 'aou') {
                        if (item.ou_type()) {
                            item.ou_type( egCore.idl.fromHash('aout', item.ou_type()) );
                        }
                    }

                    hash[''+item[pkey]()] = item;
                    if (!item[parent_field]()) {
                        top = item;
                    } else if (angular.isObject(item[parent_field]())) {
                        // un-objectify the parent
                        item[parent_field](
                            item[parent_field]()[pkey]()
                        );
                    }
                });

                angular.forEach(list, function (item) {
                    item.children([]); // just clear it out if there's junk in there

                    item.children( list.filter(function (kid) {
                        return kid[parent_field]() == item[pkey]();
                    }) );
                });

                angular.forEach(list, function (item) {
                    if (item[parent_field]()) {
                        item[parent_field]( hash[''+item[parent_field]()] );
                    }
                });

                if (type == 'aou') {
                    // Sort the org tree before absorbing
                    egCore.env.sort_aou(top);
                }

                egCore.env.absorbTree(top, type, true)
                return $q.when(true)
            });
        }
        return $q.when(false);
    }

    return service;
}]);

