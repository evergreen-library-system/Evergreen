/**
 * Copy Buckets
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

angular.module('egCatCopyBuckets', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod', 'egUserMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/cat/bucket/copy/pending/:id', {
        templateUrl: './cat/bucket/copy/t_pending',
        controller: 'PendingCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/bucket/copy/pending', {
        templateUrl: './cat/bucket/copy/t_pending',
        controller: 'PendingCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/bucket/copy/view/:id', {
        templateUrl: './cat/bucket/copy/t_view',
        controller: 'ViewCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/bucket/copy/view', {
        templateUrl: './cat/bucket/copy/t_view',
        controller: 'ViewCtrl',
        resolve : resolver
    });

    // default page / bucket view
    $routeProvider.otherwise({redirectTo : '/cat/bucket/copy/view'});
})

/**
 * bucketSvc allows us to communicate between the pending
 * and view controllers.  It also allows us to cache
 * data for each so that data reloads are not needed on every 
 * tab click (i.e. route persistence).
 */
.factory('bucketSvc', ['$q','egCore', function($q,  egCore) { 

    var service = {
        allBuckets : [], // un-fleshed user buckets
        barcodeString : '', // last scanned barcode
        barcodeRecords : [], // last scanned barcode results
        currentBucket : null, // currently viewed bucket

        // per-page list collections
        pendingList : [],
        viewList  : [],

        // fetches all staff/copy buckets for the authenticated user
        // this function may only be called after startup.
        fetchUserBuckets : function(force) {
            if (this.allBuckets.length && !force) return;
            var self = this;
            return egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.container.retrieve_by_class.authoritative',
                egCore.auth.token(), egCore.auth.user().id(), 
                'copy', 'staff_client'
            ).then(function(buckets) { self.allBuckets = buckets });
        },

        createBucket : function(name, desc) {
            var deferred = $q.defer();
            var bucket = new egCore.idl.ccb();
            bucket.owner(egCore.auth.user().id());
            bucket.name(name);
            bucket.description(desc || '');
            bucket.btype('staff_client');

            egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.container.create',
                egCore.auth.token(), 'copy', bucket
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
                egCore.auth.token(), 'copy', bucket
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
            egCore.auth.token(), 'copy', id
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
    service.detachCopy = function(itemId) {
        var deferred = $q.defer();
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.delete',
            egCore.auth.token(), 'copy', itemId
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
            egCore.auth.token(), 'copy', id
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
.controller('CopyBucketCtrl',
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
            '/cat/bucket/copy/' + 
                $scope.tab + '/' + encodeURIComponent(id));
    }

    $scope.addToBucket = function(recs) {
        if (recs.length == 0) return;
        bucketSvc.bucketNeedsRefresh = true;

        angular.forEach(recs,
            function(rec) {
                var item = new egCore.idl.ccbi();
                item.bucket(bucketSvc.currentBucket.id());
                item.target_copy(rec.id);
                egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.container.item.create', 
                    egCore.auth.token(), 'copy', item
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
            templateUrl: './cat/bucket/copy/t_bucket_create',
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
                        '/cat/bucket/copy/' + $scope.tab + '/' + id);
                }
            );
        });
    }

    $scope.openEditBucketDialog = function() {
        $modal.open({
            templateUrl: './cat/bucket/copy/t_bucket_edit',
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
            templateUrl: './cat/bucket/copy/t_bucket_delete',
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
                $location.path('/cat/bucket/copy/view');
            });
        });
    }

    // retrieves the requested bucket by ID
    $scope.openSharedBucketDialog = function() {
        $modal.open({
            templateUrl: './cat/bucket/copy/t_load_shared',
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

}])

.controller('PendingCtrl',
       ['$scope','$routeParams','bucketSvc','egGridDataProvider', 'egCore',
function($scope,  $routeParams,  bucketSvc , egGridDataProvider,   egCore) {
    $scope.setTab('pending');

    var query;
    $scope.gridControls = {
        setQuery : function(q) {
            if (bucketSvc.pendingList.length)
                return {id : bucketSvc.pendingList};
            else
            return null;
        }
    }

    $scope.search = function() {
        bucketSvc.barcodeRecords = [];

        egCore.pcrud.search(
            'acp',
            {barcode : bucketSvc.barcodeString, deleted : 'f'},
            {}
        ).then(null, null, function(copy) {
            bucketSvc.pendingList.push(copy.id());
            $scope.gridControls.setQuery({id : bucketSvc.pendingList});
        });
    }

    $scope.resetPendingList = function() {
        bucketSvc.pendingList = [];
        $scope.gridControls.setQuery({});
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
    $scope.gridControls.setQuery();
}])

.controller('ViewCtrl',
       ['$scope','$q','$routeParams','$timeout','$window','$modal','bucketSvc','egCore','egUser',
        'egConfirmDialog',
function($scope,  $q , $routeParams , $timeout , $window , $modal , bucketSvc , egCore , egUser ,
         egConfirmDialog) {

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
                    function(i){return i.target_copy()}
                );
                if (ids.length) {
                    $scope.gridControls.setQuery({id : ids});
                } else {
                    $scope.gridControls.setQuery({});
                }
            }
        );
    }

    $scope.detachCopies = function(copies) {
        var promises = [];
        angular.forEach(copies, function(rec) {
            var item = bucketSvc.currentBucket.items().filter(
                function(i) {
                    return (i.target_copy() == rec.id)
                }
            );
            if (item.length)
                promises.push(bucketSvc.detachCopy(item[0].id()));
        });

        bucketSvc.bucketNeedsRefresh = true;
        return $q.all(promises).then(drawBucket);
    }

    $scope.spawnHoldingsEdit = function (copies) {
        var cp_list = []
        angular.forEach($scope.gridControls.selectedItems(), function (i) {
            cp_list.push(i.id);
        })

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            null, 'edit-these-copies', {
                record_id: 0, // false-y value for record_id disables record summary
                copies: cp_list,
                hide_vols : true,
                hide_copies : false
            }
        ).then(function(key) {
            if (key) {
                var url = egCore.env.basePath + 'cat/volcopy/' + key;
                $timeout(function() { $window.open(url, '_blank') });
            } else {
                alert('Could not create anonymous cache key!');
            }
        });
    }

    $scope.requestItems = function() {
        var copy_list = $scope.gridControls.selectedItems().map(
            function (i) {
                i.id;
            }
        );

        if (copy_list.length == 0) return;

        return $modal.open({
            templateUrl: './cat/catalog/t_request_items',
            animation: true,
            controller:
                   ['$scope','$modalInstance',
            function($scope , $modalInstance) {
                $scope.user = null;
                $scope.first_user_fetch = true;

                $scope.hold_data = {
                    hold_type : 'C',
                    copy_list : copy_list,
                    pickup_lib: egCore.org.get(egCore.auth.user().ws_ou()),
                    user      : egCore.auth.user().id()
                };

                egUser.get( $scope.hold_data.user ).then(function(u) {
                    $scope.user = u;
                    $scope.barcode = u.card().barcode();
                    $scope.user_name = egUser.format_name(u);
                    $scope.hold_data.user = u.id();
                });

                $scope.user_name = '';
                $scope.barcode = '';
                $scope.$watch('barcode', function (n) {
                    if (!$scope.first_user_fetch) {
                        egUser.getByBarcode(n).then(function(u) {
                            $scope.user = u;
                            $scope.user_name = egUser.format_name(u);
                            $scope.hold_data.user = u.id();
                        }, function() {
                            $scope.user = null;
                            $scope.user_name = '';
                            delete $scope.hold_data.user;
                        });
                    }
                    $scope.first_user_fetch = false;
                });

                $scope.ok = function(h) {
                    var args = {
                        patronid  : h.user,
                        hold_type : h.hold_type,
                        pickup_lib: h.pickup_lib.id(),
                        depth     : 0
                    };

                    egCore.net.request(
                        'open-ils.circ',
                        'open-ils.circ.holds.test_and_create.batch.override',
                        egCore.auth.token(), args, h.copy_list
                    );

                    $modalInstance.close();
                }

                $scope.cancel = function($event) {
                    $modalInstance.dismiss();
                    $event.preventDefault();
                }
            }]
        });
    }

    $scope.deleteCopiesFromCatalog = function(copies) {
        egConfirmDialog.open(
            egCore.strings.CONFIRM_DELETE_COPY_BUCKET_ITEMS_FROM_CATALOG,
            '', {}
        ).result.then(function() {
            var fleshed_copies = [];
            var promises = [];
            angular.forEach(copies, function(i) {
                promises.push(
                    egCore.net.request(
                        'open-ils.search',
                        'open-ils.search.asset.copy.fleshed2.retrieve',
                        i.id
                    ).then(function(copy) {
                        copy.ischanged(1);
                        copy.isdeleted(1);
                        fleshed_copies.push(copy);
                    })
                );
            });
            $q.all(promises).then(function() {
                egCore.net.request(
                    'open-ils.cat',
                    'open-ils.cat.asset.copy.fleshed.batch.update',
                    egCore.auth.token(), fleshed_copies, true
                ).then(function(resp) {
                    var evt = egCore.evt.parse(resp);
                    if (evt) {
                        egConfirmDialog.open(
                            egCore.strings.OVERRIDE_DELETE_COPY_BUCKET_ITEMS_FROM_CATALOG_TITLE,
                            egCore.strings.OVERRIDE_DELETE_COPY_BUCKET_ITEMS_FROM_CATALOG_BODY,
                            {'evt_desc': evt.desc}
                        ).result.then(function() {
                            egCore.net.request(
                                'open-ils.cat',
                                'open-ils.cat.asset.copy.fleshed.batch.update.override',
                                egCore.auth.token(), fleshed_copies, true,
                                { events: ['TITLE_LAST_COPY', 'COPY_DELETE_WARNING'] }
                            ).then(function(resp) {
                                bucketSvc.bucketNeedsRefresh = true;
                                drawBucket();
                            });
                        });
                    }
                    bucketSvc.bucketNeedsRefresh = true;
                    drawBucket();
                });
            });
        });
    }

    $scope.transferCopies = function(copies) {
        var xfer_target = egCore.hatch.getLocalItem('eg.cat.item_transfer_target');
        var copy_ids = copies.map(
            function(curr,idx,arr) {
                return curr.id;
            }
        );
        if (xfer_target) {
            egCore.net.request(
                'open-ils.cat',
                'open-ils.cat.transfer_copies_to_volume',
                egCore.auth.token(),
                xfer_target,
                copy_ids
            ).then(
                function(resp) { // oncomplete
                    var evt = egCore.evt.parse(resp);
                    if (evt) {
                        egConfirmDialog.open(
                            egCore.strings.OVERRIDE_TRANSFER_COPY_BUCKET_ITEMS_TO_MARKED_VOLUME_TITLE,
                            egCore.strings.OVERRIDE_TRANSFER_COPY_BUCKET_ITEMS_TO_MARKED_VOLUME_BODY,
                            {'evt_desc': evt.desc}
                        ).result.then(function() {
                            egCore.net.request(
                                'open-ils.cat',
                                'open-ils.cat.transfer_copies_to_volume.override',
                                egCore.auth.token(),
                                xfer_target,
                                copy_ids,
                                { events: ['TITLE_LAST_COPY', 'COPY_DELETE_WARNING'] }
                            ).then(function(resp) {
                                bucketSvc.bucketNeedsRefresh = true;
                                drawBucket();
                            });
                        });
                    } else {
                        bucketSvc.bucketNeedsRefresh = true;
                        drawBucket();
                    }
                },
                null, // onerror
                null // onprogress
            )
        }
    }

    // fetch the bucket;  on error show the not-allowed message
    if ($scope.bucketId) 
        drawBucket()['catch'](function() { $scope.forbidden = true });
}])
