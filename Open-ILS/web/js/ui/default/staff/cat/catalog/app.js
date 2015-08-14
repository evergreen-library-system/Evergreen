/**
 * TPAC Frame App
 *
 * currently, this app doesn't use routes for each sub-ui, because 
 * reloading the catalog each time is sloooow.  better so far to 
 * swap out divs w/ ng-if / ng-show / ng-hide as needed.
 *
 */

angular.module('egCatalogApp', ['ui.bootstrap','ngRoute','egCoreMod','egGridMod', 'egMarcMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {delay : 
        ['egStartup', function(egStartup) {return egStartup.go()}]}

    $routeProvider.when('/cat/catalog/index', {
        templateUrl: './cat/catalog/t_catalog',
        controller: 'CatalogCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/catalog/retrieve_by_id', {
        templateUrl: './cat/catalog/t_retrieve_by_id',
        controller: 'CatalogRecordRetrieve',
        resolve : resolver
    });

    $routeProvider.when('/cat/catalog/retrieve_by_tcn', {
        templateUrl: './cat/catalog/t_retrieve_by_tcn',
        controller: 'CatalogRecordRetrieve',
        resolve : resolver
    });

    // create some catalog page-specific mappings
    $routeProvider.when('/cat/catalog/record/:record_id', {
        templateUrl: './cat/catalog/t_catalog',
        controller: 'CatalogCtrl',
        resolve : resolver
    });

    // create some catalog page-specific mappings
    $routeProvider.when('/cat/catalog/record/:record_id/:record_tab', {
        templateUrl: './cat/catalog/t_catalog',
        controller: 'CatalogCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/catalog/batchEdit', {
        templateUrl: './cat/catalog/t_batchedit',
        controller: 'BatchEditCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/catalog/batchEdit/:container_type/:container_id', {
        templateUrl: './cat/catalog/t_batchedit',
        controller: 'BatchEditCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/catalog/vandelay', {
        templateUrl: './cat/catalog/t_vandelay',
        controller: 'VandelayCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/catalog/verifyURLs', {
        templateUrl: './cat/catalog/t_verifyurls',
        controller: 'URLVerifyCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/catalog/manageAuthorities', {
        templateUrl: './cat/catalog/t_manageauthorities',
        controller: 'ManageAuthoritiesCtrl',
        resolve : resolver
    });

    $routeProvider.otherwise({redirectTo : '/cat/catalog/index'});
})


/**
 * */
.controller('CatalogRecordRetrieve',
       ['$scope','$routeParams','$location','$q','egCore',
function($scope , $routeParams , $location , $q , egCore ) {

    $scope.focusMe = true;

    // jump to the patron checkout UI
    function loadRecord(record_id) {
        $location
        .path('/cat/catalog/record/' + record_id);
    }

    $scope.submitId = function(args) {
        $scope.recordNotFound = null;
        if (!args.record_id) return;

        // blur so next time it's set to true it will re-apply select()
        $scope.selectMe = false;

        return loadRecord(args.record_id);
    }

    $scope.submitTCN = function(args) {
        $scope.recordNotFound = null;
        $scope.moreRecordsFound = null;
        if (!args.record_tcn) return;

        // blur so next time it's set to true it will re-apply select()
        $scope.selectMe = false;

        // lookup TCN
        egCore.net.request(
            'open-ils.search',
            'open-ils.search.biblio.tcn',
            args.record_tcn)

        .then(function(resp) { // get_barcodes

            if (evt = egCore.evt.parse(resp)) {
                alert(evt); // FIXME
                return;
            }

            if (!resp.count) {
                $scope.recordNotFound = args.record_tcn;
                $scope.selectMe = true;
                return;
            }

            if (resp.count > 1) {
                $scope.moreRecordsFound = args.record_tcn;
                $scope.selectMe = true;
                return;
            }

            var record_id = resp.ids[0];
            return loadRecord(record_id);
        });
    }

}])

.controller('CatalogCtrl',
       ['$scope','$routeParams','$location','$window','$q','egCore','egHolds','egCirc',
        'egGridDataProvider','egHoldGridActions','$timeout','holdingsSvc',
function($scope , $routeParams , $location , $window , $q , egCore , egHolds , egCirc, 
         egGridDataProvider , egHoldGridActions , $timeout , holdingsSvc) {

    // set record ID on page load if available...
    $scope.record_id = $routeParams.record_id;

    if ($routeParams.record_id) $scope.from_route = true;
    else $scope.from_route = false;

    // will hold a ref to the opac iframe
    $scope.opac_iframe = null;
    $scope.parts_iframe = null;

    $scope.in_opac_call = false;
    $scope.opac_call = function (opac_frame_function, force_opac_tab) {
        if ($scope.opac_iframe) {
            if (force_opac_tab) $scope.record_tab = 'catalog';
            $scope.in_opac_call = true;
            $scope.opac_iframe.dom.contentWindow[opac_frame_function]();
        }
    }

    $scope.stop_unload = false;
    $scope.$watch('stop_unload',
        function(newVal, oldVal) {
            if (newVal && newVal != oldVal && $scope.opac_iframe) {
                $($scope.opac_iframe.dom.contentWindow).on('beforeunload', function(){
                    return 'There is unsaved data in this record.'
                });
            } else {
                if ($scope.opac_iframe)
                    $($scope.opac_iframe.dom.contentWindow).off('beforeunload');
            }
        }
    );

    // Set the "last bib" cookie, if we have that
    if ($scope.record_id)
        egCore.hatch.setLocalItem("eg.cat.last_record_retrieved", $scope.record_id);

    // also set it when the iframe changes to a new record
    $scope.handle_page = function(url) {

        if (!url || url == 'about:blank') {
            // nothing loaded.  If we already have a record ID, leave it.
            return;
        }

        var match = url.match(/\/+opac\/+record\/+(\d+)/);
        if (match) {
            $scope.record_id = match[1];
            egCore.hatch.setLocalItem("eg.cat.last_record_retrieved", $scope.record_id);
            $scope.holdings_record_id_changed($scope.record_id);
            init_parts_url();
        } else {
            delete $scope.record_id;
            $scope.from_route = false;
        }

        // child scope is executing this function, so our digest doesn't fire ... thus,
        $scope.$apply();

        if (!$scope.in_opac_call) {
            if ($scope.record_id) {
                $scope.default_tab = egCore.hatch.getLocalItem( 'eg.cat.default_record_tab' );
                tab = $routeParams.record_tab || $scope.default_tab || 'catalog';
            } else {
                tab = $routeParams.record_tab || 'catalog';
            }
            $scope.set_record_tab(tab);
        } else {
            $scope.in_opac_call = false;
        }
    }

    // xulG catalog handlers
    $scope.handlers = { }

    // ------------------------------------------------------------------
    // Holdings

    $scope.holdingsGridControls = {};
    $scope.holdingsGridDataProvider = egGridDataProvider.instance({
        get : function(offset, count) {
            return this.arrayNotifier(holdingsSvc.copies, offset, count);
        }
    });

    // refresh the list of holdings when the record_id is changed.
    $scope.holdings_record_id_changed = function(id) {
        if ($scope.record_id != id) $scope.record_id = id;
        console.log('record id changed to ' + id + ', loading new holdings');
        holdingsSvc.fetch({
            rid : $scope.record_id,
            org : $scope.holdings_ou,
            copy: $scope.holdings_show_copies,
            vol : $scope.holdings_show_vols,
            empty: $scope.holdings_show_empty
        }).then(function() {
            $scope.holdingsGridDataProvider.refresh();
        });
    }

    // refresh the list of holdings when the filter lib is changed.
    $scope.holdings_ou = egCore.org.get(egCore.auth.user().ws_ou());
    $scope.holdings_ou_changed = function(org) {
        $scope.holdings_ou = org;
        holdingsSvc.fetch({
            rid : $scope.record_id,
            org : $scope.holdings_ou,
            copy: $scope.holdings_show_copies,
            vol : $scope.holdings_show_vols,
            empty: $scope.holdings_show_empty
        }).then(function() {
            $scope.holdingsGridDataProvider.refresh();
        });
    }

    $scope.holdings_cb_changed = function(cb,newVal,norefresh) {
        $scope[cb] = newVal;
        egCore.hatch.setItem('cat.' + cb, newVal);
        if (!norefresh) holdingsSvc.fetch({
            rid : $scope.record_id,
            org : $scope.holdings_ou,
            copy: $scope.holdings_show_copies,
            vol : $scope.holdings_show_vols,
            empty: $scope.holdings_show_empty
        }).then(function() {
            $scope.holdingsGridDataProvider.refresh();
        });
    }

    egCore.hatch.getItem('cat.holdings_show_vols').then(function(x){
        if (typeof x ==  'undefined') x = true;
        $scope.holdings_cb_changed('holdings_show_vols',x,true);
        $('#holdings_show_vols').prop('checked', x);
    }).then(function(){
        egCore.hatch.getItem('cat.holdings_show_copies').then(function(x){
            if (typeof x ==  'undefined') x = true;
            $scope.holdings_cb_changed('holdings_show_copies',x,true);
            $('#holdings_show_copies').prop('checked', x);
        }).then(function(){
            egCore.hatch.getItem('cat.holdings_show_empty').then(function(x){
                if (typeof x ==  'undefined') x = true;
                $scope.holdings_cb_changed('holdings_show_empty',x);
                $('#holdings_show_empty').prop('checked', x);
            })
        })
    });

    $scope.holdings_checkbox_handler = function (item) {
        $scope.holdings_cb_changed(item.checkbox,item.checked);
    }

    function gatherSelectedHoldingsIds () {
        var cp_id_list = [];
        angular.forEach(
            $scope.holdingsGridControls.selectedItems(),
            function (item) { cp_id_list = cp_id_list.concat(item.id_list) }
        );
        return cp_id_list;
    }

    $scope.selectedHoldingsVolCopyEdit = function (){
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            null, 'edit-these-copies', {record_id: $scope.record_id, copies: gatherSelectedHoldingsIds() }
        ).then(function(key) {
            if (key) {
                var url = egCore.env.basePath + 'cat/volcopy/' + key;
                $timeout(function() { $window.open(url, '_blank') });
            } else {
                alert('Could not create anonymous cache key!');
            }
        });
    }

    $scope.selectedHoldingsItemStatus = function (){
        var url = egCore.env.basePath + 'cat/item/search/' + gatherSelectedHoldingsIds().join(',')
        $timeout(function() { $window.open(url, '_blank') });
    }

    $scope.selectedHoldingsItemStatusDetail = function (){
        angular.forEach(
            gatherSelectedHoldingsIds(),
            function (cid) {
                var url = egCore.env.basePath +
                          'cat/item/' + cid;
                $timeout(function() { $window.open(url, '_blank') });
            }
        );
    }

    $scope.selectedHoldingsItemStatusTgrEvt = function (){
        angular.forEach(
            gatherSelectedHoldingsIds(),
            function (cid) {
                var url = egCore.env.basePath +
                          'cat/item/' + cid + '/triggered_events';
                $timeout(function() { $window.open(url, '_blank') });
            }
        );
    }

    $scope.selectedHoldingsItemStatusHolds = function (){
        angular.forEach(
            gatherSelectedHoldingsIds(),
            function (cid) {
                var url = egCore.env.basePath +
                          'cat/item/' + cid + '/holds';
                $timeout(function() { $window.open(url, '_blank') });
            }
        );
    }

    $scope.selectedHoldingsDamaged = function () {
        egCirc.mark_damaged(gatherSelectedHoldingsIds()).then(function() {
            holdingsSvc.fetch({
                rid : $scope.record_id,
                org : $scope.holdings_ou,
                copy: $scope.holdings_show_copies,
                vol : $scope.holdings_show_vols,
                empty: $scope.holdings_show_empty
            }).then(function() {
                $scope.holdingsGridDataProvider.refresh();
            });
        });
    }

    $scope.selectedHoldingsMissing = function () {
        egCirc.mark_missing(gatherSelectedHoldingsIds()).then(function() {
            holdingsSvc.fetch({
                rid : $scope.record_id,
                org : $scope.holdings_ou,
                copy: $scope.holdings_show_copies,
                vol : $scope.holdings_show_vols,
                empty: $scope.holdings_show_empty
            }).then(function() {
                $scope.holdingsGridDataProvider.refresh();
            });
        });
    }


    // ------------------------------------------------------------------
    // Holds 
    var provider = egGridDataProvider.instance({});
    $scope.hold_grid_data_provider = provider;
    $scope.grid_actions = egHoldGridActions;
    $scope.grid_actions.refresh = function () { provider.refresh() };
    $scope.hold_grid_controls = {};

    var hold_ids = []; // current list of holds
    function fetchHolds(offset, count) {
        var ids = hold_ids.slice(offset, offset + count);
        return egHolds.fetch_holds(ids).then(null, null,
            function(hold_data) { 
                return hold_data;
            }
        );
    }

    provider.get = function(offset, count) {
        if ($scope.record_tab != 'holds') return $q.when();
        var deferred = $q.defer();
        hold_ids = []; // no caching ATM

        // fetch the IDs
        egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.holds.retrieve_all_from_title',
            egCore.auth.token(), $scope.record_id, 
            {pickup_lib : egCore.org.descendants($scope.pickup_ou.id(), true)}
        ).then(
            function(hold_data) {
                angular.forEach(hold_data, function(list, type) {
                    hold_ids = hold_ids.concat(list);
                });
                fetchHolds(offset, count).then(
                    deferred.resolve, null, deferred.notify);
            }
        );

        return deferred.promise;
    }

    $scope.detail_view = function(action, user_data, items) {
        if (h = items[0]) {
            $scope.detail_hold_id = h.hold.id();
        }
    }

    $scope.list_view = function(items) {
         $scope.detail_hold_id = null;
    }

    // refresh the list of record holds when the pickup lib is changed.
    $scope.pickup_ou = egCore.org.get(egCore.auth.user().ws_ou());
    $scope.pickup_ou_changed = function(org) {
        $scope.pickup_ou = org;
        provider.refresh();
    }

    $scope.print_holds = function() {
        var holds = [];
        angular.forEach($scope.hold_grid_controls.allItems(), function(item) {
            holds.push({
                hold : egCore.idl.toHash(item.hold),
                patron_last : item.patron_last,
                patron_alias : item.patron_alias,
                patron_barcode : item.patron_barcode,
                copy : egCore.idl.toHash(item.copy),
                volume : egCore.idl.toHash(item.volume),
                title : item.mvr.title(),
                author : item.mvr.author()
            });
        });

        egCore.print.print({
            context : 'receipt', 
            template : 'holds_for_bib', 
            scope : {holds : holds}
        });
    }

    $scope.mark_hold_transfer_dest = function() {
        egCore.hatch.setLocalItem(
            'eg.circ.hold.title_transfer_target', $scope.record_id);
    }

    // UI presents this option as "all holds"
    $scope.transfer_holds_to_marked = function() {
        var hold_ids = $scope.hold_grid_controls.allItems().map(
            function(hold_data) {return hold_data.hold.id()});
        egHolds.transfer_to_marked_title(hold_ids);
    }

    // ------------------------------------------------------------------
    // Initialize the selected tab

    function init_cat_url() {
        // Set the initial catalog URL.  This only happens once.
        // The URL is otherwise generated through user navigation.
        if ($scope.catalog_url) return; 

        var url = $location.absUrl().replace(/\/staff.*/, '/opac/advanced');

        // A record ID in the path indicates a request for the record-
        // specific page.
        if ($routeParams.record_id) {
            url = url.replace(/advanced/, '/record/' + $scope.record_id);
        }

        $scope.catalog_url = url;
    }

    function init_parts_url() {
        $scope.parts_url = $location
            .absUrl()
            .replace(
                /\/staff.*/,
                '/conify/global/biblio/monograph_part?r='+$scope.record_id
            );
    }

    $scope.set_record_tab = function(tab) {
        $scope.record_tab = tab;

        switch(tab) {

            case 'monoparts':
                init_parts_url();
                break;

            case 'catalog':
                init_cat_url();
                break;

            case 'holds':
                $scope.detail_hold_record_id = $scope.record_id; 
                // refresh the holds grid
                provider.refresh();
                break;
        }
    }

    $scope.set_default_record_tab = function() {
        egCore.hatch.setLocalItem(
            'eg.cat.default_record_tab', $scope.record_tab);
        $timeout(function(){$scope.default_tab = $scope.record_tab});
    }

    var tab;
    if ($scope.record_id) {
        $scope.default_tab = egCore.hatch.getLocalItem( 'eg.cat.default_record_tab' );
        tab = $routeParams.record_tab || $scope.default_tab || 'catalog';

    } else {
        tab = $routeParams.record_tab || 'catalog';
    }
    $scope.set_record_tab(tab);

}])

.controller('URLVerifyCtrl',
       ['$scope','$location',
function($scope , $location) {
    $scope.verifyurls_url = $location.absUrl().replace(/\/staff.*/, '/url_verify/sessions');
}])

.controller('VandelayCtrl',
       ['$scope','$location',
function($scope , $location) {
    $scope.vandelay_url = $location.absUrl().replace(/\/staff.*/, '/vandelay/vandelay');
}])

.controller('ManageAuthoritiesCtrl',
       ['$scope','$location',
function($scope , $location) {
    $scope.manageauthorities_url = $location.absUrl().replace(/\/staff.*/, '/cat/authority/list');
}])

.controller('BatchEditCtrl',
       ['$scope','$location','$routeParams',
function($scope , $location , $routeParams) {
    $scope.batchedit_url = $location.absUrl().replace(/\/eg.*/, '/opac/extras/merge_template');
    if ($routeParams.container_type) {
        switch ($routeParams.container_type) {
            case 'bucket':
                $scope.batchedit_url += '?recordSource=b&containerid=' + $routeParams.container_id;
                break;
            case 'record':
                $scope.batchedit_url += '?recordSource=r&recid=' + $routeParams.container_id;
                break;
        };
    }
}])

 
.filter('boolText', function(){
    return function (v) {
        return v == 't';
    }
})

.factory('holdingsSvc', 
       ['egCore','$q',
function(egCore , $q) {

    var service = {
        ongoing : false,
        copies : [], // record search results
        index : 0, // search grid index
        org : null,
        rid : null
    };

    service.flesh = {   
        flesh : 2, 
        flesh_fields : {
            acp : ['status','location'],
            acn : ['prefix','suffix','copies']
        }
    }

    // resolved with the last received copy
    service.fetch = function(opts) {
        if (service.ongoing) {
            console.log('Skipping fetch, ongoing = true');
            return $q.when();
        }

        var rid = opts.rid;
        var org = opts.org;
        var copy = opts.copy;
        var vol = opts.vol;
        var empty = opts.empty;

        if (!rid) return $q.when();
        if (!org) return $q.when();

        service.ongoing = true;

        service.rid = rid;
        service.org = org;
        service.copies = [];
        service.index = 0;

        var org_list = egCore.org.descendants(org.id(), true);
        console.log('Holdings fetch with: rid='+rid+' org='+org_list+' copy='+copy+' vol='+vol+' empty='+empty);

        return egCore.pcrud.search(
            'acn',
            {record : rid, owning_lib : org_list, deleted : 'f'},
            service.flesh
        ).then(
            function() { // finished
                service.copies = service.copies.sort(
                    function (a, b) {
                        function compare_array (x, y, i) {
                            if (x[i] && y[i]) { // both have values
                                if (x[i] == y[i]) { // need to look deeper
                                    return compare_array(x, y, ++i);
                                }

                                if (x[i] < y[i]) { // x is first
                                    return -1;
                                } else if (x[i] > y[i]) { // y is first
                                    return 1;
                                }

                            } else { // no orgs to compare ...
                                if (x[i]) return -1;
                                if (y[i]) return 1;
                            }
                            return 0;
                        }

                        var owner_order = compare_array(a.owner_list, b.owner_list, 0);
                        if (!owner_order) {
                            // now compare on CN label
                            if (a.call_number.label < b.call_number.label) return -1;
                            if (a.call_number.label > b.call_number.label) return 1;

                            // try copy number
                            if (a.copy_number < b.copy_number) return -1;
                            if (a.copy_number > b.copy_number) return 1;

                            // finally, barcode
                            if (a.barcode < b.barcode) return -1;
                            if (a.barcode > b.barcode) return 1;
                        }
                        return owner_order;
                    }
                );

                // create a label using just the unique part of the owner list
                var index = 0;
                var prev_owner_list;
                angular.forEach(service.copies, function (cp) {
                    if (!prev_owner_list) {
                        cp.owner_label = cp.owner_list.join(' ... ');
                    } else {
                        var current_owner_list = cp.owner_list.slice();
                        while (current_owner_list[1] && prev_owner_list[1] && current_owner_list[0] == prev_owner_list[0]) {
                            current_owner_list.shift();
                            prev_owner_list.shift();
                        }
                        cp.owner_label = current_owner_list.join(' ... ');
                    }

                    cp.index = index++;
                    prev_owner_list = cp.owner_list.slice();
                });

                var new_list = service.copies;
                if (!copy || !vol) { // collapse copy rows, supply a count instead

                    index = 0;
                    var cp_list = [];
                    var prev_key;
                    var current_blob = {};
                    angular.forEach(new_list, function (cp) {
                        if (!prev_key) {
                            prev_key = cp.owner_list.join('') + cp.call_number.label;
                            if (cp.barcode) current_blob.copy_count = 1;
                            current_blob.index = index++;
                            current_blob.id_list = cp.id_list;
                            current_blob.call_number = cp.call_number;
                            current_blob.owner_list = cp.owner_list;
                            current_blob.owner_label = cp.owner_label;
                        } else {
                            var current_key = cp.owner_list.join('') + cp.call_number.label;
                            if (prev_key == current_key) { // collapse into current_blob
                                current_blob.copy_count++;
                                current_blob.id_list = current_blob.id_list.concat(cp.id_list);
                            } else {
                                current_blob.barcode = current_blob.copy_count;
                                cp_list.push(current_blob);
                                prev_key = current_key;
                                current_blob = {};
                                if (cp.barcode) current_blob.copy_count = 1;
                                current_blob.index = index++;
                                current_blob.id_list = cp.id_list;
                                current_blob.owner_label = cp.owner_label;
                                current_blob.call_number = cp.call_number;
                                current_blob.owner_list = cp.owner_list;
                            }
                        }
                    });

                    current_blob.barcode = current_blob.copy_count;
                    cp_list.push(current_blob);
                    new_list = cp_list;

                    if (!vol) { // do the same for vol rows

                        index = 0;
                        var cn_list = [];
                        prev_key = '';
                        var current_blob = {};
                        angular.forEach(cp_list, function (cp) {
                            if (!prev_key) {
                                prev_key = cp.owner_list.join('');
                                current_blob.index = index++;
                                current_blob.id_list = cp.id_list;
                                current_blob.cn_count = 1;
                                current_blob.copy_count = cp.copy_count;
                                current_blob.owner_list = cp.owner_list;
                                current_blob.owner_label = cp.owner_label;
                            } else {
                                var current_key = cp.owner_list.join('');
                                if (prev_key == current_key) { // collapse into current_blob
                                    current_blob.cn_count++;
                                    current_blob.copy_count += cp.copy_count;
                                    current_blob.id_list = current_blob.id_list.concat(cp.id_list);
                                } else {
                                    current_blob.barcode = current_blob.copy_count;
                                    current_blob.call_number = { label : current_blob.cn_count };
                                    cn_list.push(current_blob);
                                    prev_key = current_key;
                                    current_blob = {};
                                    current_blob.index = index++;
                                    current_blob.id_list = cp.id_list;
                                    current_blob.owner_label = cp.owner_label;
                                    current_blob.cn_count = 1;
                                    current_blob.copy_count = cp.copy_count;
                                    current_blob.owner_list = cp.owner_list;
                                }
                            }
                        });
    
                        current_blob.barcode = current_blob.copy_count;
                        current_blob.call_number = { label : current_blob.cn_count };
                        cn_list.push(current_blob);
                        new_list = cn_list;
    
                    }
                }

                service.copies = new_list;
                service.ongoing = false;
            },

            null, // error

            // notify reads the stream of copies, one at a time.
            function(cn) {

                var copies = cn.copies();
                cn.copies([]);

                angular.forEach(copies, function (cp) {
                    cp.call_number(cn);
                });

                var flat = egCore.idl.toHash(copies);
                if (flat[0]) {
                    var owner = egCore.org.get(flat[0].call_number.owning_lib);

                    var owner_name_list = [];
                    while (owner.parent_ou()) { // we're going to skip the top of the tree...
                        owner_name_list.unshift(owner.name());
                        owner = egCore.org.get(owner.parent_ou());
                    }

                    angular.forEach(flat, function (cp) {
                        cp.owner_list = owner_name_list;
                        cp.id_list = [cp.id];
                    });

                    service.copies = service.copies.concat(flat);

                    if (empty && flat.length == 0) {
                        service.copies.push({
                            owner_list : owner_name_list,
                            call_number: egCore.idl.toHash(cn)
                        });
                    }
                }

                return cn;
            }
        );
    }

    return service;
}])


