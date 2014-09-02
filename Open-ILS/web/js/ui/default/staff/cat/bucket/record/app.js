/**
 * Catalog Record Buckets
 *
 * Known Issues
 *
 * add-all actions only add visible/fetched items.
 * remove all from bucket UI leaves busted pagination 
 *   -- apply a refresh after item removal?
 * problems with bucket view fetching by record ID instead of bucket item:
 *   -- dupe bibs always sort to the bottom
 *   -- dupe bibs result in more records displayed per page than requested
 *   -- item 'pos' ordering is not honored on initial load.
 */

angular.module('egCatRecordBuckets', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/cat/bucket/record/search/:id', {
        templateUrl: './cat/bucket/record/t_search',
        controller: 'SearchCtrl',
        resolve : resolver
    });
    
    $routeProvider.when('/cat/bucket/record/search', {
        templateUrl: './cat/bucket/record/t_search',
        controller: 'SearchCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/bucket/record/pending/:id', {
        templateUrl: './cat/bucket/record/t_pending',
        controller: 'PendingCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/bucket/record/pending', {
        templateUrl: './cat/bucket/record/t_pending',
        controller: 'PendingCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/bucket/record/view/:id', {
        templateUrl: './cat/bucket/record/t_view',
        controller: 'ViewCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/bucket/record/view', {
        templateUrl: './cat/bucket/record/t_view',
        controller: 'ViewCtrl',
        resolve : resolver
    });

    // default page / bucket view
    $routeProvider.otherwise({redirectTo : '/cat/bucket/record/view'});
})

/**
 * bucketSvc allows us to communicate between the search,
 * pending, and view controllers.  It also allows us to cache
 * data for each so that data reloads are not needed on every 
 * tab click (i.e. route persistence).
 */
.factory('bucketSvc', ['$q','egCore', function($q,  egCore) { 

    var service = {
        allBuckets : [], // un-fleshed user buckets
        queryString : '', // last run query
        queryRecords : [], // last run query results
        currentBucket : null, // currently viewed bucket

        // per-page list collections
        searchList  : [],
        pendingList : [],
        viewList  : [],

        // fetches all staff/biblio buckets for the authenticated user
        // this function may only be called after startup.
        fetchUserBuckets : function(force) {
            if (this.allBuckets.length && !force) return;
            var self = this;
            return egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.container.retrieve_by_class.authoritative',
                egCore.auth.token(), egCore.auth.user().id(), 
                'biblio', 'staff_client'
            ).then(function(buckets) { self.allBuckets = buckets });
        },

        createBucket : function(name, desc) {
            var deferred = $q.defer();
            var bucket = new egCore.idl.cbreb();
            bucket.owner(egCore.auth.user().id());
            bucket.name(name);
            bucket.description(desc || '');
            bucket.btype('staff_client');

            egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.container.create',
                egCore.auth.token(), 'biblio', bucket
            ).then(function(resp) {
                if (resp) {
                    if (typeof resp == 'object') {
                        console.error('bucket create error: ' + js2JSON(resp));
                        deferred.reject();
                    } else {
                        deferred.resolve(resp);
                    }
                }
            });

            return deferred.promise;
        },

        // edit the current bucket.  since we edit the 
        // local object, there's no need to re-fetch.
        editBucket : function(args) {
            var bucket = service.currentBucket;
            bucket.name(args.name);
            bucket.description(args.desc);
            bucket.pub(args.pub);
            return egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.container.update',
                egCore.auth.token(), 'biblio', bucket
            );
        }
    }

    // returns 1 if full refresh is needed
    // returns 2 if list refresh only is needed
    service.bucketRefreshLevel = function(id) {
        if (!service.currentBucket) return 1;
        if (service.bucketNeedsRefresh) {
            service.bucketNeedsRefresh = false;
            service.currentBucket = null;
            return 1;
        }
        if (service.currentBucket.id() != id) return 1;
        return 2;
    }

    // returns a promise, resolved with bucket, rejected if bucket is
    // not fetch-able
    service.fetchBucket = function(id) {
        var refresh = service.bucketRefreshLevel(id);
        if (refresh == 2) return $q.when(service.currentBucket);

        var deferred = $q.defer();

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.container.flesh.authoritative',
            egCore.auth.token(), 'biblio', id
        ).then(function(bucket) {
            var evt = egCore.evt.parse(bucket);
            if (evt) {
                console.debug(evt);
                deferred.reject(evt);
                return;
            }
            service.currentBucket = bucket;
            deferred.resolve(bucket);
        });

        return deferred.promise;
    }

    // deletes a single container item from a bucket by container item ID.
    // promise is rejected on failure
    service.detachRecord = function(itemId) {
        var deferred = $q.defer();
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.delete',
            egCore.auth.token(), 'biblio', itemId
        ).then(function(resp) { 
            var evt = egCore.evt.parse(resp);
            if (evt) {
                console.error(evt);
                deferred.reject(evt);
                return;
            }
            console.log('detached bucket item ' + itemId);
            deferred.resolve(resp);
        });

        return deferred.promise;
    }

    // delete bucket by ID.
    // resolved w/ response on successful delete,
    // rejected otherwise.
    service.deleteBucket = function(id) {
        var deferred = $q.defer();
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.container.full_delete',
            egCore.auth.token(), 'biblio', id
        ).then(function(resp) {
            var evt = egCore.evt.parse(resp);
            if (evt) {
                console.error(evt);
                deferred.reject(evt);
                return;
            }
            deferred.resolve(resp);
        });
        return deferred.promise;
    }

    return service;
}])

/**
 * Top-level controller.  
 * Hosts functions needed by all controllers.
 */
.controller('RecordBucketCtrl',
       ['$scope','$location','$q','$timeout','$modal',
        '$window','egCore','bucketSvc',
function($scope,  $location,  $q,  $timeout,  $modal,  
         $window,  egCore,  bucketSvc) {

    $scope.bucketSvc = bucketSvc;
    $scope.bucket = function() { return bucketSvc.currentBucket }

    // tabs: search, pending, view
    $scope.setTab = function(tab) { 
        $scope.tab = tab;

        // for bucket selector; must be called after route resolve
        bucketSvc.fetchUserBuckets(); 
    };

    $scope.loadBucketFromMenu = function(item, bucket) {
        if (bucket) return $scope.loadBucket(bucket.id());
    }

    $scope.loadBucket = function(id) {
        $location.path(
            '/cat/bucket/record/' + 
                $scope.tab + '/' + encodeURIComponent(id));
    }

    $scope.addToBucket = function(recs) {
        if (recs.length == 0) return;
        bucketSvc.bucketNeedsRefresh = true;

        angular.forEach(recs,
            function(rec) {
                var item = new egCore.idl.cbrebi();
                item.bucket(bucketSvc.currentBucket.id());
                item.target_biblio_record_entry(rec.id);
                egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.container.item.create', 
                    egCore.auth.token(), 'biblio', item
                ).then(function(resp) {

                    // HACK: add the IDs of the added items so that the size
                    // of the view list will grow (and update any UI looking at
                    // the list size).  The data stored is inconsistent, but since
                    // we are forcing a bucket refresh on the next rendering of 
                    // the view pane, the list will be repaired.
                    bucketSvc.currentBucket.items().push(resp);
                });
            }
        );
    }

    $scope.openCreateBucketDialog = function() {
        $modal.open({
            templateUrl: './cat/bucket/record/t_bucket_create',
            controller: 
                ['$scope', '$modalInstance', function($scope, $modalInstance) {
                $scope.focusMe = true;
                $scope.ok = function(args) { $modalInstance.close(args) }
                $scope.cancel = function () { $modalInstance.dismiss() }
            }]
        }).result.then(function (args) {
            if (!args || !args.name) return;
            bucketSvc.createBucket(args.name, args.desc).then(
                function(id) {
                    if (!id) return;
                    bucketSvc.viewList = [];
                    bucketSvc.allBuckets = []; // reset
                    bucketSvc.currentBucket = null;
                    $location.path(
                        '/cat/bucket/record/' + $scope.tab + '/' + id);
                }
            );
        });
    }

    $scope.openEditBucketDialog = function() {
        $modal.open({
            templateUrl: './cat/bucket/record/t_bucket_edit',
            controller: 
                ['$scope', '$modalInstance', function($scope, $modalInstance) {
                $scope.focusMe = true;
                $scope.args = {
                    name : bucketSvc.currentBucket.name(),
                    desc : bucketSvc.currentBucket.description(),
                    pub : bucketSvc.currentBucket.pub() == 't'
                };
                $scope.ok = function(args) { 
                    if (!args) return;
                    $scope.actionPending = true;
                    args.pub = args.pub ? 't' : 'f';
                    // close the dialog after edit has completed
                    bucketSvc.editBucket(args).then(
                        function() { $modalInstance.close() });
                }
                $scope.cancel = function () { $modalInstance.dismiss() }
            }]
        })
    }


    // opens the delete confirmation and deletes the current
    // bucket if the user confirms.
    $scope.openDeleteBucketDialog = function() {
        $modal.open({
            templateUrl: './cat/bucket/record/t_bucket_delete',
            controller : 
                ['$scope', '$modalInstance', function($scope, $modalInstance) {
                $scope.bucket = function() { return bucketSvc.currentBucket }
                $scope.ok = function() { $modalInstance.close() }
                $scope.cancel = function() { $modalInstance.dismiss() }
            }]
        }).result.then(function () {
            bucketSvc.deleteBucket(bucketSvc.currentBucket.id())
            .then(function() {
                bucketSvc.allBuckets = [];
                $location.path('/cat/bucket/record/view');
            });
        });
    }

    // retrieves the requested bucket by ID
    $scope.openSharedBucketDialog = function() {
        $modal.open({
            templateUrl: './cat/bucket/record/t_load_shared',
            controller : 
                ['$scope', '$modalInstance', function($scope, $modalInstance) {
                $scope.focusMe = true;
                $scope.ok = function(args) { 
                    if (args && args.id) {
                        $modalInstance.close(args.id) 
                    }
                }
                $scope.cancel = function() { $modalInstance.dismiss() }
            }]
        }).result.then(function(id) {
            // RecordBucketCtrl $scope is not inherited by the
            // modal, so we need to call loadBucket from the 
            // promise resolver.
            $scope.loadBucket(id);
        });
    }

    // opens the record export dialog
    $scope.openExportBucketDialog = function() {
        $modal.open({
            templateUrl: './cat/bucket/record/t_bucket_export',
            controller : 
                ['$scope', '$modalInstance', function($scope, $modalInstance) {
                $scope.args = {format : 'XML', encoding : 'UTF-8'}; // defaults
                $scope.ok = function(args) { $modalInstance.close(args) }
                $scope.cancel = function() { $modalInstance.dismiss() }
            }]
        }).result.then(function (args) {
            if (!args) return;
            args.containerid = bucketSvc.currentBucket.id();

            var url = '/exporter?containerid=' + args.containerid + 
                '&format=' + args.format + '&encoding=' + args.encoding;

            if (args.holdings) url += '&holdings=1';

            // TODO: improve auth cookie handling so this isn't necessary.
            // today the cookie path is too specific (/eg/staff) for non-staff
            // UIs to access it.  See services/auth.js
            url += '&ses=' + egCore.auth.token(); 

            $timeout(function() { $window.open(url) });
        });
    }
}])

.controller('SearchCtrl',
       ['$scope','$routeParams','egCore','bucketSvc',
function($scope,  $routeParams,  egCore , bucketSvc) {

    $scope.setTab('search');
    $scope.focusMe = true;
    var idQueryHash = {};

    function generateQuery() {
        if (bucketSvc.queryRecords.length)
            return {id : bucketSvc.queryRecords};
        else 
            return null;
    }

    $scope.gridControls = {
        setQuery : function() {return generateQuery()},
        setSort : function() {return ['id']}
    }

    // add selected items directly to the pending list
    $scope.addToPending = function(recs) {
        angular.forEach(recs, function(rec) {
            if (bucketSvc.pendingList.filter( // remove dupes
                function(r) {return r.id == rec.id}).length) return;
            bucketSvc.pendingList.push(rec);
        });
    }

    $scope.search = function() {
        $scope.searchList = [];
        $scope.searchInProgress = true;
        bucketSvc.queryRecords = [];

        egCore.net.request(
            'open-ils.search',
            'open-ils.search.biblio.multiclass.query', {   
                limit : 500 // meh
            }, bucketSvc.queryString, true
        ).then(function(resp) {
            bucketSvc.queryRecords = 
                resp.ids.map(function(id){return id[0]});
            $scope.gridControls.setQuery(generateQuery());
        })['finally'](function() {
            $scope.searchInProgress = false;
        });
    }

    if ($routeParams.id && 
        (!bucketSvc.currentBucket || 
            bucketSvc.currentBucket.id() != $routeParams.id)) {
        // user has accessed this page cold with a bucket ID.
        // fetch the bucket for display, then set the totalCount
        // (also for display), but avoid fully fetching the bucket,
        // since it's premature, in this UI.
        bucketSvc.fetchBucket($routeParams.id);
    }
}])

.controller('PendingCtrl',
       ['$scope','$routeParams','bucketSvc','egGridDataProvider',
function($scope,  $routeParams,  bucketSvc , egGridDataProvider) {
    $scope.setTab('pending');

    var provider = egGridDataProvider.instance({});
    provider.get = function(offset, count) {
        return provider.arrayNotifier(
            bucketSvc.pendingList, offset, count);
    }
    $scope.gridDataProvider = provider;

    $scope.resetPendingList = function() {
        bucketSvc.pendingList = [];
    }
    

    if ($routeParams.id && 
        (!bucketSvc.currentBucket || 
            bucketSvc.currentBucket.id() != $routeParams.id)) {
        // user has accessed this page cold with a bucket ID.
        // fetch the bucket for display, then set the totalCount
        // (also for display), but avoid fully fetching the bucket,
        // since it's premature, in this UI.
        bucketSvc.fetchBucket($routeParams.id);
    }
}])

.controller('ViewCtrl',
       ['$scope','$q','$routeParams','bucketSvc',
function($scope,  $q , $routeParams,  bucketSvc) {

    $scope.setTab('view');
    $scope.bucketId = $routeParams.id;

    var query;
    $scope.gridControls = {
        setQuery : function(q) {
            if (q) query = q;
            return query;
        }
    };

    function drawBucket() {
        return bucketSvc.fetchBucket($scope.bucketId).then(
            function(bucket) {
                var ids = bucket.items().map(
                    function(i){return i.target_biblio_record_entry()}
                );
                if (ids.length) {
                    $scope.gridControls.setQuery({id : ids});
                } else {
                    $scope.gridControls.setQuery({});
                }
            }
        );
    }

    $scope.detachRecords = function(records) {
        var promises = [];
        angular.forEach(records, function(rec) {
            var item = bucketSvc.currentBucket.items().filter(
                function(i) {
                    return (i.target_biblio_record_entry() == rec.id)
                }
            );
            if (item.length)
                promises.push(bucketSvc.detachRecord(item[0].id()));
        });

        bucketSvc.bucketNeedsRefresh = true;
        return $q.all(promises).then(drawBucket);
    }

    // fetch the bucket;  on error show the not-allowed message
    if ($scope.bucketId) 
        drawBucket()['catch'](function() { $scope.forbidden = true });
}])
