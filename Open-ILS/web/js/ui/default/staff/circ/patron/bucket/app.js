/**
 * User Buckets
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

angular.module('egCatUserBuckets', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod', 'egUserMod', 'egUserBucketMod', 'ngToast'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/circ/patron/bucket/add/:id', {
        templateUrl: './circ/patron/bucket/t_pending',
        controller: 'PendingCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/bucket/add', {
        templateUrl: './circ/patron/bucket/t_pending',
        controller: 'PendingCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/bucket/view/:id', {
        templateUrl: './circ/patron/bucket/t_view',
        controller: 'ViewCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/patron/bucket/view', {
        templateUrl: './circ/patron/bucket/t_view',
        controller: 'ViewCtrl',
        resolve : resolver
    });

    // default page / bucket view
    $routeProvider.otherwise({redirectTo : '/circ/patron/bucket/view'});
})

/**
 * Top-level controller.  
 * Hosts functions needed by all controllers.
 */
.controller('UserBucketCtrl',
       ['$scope','$location','$q','$timeout','$uibModal',
        '$window','egCore','bucketSvc','ngToast','egProgressDialog',
function($scope,  $location,  $q,  $timeout,  $uibModal,  
         $window,  egCore,  bucketSvc , ngToast , egProgressDialog) {

    $scope.bucketSvc = bucketSvc;
    $scope.bucket = function() { return bucketSvc.currentBucket }

    // tabs: add, view
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
            '/circ/patron/bucket/' + 
                $scope.tab + '/' + encodeURIComponent(id));
    }

    $scope.addToBucket = function(recs) {
        if (recs.length == 0) return;
        bucketSvc.bucketNeedsRefresh = true;

        egProgressDialog.open();
        var ids = recs.map(function(rec) {
            $scope.removeFromPendingList(rec.id);
            return rec.id;
        });

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.container.item.create.batch',
            egCore.auth.token(), 'user',
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
        //re-draw the pending list
        $scope.resetPendingListQuery();
    }

    $scope.openCreateBucketDialog = function() {
        $uibModal.open({
            templateUrl: './circ/patron/bucket/t_bucket_create',
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
                        '/circ/patron/bucket/' + $scope.tab + '/' + id);
                }
            );
        });
    }

    $scope.openEditBucketDialog = function() {
        $uibModal.open({
            templateUrl: './circ/patron/bucket/t_bucket_edit',
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
            templateUrl: './circ/patron/bucket/t_bucket_delete',
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
                $location.path('/circ/patron/bucket/view');
            });
        });
    }

    // retrieves the requested bucket by ID
    $scope.openSharedBucketDialog = function() {
        $uibModal.open({
            templateUrl: './circ/patron/bucket/t_load_shared',
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
       ['$scope','$routeParams','bucketSvc','egGridDataProvider', 'egCore','ngToast','$q',
function($scope,  $routeParams,  bucketSvc , egGridDataProvider,   egCore , ngToast , $q) {
    $scope.setTab('add');

    var query;
    $scope.gridControls = {
        setQuery : function(q) {
            if (bucketSvc.pendingList.length)
                return {id : bucketSvc.pendingList};
            else
            return null;
        }
    }

    $scope.$watch('barcodesFromFile', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            var barcodes = [];
            // $scope.resetPendingList(); // ??? Add instead of replace
            angular.forEach(newVal.split(/\n/), function(line) {
                if (!line) return;
                // scrub any leading or trailing spaces or commas from the barcode,
                // leaving any internal spaces intact
                line = line.replace(/^(\s|,)+/, '');
                line = line.replace(/(\s|,)+$/, '');
                barcodes.push(line);

            });
            egCore.pcrud.search(
                'ac',
                {barcode : barcodes},
                {}
            ).then(
                function() {
                    $scope.gridControls.setQuery({id : bucketSvc.pendingList});
                },
                null, 
                function(card) {
                    bucketSvc.pendingList.push(card.usr());
                }
            );
        }
    });

    $scope.search = function() {
        bucketSvc.barcodeRecords = [];

        egCore.pcrud.search(
            'ac',
            {barcode : bucketSvc.barcodeString},
            {}
        ).then(null, null, function(card) {
            bucketSvc.pendingList.push(card.usr());
            $scope.gridControls.setQuery({id : bucketSvc.pendingList});
        });
        bucketSvc.barcodeString = '';
    }

    $scope.resetPendingList = function() {
        bucketSvc.pendingList = [];
        $scope.gridControls.setQuery({});
    }

    $scope.$parent.resetPendingList = $scope.resetPendingList;

    //remove entry from PendingList
    $scope.removeFromPendingList = function(usr) {
        const index = bucketSvc.pendingList.indexOf(usr);
        if (index > -1) {
            bucketSvc.pendingList.splice(index,1);
        }
    }
    $scope.$parent.removeFromPendingList = $scope.removeFromPendingList;

    $scope.resetPendingListQuery = function() {
        $scope.gridControls.setQuery({id : bucketSvc.pendingList});
    }
    $scope.$parent.resetPendingListQuery = $scope.resetPendingListQuery;

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
        'egConfirmDialog','egPerm','ngToast','$filter',
function($scope,  $q , $routeParams , $timeout , $window , $uibModal , bucketSvc , egCore , egUser ,
         egConfirmDialog , egPerm , ngToast , $filter) {

    $scope.setTab('view');
    $scope.bucketId = $routeParams.id;

    var query;
    $scope.gridControls = {
        setQuery : function(q) {
            if (q) query = q;
            return query;
        }
    };

    $scope.modifyStatcats = function() {
        bucketSvc.bucketNeedsRefresh = true;

        $uibModal.open({
            templateUrl: './circ/patron/bucket/t_update_statcats',
            backdrop: 'static',
            controller: 
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.running = false;
                $scope.complete = false;
                $scope.states = [];

                $scope.modal = $uibModalInstance;
                $scope.ok = function(args) { $uibModalInstance.close() }
                $scope.cancel = function () { $uibModalInstance.dismiss() }

                $scope.current_bucket = bucketSvc.currentBucket;

                egCore.net.request(
                    'open-ils.circ',
                    'open-ils.circ.stat_cat.actor.retrieve.all',
                    egCore.auth.token(), egCore.auth.user().ws_ou()
                ).then(function(cats) {
                    cats = cats.sort(function(a, b) {
                        return a.name() < b.name() ? -1 : 1});
                    angular.forEach(cats, function(cat) {
                        cat.new_value = '';
                        cat.allow_freetext(parseInt(cat.allow_freetext())); // just to be sure
                        cat.entries(
                            cat.entries().sort(function(a,b) {
                                return a.value() < b.value() ? -1 : 1
                            })
                        );
                    });
                    $scope.stat_cats = cats;
                });

                // This handels the progress magic instead of a normal close handler
                $scope.$on('modal.closing', function(event, reason, closed) {
                    if (!closed) return; // dismissed
                    if ($scope.complete) return; // already done

                    $scope.running = true;

                    var changes = {remove:[], apply:{}};
                    angular.forEach($scope.stat_cats, function (sc) {
                        if (sc.delete_me) {
                            changes.remove.push(sc.id());
                        } else if (sc.new_value) {
                            changes.apply[sc.id()] = sc.new_value;
                        }
                    });

                    egCore.net.request(
                        'open-ils.actor',
                        'open-ils.actor.container.user.batch_statcat_apply',
                        egCore.auth.token(), bucketSvc.currentBucket.id(), changes
                    ).then(
                        function () {
                            $scope.complete = true;
                            $scope.modal.close();
                            drawBucket();
                        },
                        function (err) { console.log('User edit error: ' + err); },
                        function (p) {
                            if (p.error) {
                                ngToast.warning(p.error);
                            }
                            if (p.stage == 'COMPLETE') return;

                            p.label = egCore.strings[p.stage];
                            if (!p.max) {
                                p.max = 1;
                                p.count = 1;
                            }
                            $scope.states[p.ord] = p;
                        }
                    );

                    return event.preventDefault();
                });
            }]
        });
    }


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

    $scope.no_update_perms = true;
    $scope.noUpdatePerms = function () { return $scope.no_update_perms; }

    egPerm.hasPermHere(['UPDATE_USER']).then(
        function (hash) {
            if (Object.keys(hash).length == 0) return;

            var one_false = false;
            angular.forEach(hash, function(has) {
                if (!has) one_false = true;
            });

            if (!one_false) $scope.no_update_perms = false;
        }
    );

    function annotate_groups(grps) {
        angular.forEach(grps, function (g) {
            if (!g.hasOwnProperty('cannot_use')) {
                if (g.usergroup() == 'f') {
                    g.cannot_use = true;
                } else if (g.application_perm) {
                    egPerm.hasPermHere(['EVERYTHING',g.application_perm]).then(
                        function (hash) {
                            if (Object.keys(hash).length == 0) {
                                g.cannot_use = true;
                                return;
                            }

                            var one_false = false;
                            angular.forEach(hash, function(has) {
                                if (has) g.cannot_use = false;
                            });
                        }
                    );
                } else {
                    g.cannot_use = false;
                }
            }
        });
    }

    $scope.viewChangesets = function() {
        bucketSvc.bucketNeedsRefresh = true;

        $uibModal.open({
            templateUrl: './circ/patron/bucket/t_changesets',
            backdrop: 'static',
            controller: 
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.running = false;
                $scope.complete = false;
                $scope.states = [];

                $scope.focusMe = true;
                $scope.modal = $uibModalInstance;
                $scope.ok = function() { $uibModalInstance.close() }
                $scope.cancel = function () { $uibModalInstance.dismiss() }

                $scope.current_bucket = bucketSvc.currentBucket;
                $scope.fieldset_groups = [];

                $scope.deleteChangeset = function (grp) {
                    egCore.pcrud.remove(grp).then(
                        function () {
                            if (grp.rollback_group()) {
                                egCore.pcrud
                                    .retrieve('afsg',grp.rollback_group())
                                    .then(function(g) {
                                        egCore.pcrud.remove(g)
                                            .then( function () { refresh_groups() } );
                                    });
                            }
                        }
                    );
                    return event.preventDefault();
                }

                function refresh_groups () {
                    $scope.fieldset_groups = [];
                    egCore.pcrud.search('afsg',{
                        rollback_group : { '>' : 0 },
                        container      : bucketSvc.currentBucket.id(),
                        container_type : 'user'
                    } ).then( null,null,function(g) {
                        $scope.fieldset_groups.push(g);
                    });
                }
                refresh_groups();

            }]
        });
    }

    $scope.applyRollback = function() {
        bucketSvc.bucketNeedsRefresh = true;

        $uibModal.open({
            templateUrl: './circ/patron/bucket/t_rollback',
            controller: 
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.running = false;
                $scope.complete = false;
                $scope.states = [];
                $scope.revert_me = null;

                $scope.focusMe = true;
                $scope.modal = $uibModalInstance;
                $scope.ok = function(args) { $uibModalInstance.close() }
                $scope.cancel = function () { $uibModalInstance.dismiss() }

                $scope.current_bucket = bucketSvc.currentBucket;
                $scope.revertable_fieldset_groups = [];

                egCore.pcrud.search('afsg',{
                    rollback_group : { '>' : 0},
                    rollback_time  : null,
                    container      : bucketSvc.currentBucket.id(),
                    container_type : 'user'
                } ).then( null,null,function(g) {
                    $scope.revertable_fieldset_groups.push(g);
                });

                // This handels the progress magic instead of a normal close handler
                $scope.$on('modal.closing', function(event, reason, closed) {
                    if (!$scope.revert_me) return;
                    if (!closed) return; // dismissed
                    if ($scope.complete) return; // already done

                    $scope.running = true;

                    var last_stage = '';
                    egCore.net.request(
                        'open-ils.actor',
                        'open-ils.actor.container.user.apply_rollback',
                        egCore.auth.token(), bucketSvc.currentBucket.id(), $scope.revert_me.id()
                    ).then(
                        function () {
                            $scope.complete = true;
                            $scope.modal.close();
                            drawBucket();
                        },
                        function (err) { console.log('User edit error: ' + err); },
                        function (p) {
                            last_stage = p.stage;
                            if (p.error) {
                                ngToast.warning(p.error);
                            }
                            if (p.stage == 'COMPLETE') return;

                            p.label = egCore.strings[p.stage];
                            if (!p.max) {
                                p.max = 1;
                                p.count = 1;
                            }
                            $scope.states[p.ord] = p;
                        }
                    ).then(function() {
                        if (last_stage != 'COMPLETE')
                            ngToast.warning(egCore.strings.BATCH_FAILED);
                    });

                    return event.preventDefault();
                });
            }]
        });
    }

    $scope.updateAllUsers = function() {
        bucketSvc.bucketNeedsRefresh = true;

        $uibModal.open({
            templateUrl: './circ/patron/bucket/t_update_all',
            backdrop: 'static',
            controller: 
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.running = false;
                $scope.complete = false;
                $scope.states = [];
                $scope.home_ou_name = '';
                $scope.args = {home_ou:null};
                $scope.focusMe = true;
                $scope.modal = $uibModalInstance;
                $scope.ok = function(args) { $uibModalInstance.close() }
                $scope.cancel = function () { $uibModalInstance.dismiss() }

                $scope.disable_home_org = function(org_id) {
                    if (!org_id) return;
                    var org = egCore.org.get(org_id);
                    return (
                        org &&
                        org.ou_type() &&
                        org.ou_type().can_have_users() == 'f'
                    );
                }

                $scope.pgt_depth = function(grp) {
                    var d = 0;
                    while (grp = egCore.env.pgt.map[grp.parent()]) d++;
                    return d;
                }

                if (egCore.env.cnal) {
                    $scope.net_access_levels = egCore.env.cnal.list;
                } else {
                    egCore.pcrud.retrieveAll('cnal', {}, {atomic : true})
                    .then(function(types) {
                        egCore.env.absorbList(types, 'cnal')
                        $scope.net_access_levels = egCore.env.cnal.list;
                    });
                }

                if (egCore.env.pgt) {
                    $scope.profiles = egCore.env.pgt.list;
                    annotate_groups($scope.profiles);
                } else {
                    egCore.pcrud.search('pgt', {parent : null}, 
                        {flesh : -1, flesh_fields : {pgt : ['children']}}
                    ).then(
                        function(tree) {
                            egCore.env.absorbTree(tree, 'pgt')
                            $scope.profiles = egCore.env.pgt.list;
                            annotate_groups($scope.profiles);
                        }
                    );
                }

                $scope.unset_field = function (event,field) {
                    $scope.args[field] = null;
                    return event.preventDefault();
                }

                // This handels the progress magic instead of a normal close handler
                $scope.$on('modal.closing', function(event, reason, closed) {
                    if (!$scope.args || !$scope.args.name) return;
                    if (!closed) return; // dismissed
                    if ($scope.complete) return; // already done

                    $scope.running = true;

                    // XXX fix up $scope.args values here
                    if ($scope.args.home_ou) {
                        $scope.args.home_ou = $scope.args.home_ou.id();
                    }
                    if ($scope.args.net_access_level) {
                        $scope.args.net_access_level = $scope.args.net_access_level.id();
                    }
                    if ($scope.args.profile) {
                        $scope.args.profile = $scope.args.profile.id();
                    }
                    if ($scope.args.expire_date) {
                        $scope.args.expire_date = $scope.args.expire_date.toJSON().substr(0,10);
                    }

                    for (var key in $scope.args) {
                        if (!$scope.args[key] && $scope.args[key] !== 0) {
                            delete $scope.args[key];
                        }
                    }

                    var last_stage = '';
                    egCore.net.request(
                        'open-ils.actor',
                        'open-ils.actor.container.user.batch_edit',
                        egCore.auth.token(), bucketSvc.currentBucket.id(), $scope.args.name, $scope.args
                    ).then(
                        function () {
                            $scope.complete = true;
                            $scope.modal.close();
                            drawBucket();
                        },
                        function (err) { console.log('User edit error: ' + err); },
                        function (p) {
                            last_stage = p.stage;
                            if (p.error) {
                                ngToast.warning(p.error);
                            }
                            if (p.stage == 'COMPLETE') return;

                            p.label = egCore.strings[p.stage];
                            if (!p.max) {
                                p.max = 1;
                                p.count = 1;
                            }
                            $scope.states[p.ord] = p;
                        }
                    ).then(function() {
                        if (last_stage != 'COMPLETE')
                            ngToast.warning(egCore.strings.BATCH_FAILED);
                    });

                    return event.preventDefault();
                });
            }]
        });
    }

    $scope.no_delete_perms = true;
    $scope.noDeletePerms = function () { return $scope.no_delete_perms; }

    egPerm.hasPermHere(['UPDATE_USER','DELETE_USER']).then(
        function (hash) {
            if (Object.keys(hash).length == 0) return;

            var one_false = false;
            angular.forEach(hash, function(has) {
                if (!has) one_false = true;
            });

            if (!one_false) $scope.no_delete_perms = false;
        }
    );

    $scope.deleteAllUsers = function() {
        bucketSvc.bucketNeedsRefresh = true;

        $uibModal.open({
            templateUrl: './circ/patron/bucket/t_delete_all',
            backdrop: 'static',
            controller: 
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.running = false;
                $scope.complete = false;
                $scope.states = [];
                $scope.args = {};
                $scope.focusMe = true;
                $scope.modal = $uibModalInstance;
                $scope.ok = function(args) { $uibModalInstance.close() }
                $scope.cancel = function () { $uibModalInstance.dismiss() }

                // This handels the progress magic instead of a normal close handler
                $scope.$on('modal.closing', function(event, reason, closed) {
                    if (!$scope.args || !$scope.args.name) return;
                    if (!closed) return; // dismissed
                    if ($scope.complete) return; // already done

                    $scope.running = true;

                    var last_stage = '';
                    egCore.net.request(
                        'open-ils.actor',
                        'open-ils.actor.container.user.batch_delete',
                        egCore.auth.token(), bucketSvc.currentBucket.id(), $scope.args.name, { deleted : 't' }
                    ).then(
                        function () {
                            $scope.complete = true;
                            $scope.modal.close();
                            drawBucket();
                        },
                        function (err) { console.log('User deletion error: ' + err); },
                        function (p) {
                            last_stage = p.stage;
                            if (p.error) {
                                ngToast.warning(p.error);
                            }
                            if (p.stage == 'COMPLETE') return;

                            p.label = egCore.strings[p.stage];
                            if (!p.max) {
                                p.max = 1;
                                p.count = 1;
                            }
                            $scope.states[p.ord] = p;
                        }
                    ).then(function() {
                        if (last_stage != 'COMPLETE')
                            ngToast.warning(egCore.strings.BATCH_FAILED);
                    });

                    return event.preventDefault();
                });
            }]
        });

    }

    $scope.detachUsers = function(users) {
        var promise = $q.when();

        $scope.running = true;
        $scope.progress = {
            count: 0,
            max: users.length
        };

        angular.forEach(users, function(rec) {
            var item = bucketSvc.currentBucket.items().filter(
                function(i) {
                    return (i.target_user() == rec.id)
                }
            );
            if (item.length) {
                promise = promise.then(function() {
                    return bucketSvc.detachUser(item[0].id())
                    .then(function() { $scope.progress.count++; });
                });
            }
        });

        bucketSvc.bucketNeedsRefresh = true;
        return promise
            .then(function() { $scope.running = false; })
            .then(drawBucket);
    }

    $scope.spawnUserEdit = function (users) {
        angular.forEach($scope.gridControls.selectedItems(), function (i) {
            var url = egCore.env.basePath + 'circ/patron/' + i.id + '/edit';
            $timeout(function() { $window.open(url, '_blank') });
        })
    }

    // fetch the bucket;  on error show the not-allowed message
    if ($scope.bucketId) 
        drawBucket()['catch'](function() { $scope.forbidden = true });
}])
