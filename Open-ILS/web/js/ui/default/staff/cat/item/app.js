/**
 * Item Display
 */

angular.module('egItemStatus', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod', 'egUserMod'])

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

/**
 * Search bar along the top of the page.
 * Parent scope for list and detail views
 */
.controller('SearchCtrl', 
       ['$scope','$location','$timeout','egCore','egGridDataProvider','egItem',
function($scope , $location , $timeout , egCore , egGridDataProvider , itemSvc) {
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

    // The functions that follow in this controller are never called
    // when the List View is active, only the Detail View.
    
    // In this context, we're only ever dealing with 1 item, so
    // we can simply refresh the page.  These various itemSvc
    // functions used to live in the ListCtrl, but they're now
    // shared between SearchCtrl (for Actions for the Detail View)
    // and ListCtrl (Actions in the egGrid)
    itemSvc.add_barcode_to_list = function(b) {
        //console.log('SearchCtrl: add_barcode_to_list',b);
        // timeout so audible can happen upon checkin
        $timeout(function() { location.href = location.href; }, 1000);
    }

    $scope.add_copies_to_bucket = function() {
        itemSvc.add_copies_to_bucket([$scope.args.copyId]);
    }

    $scope.make_copies_bookable = function() {
        itemSvc.make_copies_bookable([{
            id : $scope.args.copyId,
            'call_number.record.id' : $scope.args.recordId
        }]);
    }

    $scope.book_copies_now = function() {
        itemSvc.book_copies_now([{
            id : $scope.args.copyId,
            'call_number.record.id' : $scope.args.recordId
        }]);
    }

    $scope.requestItems = function() {
        itemSvc.requestItems([$scope.args.copyId]);
    }

    $scope.attach_to_peer_bib = function() {
        itemSvc.attach_to_peer_bib([{
            id : $scope.args.copyId,
            barcode : $scope.args.copyBarcode
        }]);
    }

    $scope.selectedHoldingsCopyDelete = function () {
        itemSvc.selectedHoldingsCopyDelete([{
            id : $scope.args.copyId,
            barcode : $scope.args.copyBarcode
        }]);
    }

    $scope.checkin = function () {
        itemSvc.checkin([{
            id : $scope.args.copyId,
            barcode : $scope.args.copyBarcode
        }]);
    }

    $scope.renew = function () {
        itemSvc.renew([{
            id : $scope.args.copyId,
            barcode : $scope.args.copyBarcode
        }]);
    }

    $scope.cancel_transit = function () {
        itemSvc.cancel_transit([{
            id : $scope.args.copyId,
            barcode : $scope.args.copyBarcode
        }]);
    }

    $scope.selectedHoldingsDamaged = function () {
        itemSvc.selectedHoldingsDamaged([{
            id : $scope.args.copyId,
            barcode : $scope.args.copyBarcode,
            refresh : true
        }]);
    }

    $scope.selectedHoldingsMissing = function () {
        itemSvc.selectedHoldingsMissing([{
            id : $scope.args.copyId,
            barcode : $scope.args.copyBarcode
        }]);
    }

    $scope.selectedHoldingsVolCopyAdd = function () {
        itemSvc.spawnHoldingsAdd([{
            id : $scope.args.copyId,
            'call_number.owning_lib' : $scope.args.cnOwningLib,
            'call_number.record.id' : $scope.args.recordId,
            barcode : $scope.args.copyBarcode
        }],true,false);
    }
    $scope.selectedHoldingsCopyAdd = function () {
        itemSvc.spawnHoldingsAdd([{
            id : $scope.args.copyId,
            'call_number.id' : $scope.args.cnId,
            'call_number.owning_lib' : $scope.args.cnOwningLib,
            'call_number.record.id' : $scope.args.recordId,
            barcode : $scope.args.copyBarcode
        }],false,true);
    }

    $scope.selectedHoldingsVolCopyEdit = function () {
        itemSvc.spawnHoldingsEdit([{
            id : $scope.args.copyId,
            'call_number.id' : $scope.args.cnId,
            'call_number.owning_lib' : $scope.args.cnOwningLib,
            'call_number.record.id' : $scope.args.recordId,
            barcode : $scope.args.copyBarcode
        }],false,false);
    }
    $scope.selectedHoldingsVolEdit = function () {
        itemSvc.spawnHoldingsEdit([{
            id : $scope.args.copyId,
            'call_number.id' : $scope.args.cnId,
            'call_number.owning_lib' : $scope.args.cnOwningLib,
            'call_number.record.id' : $scope.args.recordId,
            barcode : $scope.args.copyBarcode
        }],false,true);
    }
    $scope.selectedHoldingsCopyEdit = function () {
        itemSvc.spawnHoldingsEdit([{
            id : $scope.args.copyId,
            'call_number.id' : $scope.args.cnId,
            'call_number.owning_lib' : $scope.args.cnOwningLib,
            'call_number.record.id' : $scope.args.recordId,
            barcode : $scope.args.copyBarcode
        }],true,false);
    }

    $scope.replaceBarcodes = function() {
        itemSvc.replaceBarcodes([{
            id : $scope.args.copyId,
            barcode : $scope.args.copyBarcode
        }]);
    }

    $scope.changeItemOwningLib = function() {
        itemSvc.changeItemOwningLib([{
            id : $scope.args.copyId,
            'call_number.id' : $scope.args.cnId,
            'call_number.owning_lib' : $scope.args.cnOwningLib,
            'call_number.record.id' : $scope.args.recordId,
            'call_number.label' : $scope.args.cnLabel,
            'call_number.label_class' : $scope.args.cnLabelClass,
            'call_number.prefix.id' : $scope.args.cnPrefixId,
            'call_number.suffix.id' : $scope.args.cnSuffixId,
            barcode : $scope.args.copyBarcode
        }]);
    }

    $scope.transferItems = function (){
        itemSvc.transferItems([{
            id : $scope.args.copyId,
            barcode : $scope.args.copyBarcode
        }]);
    }

}])

/**
 * List view - grid stuff
 */
.controller('ListCtrl', 
       ['$scope','$q','$routeParams','$location','$timeout','$window','egCore','egGridDataProvider','egItem','egUser','$uibModal','egCirc','egConfirmDialog',
function($scope , $q , $routeParams , $location , $timeout , $window , egCore , egGridDataProvider , itemSvc , egUser , $uibModal , egCirc , egConfirmDialog) {
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

            if (barcodes.length > 0) {
                var promises = [];
                angular.forEach(barcodes, function (b) {
                    promises.push(itemSvc.fetch(b));
                });

                $q.all(promises).then(
                    function() {
                        copyGrid.refresh();
                        copyGrid.selectItems([itemSvc.copies[0].index]);
                    }
                );
            }
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
                egCore.audio.play('warning.item_status.itemNotFound');
            }
            $scope.context.selectBarcode = true;
        })
    }

    var add_barcode_to_list = function (b) {
        //console.log('listCtrl: add_barcode_to_list',b);
        $scope.context.search({barcode:b});
    }
    itemSvc.add_barcode_to_list = add_barcode_to_list;

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

    function gatherSelectedRecordIds () {
        var rid_list = [];
        angular.forEach(
            copyGrid.selectedItems(),
            function (item) {
                if (rid_list.indexOf(item['call_number.record.id']) == -1)
                    rid_list.push(item['call_number.record.id'])
            }
        );
        return rid_list;
    }

    function gatherSelectedVolumeIds (rid) {
        var cn_id_list = [];
        angular.forEach(
            copyGrid.selectedItems(),
            function (item) {
                if (rid && item['call_number.record.id'] != rid) return;
                if (cn_id_list.indexOf(item['call_number.id']) == -1)
                    cn_id_list.push(item['call_number.id'])
            }
        );
        return cn_id_list;
    }

    function gatherSelectedHoldingsIds (rid) {
        var cp_id_list = [];
        angular.forEach(
            copyGrid.selectedItems(),
            function (item) {
                if (rid && item['call_number.record.id'] != rid) return;
                cp_id_list.push(item.id)
            }
        );
        return cp_id_list;
    }

    $scope.add_copies_to_bucket = function() {
        var copy_list = gatherSelectedHoldingsIds();
        itemSvc.add_copies_to_bucket(copy_list);
    }

    $scope.need_one_selected = function() {
        var items = $scope.gridControls.selectedItems();
        if (items.length == 1) return false;
        return true;
    };

    $scope.make_copies_bookable = function() {
        itemSvc.make_copies_bookable(copyGrid.selectedItems());
    }

    $scope.book_copies_now = function() {
        itemSvc.book_copies_now(copyGrid.selectedItems());
    }

    $scope.requestItems = function() {
        var copy_list = gatherSelectedHoldingsIds();
        itemSvc.requestItems(copy_list);
    }

    $scope.replaceBarcodes = function() {
        itemSvc.replaceBarcodes(copyGrid.selectedItems());
    }

    $scope.attach_to_peer_bib = function() {
        itemSvc.attach_to_peer_bib(copyGrid.selectedItems());
    }

    $scope.selectedHoldingsCopyDelete = function () {
        itemSvc.selectedHoldingsCopyDelete(copyGrid.selectedItems());
    }

    $scope.selectedHoldingsItemStatusTgrEvt= function() {
        var item = copyGrid.selectedItems()[0];
        if (item)
            $location.path('/cat/item/' + item.id + '/triggered_events');
    }

    $scope.selectedHoldingsItemStatusHolds= function() {
        var item = copyGrid.selectedItems()[0];
        if (item)
            $location.path('/cat/item/' + item.id + '/holds');
    }

    $scope.cancel_transit = function () {
        itemSvc.cancel_transit(copyGrid.selectedItems());
    }

    $scope.selectedHoldingsDamaged = function () {
        itemSvc.selectedHoldingsDamaged(copyGrid.selectedItems());
    }

    $scope.selectedHoldingsMissing = function () {
        itemSvc.selectedHoldingsMissing(copyGrid.selectedItems());
    }

    $scope.checkin = function () {
        itemSvc.checkin(copyGrid.selectedItems());
    }

    $scope.renew = function () {
        itemSvc.renew(copyGrid.selectedItems());
    }

    $scope.selectedHoldingsVolCopyAdd = function () {
        itemSvc.spawnHoldingsAdd(copyGrid.selectedItems(),true,false);
    }
    $scope.selectedHoldingsCopyAdd = function () {
        itemSvc.spawnHoldingsAdd(copyGrid.selectedItems(),false,true);
    }

    $scope.showBibHolds = function () {
        angular.forEach(gatherSelectedRecordIds(), function (r) {
            var url = egCore.env.basePath + 'cat/catalog/record/' + r + '/holds';
            $timeout(function() { $window.open(url, '_blank') });
        });
    }

    $scope.selectedHoldingsVolCopyEdit = function () {
        itemSvc.spawnHoldingsEdit(copyGrid.selectedItems(),false,false);
    }
    $scope.selectedHoldingsVolEdit = function () {
        itemSvc.spawnHoldingsEdit(copyGrid.selectedItems(),false,true);
    }
    $scope.selectedHoldingsCopyEdit = function () {
        itemSvc.spawnHoldingsEdit(copyGrid.selectedItems(),true,false);
    }

    $scope.changeItemOwningLib = function() {
        itemSvc.changeItemOwningLib(copyGrid.selectedItems());
    }

    $scope.transferItems = function (){
        itemSvc.transferItems(copyGrid.selectedItems());
    }

    $scope.print_labels = function() {
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            null, 'print-labels-these-copies', {
                copies : gatherSelectedHoldingsIds()
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

    $scope.print_list = function() {
        var print_data = { copies : copyGrid.allItems() };

        if (print_data.copies.length == 0) return $q.when();

        return egCore.print.print({
            template : 'item_status',
            scope : print_data
        });
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
       ['$scope','$q','$location','$routeParams','$timeout','$window','egCore','egItem','egBilling',
function($scope , $q , $location , $routeParams , $timeout , $window , egCore , itemSvc , egBilling) {
    var copyId = $routeParams.id;
    $scope.args.copyId = copyId;
    $scope.tab = $routeParams.tab || 'summary';
    $scope.context.page = 'detail';
    $scope.summaryRecord = null;

    $scope.edit = false;
    if ($scope.tab == 'edit') {
        $scope.tab = 'summary';
        $scope.edit = true;
    }


    // use the cached record info
    if (itemSvc.copy) {
        $scope.recordId = itemSvc.copy.call_number().record().id();
        $scope.args.recordId = $scope.recordId;
        $scope.args.cnId = itemSvc.copy.call_number().id();
        $scope.args.cnOwningLib = itemSvc.copy.call_number().owning_lib();
        $scope.args.cnLabel = itemSvc.copy.call_number().label();
        $scope.args.cnLabelClass = itemSvc.copy.call_number().label_class();
        $scope.args.cnPrefixId = itemSvc.copy.call_number().prefix().id();
        $scope.args.cnSuffixId = itemSvc.copy.call_number().suffix().id();
        $scope.args.copyBarcode = itemSvc.copy.barcode();
    }

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
            $scope.args.recordId = $scope.recordId;
            $scope.args.cnId = itemSvc.copy.call_number().id();
            $scope.args.cnOwningLib = itemSvc.copy.call_number().owning_lib();
            $scope.args.cnLabel = itemSvc.copy.call_number().label();
            $scope.args.cnLabelClass = itemSvc.copy.call_number().label_class();
            $scope.args.cnPrefixId = itemSvc.copy.call_number().prefix().id();
            $scope.args.cnSuffixId = itemSvc.copy.call_number().suffix().id();
            $scope.args.copyBarcode = itemSvc.copy.barcode();
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
                egCore.audio.play('warning.item_status.itemNotFound');
                deferred.reject(); // avoid propagation of data fetch calls
                return;
            }

            var copy = res.copy;
            itemSvc.copy = copy;


            $scope.copy = copy;
            $scope.recordId = copy.call_number().record().id();
            $scope.args.recordId = $scope.recordId;
            $scope.args.cnId = itemSvc.copy.call_number().id();
            $scope.args.cnOwningLib = itemSvc.copy.call_number().owning_lib();
            $scope.args.cnLabel = itemSvc.copy.call_number().label();
            $scope.args.cnLabelClass = itemSvc.copy.call_number().label_class();
            $scope.args.cnPrefixId = itemSvc.copy.call_number().prefix().id();
            $scope.args.cnSuffixId = itemSvc.copy.call_number().suffix().id();
            $scope.args.copyBarcode = copy.barcode();
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
        delete $scope.prev_circ_usr;
        if (!copyId) return;
        
        egCore.pcrud.search('aacs', 
            {target_copy : copyId},
            {   flesh : 2,
                flesh_fields : {
                    aacs : [
                        'usr',
                        'workstation',                                         
                        'checkin_workstation',                                 
                        'duration_rule',                                       
                        'max_fine_rule',                                       
                        'recurring_fine_rule'   
                    ],
                    au : ['card']
                },
                order_by : {aacs : 'xact_start desc'}, 
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
                $scope.circ_summary = summary;
            });

            if (!loadPrev) return;

            // load the chain for the previous circ, plus the user
            egCore.net.request(
                'open-ils.circ',
                'open-ils.circ.prev_renewal_chain.retrieve_by_circ.summary',
                egCore.auth.token(), $scope.circ.id()

            ).then(null, null, function(summary) {
                $scope.prev_circ_summary = summary.summary;

                if (summary.usr) { // aged circs have no 'usr'.
                    egCore.pcrud.retrieve('au', summary.usr,
                        {flesh : 1, flesh_fields : {au : ['card']}})

                    .then(function(user) { $scope.prev_circ_usr = user });
                }
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
            // aged circs have no 'usr'.
            if (usr) users.add(usr);
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

            egCore.pcrud.search('aacs', 
                {target_copy : copyId},
                {   flesh : 2,
                    flesh_fields : {
                        aacs : [
                            'usr',
                            'workstation',                                         
                            'checkin_workstation',                                 
                            'recurring_fine_rule'   
                        ],
                        au : ['card']
                    },
                    order_by : {aacs : 'xact_start desc'}, 
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
