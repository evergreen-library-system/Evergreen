/**
 * Item Display
 */

angular.module('egItemStatus', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod'])

.filter('boolText', function(){
    return function (v) {
        return v == 't';
    }
})

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    // search page shows the list view by default
    $routeProvider.when('/cat/item/search', {
        templateUrl: './cat/item/t_list',
        controller: 'ListCtrl',
        resolve : resolver
    });

    // search page shows the list view by default
    $routeProvider.when('/cat/item/search/:idList', {
        templateUrl: './cat/item/t_list',
        controller: 'ListCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/item/:id', {
        templateUrl: './cat/item/t_view',
        controller: 'ViewCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/item/:id/:tab', {
        templateUrl: './cat/item/t_view',
        controller: 'ViewCtrl',
        resolve : resolver
    });

    // default page / bucket view
    $routeProvider.otherwise({redirectTo : '/cat/item/search'});
})

.factory('itemSvc', 
       ['egCore',
function(egCore) {

    var service = {
        copies : [], // copy barcode search results
        index : 0 // search grid index
    };

    service.flesh = {   
        flesh : 3, 
        flesh_fields : {
            acp : ['call_number','location','status','location','floating'],
            acn : ['record','prefix','suffix'],
            bre : ['simple_record','creator','editor']
        },
        select : { 
            // avoid fleshing MARC on the bre
            // note: don't add simple_record.. not sure why
            bre : ['id','tcn_value','creator','editor'],
        } 
    }

    // resolved with the last received copy
    service.fetch = function(barcode, id, noListDupes) {
        var promise;

        if (barcode) {
            promise = egCore.pcrud.search('acp', 
                {barcode : barcode, deleted : 'f'}, service.flesh);
        } else {
            promise = egCore.pcrud.retrieve('acp', id, service.flesh);
        }

        var lastRes;
        return promise.then(
            function() {return lastRes},
            null, // error

            // notify reads the stream of copies, one at a time.
            function(copy) {

                var flatCopy;
                if (noListDupes) {
                    // use the existing copy if possible
                    flatCopy = service.copies.filter(
                        function(c) {return c.id == copy.id()})[0];
                }

                if (!flatCopy) {
                    flatCopy = egCore.idl.toHash(copy, true);
                    flatCopy.index = service.index++;
                    service.copies.unshift(flatCopy);
                }

                return lastRes = {
                    copy : copy, 
                    index : flatCopy.index
                }
            }
        );
    }

    return service;
}])

/**
 * Search bar along the top of the page.
 * Parent scope for list and detail views
 */
.controller('SearchCtrl', 
       ['$scope','$location','egCore','egGridDataProvider','itemSvc',
function($scope , $location , egCore , egGridDataProvider , itemSvc) {
    $scope.args = {}; // search args

    // sub-scopes (search / detail-view) apply their version 
    // of retrieval function to $scope.context.search
    // and display toggling via $scope.context.toggleDisplay
    $scope.context = {
        selectBarcode : true
    };

    $scope.toggleView = function($event) {
        $scope.context.toggleDisplay();
        $event.preventDefault(); // avoid form submission
    }
}])

/**
 * List view - grid stuff
 */
.controller('ListCtrl', 
       ['$scope','$q','$routeParams','$location','$timeout','egCore','egGridDataProvider','itemSvc',
function($scope , $q , $routeParams , $location , $timeout , egCore , egGridDataProvider , itemSvc) {
    var copyId = [];
    var cp_list = $routeParams.idList;
    if (cp_list) {
        copyId = cp_list.split(',');
    }

    $scope.context.page = 'list';

    /*
    var provider = egGridDataProvider.instance();
    provider.get = function(offset, count) {
    }
    */

    $scope.gridDataProvider = egGridDataProvider.instance({
        get : function(offset, count) {
            //return provider.arrayNotifier(itemSvc.copies, offset, count);
            return this.arrayNotifier(itemSvc.copies, offset, count);
        }
    });

    // If a copy was just displayed in the detail view, ensure it's
    // focused in the list view.
    var selected = false;
    var copyGrid = $scope.gridControls = {
        itemRetrieved : function(item) {
            if (selected || !itemSvc.copy) return;
            if (itemSvc.copy.id() == item.id) {
                copyGrid.selectItems([item.index]);
                selected = true;
            }
        }
    };

    $scope.$watch('barcodesFromFile', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            $scope.args.barcode = '';
            var barcodes = [];

            angular.forEach(newVal.split(/\n/), function(line) {
                if (!line) return;
                // scrub any trailing spaces or commas from the barcode
                line = line.replace(/(.*?)($|\s.*|,.*)/,'$1');
                barcodes.push(line);
            });

            itemSvc.fetch(barcodes).then(
                function() {
                    copyGrid.refresh();
                    copyGrid.selectItems([itemSvc.copies[0].index]);
                }
            );
        }
    });

    $scope.context.search = function(args) {
        if (!args.barcode) return;
        $scope.context.itemNotFound = false;
        itemSvc.fetch(args.barcode).then(function(res) {
            if (res) {
                copyGrid.refresh();
                copyGrid.selectItems([res.index]);
                $scope.args.barcode = '';
            } else {
                $scope.context.itemNotFound = true;
            }
            $scope.context.selectBarcode = true;
        })
    }

    $scope.context.toggleDisplay = function() {
        var item = copyGrid.selectedItems()[0];
        if (item) 
            $location.path('/cat/item/' + item.id);
    }

    $scope.context.show_triggered_events = function() {
        var item = copyGrid.selectedItems()[0];
        if (item) 
            $location.path('/cat/item/' + item.id + '/triggered_events');
    }

    if (copyId.length > 0) {
        itemSvc.fetch(null,copyId).then(
            function() {
                copyGrid.refresh();
            }
        );
    }

}])

/**
 * Detail view -- shows one copy
 */
.controller('ViewCtrl', 
       ['$scope','$q','$location','$routeParams','$timeout','$window','egCore','itemSvc','egBilling',
function($scope , $q , $location , $routeParams , $timeout , $window , egCore , itemSvc , egBilling) {
    var copyId = $routeParams.id;
    $scope.tab = $routeParams.tab || 'summary';
    $scope.context.page = 'detail';
    $scope.summaryRecord = null;

    $scope.edit = false;
    if ($scope.tab == 'edit') {
        $scope.tab = 'summary';
        $scope.edit = true;
    }


    // use the cached record info
    if (itemSvc.copy)
        $scope.recordId = itemSvc.copy.call_number().record().id();

    function loadCopy(barcode) {
        $scope.context.itemNotFound = false;

        // Avoid re-fetching the same copy while jumping tabs.
        // In addition to being quicker, this helps to avoid flickering
        // of the top panel which is always visible in the detail view.
        //
        // 'barcode' represents the loading of a new item - refetch it
        // regardless of whether it matches the current item.
        if (!barcode && itemSvc.copy && itemSvc.copy.id() == copyId) {
            $scope.copy = itemSvc.copy;
            $scope.recordId = itemSvc.copy.call_number().record().id();
            return $q.when();
        }

        delete $scope.copy;
        delete itemSvc.copy;

        var deferred = $q.defer();
        itemSvc.fetch(barcode, copyId, true).then(function(res) {
            $scope.context.selectBarcode = true;

            if (!res) {
                copyId = null;
                $scope.context.itemNotFound = true;
                deferred.reject(); // avoid propagation of data fetch calls
                return;
            }

            var copy = res.copy;
            itemSvc.copy = copy;


            $scope.copy = copy;
            $scope.recordId = copy.call_number().record().id();
            $scope.args.barcode = '';

            // locally flesh org units
            copy.circ_lib(egCore.org.get(copy.circ_lib()));
            copy.call_number().owning_lib(
                egCore.org.get(copy.call_number().owning_lib()));

            var r = copy.call_number().record();
            if (r.owner()) r.owner(egCore.org.get(r.owner())); 

            // make boolean for auto-magic true/false display
            angular.forEach(
                ['ref','opac_visible','holdable','circulate'],
                function(field) { copy[field](Boolean(copy[field]() == 't')) }
            );

            // finally, if this is a different copy, redirect.
            // Note that we flesh first since the copy we just
            // fetched will be used after the redirect.
            if (copyId && copyId != copy.id()) {
                // if a new barcode is scanned in the detail view,
                // update the url to match the ID of the new copy
                $location.path('/cat/item/' + copy.id() + '/' + $scope.tab);
                deferred.reject(); // avoid propagation of data fetch calls
                return;
            }
            copyId = copy.id();

            deferred.resolve();
        });

        return deferred.promise;
    }

    // if loadPrev load the two most recent circulations
    function loadCurrentCirc(loadPrev) {
        delete $scope.circ;
        delete $scope.circ_summary;
        delete $scope.prev_circ_summary;
        if (!copyId) return;
        
        egCore.pcrud.search('circ', 
            {target_copy : copyId},
            {   flesh : 2,
                flesh_fields : {
                    circ : [
                        'usr',
                        'workstation',                                         
                        'checkin_workstation',                                 
                        'duration_rule',                                       
                        'max_fine_rule',                                       
                        'recurring_fine_rule'   
                    ],
                    au : ['card']
                },
                order_by : {circ : 'xact_start desc'}, 
                limit :  1
            }

        ).then(null, null, function(circ) {
            $scope.circ = circ;

            // load the chain for this circ
            egCore.net.request(
                'open-ils.circ',
                'open-ils.circ.renewal_chain.retrieve_by_circ.summary',
                egCore.auth.token(), $scope.circ.id()
            ).then(function(summary) {
                $scope.circ_summary = summary.summary;
            });

            if (!loadPrev) return;

            // load the chain for the previous circ, plus the user
            egCore.net.request(
                'open-ils.circ',
                'open-ils.circ.prev_renewal_chain.retrieve_by_circ.summary',
                egCore.auth.token(), $scope.circ.id()

            ).then(null, null, function(summary) {
                $scope.prev_circ_summary = summary.summary;

                egCore.pcrud.retrieve('au', summary.usr,
                    {flesh : 1, flesh_fields : {au : ['card']}})

                .then(function(user) {
                    $scope.prev_circ_usr = user;
                });
            });
        });
    }

    var maxHistory;
    function fetchMaxCircHistory() {
        if (maxHistory) return $q.when(maxHistory);
        return egCore.org.settings(
            'circ.item_checkout_history.max')
        .then(function(set) {
            maxHistory = set['circ.item_checkout_history.max'] || 4;
            return maxHistory;
        });
    }

    $scope.addBilling = function(circ) {
        egBilling.showBillDialog({
            xact_id : circ.id(),
            patron : circ.usr()
        });
    }

    $scope.retrieveAllPatrons = function() {
        var users = new Set();
        angular.forEach($scope.circ_list.map(function(circ) { return circ.usr(); }),function(usr) {
            users.add(usr);
        });
        users.forEach(function(usr) {
            $timeout(function() {
                var url = $location.absUrl().replace(
                    /\/cat\/.*/,
                    '/circ/patron/' + usr.id() + '/checkout');
                $window.open(url, '_blank')
            });
        });
    }

    function loadCircHistory() {
        $scope.circ_list = [];

        var copy_org = 
            itemSvc.copy.call_number().id() == -1 ?
            itemSvc.copy.circ_lib().id() :
            itemSvc.copy.call_number().owning_lib().id()

        // there is an extra layer of permissibility over circ
        // history views
        egCore.perm.hasPermAt('VIEW_COPY_CHECKOUT_HISTORY', true)
        .then(function(orgIds) {

            if (orgIds.indexOf(copy_org) == -1) {
                console.log('User is not allowed to view circ history');
                return $q.when(0);
            }

            return fetchMaxCircHistory();

        }).then(function(count) {

            egCore.pcrud.search('circ', 
                {target_copy : copyId},
                {   flesh : 2,
                    flesh_fields : {
                        circ : [
                            'usr',
                            'workstation',                                         
                            'checkin_workstation',                                 
                            'recurring_fine_rule'   
                        ],
                        au : ['card']
                    },
                    order_by : {circ : 'xact_start desc'}, 
                    limit :  count
                }

            ).then(null, null, function(circ) {

                // flesh circ_lib locally
                circ.circ_lib(egCore.org.get(circ.circ_lib()));
                circ.checkin_lib(egCore.org.get(circ.checkin_lib()));
                $scope.circ_list.push(circ);
            });
        });
    }


    function loadCircCounts() {

        delete $scope.circ_counts;
        $scope.total_circs = 0;
        $scope.total_circs_this_year = 0;
        $scope.total_circs_prev_year = 0;
        if (!copyId) return;

        egCore.pcrud.search('circbyyr', 
            {copy : copyId}, null, {atomic : true})

        .then(function(counts) {
            $scope.circ_counts = counts;

            angular.forEach(counts, function(count) {
                $scope.total_circs += Number(count.count());
            });

            var this_year = counts.filter(function(c) {
                return c.year() == new Date().getFullYear();
            });

            $scope.total_circs_this_year = 
                this_year.length ? this_year[0].count() : 0;

            var prev_year = counts.filter(function(c) {
                return c.year() == new Date().getFullYear() - 1;
            });

            $scope.total_circs_prev_year = 
                prev_year.length ? prev_year[0].count() : 0;

        });
    }

    function loadHolds() {
        delete $scope.hold;
        if (!copyId) return;

        egCore.pcrud.search('ahr', 
            {   current_copy : copyId, 
                cancel_time : null, 
                fulfillment_time : null,
                capture_time : {'<>' : null}
            }, {
                flesh : 2,
                flesh_fields : {
                    ahr : ['requestor', 'usr'],
                    au  : ['card']
                }
            }
        ).then(null, null, function(hold) {
            $scope.hold = hold;
            hold.pickup_lib(egCore.org.get(hold.pickup_lib()));
            if (hold.current_shelf_lib()) {
                hold.current_shelf_lib(
                    egCore.org.get(hold.current_shelf_lib()));
            }
            hold.behind_desk(Boolean(hold.behind_desk() == 't'));
        });
    }

    function loadTransits() {
        delete $scope.transit;
        delete $scope.hold_transit;
        if (!copyId) return;

        egCore.pcrud.search('atc', 
            {target_copy : copyId},
            {order_by : {atc : 'source_send_time DESC'}}

        ).then(null, null, function(transit) {
            $scope.transit = transit;
            transit.source(egCore.org.get(transit.source()));
            transit.dest(egCore.org.get(transit.dest()));
        })
    }


    // we don't need all data on all tabs, so fetch what's needed when needed.
    function loadTabData() {
        switch($scope.tab) {
            case 'summary':
                loadCurrentCirc();
                loadCircCounts();
                break;

            case 'circs':
                loadCurrentCirc(true);
                break;

            case 'circ_list':
                loadCircHistory();
                break;

            case 'holds':
                loadHolds()
                loadTransits();
                break;

            case 'triggered_events':
                var url = $location.absUrl().replace(/\/staff.*/, '/actor/user/event_log');
                url += '?copy_id=' + encodeURIComponent(copyId);
                $scope.triggered_events_url = url;
                $scope.funcs = {};
        }

        if ($scope.edit) {
            egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.anon_cache.set_value',
                null, 'edit-these-copies', {
                    record_id: $scope.recordId,
                    copies: [copyId],
                    hide_vols : true,
                    hide_copies : false
                }
            ).then(function(key) {
                if (key) {
                    var url = egCore.env.basePath + 'cat/volcopy/' + key;
                    $window.location.href = url;
                } else {
                    alert('Could not create anonymous cache key!');
                }
            });
        }

        return;
    }

    $scope.context.toggleDisplay = function() {
        $location.path('/cat/item/search');
    }

    // handle the barcode scan box, which will replace our current copy
    $scope.context.search = function(args) {
        loadCopy(args.barcode).then(loadTabData);
    }

    $scope.context.show_triggered_events = function() {
        $location.path('/cat/item/' + copyId + '/triggered_events');
    }

    loadCopy().then(loadTabData);
}])
