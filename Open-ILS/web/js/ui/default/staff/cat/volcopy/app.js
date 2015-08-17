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

})

.factory('itemSvc', 
       ['egCore','$q',
function(egCore , $q) {

    var service = {
        tree : {}, // holds lib->cn->copy hash stack
        copies : [] // raw copy list
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
        if (egCore.env.acnp)
            return $q.when(egCore.env.acnp.list);

        return egCore.pcrud.search('acnp',
            {owning_lib : egCore.org.fullPath(org, true)},
            null, {atomic : true}
        ).then(function(list) {
            egCore.env.absorbList(list, 'acnp');
            return list;
        });

    };

    service.get_suffixes = function(org) {
        if (egCore.env.acns)
            return $q.when(egCore.env.acns.list);

        return egCore.pcrud.search('acns',
            {owning_lib : egCore.org.fullPath(org, true)},
            null, {atomic : true}
        ).then(function(list) {
            egCore.env.absorbList(list, 'acns');
            return list;
        });

    };

    service.get_statuses = function() {
        if (egCore.env.ccs)
            return $q.when(egCore.env.ccs.list);

        return egCore.pcrud.retrieveAll('ccs', {}, {atomic : true}).then(
            function(list) {
                egCore.env.absorbList(list, 'ccs');
                return list;
            }
        );

    };

    service.bmp_parts = {};
    service.get_parts = function(rec) {
        if (service.bmp_parts[rec])
            return $q.when(service.bmp_parts[rec]);

        return egCore.pcrud.search('bmp',
            {record : rec},
            null, {atomic : true}
        ).then(function(list) {
            service.bmp_parts[rec] = list;
            return list;
        });

    };

    service.flesh = {   
        flesh : 3, 
        flesh_fields : {
            acp : ['call_number','parts','location'],
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

    return service;
}])

.directive("egVolCopyEdit", function () {
    return {
        restrict: 'E',
        replace: true,
        template:
            '<div class="row">'+
                '<div class="col-xs-6"><input type="text" ng-model="barcode" ng-change="updateBarcode()"/></div>'+
                '<div class="col-xs-2"><input type="number" ng-model="copy_number" ng-change="updateCopyNo()"/></div>'+
                '<div class="col-xs-4"><eg-basic-combo-box list="parts" selected="part"></eg-basic-combo-box></div>'+
            '</div>',

        scope: { copy: "=", callNumber: "=" },
        controller : ['$scope','itemSvc',
            function ( $scope , itemSvc ) {
                $scope.new_part_id = 0;

                $scope.updateBarcode = function () { $scope.copy.barcode($scope.barcode); $scope.copy.ischanged(1); };
                $scope.updateCopyNo = function () { $scope.copy.copy_number($scope.copy_number); $scope.copy.ischanged(1); };
                $scope.updatePart = function () {
                    var p = angular.filter($scope.part_list, function (x) {
                        return x.label() == $scope.part
                    });
                    if (p.length > 0) { // preexisting part
                        $scope.copy.parts(p)
                    } else { // create one...
                        var part = new egCore.idl.bmp();
                        part.id( --$scope.new_part_id );
                        part.isnew( true );
                        part.label( $scope.part );
                        part.record( $scope.callNumber.owning_lib() );
                        $scope.copy.parts([part]);
                        $scope.copy.ischanged(1);
                    }
                }

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
                '<div class="col-xs-1">'+
                    '<select ng-model="classification" ng-options="cl.name() for cl in classification_list track by idTracker(cl)"/>'+
                '</div>'+
                '<div class="col-xs-1">'+
                    '<select ng-model="prefix" ng-change="updatePrefix()" ng-options="p.label() for p in prefix_list track by idTracker(p)"/>'+
                '</div>'+
                '<div class="col-xs-3"><input type="text" ng-change="updateLabel()" ng-model="label"/></div>'+
                '<div class="col-xs-1">'+
                    '<select ng-model="suffix" ng-change="updateSuffix()" ng-options="s.label() for s in suffix_list track by idTracker(s)"/>'+
                '</div>'+
                '<div class="col-xs-1"><input type="number" ng-model="copy_count" min="{{orig_copy_count}}" ng-change="changeCPCount()"></div>'+
                '<div class="col-xs-5">'+
                    '<div class="container-fluid">'+
                        '<eg-vol-copy-edit ng-repeat="cp in copies track by idTracker(cp)" copy="cp" call-number="callNumber"></eg-vol-copy-edit>'+
                    '</div>'+
                '</div>'+
            '</div>',

        scope: {allcopies: "=", copies: "=" },
        controller : ['$scope','itemSvc','egCore',
            function ( $scope , itemSvc , egCore ) {
                $scope.new_cp_id = 0;
                $scope.callNumber =  $scope.copies[0].call_number();

                $scope.idTracker = function (x) { if (x) return x.id() };

                $scope.suffix_list = [];
                itemSvc.get_suffixes($scope.callNumber.owning_lib()).then(function(list){
                    $scope.suffix_list = list;
                });
                $scope.updateSuffix = function () { $scope.callNumber.suffix($scope.suffix); $scope.callNumber.ischanged(1); };

                $scope.prefix_list = [];
                itemSvc.get_prefixes($scope.callNumber.owning_lib()).then(function(list){
                    $scope.prefix_list = list;
                });
                $scope.updatePrefix = function () { $scope.callNumber.prefix($scope.prefix); $scope.callNumber.ischanged(1); };

                $scope.classification_list = [];
                itemSvc.get_classifications().then(function(list){
                    $scope.classification_list = list;
                });
                $scope.updateClassification = function () { $scope.callNumber.label_class($scope.classification); $scope.callNumber.ischanged(1); };

                $scope.classification = $scope.callNumber.label_class();
                $scope.prefix = $scope.callNumber.prefix();
                $scope.suffix = $scope.callNumber.suffix();

                $scope.label = $scope.callNumber.label();
                $scope.updateLabel = function () { $scope.callNumber.label($scope.label); $scope.callNumber.ischanged(1); };

                $scope.copy_count = $scope.copies.length;
                $scope.orig_copy_count = $scope.copy_count;

                $scope.changeCPCount = function () {
                    while ($scope.copy_count > $scope.copies.length) {
                        var cp = new egCore.idl.acp();
                        cp.id( --$scope.new_cp_id );
                        cp.isnew( true );
                        cp.circ_lib( $scope.lib );
                        cp.call_number( $scope.callNumber );
                        $scope.copies.push( cp );
                        $scope.allcopies.push( cp );
                    }

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
        ]

    }
})

.directive("egVolEdit", function () {
    return {
        restrict: 'E',
        replace: true,
        template:
            '<div class="row">'+
                '<div class="col-xs-1"><eg-org-selector selected="owning_lib" disableTest="cant_have_vols"></eg-org-selector></div>'+
                '<div class="col-xs-1"><input type="number" min="{{orig_cn_count}}" ng-model="cn_count" ng-change="changeCNCount()"/></div>'+
                '<div class="col-xs-10">'+
                    '<div class="container-fluid">'+
                        '<eg-vol-row ng-repeat="(cn,copies) in struct track by cn" copies="copies" allcopies="allcopies"></eg-vol-row>'+
                    '</div>'+
                '</div>'+
            '</div>',

        scope: { allcopies: "=", struct: "=", lib: "@", record: "@" },
        controller : ['$scope','itemSvc','egCore',
            function ( $scope , itemSvc , egCore ) {
                $scope.new_cn_id = 0;
                $scope.first_cn = Object.keys($scope.struct)[0];
                $scope.full_cn = $scope.struct[$scope.first_cn][0].call_number();

                $scope.cn_count = Object.keys($scope.struct).length;
                $scope.orig_cn_count = $scope.cn_count;

                $scope.owning_lib = egCore.org.get($scope.lib);

                $scope.cant_have_vols = function (id) { return !egCore.org.CanHaveVolumes(id); };

                $scope.$watch('cn_count', function (n) {
                    var o = Object.keys($scope.struct).length;
                    if (n > o) { // adding
                        for (var i = o; o < n; o++) {
                            var cn = new egCore.idl.acn();
                            cn.id( --$scope.new_cn_id );
                            cn.isnew( true );
                            cn.owning_lib( $scope.owning_lib );
                            cn.record( $scope.full_cn.record() );

                            var cp = new egCore.idl.acp();
                            cp.id( --$scope.new_cp_id );
                            cp.isnew( true );
                            cp.circ_lib( $scope.owning_lib );
                            cp.call_number( cn );

                            $scope.struct[cn.id()] = [cp];
                            $scope.allcopies.push(cp);
                        }
                    } else if (n < o) { // removing
                        var how_many = o - n;
                        var list = Object
                                .keys($scope.struct)
                                .sort(function(a, b){return a-b})
                                .reverse();
                        for (var i = how_many; i > 0; i--) {
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
       ['$scope','$q','$routeParams','$location','$timeout','egCore','egNet','egGridDataProvider','itemSvc',
function($scope , $q , $routeParams , $location , $timeout , egCore , egNet , egGridDataProvider , itemSvc) {

    $scope.show_vols = true;
    $scope.show_copies = true;

    $scope.idTracker = function (x) { if (x) return x.id() };

    $timeout(function(){

    var dataKey = $routeParams.dataKey;
    console.debug('dataKey: ' + dataKey);

    if (dataKey && dataKey.length > 0) {
        $scope.working = {};

        $scope.tab = 'edit';
        $scope.summaryRecord = null;
        $scope.record_id = null;
        $scope.data = {};

        $scope.workingGridDataProvider = egGridDataProvider.instance({
            get : function(offset, count) {
                //return provider.arrayNotifier(itemSvc.copies, offset, count);
                return this.arrayNotifier(itemSvc.copies, offset, count);
            }
        });

        $scope.workingGridControls = {};

        egNet.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.get_value',
            dataKey, 'edit-these-copies'
        ).then(function (data) {

            if (data.hide_vols) $scope.show_vols = false;
            if (data.hide_copies) $scope.show_copies = false;

            $scope.record_id = data.record_id;

            if (data.copies && data.copies.length)
                return itemSvc.fetchIds(data.copies);

            if (data.raw && data.raw.length) {

                /* data.raw must be an array of copies with (at least)
                 * the call number fleshed on each.  For new copies
                 * create from whole cloth, the id for each should
                 * probably be negative and isnew() should return true.
                 * Each /distinct/ call number must have a distinct id
                 * as well, probably negative also if they're new. Clear?
                 */

                angular.forEach(
                    data.raw,
                    function (cp) { itemSvc.addCopy(cp) }
                );

                return itemSvc.copies;
            }

        }).then( function() {
            $scope.data = itemSvc;
            $scope.workingGridDataProvider.refresh();
        });

        $scope.$watch('data.copies.length', function () {
            console.log('data.copies.length changed');
            $scope.workingGridDataProvider.refresh();
        });

        $scope.status_list = [];
        itemSvc.get_statuses().then(function(list){
            $scope.status_list = list;
        });
        $scope.updateWorkingStatus = function () {
            angular.forEach(
                $scope.workingGridControls.selectedItems(),
                function (cp) { cp.status($scope.working.status.id()); cp.ischanged(1); }
            );
        };
    }

    });

}])


