angular.module('egHoldingsMod', ['egCoreMod'])

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

    service.fetchAgain = function() {
        return service.fetch({
            rid: service.rid,
            org: service.org,
            copy: service.copy,
            vol: service.vol,
            empty: service.empty
        })
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
        service.copy = opts.copy;
        service.vol = opts.vol;
        service.empty = opts.empty;

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
                                    if (cp.raw) current_blob.raw = current_blob.raw.concat(cp.raw);
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

                service.copies = new_list;
                service.ongoing = false;
            },

            null, // error

            // notify reads the stream of copies, one at a time.
            function(cn) {

                var copies = cn.copies().filter(function(cp){ return cp.deleted() == 'f' });
                cn.copies([]);

                angular.forEach(copies, function (cp) {
                    cp.call_number(cn);
                });

                var owner_id = cn.owning_lib();
                var owner = egCore.org.get(owner_id);

                var owner_name_list = [];
                while (owner.parent_ou()) { // we're going to skip the top of the tree...
                    owner_name_list.unshift(owner.name());
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

                    service.copies = service.copies.concat(flat);
                } else if (empty) {
                    service.copies.push({
                        owner_id   : owner_id,
                        owner_list : owner_name_list,
                        call_number: egCore.idl.toHash(cn),
                        raw_call_number: cn
                    });
                }

                return cn;
            }
        );
    }

    return service;
}]);
