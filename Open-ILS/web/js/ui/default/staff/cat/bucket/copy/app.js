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
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
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

    // apply last inventory data to fetched bucket items
    service.fetchRecentInventoryData = function(copy) {
        return egCore.pcrud.search('alci',
            {copy: copy.id},
            {flesh: 2, flesh_fields: {alci: ['inventory_workstation']}}
        ).then(function(alci) {
            return alci;
        });
    }

    return service;
}])

/**
 * Top-level controller.  
 * Hosts functions needed by all controllers.
 */
.controller('CopyBucketCtrl',
       ['$scope','$location','$q','$timeout','$uibModal',
        '$window','egCore','bucketSvc','egProgressDialog',
function($scope,  $location,  $q,  $timeout,  $uibModal,  
         $window,  egCore,  bucketSvc , egProgressDialog) {

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

        var ids = recs.map(function(rec) { return rec.id; });

        egProgressDialog.open();

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.create.batch',
            egCore.auth.token(), 'copy',
            bucketSvc.currentBucket.id(), ids
        ).then(
            function() {
                egProgressDialog.close();
            }, // complete
            null, // error
            function(resp) {
                // HACK: add the IDs of the added items so that the size
                // of the view list will grow (and update any UI looking at
                // the list size).  The data stored is inconsistent, but since
                // we are forcing a bucket refresh on the next rendering of
                // the view pane, the list will be repaired.
                bucketSvc.currentBucket.items().push(resp);
             }
        );
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
                        '/cat/bucket/copy/' + $scope.tab + '/' + id);
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
                $location.path('/cat/bucket/copy/view');
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

}])

.controller('PendingCtrl',
       ['$scope','$routeParams','bucketSvc','egGridDataProvider', 'egCore',
function($scope,  $routeParams,  bucketSvc , egGridDataProvider,   egCore) {
    $scope.setTab('pending');

    $scope.context = {
        copyNotFound : false,
        selectPendingBC : true
    };

    var query;
    $scope.gridControls = {
        setQuery : function(q) {
            if (bucketSvc.pendingList.length)
                return {id : bucketSvc.pendingList};
            else
            return null;
        },
        allItemsRetrieved : function() {
            $scope.context.selectPendingBC = true;
        }
    }

    $scope.handle_barcode_completion = function(barcode) {
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            egCore.auth.token(), egCore.auth.user().ws_ou(), 
            'asset', barcode)

        .then(function(resp) {
            // TODO: handle event during barcode lookup
            if (evt = egCore.evt.parse(resp)) {
                console.error(evt.toString());
                return $q.reject();
            }

            // no matching barcodes: return the barcode as entered
            // by the user (so that, e.g., checkout can fall back to
            // precat/noncat handling)
            if (!resp || !resp[0]) {
                return barcode;
            }

            // exactly one matching barcode: return it
            if (resp.length == 1) {
                return resp[0].barcode;
            }

            // multiple matching barcodes: let the user pick one 
            console.debug('multiple matching barcodes');
            var matches = [];
            var promises = [];
            var final_barcode;
            angular.forEach(resp, function(cp) {
                promises.push(
                    egCore.net.request(
                        'open-ils.circ',
                        'open-ils.circ.copy_details.retrieve',
                        egCore.auth.token(), cp.id
                    ).then(function(r) {
                        matches.push({
                            barcode: r.copy.barcode(),
                            title: r.mvr.title(),
                            org_name: egCore.org.get(r.copy.circ_lib()).name(),
                            org_shortname: egCore.org.get(r.copy.circ_lib()).shortname()
                        });
                    })
                );
            });
            return $q.all(promises)
            .then(function() {
                return $uibModal.open({
                    templateUrl: './circ/share/t_barcode_choice_dialog',
                    controller:
                        ['$scope', '$uibModalInstance',
                        function($scope, $uibModalInstance) {
                        $scope.matches = matches;
                        $scope.ok = function(barcode) {
                            $uibModalInstance.close();
                            final_barcode = barcode;
                        }
                        $scope.cancel = function() {$uibModalInstance.dismiss()}
                    }],
                }).result.then(function() { return final_barcode });
            })
        });
    }

    $scope.search = function() {
        bucketSvc.barcodeRecords = [];
        $scope.context.itemNotFound = false;

        // clear selection so re-selecting can have an effect
        $scope.context.selectPendingBC = false;

        return $scope.handle_barcode_completion(bucketSvc.barcodeString)
        .then(function(actual_barcode) {
            egCore.pcrud.search(
                'acp',
                {barcode : actual_barcode, deleted : 'f'},
                {}
            ).then(function(copy) {
                if (copy) {
                    bucketSvc.pendingList.push(copy.id());
                    $scope.gridControls.setQuery({id : bucketSvc.pendingList});
                    bucketSvc.barcodeString = ''; // clear form on valid copy
                } else {
                    $scope.context.itemNotFound = true;
                    $scope.context.selectPendingBC = true;
                }
            });
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
       ['$scope','$q','$routeParams','$timeout','$window','$uibModal','bucketSvc','egCore','egOrg','egUser',
        'ngToast','egConfirmDialog','egProgressDialog', 'egItem',
function($scope,  $q , $routeParams , $timeout , $window , $uibModal , bucketSvc , egCore , egOrg , egUser ,
         ngToast , egConfirmDialog , egProgressDialog, itemSvc) {

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
        bucketSvc.bucketNeedsRefresh = true;
        var ids = copies.map(function(rec) { return rec.id; });


        egProgressDialog.open();
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.delete.batch',
            egCore.auth.token(), 'copy',
            bucketSvc.currentBucket.id(), ids
        ).then(
            function() {
                egProgressDialog.close();
            }, // complete
            null, // error
            function(resp) {
                // Remove the items as the API responds so the UI can show
                // the count of items decreasing.
                bucketSvc.currentBucket.items(
                    bucketSvc.currentBucket.items().filter(function(item) {
                        return item.target_copy() != resp;
                    })
                );
            }
        ).then(drawBucket);
    }
    
    $scope.moveToPending = function(copies) {
        angular.forEach(copies, function(copy) {
            bucketSvc.pendingList.push(copy.id);
        });
        $scope.detachCopies(copies);
    }

    $scope.spawnHoldingsEdit = function() {
        $scope.spawnEdit(true, false);
    }

    $scope.spawnCallNumberEdit = function() {
        $scope.spawnEdit(false, true);
    }

    $scope.spawnEdit = function(hide_vols,hide_copies) {
        var cp_list = []
        angular.forEach($scope.gridControls.selectedItems(), function (i) {
            cp_list.push(i.id);
        });
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            null, 'edit-these-copies', {
                record_id: 0, // false-y value for record_id disables record summary
                copies: cp_list,
                hide_vols : hide_vols,
                hide_copies : hide_copies
            }
        ).then(function(key) {
            if (key) {
                var tab = (hide_vols === true) ? 'attrs' : 'holdings';
                var url = '/eg2/staff/cat/volcopy/' + tab + '/session/ ' + key;
                $timeout(function() { $window.open(url, '_blank') });
            } else {
                alert('Could not create anonymous cache key!');
            }
        });
    }

    $scope.print_labels = function() {
        var cp_list = []
        angular.forEach($scope.gridControls.selectedItems(), function (i) {
            cp_list.push(i.id);
        })

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            null, 'print-labels-these-copies', {
                copies : cp_list
            }
        ).then(function(key) {
            if (key) {
                var url = egCore.env.basePath + 'cat/printlabels/' + key;
                $timeout(function() { $window.open(url, '_blank') });
            } else {
                alert('Could not create anonymous cache key!');
            }
        });
    }

    $scope.showItems = function() {
        var cp_list = []
        angular.forEach($scope.gridControls.selectedItems(), function (i) {
            cp_list.push(i.id);
        })
        var url = egCore.env.basePath + '/cat/item/search/' + cp_list.join();
        $timeout(function() { $window.open(url, '_blank') });
    }

    $scope.requestItems = function() {
        var copy_list = $scope.gridControls.selectedItems().map(
            function (i) {
                return i.id;
            }
        );
        var record_list = $scope.gridControls.selectedItems().map(
            function (i) {
                return i['call_number.record.id'];
            }
        ).filter(function(v,i,s){ // dedup
            return s.indexOf(v) == i;
        });

        if (copy_list.length == 0) return;

        return $uibModal.open({
            templateUrl: './cat/catalog/t_request_items',
            backdrop: 'static',
            animation: true,
            controller:
                   ['$scope','$uibModalInstance',
            function($scope , $uibModalInstance) {
                $scope.user = null;
                $scope.first_user_fetch = true;

                $scope.hold_data = {
                    hold_type : 'C',
                    copy_list : copy_list,
                    record_list : record_list,
                    pickup_lib: egCore.org.get(egCore.auth.user().ws_ou()),
                    user      : egCore.auth.user().id(),
                    honor_user_settings : 
                        egCore.hatch.getLocalItem('eg.cat.request_items.honor_user_settings')
                };

                egUser.get( $scope.hold_data.user ).then(function(u) {
                    $scope.user = u;
                    $scope.barcode = u.card().barcode();
                    $scope.user_name = egUser.format_name(u);
                    $scope.hold_data.user = u.id();
                });

                $scope.user_name = '';
                $scope.barcode = '';
                function user_preferred_pickup_lib(u) {
                    var pickup_lib = u.home_ou();
                    angular.forEach(u.settings(), function (s) {
                        if (s.name() == "opac.default_pickup_location") {
                            pickup_lib = s.value();
                        }
                    });
                    return egOrg.get(pickup_lib);
                }
                $scope.$watch('barcode', function (n) {
                    if (!$scope.first_user_fetch) {
                        egUser.getByBarcode(n).then(function(u) {
                            $scope.user = u;
                            $scope.user_name = egUser.format_name(u);
                            $scope.hold_data.user = u.id();
                            if ($scope.hold_data.honor_user_settings) {
                                $scope.hold_data.pickup_lib = user_preferred_pickup_lib(u);
                            }
                        }, function() {
                            $scope.user = null;
                            $scope.user_name = '';
                            delete $scope.hold_data.user;
                        });
                    }
                    $scope.first_user_fetch = false;
                });
                $scope.$watch('hold_data.honor_user_settings', function (n) {
                    if (n && $scope.user) {
                        $scope.hold_data.pickup_lib = user_preferred_pickup_lib($scope.user);
                    } else {
                        $scope.hold_data.pickup_lib = egCore.org.get(egCore.auth.user().ws_ou());
                    }
                    egCore.hatch.setLocalItem('eg.cat.request_items.honor_user_settings',n);
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
                        egCore.auth.token(), args,
                        h.hold_type == 'T' ? h.record_list : h.copy_list,
                        { 'all' : 1, 'honor_user_settings' : h.honor_user_settings }
                    ).then(function(r) {
                        console.log('request result',r);
                        if (isNaN(r.result)) {
                            if (typeof r.result.desc != 'undefined') {
                                ngToast.danger(r.result.desc);
                            } else {
                                if (typeof r.result.last_event != 'undefined') {
                                    ngToast.danger(r.result.last_event.desc);
                                } else {
                                    ngToast.danger(egCore.strings.FAILURE_HOLD_REQUEST);
                                }
                            }
                        } else {
                            ngToast.success(egCore.strings.SUCCESS_HOLD_REQUEST);
                        }
                    });

                    $uibModalInstance.close();
                }

                $scope.cancel = function($event) {
                    $uibModalInstance.dismiss();
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
            egProgressDialog.open();
            var fleshed_copies = [];

            var chain = $q.when();
            angular.forEach(copies, function(i) {
                chain = chain.then(function() {
                     return egCore.net.request(
                        'open-ils.search',
                        'open-ils.search.asset.copy.fleshed2.retrieve',
                        i.id
                    ).then(function(copy) {
                        copy.ischanged(1);
                        copy.isdeleted(1);
                        fleshed_copies.push(copy);
                    });
                });
            });

            chain.finally(function() {
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
                    egProgressDialog.close();
                });
            });
        });
    }

    $scope.createCarouselFromBucket = function() {
        if (!bucketSvc?.currentBucket?.items()?.length) {
            return;
        }
        itemSvc.create_carousel_from_items(
            bucketSvc.currentBucket.items().map(function (item) {return item.target_copy()})
        );
    }

    $scope.transferCopies = function(copies) {
        var xfer_target = egCore.hatch.getLocalItem('eg.cat.transfer_target_vol');
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

    $scope.applyTags = function(copies) {
        return $uibModal.open({
            templateUrl: './cat/bucket/copy/t_apply_tags',
            backdrop: 'static',
            animation: true,
            controller:
                   ['$scope','$uibModalInstance',
            function($scope , $uibModalInstance) {

                $scope.tag_map = [];

                egCore.pcrud.retrieveAll('cctt', {order_by : { cctt : 'label' }}, {atomic : true}).then(function(list) {
                    $scope.tag_types = list;
                    $scope.tag_type = $scope.tag_types[0].code(); // just pick a default
                });

                $scope.getTags = function(val) {
                    return egCore.pcrud.search('acpt',
                        {
                            owner :  egCore.org.fullPath(egCore.auth.user().ws_ou(), true),
                            label : { 'startwith' : {
                                        transform: 'evergreen.lowercase',
                                        value : [ 'evergreen.lowercase', val ]
                                    }},
                            tag_type : $scope.tag_type
                        },
                        { order_by : { 'acpt' : ['label'] } }, { atomic: true }
                    ).then(function(list) {
                        return list.map(function(item) {
                            return { value: item.label(), display: item.label() + " (" + egCore.org.get(item.owner()).shortname() + ")" };
                        });
                    });
                }

                $scope.addTag = function() {
                    var tagLabel = $scope.selectedLabel;
                    // clear the typeahead
                    $scope.selectedLabel = "";

                    egCore.pcrud.search('acpt',
                        {
                            owner : egCore.org.fullPath(egCore.auth.user().ws_ou(), true),
                            label : tagLabel,
                            tag_type : $scope.tag_type
                        },
                        { order_by : { 'acpt' : ['label'] } }, { atomic: true }
                    ).then(function(list) {
                        if (list.length > 0) {
                            var newMap = new egCore.idl.acptcm();
                            newMap.isnew(1);
                            newMap.tag(egCore.idl.Clone(list[0]));
                            $scope.tag_map.push(newMap);
                        }
                    });
                }

                $scope.ok = function() {
                    var promises = [];
                    angular.forEach($scope.tag_map, function(map) {
                        if (map.isdeleted()) return;
                        angular.forEach(copies, function (cp) {
                            var m = new egCore.idl.acptcm();
                            m.isnew(1);
                            m.copy(cp.id);
                            m.tag(map.tag().id());
                            promises.push(egCore.pcrud.create(m));
                        });
                    });
                    return $q.all(promises).then(function(){$uibModalInstance.close()});
                }

                $scope.cancel = function($event) {
                    $uibModalInstance.dismiss();
                    $event.preventDefault();
                }
            }]
        });
    }

    // fetch the bucket;  on error show the not-allowed message
    if ($scope.bucketId) 
        drawBucket()['catch'](function() { $scope.forbidden = true });
}])
