/**
 * Shared item services for circulation
 */

angular.module('egCoreMod')
    .factory('egItem',
       ['egCore','egCirc','$uibModal','$q','$timeout','$window','egConfirmDialog','egAlertDialog',
function(egCore , egCirc , $uibModal , $q , $timeout , $window , egConfirmDialog , egAlertDialog ) {

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

            if(!res.copy) { return $q.when(); }

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
            if(!copyData) { return $q.when(); }
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

    service.print_spine_labels = function(copy_ids){
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.set_value',
            null, 'print-labels-these-copies', {
                copies : copy_ids
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

    return service;
}])
