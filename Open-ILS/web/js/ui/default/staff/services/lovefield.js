var osb = lf.schema.create('offline', 2);

osb.createTable('Object').
    addColumn('type', lf.Type.STRING).          // class hint
    addColumn('id', lf.Type.STRING).           // obj id
    addColumn('object', lf.Type.OBJECT).
    addPrimaryKey(['type','id']);

osb.createTable('CacheDate').
    addColumn('type', lf.Type.STRING).          // class hint
    addColumn('cachedate', lf.Type.DATE_TIME).  // when was it last updated
    addPrimaryKey(['type']);

osb.createTable('Setting').
    addColumn('name', lf.Type.STRING).
    addColumn('value', lf.Type.STRING).
    addPrimaryKey(['name']);

osb.createTable('StatCat').
    addColumn('id', lf.Type.INTEGER).
    addColumn('value', lf.Type.OBJECT).
    addPrimaryKey(['id']);

osb.createTable('OfflineXact').
    addColumn('seq', lf.Type.INTEGER).
    addColumn('value', lf.Type.OBJECT).
    addPrimaryKey(['seq'], true);

osb.createTable('OfflineBlocks').
    addColumn('barcode', lf.Type.STRING).
    addColumn('reason', lf.Type.STRING).
    addPrimaryKey(['barcode']);

/**
 * Core Service - egLovefield
 *
 * Lovefield wrapper factory for low level offline stuff
 *
 */
angular.module('egCoreMod')

.factory('egLovefield', ['$q','$rootScope','egCore','$timeout', 
                 function($q , $rootScope , egCore , $timeout) { 

    var service = {};

    function connectOrGo() {

        if (lf.offlineDB) { // offline DB connected
            return $q.when();
        }

        if (service.cannotConnect) { // connection will never happen
            return $q.reject();
        }

        if (service.connectPromise) { // connection in progress
            return service.connectPromise;
        }

        // start a new connection attempt
        
        var deferred = $q.defer();

        console.debug('attempting offline DB connection');
        try {
            osb.connect().then(
                function(db) {
                    console.debug('successfully connected to offline DB');
                    service.connectPromise = null;
                    lf.offlineDB = db;
                    deferred.resolve();
                },
                function(err) {
                    // assumes that a single connection failure means
                    // a connection will never succeed.
                    service.cannotConnect = true;
                    console.error('Cannot connect to offline DB: ' + err);
                }
            );
        } catch (e) {
            // .connect() will throw an error if it detects that a connection
            // attempt is already in progress; this can happen with PhantomJS
            console.error('Cannot connect to offline DB: ' + e);
            service.cannotConnect = true;
        }

        service.connectPromise = deferred.promise;
        return service.connectPromise;
    }

    service.isCacheGood = function (type) {

        return connectOrGo().then(function() {
            var cacheDate = lf.offlineDB.getSchema().table('CacheDate');

            return lf.offlineDB.
                select(cacheDate.cachedate).
                from(cacheDate).
                where(cacheDate.type.eq(type)).
                exec().then(function(results) {
                    if (results.length == 0) {
                        return $q.when(false);
                    }

                    var now = new Date();
    
                    // hard-coded 1 day offline cache timeout
                    return $q.when((now.getTime() - results[0]['cachedate'].getTime()) <= 86400000);
                })
        });
    }

    service.destroyPendingOfflineXacts = function () {
        return connectOrGo().then(function() {
            var table = lf.offlineDB.getSchema().table('OfflineXact');
            return lf.offlineDB.
                delete().
                from(table).
                exec();
        });
    }

    service.havePendingOfflineXacts = function () {
        return connectOrGo().then(function() {
            var table = lf.offlineDB.getSchema().table('OfflineXact');
            return lf.offlineDB.
                select(table.reason).
                from(table).
                exec().
                then(function(list) {
                    return $q.when(Boolean(list.length > 0))
                });
        });
    }

    service.retrievePendingOfflineXacts = function () {
        return connectOrGo().then(function() {
            var table = lf.offlineDB.getSchema().table('OfflineXact');
            return lf.offlineDB.
                select(table.value).
                from(table).
                exec().
                then(function(list) {
                    return $q.when(list.map(function(x) { return x.value }))
                });
        });
    }

    service.destroyOfflineBlocks = function () {
        return connectOrGo().then(function() {
            var table = lf.offlineDB.getSchema().table('OfflineBlocks');
            return $q.when(
                lf.offlineDB.
                    delete().
                    from(table).
                    exec()
            );
        });
    }

    service.addOfflineBlock = function (barcode, reason) {
        return connectOrGo().then(function() {
            var table = lf.offlineDB.getSchema().table('OfflineBlocks');
            return $q.when(
                lf.offlineDB.
                    insertOrReplace().
                    into(table).
                    values([ table.createRow({ barcode : barcode, reason : reason }) ]).
                    exec()
            );
        });
    }

    // Returns a promise with true for blocked, false for not blocked
    service.testOfflineBlock = function (barcode) {
        return connectOrGo().then(function() {
            var table = lf.offlineDB.getSchema().table('OfflineBlocks');
            return lf.offlineDB.
                select(table.reason).
                from(table).
                where(table.barcode.eq(barcode)).
                exec().then(function(list) {
                    if(list.length > 0) return $q.when(list[0].reason);
                    return $q.when(null);
                });
        });
    }

    service.addOfflineXact = function (obj) {
        return connectOrGo().then(function() {
            var table = lf.offlineDB.getSchema().table('OfflineXact');
            return $q.when(
                lf.offlineDB.
                    insertOrReplace().
                    into(table).
                    values([ table.createRow({ value : obj }) ]).
                    exec()
            );
        });
    }

    service.setStatCatsCache = function (statcats) {
        if (lf.isOffline) return $q.when();

        return connectOrGo().then(function() {
            var table = lf.offlineDB.getSchema().table('StatCat');
            var rlist = [];

            angular.forEach(statcats, function (val) {
                rlist.push(table.createRow({
                    id    : val.id(),
                    value : egCore.idl.toHash(val)
                }));
            });
            return lf.offlineDB.
                insertOrReplace().
                into(table).
                values(rlist).
                exec();
        });
    }

    service.getStatCatsCache = function () {
        return connectOrGo().then(function() {

            var table = lf.offlineDB.getSchema().table('StatCat');
            var result = [];
            return lf.offlineDB.
                select(table.value).
                from(table).
                exec().then(function(list) {
                    angular.forEach(list, function (s) {
                        var sc = egCore.idl.fromHash('actsc', s.value);
    
                        if (angular.isArray(sc.default_entries())) {
                            sc.default_entries(
                                sc.default_entries().map( function (k) {
                                    return egCore.idl.fromHash('actsced', k);
                                })
                            );
                        }
    
                        if (angular.isArray(sc.entries())) {
                            sc.entries(
                                sc.entries().map( function (k) {
                                    return egCore.idl.fromHash('actsce', k);
                                })
                            );
                        }
    
                        result.push(sc);
                    });
                    return $q.when(result);
                });
    
        });
    }

    service.setSettingsCache = function (settings) {
        if (lf.isOffline) return $q.when();

        return connectOrGo().then(function() {

            var table = lf.offlineDB.getSchema().table('Setting');
            var rlist = [];

            angular.forEach(settings, function (val, key) {
                rlist.push(
                    table.createRow({
                        name  : key,
                        value : JSON.stringify(val)
                    })
                );
            });

            return lf.offlineDB.
                insertOrReplace().
                into(table).
                values(rlist).
                exec();
        });
    }

    service.getSettingsCache = function (settings) {
        return connectOrGo().then(function() {

            var table = lf.offlineDB.getSchema().table('Setting');

            var search_pred = table.name.isNotNull();
            if (settings && settings.length) {
                search_pred = table.name.in(settings);
            }
                
            return lf.offlineDB.
                select(table.name, table.value).
                from(table).
                where(search_pred).
                exec().then(function(list) {
                    angular.forEach(list, function (s) {
                        s.value = JSON.parse(s.value)
                    });
                    return $q.when(list);
                });
        });
    }

    service.setListInOfflineCache = function (type, list) {
        if (lf.isOffline) return $q.when();

        return connectOrGo().then(function() {

            service.isCacheGood(type).then(function(good) {
                if (!good) {
                    var object = lf.offlineDB.getSchema().table('Object');
                    var cacheDate = lf.offlineDB.getSchema().table('CacheDate');
                    var pkey = egCore.idl.classes[type].pkey;
        
                    angular.forEach(list, function(item) {
                        var row = object.createRow({
                            type    : type,
                            id      : '' + item[pkey](),
                            object  : egCore.idl.toHash(item)
                        });
                        lf.offlineDB.insertOrReplace().into(object).values([row]).exec();
                    });
        
                    var row = cacheDate.createRow({
                        type      : type,
                        cachedate : new Date()
                    });
        
                    console.log('egLovefield saving ' + type + ' list');
                    lf.offlineDB.insertOrReplace().into(cacheDate).values([row]).exec();
                }
            })
        });
    }

    service.getListFromOfflineCache = function(type) {
        return connectOrGo().then(function() {

            var object = lf.offlineDB.getSchema().table('Object');

            return lf.offlineDB.
                select(object.object).
                from(object).
                where(object.type.eq(type)).
                exec().then(function(results) {
                    return $q.when(results.map(function(item) {
                        return egCore.idl.fromHash(type,item['object'])
                    }));
                });
        });
    }

    service.reconstituteList = function(type) {
        if (lf.isOffline) {
            console.log('egLovefield reading ' + type + ' list');
            return service.getListFromOfflineCache(type).then(function (list) {
                egCore.env.absorbList(list, type, true)
                return $q.when(true);
            });
        }
        return $q.when(false);
    }

    service.reconstituteTree = function(type) {
        if (lf.isOffline) {
            console.log('egLovefield reading ' + type + ' tree');

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

                    if (item[parent_field]()) {
                        item[parent_field]( hash[''+item[parent_field]()] );
                    }

                    item.children( list.filter(function (kid) {
                        return kid[parent_field]() == item[pkey]();
                    }) );
                });

                egCore.env.absorbTree(top, type, true)
                return $q.when(true)
            });
        }
        return $q.when(false);
    }

    return service;
}]);

