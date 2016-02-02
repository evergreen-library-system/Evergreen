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

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {
        delay : ['egStartup', function(egStartup) { return egStartup.go(); }]
    };

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

    service.get_prefixes = function(org) {
        return egCore.pcrud.search('acnp',
            {owning_lib : egCore.org.fullPath(org, true)},
            {order_by : { acnp : 'label_sortkey' }}, {atomic : true}
        );

    };

    service.get_statcats = function(orgs) {
        return egCore.pcrud.search('asc',
            {owner : orgs},
            { flesh : 1,
              flesh_fields : {
                asc : ['owner','entries']
              }
            },
            { atomic : true }
        );
    };

    service.get_locations = function(orgs) {
        return egCore.pcrud.search('acpl',
            {owning_lib : orgs},
            {order_by : { acpl : 'name' }}, {atomic : true}
        );
    };

    service.get_suffixes = function(org) {
        return egCore.pcrud.search('acns',
            {owning_lib : egCore.org.fullPath(org, true)},
            {order_by : { acns : 'label_sortkey' }}, {atomic : true}
        );

    };

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
    service.get_parts = function(rec) {
        if (service.bmp_parts[rec])
            return $q.when(service.bmp_parts[rec]);

        return egCore.pcrud.search('bmp',
            {record : rec, deleted : 'f'},
            null, {atomic : true}
        ).then(function(list) {
            service.bmp_parts[rec] = list;
            return list;
        });

    };

    service.flesh = {   
        flesh : 3, 
        flesh_fields : {
            acp : ['call_number','parts','stat_cat_entries', 'notes'],
            acn : ['label_class','prefix','suffix']
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
    service.generateNewCopy = function(callNumber, owningLib, isFastAdd, isNew) {
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

        var status_setting = isFastAdd ?
            'cat.default_copy_status_fast' :
            'cat.default_copy_status_normal';
        egCore.org.settings(
            [status_setting],
            owningLib
        ).then(function(set) {
            var default_ccs = set[status_setting] || 
                (isFastAdd ? 0 : 5); // 0 is Available, 5 is In Process
            cp.status(default_ccs);
        });

        return cp;
    }

    return service;
}])

.directive("egVolCopyEdit", function () {
    return {
        restrict: 'E',
        replace: true,
        template:
            '<div class="row">'+
                '<div class="col-xs-5" ng-class="{'+"'has-error'"+':barcode_has_error}">'+
                    '<input id="{{callNumber.id()}}_{{copy.id()}}"'+
                    ' eg-enter="nextBarcode(copy.id())" class="form-control"'+
                    ' type="text" ng-model="barcode" ng-change="updateBarcode()"/>'+
                '</div>'+
                '<div class="col-xs-3"><input class="form-control" type="number" ng-model="copy_number" ng-change="updateCopyNo()"/></div>'+
                '<div class="col-xs-4"><eg-basic-combo-box eg-disabled="record == 0" list="parts" selected="part"></eg-basic-combo-box></div>'+
            '</div>',

        scope: { focusNext: "=", copy: "=", callNumber: "=", index: "@", record: "@" },
        controller : ['$scope','itemSvc','egCore',
            function ( $scope , itemSvc , egCore ) {
                $scope.new_part_id = 0;
                $scope.barcode_has_error = false;

                $scope.nextBarcode = function (i) {
                    $scope.focusNext(i, $scope.barcode);
                }

                $scope.updateBarcode = function () {
                    if ($scope.barcode != '')
                        $scope.barcode_has_error = !Boolean(itemSvc.checkBarcode($scope.barcode));
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
                $scope.$watch('part', $scope.updatePart);

                $scope.barcode = $scope.copy.barcode();
                $scope.copy_number = $scope.copy.copy_number();

                if ($scope.copy.parts()) {
                    $scope.part = $scope.copy.parts()[0];
                    if ($scope.part) $scope.part = $scope.part.label();
                };

                $scope.parts = [];
                $scope.part_list = [];

                itemSvc.get_parts($scope.callNumber.record()).then(function(list){
                    $scope.part_list = list;
                    angular.forEach(list, function(p){ $scope.parts.push(p.label()) });
                    $scope.parts = angular.copy($scope.parts);
                });

            }
        ]

    }
})

.directive("egVolRow", function () {
    return {
        restrict: 'E',
        replace: true,
        transclude: true,
        template:
            '<div class="row">'+
                '<div class="col-xs-2">'+
                    '<select ng-disabled="record == 0" class="form-control" ng-model="classification" ng-change="updateClassification()" ng-options="cl.name() for cl in classification_list"/>'+
                '</div>'+
                '<div class="col-xs-1">'+
                    '<select ng-disabled="record == 0" class="form-control" ng-model="prefix" ng-change="updatePrefix()" ng-options="p.label() for p in prefix_list"/>'+
                '</div>'+
                '<div class="col-xs-2"><input ng-disabled="record == 0" class="form-control" type="text" ng-change="updateLabel()" ng-model="label"/></div>'+
                '<div class="col-xs-1">'+
                    '<select ng-disabled="record == 0" class="form-control" ng-model="suffix" ng-change="updateSuffix()" ng-options="s.label() for s in suffix_list"/>'+
                '</div>'+
                '<div ng-hide="onlyVols" class="col-xs-1"><input ng-disabled="record == 0" class="form-control" type="number" ng-model="copy_count" min="{{orig_copy_count}}" ng-change="changeCPCount()"></div>'+
                '<div ng-hide="onlyVols" class="col-xs-5">'+
                    '<eg-vol-copy-edit record="{{record}}" ng-repeat="cp in copies track by idTracker(cp)" focus-next="focusNextBarcode" copy="cp" call-number="callNumber"></eg-vol-copy-edit>'+
                '</div>'+
            '</div>',

        scope: {focusNext: "=", allcopies: "=", copies: "=", onlyVols: "=", record: "@" },
        controller : ['$scope','itemSvc','egCore',
            function ( $scope , itemSvc , egCore ) {
                $scope.callNumber =  $scope.copies[0].call_number();

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
                });

                $scope.prefix = $scope.callNumber.prefix();
                $scope.suffix = $scope.callNumber.suffix();
                $scope.classification = $scope.callNumber.label_class();
                $scope.label = $scope.callNumber.label();

                $scope.copy_count = $scope.copies.length;
                $scope.orig_copy_count = $scope.copy_count;

                $scope.changeCPCount = function () {
                    while ($scope.copy_count > $scope.copies.length) {
                        var cp = itemSvc.generateNewCopy(
                            $scope.callNumber,
                            $scope.callNumber.owning_lib(),
                            $scope.fast_add,
                            true
                        );
                        $scope.copies.push( cp );
                        $scope.allcopies.push( cp );

                    }

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
})

.directive("egVolEdit", function () {
    return {
        restrict: 'E',
        replace: true,
        template:
            '<div class="row">'+
                '<div class="col-xs-1"><eg-org-selector alldisabled="{{record == 0}}" selected="owning_lib" disable-test="cant_have_vols"></eg-org-selector></div>'+
                '<div class="col-xs-1"><input ng-disabled="record == 0" class="form-control" type="number" min="{{orig_cn_count}}" ng-model="cn_count" ng-change="changeCNCount()"/></div>'+
                '<div class="col-xs-10">'+
                    '<eg-vol-row only-vols="onlyVols" record="{{record}}"'+
                        'ng-repeat="(cn,copies) in struct | orderBy:cn track by cn" '+
                        'focus-next="focusNextFirst" copies="copies" allcopies="allcopies">'+
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
                                true
                            );

                            $scope.struct[cn.id()] = [cp];
                            $scope.allcopies.push(cp);
                            if (!scope.defaults.classification) {
                                egCore.org.settings(
                                    ['cat.default_classification_scheme'],
                                    cn.owning_lib()
                                ).then(function (val) {
                                    cn.label_class(val['cat.default_classification_scheme']);
                                });
                            }
                        }
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
       ['$scope','$q','$window','$routeParams','$location','$timeout','egCore','egNet','egGridDataProvider','itemSvc','$modal',
function($scope , $q , $window , $routeParams , $location , $timeout , egCore , egNet , egGridDataProvider , itemSvc , $modal) {

    $scope.defaults = { // If defaults are not set at all, allow everything
        barcode_checkdigit : false,
        auto_gen_barcode : false,
        statcats : true,
        copy_notes : true,
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

    $scope.embedded = ($routeParams.mode && $routeParams.mode == 'embedded') ? true : false;

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
        });
    }
    $scope.fetchDefaults();

    $scope.$watch('defaults.statcat_filter', function() {
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

    $scope.completeToWorking = function () {
        angular.forEach( $scope.completedGridControls.selectedItems(), function (c) {
            angular.forEach( $scope.completed_copies, function (w, i) {
                if (c === w)
                    itemSvc.copies = itemSvc.copies.concat($scope.completed_copies.splice(i,1));
            });
        });

        return true;
    }

    createSimpleUpdateWatcher = function (field) {
        return $scope.$watch('working.' + field, function () {
            var newval = $scope.working[field];

            if (typeof newval != 'undefined') {
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
                            if (cp[field]() !== newval) {
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

    $scope.working = {
        statcats: {},
        statcat_filter: undefined
    };

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
                        cp.stat_cat_entries(
                            cp.stat_cat_entries().filter(function (e) {
                                return !Boolean(e.isdeleted());
                            })
                        );
   
                        cp.ischanged(1);
                    }
                );
            }
        }
    }

    var dataKey = $routeParams.dataKey;
    console.debug('dataKey: ' + dataKey);

    if (dataKey && dataKey.length > 0) {

        $scope.templates = {};
        $scope.template_name = '';
        $scope.template_name_list = [];

        $scope.fetchTemplates = function () {
            egCore.hatch.getItem('cat.copy.templates').then(function(t) {
                if (t) {
                    $scope.templates = t;
                    $scope.template_name_list = Object.keys(t);
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
                if (!angular.isObject(v)) {
                    if (typeof v != 'undefined')
                        $scope.working[k] = undefined;
                } else if (k != 'circ_lib') {
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

                function fetchRaw () {
                    if (!$scope.only_vols) $scope.dirty = true;
                    $scope.add_vols_copies = true;

                    /* data.raw data structure looks like this:
                     * [{
                     *      callnumber : $cn_id, // optional, to add a copy to a cn
                     *      owner      : $org, // optional, defaults to ws_ou
                     *      label      : $cn_label, // optional, to supply a label on a new cn
                     *      barcode    : $cp_barcode // optional, to supply a barcode on a new cp
                     *      fast_add   : boolean // optional, to specify whether this came
                     *                              in as a fast add
                     * },...]
                     * 
                     * All can be left out and a completely empty vol/copy combo will be vivicated.
                     */

                    angular.forEach(
                        data.raw,
                        function (proto) {
                            if (proto.fast_add) $scope.is_fast_add = true;
                            if (proto.callnumber) {
                                return egCore.pcrud.retrieve('acn', proto.callnumber)
                                .then(function(cn) {
                                    var cp = new itemSvc.generateNewCopy(
                                        cn,
                                        proto.owner || egCore.auth.user().ws_ou(),
                                        $scope.is_fast_add,
                                        ((!$scope.only_vols) ? true : false)
                                    );

                                    if (proto.barcode) cp.barcode( proto.barcode );

                                    itemSvc.addCopy(cp)
                                });
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

                                var cp = new itemSvc.generateNewCopy(
                                    cn,
                                    proto.owner || egCore.auth.user().ws_ou(),
                                    $scope.is_fast_add,
                                    true
                                );

                                if (proto.barcode) cp.barcode( proto.barcode );

                                itemSvc.addCopy(cp)
                            }
    
                        }
                    );

                    return itemSvc.copies;
                }

                if (data.copies && data.copies.length)
                    return itemSvc.fetchIds(data.copies).then(fetchRaw);

                return fetchRaw();

            }

        }).then( function() {
            $scope.data = itemSvc;
            $scope.workingGridDataProvider.refresh();
        });

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
                    angular.forEach(item_list, function (item) {
                        if (item[attr]) {
                            var v = item[attr]()
                            if (angular.isObject(v)) {
                                if (v.id) v = v.id();
                                else if (v.code) v = v.code();
                            }
                            value_hash[v] = 1;
                        }
                    });

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
                            }
                        } else {
                            none = true;
                        }
                    });

                    if (!none && Object.keys(value_hash).length == 1) {
                        $scope.working.statcats[sc.id()] = value_hash[Object.keys(value_hash)[0]];
                    } else {
                        $scope.working.statcats[sc.id()] = undefined;
                    }
                });

            } else {
                $scope.clearWorking();
            }

        }

        $scope.$watch('data.copies.length', function () {
            if ($scope.data.copies) {
                var base_orgs = $scope.data.copies.map(function(cp){
                    return cp.circ_lib()
                }).concat(
                    $scope.data.copies.map(function(cp){
                        return cp.call_number().owning_lib()
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
                }).sort(function(a, b){return parseInt(a)-parseInt(b)});

                if ($scope.location_orgs.toString() != final_orgs.toString()) {
                    $scope.location_orgs = final_orgs;
                    if ($scope.location_orgs.length) {
                        itemSvc.get_locations($scope.location_orgs).then(function(list){
                            angular.forEach(list, function(l) {
                                $scope.location_cache[ ''+l.id() ] = l;
                            });
                            $scope.location_list = list;
                        });

                        $scope.statcat_filter_list = [];
                        angular.forEach($scope.location_orgs, function (o) {
                            $scope.statcat_filter_list.push(egCore.org.get(o));
                        });

                        itemSvc.get_statcats($scope.location_orgs).then(function(list){
                            $scope.statcats = list;
                            angular.forEach($scope.statcats, function (s) {

                                if (!$scope.working)
                                    $scope.working = { statcats: {}, statcat_filter: undefined};
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
                    }
                }
            }

            $scope.workingGridDataProvider.refresh();
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
        itemSvc.get_locations().then(function(list){
            $scope.location_list = list;
        });
        createSimpleUpdateWatcher('location');

        $scope.status_list = [];
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

            angular.forEach(perCnCopies, function (v, k) {
                cnHash[k].copies(v);
            });

            cnList = [];
            angular.forEach(cnHash, function (v, k) {
                cnList.push(v);
            });

            egNet.request(
                'open-ils.cat',
                'open-ils.cat.asset.volume.fleshed.batch.update.override',
                egCore.auth.token(), cnList, 1, { auto_merge_vols : 1, create_parts : 1 }
            ).then(function(update_count) {
                if (and_exit) {
                    $scope.dirty = false;
                    $timeout(function(){$window.close()});
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

        return $modal.open({
            templateUrl: './cat/volcopy/t_copy_notes',
            animation: true,
            controller:
                   ['$scope','$modalInstance',
            function($scope , $modalInstance) {
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
                    $scope.require_initials = Boolean(set['ui.staff.require_initials.copy_notes']);
                });

                $scope.note_list = [];
                if (copy_list.length == 1) {
                    $scope.note_list = copy_list[0].notes();
                }

                $scope.ok = function(note) {

                    if (note.initials) note.value += ' [' + note.initials + ']';
                    angular.forEach(copy_list, function (cp) {
                        if (!angular.isArray(cp.notes())) cp.notes([]);
                        var n = new egCore.idl.acpn();
                        n.isnew(1);
                        n.creator(note.creator);
                        n.pub(note.pub);
                        n.title(note.title);
                        n.value(note.value);
                        n.owning_copy(cp.id());
                        cp.notes().push( n );
                    });

                    $modalInstance.close();
                }

                $scope.cancel = function($event) {
                    $modalInstance.dismiss();
                    $event.preventDefault();
                }
            }]
        });
    }

}])

.directive("egVolTemplate", function () {
    return {
        restrict: 'E',
        replace: true,
        template: '<div ng-include="'+"'/eg/staff/cat/volcopy/t_attr_edit'"+'"></div>',
        scope: { },
        controller : ['$scope','$window','itemSvc','egCore',
            function ( $scope , $window , itemSvc , egCore ) {

                $scope.defaults = { // If defaults are not set at all, allow everything
                    barcode_checkdigit : false,
                    auto_gen_barcode : false,
                    statcats : true,
                    copy_notes : true,
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
                    egCore.hatch.getItem('cat.copy.templates').then(function(t) {
                        if (t) {
                            $scope.templates = t;
                            $scope.template_name_list = Object.keys(t);
                        }
                    });
                }
                $scope.fetchTemplates();
            
                $scope.applyTemplate = function (n) {
                    angular.forEach($scope.templates[n], function (v,k) {
                        if (k == 'circ_lib') {
                            $scope.working[k] = egCore.org.get(v);
                        } else if (!angular.isObject(v)) {
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
                        $scope.template_name_list = Object.keys($scope.templates);
                        $scope.template_name = '';
                        egCore.hatch.setItem('cat.copy.templates', $scope.templates);
                        $scope.$parent.fetchTemplates();
                    }
                }

                $scope.saveTemplate = function (n) {
                    if (n) {
                        var tmpl = {};
            
                        angular.forEach($scope.working, function (v,k) {
                            if (angular.isObject(v)) { // we'll use the pkey
                                if (v.id) v = v.id();
                                else if (v.code) v = v.code();
                            }
            
                            tmpl[k] = v;
                        });
            
                        $scope.templates[n] = tmpl;
                        $scope.template_name_list = Object.keys($scope.templates);
            
                        egCore.hatch.setItem('cat.copy.templates', $scope.templates);
                        $scope.$parent.fetchTemplates();

                        $scope.dirty = false;
                    } else {
                        // save all templates, as we might do after an import
                        egCore.hatch.setItem('cat.copy.templates', $scope.templates);
                        $scope.$parent.fetchTemplates();
                    }
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
                            $scope.templates = newTemplates;
                            $scope.template_name_list = Object.keys(newTemplates);
                            $scope.template_name = '';
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
                        } else if (k != 'circ_lib') {
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
                itemSvc.get_locations(
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
            
                $scope.status_list = [];
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


