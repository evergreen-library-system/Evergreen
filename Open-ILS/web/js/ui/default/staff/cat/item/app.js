/**
 * Item Display
 */

angular.module('egItemStatus', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod', 'egUserMod', 'egBatchPromisesMod'])

.filter('boolText', function(){
    return function (v) {
        return v == 't';
    }
})

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
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
      ['$scope','$q','$window','$location','$timeout','egCore','egNet','egGridDataProvider','egItem', 'egCirc', 'ngToast',
function($scope , $q , $window , $location , $timeout , egCore , egNet , egGridDataProvider , itemSvc , egCirc, ngToast) {
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

    $scope.add_records_to_bucket = function() {
        itemSvc.add_records_to_bucket([$scope.args.recordId], 'biblio');
    }

    $scope.show_in_catalog = function() {
        window.open('/eg2/staff/catalog/record/' + $scope.args.recordId, '_blank');
    }

    $scope.print_labels = function() {
        itemSvc.print_spine_labels([$scope.args.copyId]);
    }


    $scope.make_copies_bookable = function() {
        itemSvc.make_copies_bookable([{
            id : $scope.args.copyId,
            'call_number.record.id' : $scope.args.recordId
        }]);
    }

    $scope.book_copies_now = function() {
        itemSvc.book_copies_now([$scope.args.copyBarcode]);
    }

    $scope.findAcquisition = function() {
        var acqData;
        var promises = [];
        $scope.openAcquisitionLineItem([$scope.args.copyId]);
    }

    $scope.openAcquisitionLineItem = function (cp_list) {
        var hasResults = false;
        var promises = [];

        angular.forEach(cp_list, function (copyId) {
            promises.push(
                egNet.request(
                    'open-ils.acq',
                    'open-ils.acq.lineitem.retrieve.by_copy_id',
                    egCore.auth.token(),
                    copyId
                ).then(function (acqData) {
                    if (acqData) {
                        if (acqData.a) {
                            acqData = egCore.idl.toHash(acqData);
                            var url = '/eg2/staff/acq/po/' + acqData.purchase_order + '#' + acqData.id;
                            $timeout(function () { $window.open(url, '_blank') });
                            hasResults = true;
                        }
                    }
                })
            )
        });

        $q.all(promises).then(function () {
            !hasResults ? alert('There is no corresponding purchase order for this item.') : false;
        });
    }

    $scope.manage_reservations = function() {
        itemSvc.manage_reservations([$scope.args.copyBarcode]);
    }

    $scope.requestItems = function() {
        itemSvc.requestItems([$scope.args.copyId],[$scope.args.recordId]);
    }

    $scope.update_inventory = function() {
        itemSvc.updateInventory([$scope.args.copyId], null)
        .then(function(res) {
            if (res[0]) {
                ngToast.create(egCore.strings.SUCCESS_UPDATE_INVENTORY_SINGLE);
            } else {
                ngToast.warning(egCore.strings.FAIL_UPDATE_INVENTORY_SINGLE);
            }
            $timeout(function() { location.href = location.href; }, 1500);
        });
    }

    $scope.show_triggered_events = function() {
        window.open('/eg2/staff/circ/item/event-log/' + $scope.args.copyId, '_blank');
    }

    $scope.show_item_holds = function() {
        $location.path('/cat/item/' + $scope.args.copyId + '/holds');
    }

    $scope.show_record_holds = function() {
        window.open('/eg2/staff/catalog/record/' + $scope.args.recordId + '/holds', '_blank');
    }

    $scope.add_item_alerts = function() {
        egCirc.add_copy_alerts([$scope.args.copyId]);
    }

    $scope.manage_item_alerts = function() {
        egCirc.manage_copy_alerts([$scope.args.copyId]);
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

    $scope.selectedHoldingsDiscard = function () {
        itemSvc.selectedHoldingsDiscard([{
            id : $scope.args.copyId,
            barcode : $scope.args.barcode
        }]);
    }

    $scope.selectedHoldingsMissing = function () {
        itemSvc.selectedHoldingsMissing([{
            id : $scope.args.copyId,
            barcode : $scope.args.barcode
        }]).catch(function(){});
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
       ['$scope','$q','$routeParams','$location','$timeout','$window','egCore',
        'egGridDataProvider','egItem','egUser','$uibModal','egCirc','egConfirmDialog',
        'egProgressDialog', 'ngToast', 'egBatchPromises',
// function($scope , $q , $routeParams , $location , $timeout , $window , egCore , 
//          egGridDataProvider , itemSvc , egUser , $uibModal , egCirc , egConfirmDialog,
//          egProgressDialog, ngToast) {
    function($scope , $q , $routeParams , $location , $timeout , $window , egCore , egGridDataProvider , itemSvc , egUser , $uibModal , egCirc , egConfirmDialog,
                 egProgressDialog, ngToast, egBatchPromises) {
    var copyId = [];
    var cp_list = $routeParams.idList;
    if (cp_list) {
        copyId = cp_list.split(',');
    }

    var modified_items = new Set();

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
        $scope.context.itemsNotFound = [];
        $scope.context.fileDoneLoading = false;
        $scope.context.numBarcodesInFile = 0;
        if (newVal && newVal != oldVal) {
            $scope.args.barcode = '';
            var barcodes = [];

            angular.forEach(newVal.split(/\r?\n/), function(line) {
                //remove all whitespace and commas
                line = line.replace(/[\s,]+/g,'');

                //Or remove leading/trailing whitespace
                //line = line.replace(/(^[\s,]+|[\s,]+$/g,'');

                if (!line) return;
                barcodes.push(line);
            });

            // Serialize copy retrieval since there may be many, many copies.
            function fetch_next_copy() {
                var barcode = barcodes.pop();
                egProgressDialog.increment();

                if (barcode == undefined) { // All done here.
                    egProgressDialog.close();
                    copyGrid.refresh();
                    if(itemSvc.copies[0]){  // Were any copies actually retrieved
                        copyGrid.selectItems([itemSvc.copies[0].index]);
                    }
                    $scope.context.fileDoneLoading = true;
                    return;
                }

                itemSvc.fetch(barcode).then(function(item) {
                    if (!item) {
                        $scope.context.itemsNotFound.push(barcode);
                    }
                    fetch_next_copy();
                })
            }

            if (barcodes.length) {
                $scope.context.numBarcodesInFile = barcodes.length;
                egProgressDialog.open({value: 0, max: barcodes.length});
                fetch_next_copy();
            }
        }
    });

    $scope.context.search = function(args, noGridRefresh) {
        if (!args.barcode) return $q.when();
        $scope.context.itemNotFound = false;

        // reset so the input can be auto-selected after the search
        $scope.context.selectBarcode = false;

        //check to see if there are multiple barcodes in CSV format
        var barcodes = [];
        //split on commas and clean up barcodes
        angular.forEach(args.barcode.split(/,/), function(line) {
            //remove all whitespace and commas
            line = line.replace(/[\s,]+/g,'');

            //Or remove leading/trailing whitespace
            //line = line.replace(/(^[\s,]+|[\s,]+$/g,'');

            if (!line) return;
            barcodes.push(line);
        });

        if(barcodes.length > 1){
            //convert to newline seperated list and send to barcodesFromFile processor
            $scope.barcodesFromFile = barcodes.join('\n');
            //console.log('Barcodes: ',barcodes);
            return $q.when();

        } else {
            //Single Barcode
            return itemSvc.fetch(args.barcode).then(function(res) {
                if (res) {
                    if (!noGridRefresh) {
                        copyGrid.refresh();
                    }
                    copyGrid.selectItems([res.index]);
                    $scope.args.barcode = '';
                } else {
                    $scope.context.itemNotFound = true;
                    egCore.audio.play('warning.item_status.itemNotFound');
                }
                $scope.context.selectBarcode = true;
            })
        }
    }

    var add_barcode_to_list = function (b, noGridRefresh) {
        // console.log('listCtrl: add_barcode_to_list',b);
        return $scope.context.search({barcode:b}, noGridRefresh);
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
            window.open('/eg2/staff/circ/item/event-log/' + item.id, '_blank');
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

    function gatherSelectedHoldingsRecords() {
        var record_id_list = [];
        angular.forEach(
            copyGrid.selectedItems(),
            function (item) {
                record_id_list.push(item['call_number.record.id']);
            }
        )
        return record_id_list;
    }

    // Refresh the data shown in the item status grid,
    // such as after the user has changed some data
    //
    // Takes an optional restrictToIds argument, which
    // is a Set of item IDs that have been changed
    $scope.refreshGridData = function(restrictToIds) {
        var fetch_list = [];
        var progress_bar;

        angular.forEach(itemSvc.copies, function(item, index) {
            if (!restrictToIds || restrictToIds.has(item['id'])) {
                fetch_list.push(
                    itemSvc.fetch(null, item['id'], null, true)
                    .then(function(res) {
                        itemSvc.copies[index] = res;
                        if (progress_bar) egProgressDialog.increment();
                        return res;
                    })
                );
            }
        });

        progress_bar = $timeout(egProgressDialog.open, 5000, true, {value: 0, max: fetch_list.length});

        egBatchPromises.all(fetch_list)
        .then( function() {
            copyGrid.refresh();
            if (progress_bar) $timeout.cancel(progress_bar);
            egProgressDialog.close();
            ngToast.create(egCore.strings.ITEMS_SUCCESSFULLY_MODIFIED);
        });
    }


    $scope.add_copies_to_bucket = function() {
        var copy_list = gatherSelectedHoldingsIds();
        itemSvc.add_copies_to_bucket(copy_list);
    }

    $scope.add_records_to_bucket = function() {
        var record_list = gatherSelectedHoldingsRecords();
        itemSvc.add_copies_to_bucket(record_list, 'biblio');
    }

    $scope.locateAcquisition = function() {
        if (gatherSelectedHoldingsIds) {
            var cp_list = gatherSelectedHoldingsIds();
            if (cp_list) {
                if (cp_list.length > 0) {
                    $scope.openAcquisitionLineItem(cp_list);
                }
            }
        }
    }

    $scope.update_inventory = function() {
        var copy_list = gatherSelectedHoldingsIds();
        itemSvc.updateInventory(copy_list, $scope.gridControls.allItems()).then(function(res) {
            if (res[0]) {
                ngToast.create(egCore.strings.SUCCESS_UPDATE_INVENTORY);
            } else {
                ngToast.warning(egCore.strings.FAIL_UPDATE_INVENTORY);
            }
        });
    }

    $scope.need_one_selected = function() {
        var items = $scope.gridControls.selectedItems();
        if (items.length == 1) return false;
        return true;
    };

    $scope.need_at_least_one_selected = function() {
        var items = $scope.gridControls.selectedItems();
        if (items.length == 0) return true; // Disable the control (i.e. true) if none selected
        return false;
    };

    $scope.make_copies_bookable = function() {
        itemSvc.make_copies_bookable(copyGrid.selectedItems());
    }

    $scope.book_copies_now = function() {
        var item = copyGrid.selectedItems()[0];
        if (item)
            itemSvc.book_copies_now(item.barcode);
    }

    $scope.manage_reservations = function() {
        var item = copyGrid.selectedItems()[0];
        if (item)
            itemSvc.manage_reservations(item.barcode);
    }

    $scope.create_carousel = function() {
        var itemIds = copyGrid.selectedItems().map(function (item) {return item.id});
        itemSvc.create_carousel_from_items(itemIds);
    }

    $scope.requestItems = function() {
        var copy_list = gatherSelectedHoldingsIds();
        var record_list = gatherSelectedRecordIds();
        itemSvc.requestItems(copy_list,record_list);
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
            window.open('/eg2/staff/circ/item/event-log/' + item.id, '_blank');
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

    $scope.selectedHoldingsDiscard = function () {
        itemSvc.selectedHoldingsDiscard(copyGrid.selectedItems());
    }

    $scope.selectedHoldingsMissing = function () {
        var dialog = egProgressDialog.open();
        dialog.opened.then(function() {
            itemSvc.selectedHoldingsMissing(copyGrid.selectedItems())
            .then(function() { 
                console.debug('Marking missing complete, refreshing grid');
                copyGrid.refresh();
            }).catch(function() {
            }).finally(function() {
                egProgressDialog.close();
            });
        });
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

    $scope.selectedHoldingsCopyAlertsAdd = function(items) {
        var copy_ids = [];
        angular.forEach(items, function(item) {
            if (item.id) copy_ids.push(item.id);
        });
        egCirc.add_copy_alerts(copy_ids).then(function() {
            // update grid items?
        });
    }

    $scope.selectedHoldingsCopyAlertsEdit = function(items) {
        var copy_ids = [];
        angular.forEach(items, function(item) {
            if (item.id) copy_ids.push(item.id);
        });
        egCirc.manage_copy_alerts(copy_ids).then(function() {
            // update grid items?
        });
    }

    $scope.gridCellHandlers = {};
    $scope.gridCellHandlers.copyAlertsEdit = function(id) {
        egCirc.manage_copy_alerts([id]).then(function() {
            // update grid items?
        });
    };

    $scope.showBibHolds = function () {
        angular.forEach(gatherSelectedRecordIds(), function (r) {
            var url = '/eg2/staff/catalog/record/' + r + '/holds';
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

    $scope.show_in_catalog = function(){
        itemSvc.show_in_catalog(copyGrid.selectedItems());
    }

    if (copyId.length > 0) {
        var fetch_list = [];
        angular.forEach(copyId, function (c) {
            fetch_list.push(itemSvc.fetch(null,c));
        });

        return $q.all(fetch_list).then(function (res) { copyGrid.refresh(); });
    }

    $scope.statusIconColumn = {
        isEnabled: true,
        template:  function(item) {
            var icon = '';
            if (modified_items.has(item['id'])) {
                icon = '<span class="glyphicon glyphicon-floppy-saved"' +
                    'title="' + egCore.strings.ITEM_SUCCESSFULLY_MODIFIED + '" ' +
                    'aria-label="' + egCore.strings.ITEM_SUCCESSFULLY_MODIFIED + '">' +
                    '</span>';
            }
            return icon;
        }
    }

    if (typeof BroadcastChannel != 'undefined') {
        var holdings_bChannel = new BroadcastChannel("eg.holdings.update");
        holdings_bChannel.onmessage = function(e) {
            if (e.data.copies.length) {
                angular.forEach(e.data.copies, function(i) {
                    modified_items.add(i);
                });
                $scope.refreshGridData(modified_items);
            } else { // if only call numbers were modified
                egCore.pcrud.search('acp',
                    {
                        deleted : 0,
                        call_number : e.data.volumes
                    }, null, {atomic: true}
                    
                ).then(function(all_affected_items) {
                    all_affected_items.map(function(item) {
                        modified_items.add(item.id());
                    });
                    $scope.refreshGridData(modified_items);
                });

            }
        }
        $scope.$on('$destroy', function() {
            holdings_bChannel.close();
        });
    }

}])

/**
 * Detail view -- shows one copy
 */
.controller('ViewCtrl', 
       ['$scope','$q','egGridDataProvider','$location','$routeParams','$timeout','$window','egCore','egItem','egBilling','egCirc',
function($scope , $q , egGridDataProvider , $location , $routeParams , $timeout , $window , egCore , itemSvc , egBilling , egCirc) {
    var copyId = $routeParams.id;
    $scope.args.copyId = copyId;
    $scope.tab = $routeParams.tab || 'summary';
    $scope.context.page = 'detail';
    $scope.summaryRecord = null;
    $scope.courseModulesOptIn = fetchCourseOptIn();
    $scope.has_course_perms = fetchCoursePerms();
    $scope.edit = false;
    if ($scope.tab == 'edit') {
        $scope.tab = 'summary';
        $scope.edit = true;
    }

    // use the cached record info
    if (itemSvc.copy) {
        $scope.copy_alert_count = itemSvc.copy.copy_alerts().filter(function(aca) {
            return !aca.ack_time();
        }).length;
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
            if (itemSvc.latest_inventory && itemSvc.latest_inventory.copy() == copyId) {
                $scope.latest_inventory = itemSvc.latest_inventory;
            }
            $scope.copy_alert_count = itemSvc.copy.copy_alerts().filter(function(aca) {
                return !aca.ack_time();
            }).length;
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
            if (res.latest_inventory) itemSvc.latest_inventory = res.latest_inventory;


            $scope.copy = copy;
            $scope.latest_inventory = res.latest_inventory;
            $scope.copy_alert_count = copy.copy_alerts().filter(function(aca) {
                return !aca.ack_time();
            }).length;
console.debug($scope.copy_alert_count);
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

    // load the two most recent circulations in /circs tab
    function loadCurrentCirc() {
        delete $scope.circ;
        delete $scope.circ_summary;
        delete $scope.prev_circ_summary;
        delete $scope.prev_circ_usr;
        if (!copyId) return;
        
        var copy_org =
            itemSvc.copy.call_number().id() == -1 ?
            itemSvc.copy.circ_lib().id() :
            itemSvc.copy.call_number().owning_lib().id();

        // since a user can still view patron checkout history here, check perms
        egCore.perm.hasPermAt('VIEW_COPY_CHECKOUT_HISTORY', true)
        .then(function(orgIds){
            if(orgIds.indexOf(copy_org) == -1){
                console.warn('User is not allowed to view circ history!');
                $q.when(0);
            }

            return fetchMaxCircHistory();
        })
        .then(function(maxHistCount){

            if (!maxHistCount) $scope.isMaxCircHistoryZero = true;

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

                if (!circ) return $q.when();

                // load the chain for this circ
                egCore.net.request(
                    'open-ils.circ',
                    'open-ils.circ.renewal_chain.retrieve_by_circ.summary',
                    egCore.auth.token(), $scope.circ.id()
                ).then(function(summary) {
                    $scope.circ_summary = summary;
                });

                if (maxHistCount <= 1) return;

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
        })
    }

    var maxHistory;
    function fetchMaxCircHistory() {
        if (maxHistory) return $q.when(maxHistory);
        return egCore.org.settings(
            'circ.item_checkout_history.max')
        .then(function(set) {
            maxHistory = set['circ.item_checkout_history.max'] || 4;
            return Number(maxHistory);
        });
    }

    // Check for Course Modules Opt-In to enable Course Info tab
    function fetchCourseOptIn() {
        return egCore.org.settings(
            'circ.course_materials_opt_in'
        ).then(function(set) {
            $scope.courseModulesOptIn = set['circ.course_materials_opt_in'];

            return $scope.courseModulesOptIn;
        });
    }

    function fetchCoursePerms() {
        return egCore.perm.hasPermAt('MANAGE RESERVES', true).then(function(orgIds) {
            if(orgIds.indexOf(egCore.auth.user().ws_ou()) != -1){
                $scope.has_course_perms = true;

                return $scope.has_course_perms;
            }
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

    // load data for /circ_list tab
    function loadCircHistory() {
        $scope.circ_list = [];

        var copy_org = 
            itemSvc.copy.call_number().id() == -1 ?
            itemSvc.copy.circ_lib().id() :
            itemSvc.copy.call_number().owning_lib().id();

        // there is an extra layer of permissibility over circ
        // history views
        egCore.perm.hasPermAt('VIEW_COPY_CHECKOUT_HISTORY', true)
        .then(function(orgIds) {

            if (orgIds.indexOf(copy_org) == -1) {
                console.log('User is not allowed to view circ history');
                return $q.when(0);
            }

            return fetchMaxCircHistory();

        }).then(function(maxHistCount) {

            if(!maxHistCount) $scope.isMaxCircHistoryZero = true;

            egCore.pcrud.search('aacs',
                {target_copy : copyId},
                {   flesh : 2,
                    flesh_fields : {
                        aacs : [
                            'usr',
                            'workstation',
                            'checkin_workstation',
                            'recurring_fine_rule',
                            'circ_staff'
                        ],
                        au : ['card']
                    },
                    order_by : {aacs : 'xact_start desc'},
                    // fetch at least one to see if copy ever circulated
                    limit : $scope.isMaxCircHistoryZero ? 1 : maxHistCount
                }

            ).then(null, null, function(circ) {

                $scope.circ = circ;

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
        $scope.circ_popover_placement = 'top';
        if (!copyId) return;

        egCore.pcrud.search('circbyyr', 
            {copy : copyId}, null, {atomic : true})

        .then(function(counts) {
            var this_year = new Date().getFullYear();
            var prev_year = this_year - 1;

            $scope.circ_counts = counts.reduce(function(circ_counts, circbyyr) {
                var count = Number(circbyyr.count());
                var year = Number(circbyyr.year());

                var index = circ_counts.findIndex(function(existing_count) {
                    return existing_count.year === year;
                });

                if (index === -1) {
                    circ_counts.push({count: count, year: year});
                } else {
                    circ_counts[index].count += count;
                }

                $scope.total_circs += count;
                if (this_year === year) {
                    $scope.total_circs_this_year += count;
                }
                if (prev_year === year) {
                    $scope.total_circs_prev_year += count;
                }

                return circ_counts;
            }, []);

            if ($scope.circ_counts.length > 15) {
                $scope.circ_popover_placement = 'right';
            }
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

    function loadMostRecentTransit() {
        delete $scope.transit;
        delete $scope.hold_transit;
        if (!copyId) return;

        egCore.pcrud.search('atc', 
            {target_copy : copyId},
            {
                order_by : {atc : 'source_send_time DESC'},
                limit : 1
            }

        ).then(null, null, function(transit) {
            // use progress callback since we'll get up to one result
            $scope.transit = transit;
            transit.source(egCore.org.get(transit.source()));
            transit.dest(egCore.org.get(transit.dest()));
        })
    }

    function loadCourseInfo() {
        delete $scope.courses;
        delete $scope.instructors;
        delete $scope.course_ids;
        delete $scope.instructors_exist;
        if (!copyId) return;
        $scope.course_ids = [];
        $scope.courses = [];
        $scope.instructors = {};

        egCore.pcrud.search('acmcm', {
            item: copyId
        }, {
            flesh: 3,
            flesh_fields: {
                acmcm: ['course']
            }, order_by: {acmc : 'id desc'}
        }).then(null, null, function(material) {
            
            $scope.courses.push(material.course());
            egCore.net.request(
                'open-ils.circ',
                'open-ils.circ.course_users.retrieve',
                material.course().id()
            ).then(null, null, function(instructors) {
                angular.forEach(instructors, function(instructor) {
                    var patron_id = instructor.patron_id.toString();
                    if (!$scope.instructors[patron_id]) {
                        $scope.instructors[patron_id] = instructor;
                        $scope.instructors_exist = true;
                        $scope.instructors[patron_id]._linked_course = [];
                    }
                    $scope.instructors[patron_id]._linked_course.push({
                        role: instructor.usr_role,
                        course: material.course().name()
                    });
                });
            });
        });
    }


    // we don't need all data on all tabs, so fetch what's needed when needed.
    function loadTabData() {
        switch($scope.tab) {
            case 'summary':
                loadCurrentCirc();
                loadCircCounts();
                break;

            case 'circs':
                loadCurrentCirc();
                break;

            case 'circ_list':
                loadCircHistory();
                break;

            case 'holds':
                loadHolds()
                loadMostRecentTransit();
                break;

            case 'course':
                loadCourseInfo();
                break;

            case 'triggered_events':
                var url = $location.absUrl().replace(/\/staff\/.*/, '/actor/user/event_log');
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

    $scope.addCopyAlerts = function(copy_id) {
        egCirc.add_copy_alerts([copy_id]).then(function() {
            // force a refresh
            loadCopy($scope.copy.barcode()).then(loadTabData);
        });
    }
    $scope.manageCopyAlerts = function(copy_id) {
        egCirc.manage_copy_alerts([copy_id]).then(function() {
            // force a refresh
            loadCopy($scope.copy.barcode()).then(loadTabData);
        });
    }

    $scope.context.toggleDisplay = function() {
        $location.path('/cat/item/search');
    }

    // handle the barcode scan box, which will replace our current copy
    $scope.context.search = function(args) {
        loadCopy(args.barcode).then(loadTabData);
    }

    $scope.context.show_triggered_events = function() {
        window.open('/eg2/staff/circ/item/event-log/' + copyId, '_blank');
    }

    loadCopy().then(loadTabData);
}])

