angular.module('egSerialsMod', ['egCoreMod'])
.factory('egSerialsCoreSvc',
       ['egCore','orderByFilter','$q','$filter','$uibModal','ngToast','egConfirmDialog',
function(egCore , orderByFilter , $q , $filter , $uibModal , ngToast , egConfirmDialog) {
    var DAY = 86400000;
    var service = {
        bibId : null,
        subId : null,
        subTree : [],
        subList : [],
        sptList : [],
        mfhdList : [],
        potentialPatternList : [],
        flatMfhdList : [],
        itemMap : {},
        itemTree : [],
        itemList : [],
        freq_offset : {
            a : 365 * DAY,
            b : 62 * DAY,
            c : 4 * DAY,
            d : DAY,
            e : 14 * DAY,
            f : 186 * DAY,
            g : 2 * 365 * DAY,
            h : 3 * 365 * DAY,
            i : 2 * DAY,
            j : 10 * DAY,
            k : DAY,
            m : 31 * DAY,
            q : 93 * DAY,
            s : 14 * DAY,
            t : 124 * DAY,
            w : 7 * DAY,
            x : 0
        },
        freq_chrons : {
            a : ['year'],
            b : ['year','month'],
            c : ['year','month'],
            d : ['year','month','day'],
            e : ['year','month','day'],
            f : ['year','month'],
            g : ['year'],
            h : ['year','month'],
            i : ['year','month','day'],
            j : ['year','month','day'],
            k : ['year','month','day'],
            m : ['year','month'],
            q : ['year','season'],
            s : ['year','month'],
            t : ['year','month','day'],
            w : ['year','month','day'],
            x : ['year','month','day']
        },
        get_chron_part : {
            year  : function(d) { return d.getFullYear() },
            season: function(d) { return _loose_season(d) },
            month : function(d) { return ('00' + (d.getMonth() + 1)).slice(-2) },
            week  : function(d) { return $filter('date')(d, 'ww') },
            day   : function(d) { return ('00'+d.getDate()).slice(-2) },
            hour  : function(d) { return ('00'+d.getHours()).slice(-2) }
        },
        item_status_list : [
            'Expected',
            'Received',
            'Claimed',
            'Bindery',
            'Bound',
            'Discarded',
            'Not Held',
            'Not Published'
        ],
        item_status_i18n : []
    };

    angular.forEach(service.item_status_list, function(status) {
        service.item_status_i18n.push({
            name  : status,
            label : egCore.strings.SERIALS_ITEM_STATUS[status]
        });
    });

    function _loose_season(D) {
        var m = D.getMonth() + 1;
        var d = D.getDate();

        if (
            (m == 1 || m == 2) || (m == 12 && d >= 21) || (m == 3 && d < 20)
        ) {
            return 24;  /* MFHD winter */
        } else if (
            (m == 4 || m == 5) || (m == 3 && d >= 20) || (m == 6 && d < 21)
        ) {
            return 21;  /* spring */
        } else if (
            (m == 7 || m == 8) || (m == 6 && d >= 21) || (m == 9 && d < 22)
        ) {
            return 22;  /* summer */
        } else {
            return 23;  /* autumn */
        }
    }

    service.fetch_mfhds = function(bibId, contextOrg) {
        // TODO filter by contextOrg
        return egCore.pcrud.search('sre', {
                record       : bibId,
                deleted      : 'f',
                active       : 't'
            }, {
                flesh : 3,
                flesh_fields : {
                    'sre' : ['owning_lib']
                }
            },
            { atomic : true }
        ).then(function(list) {
            service.bibId = bibId;
            service.mfhdList = list;
            update_flat_mfhd_list();
        });
    }

    service.fetch_patterns_from_bibs_mfhds = function(bibId) {
        return egCore.net.request(
            'open-ils.serial',
            'open-ils.serial.caption_and_pattern.find_legacy_by_bib_record.atomic',
            egCore.auth.token(),
            bibId
        ).then(function(list) {
            service.potentialPatternList = egCore.idl.toTypedHash(list);
            angular.forEach(service.potentialPatternList, function(pot) {
                var rec = new MARC21.Record({ marcxml : pot.marc });
                var pattern_fields = rec.fields.filter(function(f) {
                    return (f.tag == '853' || f.tag == '854' || f.tag == '855');
                });
                pot.desc = '';
                if (pattern_fields.length > 0) {
                    // just take the first one
                    var fld = pattern_fields[0];
                    pot.desc = fld.tag + ' ' + fld.ind1 + fld.ind2 +
                               fld.subfields.map(function(sf) { 
                                 return '$' + sf[0] + sf[1]
                               }).join('');
                }
            });
        })
    }

    // fetch subscription, distributions, streams, captions,
    // and notes associated with the indicated bib
    service.fetch = function(bibId, contextOrg) {

        var filter = { record_entry : bibId };
        if (contextOrg) filter.owning_lib = egCore.org.descendants(contextOrg, true);
        return egCore.pcrud.search('ssub', filter,
            {
                flesh : 5,
                flesh_fields : {
                    'ssub'  : ['owning_lib','distributions', 'scaps', 'notes'],
                    'sdist' : [ 'record_entry','holding_lib',
                                'receive_call_number',
                                'receive_unit_template',
                                'bind_call_number',
                                'bind_unit_template',
                                'streams','notes'],
                    'sstr'  : ['routing_list_users'],
                    'srlu'  : ['reader'],
                    'au'    : ['card','home_ou','mailing_address','billing_address']
                }
            },
            { atomic : true }
        ).then(function(list) {
            service.bibId = bibId;
            service.subTree = list;
            update_flat_sdist_sstr_list();
            return $q.when(list);
        });
    }

    // fetch subscription, distributions, streams, captions,
    // and notes associated with the indicated bib
    service.fetchLastCallnumber = function(contextOrg) {
        return egCore.pcrud.search('acn', {
                record : service.bibId,
                owning_lib : contextOrg,
                deleted : 'f'
            }, { flesh : 1,
                 flesh_fields : {acn : ['prefix','suffix']},
                 order_by : [{class:'acn',field:'create_date',direction:'desc'}],
                 limit : 1
            }, { atomic : true }
        ).then(function(list) {
            return $q.when(list[0]);
        });
    }

    service.fetchItemsForSubPaged = function(subId,filter,offset,limit,sort) {
        return service.fetchItemsForSub(
            subId,
            filter,
            { limit : limit, offset : offset, paging : true },
            sort
        );
    }

    // Creates an inverted tree from item to sub
    service.fetchItemsForSub = function(subId,filter,options,sort) {
        var deferred = $q.defer(); // side-effects only, otherwise the grid is wonky

        if (!filter) filter = {};
        if (!options) options = { limit : 100 }; // only used during full refresh

        if (!subId && service.subId) subId = service.subId;
        if (!subId) return $q.reject('fetchItemsForSub: no subscription id');

        var sub = service.get_ssub(subId);
        if (!sub) return $q.reject('fetchItemsForSub: unknown subscription id');

        var streams = [];
        angular.forEach(sub.distributions(), function(dist) {
            angular.forEach(
                dist.streams().map(
                    function (stream) { return stream.id() }
                ),
                function (sid) { streams.push(sid) }
            );
        });

        angular.extend(filter, {stream:streams});
        angular.extend(options, { 
            order_by : [{class:'sitem',field:'date_expected'}], // best aprox of pub date
            flesh : 1,
            flesh_fields : {
                sitem : ['notes','issuance','editor','creator','unit','url']
            }
        });
        if (sort) {
            angular.extend(options, {
                order_by : [sort]
            });
        }

        egCore.pcrud.search(
            'sitem', filter, options,
            { atomic : true }
        ).then(function(list) {
            service.subId = subId;
            if (!options.paging) { // not paged
                service.itemTree = list;
                service.itemMap = {};
            } else { // paged
                angular.forEach(list, function (item) {
                    var exists = service.itemTree.filter(function (i) {
                        return i.id() == item.id()
                    }).length;
                    if (!exists) service.itemTree.push(item);
                });
            }

            // map items by stream for faster lookup
            var tmp = {};
            angular.forEach(list, function(item) {
                if (!tmp[item.stream()]) tmp[item.stream()] = [];
                tmp[item.stream()].push(item);
                service.itemMap[item.id()] = item;
            });

            angular.forEach(sub.distributions(), function(dist) {
                angular.forEach(dist.streams(), function(stream) {
                    angular.forEach(tmp[stream.id()], function (item) {
                        var routing_list = egCore.idl.Clone(stream.routing_list_users());
                        var st = egCore.idl.Clone(stream,1);
                        st.routing_list_users(routing_list);
                        var d = egCore.idl.Clone(dist,1);
                        var ss = egCore.idl.Clone(sub,1);
                        ss.distributions([]);
                        d.subscription(ss);
                        d.streams([]);
                        st.distribution(d);
                        item.stream(st);
                    });
                });
            });

            var hashList = egCore.idl.toHash(service.itemTree);
            angular.forEach(hashList, function (item) {
                item['issuance.date_published'] = item.issuance.date_published;
                item['stream.distribution.holding_lib.name'] = item.stream.distribution.holding_lib.name;
            });

            // ... then sort it
            if (sort) {
                service.itemList = hashList;
            } else {
                service.itemList = orderByFilter(hashList, ['"issuance.date_published"', '"stream.distribution.holding_lib.name"', '"id"']);
            }
            deferred.resolve();
        });

        return deferred.promise;
    }

    service.prep_new_holding_code = function (args) {

        var type = args.type;
        var date = args.date;
        var prev_iss = args.prev_iss;
        var curr_iss = args.curr_iss;
        var adhoc = false;
        var link = '1.1';
        var current_values = {};

        var sub = service.get_ssub(service.subId);
        if (!sub) return args;

        var scap;
        var pattern_changed = false;
        if (prev_iss && prev_iss.holding_code()) { // we're predicting
            var old_link_parts = JSON.parse(prev_iss.holding_code())[3].split('.');
            var olink = old_link_parts[0];
            var oseq = parseInt(old_link_parts[1]) + 1;
            link = [olink,oseq].join('.');

            if (prev_iss.holding_type())
                type = prev_iss.holding_type();

            if (prev_iss.caption_and_pattern()) {
                var tmp = sub.scaps().filter(function (s) {
                    return (s.id() == prev_iss.caption_and_pattern() && s.active() == 't');
                });
                if (angular.isArray(tmp) && tmp[0]) {
                    scap = tmp[0];
                } else {
                    // pattern associated with last issue must no longer be active
                    pattern_changed = true;
                }
            }

            date = new Date(prev_iss.date_published());
        } else if (curr_iss) { // we're editing
            if (curr_iss.holding_type())
                type = curr_iss.holding_type();

            if (curr_iss.caption_and_pattern()) {
                var tmp = sub.scaps().filter(function (s) {
                    return (s.id() == curr_iss.caption_and_pattern());
                });
                if (angular.isArray(tmp) && tmp[0]) scap = tmp[0];
            }
            if (!curr_iss.holding_code()) {
                adhoc = true;
            } else {
                var tmp = JSON.parse(curr_iss.holding_code());
                for (var i = 2; i < tmp.length; i += 2) {
                    // we're intentionally being a bit sloppy here, as
                    // the only subfields we are about in this context
                    // are the ones that are not repeatable
                    current_values[tmp[i]] = tmp[i + 1];
                }
            }

            date = new Date(curr_iss.date_published());
        } else {
            // starting from scratch, so default the
            // first publication date to the subscription start date
            if (!date) date = new Date(sub.start_date());
        }

        args.date = date;

        if (!scap) {
            var tmp = sub.scaps().filter(function (s) {
                return (s.type() == type && s.active() == 't');
            });
            if (angular.isArray(tmp) && tmp[0]) scap = tmp[0];
        }

        if (!scap) return args;

        var others = [], enums = [], chrons = [], freq = '';
        var pat = JSON.parse(scap.pattern_code()).slice(4); // just the part we care about

        var freq_index = pat.indexOf('w');
        if (freq_index > -1) {
            freq = pat[freq_index + 1];
            if (prev_iss && !args.pattern_changed) {
                date = new Date(
                    date.getTime() + service.freq_offset[freq]
                );
            }
        }
       
        if (!date) date = new Date();

        for (var i = 0; i < pat.length; i++) {
            sf = pat[i]; i++;
            val = pat[i];

            if (sf != 'w') {
                var pat_part = {
                    subfield : sf,
                    pattern  : val
                };

                var chron_part = String(val).replace(/[)(]+/g,'');
                if (sf in current_values) {
                    pat_part.value = current_values[sf];
                } else {
                    try {
                        pat_part.value = service.get_chron_part[chron_part](date);
                    } catch (e) {
                        // not a chron part
                        pat_part.value = '';
                    }
                }

                if (sf.match(/[a-f]/)) {
                    enums.push(pat_part);
                } else if (sf.match(/[i-l]/)) {
                    chrons.push(pat_part);
                } else {
                    others.push(pat_part);
                }
            }
        }

        if (enums.length == 0 && chrons.length == 0) {
            var parts = service.freq_chrons[freq];
            if (parts.length) {
                angular.forEach(parts, function(p, ind) {
                    var sf = !ind ? 'i' : !--ind ? 'j' : 'k';
                    chrons.push({
                        subfield : sf,
                        value    : service.get_chron_part.year(date)
                    });
                });
            } else { 
                chrons = [
                    { subfield : 'i', value : service.get_chron_part.year(date)  },
                    { subfield : 'j', value : service.get_chron_part.month(date) },
                    { subfield : 'k', value : service.get_chron_part.day(date)  }
                ];
            }
        }

        return {
            holding_code : ["4","1","8",link],
            scap         : scap.id(),
            type         : type,
            date         : date,
            enums        : enums,
            chrons       : chrons,
            others       : others,
            freq         : freq,
            adhoc        : adhoc,
            pattern_changed : pattern_changed
        };
    }

    service.new_holding_code = function (options) {
        if (options === undefined) options = {};
        options.count = options.count || 1;
        options.label = options.label || '';

        return $uibModal.open({
            templateUrl: './serials/t_holding_code_dialog',
            //size: 'lg',
            //windowClass: 'eg-wide-modal',
            backdrop: 'static',
            controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                $scope.focusMe = true;
                $scope.title = options.title;
                $scope.request_count = options.request_count;
                $scope.count = options.count;
                $scope.label = options.label;
                $scope.save_label = options.save_label;
                $scope.pubdate = options.date;
                $scope.type = options.type || 'basic';
                $scope.args = { adhoc : false };
                if (options.adhoc) $scope.args.adhoc = true;
                $scope.can_change_adhoc = options.can_change_adhoc;

                function refresh (n,o) {
                    if (n && o && n !== o) {
                        $scope.args = service.prep_new_holding_code({
                            type : $scope.type,
                            date : $scope.pubdate,
                            prev_iss : options.prev_iss,
                            curr_iss : options.curr_iss,
                        });
                        if (!options.can_change_adhoc && options.adhoc) $scope.args.adhoc = true;

                        if ($scope.args.type && $scope.type != $scope.args.type)
                            $scope.type = $scope.args.type;
                        if ($scope.args.date)
                            $scope.pubdate = $scope.args.date;

                        delete options.prev_iss; // only use this once
                        delete options.curr_iss; // only use this once
                    }
                }

                $scope.$watch('count',function (n) {options.count = n});
                $scope.$watch('label',function (n) {options.label = n});
                $scope.$watch('type',refresh);
                $scope.$watch('pubdate',refresh);

                $scope.ok = function(args) { $uibModalInstance.close(args) }
                $scope.cancel = function () { $uibModalInstance.dismiss() }

                refresh(1,2); // force data loading
            }]
        }).result.then(function (args) {
            if (args.enums && args.chrons) {
                angular.forEach(
                    args.enums.concat(args.chrons),
                    function (e) {
                        args.holding_code.push(e.subfield);
                        args.holding_code.push(e.value);
                    }
                );
            }
            args.count = options.count;
            args.label = options.label;
            return $q.when(args);
        });
    }

    function update_flat_mfhd_list() {
        var list = [];
        angular.forEach(service.mfhdList, function(sre) {
            var mfhdHash = egCore.idl.toHash(sre);
            var rec = new MARC21.Record({ marcxml : mfhdHash.marc });
            var _mfhd = {
                'id'                   : mfhdHash.id,
                'owning_lib.name'      : mfhdHash.owning_lib.name,
                'owning_lib.id'        : mfhdHash.owning_lib.id,
                'marc'                 : rec.toBreaker(),
                'marc_xml'             : mfhdHash.marc,
                'svr'                  : null,
                'basic_holdings'       : null,
                'index_holdings'       : null,
                'supplement_holdings'  : null
            }
            list.push(_mfhd);
            egCore.net.request(
                'open-ils.search',
                'open-ils.search.serial.record.mfhd.retrieve',
                mfhdHash.id
            ).then(function(svr) {
                _mfhd.svr = egCore.idl.toTypedHash(svr);
                _mfhd.basic_holdings = _mfhd.svr.basic_holdings.join("; ");
                _mfhd.index_holdings = _mfhd.svr.index_holdings.join("; ");
                _mfhd.supplement_holdings = _mfhd.svr.supplement_holdings.join("; ");
            })
        });
        service.flatMfhdList.length = 0;
        angular.extend(service.flatMfhdList, list);
    }

    // create/update a flat version of the subscription/distribution/stream
    // tree for feeding to the distribution and stream grid
    function update_flat_sdist_sstr_list() {

        // flatten the structure...
        var list = [];
        angular.forEach(service.subTree, function(ssub) {
            var ssubHash = egCore.idl.toHash(ssub);

            var _ssub = {
                'id'                   : ssubHash.id,
                'owning_lib.name'      : ssubHash.owning_lib.name,
                'owning_lib.id'        : ssubHash.owning_lib.id,
                'start_date'           : ssubHash.start_date,
                'end_date'             : ssubHash.end_date,
                'expected_date_offset' : ssubHash.expected_date_offset
            };
            // insert and escape if we have no distributions
            if (ssubHash.distributions.length == 0) {
                list.push(_ssub);
                return;
            }

            angular.forEach(ssubHash.distributions, function(sdist) {
                var _sdist = {};
                angular.forEach([
                    'id',
                    'summary_method',
                    'record_entry',
                    'label',
                    'display_grouping',
                    'unit_label_prefix',
                    'unit_label_suffix',
                ], function(fld) {
                    _sdist['sdist.' + fld] = sdist[fld];
                });
                _sdist['sdist.holding_lib.name'] = sdist.holding_lib.name;
                _sdist['sdist.holding_lib.id'] = sdist.holding_lib.id;
                _sdist['sdist.receive_call_number.label'] = 
                    sdist.receive_call_number ? sdist.receive_call_number.label : null;
                _sdist['sdist.receive_unit_template.name'] =
                    sdist.receive_unit_template ? sdist.receive_unit_template.name : null;
                _sdist['sdist.bind_call_number.label'] =
                    sdist.bind_call_number ? sdist.bind_call_number.label : null;
                _sdist['sdist.bind_unit_template.name'] =
                    sdist.bind_unit_template ? sdist.bind_unit_template.name : null;
                // if we have no streams, add to the list and escape
                if (sdist.streams.length == 0) {
                    var row = {};
                    angular.extend(row, _ssub, _sdist);
                    list.push(row);
                    return;
                }

                angular.forEach(sdist.streams, function(sstr) {
                    var _sstr = {
                        'sstr.id'                 : sstr.id,
                        'sstr.routing_label'      : sstr.routing_label,
                        'sstr.additional_routing' : ((sstr.routing_list_users.length > 0) ? true : false)
                    };
                    var row = {};
                    angular.extend(row, _ssub, _sdist, _sstr);
                    list.push(row);
                });
            });
        });

        // ... then sort it
        service.subList.length = 0;
        angular.extend(service.subList,
            orderByFilter(list, ['"owning_lib.name"', '"start_date"', '"end_date"',
                                 '"holding_lib.name"', '"sdist.id"', '"sstr.id"'])
        );

        // ... then remove duplication of owning library, distribution library,
        // and distribution labels
        var sub_lib = null;
        var dist_lib = null;
        var dist_label = null;
        var index = 0;
        angular.forEach(service.subList, function(row) {
            row['index'] = index++;
            if (sub_lib == row['owning_lib.name']) {
                row['owning_lib.name'] = null;
            } else {
                sub_lib = row['owning_lib.name'];
                dist_lib = row['sdist.holding_lib.name'];
                dist_label = row['sdist.label'];
                return;
            }
            if (dist_lib == row['sdist.holding_lib.name']) {
                row['sdist.holding_lib.name'] = null;
            } else {
                dist_lib = row['sdist.holding_lib.name'];
            }
            if (dist_label == row['sdist.label']) {
                row['sdist.label'] = null;
            } else {
                dist_label = row['sdist.label'];
            }
        });
    }

    // verify that a subscription ID and bib ID are actually
    // associated with each other
    service.verify_subscription_id = function(bibId, ssubId) {
        var deferred = $q.defer();
        egCore.pcrud.search('ssub', {
                record_entry : bibId,
                id           : ssubId
        }, {}, { atomic : true, idlist : true }
        ).then(function(list) {
            if (list.length == 1) {
                deferred.resolve(true);
            } else {
                deferred.resolve(false);
            }
        });
        return deferred.promise;
    }

    service.get_ssub = function(ssubId) {
        if (!ssubId) return;
        for (var i = 0; i <= service.subTree.length; i++) {
            if (service.subTree[i].id() == ssubId) {
                return service.subTree[i];
            }
        }
    }

    service.fetch_spt = function() {
        return egCore.net.request(
            'open-ils.serial',
            'open-ils.serial.pattern_template.retrieve.at.atomic',
            egCore.auth.token(),
            egCore.auth.user().ws_ou()
        ).then(function(list) {
            service.sptList.length = 0;
            angular.extend(service.sptList, list);
        });
    }

    service.fetch_templates = function(org) {
        return egCore.pcrud.search('act',
            {owning_lib : egCore.org.fullPath(org, true)},
            {order_by : { act : 'name' }}, {atomic : true}
        );
    };

    service.print_routing_lists = function (bibId, items, check, force, print_rl) {
        if (!check && !print_rl && !force) return $q.when();

        return egCore.net.request(
            'open-ils.search',
            'open-ils.search.biblio.record.mods_slim.retrieve',
            bibId
        ).then(function(mvr) {

            var by_issuance = {};
            angular.forEach(items, function (i) {
                if (check && !i._print_routing_list) return;
                if (!by_issuance[i.issuance().id()])
                    by_issuance[i.issuance().id()] = [];
                by_issuance[i.issuance().id()].push(i);
            });

            var issuance_matrix = [];
            angular.forEach(by_issuance, function (list) {
                issuance_matrix.push(list);
            });

            var deferred = $q.defer();
            var promise = deferred.promise;

            angular.forEach(issuance_matrix, function(item_list, index) {

                promise = promise.then(function(){
                    return $uibModal.open({
                        templateUrl: './serials/t_print_routing_list',
                        size: 'lg',
                        windowClass: 'eg-wide-modal',
                        backdrop: 'static',
                        controller:
                        ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                            var all_users = [];
                            var all_streams = [];

                            angular.forEach(item_list, function(i){
                                all_streams.push(i.stream());
                                all_users = all_users.concat(i.stream().routing_list_users());
                            });

                            $scope.xulg = {
                                show_print_button: true,
                                routing_list_data: {
                                    streams : all_streams,
                                    mvr     : mvr,
                                    issuance: item_list[0].issuance(),
                                    users   : orderByFilter(all_users, 'pos')
                                }
                            };

                            $scope.url = '/eg/serial/print_routing_list_users?ses=' + egCore.auth.token();
                            $scope.last = index == issuance_matrix.length - 1 ? true : false; 
                            $scope.ok = function() { $uibModalInstance.close() }
                        }]
                    }).result;
                });

            });

            return deferred.resolve();
        });

    }

    service.set_item_status = function(newStatus, bibId, list, callback) {
        if (!callback) callback = function () { return $q.when() }
        if (!list.length) return $q.reject();

        return egConfirmDialog.open(
            egCore.strings.CONFIRM_CHANGE_ITEMS.status,
            egCore.strings.CONFIRM_CHANGE_ITEMS_MESSAGE.status,
            {items : list.length}
        ).result.then(function () {
            var promises = [$q.when()];
            angular.forEach(list, function(item) {
                item.status(newStatus);
                promises.push(
                    egCore.net.request(
                        'open-ils.serial',
                        'open-ils.serial.item.update',
                        egCore.auth.token(),
                        item
                    ).then(function(res) {
                        return $q.when();
                    })
                );
            });
            $q.all(promises).then(function() {
                callback();
            });
        });
    }
    
    service.process_items = function (mode, bibId, list, do_barcode, bind, print_rl, callback) {
        if (!callback) callback = function () { return $q.when() }
        if (!list.length) return $q.reject();

        // deal with locations and circ mods for *NEW* units
        var copy_locations = {};
        var circ_mods = {};

        // deal with barcodes and call numbers for *NEW* units
        var barcodes = {};
        var call_numbers = {};
        var call_numbers_by_siss_and_sdist = {};

        var deferred = $q.defer();
        var current_promise = deferred.promise;
        var last_promise;

        var sitem_alerts = [];
        var sdist_alerts = [];
        var ssub_alerts = list[0].stream().distribution().subscription().notes().filter(function(n){
            return n.alert() == 't';
        })

        var dist_seen = {};
        angular.forEach(list, function(i) {
            sitem_alerts = sitem_alerts.concat(
                i.notes().filter(function(n){
                    return n.alert() == 't';
                })
            );
            var sdist = '_'+i.stream().distribution().id();
            if (!dist_seen[sdist]) {
                dist_seen[sdist] = 1;
                sdist_alerts = sdist_alerts.concat(
                    i.stream().distribution().notes().filter(function(n){
                        return n.alert() == 't';
                    })
                );
            }
        });

        if (do_barcode || bind) {

            last_promise = current_promise.then(function(){ return $uibModal.open({
                templateUrl: './serials/t_batch_receive',
                size: 'lg',
                windowClass: 'eg-wide-modal',
                backdrop: 'static',
                controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {

                    $scope.print_routing_lists = print_rl;
                    $scope.barcode_items = do_barcode;
                    $scope.force_bind = bind;
                    $scope.bind = bind;
                    $scope.items = list;
                    $scope.ssub_alerts = ssub_alerts;
                    $scope.sdist_alerts = sdist_alerts;
                    $scope.sitem_alerts = sitem_alerts;
                    $scope.acn_list = [];
                    $scope.acnp_labels = [];
                    $scope.acns_labels = [];
                    $scope.acpl_list = [];

                    $scope.cannot_print = function (index) {
                        return $scope.items[index].stream().routing_list_users().length == 0 || ($scope.bind && index > 0);
                    }

                    $scope.bind_or_none = function (index) {
                        return !$scope.barcode_items || ($scope.bind && index > 0);
                    }

                    $scope.focus_next_barcode = function (index) {
                        index++;
                        $('#item_barcode_'+index).focus().select();
                    }

                    $scope.fullCNLabel = function (cn) {
                        var label = [cn.prefix.label,cn.label,cn.suffix.label].join(' ');
                        return label;
                    }

                    $scope.apply_template_overrides = function (e) {
                        if ($scope.selected_call_number) {
                            angular.forEach($scope.items, function (i) {
                                i._call_number = $scope.selected_call_number.label;
                                i._cn_prefix = $scope.selected_call_number.prefix.label;
                                i._cn_suffix = $scope.selected_call_number.suffix.label;
                            });
                        }
                        if ($scope.selected_circ_mod) {
                            angular.forEach($scope.items, function (i) {
                                i._circ_mod = $scope.selected_circ_mod;
                            });
                        }
                        if ($scope.selected_copy_location) {
                            angular.forEach($scope.items, function (i) {
                                i._copy_location = $scope.selected_copy_location;
                            });
                        }
                    }

                    $scope.ok = function(items) { $uibModalInstance.close(items) }
                    $scope.cancel = function () { $uibModalInstance.dismiss() }

                    var dist_libs = {};
                    var pile_o_promises = [$q.when()];

                    // let's gather what we need...
                    angular.forEach(list, function (i, index) {
                        var dlib = i.stream().distribution().holding_lib().id();
                        dist_libs[dlib] = egCore.org.fullPath(dlib, true);
                        if (i.unit()) {
                            i._barcode = i.unit().barcode();
                            pile_o_promises.push(
                                egCore.pcrud.retrieve(
                                    'acn', i.unit().call_number(),
                                    {flesh : 1, flesh_fields : {acn : ['prefix','suffix']}}
                                ).then(function(cn){
                                    if (cn.deleted() == 'f') {
                                        i._call_number = cn.label();
                                        i._cn_prefix = cn.prefix().label();
                                        i._cn_suffix = cn.suffix().label();
                                    }
                                })
                            );
                        } else {
                            if (i.stream().distribution()[mode + '_call_number']() && 
                                i.stream().distribution()[mode + '_call_number']().deleted() == 'f'
                            ) {
                                i._call_number = i.stream().distribution()[mode + '_call_number']().label();
                            } else {
                                pile_o_promises.push(
                                    service.fetchLastCallnumber(
                                        i.stream().distribution().holding_lib().id()
                                    ).then(function(cn){
                                        if (cn) {
                                            i._call_number = cn.label();
                                            i._cn_prefix = cn.prefix().label();
                                            i._cn_suffix = cn.suffix().label();
                                        }
                                    })
                                );
                            }
                        }

                        if (i.stream().distribution()[mode + '_unit_template']()) {
                            i._copy_location = i.stream().distribution()[mode + '_unit_template']().location();
                            i._circ_mod = i.stream().distribution()[mode + '_unit_template']().circ_modifier();
                        }

                        if ($scope.print_routing_lists && !$scope.cannot_print(index))
                            i._print_routing_list = true;

                        i._receive = true;
                    });

                    // build unique list of orgs from distribution.holding_lib fullPaths
                    var dist_lib_list = [];
                    angular.forEach(dist_libs, function (l) {
                        dist_lib_list = dist_lib_list.concat(l);
                    });
                    dist_lib_list = dist_lib_list.filter(function(v,i,s){
                        return s.indexOf(v) == i;
                    });

                    // Copy locations only come from the workstation location, same as XUL
                    pile_o_promises.push(egCore.pcrud.search(
                        'acpl',
                        {owning_lib : egCore.org.fullPath(egCore.auth.user().ws_ou(), true)},
                        {},{ atomic : true }
                    ).then(function (list) {
                        $scope.acpl_list = list.map(function(i){return egCore.idl.toHash(i)});
                        return $q.when();
                    }));

                    // Call numbers, however, come from anywhere the distributions might live
                    pile_o_promises.push(egCore.pcrud.search(
                        'acn',
                        {deleted : 'f', record : bibId, owning_lib : dist_lib_list},
                        {flesh : 1, flesh_fields : {acn : ['prefix','suffix']}},{ atomic : true }
                    ).then(function (list) {
                        $scope.acn_list = list.map(function(i){return egCore.idl.toHash(i)});
                        return $q.when();
                    }));

                    // Likewise for prefix and suffix, for combo box
                    angular.forEach(['acnp','acns'], function (cl) {
                        pile_o_promises.push(egCore.pcrud.search(
                            cl,
                            {owning_lib : dist_lib_list},
                            {},{ atomic : true }
                        ).then(function (list) {
                            $scope[cl+'_labels'] = list.map(function(i){return i.label()});
                            return $q.when();
                        }));
                    });

                    pile_o_promises.push(egCore.pcrud.retrieveAll(
                        'ccm', {}, { atomic : true }
                    ).then(function (list) {
                        $scope.ccm_list = list.map(function(i){return egCore.idl.toHash(i)});
                        return $q.when();
                    }));

                    $q.all(pile_o_promises).then(function() {
                        console.log('receive data collected');
                    });

                    $scope.$watch('barcode_items', function (n,o) {
                        if (n === undefined || n == o) return;
                        do_barcode = n;
                    });

                    $scope.$watch('bind', function (n,o) {
                        if (n === undefined || n == o) return;
                        bind = n;
                        if (bind) {
                            angular.forEach($scope.items, function (i,index) {
                                if (index > 0) i._print_routing_list = false;
                            });
                        }
                    });
                        
                    $scope.$watch('auto_barcodes', function (n,o) {
                        if (n === undefined || n == o) return;

                        var bc = '@@AUTO';
                        if (!n) bc = '';

                        angular.forEach($scope.items, function (i) {
                            if (!i.stream().distribution().receive_unit_template()) return;
                            var _barcode = i._barcode;
                            i._barcode = bc || i._old_barcode;
                            i._old_barcode = _barcode;
                        });
                    });

                    $scope.$watch('print_routing_lists', function (n,o) {
                        if (n === undefined || n == o) return;

                        angular.forEach($scope.items, function(i, index) {
                            if (!$scope.cannot_print(index)) {
                                i._print_routing_list = n;
                            } else {
                                i._print_routing_list = false;
                            }
                        });
                    });
                }]
            }).result});
        } else {
            last_promise = current_promise.then(function(){ return $uibModal.open({
                templateUrl: './serials/t_receive_alerts',
                backdrop: 'static',
                controller:
                ['$scope', '$uibModalInstance', function($scope, $uibModalInstance) {
                    $scope.title = egCore.strings.CONFIRM_CHANGE_ITEMS[mode];
                    $scope.items = list.length;
                    $scope.list = list;
                    $scope.mode = mode;
                    $scope.ssub_alerts = ssub_alerts;
                    $scope.sdist_alerts = sdist_alerts;
                    $scope.sitem_alerts = sitem_alerts;

                    $scope.ok = function(items) { $uibModalInstance.close(items) }
                    $scope.cancel = function () { $uibModalInstance.dismiss() }
                }]
            }).result.then(
                function(items) {
                    angular.forEach(list, function (i, index) {
                        i._receive = true;
                    });
                    return $q.when(list);
                })
            });
        }

        last_promise.then(function (items) {

            var method;
            if (mode == 'receive') {
                method = 'open-ils.serial.receive_items';
                items = items.filter(function(i){return i._receive});
            } else if ( mode == 'bind') {
                method = 'open-ils.serial.bind_items';
                items = items.filter(function(i){return i._receive});
            } else if ( mode == 'reset') {
                method = 'open-ils.serial.reset_items';
            } 

            if (!items.length) return $q.reject();

            var donor_unit_ids = {};
            angular.forEach(items, function(i, index) {
                if (i.unit()) donor_unit_ids[i.unit().id()] = 1;
                if (do_barcode) i.unit(-1);
                if (bind) i.unit(-2);
                copy_locations[i.id()] = i._copy_location;
                circ_mods[i.id()] = i._circ_mod;
                call_numbers[i.id()] = [i._cn_prefix, i._call_number, i._cn_suffix] || 'DEFAULT';
                barcodes[i.id()] = i._barcode || '@@AUTO';
                if (bind && index > 0) barcodes[i.id()] = items[0]._barcode;
            });

            return egCore.net.request(
                'open-ils.serial', method,
                egCore.auth.token(), items, barcodes, call_numbers, donor_unit_ids,
                    {circ_mods:circ_mods, copy_locations : copy_locations}
            ).then(
                function(resp) {
                    var evt = egCore.evt.parse(resp);
                    if (evt) {
                        ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                    } else {
                        ngToast.success(egCore.strings.SERIALS_ISSUANCE_SUCCESS_SAVE);
                        return service.print_routing_lists(bibId, items, do_barcode || bind, false, print_rl)
                            .finally(callback);
                    }
                },
                function(resp) {
                    ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                }
            );
        });

        return deferred.resolve();
    }

    service.add_issuances = function (mySsubId) {
        if (!mySsubId && service.subId) mySsubId = service.subId;
        if (!mySsubId) return $q.reject('fetchItemsForSub: no subscription id');

        var sub = service.get_ssub(mySsubId);
        if (!sub) return $q.reject('fetchItemsForSub: unknown subscription id');

        var streams = [];
        angular.forEach(sub.distributions(), function(dist) {
            angular.forEach(
                dist.streams().map(
                    function (stream) { return stream.id() }
                ),
                function (sid) { streams.push(sid) }
            );
        });

        var options = { 
            order_by : [{class:'sitem',field:'date_expected',direction:'desc'}], // best aprox of pub date
            limit : 1,
            flesh : 1,
            flesh_fields : { sitem : ['issuance'] }
        };

        return egCore.pcrud.search(
            'sitem', {stream:streams},
            {   order_by : [{class:'sitem',field:'date_expected',direction:'desc'}], // best aprox of pub date
                limit : 1,
                flesh : 1,
                flesh_fields : { sitem : ['issuance'] }
            },
            { atomic : true }
        ).then(function(list) {
            var lastItem = list[0];
    
            if (lastItem) lastItem = lastItem.issuance();
    
            return service.new_holding_code({
                title : egCore.strings.SERIALS_ISSUANCE_PREDICT,
                request_count : true,
                prev_iss : lastItem,
                allow_adhoc : false
            }).then(function(hc) {
    
                var base_iss;
                var include_base_iss = 0;
                if (!lastItem || hc.pattern_changed) {
                    include_base_iss = 1;
                    base_iss = new egCore.idl.siss();
                    base_iss.creator( egCore.auth.user().id() );
                    base_iss.editor( egCore.auth.user().id() );
                    base_iss.date_published( hc.date.toISOString() );
                    base_iss.subscription( mySsubId );
                    base_iss.caption_and_pattern( hc.scap );
                    base_iss.holding_code( JSON.stringify(hc.holding_code) );
                    base_iss.holding_type( hc.type );
                }

                // if we're predicting without a preexisting holding, reduce the count
                if (!lastItem) hc.count--;
    
                return egCore.net.request(
                    'open-ils.serial',
                    'open-ils.serial.make_predictions',
                    egCore.auth.token(),
                    { ssub_id : mySsubId,
                      include_base_issuance : include_base_iss,
                      num_to_predict : hc.count,
                      base_issuance : base_iss || lastItem
                    }
                ).then(
                    function(resp) {
                        var evt = egCore.evt.parse(resp);
                        if (evt) {
                            ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                        } else {
                            ngToast.success(egCore.strings.SERIALS_ISSUANCE_SUCCESS_SAVE);
                        }
                    },
                    function(resp) {
                        ngToast.danger(egCore.strings.SERIALS_ISSUANCE_FAIL_SAVE);
                    }
                );
            });
        });
    }

    return service;
}]);

