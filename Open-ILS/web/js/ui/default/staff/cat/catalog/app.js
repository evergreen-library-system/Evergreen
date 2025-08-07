/**
 * TPAC Frame App
 *
 * currently, this app doesn't use routes for each sub-ui, because 
 * reloading the catalog each time is sloooow.  better so far to 
 * swap out divs w/ ng-if / ng-show / ng-hide as needed.
 *
 */

angular.module('egCatalogApp', ['ui.bootstrap','ngRoute','ngLocationUpdate','egCoreMod','egGridMod', 'egMarcMod', 'egUserMod', 'egHoldingsMod', 'ngToast','egPatronSearchMod',
'egSerialsMod','egSerialsAppDep'])

.config(['ngToastProvider', function(ngToastProvider) {
  ngToastProvider.configure({
    verticalPosition: 'bottom',
    animation: 'fade'
  });
}])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export

    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/cat/catalog/index', {
        templateUrl: './cat/catalog/t_catalog',
        controller: 'CatalogCtrl',
        resolve : resolver
    });

    // Jump directly to the results page.  Any URL parameter 
    // supported by the embedded catalog is supported here.
    $routeProvider.when('/cat/catalog/results', {
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

    $routeProvider.when('/cat/catalog/retrieve_by_authority_id', {
        templateUrl: './cat/catalog/t_retrieve_by_authority_id',
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

    function loadAuthorityRecord(record_id) {
        $location
        .path('/cat/catalog/authority/' + record_id + '/marc_edit');
    }

    $scope.submitId = function(args) {
        $scope.recordNotFound = null;
        if (!args.record_id) return;

        // blur so next time it's set to true it will re-apply select()
        $scope.selectMe = false;

        return loadRecord(args.record_id);
    }

    $scope.submitAuthorityId = function(args) {
        if (!args.record_id) return;

        // blur so next time it's set to true it will re-apply select()
        $scope.selectMe = false;

        return loadAuthorityRecord(args.record_id);
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

            if (resp.count) {
                return $q.when(resp);
            } else {
                // Search again including deleted records
                return egCore.net.request('open-ils.search', 
                    'open-ils.search.biblio.tcn', args.record_tcn, true);
            }

        }).then(function(resp2) {

            if (!resp2.count) {
                $scope.recordNotFound = args.record_tcn;
                $scope.selectMe = true;
                return;
            }

            if (resp2.count > 1) {
                $scope.moreRecordsFound = args.record_tcn;
                $scope.selectMe = true;
                return;
            }

            var record_id = resp2.ids[0];
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

    egCore.strings.setPageTitle(egCore.strings.PAGE_TITLE_CREATE_MARC);

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
            ).then(function(xml) {
                let new_record = new MARC21.Record();
                new_record.fromXmlString(xml);
                new_record.generate008();

                // now we need to redo the date (not sure why generate008() sometimes gives us spaces)
                var now = new Date();
                var y = now.getUTCFullYear().toString().substr(2,2);
                var m = now.getUTCMonth() + 1;
                if (m < 10) m = '0' + m;
                var d = now.getUTCDate();
                if (d < 10) d = '0' + d;
                let new_008_data = y + m + d + new_record.field('008').data.substring(6);
                new_record.field('008').update(new_008_data);

                $scope.marc_template = new_record.toXmlString();
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
            location.href = '/eg2/staff/catalog/record/' + $scope.new_bib_id;
        }
    });
    

}])

.directive('autoFocus', function($timeout) {
    return {
        restrict: 'AC',
        link: function(_scope, _element) {
            $timeout(function(){
                _element[0].focus();
            }, 0);
        }
    };
})

.directive('focusOnShow', function($timeout) {
    return {
        restrict: 'A',
        link: function($scope, $element, $attr) {
            if ($attr.ngShow){
                $scope.$watch($attr.ngShow, function(newValue){
                    if(newValue){
                        $timeout(function(){
                            $element[0].focus();
                        }, 0);
                    }
                })
            }
            if ($attr.ngHide){
                $scope.$watch($attr.ngHide, function(newValue){
                    if(!newValue){
                        $timeout(function(){
                            $element[0].focus();
                        }, 0);
                    }
                })
            }

        }
    };
})

.controller('CatalogCtrl',
       ['$scope','$routeParams','$location','$window','$q','egCore','egHolds','egCirc','egConfirmDialog','ngToast',
        'egGridDataProvider','egHoldGridActions','egProgressDialog','$timeout','$uibModal','holdingsSvc','egUser','conjoinedSvc',
        '$cookies','egSerialsCoreSvc',
function($scope , $routeParams , $location , $window , $q , egCore , egHolds , egCirc , egConfirmDialog , ngToast ,
         egGridDataProvider , egHoldGridActions , egProgressDialog , $timeout , $uibModal , holdingsSvc , egUser , conjoinedSvc,
         $cookies , egSerialsCoreSvc
) {

    var holdingsSvcInst = new holdingsSvc();

    // set record ID on page load if available...
    $scope.record_id = $routeParams.record_id;
    $scope.summary_pane_record;

    if ($scope.record_id) {
        // TODO: Apply tab-specific title contexts
        egCore.strings.setPageTitle(
            egCore.strings.PAGE_TITLE_BIB_DETAIL,
            egCore.strings.PAGE_TITLE_CATALOG_CONTEXT,
            {record_id : $scope.record_id}
        );
    } else {
        // Default to title = Catalog
        egCore.strings.setPageTitle(
            egCore.strings.PAGE_TITLE_CATALOG_CONTEXT);
    }

    if ($routeParams.record_id) $scope.from_route = true;
    else $scope.from_route = false;

    // set search and preferred library cookies
    egCore.hatch.getItem('eg.search.search_lib').then(function(val) {
        $cookies.put('eg_search_lib', val, { path : '/' });
    });
    egCore.hatch.getItem('eg.search.pref_lib').then(function(val) {
        $cookies.put('eg_pref_lib', val, { path : '/' });
    });

    // will hold a ref to the opac iframe
    $scope.opac_iframe = null;
    $scope.parts_iframe = null;

    $scope.search_result_index = 1;
    $scope.search_result_hit_count = 1;

    $scope.$watch(
        'opac_iframe.dom.contentWindow.search_result_index',
        function (n,o) {
            if (!isNaN(parseInt(n)))
                $scope.search_result_index = n + 1;
        }
    );

    $scope.$watch(
        'opac_iframe.dom.contentWindow.search_result_hit_count',
        function (n,o) {
            if (!isNaN(parseInt(n)))
                $scope.search_result_hit_count = n;
        }
    );

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

    $scope.add_cart_to_record_bucket = function() {
        var cartkey = $cookies.get('cartcache');
        if (!cartkey) return;
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.get_value',
            cartkey,
            'mylist'
        ).then(function(list) {
            list = list.map(function(x) {
                return parseInt(x);
            });
            $scope.add_to_record_bucket(list);
        });
    }

    $scope.add_to_record_bucket = function(recs) {
        if (!angular.isArray(recs)) {
            recs = [ $scope.record_id ];
        }
        return $uibModal.open({
            templateUrl: './cat/catalog/t_add_to_bucket',
            backdrop: 'static',
            animation: true,
            size: 'md',
            controller:
                   ['$scope','$uibModalInstance',
            function($scope , $uibModalInstance) {

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
                    var promises = [];
                    angular.forEach(recs, function(recId) {
                        var item = new egCore.idl.cbrebi();
                        item.bucket($scope.bucket_id);
                        item.target_biblio_record_entry(recId);
                        promises.push(egCore.net.request(
                            'open-ils.actor',
                            'open-ils.actor.container.item.create',
                            egCore.auth.token(), 'biblio', item
                        ));
                    });
                    $q.all(promises).then(function(resp) {
                        $uibModalInstance.close();
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
                    $uibModalInstance.dismiss();
                }
            }]
        });
    }

    $scope.carousels_available = false;
    egCore.net.request(
        'open-ils.actor',
        'open-ils.actor.carousel.retrieve_manual_by_staff',
        egCore.auth.token()
    ).then(function(carousels) { $scope.carousels_available = true; });

    $scope.add_to_carousel = function(recs) {
        if (!angular.isArray(recs)) {
            recs = [ $scope.record_id ];
        }
        return $uibModal.open({
            templateUrl: './cat/catalog/t_add_to_carousel',
            backdrop: 'static',
            animation: true,
            size: 'md',
            controller:
                   ['$scope','$uibModalInstance',
            function($scope , $uibModalInstance) {
                $scope.bucket_id = 0;
                $scope.allCarousels = [];
                egCore.net.request(
                    'open-ils.actor',
                    'open-ils.actor.carousel.retrieve_manual_by_staff',
                    egCore.auth.token()
                ).then(function(carousels) { $scope.allCarousels = carousels; });

                $scope.add_to_carousel = function() {
                    // or more precisely, the carousel's bucket
                    var promises = [];
                    angular.forEach(recs, function(recId) {
                        var item = new egCore.idl.cbrebi();
                        item.bucket($scope.bucket_id);
                        item.target_biblio_record_entry(recId);
                        promises.push(egCore.net.request(
                            'open-ils.actor',
                            'open-ils.actor.container.item.create',
                            egCore.auth.token(), 'biblio', item
                        ));
                    });
                    $q.all(promises).then(function(resp) {
                        $uibModalInstance.close();
                    });
                }

                $scope.cancel = function() {
                    $uibModalInstance.dismiss();
                }
            }]
        });
    }

    $scope.current_overlay_target     = egCore.hatch.getLocalItem('eg.cat.marked_overlay_record');
    $scope.current_transfer_target    = egCore.hatch.getLocalItem('eg.cat.transfer_target_record');
    $scope.current_conjoined_target   = egCore.hatch.getLocalItem('eg.cat.marked_conjoined_record');

    $scope.quickReceive = function () {
        var list = [];
        var next_per_stream = {};

        var recId = $scope.record_id;
        return $uibModal.open({
            templateUrl: './share/t_subscription_select_dialog',
            backdrop: 'static',
            controller: ['$scope', '$uibModalInstance',
                function($scope, $uibModalInstance) {

                    $scope.focus = true;
                    $scope.rememberMe = 'eg.serials.quickreceive.last_org';
                    $scope.record_id = recId;
                    $scope.ssubId = null;

                    $scope.ok = function() { $uibModalInstance.close($scope.ssubId) }
                    $scope.cancel = function() { $uibModalInstance.dismiss(); }
                }
            ]
        }).result.then(function(ssubId) {
            if (ssubId) {
                var promises = [];
                promises.push(egSerialsCoreSvc.fetchItemsForSub(ssubId,{status:'Expected'}).then(function(){
                    angular.forEach(egSerialsCoreSvc.itemTree, function (item) {
                        if (next_per_stream[item.stream().id()]) return;
                        if (item.status() == 'Expected') {
                            next_per_stream[item.stream().id()] = item;
                            list.push(egCore.idl.Clone(item));
                        }
                    });
                }));

                return $q.all(promises).then(function() {

                    if (!list.length) {
                        ngToast.warning(egCore.strings.SERIALS_NO_ITEMS);
                        return $q.reject();
                    }

                    return egSerialsCoreSvc.process_items(
                        'receive',
                        $scope.record_id,
                        list,
                        true, // barcode
                        false,// bind
                        false, // print by default
                        function() { $scope.holdings_record_id_changed($scope.record_id) }
                    );
                });
            } else {
                ngToast.warning(egCore.strings.SERIALS_NO_SUBS);
                return $q.reject();
            }
        });
    }

    $scope.markConjoined = function () {
        $scope.current_conjoined_target = $scope.record_id;
        egCore.hatch.setLocalItem('eg.cat.marked_conjoined_record',$scope.record_id);
        ngToast.create(egCore.strings.MARK_CONJ_TARGET);
    };

    $scope.markHoldingsTransfer = function () {
        $scope.current_transfer_target = $scope.record_id;
        egCore.hatch.setLocalItem('eg.cat.transfer_target_record',$scope.record_id);
        egCore.hatch.removeLocalItem('eg.cat.transfer_target_lib');
        egCore.hatch.removeLocalItem('eg.cat.transfer_target_vol');
        ngToast.create(egCore.strings.MARK_HOLDINGS_TARGET);
    };

    $scope.markOverlay = function () {
        $scope.current_overlay_target = $scope.record_id;
        egCore.hatch.setLocalItem('eg.cat.marked_overlay_record',$scope.record_id);
        ngToast.create(egCore.strings.MARK_OVERLAY_TARGET);
    };

    $scope.clearRecordMarks = function () {
        $scope.current_overlay_target     = null;
        $scope.current_transfer_target    = null;
        $scope.current_conjoined_target   = null;
        $scope.current_hold_transfer_dest = null;
        egCore.hatch.removeLocalItem('eg.cat.transfer_target_record');
        egCore.hatch.removeLocalItem('eg.cat.marked_conjoined_record');
        egCore.hatch.removeLocalItem('eg.cat.marked_overlay_record');
        egCore.hatch.removeLocalItem('eg.circ.hold.title_transfer_target');
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

    patron_search_dialog = function() {
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
        });
    }

    // Map the Angular catalog-only 'item_table' tab to the AngJS
    // 'catalog' tab.
    function get_default_record_tab() {
        var tab = egCore.hatch.getLocalItem('eg.cat.default_record_tab');
        if (!tab || tab === 'item_table' || tab === 'staff_view' || tab === 'added-content' || tab === 'bibnotes' || tab === 'cnbrowse') { return 'catalog'; }
        return tab;
    }

    // also set it when the iframe changes to a new record
    $scope.handle_page = function(url) {

        if (!url || url == 'about:blank') {
            // nothing loaded.  If we already have a record ID, leave it.
            return;
        }

        var prev_record_id = $scope.record_id;
        var match = url.match(/\/+opac\/+record\/+(\d+)/);
        if (match) {
            $scope.record_id = match[1];
            egCore.hatch.setLocalItem("eg.cat.last_record_retrieved", $scope.record_id);
            $scope.holdings_record_id_changed($scope.record_id);
            conjoinedSvc.fetch($scope.record_id).then(function(){
                $scope.conjoinedGridDataProvider.refresh();
            });
            init_parts_url();
            $scope.grid_actions.refresh();
            $location.update_path('/cat/catalog/record/' + $scope.record_id);
            // update_path() bypasses the controller for path 
            // /cat/catalog/record/:record_id. Manually set title here too.
            egCore.strings.setPageTitle(
                egCore.strings.PAGE_TITLE_BIB_DETAIL,
                egCore.strings.PAGE_TITLE_CATALOG_CONTEXT,
                {record_id : $scope.record_id}
            );
        } else {
            delete $scope.record_id;
            $scope.from_route = false;
        }

        // child scope is executing this function, so our digest doesn't fire ... thus,
        $scope.$apply();

        // don't change tabs if we are using the OPAC nav buttons,
        // or we didn't change records on the OPAC load
        if (!$scope.in_opac_call && ($scope.record_id != prev_record_id)) {
            if ($scope.record_id) {
                $scope.default_tab = get_default_record_tab();
                tab = $routeParams.record_tab || $scope.default_tab;
            } else {
                tab = $routeParams.record_tab || 'catalog';
            }
            $scope.set_record_tab(tab);
        } else {
            $scope.in_opac_call = false;
        }

        if ($scope.opac_iframe && $location.path().match(/cat\/catalog/)) {
            var doc = $scope.opac_iframe.dom.contentWindow.document;
            $(doc).find('#hold_usr_search').show();
            $(doc).find('#hold_usr_search').on('click', function() {
                patron_search_dialog().result.then(function(barc) {
                    $(doc).find('#hold_usr_input').val(barc);
                    $(doc).find('#hold_usr_input').trigger($.Event('keydown', {which: 13}));
                });
            });
            // Add Cart to Record Bucket, in two flavors:
            // First, the traditional TPAC, which uses a <select> menu
            $(doc).find('#select_basket_action').on('change', function() {
                if (this.options[this.selectedIndex].value && this.options[this.selectedIndex].value == "add_cart_to_bucket") {
                    $scope.add_cart_to_record_bucket();
                }
            });
            // Second, the bootstrap OPAC, which uses a bunch of <a>s styled as a dropdown
            $(doc).find('a[href="add_cart_to_bucket"]').on('click', function (event) {
                event.preventDefault();
                $scope.add_cart_to_record_bucket();
            });
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

        return $uibModal.open({
            templateUrl: './cat/catalog/t_conjoined_selector',
            backdrop: 'static',
            animation: true,
            controller:
                   ['$scope','$uibModalInstance',
            function($scope , $uibModalInstance) {
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
                        .then(function(){$uibModalInstance.close()})
                        .then(function(){return conjoinedSvc.fetch()})
                        .then(function(){conjoinedGridDataProviderRef.refresh()});
                }
    
                $scope.cancel = function($event) {
                    $uibModalInstance.dismiss();
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

        return $uibModal.open({
            templateUrl: './cat/catalog/t_add_to_bucket',
            backdrop: 'static',
            animation: true,
            size: 'md',
            controller:
                   ['$scope','$uibModalInstance',
            function($scope , $uibModalInstance) {

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
                            $uibModalInstance.close();
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
                    $uibModalInstance.dismiss();
                }
            }]
        });
    }

    // TODO: refactor common code between cat/catalog/app.js and cat/item/app.js 

    $scope.need_one_selected = function() {
        var items = $scope.holdingsGridControls.selectedItems();
        if (items.length == 1) return false;
        return true;
    };

    $scope.make_copies_bookable = function() {

        var copies_by_record = {};
        var record_list = [];
        angular.forEach(
            $scope.holdingsGridControls.selectedItems(),
            function (item) {
                var record_id = item['call_number.record.id'];
                if (typeof copies_by_record[ record_id ] == 'undefined') {
                    copies_by_record[ record_id ] = [];
                    record_list.push( record_id );
                }
                copies_by_record[ record_id ].push(item.id);
            }
        );

        var promises = [];
        var combined_results = [];
        angular.forEach(record_list, function(record_id) {
            promises.push(
                egCore.net.request(
                    'open-ils.booking',
                    'open-ils.booking.resources.create_from_copies',
                    egCore.auth.token(),
                    copies_by_record[record_id]
                ).then(function(results) {
                    if (results && results['brsrc']) {
                        combined_results = combined_results.concat(results['brsrc']);
                    }
                })
            );
        });

        $q.all(promises).then(function() {
            if (combined_results.length > 0) {
                $uibModal.open({
                    template: '<eg-embed-frame url="booking_admin_url" handlers="funcs"></eg-embed-frame>',
                    backdrop: 'static',
                    animation: true,
                    size: 'md',
                    controller:
                           ['$scope','$location','egCore','$uibModalInstance',
                    function($scope , $location , egCore , $uibModalInstance) {

                        $scope.funcs = {
                            ses : egCore.auth.token(),
                            resultant_brsrc : combined_results.map(function(o) { return o[0]; })
                        }

                        var booking_path = '/eg/conify/global/booking/resource';

                        $scope.booking_admin_url =
                            $location.absUrl().replace(/\/eg\/staff\/.*/, booking_path);
                    }]
                });
            }
        });
    }

    $scope.book_copies_now = function(items) {
        location.href = "/eg2/staff/booking/create_reservation/for_resource/" + items[0]['barcode'];
    }

    $scope.requestItems = function() {
        var copy_list = gatherSelectedHoldingsIds();
        if (copy_list.length == 0) return;

        return $uibModal.open({
            templateUrl: './cat/catalog/t_request_items',
            animation: true,
            controller:
                   ['$scope','$uibModalInstance',
            function($scope , $uibModalInstance) {
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
                    ).then(function() {
                        holds = []; // force the holds grid to refetch data.
                        $uibModalInstance.close();
                    });
                }

                $scope.cancel = function($event) {
                    $uibModalInstance.dismiss();
                    $event.preventDefault();
                }
            }]
        });
    }

    $scope.manage_reservations = function() {
        var item = $scope.holdingsGridControls.selectedItems()[0];
        if (item)
            location.href = "/eg2/staff/booking/manage_reservations/by_resource/" + item.barcode;
    }


    $scope.view_place_orders = function() {
        if (!$scope.record_id) return;
        var url = egCore.env.basePath + 'acq/legacy/lineitem/related/' + $scope.record_id + '?target=bib';
        $timeout(function() { $window.open(url, '_blank') });
    }

    $scope.replaceBarcodes = function() {
        var copy_list = gatherSelectedRawCopies();
        if (copy_list.length == 0) return;

        var holdingsGridDataProviderRef = $scope.holdingsGridDataProvider;

        angular.forEach(copy_list, function (cp) {
            $uibModal.open({
                templateUrl: './cat/share/t_replace_barcode',
                backdrop: 'static',
                animation: true,
                controller:
                           ['$scope','$uibModalInstance',
                    function($scope , $uibModalInstance) {
                        $scope.duplicate_barcode = false;
                        $scope.isModal = true;
                        $scope.focusBarcode = false;
                        $scope.focusBarcode2 = true;
                        $scope.barcode1 = cp.barcode();

                        // check input to see if it's a duplicate barcode
                        $scope.checkCurrentBarcode = function() {
                            if (!$scope.duplicate_barcode_string) {
                                $scope.duplicate_barcode_string = window.duplicate_barcode_string;
                            }
                            var searchParams = {
                                deleted : 'f',
                                'barcode' : $scope.barcode2,
                                id : { '!=' : $scope.copyId }
                            };
                            egCore.pcrud.search('acp', searchParams).then(function (res) {
                                $scope.duplicate_barcode = res;
                            });
                        }

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
                
                                egCore.net.request(
                                    'open-ils.cat',
                                    'open-ils.cat.update_copy_barcode',
                                    egCore.auth.token(), $scope.copyId, $scope.barcode2
                                ).then(function(resp) {
                                    var evt = egCore.evt.parse(resp);
                                    if (evt) {
                                        console.log('toast 0 here', evt);
                                    } else {
                                        $scope.updateOK = stat;
                                        $scope.focusBarcode = true;
                                        holdingsSvc.fetchAgain().then(function (){
                                            holdingsGridDataProviderRef.refresh();
                                        });
                                    }
                                });

                            },function(E) {
                                console.log('toast 1 here',E);
                            },function(E) {
                                console.log('toast 2 here',E);
                            });
                            $uibModalInstance.close();
                        }

                        $scope.cancel = function($event) {
                            $uibModalInstance.dismiss();
                            $event.preventDefault();
                        }
                    }
                ]
            });
        });
    }

    var holdings_bChannel = null;
    // subscribe to BroadcastChannel for any child VolCopy tabs
    // refresh grid if needed to show new updates
    // if ($scope.record_tab === 'holdings'){
    $scope.$watch('record_tab', function(n){
    
        if (n === 'holdings'){
            if (typeof BroadcastChannel != 'undefined') {
                // we're in holdings tab, connect 2 bChannel
                holdings_bChannel = new BroadcastChannel('eg.holdings.update');
                holdings_bChannel.onmessage = function(e){
                    if (e.data
                        && e.data.records
                        && e.data.records.length
                        && e.data.records.includes(Number($scope.record_id))
                    ){ // it's for us, refresh grid!
                        console.log("Got broadcast from channel eg.holdings.update for records " + e.data.records);
                        $scope.holdings_record_id_changed($scope.record_id);
                    }
                }
            };

        } else if (holdings_bChannel){ // we're leaving holding tab, close bChannel
            holdings_bChannel.close();
        }
    
    });

    // refresh the list of holdings when the record_id is changed.
    $scope.holdings_record_id_changed = function(id) {
        if ($scope.record_id != id) $scope.record_id = id;
        console.log('record id changed to ' + id + ', loading new holdings');
        holdingsSvcInst.fetch({
            rid : $scope.record_id,
            org : $scope.holdings_ou,
            copy: $scope.holdings_show_vols ? $scope.holdings_show_copies : false,
            vol : $scope.holdings_show_vols,
            empty: $scope.holdings_show_empty,
            empty_org: $scope.holdings_show_empty_org
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
            copy: $scope.holdings_show_vols ? $scope.holdings_show_copies : false,
            vol : $scope.holdings_show_vols,
            empty: $scope.holdings_show_empty,
            empty_org: $scope.holdings_show_empty_org
        }).then(function() {
            $scope.holdingsGridDataProvider.refresh();
        });
    }

    $scope.holdings_cb_changed = function(cb,newVal,norefresh) {
        $scope[cb] = newVal;
        var x = $scope.holdings_show_vols ? $scope.holdings_show_copies : false;
        $('#holdings_show_copies').prop('checked', x);
        egCore.hatch.setItem('cat.' + cb, newVal);
        if (!norefresh) holdingsSvcInst.fetch({
            rid : $scope.record_id,
            org : $scope.holdings_ou,
            copy: $scope.holdings_show_vols ? $scope.holdings_show_copies : false,
            vol : $scope.holdings_show_vols,
            empty: $scope.holdings_show_empty,
            empty_org: $scope.holdings_show_empty_org
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
            x = $scope.holdings_show_vols ? x : false;
            $('#holdings_show_copies').prop('checked', x);
        }).then(function(){
            egCore.hatch.getItem('cat.holdings_show_empty').then(function(x){
                if (typeof x ==  'undefined') x = true;
                $scope.holdings_cb_changed('holdings_show_empty',x);
                $('#holdings_show_empty').prop('checked', x);
            }).then(function(){
                egCore.hatch.getItem('cat.holdings_show_empty_org').then(function(x){
                    if (typeof x ==  'undefined') x = true;
                    $scope.holdings_cb_changed('holdings_show_empty_org',x);
                    $('#holdings_show_empty_org').prop('checked', x);
                })
            })
        })
    });

    $scope.vols_not_shown = function () {
        return !$scope.holdings_show_vols;
    }

    $scope.copies_not_shown = function () {
        return !$scope.holdings_show_copies;
    }

    $scope.empty_org_not_shown = function () {
        return !$scope.holdings_show_empty_org;
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
                if (item.copy_count == 0 || (!item.id && item.call_number))
                    // we are in a compressed row with no copies, or we are in a single
                    // call number row with no copy (testing for presence of 'id')
                    // In either case, the call number is 'empty'
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
                'open-ils.cat.asset.volume.fleshed.batch.update',
                egCore.auth.token(), cnList, 1, flags
            ).then(function(resp) {
                var evt = egCore.evt.parse(resp);
                if (evt) {
                    egConfirmDialog.open(
                        egCore.strings.OVERRIDE_DELETE_ITEMS_FROM_CATALOG_TITLE,
                        egCore.strings.OVERRIDE_DELETE_ITEMS_FROM_CATALOG_BODY,
                        {'evt_desc': evt.desc}
                    ).result.then(function() {
                        egCore.net.request(
                            'open-ils.cat',
                            'open-ils.cat.asset.volume.fleshed.batch.update.override',
                            egCore.auth.token(), cnList, 1,
                            { events: ['TITLE_LAST_COPY', 'COPY_DELETE_WARNING'] }
                        ).then(function() {
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
            });
        });
    }
    $scope.selectedHoldingsCopyDelete = function () { $scope.selectedHoldingsDelete(false,true) }
    $scope.selectedHoldingsVolCopyDelete = function () { $scope.selectedHoldingsDelete(true,true) }
    $scope.selectedHoldingsEmptyVolCopyDelete = function () { $scope.selectedHoldingsDelete(true,false) }

    spawnHoldingsAdd = function (add_vols,add_copies){
        var raw = [];
        if (!add_vols && add_copies) { // just a copy on existing volumes
            angular.forEach(gatherSelectedVolumeIds(), function (v) {
                raw.push( {callnumber : v} );
            });
        } else if (add_vols) {
            if (typeof $scope.holdingsGridControls.selectedItems == "function" &&
                $scope.holdingsGridControls.selectedItems().length > 0) {
                angular.forEach($scope.holdingsGridControls.selectedItems(),
                    function (item) {
                        raw.push({
                            owner : item.owner_id,
                            label : ((item.call_number) ? item.call_number.label : null)
                        });
                    });
            } else {
                raw.push({
                    owner : egCore.auth.user().ws_ou()
                });
            }
        }

        if (raw.length == 0) raw.push({});

        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            null, 'edit-these-copies', {
                record_id: $scope.record_id,
                raw: raw,
                hide_vols : false,
                hide_copies : !add_copies
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
    $scope.selectedHoldingsVolCopyAdd = function () { spawnHoldingsAdd(true,true) }
    $scope.selectedHoldingsCopyAdd = function () { spawnHoldingsAdd(false,true) }
    $scope.selectedHoldingsVolAdd = function () { spawnHoldingsAdd(true,false) }

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

    $scope.markFromSelectedAsHoldingsTarget = function() {
        egCore.hatch.setLocalItem(
            'eg.cat.transfer_target_lib',
            $scope.holdingsGridControls.selectedItems()[0].owner_id
        );
        egCore.hatch.setLocalItem(
            'eg.cat.transfer_target_record',
            $scope.record_id
        );
        if ($scope.holdingsGridControls.selectedItems()[0].call_number.id) { // cn.id missing when vols are collapsed, or we are on an empty lib
            egCore.hatch.setLocalItem(
                'eg.cat.transfer_target_vol',
                $scope.holdingsGridControls.selectedItems()[0].call_number.id
            );
        } else {
            // clear out the stale value if we're on a lib-only
            // or vol-collapsed row
            egCore.hatch.removeLocalItem('eg.cat.transfer_target_vol');
        }
        ngToast.create(egCore.strings.MARK_HOLDINGS_TARGET);
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

    $scope.transferVolumes = function (){
        var target_record = egCore.hatch.getLocalItem('eg.cat.transfer_target_record');
        var target_lib = egCore.hatch.getLocalItem('eg.cat.transfer_target_lib');
        if (!target_lib
            && (!target_record || ($scope.record_id == target_record) )
        ) return;

        var vols_to_move = {};
        if (target_lib) {
            // we're moving volumes to a different library
            var vol_ids = gatherSelectedVolumeIds();
            if (vol_ids.length) {
                vols_to_move[target_lib] = vol_ids;

                // if we're *only* switching libs,
                // grab the current record as the target
                target_record = target_record || $scope.record_id;
            }
        } else {
            // we're moving volumes to the same library they exist in
            // currently, but on a different record
            var items = $scope.holdingsGridControls.selectedItems();
            angular.forEach(items, function(item) {
                if (!(item.call_number.owning_lib in vols_to_move)) {
                    vols_to_move[item.call_number.owning_lib] = new Array;
                }
                vols_to_move[item.call_number.owning_lib].push(item.call_number.id);
            });
        }

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
                ngToast.create(egCore.strings.VOLS_TRANSFERED);
                holdingsSvcInst.fetchAgain().then(function() {
                    $scope.holdingsGridDataProvider.refresh();
                });
            } else {
                alert('Could not transfer volumes!');
            }
        });
    }

    // this "transfers" selected copies to a new owning library,
    // auto-creating volumes as required
    $scope.transferItemsAutoFill = function() {
        var target_record = egCore.hatch.getLocalItem('eg.cat.transfer_target_record');
        var target_lib = egCore.hatch.getLocalItem('eg.cat.transfer_target_lib');
        if (!target_lib
            && (!target_record || ($scope.record_id == target_record) )
        ) return;

        var items = $scope.holdingsGridControls.selectedItems();
        if (!items.length) {
            return;
        }

        var vols_to_move   = {};
        var copies_to_move = {};
        angular.forEach(items, function(item) {
            var needs_move = false;
            if (target_lib
                && (item.call_number.owning_lib != target_lib)) {
                    item.call_number.owning_lib = target_lib;
                    needs_move = true;
            }
            if (target_record
                && (item.call_number.record != target_record)) {
                    item.call_number.record = target_record;
                    needs_move = true;
            }
            if (needs_move) {
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
                vol.record, // may be new
                vol.owning_lib, // may be new
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
            ngToast.create(egCore.strings.ITEMS_TRANSFERED);
            holdingsSvcInst.fetchAgain().then(function() {
                $scope.holdingsGridDataProvider.refresh();
            });
        });
    }

    $scope.gridCellHandlers = {};
    $scope.gridCellHandlers.copyAlertsEdit = function(id) {
        egCirc.manage_copy_alerts([id]).then(function() {
            // update grid items?
        });
    };

    $scope.transferItems = function (){
        var xfer_target = egCore.hatch.getLocalItem('eg.cat.transfer_target_vol');

        if (!xfer_target) {
            // we have no specific volume, let's try to fill in the
            // blanks instead
            return $scope.transferItemsAutoFill();
        }

        var copy_ids = gatherSelectedHoldingsIds();
        if (copy_ids.length > 0) {
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
                        ngToast.create(egCore.strings.ITEMS_TRANSFERED);
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
                var url = '/eg2/staff/circ/item/event-log/' + cid;
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

    $scope.selectedHoldingsPrintLabels = function() {
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

    $scope.selectedHoldingsDamaged = function () {
        var copy_list = gatherSelectedRawCopies();
        if (copy_list.length == 0) return;

        angular.forEach(copy_list, function(cp) {
            egCirc.mark_damaged({
                id: cp.id(),
                barcode: cp.barcode(),
                circ_lib: cp.circ_lib().id()
            }).then(function() {
                holdingsSvcInst.fetchAgain().then(function() {
                    $scope.holdingsGridDataProvider.refresh();
                });
            });
        });
    }

    $scope.selectedHoldingsDiscard = function () {
        var copy_list = gatherSelectedRawCopies();
        if (copy_list.length == 0) return;
        egCirc.mark_discard(copy_list.map(function(cp) {
            return {id: cp.id(), barcode: cp.barcode()};})).then(function() {
                holdingsSvcInst.fetchAgain().then(function() {
                    $scope.holdingsGridDataProvider.refresh();
                });
            });
    }

    $scope.selectedHoldingsMissing = function () {
        var copy_list = gatherSelectedRawCopies();
        if (copy_list.length == 0) return;
        egCirc.mark_missing(copy_list.map(function(cp) {
            return {id: cp.id(), barcode: cp.barcode()};})).then(function() {
                holdingsSvcInst.fetchAgain().then(function() {
                    $scope.holdingsGridDataProvider.refresh();
                });
            });
    }

    $scope.selectedHoldingsCopyAlertsAdd = function() {
        egCirc.add_copy_alerts(gatherSelectedHoldingsIds()).then(function() {
            // no need to refresh grid
        });
    }
    $scope.selectedHoldingsCopyAlertsManage = function() {
        egCirc.manage_copy_alerts(gatherSelectedHoldingsIds()).then(function() {
            // no need to refresh grid
        });
    }

    $scope.attach_to_peer_bib = function() {
        var copy_list = gatherSelectedHoldingsIds();
        if (copy_list.length == 0) return;

        egCore.hatch.getItem('eg.cat.marked_conjoined_record').then(function(target_record) {
            if (!target_record) return;

            return $uibModal.open({
                templateUrl: './cat/catalog/t_conjoined_selector',
                backdrop: 'static',
                animation: true,
                controller:
                       ['$scope','$uibModalInstance',
                function($scope , $uibModalInstance) {
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
    
                        return $q.all(promises).then(function(){$uibModalInstance.close()});
                    }
    
                    $scope.cancel = function($event) {
                        $uibModalInstance.dismiss();
                        $event.preventDefault();
                    }
                }]
            });
        });
    }


    // ------------------------------------------------------------------
    // Holds 
    var provider = egGridDataProvider.instance({});
    var holds = []; // current list of holds
    var hold_count = 0;
    var hold_grid_load_promise;

    $scope.hold_grid_data_provider = provider;
    $scope.grid_actions = egHoldGridActions;
    $scope.grid_actions.refresh = function () { holds = []; hold_count = 0; provider.refresh() };
    $scope.hold_grid_controls = {};

    provider.get = function(offset, count) {
        if ($scope.record_tab != 'holds') return $q.when();

        if (hold_grid_load_promise) {
            // Active load in progress.
            console.debug('Exiting concurrent hold fetch');
            return hold_grid_load_promise;
        }

        // see if we have the requested range cached
        if (holds[offset]) {
            console.debug(
                'Serving holds from cache with pickup lib', $scope.pickup_ou.id());
            return provider.arrayNotifier(holds, offset, count);
        }

        hold_count = 0;
        holds = [];
        var restrictions = {
                is_staff_request : 'true',
                fulfillment_time : null,
                cancel_time      : null,
                record_id        : $scope.record_id,
                pickup_lib       : egCore.org.descendants($scope.pickup_ou.id(), true)
        };

        var order_by = [{ request_time : null }];
        // NOTE: Server sort is disabled for now.  See the comment on
        // similar code in circ/holds/app.js for details.
        if (false && provider.sort && provider.sort.length) {
            order_by = [];
            angular.forEach(provider.sort, function (c) {
                if (!angular.isObject(c)) {
                    if (c.match(/^hold\./)) {
                        var i = c.replace('hold.','');
                        var ob = {};
                        ob[i] = null;
                        order_by.push(ob);
                    }
                } else {
                    var i = Object.keys(c)[0];
                    var direction = c[i];
                    if (i.match(/^hold\./)) {
                        i = i.replace('hold.','');
                        var ob = {}
                        ob[i] = {dir:direction};
                        order_by.push(ob);
                    }
                }
            });
        }

        console.debug(
            'Fetching holds from network with PU lib', $scope.pickup_ou.id());

        egProgressDialog.open({max : 1, value : 0});
        var first = true;
        hold_grid_load_promise = egHolds.fetch_wide_holds(
            restrictions,
            order_by
        ).then(function () {
                hold_grid_load_promise = null;
                return provider.arrayNotifier(holds, offset, count);
            },
            null,
            function(hold_data) {
                if (first) {
                    hold_count = hold_data;
                    first = false;
                    egProgressDialog.update({max:hold_count});
                } else {
                    egProgressDialog.increment();
                    var new_item = { id : hold_data.id, hold : hold_data };
                    new_item.status_string =
                        egCore.strings['HOLD_STATUS_' + hold_data.hold_status]
                        || hold_data.hold_status;

                    holds.push(new_item);
                }
            }
        ).finally(function() {
            hold_grid_load_promise = null;
            egProgressDialog.close();
        });

        return hold_grid_load_promise;
    }

    $scope.detail_view = function(action, user_data, items) {
        if (h = items[0]) {
            $scope.detail_hold_id = h.hold.id;
        }
    }

    $scope.list_view = function(items) {
         $scope.detail_hold_id = null;
    }

    // refresh the list of record holds when the pickup lib is changed.
    $scope.pickup_ou = egCore.org.get(egCore.auth.user().ws_ou());
    $scope.pickup_ou_changed = function(org) {
        if ($scope.pickup_ou && $scope.pickup_ou.id() == org.id()) {
            // This fires on every component render, even though the
            // value we already have may match.  Avoid duplicate lookups.
            return;
        }

        var promise = hold_grid_load_promise || $q.when();

        // Avoid refreshing the grid if it's currently loading data.
        promise.finally(function() {

            // Previous grid data load complete.  Timeout gives the
            // grid a chance to mark itself as load-completed, which
            // happens after the data load promise is done.
            setTimeout(function() {
                console.debug('Refreshing holds after PU lib change to ', org.id());
                $scope.pickup_ou = org;
                holds = []
                hold_count = 0;
                provider.refresh();
            });
        })
    }

    function map_prefix_to_subhash (h,pf) {
        var newhash = {};
        angular.forEach(Object.keys(h), function (k) {
            if (k.startsWith(pf)) {
                var nk = k.substr(pf.length);
                newhash[nk] = h[k];
            }
        });
        return newhash;
    }

    $scope.print_holds = function() {
        var pholds = [];
        angular.forEach(holds, function(item) {
            pholds.push({
                hold : item.hold,
                status_string : item.status_string,
                patron_first : item.hold.usr_first_given_name,
                patron_last : item.hold.usr_family_name,
                patron_alias : item.hold.usr_alias,
                patron_barcode : item.hold.ucard_barcode,
                copy : map_prefix_to_subhash(item.hold,'cp_'),
                volume : map_prefix_to_subhash(item.hold,'cn_'),
                title : item.hold.title,
                author : item.hold.author
            });
        });

        egCore.print.print({
            context : 'receipt', 
            template : 'holds_for_bib', 
            scope : {holds : pholds}
        });
    }

    $scope.current_hold_transfer_dest = egCore.hatch.getLocalItem ('eg.circ.hold.title_transfer_target');

    $scope.mark_hold_transfer_dest = function() {
        $scope.current_hold_transfer_dest = $scope.record_id;
        egCore.hatch.setLocalItem(
            'eg.circ.hold.title_transfer_target', $scope.record_id);
        ngToast.create(egCore.strings.HOLD_TRANSFER_DEST_MARKED);
    }

    // UI presents this option as "all holds"
    $scope.transfer_holds_to_marked = function() {
        var hold_ids = $scope.hold_grid_controls.allItems().map(
            function(hold_data) {return hold_data.hold.id});
        egHolds.transfer_to_marked_title(hold_ids);
    }

    // ------------------------------------------------------------------
    // Initialize the selected tab

    // we explicitly initialize catalog_url because otherwise Firefox
    // ends up setting it to $BASE_URL/{{url}}, which then messes
    // things up. See LP#1708951
    $scope.catalog_url = '';

    function init_cat_url() {
        // Set the initial catalog URL.  This only happens once.
        // The URL is otherwise generated through user navigation.
        if ($scope.catalog_url) return;

        var url = $location.absUrl().replace(/\/staff\/.*/, '/opac/advanced');

        // A record ID in the path indicates a request for the record-
        // specific page.
        if ($routeParams.record_id) {
            url = url.replace(/\/advanced/, '/record/' + $scope.record_id);
        }

        // Jumping directly to the results page by passing a search
        // query via the URL.  Copy all URL params to the iframe url.
        if ($location.path().match(/catalog\/results/)) {
            url = url.replace(/\/advanced/, '/results?');
            var first = true;
            angular.forEach($location.search(), function(val, key) {
                if (!first) url += '&';
                first = false;
                url += encodeURIComponent(key) 
                    + '=' + encodeURIComponent(val);
            });
        }

        // if we're displaying the advanced search form, select
        // whatever default pane the user has chosen via workstation
        // preference
        if (url.match(/\/opac\/advanced$/)) {
            egCore.hatch.getItem('eg.search.adv_pane').then(function(adv_pane_val){
                if (adv_pane_val) {
                    url += '?pane=' + encodeURIComponent(adv_pane_val);
                }

                $scope.catalog_url = url;
            });
        } else {
            $scope.catalog_url = url;
	}

    }

    function init_parts_url() {
        $scope.parts_url = $location
            .absUrl()
            .replace(
                /\/staff\/.*/,
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
        $scope.default_tab = get_default_record_tab();
        tab = $routeParams.record_tab || $scope.default_tab;

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
    $scope.verifyurls_url = $location.absUrl().replace(/\/staff\/.*/, '/url_verify/sessions');
}])

.controller('VandelayCtrl',
       ['$scope','$location', 'egCore', '$uibModal',
function($scope , $location, egCore, $uibModal) {
    $scope.vandelay_url = $location.absUrl().replace(/\/staff\/cat\/catalog\/vandelay/, '/vandelay/vandelay');
    $scope.funcs = {};
    $scope.funcs.edit_marc_modal = function(bre, callback){
        var marcArgs = { 'marc_xml': bre.marc() };
        var vqbibrecId = bre.id();
        $uibModal.open({
            templateUrl: './cat/catalog/t_edit_marc_modal',
            backdrop: 'static',
            size: 'lg',
            controller: ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.recordId = vqbibrecId;
                $scope.args = marcArgs;
                $scope.dirty_flag = false;
                $scope.ok = function(marg){
                    $uibModalInstance.close(marg);
                };
                $scope.cancel = function(){ $uibModalInstance.dismiss() }
            }]
        }).result.then(function(res){
            var new_xml = res.marc_xml;
            egCore.pcrud.retrieve('vqbr', vqbibrecId).then(function(vqbib){
                vqbib.marc(new_xml);
                egCore.pcrud.update(vqbib).then( function(){ callback(vqbibrecId); });
            });
        });
    };
}])

.controller('ManageAuthoritiesCtrl',
       ['$scope','$location',
function($scope , $location) {
    $scope.manageauthorities_url = $location.absUrl().replace(/\/staff\/.*/, '/cat/authority/list');
}])

.controller('BatchEditCtrl',
       ['$scope','$location','$routeParams',
function($scope , $location , $routeParams) {
    $scope.batchedit_url = $location.absUrl().replace(/\/eg\/.*/, '/opac/extras/merge_template');
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


