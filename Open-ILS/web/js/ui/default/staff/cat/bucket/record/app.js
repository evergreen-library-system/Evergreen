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
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod', 'egMarcMod', 'egHoldingsMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
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

    $routeProvider.when('/cat/bucket/record/view/:id/merge/:ids', {
        templateUrl: './cat/bucket/record/t_view',
        controller: 'ViewCtrl',
        resolve: resolver
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
                'biblio', ['staff_client', 'vandelay_queue']
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
            egCore.pcrud.retrieve(
                'au', bucket.owner(),
                {flesh : 1, flesh_fields : {au : ["card"]}}
            ).then(function(patron) {
                // On the off chance no barcode is present (it's not 
                // required) use the patron username as the identifier.
                bucket._owner_ident = patron.card() ? 
                    patron.card().barcode() : patron.usrname();
                bucket._owner_name = patron.family_name();
                bucket._owner_ou = egCore.org.get(patron.home_ou()).shortname();
            });

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

    service.deleteRecordFromCatalog = function(recordId) {
        var deferred = $q.defer();

        egCore.net.request(
            'open-ils.cat',
            'open-ils.cat.biblio.record_entry.delete',
            egCore.auth.token(), recordId
        ).then(function(resp) { 
            // rather than rejecting the promise in the
            // case of a failure, we'll let the caller
            // look for errors -- doing this because AngularJS
            // does not have a native $q.allSettled() yet.
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
       ['$scope','$location','$q','$timeout','$uibModal',
        '$window','egCore','bucketSvc',
function($scope,  $location,  $q,  $timeout,  $uibModal,  
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

        var ids = recs.map(function(rec) { return rec.id; });

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.create.batch',
            egCore.auth.token(), 'biblio_record_entry', 
            bucketSvc.currentBucket.id(), ids

        ).then(
            null, // complete
            null, // error
            function(resp) {
                // HACK: add the IDs of the added items so that the size
                // of the view list will grow (and update any UI looking at
                // the list size).  The data stored is inconsistent, but since
                // we are forcing a bucket refresh on the next rendering of 
                // the view pane, the list will be repaired.
                bucketSvc.currentBucket.items().push(resp);
            }
        )
    }

    $scope.openCreateBucketDialog = function() {
        $uibModal.open({
            templateUrl: './cat/bucket/share/t_bucket_create',
            backdrop: 'static',
            controller: 
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
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
        $uibModal.open({
            templateUrl: './cat/bucket/share/t_bucket_edit',
            backdrop: 'static',
            controller: 
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
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
                        function() { $uibModalInstance.close() });
                }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        })
    }


    // opens the delete confirmation and deletes the current
    // bucket if the user confirms.
    $scope.openDeleteBucketDialog = function() {
        $uibModal.open({
            templateUrl: './cat/bucket/share/t_bucket_delete',
            backdrop: 'static',
            controller : 
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.bucket = function() { return bucketSvc.currentBucket }
                $scope.ok = function() { $uibModalInstance.close() }
                $scope.cancel = function() { $uibModalInstance.dismiss() }
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
        $uibModal.open({
            templateUrl: './cat/bucket/share/t_load_shared',
            backdrop: 'static',
            controller : 
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.ok = function(args) { 
                    if (args && args.id) {
                        $uibModalInstance.close(args.id) 
                    }
                }
                $scope.cancel = function() { $uibModalInstance.dismiss() }
            }]
        }).result.then(function(id) {
            // RecordBucketCtrl $scope is not inherited by the
            // modal, so we need to call loadBucket from the 
            // promise resolver.
            $scope.loadBucket(id);
        });
    }

    // allows user to create a carousel from the selected bucket
    $scope.openCreateCarouselDialog = function() {
        if (!bucketSvc.currentBucket || !bucketSvc.currentBucket.id()) {
            return;
        }
        $uibModal.open({
            templateUrl: './cat/bucket/record/t_create_carousel',
            backdrop: 'static',
            controller :
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.ok = function(args) {
                    if (args && args.name) {
                        return egCore.net.request(
                            'open-ils.actor',
                            'open-ils.actor.carousel.create.from_bucket',
                            egCore.auth.token(), args.name, bucketSvc.currentBucket.id()
                        ).then(function(carouselId) { $uibModalInstance.close(carouselId) });
                    }
                }
                $scope.cancel = function() { $uibModalInstance.dismiss() }
            }]
        }).result.then(function(carouselId) {
            // bouncing outside of AngularJS
            $window.location.href = '/eg2/en-US/staff/admin/local/container/carousel';
        });
    }

    // opens the record export dialog
    $scope.openExportBucketDialog = function() {
        $uibModal.open({
            templateUrl: './cat/bucket/record/t_bucket_export',
            backdrop: 'static',
            controller : 
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.args = {format : 'XML', encoding : 'UTF-8'}; // defaults
                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function() { $uibModalInstance.dismiss() }
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
            'open-ils.search.biblio.multiclass.query.staff', {   
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
        $scope.gridDataProvider.refresh();
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
       ['$scope','$q','$routeParams','bucketSvc','egCore','$window',
        '$timeout','egConfirmDialog','$uibModal','egHolds',
function($scope,  $q , $routeParams,  bucketSvc,  egCore,  $window,
         $timeout,  egConfirmDialog,  $uibModal,  egHolds) {

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

    // runs the transfer title holds action
    $scope.transfer_holds_to_marked = function(records) {
        var bib_ids = records.map(function(val) { return val.id; })
        egHolds.transfer_all_bib_holds_to_marked_title(bib_ids);
    }

    // Refresh and update a single bib record.
    // Returns a promise.
    function updateOneRecord(recId, marcXml) {

        return egCore.net.request(
            'open-ils.cat',
            'open-ils.cat.biblio.record.xml.update',
            egCore.auth.token(), recId, marcXml
        ).then(function(result) {
            var evt = egCore.evt.parse(result);
            if (evt) {
                alert(evt);
                return $q.reject(evt);
            } else {
                return result; // bib record
            }
        });
    }

    // opens the record merge dialog
    $scope.openRecordMergeDialog = function(records, bChannel) {
        $uibModal.open({
            templateUrl: './cat/bucket/record/t_merge_records',
            backdrop: 'static',
            size: 'lg',
            windowClass: 'eg-wide-modal',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.records = [];
                $scope.lead_id = 0;
                $scope.merge_profile = null;
                $scope.lead = { marc_xml : null };
                $scope.editing_inplace = false;
                $scope.showHoldings = false;
                angular.forEach(records, function(rec) {
                    $scope.records.push({ id : rec.id });
                });
                $scope.ok = function() {
                    $uibModalInstance.close({
                        lead_id : $scope.lead_id,
                        records : $scope.records,
                        merge_profile : $scope.merge_profile,
                        lead : $scope.lead
                    });
                }
                $scope.cancel = function () {
                    if (bChannel) { $window.close(); } // called from the Angular bucket UI
                    $uibModalInstance.dismiss();
                }

                $scope.merge_marc = function() {
                    // need lead, at least one sub, and a merge profile
                    if (!$scope.lead_id) return;
                    if (!$scope.merge_profile) return;

                    if (!$scope.records.length) {
                        // if we got here, the last subordinate record
                        // was likely removed, so let's refresh the
                        // lead for the sake of a consistent display
                        egCore.pcrud.retrieve('bre', $scope.lead_id)
                        .then(function(rec) {
                            $scope.lead.marc_xml = rec.marc();
                        });
                        return;
                    }

                    var recs = $scope.records.map(function(val) { return val.id; });
                    recs.unshift($scope.lead_id);
                    egCore.net.request(
                        'open-ils.cat',
                        'open-ils.cat.merge.biblio.per_profile',
                        egCore.auth.token(),
                        $scope.merge_profile,
                        recs
                    ).then(function(merged) {
                        if (merged) $scope.lead.marc_xml = merged;
                    });
                }
                $scope.$watch('merge_profile', function(newVal, oldVal) {
                    if (newVal && newVal !== oldVal) {
                        $scope.merge_marc();
                    }
                });

                $scope.use_as_lead = function(rec) {
                    if ($scope.lead_id) {
                        $scope.records.push({ id : $scope.lead_id });
                    }
                    $scope.lead_id = rec.id;
                    $scope.drop(rec);

                    egCore.pcrud.retrieve('bre', $scope.lead_id)
                    .then(function(rec) {
                        $scope.lead.marc_xml = rec.marc();
                        $scope.merge_marc();
                    });
                }
                $scope.drop = function(rec) {
                    angular.forEach($scope.records, function(val, i) {
                        if (rec == $scope.records[i]) {
                            $scope.records.splice(i, 1);
                        }
                    });
                    $scope.merge_marc();
                }
                $scope.post_edit_inplace = function() {
                    $scope.editing_inplace = false;
                    updateOneRecord($scope.lead_id, $scope.lead.marc_xml);
                }

                $scope.cancel_edit_lead_inplace = function() {
                    $scope.editing_inplace = false;
                    $scope.lead.marc_xml = $scope.lead.orig_marc_xml;
                }

                $scope.edit_lead_inplace = function() {
                    $scope.editing_inplace = true;
                    let lead = { orig_marc_xml : $scope.lead.marc_xml };
                    $scope.lead = lead;
                }
                $scope.edit_lead = function() {
                    var lead = { marc_xml : $scope.lead.marc_xml };
                    var parentScope = $scope;

                    $uibModal.open({
                        templateUrl: './cat/bucket/record/t_edit_lead_record',
                        backdrop: 'static',
                        size: 'lg',
                        controller:
                            ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                            $scope.focusMe = true;
                            $scope.lead = lead;
                            $scope.dirty_flag = false;
                            $scope.ok = function() { $uibModalInstance.close() }
                            $scope.cancel = function () { $uibModalInstance.dismiss() }
                            $scope.on_save = function() {
                                parentScope.lead.marc_xml = $scope.lead.marc_xml;
                                parentScope.post_edit_inplace();
                            }
                        }]
                    }).result.then(function() {
                        $scope.lead.marc_xml = lead.marc_xml;
                    });
                };
            }]
        }).result.then(function (args) {
            if (!args.lead_id || !args.records.length) {
                if (bChannel) { $window.close(); } // called from the Angular bucket UI
                return;
            }

            function update_bib() {
                if (args.merge_profile) {
                    return updateOneRecord(args.lead_id, args.lead.marc_xml);
                } else {
                    return $q.when();
                }
            }

            update_bib().then(function() {
                egCore.net.request(
                    'open-ils.cat',
                    'open-ils.cat.biblio.records.merge',
                    egCore.auth.token(),
                    args.lead_id,
                    args.records.map(function(val) { return val.id; })
                ).then(function() {
                    if (bChannel) {
                        bChannel.postMessage({success:true});
                        // $window.open('/eg2/staff/catalog/record/' + args.lead_id);
                        $window.close(); // called from the Angular bucket UI
                    }
                });
            });
        });
    }

    $scope.showRecords = function(records) {
        // TODO: probably want to set a limit on the number of
        //       new tabs one could choose to open at once
        angular.forEach(records, function(rec) {
            var url = '/eg2/staff/catalog/record/' + rec.id;
            $timeout(function() { $window.open(url, '_blank') });
        });
    }

    $scope.batchEdit = function() {
        var url = '/eg2/staff/cat/marcbatch/bucket/' + $scope.bucketId;
        $timeout(function() { $window.open(url, '_blank') });
    }

    $scope.detachRecords = function(records) {
        bucketSvc.bucketNeedsRefresh = true;

        var ids = records.map(function(rec) { return rec.id; });

        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.delete.batch',
            egCore.auth.token(), 'biblio_record_entry', 
            bucketSvc.currentBucket.id(), ids

        ).then(
            null, // complete
            null, // error
            function(resp) {
                // Remove the items as the API responds so the UI can show
                // the count of items decreasing.
                bucketSvc.currentBucket.items(
                    bucketSvc.currentBucket.items().filter(function(item) {
                        return item.target_biblio_record_entry() != resp;
                    })
                );
            }
        ).then(drawBucket);
    }

    $scope.moveToPending = function(records) {
        angular.forEach(records, function(rec) {
            if (bucketSvc.pendingList.filter( // remove dupes
                function(r) {return r.id == rec.id}).length) return;
            bucketSvc.pendingList.push(rec);
        });
        $scope.detachRecords(records);
    }

    $scope.deleteRecordsFromCatalog = function(records) {
        egConfirmDialog.open(
            egCore.strings.CONFIRM_DELETE_RECORD_BUCKET_ITEMS_FROM_CATALOG,
            '',
            {}
        ).result.then(function() {
            var promises = [];
            angular.forEach(records, function(rec) {
                promises.push(bucketSvc.deleteRecordFromCatalog(rec.id));
            });
            bucketSvc.bucketNeedsRefresh = true;
            return $q.all(promises).then(function(results) {
                var failures = results.filter(function(result) {
                    return egCore.evt.parse(result);
                }).map(function(result) {
                    var evt = egCore.evt.parse(result);
                    if (evt) {
                        return { recordId: evt.payload, desc: evt.desc };
                    }
                });
                if (failures.length) {
                    $uibModal.open({
                        templateUrl: './cat/bucket/record/t_records_not_deleted',
                        backdrop: 'static',
                        controller :
                            ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                            $scope.failures = failures;
                            $scope.ok = function() { $uibModalInstance.close() }
                            $scope.cancel = function() { $uibModalInstance.dismiss() }
                            }]
                    });
                }
                drawBucket();
            });
        });
    }

    $scope.need_multiple_selected = function() {
        var items = $scope.gridControls.selectedItems();
        if (items.length > 1) return false;
        return true;
    }

    if ($routeParams.ids) {
        var recordIds = $routeParams.ids.split(',');
        var records = recordIds.map(function(id) { return {id: id}; });
        var bChannel = null;
        if (typeof BroadcastChannel != 'undefined') {
            bChannel = new BroadcastChannel("eg.merge_records_in_bucket_" + $scope.bucketId);
        }
        
        // Wait for the bucket to load before opening the modal
        drawBucket().then(function() {
            $timeout(function() {
                $scope.openRecordMergeDialog(records, bChannel);
            });
        });
    } else if ($scope.bucketId) {
        // Normal bucket view behavior
        drawBucket()['catch'](function() { $scope.forbidden = true });
    }
}])
