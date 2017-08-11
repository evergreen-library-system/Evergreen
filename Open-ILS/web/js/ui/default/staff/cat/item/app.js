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

.factory('itemSvc', 
       ['egCore','egCirc','$uibModal','$q','$timeout','$window','egConfirmDialog','egAlertDialog',
function(egCore , egCirc , $uibModal , $q , $timeout , $window , egConfirmDialog, egAlertDialog ) {

    var service = {
        copies : [], // copy barcode search results
        index : 0 // search grid index
    };

    service.flesh = {   
        flesh : 3, 
        flesh_fields : {
            acp : ['call_number','location','status','location','floating','circ_modifier',
                'age_protect','circ_lib'],
            acn : ['record','prefix','suffix','label_class'],
            bre : ['simple_record','creator','editor']
        },
        select : { 
            // avoid fleshing MARC on the bre
            // note: don't add simple_record.. not sure why
            bre : ['id','tcn_value','creator','editor'],
        } 
    }

    service.circFlesh = {
        flesh : 2,
        flesh_fields : {
            circ : [
                'usr',
                'workstation',
                'checkin_workstation',
                'checkin_lib',
                'duration_rule',
                'max_fine_rule',
                'recurring_fine_rule'
            ],
            au : ['card']
        },
        order_by : {circ : 'xact_start desc'},
        limit :  1
    }

    //Retrieve separate copy, aacs, and accs information
    service.getCopy = function(barcode, id) {
        if (barcode) {
            // handle barcode completion
            return egCirc.handle_barcode_completion(barcode)
            .then(function(actual_barcode) {
                return egCore.pcrud.search(
                    'acp', {barcode : actual_barcode, deleted : 'f'},
                    service.flesh).then(function(copy) {return copy});
            });
        }

        return egCore.pcrud.retrieve( 'acp', id, service.flesh)
            .then(function(copy) {return copy});
    }

    service.getCirc = function(id) {
        return egCore.pcrud.search('aacs', { target_copy : id },
            service.circFlesh).then(function(circ) {return circ});
    }

    service.getSummary = function(id) {
        return circ_summary = egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.renewal_chain.retrieve_by_circ.summary',
            egCore.auth.token(), id).then(
                function(circ_summary) {return circ_summary});
    }

    //Combine copy, circ, and accs information
    service.retrieveCopyData = function(barcode, id) {
        var copyData = {};

        var fetchCopy = function(barcode, id) {
            return service.getCopy(barcode, id)
                .then(function(copy) {
                    copyData.copy = copy;
                    return copyData;
                });
        }
        var fetchCirc = function(copy) {
            return service.getCirc(copy.id())
                .then(function(circ) {
                    copyData.circ = circ;
                    return copyData;
                });
        }
        var fetchSummary = function(circ) {
            return service.getSummary(circ.id())
                .then(function(summary) {
                    copyData.circ_summary = summary;
                    return copyData;
                });
        }
        return fetchCopy(barcode, id).then(function(res) {
            return fetchCirc(copyData.copy).then(function(res) {
                if (copyData.circ) {
                    return fetchSummary(copyData.circ).then(function() {
                        return copyData;
                    });
                } else {
                    return copyData;
                }
            });
        });

    }

    // resolved with the last received copy
    service.fetch = function(barcode, id, noListDupes) {
        var copy;
        var circ;
        var circ_summary;
        var lastRes = {};

        return service.retrieveCopyData(barcode, id)
        .then(function(copyData) {
            //Make sure we're getting a completed copyData - no plain acp or circ objects
            if (copyData.circ) {
                // flesh circ_lib locally
                copyData.circ.circ_lib(egCore.org.get(copyData.circ.circ_lib()));
                copyData.circ.checkin_workstation(
                    egCore.org.get(copyData.circ.checkin_workstation()));
            }
            var flatCopy;

            if (noListDupes) {
                // use the existing copy if possible
                flatCopy = service.copies.filter(
                    function(c) {return c.id == copyData.copy.id()})[0];
            }

            if (!flatCopy) {
                flatCopy = egCore.idl.toHash(copyData.copy, true);

                if (copyData.circ) {
                    flatCopy._circ = egCore.idl.toHash(copyData.circ, true);
                    flatCopy._circ_summary = egCore.idl.toHash(copyData.circ_summary, true);
                    flatCopy._circ_lib = copyData.circ.circ_lib();
                    flatCopy._duration = copyData.circ.duration();
                }
                flatCopy.index = service.index++;
                service.copies.unshift(flatCopy);
            }

            //Get in-house use count
            egCore.pcrud.search('aihu',
                {item : flatCopy.id}, {}, {idlist : true, atomic : true})
            .then(function(uses) {
                flatCopy._inHouseUseCount = uses.length;
                copyData.copy._inHouseUseCount = uses.length;
            });

            return lastRes = {
                copy : copyData.copy,
                index : flatCopy.index
            }
        });


    }

    service.add_copies_to_bucket = function(copy_list) {
        if (copy_list.length == 0) return;

        return $uibModal.open({
            templateUrl: './cat/catalog/t_add_to_bucket',
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

    service.make_copies_bookable = function(items) {

        var copies_by_record = {};
        var record_list = [];
        angular.forEach(
            items,
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
                            $location.absUrl().replace(/\/eg\/staff.*/, booking_path);
                    }]
                });
            }
        });
    }

    service.book_copies_now = function(items) {
        var copies_by_record = {};
        var record_list = [];
        angular.forEach(
            items,
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
        var combined_brt = [];
        var combined_brsrc = [];
        angular.forEach(record_list, function(record_id) {
            promises.push(
                egCore.net.request(
                    'open-ils.booking',
                    'open-ils.booking.resources.create_from_copies',
                    egCore.auth.token(),
                    copies_by_record[record_id]
                ).then(function(results) {
                    if (results && results['brt']) {
                        combined_brt = combined_brt.concat(results['brt']);
                    }
                    if (results && results['brsrc']) {
                        combined_brsrc = combined_brsrc.concat(results['brsrc']);
                    }
                })
            );
        });

        $q.all(promises).then(function() {
            if (combined_brt.length > 0 || combined_brsrc.length > 0) {
                $uibModal.open({
                    template: '<eg-embed-frame url="booking_admin_url" handlers="funcs"></eg-embed-frame>',
                    animation: true,
                    size: 'md',
                    controller:
                           ['$scope','$location','egCore','$uibModalInstance',
                    function($scope , $location , egCore , $uibModalInstance) {

                        $scope.funcs = {
                            ses : egCore.auth.token(),
                            bresv_interface_opts : {
                                booking_results : {
                                     brt : combined_brt
                                    ,brsrc : combined_brsrc
                                }
                            }
                        }

                        var booking_path = '/eg/booking/reservation';

                        $scope.booking_admin_url =
                            $location.absUrl().replace(/\/eg\/staff.*/, booking_path);

                    }]
                });
            }
        });
    }

    service.requestItems = function(copy_list) {
        if (copy_list.length == 0) return;

        return $uibModal.open({
            templateUrl: './cat/catalog/t_request_items',
            animation: true,
            controller:
                   ['$scope','$uibModalInstance','egUser',
            function($scope , $uibModalInstance , egUser) {
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

                    $uibModalInstance.close();
                }

                $scope.cancel = function($event) {
                    $uibModalInstance.dismiss();
                    $event.preventDefault();
                }
            }]
        });
    }

    service.attach_to_peer_bib = function(items) {
        if (items.length == 0) return;

        egCore.hatch.getItem('eg.cat.marked_conjoined_record').then(function(target_record) {
            if (!target_record) return;

            return $uibModal.open({
                templateUrl: './cat/catalog/t_conjoined_selector',
                animation: true,
                controller:
                       ['$scope','$uibModalInstance',
                function($scope , $uibModalInstance) {
                    $scope.update = false;

                    $scope.peer_type = null;
                    $scope.peer_type_list = [];

                    get_peer_types = function() {
                        if (egCore.env.bpt)
                            return $q.when(egCore.env.bpt.list);

                        return egCore.pcrud.retrieveAll('bpt', null, {atomic : true})
                        .then(function(list) {
                            egCore.env.absorbList(list, 'bpt');
                            return list;
                        });
                    }

                    get_peer_types().then(function(list){
                        $scope.peer_type_list = list;
                    });

                    $scope.ok = function(type) {
                        var promises = [];

                        angular.forEach(items, function (cp) {
                            var n = new egCore.idl.bpbcm();
                            n.isnew(true);
                            n.peer_record(target_record);
                            n.target_copy(cp.id);
                            n.peer_type(type);
                            promises.push(egCore.pcrud.create(n).then(function(){service.add_barcode_to_list(cp.barcode)}));
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

    service.selectedHoldingsCopyDelete = function (items) {
        if (items.length == 0) return;

        var copy_objects = [];
        egCore.pcrud.search('acp',
            {deleted : 'f', id : items.map(function(el){return el.id;}) },
            { flesh : 1, flesh_fields : { acp : ['call_number'] } }
        ).then(function(copy) {
            copy_objects.push(copy);
        }).then(function() {

            var cnHash = {};
            var perCnCopies = {};

            var cn_count = 0;
            var cp_count = 0;

            angular.forEach(
                copy_objects,
                function (cp) {
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
                }
            );

            angular.forEach(perCnCopies, function (v, k) {
                cnHash[k].copies(v);
            });

            cnList = [];
            angular.forEach(cnHash, function (v, k) {
                cnList.push(v);
            });

            if (cnList.length == 0) return;

            var flags = {};

            egConfirmDialog.open(
                egCore.strings.CONFIRM_DELETE_COPIES_VOLUMES,
                egCore.strings.CONFIRM_DELETE_COPIES_VOLUMES_MESSAGE,
                {copies : cp_count, volumes : cn_count}
            ).result.then(function() {
                egCore.net.request(
                    'open-ils.cat',
                    'open-ils.cat.asset.volume.fleshed.batch.update.override',
                    egCore.auth.token(), cnList, 1, flags
                ).then(function(){
                    angular.forEach(items, function(cp){service.add_barcode_to_list(cp.barcode)});
                });
            });
        });
    }

    service.checkin = function (items) {
        angular.forEach(items, function (cp) {
            egCirc.checkin({copy_barcode:cp.barcode}).then(
                function() { service.add_barcode_to_list(cp.barcode) }
            );
        });
    }

    service.renew = function (items) {
        angular.forEach(items, function (cp) {
            egCirc.renew({copy_barcode:cp.barcode}).then(
                function() { service.add_barcode_to_list(cp.barcode) }
            );
        });
    }

    service.cancel_transit = function (items) {
        angular.forEach(items, function(cp) {
            egCirc.find_copy_transit(null, {copy_barcode:cp.barcode})
                .then(function(t) { return egCirc.abort_transit(t.id())    })
                .then(function()  { return service.add_barcode_to_list(cp.barcode) });
        });
    }

    service.selectedHoldingsDamaged = function (items) {
        egCirc.mark_damaged(items.map(function(el){return el.id;})).then(function(){
            angular.forEach(items, function(cp){service.add_barcode_to_list(cp.barcode)});
        });
    }

    service.selectedHoldingsMissing = function (items) {
        egCirc.mark_missing(items.map(function(el){return el.id;})).then(function(){
            angular.forEach(items, function(cp){service.add_barcode_to_list(cp.barcode)});
        });
    }

    service.gatherSelectedRecordIds = function (items) {
        var rid_list = [];
        angular.forEach(
            items,
            function (item) {
                if (rid_list.indexOf(item['call_number.record.id']) == -1)
                    rid_list.push(item['call_number.record.id'])
            }
        );
        return rid_list;
    }

    service.gatherSelectedVolumeIds = function (items,rid) {
        var cn_id_list = [];
        angular.forEach(
            items,
            function (item) {
                if (rid && item['call_number.record.id'] != rid) return;
                if (cn_id_list.indexOf(item['call_number.id']) == -1)
                    cn_id_list.push(item['call_number.id'])
            }
        );
        return cn_id_list;
    }

    service.gatherSelectedHoldingsIds = function (items,rid) {
        var cp_id_list = [];
        angular.forEach(
            items,
            function (item) {
                if (rid && item['call_number.record.id'] != rid) return;
                cp_id_list.push(item.id)
            }
        );
        return cp_id_list;
    }

    service.spawnHoldingsAdd = function (items,use_vols,use_copies){
        angular.forEach(service.gatherSelectedRecordIds(items), function (r) {
            var raw = [];
            if (use_copies) { // just a copy on existing volumes
                angular.forEach(service.gatherSelectedVolumeIds(items,r), function (v) {
                    raw.push( {callnumber : v} );
                });
            } else if (use_vols) {
                angular.forEach(
                    service.gatherSelectedHoldingsIds(items,r),
                    function (i) {
                        angular.forEach(items, function(item) {
                            if (i == item.id) raw.push({owner : item['call_number.owning_lib']});
                        });
                    }
                );
            }

            if (raw.length == 0) raw.push({});

            egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.anon_cache.set_value',
                null, 'edit-these-copies', {
                    record_id: r,
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
        });
    }

    service.spawnHoldingsEdit = function (items,hide_vols,hide_copies){
        angular.forEach(service.gatherSelectedRecordIds(items), function (r) {
            egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.anon_cache.set_value',
                null, 'edit-these-copies', {
                    record_id: r,
                    copies: service.gatherSelectedHoldingsIds(items,r),
                    raw: {},
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
        });
    }

    service.replaceBarcodes = function(items) {
        angular.forEach(items, function (cp) {
            $uibModal.open({
                templateUrl: './cat/share/t_replace_barcode',
                animation: true,
                controller:
                           ['$scope','$uibModalInstance',
                    function($scope , $uibModalInstance) {
                        $scope.isModal = true;
                        $scope.focusBarcode = false;
                        $scope.focusBarcode2 = true;
                        $scope.barcode1 = cp.barcode;

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
                                    if (stat) service.add_barcode_to_list(copy.barcode());
                                });

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

    // this "transfers" selected copies to a new owning library,
    // auto-creating volumes and deleting unused volumes as required.
    service.changeItemOwningLib = function(items) {
        var xfer_target = egCore.hatch.getLocalItem('eg.cat.volume_transfer_target');
        if (!xfer_target || !items.length) {
            return;
        }
        var vols_to_move   = {};
        var copies_to_move = {};
        angular.forEach(items, function(item) {
            if (item['call_number.owning_lib'] != xfer_target) {
                if (item['call_number.id'] in vols_to_move) {
                    copies_to_move[item['call_number.id']].push(item.id);
                } else {
                    vols_to_move[item['call_number.id']] = {
                        label       : item['call_number.label'],
                        label_class : item['call_number.label_class'],
                        record      : item['call_number.record.id'],
                        prefix      : item['call_number.prefix.id'],
                        suffix      : item['call_number.suffix.id']
                    };
                    copies_to_move[item['call_number.id']] = new Array;
                    copies_to_move[item['call_number.id']].push(item.id);
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
                vol.prefix,
                vol.suffix,
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

        angular.forEach(
            items,
            function(cp){
                promises.push(
                    function(){ service.add_barcode_to_list(cp.barcode) }
                )
            }
        );
        $q.all(promises);
    }

    service.transferItems = function (items){
        var xfer_target = egCore.hatch.getLocalItem('eg.cat.item_transfer_target');
        var copy_ids = service.gatherSelectedHoldingsIds(items);
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
                            {'evt_desc': evt}
                        ).result.then(function() {
                            egCore.net.request(
                                'open-ils.cat',
                                'open-ils.cat.transfer_copies_to_volume.override',
                                egCore.auth.token(),
                                xfer_target,
                                copy_ids,
                                { events: ['TITLE_LAST_COPY', 'COPY_DELETE_WARNING'] }
                            );
                        }).then(function() {
                            angular.forEach(items, function(cp){service.add_barcode_to_list(cp.barcode)});
                        });
                    } else {
                        angular.forEach(items, function(cp){service.add_barcode_to_list(cp.barcode)});
                    }

                },
                null, // onerror
                null // onprogress
            );
        }
    }

    service.mark_missing_pieces = function(copy) {
        var b = copy.barcode();
        var t = egCore.idl.toHash(copy.call_number()).record.title;
        egConfirmDialog.open(
            egCore.strings.CONFIRM_MARK_MISSING_TITLE,
            egCore.strings.CONFIRM_MARK_MISSING_BODY,
            { barcode : b, title : t }
        ).result.then(function() {

            // kick off mark missing
            return egCore.net.request(
                'open-ils.circ',
                'open-ils.circ.mark_item_missing_pieces',
                egCore.auth.token(), copy.id()
            )

        }).then(function(resp) {
            var evt = egCore.evt.parse(resp); // should always produce event

            if (evt.textcode == 'ACTION_CIRCULATION_NOT_FOUND') {
                return egAlertDialog.open(
                    egCore.strings.CIRC_NOT_FOUND, {barcode : copy.barcode()});
            }

            var payload = evt.payload;

            // TODO: open copy editor inline?  new tab?

            // print the missing pieces slip
            var promise = $q.when();
            if (payload.slip) {
                // wait for completion, since it may spawn a confirm dialog
                promise = egCore.print.print({
                    context : 'default',
                    content_type : 'text/html',
                    content : payload.slip.template_output().data()
                });
            }

            if (payload.letter) {
                $scope.letter = payload.letter.template_output().data();
            }

            // apply patron penalty
            if (payload.circ) {
                promise.then(function() {
                    egCirc.create_penalty(payload.circ.usr())
                });
            }

        });
    }

    return service;
}])

/**
 * Search bar along the top of the page.
 * Parent scope for list and detail views
 */
.controller('SearchCtrl', 
       ['$scope','$location','$timeout','egCore','egGridDataProvider','itemSvc',
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
            barcode : $scope.args.copyBarcode
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
       ['$scope','$q','$routeParams','$location','$timeout','$window','egCore','egGridDataProvider','itemSvc','egUser','$uibModal','egCirc','egConfirmDialog',
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
       ['$scope','$q','$location','$routeParams','$timeout','$window','egCore','itemSvc','egBilling',
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
