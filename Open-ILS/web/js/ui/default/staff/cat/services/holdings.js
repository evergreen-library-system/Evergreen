angular.module('egHoldingsMod', ['egCoreMod','egGridMod'])

.factory('holdingsSvc', 
       ['egCore','$q',
function(egCore , $q) {

    var service = function() {
        this.ongoing = false;
        this.copies = []; // record search results
        this.index = 0; // search grid index
        this.org = null;
        this.rid = null;
    };

    service.prototype.flesh = {   
        flesh : 3,
        flesh_fields : {
            acp : ['status','location','circ_lib','parts','age_protect','copy_alerts', 'latest_inventory'],
            acn : ['prefix','suffix','copies','label_class','record'],
            bre : ['simple_record'],
            alci : ['inventory_workstation']
        }
    }

    service.prototype.fetchAgain = function() {
        return this.fetch({
            rid: this.rid,
            org: this.org,
            copy: this.copy,
            vol: this.vol,
            empty: this.empty,
            empty_org: this.empty_org
        })
    };

    // resolved with the last received copy
    service.prototype.fetch = function(opts) {
        var svc = this;

        if (svc.ongoing && svc.p) {
            svc.p.cancel = true;
            console.log('Canceling fetch for org '+ svc.org.id());
            if (svc.p.reject) svc.p.reject();
        }

        var rid = opts.rid;
        var empty_org = opts.empty_org;
        var org = opts.org;
        var copy = opts.copy;
        var vol = opts.vol;
        var empty = opts.empty;

        if (!rid) return $q.when();
        if (!org) return $q.when();

        svc.ongoing = true;

        svc.rid = rid;
        svc.empty_org = opts.empty_org;
        svc.org = org;
        svc.copy = opts.copy;
        svc.vol = opts.vol;
        svc.empty = opts.empty;

        svc.copies = [];
        svc.index = 0;

        var org_list = egCore.org.descendants(org.id(), true);
        console.log('Holdings fetch with: rid='+rid+' org='+org_list+' copy='+copy+' vol='+vol+' empty='+empty);

        svc.org_use_map = {};
        org_list.map(function(o){svc.org_use_map[''+o]=0;})

        var p = egCore.pcrud.search(
            'acn',
            {record : rid, owning_lib : org_list, deleted : 'f', label : {'!=' : '##URI##'}},
            svc.flesh
        ).then(
            function() { // finished
                if (p.cancel) return;

                // create virtual field for displaying active parts
                angular.forEach(svc.copies, function (cp) {
                    cp.monograph_parts = '';
                    if (cp.parts && cp.parts.length > 0) {
                        cp.monograph_parts = cp.parts.map(function(obj) { return obj.label; }).join(', ');
                        cp.monograph_parts_sortkeys = cp.parts.map(function(obj) { return obj.label_sortkey; }).join();
                    }
                });

                if (empty_org) {

                    var empty_org_list = [];
                    angular.forEach(svc.org_use_map,function(v,k){
                        if (v == 0) empty_org_list.push(k);
                    });

                    angular.forEach(empty_org_list, function (oid) {
                        var owner = egCore.org.get(oid);
                        if (owner.ou_type().can_have_vols() != 't') return;

                        var owner_list = [];
                        while (owner.parent_ou()) { // we're going to skip the top of the tree...
                            owner_list.unshift(owner.shortname());
                            owner = egCore.org.get(owner.parent_ou());
                        }

                        var owner_label = owner_list.join(' ... ');

                        svc.copies.push({
                            index      : index++,
                            id_list    : [],
                            call_number: { label : '' },
                            barcode    : '',
                            owner_id   : oid,
                            owner_list : owner_list,
                            owner_label: owner_label,
                            copy_count : 0,
                            cn_count   : 0,
                            copy_alert_count : 0
                        });
                    });
                }

                svc.ongoing = false;


                svc.copies = svc.copies.sort(
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

                            // also parts sortkeys combined string
                            if (a.monograph_parts_sortkeys < b.monograph_parts_sortkeys) return -1;
                            if (a.monograph_parts_sortkeys > b.monograph_parts_sortkeys) return 1;

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

                // create virtual fields for copy alert count and most recent circ
                angular.forEach(svc.copies, function (cp) {
                    if (cp.copy_alerts) {
                        cp.copy_alert_count = cp.copy_alerts.filter(function(aca) { return aca.ack_time == null ;}).length;
                    }
                    else cp.copy_alert_count = 0;
                });

                // Grab the open circulation (i.e. checkin_time=null) for
                // all of the copies we're rendering so we can display
                // due date info.  There should only ever be one circulation
                // at most with checkin_time=null for any copy.
                var copyIds = svc.copies.map(function(cp) {return cp.id})
                    .filter(function(id) {return Boolean(id)}); // avoid nulls

                egCore.pcrud.search('circ', 
                    {target_copy: copyIds, checkin_time: null}
                ).then(
                    null, // complete
                    null, // error
                    function(circ) {
                        var cp = svc.copies.filter(function(c) { 
                            return c.id == circ.target_copy() })[0];
                        if (!cp) { return; } // can disappear during reloads.
                        cp._circ = egCore.idl.toHash(circ, true);
                        cp._circ_lib = circ.circ_lib();
                        cp._duration = circ.duration();
                    }
                );

                // create a label using just the unique part of the owner list
                var index = 0;
                var prev_owner_list;
                angular.forEach(svc.copies, function (cp) {
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

                var new_list = svc.copies;
                if (!copy || !vol) { // collapse copy rows, supply a count instead

                    index = 0;
                    var cp_list = [];
                    var prev_key;
                    var current_blob = { copy_count : 0 };
                    angular.forEach(new_list, function (cp) {
                        if (!prev_key) {
                            prev_key = cp.owner_list.join('') + cp.call_number.label;
                            if (cp.barcode) current_blob.copy_count = 1;
                            current_blob.index = index++;
                            current_blob.id_list = cp.id_list;
                            if (cp.raw) current_blob.raw = cp.raw;
                            current_blob.call_number = cp.call_number;
                            current_blob.owner_list = cp.owner_list;
                            current_blob.owner_label = cp.owner_label;
                            current_blob.owner_id = cp.owner_id;
                        } else {
                            var current_key = cp.owner_list.join('') + cp.call_number.label;
                            if (prev_key == current_key) { // collapse into current_blob
                                current_blob.copy_count++;
                                current_blob.id_list = current_blob.id_list.concat(cp.id_list);
                                current_blob.raw = current_blob.raw.concat(cp.raw);
                            } else {
                                current_blob.barcode = current_blob.copy_count;
                                cp_list.push(current_blob);
                                prev_key = current_key;
                                current_blob = { copy_count : 0 };
                                if (cp.barcode) current_blob.copy_count = 1;
                                current_blob.index = index++;
                                current_blob.id_list = cp.id_list;
                                if (cp.raw) current_blob.raw = cp.raw;
                                current_blob.owner_label = cp.owner_label;
                                current_blob.owner_id = cp.owner_id;
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
                        current_blob = { copy_count : 0 };
                        angular.forEach(cp_list, function (cp) {
                            if (!prev_key) {
                                prev_key = cp.owner_list.join('');
                                current_blob.index = index++;
                                current_blob.id_list = cp.id_list;
                                if (cp.raw) current_blob.raw = cp.raw;
                                current_blob.cn_count = 1;
                                current_blob.copy_count = cp.copy_count;
                                current_blob.owner_list = cp.owner_list;
                                current_blob.owner_label = cp.owner_label;
                                current_blob.owner_id = cp.owner_id;
                            } else {
                                var current_key = cp.owner_list.join('');
                                if (prev_key == current_key) { // collapse into current_blob
                                    current_blob.cn_count++;
                                    current_blob.copy_count += cp.copy_count;
                                    current_blob.id_list = current_blob.id_list.concat(cp.id_list);
                                    if (cp.raw) {
                                        if (current_blob.raw) current_blob.raw = current_blob.raw.concat(cp.raw);
                                        else current_blob.raw = cp.raw;
                                    }
                                } else {
                                    current_blob.barcode = current_blob.copy_count;
                                    current_blob.call_number = { label : current_blob.cn_count };
                                    cn_list.push(current_blob);
                                    prev_key = current_key;
                                    current_blob = { copy_count : 0 };
                                    current_blob.index = index++;
                                    current_blob.id_list = cp.id_list;
                                    if (cp.raw) current_blob.raw = cp.raw;
                                    current_blob.owner_label = cp.owner_label;
                                    current_blob.owner_id = cp.owner_id;
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

                svc.copies = new_list;
                svc.ongoing = false;
            },

            null, // error

            // notify reads the stream of copies, one at a time.
            function(cn) {
                if (p.cancel) return;

                var copies = cn.copies().filter(function(cp){ return cp.deleted() == 'f' });
                cn.copies([]);

                angular.forEach(copies, function (cp) {
                    cp.call_number(cn);
                });

                var owner_id = cn.owning_lib();
                var owner = egCore.org.get(owner_id);
                svc.org_use_map[''+owner_id] += 1;

                var owner_name_list = [];
                while (owner.parent_ou()) { // we're going to skip the top of the tree...
                    owner_name_list.unshift(owner.shortname());
                    owner = egCore.org.get(owner.parent_ou());
                }

                if (copies[0]) {
                    var flat = [];
                    angular.forEach(copies, function (cp) {
                        var flat_cp = egCore.idl.toHash(cp);
                        flat_cp.owner_id = owner_id;
                        flat_cp.owner_list = owner_name_list;
                        flat_cp.id_list = [flat_cp.id];
                        flat_cp.raw = [cp];
                        flat.push(flat_cp);
                    });

                    svc.copies = svc.copies.concat(flat);
                } else if (empty) {
                    svc.copies.push({
                        id_list    : [],
                        owner_id   : owner_id,
                        owner_list : owner_name_list,
                        call_number: egCore.idl.toHash(cn),
                        raw_call_number: cn
                    });
                }

                return cn;
            }
        );

        return svc.p = p;
    };

    return service;
}])
.directive("egVolumeList", function () {
    return {
        restrict:   'AE',
        scope: {
            recordId : '=',
            editVolumes : '@',
            editCopies  : '@'
        },
        templateUrl: './cat/share/t_volume_list',
        controller:
                   ['$scope','holdingsSvc','egCore','egGridDataProvider','$uibModal',
            function($scope , holdingsSvc , egCore , egGridDataProvider,  $uibModal) {
                var holdingsSvcInst = new holdingsSvc();

                $scope.holdingsGridControls = {};
                $scope.holdingsGridDataProvider = egGridDataProvider.instance({
                    get : function(offset, count) {
                        return this.arrayNotifier(holdingsSvcInst.copies, offset, count);
                    }
                });

                function gatherHoldingsIds () {
                    var cp_id_list = [];
                    angular.forEach(
                        $scope.holdingsGridControls.allItems(),
                        function (item) { cp_id_list = cp_id_list.concat(item.id_list) }
                    );
                    return cp_id_list;
                }

                var spawn_volume_editor = function (copies_too) {
                    egCore.net.request(
                        'open-ils.actor',
                        'open-ils.actor.anon_cache.set_value',
                        null, 'edit-these-copies', {
                            record_id: $scope.recordId,
                            copies: gatherHoldingsIds(),
                            hide_vols : false,
                            hide_copies : ((copies_too) ? false : true)
                        }
                    ).then(function(key) {
                        if (key) {
                            $uibModal.open({
                                templateUrl: './cat/share/t_embedded_volcopy',
                                backdrop: 'static',
                                size: 'lg',
                                windowClass: 'eg-wide-modal',
                                controller:
                                    ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                                    $scope.volcopy_url = 
                                        egCore.env.basePath + 'cat/volcopy/' + key + '/embedded';
                                    $scope.ok = function(args) { $uibModalInstance.close(args) }
                                    $scope.cancel = function () { $uibModalInstance.dismiss() }
                                }]
                            }).result.then(function() {
                                load_holdings();
                            });
                        }
                    });
                }
                $scope.edit_volumes = function() {
                    spawn_volume_editor(false);
                }
                $scope.edit_copies = function() {
                    spawn_volume_editor(true);
                }

                function load_holdings() {
                    holdingsSvcInst.fetch({
                        rid   : $scope.recordId,
                        org   : egCore.org.root(),
                        copy  : false,
                        vol   : true,
                        empty : true
                    }).then(function() {
                        $scope.holdingsGridDataProvider.refresh();
                    });
                };
                $scope.$watch('recordId',
                    function(newVal, oldVal) {
                        if (newVal && newVal !== oldVal) {
                            load_holdings();
                        }
                    }
                );
                load_holdings();
            }]
    }
})
.filter('string_pick', function() { return function(i){ return arguments[i] || ''; }; })
;
