/**
 * Vol/Copy Editor
 */

angular.module('egVolCopy',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod'])

.filter('boolText', function(){
    return function (v) {
        return v == 't';
    }
})

.config(['ngToastProvider', function(ngToastProvider) {
  ngToastProvider.configure({
    verticalPosition: 'bottom',
    animation: 'fade'
  });
}])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
    var resolver = {
        delay : ['egStartup', function(egStartup) { return egStartup.go(); }]
    };

    $routeProvider.when('/cat/volcopy/edit_templates', {
        templateUrl: './cat/volcopy/t_view',
        controller: 'EditCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/volcopy/:dataKey', {
        templateUrl: './cat/volcopy/t_view',
        controller: 'EditCtrl',
        resolve : resolver
    });

    $routeProvider.when('/cat/volcopy/:dataKey/:mode', {
        templateUrl: './cat/volcopy/t_view',
        controller: 'EditCtrl',
        resolve : resolver
    });
})

.factory('itemSvc', 
       ['egCore','$q',
function(egCore , $q) {

    var service = {
        currently_generating : false,
        auto_gen_barcode : false,
        barcode_checkdigit : false,
        new_cp_id : 0,
        new_cn_id : 0,
        tree : {}, // holds lib->cn->copy hash stack
        copies : [] // raw copy list
    };

    service.nextBarcode = function(bc) {
        service.currently_generating = true;
        return egCore.net.request(
            'open-ils.cat',
            'open-ils.cat.item.barcode.autogen',
            egCore.auth.token(),
            bc, 1, { checkdigit: service.barcode_checkdigit }
        ).then(function(resp) { // get_barcodes
            var evt = egCore.evt.parse(resp);
            if (!evt) return resp[0];
            return '';
        });
    };

    service.checkBarcode = function(bc) {
        if (!service.barcode_checkdigit) return true;
        if (bc != Number(bc)) return false;
        bc = bc.toString();
        // "16.00" == Number("16.00"), but the . is bad.
        // Throw out any barcode that isn't just digits
        if (bc.search(/\D/) != -1) return false;
        var last_digit = bc.substr(bc.length-1);
        var stripped_barcode = bc.substr(0,bc.length-1);
        return service.barcodeCheckdigit(stripped_barcode).toString() == last_digit;
    };

    service.barcodeCheckdigit = function(bc) {
        var reverse_barcode = bc.toString().split('').reverse();
        var check_sum = 0; var multiplier = 2;
        for (var i = 0; i < reverse_barcode.length; i++) {
            var digit = reverse_barcode[i];
            var product = digit * multiplier; product = product.toString();
            var temp_sum = 0;
            for (var j = 0; j < product.length; j++) {
                temp_sum += Number( product[j] );
            }
            check_sum += Number( temp_sum );
            multiplier = ( multiplier == 2 ? 1 : 2 );
        }
        check_sum = check_sum.toString();
        var next_multiple_of_10 = (check_sum.match(/(\d*)\d$/)[1] * 10) + 10;
        var check_digit = next_multiple_of_10 - Number(check_sum); if (check_digit == 10) check_digit = 0;
        return check_digit;
    };

    // returns a promise resolved with the list of circ mods
    service.get_classifications = function() {
        if (egCore.env.acnc)
            return $q.when(egCore.env.acnc.list);

        return egCore.pcrud.retrieveAll('acnc', null, {atomic : true})
        .then(function(list) {
            egCore.env.absorbList(list, 'acnc');
            return list;
        });
    };

    var _acnp_promises = {};
    var _acnp_cache = {};
    service.get_prefixes = function(org) {

        var _org_id;
        if (angular.isObject(org)) {
            _org_id = org.id();
        } else {
            _org_id = org;
        }

        if (!(_org_id in _acnp_promises)) {
            _acnp_promises[_org_id] = $q.defer();

            if (_org_id in _acnp_cache) {
                $_acnp_promises[_org_id].resolve(_acnp_cache[_org_id]);
            } else {
                egCore.pcrud.search('acnp',
                    {owning_lib : egCore.org.fullPath(org, true)},
                    {order_by : { acnp : 'label_sortkey' }}, {atomic : true}
                ).then(function(list) {
                    _acnp_cache[_org_id] = list;
                    _acnp_promises[_org_id].resolve(list);
                });
            }
        }

        return _acnp_promises[_org_id].promise;
    };

    service.get_statcats = function(orgs) {
        return egCore.pcrud.search('asc',
            {owner : orgs},
            { flesh : 1,
              flesh_fields : {
                asc : ['owner','entries']
              },
              order_by : [{'class':'asc', 'field':'owner'},{'class':'asc', 'field':'name'},{'class':'asce', 'field':'value'} ]
            },
            { atomic : true }
        );
    };

    service.get_copy_alert_types = function(orgs) {
        return egCore.pcrud.search('ccat',
            { active : 't' },
            {},
            { atomic : true }
        );
    };

    service.get_locations_by_org = function(orgs) {
        return egCore.pcrud.search('acpl',
            {owning_lib : orgs, deleted : 'f'},
            {
                flesh : 1,
                flesh_fields : {
                    acpl : ['owning_lib']
                },
                order_by : { acpl : 'name' }
            },
            {atomic : true}
        );
    };

    service.fetch_locations = function(locs) {
        return egCore.pcrud.search('acpl',
            {id : locs},
            {
                flesh : 1,
                flesh_fields : {
                    acpl : ['owning_lib']
                },
                order_by : { acpl : 'name' }
            },
            {atomic : true}
        );
    };

    var _acns_promises = {};
    var _acns_cache = {};
    service.get_suffixes = function(org) {

        var _org_id;
        if (angular.isObject(org)) {
            _org_id = org.id();
        } else {
            _org_id = org;
        }

        if (!(_org_id in _acns_promises)) {
            _acns_promises[_org_id] = $q.defer();

            if (_org_id in _acns_cache) {
                $_acns_promises[_org_id].resolve(_acns_cache[_org_id]);
            } else {
                egCore.pcrud.search('acns',
                    {owning_lib : egCore.org.fullPath(org, true)},
                    {order_by : { acns : 'label_sortkey' }}, {atomic : true}
                ).then(function(list) {
                    _acns_cache[_org_id] = list;
                    _acns_promises[_org_id].resolve(list);
                });
            }
        }

        return _acns_promises[_org_id].promise;
    };

    service.get_magic_statuses = function() {
        /* TODO: make these more configurable per lp1616170 */
        return $q.when([
             1  /* Checked out */
            ,3  /* Lost */
            ,6  /* In transit */
            ,8  /* On holds shelf */
            ,16 /* Long overdue */
            ,18 /* Canceled Transit */
        ]);
    }

    service.get_statuses = function() {
        if (egCore.env.ccs)
            return $q.when(egCore.env.ccs.list);

        return egCore.pcrud.retrieveAll('ccs', {order_by : { ccs : 'name' }}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'ccs');
                return list;
            }
        );

    };

    service.get_circ_mods = function() {
        if (egCore.env.ccm)
            return $q.when(egCore.env.ccm.list);

        return egCore.pcrud.retrieveAll('ccm', {}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'ccm');
                return list;
            }
        );

    };

    service.get_circ_types = function() {
        if (egCore.env.citm)
            return $q.when(egCore.env.citm.list);

        return egCore.pcrud.retrieveAll('citm', {}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'citm');
                return list;
            }
        );

    };

    service.get_age_protects = function() {
        if (egCore.env.crahp)
            return $q.when(egCore.env.crahp.list);

        return egCore.pcrud.retrieveAll('crahp', {}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'crahp');
                return list;
            }
        );

    };

    service.get_floating_groups = function() {
        if (egCore.env.cfg)
            return $q.when(egCore.env.cfg.list);

        return egCore.pcrud.retrieveAll('cfg', {}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'cfg');
                return list;
            }
        );

    };

    service.bmp_parts = {};
    var _bmp_chain = $q.when(); // use a promise chain to serialize
                                // the requests
    service.get_parts = function(rec) {
        if (service.bmp_parts[rec])
            return $q.when(service.bmp_parts[rec]);

        var deferred = $q.defer();
        _bmp_chain = _bmp_chain.then(function() {
            return egCore.pcrud.search('bmp',
                {record : rec, deleted : 'f'},
                {order_by: {bmp : 'label_sortkey DESC'}},
                {atomic : true}
            ).then(function(list) {
                service.bmp_parts[rec] = list;
                deferred.resolve(list);
            });
        });
        return deferred.promise;
    };

    service.get_acp_templates = function() {
        // Already downloaded for this user? Return local copy. Changing users or logging out causes another download
        // so users always have their own templates, and any changes made on other machines appear as expected.
        if (egCore.hatch.getSessionItem('cat.copy.templates.usr') == egCore.auth.user().id()) {
            return egCore.hatch.getItem('cat.copy.templates').then(function(templ) {
                return templ;
            });
        } else {
            // this can be disabled for debugging to force a re-download and translation of test templates
            egCore.hatch.setSessionItem('cat.copy.templates.usr', egCore.auth.user().id());
            return service.load_remote_acp_templates();
        }

    };

    service.save_acp_templates = function(t) {
        egCore.hatch.setItem('cat.copy.templates', t);
        egCore.net.request('open-ils.actor', 'open-ils.actor.patron.settings.update',
            egCore.auth.token(), egCore.auth.user().id(), { "cat.copy.templates": t });
        // console.warn('Saved ' + JSON.stringify({"cat.copy.templates": t}));
    };

    service.load_remote_acp_templates = function() {
        // After the XUL Client is completely removed everything related
        // to staff_client.copy_editor.templates and convert_xul_templates
        // can be thrown away.
        return egCore.net.request('open-ils.actor', 'open-ils.actor.patron.settings.retrieve.authoritative',
            egCore.auth.token(), egCore.auth.user().id(),
            ['cat.copy.templates','staff_client.copy_editor.templates']).then(function(settings) {
                if (settings['cat.copy.templates']) {
                    egCore.hatch.setItem('cat.copy.templates', settings['cat.copy.templates']);
                    return settings['cat.copy.templates'];
                } else {
                    if (settings['staff_client.copy_editor.templates']) {
                        var new_templ = service.convert_xul_templates(settings['staff_client.copy_editor.templates']);
                        egCore.hatch.setItem('cat.copy.templates', new_templ);
                        // console.warn('Saving: ' + JSON.stringify({'cat.copy.templates' : new_templ}));
                        egCore.net.request('open-ils.actor', 'open-ils.actor.patron.settings.update',
                            egCore.auth.token(), egCore.auth.user().id(), {'cat.copy.templates' : new_templ});
                        return new_templ;
                    }
                }
                return {};
        });
    };

    service.convert_xul_templates = function(xultempl) {
        var conv_templ = {};
        var templ_names = Object.keys(xultempl);
        var name;
        var xul_t;
        var curr_templ;
        var stat_cats;
        var fields;
        var curr_field;
        var tmp_val;
        var i, j;

        if (templ_names) {
            for (i=0; i < templ_names.length; i++) {
                name = templ_names[i];
                curr_templ = {};
                stat_cats = {};
                xul_t  = xultempl[name];
                fields = Object.keys(xul_t);

                if (fields.length > 0) {
                    for (j=0; j < fields.length; j++) {
                        curr_field = xul_t[fields[j]];
                        var field_name = curr_field["field"];

                        if ( field_name == null ) { continue; }
                        if ( curr_field["value"] == "<HACK:KLUDGE:NULL>" ) { continue; }

                        // floating changed from a boolean to an integer at one point;
                        // take this opportunity to remove the boolean from any old templates
                        if ( curr_field["type"] === "attribute" && field_name === "floating" ) {
                            if ( curr_field["value"].match(/[tf]/) ) { continue; }
                        }

                        if ( curr_field["type"] === "stat_cat" ) {
                            stat_cats[field_name] = parseInt(curr_field["value"]);
                        } else {
                            tmp_val = curr_field['value'];
                            if ( tmp_val.toString().match(/^[-0-9.]+$/)) {
                                tmp_val = parseFloat(tmp_val);
                            }

                            if (field_name.match(/^batch_.*_menulist$/)) {
                                // special handling for volume fields
                                if (!("callnumber" in curr_templ)) curr_templ["callnumber"] = {};
                                if (field_name === "batch_class_menulist")  curr_templ["callnumber"]["classification"] = tmp_val;
                                if (field_name === "batch_prefix_menulist") curr_templ["callnumber"]["prefix"] = tmp_val;
                                if (field_name === "batch_suffix_menulist") curr_templ["callnumber"]["suffix"] = tmp_val;
                            } else {
                                curr_templ[field_name] = tmp_val;
                            }
                        }
                    }

                    if ( (Object.keys(stat_cats)).length > 0 ) {
                        curr_templ["statcats"] = stat_cats;
                    }

                    conv_templ[name] = curr_templ;
                }
            }
        }
        return conv_templ;
    };

    service.flesh = {   
        flesh : 3, 
        flesh_fields : {
            acp : ['call_number','parts','stat_cat_entries', 'notes', 'tags', 'creator', 'editor', 'copy_alerts'],
            acn : ['label_class','prefix','suffix'],
            acptcm : ['tag'],
            aca : ['alert_type']
        }
    }

    service.addCopy = function (cp) {

        if (!cp.parts()) cp.parts([]); // just in case...

        var lib = cp.call_number().owning_lib();
        var cn = cp.call_number().id();

        if (!service.tree[lib]) service.tree[lib] = {};
        if (!service.tree[lib][cn]) service.tree[lib][cn] = [];

        service.tree[lib][cn].push(cp);
        service.copies.push(cp);
    }

    service.checkDuplicateBarcode = function(bc, id) {
        var final = false;
        return egCore.pcrud.search('acp', { deleted : 'f', 'barcode' : bc, id : { '!=' : id } })
            .then(
                function () { return final },
                function () { return final },
                function () { final = true; }
            );
    }

    service.fetchIds = function(idList) {
        service.tree = {}; // clear the tree on fetch
        service.copies = []; // clear the copy list on fetch
        return egCore.pcrud.search('acp', { 'id' : idList }, service.flesh).then(null,null,
            function(copy) {
                service.addCopy(copy);
            }
        );
    }

    // create a new acp object with default values
    // (both hard-coded and coming from OU settings)
    service.generateNewCopy =
        function(callNumber, owningLib, isFastAdd, isNew, delayCopyStatus) {

        var cp = new egCore.idl.acp();
        cp.id( --service.new_cp_id );
        if (isNew) {
            cp.isnew( true );
        }
        cp.circ_lib( owningLib );
        cp.call_number( callNumber );
        cp.deposit(0);
        cp.price(0);
        cp.deposit_amount(0);
        cp.fine_level(2); // Normal
        cp.loan_duration(2); // Normal
        cp.location(1); // Stacks
        cp.circulate('t');
        cp.holdable('t');
        cp.opac_visible('t');
        cp.ref('f');
        cp.mint_condition('t');
        cp.empty_barcode = true;

        if (delayCopyStatus) { return cp; }

        service.applyDefaultStatus([cp], isFastAdd);

        return cp;
    }

    // Apply the default copy status to a batch of copies
    service.applyDefaultStatus = function(copies, isFastAdd) {

        var setting = isFastAdd ?
            'cat.default_copy_status_fast' :
            'cat.default_copy_status_normal';

        var orgs = {};
        copies.forEach(function(copy) { orgs[copy.circ_lib()] = 1; });

        var promise = $q.when();

        // Fetch needed org settings; serialized
        // Note in practice this is always one org unit since
        // batches of copies are added to a single volume at a time.
        Object.keys(orgs).forEach(function(org) {
            promise = promise.then(function() {
                return egCore.org.settings(setting, org)
                .then(function(sets) {
                    var stat = sets[setting] || (isFastAdd ? 0 : 5);
                    orgs[org] = stat;
                });
            })
        });

        // All needed org settings retrieved.
        // Appply values to matching copies
        promise.then(function() {
            Object.keys(orgs).forEach(function(org) {

                var someCopies = copies.filter(function(copy) {
                    return copy.circ_lib() == org});

                someCopies.forEach(function(copy) { copy.status(orgs[org]); });
            });
        });

        return promise;
    }

    return service;
}])

.directive("egVolCopyEdit", ['egCore', function (egCore) {
    return {
        restrict: 'E',
        replace: true,
        template:
            '<div class="row" ng-class="{'+"'new-cp'"+':is_new}">'+
                '<span ng-if="is_new" class="sr-only">' + egCore.strings.VOL_COPY_NEW_ITEM + '</span>' +
                '<div class="col-xs-5" ng-class="{'+"'has-error'"+':barcode_has_error}">'+
                    '<input id="{{callNumber.id()}}_{{copy.id()}}"'+
                    ' eg-enter="nextBarcode(copy.id())" class="form-control"'+
                    ' type="text" ng-model="barcode" ng-model-options="{ debounce: 500 }" ng-change="updateBarcode()"'+
                    ' ng-focus="selectOnFocus($event)" autofocus/>'+
                    '<div class="label label-danger" ng-if="duplicate_barcode">{{duplicate_barcode_string}}</div>'+
                    '<div class="label label-danger" ng-if="empty_barcode">{{empty_barcode_string}}</div>'+
                '</div>'+
                '<div class="col-xs-3"><input class="form-control" type="number" min="1" ng-model="copy_number" ng-change="updateCopyNo()"/></div>'+
                '<div class="col-xs-3"><eg-basic-combo-box list="parts" selected="part"></eg-basic-combo-box></div>'+
            '</div>',

        scope: { focusNext: "=", copy: "=", callNumber: "=", index: "@", record: "@" },
        controller : ['$scope','itemSvc','egCore',
            function ( $scope , itemSvc , egCore ) {
                $scope.new_part_id = 0;
                $scope.barcode_has_error = false;
                $scope.duplicate_barcode = false;
                $scope.empty_barcode = false;
                $scope.is_new = false;
                $scope.duplicate_barcode_string = window.duplicate_barcode_string;
                $scope.empty_barcode_string = window.empty_barcode_string;
                var duplicate_check_count = 0;

                if (!$scope.copy.barcode()) $scope.copy.empty_barcode = true;
                if ($scope.copy.isnew() || $scope.copy.id() < 0) $scope.copy.is_new = $scope.is_new = true;

                $scope.selectOnFocus = function($event) {
                    if (!$scope.copy.empty_barcode)
                        $event.target.select();
                }

                $scope.nextBarcode = function (i) {
                    $scope.focusNext(i, $scope.barcode);
                }

                $scope.updateBarcode = function () {
                    if ($scope.barcode != '') {
                        $scope.copy.empty_barcode = $scope.empty_barcode = false;
                        $scope.barcode_has_error = !Boolean(itemSvc.checkBarcode($scope.barcode));

                        var duplicate_check_id = ++duplicate_check_count;
                        itemSvc.checkDuplicateBarcode($scope.barcode, $scope.copy.id())
                            .then(function (state) {
                                if (duplicate_check_id == duplicate_check_count)
                                    $scope.copy.duplicate_barcode = $scope.duplicate_barcode = state;
                            });
                    } else {
                        $scope.copy.empty_barcode = $scope.empty_barcode = true;
                    }
                        
                    $scope.copy.barcode($scope.barcode);
                    $scope.copy.ischanged(1);
                    if (itemSvc.currently_generating)
                        $scope.focusNext($scope.copy.id(), $scope.barcode);
                };

                $scope.updateCopyNo = function () { $scope.copy.copy_number($scope.copy_number); $scope.copy.ischanged(1); };
                $scope.updatePart = function () {
                    if ($scope.part) {
                        var p = $scope.part_list.filter(function (x) {
                            return x.label() == $scope.part
                        });
                        if (p.length > 0) { // preexisting part
                            $scope.copy.parts(p)
                        } else { // create one...
                            var part = new egCore.idl.bmp();
                            part.id( --$scope.new_part_id );
                            part.isnew( true );
                            part.label( $scope.part );
                            part.record( $scope.callNumber.record() );
                            $scope.copy.parts([part]);
                            $scope.copy.ischanged(1);
                        }
                    } else {
                        $scope.copy.parts([]);
                    }
                    $scope.copy.ischanged(1);
                }

                $scope.parts = [];
                $scope.part_list = [];

                itemSvc.get_parts($scope.callNumber.record())
                .then(function(list){
                    $scope.part_list = list;
                    angular.forEach(list, function(p){ $scope.parts.push(p.label()) });
                    $scope.parts = angular.copy($scope.parts);
                
                    $scope.$watch('part', $scope.updatePart);
                    if ($scope.copy.parts()) {
                        var the_part = $scope.copy.parts()[0];
                        if (the_part) $scope.part = the_part.label();
                    };
                });

                $scope.barcode = $scope.copy.barcode();
                $scope.copy_number = $scope.copy.copy_number();

            }
        ]

    }
}])

.directive("egVolRow", ['egCore', function (egCore) {
    return {
        restrict: 'E',
        replace: true,
        transclude: true,
        template:
            '<div class="row" ng-class="{'+"'new-cn'"+':!callNumber.not_ephemeral}">'+
                '<span ng-if="!callNumber.not_ephemeral" class="sr-only">' + egCore.strings.VOL_COPY_NEW_CALL_NUMBER + '</span>' +
                '<div class="col-xs-2">'+
                    '<button aria-label="Delete" style="margin:-5px -15px; float:left;" ng-hide="callNumber.not_ephemeral" type="button" class="close" ng-click="removeCN()">&times;</button>' +
                    '<select class="form-control" ng-model="classification" ng-change="updateClassification()" ng-options="cl.name() for cl in classification_list"></select>'+
                '</div>'+
                '<div class="col-xs-1">'+
                    '<select class="form-control" ng-model="prefix" ng-change="updatePrefix()" ng-options="p.label() for p in prefix_list"></select>'+
                '</div>'+
                '<div class="col-xs-2">'+
                    '<input class="form-control" type="text" ng-change="updateLabel()" ng-model="label"/>'+
                    '<div class="label label-danger" ng-if="empty_label && require_label">{{empty_label_string}}</div>'+
                '</div>'+
                '<div class="col-xs-1">'+
                    '<select class="form-control" ng-model="suffix" ng-change="updateSuffix()" ng-options="s.label() for s in suffix_list"></select>'+
                '</div>'+
                '<div ng-hide="onlyVols" class="col-xs-1"><input class="form-control" type="number" ng-model="copy_count" min="{{orig_copy_count}}" ng-change="changeCPCount()"></div>'+
                '<div ng-hide="onlyVols" class="col-xs-5">'+
                    '<eg-vol-copy-edit record="{{record}}" ng-repeat="cp in copies track by idTracker(cp)" focus-next="focusNextBarcode" copy="cp" call-number="callNumber"></eg-vol-copy-edit>'+
                '</div>'+
            '</div>',

        scope: {focusNext: "=", allcopies: "=", copies: "=", onlyVols: "=", record: "@", struct:"=" },
        controller : ['$scope','itemSvc','egCore',
            function ( $scope , itemSvc , egCore ) {
                $scope.callNumber =  $scope.copies[0].call_number();
                if (!$scope.callNumber.label()) $scope.callNumber.empty_label = true;

                $scope.empty_label = false;
                egCore.org.settings('cat.require_call_number_labels').then(function(res) {
                    $scope.require_label = res['cat.require_call_number_labels'];
                });
                $scope.empty_label_string = window.empty_label_string;

                $scope.idTracker = function (x) { if (x && x.id) return x.id() };

                // XXX $() is not working! arg
                $scope.focusNextBarcode = function (i, prev_bc) {
                    var n;
                    var yep = false;
                    angular.forEach($scope.copies, function (cp) {
                        if (n) return;

                        if (cp.id() == i) {
                            yep = true;
                            return;
                        }

                        if (yep) n = cp.id();
                    });

                    if (n) {
                        var next = '#' + $scope.callNumber.id() + '_' + n;
                        var el = $(next);
                        if (el) {
                            if (!itemSvc.currently_generating) el.focus();
                            if (prev_bc && itemSvc.auto_gen_barcode && el.val() == "") {
                                itemSvc.nextBarcode(prev_bc).then(function(bc){
                                    el.focus();
                                    el.val(bc);
                                    el.trigger('change');
                                });
                            } else {
                                itemSvc.currently_generating = false;
                            }
                        }
                    } else {
                        $scope.focusNext($scope.callNumber.id(),prev_bc)
                    }
                }

                $scope.suffix_list = [];
                itemSvc.get_suffixes($scope.callNumber.owning_lib()).then(function(list){
                    $scope.suffix_list = list;
                    $scope.$watch('callNumber.suffix()', function (v) {
                        if (angular.isObject(v)) v = v.id();
                        $scope.suffix = $scope.suffix_list.filter( function (s) {
                            return s.id() == v;
                        })[0];
                    });

                });
                $scope.updateSuffix = function () {
                    angular.forEach($scope.copies, function(cp) {
                        cp.call_number().suffix($scope.suffix);
                        cp.call_number().ischanged(1);
                    });
                }

                $scope.prefix_list = [];
                itemSvc.get_prefixes($scope.callNumber.owning_lib()).then(function(list){
                    $scope.prefix_list = list;
                    $scope.$watch('callNumber.prefix()', function (v) {
                        if (angular.isObject(v)) v = v.id();
                        $scope.prefix = $scope.prefix_list.filter(function (p) {
                            return p.id() == v;
                        })[0];
                    });

                });
                $scope.updatePrefix = function () {
                    angular.forEach($scope.copies, function(cp) {
                        cp.call_number().prefix($scope.prefix);
                        cp.call_number().ischanged(1);
                    });
                }
                $scope.$watch('callNumber.owning_lib()', function(oldLib, newLib) {
                    if (oldLib == newLib) return;
                    var currentPrefix = $scope.callNumber.prefix();
                    if (angular.isObject(currentPrefix)) currentPrefix = currentPrefix.id();
                    itemSvc.get_prefixes($scope.callNumber.owning_lib()).then(function(list){
                        $scope.prefix_list = list;
                        var newPrefixId = $scope.prefix_list.filter(function (p) {
                            return p.id() == currentPrefix;
                        })[0] || -1;
                        if (newPrefixId.id) newPrefixId = newPrefixId.id();
                        $scope.prefix = $scope.prefix_list.filter(function (p) {
                            return p.id() == newPrefixId;
                        })[0];
                        if ($scope.newPrefixId != currentPrefix) {
                            $scope.callNumber.prefix($scope.prefix);
                        }
                    });
                    var currentSuffix = $scope.callNumber.suffix();
                    if (angular.isObject(currentSuffix)) currentSuffix = currentSuffix.id();
                    itemSvc.get_suffixes($scope.callNumber.owning_lib()).then(function(list){
                        $scope.suffix_list = list;
                        var newSuffixId = $scope.suffix_list.filter(function (s) {
                            return s.id() == currentSuffix;
                        })[0] || -1;
                        if (newSuffixId.id) newSuffixId = newSuffixId.id();
                        $scope.suffix = $scope.suffix_list.filter(function (s) {
                            return s.id() == newSuffixId;
                        })[0];
                        if ($scope.newSuffixId != currentSuffix) {
                            $scope.callNumber.suffix($scope.suffix);
                        }
                    });
                });

                $scope.classification_list = [];
                itemSvc.get_classifications().then(function(list){
                    $scope.classification_list = list;
                    $scope.$watch('callNumber.label_class()', function (v) {
                        if (angular.isObject(v)) v = v.id();
                        $scope.classification = $scope.classification_list.filter(function (c) {
                            return c.id() == v;
                        })[0];
                    });

                });
                $scope.updateClassification = function () {
                    angular.forEach($scope.copies, function(cp) {
                        cp.call_number().label_class($scope.classification);
                        cp.call_number().ischanged(1);
                    });
                }

                $scope.updateLabel = function () {
                    angular.forEach($scope.copies, function(cp) {
                        cp.call_number().label($scope.label);
                        cp.call_number().ischanged(1);
                    });
                }

                $scope.$watch('callNumber.label()', function (v) {
                    $scope.label = v;
                    if ($scope.label == '') {
                        $scope.callNumber.empty_label = $scope.empty_label = true;
                    } else {
                        $scope.callNumber.empty_label = $scope.empty_label = false;
                    }
                });

                $scope.prefix = $scope.callNumber.prefix();
                $scope.suffix = $scope.callNumber.suffix();
                $scope.classification = $scope.callNumber.label_class();

		// If no call number label, set to empty string to avoid merging problem
		if ($scope.callNumber.label() == null) {
			$scope.callNumber.label('');
		}
                $scope.label = $scope.callNumber.label();

                $scope.copy_count = $scope.copies.length;
                $scope.orig_copy_count = $scope.copy_count;

                $scope.removeCN = function(){
                    var cn = $scope.callNumber;
                    if (cn.not_ephemeral) return;  // can't delete existing volumes

                    angular.forEach(Object.keys($scope.struct), function(k){
                        angular.forEach($scope.struct[k], function(cp){
                            var struct_cn = cp.call_number();
                            if (struct_cn.id() == cn.id()){
                                console.log("X'ed CN id" + cn.id() + " and struct CN id match!");
                                // remove any copies in $scope.struct[k]
                                angular.forEach($scope.copies, function(c){
                                    var idx = $scope.allcopies.indexOf(c);
                                    $scope.allcopies.splice(idx, 1);
                                });

                                $scope.copies = [];
                                // remove added vol:
                                delete $scope.struct[k];
                            }
                        });
                    });

                    // manually decrease cn_count numeric input
                    var cn_spinner = $("input[name='cn_count_lib"+ cn.owning_lib() +"']");
                    if (cn_spinner.val() > 0) cn_spinner.val(parseInt(cn_spinner.val()) - 1);
                    cn_spinner.trigger("change");

                }

                $scope.changeCPCount = function () {
                    var newCopies = [];
                    while ($scope.copy_count > $scope.copies.length) {
                        var cp = itemSvc.generateNewCopy(
                            $scope.callNumber,
                            $scope.callNumber.owning_lib(),
                            $scope.fast_add,
                            true, true
                        );
                        $scope.copies.push( cp );
                        $scope.allcopies.push( cp );
                        newCopies.push(cp);
                    }

                    itemSvc.applyDefaultStatus(newCopies, $scope.fast_add);

                    if ($scope.copy_count >= $scope.orig_copy_count) {
                        var how_many = $scope.copies.length - $scope.copy_count;
                        if (how_many > 0) {
                            var dead = $scope.copies.splice($scope.copy_count,how_many);
                            $scope.callNumber.copies($scope.copies);

                            // Trimming the global list is a bit more tricky
                            angular.forEach( dead, function (d) {
                                angular.forEach( $scope.allcopies, function (l, i) { 
                                    if (l === d) $scope.allcopies.splice(i,1);
                                });
                            });
                        }
                    }
                }

            }
        ]

    }
}])

.directive("egVolEdit", function () {
    return {
        restrict: 'E',
        replace: true,
        template:
            '<div class="row">'+
                '<div class="col-xs-1"><eg-org-selector selected="owning_lib" disable-test="cant_have_vols"></eg-org-selector></div>'+
                '<div class="col-xs-1"><input class="form-control" type="number" min="{{orig_cn_count}}" ng-model="cn_count" ng-change="changeCNCount()"/></div>'+
                '<div class="col-xs-10">'+
                    '<eg-vol-row only-vols="onlyVols" record="{{record}}"'+
                        'ng-repeat="(cn,copies) in struct" '+
                        'focus-next="focusNextFirst" copies="copies" allcopies="allcopies" struct="struct">'+
                    '</eg-vol-row>'+
                '</div>'+
            '</div>',

        scope: { focusNext: "=", allcopies: "=", struct: "=", lib: "@", record: "@", onlyVols: "=" },
        controller : ['$scope','itemSvc','egCore',
            function ( $scope , itemSvc , egCore ) {
                $scope.first_cn = Object.keys($scope.struct)[0];
                $scope.full_cn = $scope.struct[$scope.first_cn][0].call_number();

                $scope.defaults = {};
                egCore.hatch.getItem('cat.copy.defaults').then(function(t) {
                    if (t) {
                        $scope.defaults = t;
                    }
                });

                $scope.focusNextFirst = function(prev_cn,prev_bc) {
                    var n;
                    var yep = false;
                    angular.forEach(Object.keys($scope.struct).sort(), function (cn) {
                        if (n) return;

                        if (cn == prev_cn) {
                            yep = true;
                            return;
                        }

                        if (yep) n = cn;
                    });

                    if (n) {
                        var next = '#' + n + '_' + $scope.struct[n][0].id();
                        var el = $(next);
                        if (el) {
                            if (!itemSvc.currently_generating) el.focus();
                            if (prev_bc && itemSvc.auto_gen_barcode && el.val() == "") {
                                itemSvc.nextBarcode(prev_bc).then(function(bc){
                                    el.focus();
                                    el.val(bc);
                                    el.trigger('change');
                                });
                            } else {
                                itemSvc.currently_generating = false;
                            }
                        }
                    } else {
                        $scope.focusNext($scope.lib, prev_bc);
                    }
                }

                $scope.cn_count = Object.keys($scope.struct).length;
                $scope.orig_cn_count = $scope.cn_count;

                $scope.owning_lib = egCore.org.get($scope.lib);
                $scope.$watch('owning_lib', function (oldLib, newLib) {
                    if (oldLib == newLib) return;
                    angular.forEach( Object.keys($scope.struct), function (cn) {
                        $scope.struct[cn][0].call_number().owning_lib( $scope.owning_lib.id() );
                        $scope.struct[cn][0].call_number().ischanged(1);
                    });
                });

                $scope.cant_have_vols = function (id) { return !egCore.org.CanHaveVolumes(id); };

                $scope.$watch('cn_count', function (n) {
                    var o = Object.keys($scope.struct).length;
                    if (n > o) { // adding
                        var newCopies = [];
                        for (var i = o; o < n; o++) {
                            var cn = new egCore.idl.acn();
                            cn.id( --itemSvc.new_cn_id );
                            cn.isnew( true );
                            cn.prefix( $scope.defaults.prefix || -1 );
                            cn.suffix( $scope.defaults.suffix || -1 );
                            cn.label_class( $scope.defaults.classification || 1 );
                            cn.owning_lib( $scope.owning_lib.id() );
                            cn.record( $scope.full_cn.record() );

                            var cp = itemSvc.generateNewCopy(
                                cn,
                                $scope.owning_lib.id(),
                                $scope.fast_add,
                                true, true
                            );

                            newCopies.push(cp);
                            $scope.struct[cn.id()] = [cp];
                            $scope.allcopies.push(cp);
                            if (!$scope.defaults.classification) {
                                egCore.org.settings(
                                    ['cat.default_classification_scheme'],
                                    cn.owning_lib()
                                ).then(function (val) {
                                    cn.label_class(val['cat.default_classification_scheme']);
                                });
                            }
                        }

                        itemSvc.applyDefaultStatus(newCopies, $scope.fast_add);

                    } else if (n < o && n >= $scope.orig_cn_count) { // removing
                        var how_many = o - n;
                        var list = Object
                                .keys($scope.struct)
                                .sort(function(a, b){return parseInt(a)-parseInt(b)})
                                .filter(function(x){ return parseInt(x) <= 0 });
                        for (var i = 0; i < how_many; i++) {
                            // Trimming the global list is a bit more tricky
                            angular.forEach($scope.struct[list[i]], function (d) {
                                angular.forEach( $scope.allcopies, function (l, j) { 
                                    if (l === d) $scope.allcopies.splice(j,1);
                                });
                            });
                            delete $scope.struct[list[i]];
                        }
                    }
                });
            }
        ]

    }
})

/**
 * Edit controller!
 */
.controller('EditCtrl', 
       ['$scope','$q','$window','$routeParams','$location','$timeout','egCore','egNet','egGridDataProvider','itemSvc','$uibModal',
function($scope , $q , $window , $routeParams , $location , $timeout , egCore , egNet , egGridDataProvider , itemSvc , $uibModal) {

    $scope.forms = {}; // Accessed by t_attr_edit.tt2
    $scope.i18n = egCore.i18n;

    $scope.defaults = { // If defaults are not set at all, allow everything
        barcode_checkdigit : false,
        auto_gen_barcode : false,
        statcats : true,
        copy_notes : true,
        copy_tags : true,
        attributes : {
            status : true,
            loan_duration : true,
            fine_level : true,
            cost : true,
            alerts : true,
            deposit : true,
            deposit_amount : true,
            opac_visible : true,
            price : true,
            circulate : true,
            mint_condition : true,
            circ_lib : true,
            ref : true,
            circ_modifier : true,
            circ_as_type : true,
            location : true,
            holdable : true,
            age_protect : true,
            floating : true,
            alerts : true
        }
    };

    egCore.org.settings('cat.require_call_number_labels').then(function(res) {
        $scope.require_label = res['cat.require_call_number_labels'];
    });

    $scope.new_lib_to_add = egCore.org.get(egCore.auth.user().ws_ou());
    $scope.changeNewLib = function (org) {
        $scope.new_lib_to_add = org;
    }
    $scope.addLibToStruct = function () {
        var newLib = $scope.new_lib_to_add;
        var cn = new egCore.idl.acn();
        cn.id( --itemSvc.new_cn_id );
        cn.isnew( true );
        cn.prefix( $scope.defaults.prefix || -1 );
        cn.suffix( $scope.defaults.suffix || -1 );
        cn.label_class( $scope.defaults.classification || 1 );
        cn.owning_lib( newLib.id() );
        cn.record( $scope.record_id );

        var cp = itemSvc.generateNewCopy(
            cn,
            newLib.id(),
            $scope.fast_add,
            true
        );

        $scope.data.addCopy(cp);

        // manually increase cn_count numeric input
        var cn_spinner = $("input[name='cn_count_lib"+ newLib.id() +"']");
        cn_spinner.val(parseInt(cn_spinner.val()) + 1);
        cn_spinner.trigger("change");

        if (!$scope.defaults.classification) {
            egCore.org.settings(
                ['cat.default_classification_scheme'],
                cn.owning_lib()
            ).then(function (val) {
                cn.label_class(val['cat.default_classification_scheme']);
            });
        }
    }

    $scope.embedded = ($routeParams.mode && $routeParams.mode == 'embedded') ? true : false;
    $scope.edit_templates = ($location.path().match(/edit_template/)) ? true : false;

    $scope.saveDefaults = function () {
        egCore.hatch.setItem('cat.copy.defaults', $scope.defaults);
    }

    $scope.fetchDefaults = function () {
        egCore.hatch.getItem('cat.copy.defaults').then(function(t) {
            if (t) {
                $scope.defaults = t;
                if (!$scope.batch) $scope.batch = {};
                $scope.batch.classification = $scope.defaults.classification;
                $scope.batch.prefix = $scope.defaults.prefix;
                $scope.batch.suffix = $scope.defaults.suffix;
                $scope.working.statcat_filter = $scope.defaults.statcat_filter;
                if (
                        typeof $scope.defaults.statcat_filter == 'object' &&
                        Object.keys($scope.defaults.statcat_filter).length > 0
                   ) {
                    // want fieldmapper object here...
                    $scope.defaults.statcat_filter =
                         egCore.idl.Clone($scope.defaults.statcat_filter);
                    // ... and ID here
                    $scope.working.statcat_filter = $scope.defaults.statcat_filter.id();
                }
                if ($scope.defaults.always_volumes) $scope.show_vols = true;
                if ($scope.defaults.barcode_checkdigit) itemSvc.barcode_checkdigit = true;
                if ($scope.defaults.auto_gen_barcode) itemSvc.auto_gen_barcode = true;
            }

            // Fetch the list of bib-level callnumbers based on the applied
            // classification scheme.  If none is defined, default to "1"
            // (Generic) since it provides the most options.
            egCore.net.request(
                'open-ils.cat',
                'open-ils.cat.biblio.record.marc_cn.retrieve',
                $scope.record_id,
                $scope.batch.classification || 1
            ).then(function(list) {
                $scope.batch.marcCallNumbers = [];
                list.forEach(function(hash) {
                    $scope.batch.marcCallNumbers.push(Object.values(hash)[0]);
                });
            });
        });
    }

    $scope.$watch('defaults.statcat_filter', function(n,o) {
        if (n && n != o)
            $scope.saveDefaults();
    });
    $scope.$watch('defaults.auto_gen_barcode', function (n,o) {
        itemSvc.auto_gen_barcode = n
    });

    $scope.$watch('defaults.barcode_checkdigit', function (n,o) {
        itemSvc.barcode_checkdigit = n
    });

    $scope.dirty = false;
    $scope.$watch('dirty',
        function(newVal, oldVal) {
            if (newVal && newVal != oldVal) {
                $($window).on('beforeunload.edit', function(){
                    return 'There is unsaved data!'
                });
            } else {
                $($window).off('beforeunload.edit');
            }
        }
    );

    $scope.only_vols = false;
    $scope.show_vols = true;
    $scope.show_copies = true;

    $scope.tracker = function (x,f) { if (x) return x[f]() };
    $scope.idTracker = function (x) { if (x) return $scope.tracker(x,'id') };
    $scope.cant_have_vols = function (id) { return !egCore.org.CanHaveVolumes(id); };

    $scope.orgById = function (id) { return egCore.org.get(id) }
    $scope.statusById = function (id) {
        return $scope.status_list.filter( function (s) { return s.id() == id } )[0];
    }
    $scope.locationById = function (id) {
        return $scope.location_cache[''+id];
    }

    $scope.workingToComplete = function () {
        angular.forEach( $scope.workingGridControls.selectedItems(), function (c) {
            angular.forEach( itemSvc.copies, function (w, i) {
                if (c === w)
                    $scope.completed_copies = $scope.completed_copies.concat(itemSvc.copies.splice(i,1));
            });
        });

        return true;
    }

    $scope.changed_fields = [];

    $scope.completeToWorking = function () {
        angular.forEach( $scope.completedGridControls.selectedItems(), function (c) {
            angular.forEach( $scope.completed_copies, function (w, i) {
                if (c === w)
                    itemSvc.copies = itemSvc.copies.concat($scope.completed_copies.splice(i,1));
            });
        });

        return true;
    }

    createSimpleUpdateWatcher = function (field,exclude_copies_with_one_of_these_values) {
        return $scope.$watch('working.' + field, function () {
            var newval = $scope.working[field];

            if (typeof newval != 'undefined') {
                delete $scope.working.MultiMap[field];
                if (angular.isObject(newval)) { // we'll use the pkey
                    if (newval.id) newval = newval.id();
                    else if (newval.code) newval = newval.code();
                }

                if (""+newval == "" || newval == null) {
                    $scope.working[field] = undefined;
                    newval = null;
                }

                if ($scope.workingGridControls && $scope.workingGridControls.selectedItems) {
                    angular.forEach(
                        $scope.workingGridControls.selectedItems(),
                        function (cp) {
                            if (exclude_copies_with_one_of_these_values
                                && exclude_copies_with_one_of_these_values.indexOf(cp[field](),0) > -1) {
                                return;
                            }
                            if (cp[field]() !== newval) {
                                $scope.changed_fields[cp.$$hashKey+field] = true;
                                cp[field](newval);
                                cp.ischanged(1);
                                $scope.dirty = true;
                            }
                        }
                    );
                }
            }
        });
    }

    // determine if any of the selected copies have had changed their value for this field:
    $scope.field_changed = function (field){
        // if objects controlling selection don't exist, assume the fields haven't changed
        if(!$scope.workingGridControls || !$scope.workingGridControls.selectedItems){ return false; }
        var selected = $scope.workingGridControls.selectedItems();
        return selected.reduce((acc, cp) => acc || $scope.changed_fields[cp.$$hashKey+field], false);
    };

    $scope.working = {
        MultiMap: {},
        statcats: {},
        statcats_multi: {},
        statcat_filter: undefined
    };

    // Returns true if we are editing multiple copies and at least
    // one field contains multiple values.
    $scope.hasMulti = function() {
        var keys = Object.keys($scope.working.MultiMap);
        // for-loop for shortcut exit
        for (var i = 0; i < keys.length; i++) {
            if ($scope.working.MultiMap[keys[i]] &&
                $scope.working.MultiMap[keys[i]].length > 1) {
                return true;
            }
        }
        return false;
    }

    $scope.copyAlertUpdate = function (alerts) {
        if (!$scope.in_item_select &&
            $scope.workingGridControls &&
            $scope.workingGridControls.selectedItems) {
            itemSvc.get_copy_alert_types().then(function(ccat) {
                var ccat_map = {};
                $scope.alert_types = ccat;
                angular.forEach(ccat, function(t) {
                    ccat_map[t.id()] = t;
                });
                angular.forEach(
                    $scope.workingGridControls.selectedItems(),
                    function (cp) {
                        if (!angular.isArray(cp.copy_alerts())) cp.copy_alerts([]);
                        $scope.dirty = true;
                        angular.forEach(alerts, function(alrt) {
                            var a = egCore.idl.fromHash('aca', alrt);
                            a.isnew(1);
                            a.create_staff(egCore.auth.user().id());
                            a.alert_type(ccat_map[a.alert_type()]);
                            a.ack_time(null);
                            a.copy(cp.id());
                            cp.copy_alerts().push( a );
                        });
                        cp.ischanged(1);
                    }
                );
            });
        }
    };

    $scope.copyNoteUpdate = function (notes) {
        if (!$scope.in_item_select &&
            $scope.workingGridControls &&
            $scope.workingGridControls.selectedItems) {
            angular.forEach(
                $scope.workingGridControls.selectedItems(),
                function (cp) {
                    if (!angular.isArray(cp.notes())) cp.notes([]);
                    $scope.dirty = true;
                    angular.forEach(notes, function(note) {
                        var n = egCore.idl.fromHash('acpn', note);
                        n.isnew(1);
                        n.creator(egCore.auth.user().id());
                        n.owning_copy(cp.id());
                        cp.notes().push( n );
                    });
                    cp.ischanged(1);
                }
            );

        }
    }

    $scope.statcatUpdate = function (id) {
        var newval = $scope.working.statcats[id];

        if (typeof newval != 'undefined') {
            if (angular.isObject(newval)) { // we'll use the pkey
                newval = newval.id();
            }
    
            if (""+newval == "" || newval == null) {
                $scope.working.statcats[id] = undefined;
                newval = null;
            }
    
            if (!$scope.in_item_select && $scope.workingGridControls && $scope.workingGridControls.selectedItems) {
                angular.forEach(
                    $scope.workingGridControls.selectedItems(),
                    function (cp) {
                        $scope.dirty = true;

                        cp.stat_cat_entries(
                            angular.forEach( cp.stat_cat_entries(), function (e) {
                                if (e.stat_cat() == id) { // mark deleted
                                    e.isdeleted(1);
                                }
                            })
                        );
    
                        if (newval) {
                            var e = new egCore.idl.asce();
                            e.isnew( 1 );
                            e.stat_cat( id );
                            e.id(newval);

                            cp.stat_cat_entries(
                                cp.stat_cat_entries() ?
                                    cp.stat_cat_entries().concat([ e ]) :
                                    [ e ]
                            );

                        }

                        // trim out all deleted ones; the API used to
                        // do the update doesn't actually consult
                        // isdeleted for stat cat entries
                        if (cp.stat_cat_entries()) {
                            cp.stat_cat_entries(
                                cp.stat_cat_entries().filter(function (e) {
                                    return !Boolean(e.isdeleted());
                                })
                            );
                        }
   
                        cp.ischanged(1);
                    }
                );
            }
        }
    }

    var dataKey = $routeParams.dataKey;
    console.debug('dataKey: ' + dataKey);

    if ((dataKey && dataKey.length > 0) || $scope.edit_templates) {

        $scope.templates = {};
        $scope.template_name = '';
        $scope.template_name_list = [];

        $scope.fetchTemplates = function () {
            itemSvc.get_acp_templates().then(function(t) {
                if (t) {
                    $scope.templates = t;
                    $scope.template_name_list = Object.keys(t).sort();
                }
            });
            egCore.hatch.getItem('cat.copy.last_template').then(function(t) {
                if (t) $scope.template_name = t;
            });
        }
        $scope.fetchTemplates();

        $scope.applyTemplate = function (n) {
            angular.forEach($scope.templates[n], function (v,k) {
                if (k == 'circ_lib') {
                    $scope.working[k] = egCore.org.get(v);
                } else if (k == 'copy_notes' && v.length) {
                    $scope.copyNoteUpdate(v);
                } else if (k == 'copy_alerts' && v.length) {
                    $scope.copyAlertUpdate(v);
                } else if (!angular.isObject(v)) {
                    $scope.working[k] = angular.copy(v);
                } else {
                    angular.forEach(v, function (sv,sk) {
                        if (k == 'callnumber') {
                            angular.forEach(v, function (cnv,cnk) {
                                $scope.batch[cnk] = cnv;
                            });
                            $scope.applyBatchCNValues();
                        } else {
                            $scope.working[k][sk] = angular.copy(sv);
                            if (k == 'statcats') $scope.statcatUpdate(sk);
                        }
                    });
                }
                delete $scope.working.MultiMap[k];
            });
            egCore.hatch.setItem('cat.copy.last_template', n);
        }

        $scope.copytab = 'working';
        $scope.tab = 'edit';
        $scope.summaryRecord = null;
        $scope.record_id = null;
        $scope.data = {};
        $scope.completed_copies = [];
        $scope.location_orgs = [];
        $scope.location_cache = {};
        $scope.statcats = [];
        if (!$scope.batch) $scope.batch = {};

        $scope.applyBatchCNValues = function () {
            if ($scope.data.tree) {
                angular.forEach($scope.data.tree, function(cn_hash) {
                    angular.forEach(cn_hash, function(copies) {
                        angular.forEach(copies, function(cp) {
                            if (typeof $scope.batch.classification != 'undefined' && $scope.batch.classification != '') {
                                var label_class = $scope.classification_list.filter(function(p){ return p.id() == $scope.batch.classification })[0];
                                cp.call_number().label_class(label_class);
                                cp.call_number().ischanged(1);
                                $scope.dirty = true;
                            }
                            if (typeof $scope.batch.prefix != 'undefined' && $scope.batch.prefix != '') {
                                var prefix = $scope.prefix_list.filter(function(p){ return p.id() == $scope.batch.prefix })[0];
                                cp.call_number().prefix(prefix);
                                cp.call_number().ischanged(1);
                                $scope.dirty = true;
                            }
                            if (typeof $scope.batch.label != 'undefined' && $scope.batch.label != '') {
                                cp.call_number().label($scope.batch.label);
                                cp.call_number().ischanged(1);
                                $scope.dirty = true;
                            }
                            if (typeof $scope.batch.suffix != 'undefined' && $scope.batch.suffix != '') {
                                var suffix = $scope.suffix_list.filter(function(p){ return p.id() == $scope.batch.suffix })[0];
                                cp.call_number().suffix(suffix);
                                cp.call_number().ischanged(1);
                                $scope.dirty = true;
                            }
                        });
                    });
                });
            }
        }

        $scope.clearWorking = function () {
            angular.forEach($scope.working, function (v,k,o) {
                if (k != 'MultiMap') $scope.working.MultiMap[k] = [];
                if (!angular.isObject(v)) {
                    if (typeof v != 'undefined')
                        $scope.working[k] = undefined;
                } else if (k != 'circ_lib' && k != 'MultiMap') {
                    angular.forEach(v, function (sv,sk) {
                        if (typeof v != 'undefined')
                            $scope.working[k][sk] = undefined;
                    });
                }
            });
            $scope.working.circ_lib = undefined; // special
        }

        $scope.completedGridDataProvider = egGridDataProvider.instance({
            get : function(offset, count) {
                //return provider.arrayNotifier(itemSvc.copies, offset, count);
                return this.arrayNotifier($scope.completed_copies, offset, count);
            }
        });

        $scope.completedGridControls = {};

        $scope.workingGridDataProvider = egGridDataProvider.instance({
            get : function(offset, count) {
                //return provider.arrayNotifier(itemSvc.copies, offset, count);
                return this.arrayNotifier(itemSvc.copies, offset, count);
            }
        });

        $scope.workingGridControls = {};
        $scope.add_vols_copies = false;
        $scope.is_fast_add = false;

        // Generate some functions for selecting items by column value in the working grid
        angular.forEach(
            ['circulate','status','circ_lib','ref','location','opac_visible','circ_modifier','price',
             'loan_duration','cost','circ_as_type','deposit','holdable','deposit_amount','age_protect',
             'mint_condition','fine_level','floating'],
            function (field) {
                $scope['select_by_' + field] = function (x) {
                    $scope.workingGridControls.selectItemsByValue(field,x);
                }
            }
        );

        var truthy = /^t|1/;
        $scope.labelYesNo = function (x) {
            return truthy.test(x) ? egCore.strings.YES : egCore.strings.NO;
        }

        $scope.orgShortname = function (x) {
            return egCore.org.get(x).shortname();
        }

        $scope.statusName = function (x) {
            var s = $scope.status_list.filter(function(y) {
                return y.id() == x;
            });

            return s[0] ? s[0].name() : '';
        }

        $scope.locationName = function (x) {
            var s = $scope.location_list.filter(function(y) {
                return y.id() == x;
            });

            return $scope.i18n.ou_qualified_location_name(s[0]);
        }

        $scope.durationLabel = function (x) {
            return [egCore.strings.SHORT, egCore.strings.NORMAL, egCore.strings.EXTENDED][-1 + x]
        }

        $scope.fineLabel = function (x) {
            return [egCore.strings.LOW, egCore.strings.NORMAL, egCore.strings.HIGH][-1 + x]
        }

        $scope.circTypeValue = function (x) {
            if (x === null || x === undefined) return egCore.strings.UNSET;
            var s = $scope.circ_type_list.filter(function(y) {
                return y.code() == x;
            });

            return s[0].value();
        }

        $scope.ageprotectName = function (x) {
            if (x === null || x === undefined) return egCore.strings.UNSET;
            var s = $scope.age_protect_list.filter(function(y) {
                return y.id() == x;
            });

            return s[0].name();
        }

        $scope.floatingName = function (x) {
            if (x === null || x === undefined) return egCore.strings.UNSET;
            var s = $scope.floating_list.filter(function(y) {
                return y.id() == x;
            });

            return s[0].name();
        }

        $scope.circmodName = function (x) {
            if (x === null || x === undefined) return egCore.strings.UNSET;
            var s = $scope.circ_modifier_list.filter(function(y) {
                return y.code() == x;
            });

            return s[0].name();
        }

        egNet.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.get_value',
            dataKey, 'edit-these-copies'
        ).then(function (data) {

            if (data) {
                if (data.hide_vols && !$scope.defaults.always_volumes) $scope.show_vols = false;
                if (data.hide_copies) {
                    $scope.show_copies = false;
                    $scope.only_vols = true;
                }

                $scope.record_id = data.record_id;

                // Fetch defaults 
                $scope.fetchDefaults();

                function fetchRaw () {
                    if (!$scope.only_vols) $scope.dirty = true;
                    $scope.add_vols_copies = true;

                    /* data.raw data structure looks like this:
                     * [{
                     *      callnumber : $cn_id, // optional, to add a copy to a cn
                     *      owner      : $org, // optional, defaults to cn.owning_lib or ws_ou
                     *      label      : $cn_label, // optional, to supply a label on a new cn
                     *      barcode    : $cp_barcode // optional, to supply a barcode on a new cp
                     *      fast_add   : boolean // optional, to specify whether this came
                     *                              in as a fast add
                     * },...]
                     * 
                     * All can be left out and a completely empty vol/copy combo will be vivicated.
                     */

                    var promises = [];
                    angular.forEach(
                        data.raw,
                        function (proto) {
                            if (proto.fast_add) $scope.is_fast_add = true;
                            if (proto.callnumber) {
                                promises.push(egCore.pcrud.retrieve('acn', proto.callnumber)
                                .then(function(cn) {
                                    var cp = new itemSvc.generateNewCopy(
                                        cn,
                                        proto.owner || cn.owning_lib(),
                                        $scope.is_fast_add,
                                        ((!$scope.only_vols) ? true : false)
                                    );

                                    if (proto.barcode) {
                                        cp.barcode( proto.barcode );
                                        cp.empty_barcode = false;
                                    }

                                    itemSvc.addCopy(cp)
                                }));
                            } else {
                                var cn = new egCore.idl.acn();
                                cn.id( --itemSvc.new_cn_id );
                                cn.isnew( true );
                                cn.prefix( $scope.defaults.prefix || -1 );
                                cn.suffix( $scope.defaults.suffix || -1 );
                                cn.owning_lib( proto.owner || egCore.auth.user().ws_ou() );
                                cn.record( $scope.record_id );
                                egCore.org.settings(
                                    ['cat.default_classification_scheme'],
                                    cn.owning_lib()
                                ).then(function (val) {
                                    cn.label_class(
                                        $scope.defaults.classification ||
                                        val['cat.default_classification_scheme'] ||
                                        1
                                    );
                                    if (proto.label) {
                                        cn.label( proto.label );
                                    } else {
                                        egCore.net.request(
                                            'open-ils.cat',
                                            'open-ils.cat.biblio.record.marc_cn.retrieve',
                                            $scope.record_id,
                                            cn.label_class()
                                        ).then(function(cn_array) {
                                            if (cn_array.length > 0) {
                                                for (var field in cn_array[0]) {
                                                    cn.label( cn_array[0][field] );
                                                    break;
                                                }
                                            }
                                        });
                                    }
                                });

                                // If we are adding an empty vol,
                                // this is ultimately just a placeholder copy
                                // which gets removed before saving.
                                // TODO: consider ways to remove this
                                // requirement
                                var cp = new itemSvc.generateNewCopy(
                                    cn,
                                    proto.owner || cn.owning_lib(),
                                    $scope.is_fast_add,
                                    true
                                );

                                if (proto.barcode) {
                                    cp.barcode( proto.barcode );
                                    cp.empty_barcode = false;
                                }

                                itemSvc.addCopy(cp)
                            }
                        }
                    );

                    angular.forEach(itemSvc.copies, function(c){
                        var cn = c.call_number();
                        var copy_id = c.id();
                        if (copy_id > 0){
                            cn.not_ephemeral = true;
                        }
                    });

                    return $q.all(promises);
                }

                if (data.copies && data.copies.length)
                    return itemSvc.fetchIds(data.copies).then(fetchRaw);

                return fetchRaw();

            }

        }).then( function() {

            return itemSvc.fetch_locations(
                itemSvc.copies.map(function(cp){
                    return cp.location();
                }).filter(function(e,i,a){
                    return a.lastIndexOf(e) === i;
                })
            ).then(function(list){
                $scope.data = itemSvc;
                $scope.location_list = list;
                $scope.workingGridDataProvider.refresh();
            });

        });

        $scope.can_save = false;
        function check_saveable () {
            var can_save = true;

            angular.forEach(
                itemSvc.copies,
                function (i) {
                    if (!$scope.only_vols) {
                        if (i.duplicate_barcode || i.empty_barcode) {
                            can_save = false;
                        }
                        if (i.call_number().empty_label && $scope.require_label) {
                            can_save = false;
                        }
                    } else if (i.call_number().empty_label && $scope.require_label) {
                        can_save = false;
                    }
                }
            );

            if (!$scope.only_vols && $scope.forms.myForm && $scope.forms.myForm.$invalid) {
                can_save = false;
            }

            $scope.can_save = can_save;
        }

        $scope.disableSave = function () {
            check_saveable();
            return !$scope.can_save;
        }

        $scope.focusNextFirst = function(prev_lib,prev_bc) {
            var n;
            var yep = false;
            angular.forEach(Object.keys($scope.data.tree).sort(), function (lib) {
                if (n) return;

                if (lib == prev_lib) {
                    yep = true;
                    return;
                }

                if (yep) n = lib;
            });

            if (n) {
                var first_cn = Object.keys($scope.data.tree[n])[0];
                var next = '#' + first_cn + '_' + $scope.data.tree[n][first_cn][0].id();
                var el = $(next);
                if (el) {
                    if (!itemSvc.currently_generating) el.focus();
                    if (prev_bc && itemSvc.auto_gen_barcode && el.val() == "") {
                        itemSvc.nextBarcode(prev_bc).then(function(bc){
                            el.focus();
                            el.val(bc);
                            el.trigger('change');
                        });
                    } else {
                        itemSvc.currently_generating = false;
                    }
                }
            }
        }

        $scope.in_item_select = false;
        $scope.afterItemSelect = function() { $scope.in_item_select = false };
        $scope.handleItemSelect = function (item_list) {
            if (item_list && item_list.length > 0) {
                $scope.in_item_select = true;

                angular.forEach(Object.keys($scope.defaults.attributes), function (attr) {

                    var value_hash = {};
                    var value_list = [];
                    angular.forEach(item_list, function (item) {
                        if (item[attr]) {
                            var v = item[attr]()
                            if (angular.isObject(v)) {
                                if (v.id) v = v.id();
                                else if (v.code) v = v.code();
                            }
                            value_list.push(v);
                            value_hash[v] = 1;
                        }
                    });

                    $scope.working.MultiMap[attr] = value_list;

                    if (Object.keys(value_hash).length == 1) {
                        if (attr == 'circ_lib') {
                            $scope.working[attr] = egCore.org.get(item_list[0][attr]());
                        } else {
                            $scope.working[attr] = item_list[0][attr]();
                        }
                    } else {
                        $scope.working[attr] = undefined;
                    }
                });

                angular.forEach($scope.statcats, function (sc) {

                    var counter = -1;
                    var value_hash = {};
                    var none = false;
                    angular.forEach(item_list, function (item) {
                        if (item.stat_cat_entries()) {
                            if (item.stat_cat_entries().length > 0) {
                                var right_sc = item.stat_cat_entries().filter(function (e) {
                                    return e.stat_cat() == sc.id() && !Boolean(e.isdeleted());
                                });

                                if (right_sc.length > 0) {
                                    value_hash[right_sc[0].id()] = right_sc[0].id();
                                } else {
                                    none = true;
                                }
                            } else {
                                none = true;
                            }
                        } else {
                            none = true;
                        }
                    });

                    if (!none && Object.keys(value_hash).length == 1) {
                        $scope.working.statcats[sc.id()] = value_hash[Object.keys(value_hash)[0]];
                        $scope.working.statcats_multi[sc.id()] = false;
                    } else if (item_list.length > 1 && Object.keys(value_hash).length > 0) {
                        $scope.working.statcats[sc.id()] = undefined;
                        $scope.working.statcats_multi[sc.id()] = true;
                    } else {
                        $scope.working.statcats[sc.id()] = undefined;
                        $scope.working.statcats_multi[sc.id()] = false;
                    }

                });

            } else {
                $scope.clearWorking();
            }

        }

        $scope.$watch('data.copies.length', function () {
            if ($scope.data.copies) {
                var base_orgs = $scope.data.copies.map(function(cp){
                    if (isNaN(cp.circ_lib())) return Number(cp.circ_lib().id());
                    return Number(cp.circ_lib());
                }).concat(
                    $scope.data.copies.map(function(cp){
                        if (isNaN(cp.call_number().owning_lib())) return Number(cp.call_number().owning_lib().id());
                        return Number(cp.call_number().owning_lib());
                    })
                ).concat(
                    [egCore.auth.user().ws_ou()]
                ).filter(function(e,i,a){
                    return a.lastIndexOf(e) === i;
                });

                var all_orgs = [];
                angular.forEach(base_orgs, function(o) {
                    all_orgs = all_orgs.concat( egCore.org.fullPath(o, true) );
                });

                var final_orgs = all_orgs.filter(function(e,i,a){
                    return a.lastIndexOf(e) === i;
                }).sort(function(a, b){return a-b});

                if ($scope.location_orgs.toString() != final_orgs.toString()) {
                    $scope.location_orgs = final_orgs;
                    if ($scope.location_orgs.length) {
                        itemSvc.get_locations_by_org($scope.location_orgs).then(function(list){
                            angular.forEach(list, function(l) {
                                $scope.location_cache[ ''+l.id() ] = l;
                            });
                            $scope.location_list = list;
                        }).then(function() {
                            $scope.statcat_filter_list = [];
                            angular.forEach($scope.location_orgs, function (o) {
                                $scope.statcat_filter_list.push(egCore.org.get(o));
                            });

                            itemSvc.get_statcats($scope.location_orgs).then(function(list){
                                $scope.statcats = list;
                                angular.forEach($scope.statcats, function (s) {

                                    if (!$scope.working)
                                        $scope.working = { statcats_multi: {}, statcats: {}, statcat_filter: undefined};
                                    if (!$scope.working.statcats_multi)
                                        $scope.working.statcats_multi = {};
                                    if (!$scope.working.statcats)
                                        $scope.working.statcats = {};

                                    if (!$scope.in_item_select) {
                                        $scope.working.statcats[s.id()] = undefined;
                                    }
                                    createStatcatUpdateWatcher(s.id());
                                });
                                $scope.in_item_select = false;
                                // do a refresh here to work around a race
                                // condition that can result in stat cats
                                // not being selected.
                                $scope.workingGridDataProvider.refresh();
                            });
                        });
                    }
                } else {
                    $scope.workingGridDataProvider.refresh();
                }
            }
        });

        $scope.statcat_visible = function (sc_owner) {
            var visible = typeof $scope.working.statcat_filter === 'undefined' || !$scope.working.statcat_filter;
            angular.forEach(egCore.org.ancestors(sc_owner), function (ancestor_org) {
                if ($scope.working.statcat_filter == ancestor_org.id())
                    visible = true;
            });
            return visible;
        }

        $scope.suffix_list = [];
        itemSvc.get_suffixes(egCore.auth.user().ws_ou()).then(function(list){
            $scope.suffix_list = list;
        });

        $scope.prefix_list = [];
        itemSvc.get_prefixes(egCore.auth.user().ws_ou()).then(function(list){
            $scope.prefix_list = list;
        });

        $scope.classification_list = [];
        itemSvc.get_classifications().then(function(list){
            $scope.classification_list = list;
        });

        $scope.$watch('completed_copies.length', function () {
            $scope.completedGridDataProvider.refresh();
        });

        $scope.location_list = [];
        createSimpleUpdateWatcher('location');

        $scope.status_list = [];
        itemSvc.get_magic_statuses().then(function(list){
            $scope.magic_status_list = list;
            createSimpleUpdateWatcher('status',$scope.magic_status_list);
        });
        itemSvc.get_statuses().then(function(list){
            $scope.status_list = list;
        });

        $scope.circ_modifier_list = [];
        itemSvc.get_circ_mods().then(function(list){
            $scope.circ_modifier_list = list;
        });
        createSimpleUpdateWatcher('circ_modifier');

        $scope.circ_type_list = [];
        itemSvc.get_circ_types().then(function(list){
            $scope.circ_type_list = list;
        });
        createSimpleUpdateWatcher('circ_as_type');

        $scope.age_protect_list = [];
        itemSvc.get_age_protects().then(function(list){
            $scope.age_protect_list = list;
        });
        createSimpleUpdateWatcher('age_protect');

        $scope.floating_list = [];
        itemSvc.get_floating_groups().then(function(list){
            $scope.floating_list = list;
        });
        createSimpleUpdateWatcher('floating');

        createSimpleUpdateWatcher('circ_lib');
        createSimpleUpdateWatcher('circulate');
        createSimpleUpdateWatcher('holdable');
        createSimpleUpdateWatcher('fine_level');
        createSimpleUpdateWatcher('loan_duration');
        createSimpleUpdateWatcher('price');
        createSimpleUpdateWatcher('cost');
        createSimpleUpdateWatcher('deposit');
        createSimpleUpdateWatcher('deposit_amount');
        createSimpleUpdateWatcher('mint_condition');
        createSimpleUpdateWatcher('opac_visible');
        createSimpleUpdateWatcher('ref');

        $scope.saveCompletedCopies = function (and_exit) {
            var cnHash = {};
            var perCnCopies = {};
            angular.forEach( $scope.completed_copies, function (cp) {
                var cn = cp.call_number();
                var cn_cps = cp.call_number().copies();
                cp.call_number().copies([]);
                var cn_id = cp.call_number().id();
                cp.call_number(cn_id); // prevent loops in JSON-ification
                if (!cnHash[cn_id]) {
                    cnHash[cn_id] = egCore.idl.Clone(cn);
                    perCnCopies[cn_id] = [egCore.idl.Clone(cp)];
                } else {
                    perCnCopies[cn_id].push(egCore.idl.Clone(cp));
                }
                cp.call_number(cn); // put the data back
                cp.call_number().copies(cn_cps);
                if (typeof cnHash[cn_id].prefix() == 'object')
                    cnHash[cn_id].prefix(cnHash[cn_id].prefix().id()); // un-object-ize some fields
                if (typeof cnHash[cn_id].suffix() == 'object')
                    cnHash[cn_id].suffix(cnHash[cn_id].suffix().id()); // un-object-ize some fields
            });

            if ($scope.only_vols) { // strip off copies when we're in vol-only mode
                angular.forEach(cnHash, function (v, k) {
                    cnHash[k].copies([]);
                });
            } else {
                angular.forEach(perCnCopies, function (v, k) {
                    cnHash[k].copies(v);
                });
            }

            cnList = [];
            angular.forEach(cnHash, function (v, k) {
                cnList.push(v);
            });

            egNet.request(
                'open-ils.cat',
                'open-ils.cat.asset.volume.fleshed.batch.update.override',
                egCore.auth.token(), cnList, 1, { auto_merge_vols : 1, create_parts : 1, return_copy_ids : 1 }
            ).then(function(copy_ids) {
                if (and_exit) {
                    $scope.dirty = false;
                    if ($scope.defaults.print_item_labels) {
                        egCore.net.request(
                            'open-ils.actor',
                            'open-ils.actor.anon_cache.set_value',
                            null, 'print-labels-these-copies', {
                                copies : copy_ids
                            }
                        ).then(function(key) {
                            if (key) {
                                var url = egCore.env.basePath + 'cat/printlabels/' + key;
                                $timeout(function() { $window.open(url, '_blank') }).then(
                                    function() { $timeout(function(){$window.close()}); }
                                );
                            } else {
                                alert('Could not create anonymous cache key!');
                            }
                        });
                    } else {
                        $timeout(function(){
                            if (typeof BroadcastChannel != 'undefined') {
                                var bChannel = new BroadcastChannel("eg.holdings.update");
                                var bre_ids = cnList && cnList.length > 0 ? cnList.map(function(cn){ return Number(cn.record()) }) : [];
                                var cn_ids = cnList && cnList.length > 0 ? cnList.map(function(cn){ return cn.id() }) : [];
                                bChannel.postMessage({
                                    copies : copy_ids,
                                    volumes: cn_ids,
                                    records: bre_ids
                                });
                            }

                            $window.close();
                        });
                    }
                }
            });
        }

        $scope.saveAndContinue = function () {
            $scope.saveCompletedCopies(false);
        }

        $scope.workingSaveAndExit = function () {
            $scope.workingToComplete();
            $scope.saveAndExit();
        }

        $scope.saveAndExit = function () {
            $scope.saveCompletedCopies(true);
        }

    }

    $scope.copy_notes_dialog = function(copy_list) {
        var default_pub = Boolean($scope.defaults.copy_notes_pub);
        if (!angular.isArray(copy_list)) copy_list = [copy_list];

        return $uibModal.open({
            templateUrl: './cat/volcopy/t_copy_notes',
            backdrop: 'static',
            animation: true,
            controller:
                   ['$scope','$uibModalInstance',
            function($scope , $uibModalInstance) {
                $scope.focusNote = true;
                $scope.note = {
                    creator : egCore.auth.user().id(),
                    title   : '',
                    value   : '',
                    pub     : default_pub,
                };

                $scope.require_initials = false;
                egCore.org.settings([
                    'ui.staff.require_initials.copy_notes'
                ]).then(function(set) {
                    $scope.require_initials_ous = Boolean(set['ui.staff.require_initials.copy_notes']);
                });

                $scope.are_initials_required = function() {
                  $scope.require_initials = $scope.require_initials_ous && ($scope.note.value.length > 0 || $scope.note.title.length > 0);
                };

                $scope.$watch('note.value.length', $scope.are_initials_required);
                $scope.$watch('note.title.length', $scope.are_initials_required);

                $scope.note_list = [];
                if (copy_list.length == 1) {
                    $scope.note_list = copy_list[0].notes();
                }

                $scope.ok = function(note) {

                    if (note.value.length > 0 || note.title.length > 0) {
                        if ($scope.initials) {
                            note.value = egCore.strings.$replace(
                                egCore.strings.COPY_NOTE_INITIALS, {
                                value : note.value,
                                initials : $scope.initials,
                                ws_ou : egCore.org.get(
                                    egCore.auth.user().ws_ou()).shortname()
                            });
                        }

                        angular.forEach(copy_list, function (cp) {
                            if (!angular.isArray(cp.notes())) cp.notes([]);
                            var n = new egCore.idl.acpn();
                            n.isnew(1);
                            n.creator(note.creator);
                            n.pub(note.pub ? 't' : 'f');
                            n.title(note.title);
                            n.value(note.value);
                            n.owning_copy(cp.id());
                            cp.notes().push( n );
                        });
                    }

                    $uibModalInstance.close();
                }

                $scope.cancel = function($event) {
                    $uibModalInstance.dismiss();
                    $event.preventDefault();
                }
            }]
        });
    }

    $scope.copy_tags_dialog = function(copy_list) {
        if (!angular.isArray(copy_list)) copy_list = [copy_list];

        return $uibModal.open({
            templateUrl: './cat/volcopy/t_copy_tags',
            backdrop: 'static',
            animation: true,
            controller:
                   ['$scope','$uibModalInstance',
            function($scope , $uibModalInstance) {

                $scope.tag_map = [];
                var tag_hash = {};
                var shared_tags = {};
                angular.forEach(copy_list, function (cp) {
                    angular.forEach(cp.tags(), function(tag) {
                        if (!(tag.tag().id() in shared_tags)) {
                            shared_tags[tag.tag().id()] = 1;
                        } else {
                            shared_tags[tag.tag().id()]++;
                        }
                        if (!(tag.tag().id() in tag_hash)) {
                            tag_hash[tag.tag().id()] = tag;
                        }
                    });
                });
                angular.forEach(tag_hash, function(value, key) {
                    if (shared_tags[key] == copy_list.length) {
                        $scope.tag_map.push(value);
                    }
                });

                $scope.tag_types = [];
                egCore.pcrud.retrieveAll('cctt', {order_by : { cctt : 'label' }}, {atomic : true}).then(function(list) {
                    $scope.tag_types = list;
                    $scope.tag_type = $scope.tag_types[0].code(); // just pick a default
                });

                $scope.getTags = function(val) {
                    return egCore.pcrud.search('acpt',
                        { 
                            owner :  egCore.org.fullPath(egCore.auth.user().ws_ou(), true),
                            label : { 'startwith' : {
                                        transform: 'evergreen.lowercase',
                                        value : [ 'evergreen.lowercase', val ]
                                    }},
                            tag_type : $scope.tag_type
                        },
                        { order_by : { 'acpt' : ['label'] } }, { atomic: true }
                    ).then(function(list) {
                        return list.map(function(item) {
                            return { value: item.label(), display: item.label() + " (" + egCore.org.get(item.owner()).shortname() + ")" };
                        });
                    });
                }

                $scope.addTag = function() {
                    var tagLabel = $scope.selectedLabel;
                    // clear the typeahead
                    $scope.selectedLabel = "";

                    // first, check tags already associated with the copy
                    var foundMatch = false;
                    angular.forEach($scope.tag_map, function(tag) {
                        if (tag.tag().label() ==  tagLabel && tag.tag().tag_type() == $scope.tag_type) {
                            foundMatch = true;
                            if (tag.isdeleted()) tag.isdeleted(0); // just deleting the mapping
                        }
                    });
                    if (!foundMatch) {
                        egCore.pcrud.search('acpt',
                            { 
                                owner : egCore.org.fullPath(egCore.auth.user().ws_ou(), true),
                                label : tagLabel,
                                tag_type : $scope.tag_type
                            },
                            { order_by : { 'acpt' : ['label'] } }, { atomic: true }
                        ).then(function(list) {
                            if (list.length > 0) {
                                var newMap = new egCore.idl.acptcm();
                                newMap.isnew(1);
                                newMap.copy(copy_list[0].id());
                                newMap.tag(egCore.idl.Clone(list[0]));
                                $scope.tag_map.push(newMap);
                            } else {
                                var newTag = new egCore.idl.acpt();
                                newTag.isnew(1);
                                newTag.owner(egCore.auth.user().ws_ou());
                                newTag.label(tagLabel);
                                newTag.pub('t');
                                newTag.tag_type($scope.tag_type);

                                var newMap = new egCore.idl.acptcm();
                                newMap.isnew(1);
                                newMap.copy(copy_list[0].id());
                                newMap.tag(newTag);
                                $scope.tag_map.push(newMap);
                            }
                        });
                    }
                }

                $scope.ok = function(note) {
                    // in the multi-item case, this works OK for
                    // adding new maps to existing tags, but doesn't handle
                    // all possibilities
                    angular.forEach(copy_list, function (cp) {
                        cp.tags($scope.tag_map);
                    });
                    $uibModalInstance.close();
                }

                $scope.cancel = function($event) {
                    $uibModalInstance.dismiss();
                    $event.preventDefault();
                }
            }]
        });
    }

    $scope.copy_alerts_dialog = function(copy_list) {
        if (!angular.isArray(copy_list)) copy_list = [copy_list];


        // Instead of opening modal, open new tab with Angular route
        const copyIds = copy_list.map(cp => cp.id()).join(',');
        window.open(`/eg2/staff/cat/item/alerts?copyIds=${copyIds}`, '_blank');
    }

}])

.directive("egVolTemplate", function () {
    return {
        restrict: 'E',
        replace: true,
        template: '<div ng-include="'+"'/eg/staff/cat/volcopy/t_attr_edit'"+'"></div>',
        scope: {
            editTemplates: '=',
        },
        controller : ['$scope','$window','itemSvc','egCore','ngToast','$uibModal',
            function ( $scope , $window , itemSvc , egCore , ngToast , $uibModal) {

                $scope.i18n = egCore.i18n;

                $scope.defaults = { // If defaults are not set at all, allow everything
                    barcode_checkdigit : false,
                    auto_gen_barcode : false,
                    statcats : true,
                    copy_notes : true,
                    copy_tags : true,
                    copy_alerts : true,
                    attributes : {
                        status : true,
                        loan_duration : true,
                        fine_level : true,
                        cost : true,
                        alerts : true,
                        deposit : true,
                        deposit_amount : true,
                        opac_visible : true,
                        price : true,
                        circulate : true,
                        mint_condition : true,
                        circ_lib : true,
                        ref : true,
                        circ_modifier : true,
                        circ_as_type : true,
                        location : true,
                        holdable : true,
                        age_protect : true,
                        floating : true
                    }
                };

                $scope.fetchDefaults = function () {
                    egCore.hatch.getItem('cat.copy.defaults').then(function(t) {
                        if (t) {
                            $scope.defaults = t;
                            $scope.working.statcat_filter = $scope.defaults.statcat_filter;
                            if (
                                    typeof $scope.defaults.statcat_filter == 'object' &&
                                    Object.keys($scope.defaults.statcat_filter).length > 0
                                ) {
                                // want fieldmapper object here...
                                $scope.defaults.statcat_filter =
                                    egCore.idl.Clone($scope.defaults.statcat_filter);
                                // ... and ID here
                                $scope.working.statcat_filter = $scope.defaults.statcat_filter.id();
                            }
                        }
                    });
                }
                $scope.fetchDefaults();

                $scope.dirty = false;
                $scope.$watch('dirty',
                    function(newVal, oldVal) {
                        if (newVal && newVal != oldVal) {
                            $($window).on('beforeunload.template', function(){
                                return 'There is unsaved template data!'
                            });
                        } else {
                            $($window).off('beforeunload.template');
                        }
                    }
                );

                $scope.template_controls = true;

                $scope.fetchTemplates = function () {
                    itemSvc.get_acp_templates().then(function(t) {
                        if (t) {
                            $scope.templates = t;
                            $scope.template_name_list = Object.keys(t).sort();
                        }
                    });
                }
                $scope.fetchTemplates();
            
                $scope.applyTemplate = function (n) {
                    angular.forEach($scope.templates[n], function (v,k) {
                        if (k == 'circ_lib') {
                            $scope.working[k] = egCore.org.get(v);
                        } else if (angular.isArray(v) || !angular.isObject(v)) {
                            $scope.working[k] = angular.copy(v);
                        } else {
                            angular.forEach(v, function (sv,sk) {
                                if (!(k in $scope.working))
                                    $scope.working[k] = {};
                                $scope.working[k][sk] = angular.copy(sv);
                            });
                        }
                    });
                    $scope.template_name = '';
                }

                $scope.deleteTemplate = function (n) {
                    if (n) {
                        delete $scope.templates[n]
                        $scope.template_name_list = Object.keys($scope.templates).sort();
                        $scope.template_name = '';
                        itemSvc.save_acp_templates($scope.templates);
                        $scope.$parent.fetchTemplates();
                        ngToast.create(egCore.strings.VOL_COPY_TEMPLATE_SUCCESS_DELETE);
                    }
                }

                $scope.saveTemplate = function (n) {
                    if (n) {
                        var tmpl = {};
            
                        angular.forEach($scope.working, function (v,k) {
                            if (angular.isObject(v)) { // we'll use the pkey
                                if (v.id) v = v.id();
                                else if (v.code) v = v.code();
                                else v = angular.copy(v); // Should only be statcats and callnumbers currently
                            }
            
                            tmpl[k] = v;
                        });
            
                        $scope.templates[n] = tmpl;
                        $scope.template_name_list = Object.keys($scope.templates).sort();
            
                        itemSvc.save_acp_templates($scope.templates);
                        $scope.$parent.fetchTemplates();

                        $scope.dirty = false;
                    } else {
                        // save all templates, as we might do after an import
                        itemSvc.save_acp_templates($scope.templates);
                        $scope.$parent.fetchTemplates();
                    }
                    ngToast.create(egCore.strings.VOL_COPY_TEMPLATE_SUCCESS_SAVE);
                }

                $scope.templates = {};
                $scope.imported_templates = { data : '' };
                $scope.template_name = '';
                $scope.template_name_list = [];

                $scope.$watch('imported_templates.data', function(newVal, oldVal) {
                    if (newVal && newVal != oldVal) {
                        try {
                            var newTemplates = JSON.parse(newVal);
                            if (!Object.keys(newTemplates).length) return;
                            angular.forEach(Object.keys(newTemplates), function (k) {
                                $scope.templates[k] = newTemplates[k];
                            });
                            itemSvc.save_acp_templates($scope.templates);
                            $scope.fetchTemplates();
                        } catch (E) {
                            console.log('tried to import an invalid copy template file');
                        }
                    }
                });

                $scope.tracker = function (x,f) { if (x) return x[f]() };
                $scope.idTracker = function (x) { if (x) return $scope.tracker(x,'id') };
                $scope.cant_have_vols = function (id) { return !egCore.org.CanHaveVolumes(id); };
            
                $scope.orgById = function (id) { return egCore.org.get(id) }
                $scope.statusById = function (id) {
                    return $scope.status_list.filter( function (s) { return s.id() == id } )[0];
                }
                $scope.locationById = function (id) {
                    return $scope.location_cache[''+id];
                }
            
                createSimpleUpdateWatcher = function (field) {
                    $scope.$watch('working.' + field, function () {
                        var newval = $scope.working[field];
            
                        if (typeof newval != 'undefined') {
                            $scope.dirty = true;
                            if (angular.isObject(newval)) { // we'll use the pkey
                                if (newval.id) $scope.working[field] = newval.id();
                                else if (newval.code) $scope.working[field] = newval.code();
                            }
            
                            if (""+newval == "" || newval == null) {
                                $scope.working[field] = undefined;
                            }
            
                        }
                    });
                }
            
                $scope.working = {
                    copy_notes: [],
                    copy_alerts: [],
                    statcats: {},
                    statcat_filter: undefined
                };
            
                $scope.statcat_visible = function (sc_owner) {
                    var visible = typeof $scope.working.statcat_filter === 'undefined' || !$scope.working.statcat_filter;
                    angular.forEach(egCore.org.ancestors(sc_owner), function (ancestor_org) {
                        if ($scope.working.statcat_filter == ancestor_org.id())
                            visible = true;
                    });
                    return visible;
                }

                createStatcatUpdateWatcher = function (id) {
                    return $scope.$watch('working.statcats[' + id + ']', function () {
                        if ($scope.working.statcats) {
                            var newval = $scope.working.statcats[id];
                
                            if (typeof newval != 'undefined') {
                                $scope.dirty = true;
                                if (angular.isObject(newval)) { // we'll use the pkey
                                    newval = newval.id();
                                }
                
                                if (""+newval == "" || newval == null) {
                                    $scope.working.statcats[id] = undefined;
                                    newval = null;
                                }
                
                            }
                        }
                    });
                }

                $scope.clearWorking = function () {
                    angular.forEach($scope.working, function (v,k,o) {
                        if (!angular.isObject(v)) {
                            if (typeof v != 'undefined')
                                $scope.working[k] = undefined;
                        } else if (k != 'circ_lib' && k != 'MultiMap') {
                            angular.forEach(v, function (sv,sk) {
                                $scope.working[k][sk] = undefined;
                            });
                        }
                    });
                    $scope.working.circ_lib = undefined; // special
                    $scope.dirty = false;
                }

                $scope.working = {};
                $scope.location_orgs = [];
                $scope.location_cache = {};
            
                $scope.location_list = [];
                itemSvc.get_locations_by_org(
                    egCore.org.fullPath( egCore.auth.user().ws_ou(), true )
                ).then(function(list){
                    $scope.location_list = list;
                });
                createSimpleUpdateWatcher('location');

                $scope.statcat_filter_list = egCore.org.fullPath( egCore.auth.user().ws_ou() );

                $scope.statcats = [];
                itemSvc.get_statcats(
                    egCore.org.fullPath( egCore.auth.user().ws_ou(), true )
                ).then(function(list){
                    $scope.statcats = list;
                    angular.forEach($scope.statcats, function (s) {

                        if (!$scope.working)
                            $scope.working = { statcats: {}, statcat_filter: undefined};
                        if (!$scope.working.statcats)
                            $scope.working.statcats = {};

                        $scope.working.statcats[s.id()] = undefined;
                        createStatcatUpdateWatcher(s.id());
                    });
                });

                $scope.copy_notes_dialog = function() {
                    var default_pub = Boolean($scope.defaults.copy_notes_pub);
                    var working = $scope.working;
            
                    return $uibModal.open({
                        templateUrl: './cat/volcopy/t_copy_notes',
                        animation: true,
                        controller:
                            ['$scope','$uibModalInstance',
                        function($scope , $uibModalInstance) {
                            $scope.focusNote = true;
                            $scope.note = {
                                title   : '',
                                value   : '',
                                pub     : default_pub,
                            };

                            $scope.require_initials = false;
                            egCore.org.settings([
                                'ui.staff.require_initials.copy_notes'
                            ]).then(function(set) {
                                $scope.require_initials = Boolean(set['ui.staff.require_initials.copy_notes']);
                            });

                            $scope.note_list = [];
                            angular.forEach(working.copy_notes, function(note) {
                                var acpn = egCore.idl.fromHash('acpn', note);
                                $scope.note_list.push(acpn);
                            });

                            $scope.ok = function(note) {

                                if (!working.copy_notes) {
                                    working.copy_notes = [];
                                }

                                // clear slate
                                working.copy_notes.length = 0;
                                angular.forEach($scope.note_list, function(existing_note) {
                                    if (!existing_note.isdeleted()) {
                                        working.copy_notes.push({
                                            pub : existing_note.pub() ? 't' : 'f',
                                            title : existing_note.title(),
                                            value : existing_note.value()
                                        });
                                    }
                                });

                                // add new note, if any
                                if (note.initials) note.value += ' [' + note.initials + ']';
                                note.pub = note.pub ? 't' : 'f';
                                if (note.title.length && note.value.length) {
                                    working.copy_notes.push(note);
                                }

                                $uibModalInstance.close();
                            }

                            $scope.cancel = function($event) {
                                $uibModalInstance.dismiss();
                                $event.preventDefault();
                            }
                        }]
                    });
                }
            
                $scope.copy_alerts_dialog = function() {
                    var working = $scope.working;

                    return $uibModal.open({
                        templateUrl: './cat/volcopy/t_copy_alerts',
                        animation: true,
                        controller:
                            ['$scope','$uibModalInstance',
                        function($scope , $uibModalInstance) {

                            itemSvc.get_copy_alert_types().then(function(ccat) {
                                var ccat_map = {};
                                $scope.alert_types = ccat;
                                angular.forEach(ccat, function(t) {
                                    ccat_map[t.id()] = t;
                                });
                                $scope.copy_alert_list = [];
                                angular.forEach(working.copy_alerts, function (alrt) {
                                    var aca = egCore.idl.fromHash('aca', alrt);
                                    aca.alert_type(ccat_map[alrt.alert_type]);
                                    aca.ack_time(null);
                                    $scope.copy_alert_list.push(aca);
                                });
                            });

                            $scope.focusNote = true;
                            $scope.copy_alert = {
                                note         : '',
                                temp         : false
                            };

                            $scope.ok = function(copy_alert) {
            
                                if (!working.copy_alerts) {
                                    working.copy_alerts = [];
                                }
                                // clear slate
                                working.copy_alerts.length = 0;

                                angular.forEach($scope.copy_alert_list, function(alrt) {
                                    if (alrt.ack_time() == null) {
                                        working.copy_alerts.push({
                                            note : alrt.note(),
                                            temp : alrt.temp(),
                                            alert_type : alrt.alert_type().id()
                                        });
                                    }
                                });

                                if (typeof(copy_alert.note) != 'undefined' &&
                                    copy_alert.note != '') {
                                    working.copy_alerts.push({
                                        note : copy_alert.note,
                                        temp : copy_alert.temp ? 't' : 'f',
                                        alert_type : copy_alert.alert_type
                                    });
                                }

                                $uibModalInstance.close();
                            }

                            $scope.cancel = function($event) {
                                $uibModalInstance.dismiss();
                                $event.preventDefault();
                            }
                        }]
                    });
                }

                $scope.status_list = [];
                itemSvc.get_magic_statuses().then(function(list){
                    $scope.magic_status_list = list;
                });
                itemSvc.get_statuses().then(function(list){
                    $scope.status_list = list;
                });
                createSimpleUpdateWatcher('status');
            
                $scope.circ_modifier_list = [];
                itemSvc.get_circ_mods().then(function(list){
                    $scope.circ_modifier_list = list;
                });
                createSimpleUpdateWatcher('circ_modifier');
            
                $scope.circ_type_list = [];
                itemSvc.get_circ_types().then(function(list){
                    $scope.circ_type_list = list;
                });
                createSimpleUpdateWatcher('circ_as_type');
            
                $scope.age_protect_list = [];
                itemSvc.get_age_protects().then(function(list){
                    $scope.age_protect_list = list;
                });
                createSimpleUpdateWatcher('age_protect');

                $scope.floating_list = [];
                itemSvc.get_floating_groups().then(function(list){
                    $scope.floating_list = list;
                });
                createSimpleUpdateWatcher('floating');

                createSimpleUpdateWatcher('circulate');
                createSimpleUpdateWatcher('holdable');
                createSimpleUpdateWatcher('fine_level');
                createSimpleUpdateWatcher('loan_duration');
                createSimpleUpdateWatcher('cost');
                createSimpleUpdateWatcher('deposit');
                createSimpleUpdateWatcher('deposit_amount');
                createSimpleUpdateWatcher('mint_condition');
                createSimpleUpdateWatcher('opac_visible');
                createSimpleUpdateWatcher('ref');

                $scope.suffix_list = [];
                itemSvc.get_suffixes(egCore.auth.user().ws_ou()).then(function(list){
                    $scope.suffix_list = list;
                });

                $scope.prefix_list = [];
                itemSvc.get_prefixes(egCore.auth.user().ws_ou()).then(function(list){
                    $scope.prefix_list = list;
                });

                $scope.classification_list = [];
                itemSvc.get_classifications().then(function(list){
                    $scope.classification_list = list;
                });

                createSimpleUpdateWatcher('working.callnumber.classification');
                createSimpleUpdateWatcher('working.callnumber.prefix');
                createSimpleUpdateWatcher('working.callnumber.suffix');
            }
        ]
    }
})


