/**
 * Hold Group (user) Buckets
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

angular.module('egCatBatchHoldBuckets', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod', 'egUserMod', 'egPatronSearchMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/cat/bucket/batch_hold/pending/:id', {
        templateUrl: './cat/bucket/batch_hold/t_pending',
        controller: 'PendingCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/bucket/batch_hold/pending', {
        templateUrl: './cat/bucket/batch_hold/t_pending',
        controller: 'PendingCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/bucket/batch_hold/view/:id', {
        templateUrl: './cat/bucket/batch_hold/t_view',
        controller: 'ViewCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/bucket/batch_hold/view', {
        templateUrl: './cat/bucket/batch_hold/t_view',
        controller: 'ViewCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/bucket/batch_hold/list', {
        templateUrl: './cat/bucket/batch_hold/t_list',
        controller: 'ListCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/bucket/batch_hold/event/:id', {
        templateUrl: './cat/bucket/batch_hold/t_event',
        controller: 'BucketEventCtrl',
        resolve : resolver
    });

    // default page / bucket view
    $routeProvider.otherwise({redirectTo : '/cat/bucket/batch_hold/list'});
})

.config(['ngToastProvider', function(ngToastProvider) {
  ngToastProvider.configure({
    verticalPosition: 'bottom',
    animation: 'fade'
  });
}])

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

        // for informational purposes
        eventList : [],

        // per-page list collections
        pendingList : [],
        viewList  : [],

        // fetches all staff/batch_hold buckets for the authenticated user
        // this function may only be called after startup.
        fetchUserBuckets : function(force) {
            if (this.allBuckets.length && !force) return;
            var self = this;
            return egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.container.retrieve_by_class.authoritative',
                egCore.auth.token(), egCore.auth.user().id(), 
                'user', 'hold_subscription'
            ).then(function(buckets) { self.allBuckets = buckets });
        },

        createBucket : function(name, desc, owning_lib, pub) {
            var deferred = $q.defer();
            var bucket = new egCore.idl.cub();
            bucket.owner(egCore.auth.user().id());
            bucket.name(name);
            bucket.pub(pub);
            bucket.description(desc || '');
            bucket.btype('hold_subscription');
            bucket.owning_lib(owning_lib.id());

            egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.container.create',
                egCore.auth.token(), 'user', bucket
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
            if (args.owning_lib) {
                if (typeof args.owning_lib == 'object') bucket.owning_lib(args.owning_lib.id());
                else bucket.owning_lib(args.owning_lib);
            }
            return egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.container.update',
                egCore.auth.token(), 'user', bucket
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
            egCore.auth.token(), 'user', id
        ).then(function(bucket) {
            var evt = egCore.evt.parse(bucket);
            if (evt) {
                console.debug(evt);
                deferred.reject(evt);
                return;
            }

            if (typeof bucket.owning_lib != 'object') {
                if (bucket.owning_lib()) {
                    bucket.owning_lib(egCore.org.get(bucket.owning_lib()));
                } else {
                    bucket.owning_lib(egCore.org.get(egCore.auth.user().ws_ou()));
                }
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
                bucket._owner_ou = bucket.owning_lib().shortname();
            });

            service.currentBucket = bucket;
            deferred.resolve(bucket);
        });

        return deferred.promise;
    }

    // deletes a single container item from a bucket by container item ID.
    // promise is rejected on failure
    service.detachUser = function(itemId) {
        var deferred = $q.defer();
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.delete',
            egCore.auth.token(), 'user', itemId
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
            egCore.auth.token(), 'user', id
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
.controller('BatchHoldBucketCtrl',
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
            '/cat/bucket/batch_hold/' + 
                $scope.tab + '/' + encodeURIComponent(id));
    }

    $scope.viewBucket = function(buckets) {
        console.debug('viewBucket', buckets[buckets.length - 1].id);
        $location.path('cat/bucket/batch_hold/view/' + encodeURIComponent(buckets[0].id));
    }

    $scope.addBucketUsers = function() {
        $location.path('/cat/bucket/batch_hold/pending/');
    }

    $scope.manageBucketEvents = function(buckets) {
        console.debug('manageBucketEvents', buckets[buckets.length - 1].id);
        $location.path('cat/bucket/batch_hold/event/' + encodeURIComponent(buckets[0].id));
    }

    $scope.addToBucket = function(recs) {
        if (recs.length == 0) return;
        bucketSvc.bucketNeedsRefresh = true;

        angular.forEach(recs,
            function(rec) {
                var item = new egCore.idl.cubi();
                item.bucket(bucketSvc.currentBucket.id());
                item.target_user(rec.id);
                egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.container.item.create', 
                    egCore.auth.token(), 'user', item, 1
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
        $uibModal.open({
            templateUrl: './cat/bucket/share/t_bucket_create',
            backdrop: 'static',
            controller: 
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.change_owner = true;
                $scope.args = {};
                $scope.args.owning_lib = egCore.org.get(egCore.auth.user().ws_ou());
                $scope.args.hold_sub = true;
                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        }).result.then(function (args) {
            if (!args || !args.name) return;
            bucketSvc.createBucket(args.name, args.desc, args.owning_lib, args.pub).then(
                function(id) {
                    if (!id) return;
                    bucketSvc.viewList = [];
                    bucketSvc.allBuckets = []; // reset
                    bucketSvc.currentBucket = null;
                    $location.path(
                        '/cat/bucket/batch_hold/' + $scope.tab + '/' + id);
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
                $scope.change_owner = true;
                $scope.args = {
                    hold_sub : true,
                    name : bucketSvc.currentBucket.name(),
                    desc : bucketSvc.currentBucket.description(),
                    pub : bucketSvc.currentBucket.pub() == 't',
                    owning_lib : bucketSvc.currentBucket.owning_lib() || egCore.org.get(egCore.auth.user().ws_ou())
                };
                $scope.ok = function(args) { 
                    if (!args) return;
                    $scope.actionPending = true;
                    args.pub = args.pub ? 't' : 'f';
                    // close the dialog after edit has completed
                    bucketSvc.bucketNeedsRefresh = true;
                    bucketSvc.editBucket(args).then(
                        function() { $uibModalInstance.close(); bucketSvc.fetchBucket(bucketSvc.currentBucket.id()) });
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
                $location.path('/cat/bucket/batch_hold/view');
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
       ['$scope','$routeParams','bucketSvc','egGridDataProvider', 'egCore','$uibModal',
function($scope,  $routeParams,  bucketSvc , egGridDataProvider,   egCore,  $uibModal) {
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


    $scope.addAllPending = function() {
        $scope.addToBucket($scope.gridControls.allItems());
        $scope.resetPendingList();
    }

    $scope.handle_barcode_completion = function(barcode) {
        return egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.get_barcodes',
            egCore.auth.token(), egCore.auth.user().ws_ou(), 
            'actor', barcode)

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
            angular.forEach(resp, function(usr) {
                promises.push(
                    egCore.net.request(
                        'open-ils.actor',
                        'open-ils.actor.user.fleshed.retrieve_by_barcode',
                        egCore.auth.token(), usr.barcode
                    ).then(function(r) {
                        matches.push({
                            barcode: r.card.barcode(),
                            title: r.last_given_name() + ', ' + r.first_given_name(),
                            org_name: egCore.org.get(r.home_ou()).name(),
                            org_shortname: egCore.org.get(r.home_ou()).shortname()
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
                'ac',
                {barcode : actual_barcode},
                {}
            ).then(function(card) {
                if (card) {
                    bucketSvc.pendingList.push(card.usr());
                    $scope.gridControls.setQuery({id : bucketSvc.pendingList});
                    bucketSvc.barcodeString = ''; // clear form on valid usr
                } else {
                    $scope.context.itemNotFound = true;
                    $scope.context.selectPendingBC = true;
                }
            });
        });
    }

    $scope.patron_search_dialog = function() {
        return $uibModal.open({
            templateUrl: './share/t_patron_selector',
            backdrop: 'static',
            size: 'lg',
            animation: true,
            controller:
                   ['$scope','$uibModalInstance','$controller',
            function($scope , $uibModalInstance , $controller) {
                angular.extend(this, $controller('BasePatronSearchCtrl', {$scope : $scope}));
                $scope.clearForm();
                $scope.need_one_selected = function() {
                    var items = $scope.gridControls.selectedItems();
                    return (items.length == 1) ? false : true
                }
                $scope.ok = function() {
                    var items = $scope.gridControls.selectedItems();
                    if (items.length == 1) {
                        $uibModalInstance.close(items[0].card().barcode());
                    } else {
                        $uibModalInstance.close()
                    }
                }
                $scope.cancel = function($event) {
                    $uibModalInstance.dismiss();
                    $event.preventDefault();
                }
            }]
        }).result.then(function(bc) {
            bucketSvc.barcodeString = bc;
            if (bc) $scope.search();
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
       ['$scope','$q','$routeParams','$timeout','$window','$uibModal','bucketSvc','egCore','egUser',
        'egConfirmDialog',
function($scope,  $q , $routeParams , $timeout , $window , $uibModal , bucketSvc , egCore , egUser ,
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
                    function(i){return i.target_user()}
                );
                if (ids.length) {
                    $scope.gridControls.setQuery({id : ids});
                } else {
                    $scope.gridControls.setQuery({});
                }
            }
        );
    }

    $scope.detachUsers = function(users) {
        var promises = [];
        angular.forEach(users, function(rec) {
            var item = bucketSvc.currentBucket.items().filter(
                function(i) {
                    return (i.target_user() == rec.id)
                }
            );
            if (item.length)
                promises.push(bucketSvc.detachUser(item[0].id()));
        });

        bucketSvc.bucketNeedsRefresh = true;
        return $q.all(promises).then(drawBucket);
    }
    
    $scope.moveToPending = function(users) {
        angular.forEach(users, function(usr) {
            bucketSvc.pendingList.push(usr.id);
        });
        $scope.detachUsers(users);
    }


    // fetch the bucket;  on error show the not-allowed message
    if ($scope.bucketId) 
        drawBucket()['catch'](function() { $scope.forbidden = true });
}])

.controller('BucketEventCtrl',
       ['$scope','$q','$routeParams','$timeout','$window','$uibModal','bucketSvc','egCore','egUser',
        'egConfirmDialog','egProgressDialog', 'ngToast', '$interpolate',
function($scope,  $q , $routeParams , $timeout , $window , $uibModal , bucketSvc , egCore , egUser ,
         egConfirmDialog,  egProgressDialog ,  ngToast ,  $interpolate) {

    $scope.setTab('event');
    $scope.bucketId = $routeParams.id;
    $scope.eventList = [];
    $scope.failedPatronList = [];

    var query;
    $scope.gridControls = {
        setSort  : function() {
            return [{run_date : 'desc'}];
        },
        setQuery : function(q) {
            if (q) query = q;
            return query;
        },
        itemRetrieved : function (item) {
            item.mappings = [];
            egCore.pcrud.retrieve(
                'mwde', item.target
            ).then(function (wide) {
                item.title = angular.fromJson(wide.title());
                item.author = angular.fromJson(wide.author());
            }).then(function () {
                egCore.pcrud.search(
                    'abhem', {batch_hold_event : item.id}
                ).then(null,null,function (m) {
                    if (m) item.mappings.push(m);
                });
            });
        }
    };

    function drawEventList() {
        $scope.gridControls.setQuery({bucket : $scope.bucketId});
    }

    $scope.rollbackEvent = function (items) {
        egConfirmDialog.open(
            egCore.strings.EVENT_ROLLBACK_TITLE, '', {}
        ).result.then(function() {
            var promises = [];
            egProgressDialog.open({max : 1, value : 0});
            angular.forEach(items, function (item) {
                promises.push(
                    egCore.net.request(
                        'open-ils.circ',
                        'open-ils.circ.holds.rollback.subscription_batch',
                        egCore.auth.token(), item.id
                    ).then(
                        null,
                        null,
                        function(res) { // each
                            egProgressDialog.update({
                                max   : res.total,
                                value : res.count
                            });
                        }
                    )
                )
            });

            $q.all(promises).finally(function() {
                egProgressDialog.close();
                drawEventList();
            });
        });

    }

    $scope.openCreateEventDialog = function () {
        var outer_scope = $scope;
        $uibModal.open({
            templateUrl: './cat/bucket/batch_hold/t_event_create',
            backdrop: 'static',
            controller: 
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.args = { target: null, override: true };
                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }
            }]
        }).result.then(function (args) {
            outer_scope.failedPatronList = [];

            if (!args || !args.target) {
                ngToast.warning(egCore.strings.EVENT_NO_TARGET);
                return;
            }

            var method = 'open-ils.circ.holds.test_and_create.subscription_batch';
            if (args.override) method += '.override';

            var success_count = 0;
            var total_count = -1; // we throw away the first result, which just gives us the max
            egProgressDialog.open({max : 1, value : 0});
            egCore.net.request(
                'open-ils.circ', method,
                egCore.auth.token(), {pickup_lib : egCore.auth.user().ws_ou()},
                bucketSvc.currentBucket.id(), args.target
            ).then(
                null,
                null,
                function(res) { // each
                    if (res.error && res.error == 'invalid_target') {
                        ngToast.warning(egCore.strings.EVENT_INVALID_TARGET);
                        return;
                    } else {
                        total_count++;
                    }
                    egProgressDialog.update({
                        max   : res.total,
                        value : res.count
                    });
                    if (res.patronid) {
                        success_count++;
                    } else if (res.failedpatronid) {
                        outer_scope.failedPatronList.push(res.failedpatronid);
                    }
                }
            ).finally(function() {
                if (total_count > 0) {
                    ngToast.create(
                        $interpolate(egCore.strings.EVENT_CREATE_SUMMARY)(
                            {success:success_count,total:total_count}
                        )
                    );
                }
                egProgressDialog.close();
                drawEventList();
            })
        });
    }

    /** Export the failed patron list as CSV.
     *  Flow of events:
     *  1. User clicks the 'download patrons' link
     *  2. All patrons (cards) are retrieved asychronously
     *  3. Once all data is all present and CSV-ized, the download
     *     attributes are linked to the href.
     *  4. The href .click() action is prgrammatically fired again,
     *     telling the browser to download the data, now that the
     *     data is available for download.
     *  5 Once downloaded, the href attributes are reset.
     */
    $scope.csvExportURL = '';
    $scope.csvExportFileName = '';
    $scope.csvExportInProgress = false;
    $scope.downloadFailed = function($event) {

        if ($scope.csvExportInProgress) {
            // This is secondary href click handler.  Give the
            // browser a moment to start the download, then reset
            // the CSV download attributes / state.
            $timeout(
                function() {
                    $scope.csvExportURL = '';
                    $scope.csvExportFileName = '';
                    $scope.csvExportInProgress = false;
                }, 500
            );
            return;
        }

        $scope.csvExportInProgress = true;

        // let the file name describe the grid
        $scope.csvExportFileName = 'failed_hold_patrons';

        var list_text = '';
        egCore.pcrud.search(
            'au',
            {id : $scope.failedPatronList},
            {flesh : 1, flesh_fields : {au : ["card"]}}
        ).then(
            function() {
                var blob = new Blob([list_text], {type : 'text/plain'});
                $scope.csvExportURL =
                    ($window.URL || $window.webkitURL).createObjectURL(blob);

                // Fire the 2nd click event now that the browser has
                // information on how to download the CSV file.
                $timeout(function() {$event.target.click()});
            },null,
            function (u) {
                list_text += u.card().barcode() + '\n';
            }
        );
    }

    // fetch the bucket;  on error show the not-allowed message
    if ($scope.bucketId && 
        (!bucketSvc.currentBucket || 
            bucketSvc.currentBucket.id() != $scope.bucketId)) {
        // user has accessed this page cold with a bucket ID.
        // fetch the bucket for display, then set the totalCount
        // (also for display), but avoid fully fetching the bucket,
        // since it's premature, in this UI.
        bucketSvc.fetchBucket($scope.bucketId).then(drawEventList);
    } else {
        $timeout(drawEventList);
    }
}])

.controller('ListCtrl',
       ['$scope','$q','$location','$timeout','$window','$uibModal','bucketSvc','egCore','egUser',
        'egConfirmDialog',
function($scope,  $q , $location , $timeout , $window , $uibModal , bucketSvc , egCore , egUser ,
         egConfirmDialog) {

    $scope.setTab('list');

    var query;
    $scope.gridControls = {
        setSort  : function() {
            return ['name'];
        },
        setQuery : function(q) {
            if (q) query = q;
            return query;
        },
        activateItem : function (item) {
            $location.path(
                '/cat/bucket/batch_hold/view/' + item.id );
        }
    };

    function drawList() {
        $scope.gridControls.setQuery({btype : 'hold_subscription'});
    }

    $timeout(drawList);
}])

