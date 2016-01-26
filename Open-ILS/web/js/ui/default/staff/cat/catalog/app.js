/**
 * TPAC Frame App
 *
 * currently, this app doesn't use routes for each sub-ui, because 
 * reloading the catalog each time is sloooow.  better so far to 
 * swap out divs w/ ng-if / ng-show / ng-hide as needed.
 *
 */

angular.module('egCatalogApp', ['ui.bootstrap','ngRoute','ngLocationUpdate','egCoreMod','egGridMod', 'egMarcMod', 'egUserMod', 'egHoldingsMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {delay : ['egCore','egStartup','egUser', function(egCore, egStartup, egUser) {
        egCore.env.classLoaders.aous = function() {
            return egCore.org.settings([
                'cat.marc_control_number_identifier'
            ]).then(function(settings) {
                // local settings are cached within egOrg.  Caching them
                // again in egEnv just simplifies the syntax for access.
                egCore.env.aous = settings;
            });
        }
        egCore.env.loadClasses.push('aous');
        return egStartup.go()
    }]};

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

    $routeProvider.when('/cat/catalog/new_bib', {
        templateUrl: './cat/catalog/t_new_bib',
        controller: 'NewBibCtrl',
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

    $routeProvider.when('/cat/catalog/authority/:authority_id/marc_edit', {
        templateUrl: './cat/catalog/t_authority',
        controller: 'AuthorityCtrl',
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

.controller('NewBibCtrl',
       ['$scope','$routeParams','$location','$window','$q','egCore',
        'egGridDataProvider','egHoldGridActions','$timeout','holdingsSvc',
function($scope , $routeParams , $location , $window , $q , egCore) {

    $scope.have_template = false;
    $scope.marc_template = '';
    $scope.stop_unload = false;
    $scope.template_list = [];
    $scope.template_name = '';
    $scope.new_bib_id = 0;

    egCore.net.request(
        'open-ils.cat',
        'open-ils.cat.marc_template.types.retrieve'
    ).then(function(resp) {
        angular.forEach(resp, function(name) {
            $scope.template_list.push(name);
        });
        $scope.template_list.sort();
    });
    $scope.template_name = egCore.hatch.getSessionItem('eg.cat.last_bib_marc_template');
    if (!$scope.template_name) {
        egCore.hatch.getItem('cat.default_bib_marc_template').then(function(template) {
            $scope.template_name = template;
        });
    }

    $scope.loadTemplate = function() {
        if ($scope.template_name) {
            egCore.net.request(
                'open-ils.cat',
                'open-ils.cat.biblio.marc_template.retrieve',
                $scope.template_name
            ).then(function(template) {
                $scope.marc_template = template;
                $scope.have_template = true;
                egCore.hatch.setSessionItem('eg.cat.last_bib_marc_template', $scope.template_name);
            });
        }
    }

    $scope.setDefaultTemplate = function() {
        var hatch_key = "cat.default_bib_marc_template";
        if ($scope.template_name) {
            egCore.hatch.setItem(hatch_key, $scope.template_name);
        } else {
            egCore.hatch.removeItem(hatch_key);
        }
    }

    $scope.$watch('new_bib_id', function(newVal, oldVal) {
        if (newVal) {
            $location.path('/cat/catalog/record/' + $scope.new_bib_id);
        }
    });
    

}])

.controller('CatalogCtrl',
       ['$scope','$routeParams','$location','$window','$q','egCore','egHolds','egCirc','egConfirmDialog',
        'egGridDataProvider','egHoldGridActions','$timeout','$modal','holdingsSvc','egUser','conjoinedSvc',
function($scope , $routeParams , $location , $window , $q , egCore , egHolds , egCirc,  egConfirmDialog,
         egGridDataProvider , egHoldGridActions , $timeout , $modal , holdingsSvc , egUser , conjoinedSvc) {

    var holdingsSvcInst = new holdingsSvc();

    // set record ID on page load if available...
    $scope.record_id = $routeParams.record_id;
    $scope.summary_pane_record;

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
            if (opac_frame_function == 'rdetailBackToResults') {
                $location.update_path('/cat/catalog/index');
            }
        }
    }

    $scope.add_to_record_bucket = function() {
        var recId = $scope.record_id;
        return $modal.open({
            templateUrl: './cat/catalog/t_add_to_bucket',
            animation: true,
            size: 'md',
            controller:
                   ['$scope','$modalInstance',
            function($scope , $modalInstance) {

                $scope.bucket_id = 0;
                $scope.newBucketName = '';
                $scope.allBuckets = [];
                egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.container.retrieve_by_class.authoritative',
                    egCore.auth.token(), egCore.auth.user().id(),
                    'biblio', 'staff_client'
                ).then(function(buckets) { $scope.allBuckets = buckets; });

                $scope.add_to_bucket = function() {
                    var item = new egCore.idl.cbrebi();
                    item.bucket($scope.bucket_id);
                    item.target_biblio_record_entry(recId);
                    egCore.net.request(
                        'open-ils.actor',
                        'open-ils.actor.container.item.create',
                        egCore.auth.token(), 'biblio', item
                    ).then(function(resp) {
                        $modalInstance.close();
                    });
                }

                $scope.add_to_new_bucket = function() {
                    var bucket = new egCore.idl.cbreb();
                    bucket.owner(egCore.auth.user().id());
                    bucket.name($scope.newBucketName);
                    bucket.description('');
                    bucket.btype('staff_client');

                    egCore.net.request(
                        'open-ils.actor',
                        'open-ils.actor.container.create',
                        egCore.auth.token(), 'biblio', bucket
                    ).then(function(bucket) {
                        $scope.bucket_id = bucket;
                        $scope.add_to_bucket();
                    });
                }

                $scope.cancel = function() {
                    $modalInstance.dismiss();
                }
            }]
        });
    }

    $scope.current_overlay_target     = egCore.hatch.getLocalItem('eg.cat.marked_overlay_record');
    $scope.current_voltransfer_target = egCore.hatch.getLocalItem('eg.cat.marked_volume_transfer_record');
    $scope.current_conjoined_target   = egCore.hatch.getLocalItem('eg.cat.marked_conjoined_record');

    $scope.markConjoined = function () {
        $scope.current_conjoined_target = $scope.record_id;
        egCore.hatch.setLocalItem('eg.cat.marked_conjoined_record',$scope.record_id);
    };

    $scope.markVolTransfer = function () {
        $scope.current_voltransfer_target = $scope.record_id;
        egCore.hatch.setLocalItem('eg.cat.marked_volume_transfer_record',$scope.record_id);
    };

    $scope.markOverlay = function () {
        $scope.current_overlay_target = $scope.record_id;
        egCore.hatch.setLocalItem('eg.cat.marked_overlay_record',$scope.record_id);
    };

    $scope.clearRecordMarks = function () {
        $scope.current_overlay_target     = null;
        $scope.current_voltransfer_target = null;
        $scope.current_conjoined_target   = null;
        egCore.hatch.removeLocalItem('eg.cat.marked_volume_transfer_record');
        egCore.hatch.removeLocalItem('eg.cat.marked_conjoined_record');
        egCore.hatch.removeLocalItem('eg.cat.marked_overlay_record');
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

    $scope.refresh_record_callback = function (record_id) {
        egCore.pcrud.retrieve('bre', record_id, {
            flesh : 1,
            flesh_fields : {
                bre : ['simple_record','creator','editor']
            }
        }).then(function(rec) {
            rec.owner(egCore.org.get(rec.owner()));
            $scope.summary_pane_record = rec;
        });

        return record_id;
    }

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
            conjoinedSvc.fetch($scope.record_id).then(function(){
                $scope.conjoinedGridDataProvider.refresh();
            });
            init_parts_url();
            $location.update_path('/cat/catalog/record/' + $scope.record_id);
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
    // Conjoined items

    $scope.conjoinedGridControls = {};
    $scope.conjoinedGridDataProvider = egGridDataProvider.instance({
        get : function(offset, count) {
            return this.arrayNotifier(conjoinedSvc.items, offset, count);
        }
    });

    $scope.changeConjoinedType = function () {
        var peers = egCore.idl.Clone($scope.conjoinedGridControls.selectedItems());
        angular.forEach(peers, function (p) {
            p.target_copy(p.target_copy().id());
            p.peer_type(p.peer_type().id());
        });

        var conjoinedGridDataProviderRef = $scope.conjoinedGridDataProvider;

        return $modal.open({
            templateUrl: './cat/catalog/t_conjoined_selector',
            animation: true,
            controller:
                   ['$scope','$modalInstance',
            function($scope , $modalInstance) {
                $scope.update = true;

                $scope.peer_type = null;
                $scope.peer_type_list = [];
                conjoinedSvc.get_peer_types().then(function(list){
                    $scope.peer_type_list = list;
                });
    
                $scope.ok = function(type) {
                    var promises = [];
    
                    angular.forEach(peers, function (p) {
                        p.ischanged(1);
                        p.peer_type(type);
                        promises.push(egCore.pcrud.update(p));
                    });
    
                    return $q.all(promises)
                        .then(function(){$modalInstance.close()})
                        .then(function(){return conjoinedSvc.fetch()})
                        .then(function(){conjoinedGridDataProviderRef.refresh()});
                }
    
                $scope.cancel = function($event) {
                    $modalInstance.dismiss();
                    $event.preventDefault();
                }
            }]
        });
        
    }

    $scope.refreshConjoined = function () {
        conjoinedSvc.fetch($scope.record_id)
        .then(function(){$scope.conjoinedGridDataProvider.refresh();});
    }

    $scope.deleteSelectedConjoined = function () {
        var peers = $scope.conjoinedGridControls.selectedItems();

        if (peers.length > 0) {
            egConfirmDialog.open(
                egCore.strings.CONFIRM_DELETE_PEERS,
                egCore.strings.CONFIRM_DELETE_PEERS_MESSAGE,
                {peers : peers.length}
            ).result.then(function() {
                angular.forEach(peers, function (p) {
                    p.isdeleted(1);
                });

                egCore.pcrud.remove(peers).then(function() {
                    return conjoinedSvc.fetch();
                }).then(function() {
                    $scope.conjoinedGridDataProvider.refresh();
                });
            });
        }
    }
    if ($scope.record_id)
        conjoinedSvc.fetch($scope.record_id);

    // ------------------------------------------------------------------
    // Holdings

    $scope.holdingsGridControls = {
        activateItem : function (item) {
            $scope.selectedHoldingsVolCopyEdit();
        }
    };
    $scope.holdingsGridDataProvider = egGridDataProvider.instance({
        get : function(offset, count) {
            return this.arrayNotifier(holdingsSvcInst.copies, offset, count);
        }
    });

    $scope.add_copies_to_bucket = function() {
        var copy_list = gatherSelectedHoldingsIds();
        if (copy_list.length == 0) return;

        return $modal.open({
            templateUrl: './cat/catalog/t_add_to_bucket',
            animation: true,
            size: 'md',
            controller:
                   ['$scope','$modalInstance',
            function($scope , $modalInstance) {

                $scope.bucket_id = 0;
                $scope.newBucketName = '';
                $scope.allBuckets = [];

                egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.container.retrieve_by_class.authoritative',
                    egCore.auth.token(), egCore.auth.user().id(),
                    'copy', 'staff_client'
                ).then(function(buckets) { $scope.allBuckets = buckets; });

                $scope.add_to_bucket = function() {
                    var promises = [];
                    angular.forEach(copy_list, function (cp) {
                        var item = new egCore.idl.ccbi()
                        item.bucket($scope.bucket_id);
                        item.target_copy(cp);
                        promises.push(
                            egCore.net.request(
                                'open-ils.actor',
                                'open-ils.actor.container.item.create',
                                egCore.auth.token(), 'copy', item
                            )
                        );

                        return $q.all(promises).then(function() {
                            $modalInstance.close();
                        });
                    });
                }

                $scope.add_to_new_bucket = function() {
                    var bucket = new egCore.idl.ccb();
                    bucket.owner(egCore.auth.user().id());
                    bucket.name($scope.newBucketName);
                    bucket.description('');
                    bucket.btype('staff_client');

                    return egCore.net.request(
                        'open-ils.actor',
                        'open-ils.actor.container.create',
                        egCore.auth.token(), 'copy', bucket
                    ).then(function(bucket) {
                        $scope.bucket_id = bucket;
                        $scope.add_to_bucket();
                    });
                }

                $scope.cancel = function() {
                    $modalInstance.dismiss();
                }
            }]
        });
    }

    $scope.requestItems = function() {
        var copy_list = gatherSelectedHoldingsIds();
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

    $scope.replaceBarcodes = function() {
        var copy_list = gatherSelectedRawCopies();
        if (copy_list.length == 0) return;

        var holdingsGridDataProviderRef = $scope.holdingsGridDataProvider;

        angular.forEach(copy_list, function (cp) {
            $modal.open({
                templateUrl: './cat/share/t_replace_barcode',
                animation: true,
                controller:
                           ['$scope','$modalInstance',
                    function($scope , $modalInstance) {
                        $scope.isModal = true;
                        $scope.focusBarcode = false;
                        $scope.focusBarcode2 = true;
                        $scope.barcode1 = cp.barcode();

                        $scope.updateBarcode = function() {
                            $scope.copyNotFound = false;
                            $scope.updateOK = false;
                
                            egCore.pcrud.search('acp',
                                {deleted : 'f', barcode : $scope.barcode1})
                            .then(function(copy) {
                
                                if (!copy) {
                                    $scope.focusBarcode = true;
                                    $scope.copyNotFound = true;
                                    return;
                                }
                
                                $scope.copyId = copy.id();
                                copy.barcode($scope.barcode2);
                
                                egCore.pcrud.update(copy).then(function(stat) {
                                    $scope.updateOK = stat;
                                    $scope.focusBarcode = true;
                                    holdingsSvc.fetchAgain().then(function (){
                                        holdingsGridDataProviderRef.refresh();
                                    });
                                });

                            });
                            $modalInstance.close();
                        }

                        $scope.cancel = function($event) {
                            $modalInstance.dismiss();
                            $event.preventDefault();
                        }
                    }
                ]
            });
        });
    }

    // refresh the list of holdings when the record_id is changed.
    $scope.holdings_record_id_changed = function(id) {
        if ($scope.record_id != id) $scope.record_id = id;
        console.log('record id changed to ' + id + ', loading new holdings');
        holdingsSvcInst.fetch({
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
        holdingsSvcInst.fetch({
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
        if (!norefresh) holdingsSvcInst.fetch({
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

    $scope.vols_not_shown = function () {
        return !$scope.holdings_show_vols;
    }

    $scope.copies_not_shown = function () {
        return !$scope.holdings_show_copies;
    }

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

    function gatherSelectedRawCopies () {
        var cp_list = [];
        angular.forEach(
            $scope.holdingsGridControls.selectedItems(),
            function (item) { if (item.raw) cp_list = cp_list.concat(item.raw) }
        );
        return cp_list;
    }

    function gatherSelectedEmptyVolumeIds () {
        var cn_id_list = [];
        angular.forEach(
            $scope.holdingsGridControls.selectedItems(),
            function (item) {
                if (item.copy_count == 0)
                    cn_id_list.push(item.call_number.id)
            }
        );
        return cn_id_list;
    }

    function gatherSelectedVolumeIds () {
        var cn_id_list = [];
        angular.forEach(
            $scope.holdingsGridControls.selectedItems(),
            function (item) {
                if (cn_id_list.indexOf(item.call_number.id) == -1)
                    cn_id_list.push(item.call_number.id)
            }
        );
        return cn_id_list;
    }

    $scope.selectedHoldingsDelete = function (vols, copies) {

        var cnHash = {};
        var perCnCopies = {};

        var cn_count = 0;
        var cp_count = 0;

        angular.forEach(
            $scope.holdingsGridControls.selectedItems(),
            function (item) {
                if (vols && item.raw_call_number) {
                    cnHash[item.call_number.id] = egCore.idl.Clone(item.raw_call_number);
                    cnHash[item.call_number.id].isdeleted(1);
                    cn_count++;
                } else if (copies) {
                    angular.forEach(egCore.idl.Clone(item.raw), function (cp) {
                        cp.isdeleted(1);
                        cp_count++;
                        var cn_id = cp.call_number().id();
                        if (!cnHash[cn_id]) {
                            cnHash[cn_id] = cp.call_number();
                            perCnCopies[cn_id] = [cp];
                        } else {
                            perCnCopies[cn_id].push(cp);
                        }
                        cp.call_number(cn_id); // prevent loops in JSON-ification
                    });

                }
            }
        );

        angular.forEach(perCnCopies, function (v, k) {
            if (vols) {
                cnHash[k].isdeleted(1);
                cn_count++;
            }
            cnHash[k].copies(v);
        });

        cnList = [];
        angular.forEach(cnHash, function (v, k) {
            cnList.push(v);
        });

        if (cnList.length == 0) return;

        var flags = {};
        if (vols && copies) flags.force_delete_copies = 1;

        egConfirmDialog.open(
            egCore.strings.CONFIRM_DELETE_COPIES_VOLUMES,
            egCore.strings.CONFIRM_DELETE_COPIES_VOLUMES_MESSAGE,
            {copies : cp_count, volumes : cn_count}
        ).result.then(function() {
            egCore.net.request(
                'open-ils.cat',
                'open-ils.cat.asset.volume.fleshed.batch.update.override',
                egCore.auth.token(), cnList, 1, flags
            ).then(function(update_count) {
                holdingsSvcInst.fetchAgain().then(function() {
                    $scope.holdingsGridDataProvider.refresh();
                });
            });
        });
    }
    $scope.selectedHoldingsCopyDelete = function () { $scope.selectedHoldingsDelete(false,true) }
    $scope.selectedHoldingsVolCopyDelete = function () { $scope.selectedHoldingsDelete(true,true) }
    $scope.selectedHoldingsEmptyVolCopyDelete = function () { $scope.selectedHoldingsDelete(true,false) }

    spawnHoldingsAdd = function (vols,copies){
        var raw = [];
        if (copies) { // just a copy on existing volumes
            angular.forEach(gatherSelectedVolumeIds(), function (v) {
                raw.push( {callnumber : v} );
            });
        } else if (vols) {
            angular.forEach(
                $scope.holdingsGridControls.selectedItems(),
                function (item) {
                    raw.push({owner : item.owner_id});
                }
            );
        }

        if (raw.length == 0) raw.push({});

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            null, 'edit-these-copies', {
                record_id: $scope.record_id,
                raw: raw,
                hide_vols : false,
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
    $scope.selectedHoldingsVolCopyAdd = function () { spawnHoldingsAdd(true,false) }
    $scope.selectedHoldingsCopyAdd = function () { spawnHoldingsAdd(false,true) }

    spawnHoldingsEdit = function (hide_vols,hide_copies){
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            null, 'edit-these-copies', {
                record_id: $scope.record_id,
                copies: gatherSelectedHoldingsIds(),
                raw: gatherSelectedEmptyVolumeIds().map(
                    function(v){ return { callnumber : v } }
                ),
                hide_vols : hide_vols,
                hide_copies : hide_copies
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
    $scope.selectedHoldingsVolCopyEdit = function () { spawnHoldingsEdit(false,false) }
    $scope.selectedHoldingsVolEdit = function () { spawnHoldingsEdit(false,true) }
    $scope.selectedHoldingsCopyEdit = function () { spawnHoldingsEdit(true,false) }

    $scope.selectedHoldingsItemStatus = function (){
        var url = egCore.env.basePath + 'cat/item/search/' + gatherSelectedHoldingsIds().join(',')
        $timeout(function() { $window.open(url, '_blank') });
    }

    $scope.markVolAsItemTarget = function() {
        if ($scope.holdingsGridControls.selectedItems()[0].call_number.id) { // cn.id missing when vols are collapsed
            egCore.hatch.setLocalItem(
                'eg.cat.item_transfer_target',
                $scope.holdingsGridControls.selectedItems()[0].call_number.id
            );
        }
    }

    $scope.markLibAsVolTarget = function() {
        return $modal.open({
            templateUrl: './cat/catalog/t_choose_vol_target_lib',
            animation: true,
            controller:
                   ['$scope','$modalInstance',
            function($scope , $modalInstance) {

                var orgId = egCore.hatch.getLocalItem('eg.cat.volume_transfer_target') || 1;
                $scope.org = egCore.org.get(orgId);
                $scope.cant_have_vols = function (id) { return !egCore.org.CanHaveVolumes(id); };
                $scope.ok = function(org) {
                    egCore.hatch.setLocalItem(
                        'eg.cat.volume_transfer_target',
                        org.id()
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
    $scope.markLibFromSelectedAsVolTarget = function() {
        egCore.hatch.setLocalItem(
            'eg.cat.volume_transfer_target',
            $scope.holdingsGridControls.selectedItems()[0].owner_id
        );
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

    $scope.transferVolumesToRecord = function (){
        var target_record = egCore.hatch.getLocalItem('eg.cat.marked_volume_transfer_record');
        if (!target_record) return;
        if ($scope.record_id == target_record) return;
        var items = $scope.holdingsGridControls.selectedItems();
        if (!items.length) return;

        var vols_to_move   = {};
        angular.forEach(items, function(item) {
            if (!(item.call_number.owning_lib in vols_to_move)) {
                vols_to_move[item.call_number.owning_lib] = new Array;
            }
            vols_to_move[item.call_number.owning_lib].push(item.call_number.id);
        });

        var promises = [];        
        angular.forEach(vols_to_move, function(vols, owning_lib) {
            promises.push(egCore.net.request(
                'open-ils.cat',
                'open-ils.cat.asset.volume.batch.transfer.override',
                egCore.auth.token(), {
                    docid   : target_record,
                    lib     : owning_lib,
                    volumes : vols
                }
            ));
        });
        $q.all(promises).then(function(success) {
            if (success) {
                holdingsSvcInst.fetchAgain().then(function() {
                    $scope.holdingsGridDataProvider.refresh();
                });
            } else {
                alert('Could not transfer volumes!');
            }
        });
    }

    $scope.transferVolumes = function (new_record){
        var xfer_target = egCore.hatch.getLocalItem('eg.cat.volume_transfer_target');

        if (xfer_target) {
            egCore.net.request(
                'open-ils.cat',
                'open-ils.cat.asset.volume.batch.transfer.override',
                egCore.auth.token(), {
                    docid   : (new_record ? new_record : $scope.record_id),
                    lib     : xfer_target,
                    volumes : gatherSelectedVolumeIds()
                }
            ).then(function(success) {
                if (success) {
                    holdingsSvcInst.fetchAgain().then(function() {
                        $scope.holdingsGridDataProvider.refresh();
                    });
                } else {
                    alert('Could not transfer volumes!');
                }
            });
        }
        
    }

    $scope.transferVolumesToRecordAndLibrary = function() {
        var target_record = egCore.hatch.getLocalItem('eg.cat.marked_volume_transfer_record');
        if (!target_record) return;
        $scope.transferVolumes(target_record);
    }

    // this "transfers" selected copies to a new owning library,
    // auto-creating volumes and deleting unused volumes as required.
    $scope.changeItemOwningLib = function() {
        var xfer_target = egCore.hatch.getLocalItem('eg.cat.volume_transfer_target');
        var items = $scope.holdingsGridControls.selectedItems();
        if (!xfer_target || !items.length) {
            return;
        }
        var vols_to_move   = {};
        var copies_to_move = {};
        angular.forEach(items, function(item) {
            if (item.call_number.owning_lib != xfer_target) {
                if (item.call_number.id in vols_to_move) {
                    copies_to_move[item.call_number.id].push(item.id);
                } else {
                    vols_to_move[item.call_number.id] = item.call_number;
                    copies_to_move[item.call_number.id] = new Array;
                    copies_to_move[item.call_number.id].push(item.id);
                }
            }
        });
    
        var promises = [];
        angular.forEach(vols_to_move, function(vol) {
            promises.push(egCore.net.request(
                'open-ils.cat',
                'open-ils.cat.call_number.find_or_create',
                egCore.auth.token(),
                vol.label,
                vol.record,
                xfer_target,
                vol.prefix.id,
                vol.suffix.id,
                vol.label_class
            ).then(function(resp) {
                var evt = egCore.evt.parse(resp);
                if (evt) return;
                return egCore.net.request(
                    'open-ils.cat',
                    'open-ils.cat.transfer_copies_to_volume',
                    egCore.auth.token(),
                    resp.acn_id,
                    copies_to_move[vol.id]
                );
            }));
        });
        $q.all(promises).then(function() {
            holdingsSvcInst.fetchAgain().then(function() {
                $scope.holdingsGridDataProvider.refresh();
            });
        });
    }

    $scope.transferItems = function (){
        var xfer_target = egCore.hatch.getLocalItem('eg.cat.item_transfer_target');
        var copy_ids = gatherSelectedHoldingsIds();
        if (xfer_target && copy_ids.length > 0) {
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
                            egCore.strings.OVERRIDE_TRANSFER_COPIES_TO_MARKED_VOLUME_TITLE,
                            egCore.strings.OVERRIDE_TRANSFER_COPIES_TO_MARKED_VOLUME_BODY,
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
                                holdingsSvcInst.fetchAgain().then(function() {
                                    $scope.holdingsGridDataProvider.refresh();
                                });
                            });
                        });
                    } else {
                        holdingsSvcInst.fetchAgain().then(function() {
                            $scope.holdingsGridDataProvider.refresh();
                        });
                    }
                },
                null, // onerror
                null // onprogress
            )
        }
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
            holdingsSvcInst.fetchAgain().then(function() {
                $scope.holdingsGridDataProvider.refresh();
            });
        });
    }

    $scope.selectedHoldingsMissing = function () {
        egCirc.mark_missing(gatherSelectedHoldingsIds()).then(function() {
            holdingsSvcInst.fetchAgain().then(function() {
                $scope.holdingsGridDataProvider.refresh();
            });
        });
    }

    $scope.attach_to_peer_bib = function() {
        var copy_list = gatherSelectedHoldingsIds();
        if (copy_list.length == 0) return;

        egCore.hatch.getItem('eg.cat.marked_conjoined_record').then(function(target_record) {
            if (!target_record) return;

            return $modal.open({
                templateUrl: './cat/catalog/t_conjoined_selector',
                animation: true,
                controller:
                       ['$scope','$modalInstance',
                function($scope , $modalInstance) {
                    $scope.update = false;

                    $scope.peer_type = null;
                    $scope.peer_type_list = [];
                    conjoinedSvc.get_peer_types().then(function(list){
                        $scope.peer_type_list = list;
                    });
    
                    $scope.ok = function(type) {
                        var promises = [];
    
                        angular.forEach(copy_list, function (cp) {
                            var n = new egCore.idl.bpbcm();
                            n.isnew(true);
                            n.peer_record(target_record);
                            n.target_copy(cp);
                            n.peer_type(type);
                            promises.push(egCore.pcrud.create(n));
                        });
    
                        return $q.all(promises).then(function(){$modalInstance.close()});
                    }
    
                    $scope.cancel = function($event) {
                        $modalInstance.dismiss();
                        $event.preventDefault();
                    }
                }]
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

.controller('AuthorityCtrl',
       ['$scope','$routeParams','$location','$window','$q','egCore',
function($scope , $routeParams , $location , $window , $q , egCore) {

    // set record ID on page load if available...
    $scope.authority_id = $routeParams.authority_id;

    if ($routeParams.authority_id) $scope.from_route = true;
    else $scope.from_route = false;

    $scope.stop_unload = false;
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

.factory('conjoinedSvc', 
       ['egCore','$q',
function(egCore , $q) {

    var service = {
        items : [], // record search results
        index : 0, // search grid index
        rid : null
    };

    service.flesh = {   
        flesh : 4, 
        flesh_fields : {
            bpbcm : ['target_copy','peer_type'],
            acp : ['call_number'],
            acn : ['record'],
            bre : ['simple_record']
        },
        // avoid fetching the MARC blob by specifying which
        // fields on the bre to select.  More may be needed.
        // note that fleshed fields are explicitly selected.
        select : { bre : ['id'] },
        order_by : { bpbcm : ['id'] },
    }

    // resolved with the last received copy
    service.fetch = function(rid) {
        if (!rid && !service.rid) return $q.when();

        if (rid) service.rid = rid;
        service.items = [];
        service.index = 0;

        return egCore.pcrud.search(
            'bpbcm',
            {peer_record : service.rid},
            service.flesh,
            {atomic : true}
        ).then( function(list) { // finished
            service.items = list;
            return service.items;
        });
    }

    // returns a promise resolved with the list of peer bib types
    service.get_peer_types = function() {
        if (egCore.env.bpt)
            return $q.when(egCore.env.bpt.list);

        return egCore.pcrud.retrieveAll('bpt', null, {atomic : true})
        .then(function(list) {
            egCore.env.absorbList(list, 'bpt');
            return list;
        });
    };

    return service;
}])


