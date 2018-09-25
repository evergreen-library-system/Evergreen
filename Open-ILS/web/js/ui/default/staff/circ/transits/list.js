angular.module('egTransitListApp', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
    var resolver = {delay : 
        ['egStartup', function(egStartup) {return egStartup.go()}]}

    $routeProvider.when('/circ/transits/list', {
        templateUrl: './circ/transits/t_list',
        controller: 'TransitListCtrl',
        resolve : resolver
    });

    $routeProvider.otherwise({redirectTo : '/circ/transits/list'});
})

.controller('TransitListCtrl',
       ['$scope','$q','$routeParams','$window','egCore','egTransits','egGridDataProvider','$uibModal','$timeout',
function($scope , $q , $routeParams , $window , egCore , egTransits , egGridDataProvider , $uibModal , $timeout) {

    $scope.transit_direction = 'to';

    function init_dates() {
        // setup date filters
        var start = new Date(); // midnight this morning
        start.setHours(0);
        start.setMinutes(0);
        var end = new Date(); // near midnight tonight
        end.setHours(23);
        end.setMinutes(59);
        $scope.dates = {
            start_date : start,
            end_date : new Date()
        }
    }
    init_dates();

    function date_range() {
        if ($scope.dates.start_date > $scope.dates.end_date) {
            var tmp = $scope.dates.start_date;
            $scope.dates.start_date = $scope.dates.end_date;
            $scope.dates.end_date = tmp;
        }
        $scope.dates.start_date.setHours(0);
        $scope.dates.start_date.setMinutes(0);
        $scope.dates.end_date.setHours(23);
        $scope.dates.end_date.setMinutes(59);
        try {
            var start = $scope.dates.start_date.toISOString().replace(/T.*/,'');
            var end = $scope.dates.end_date.toISOString().replace(/T.*/,'');
        } catch(E) { // handling empty date widgets; maybe dangerous if something else can happen
            init_dates();
            return date_range();
        }
        var today = new Date().toISOString().replace(/T.*/,'');
        if (end == today) end = 'now';
        return [start, end];
    }

    function load_item(transits) {
        if (!transits) return;
        if (!angular.isArray(transits)) transits = [transits];
        angular.forEach(transits, function(transit) {
            $window.open(
                egCore.env.basePath + '/cat/item/' +
                transit.target_copy().id(),
                '_blank'
            ).focus()
        });
    }

    $scope.load_item = function(action, data, transits) {
        load_item(transits);
    }

    function abort_transit(transits) {
        if (!transits) return;
        if (!angular.isArray(transits)) transits = [transits];
        if (transits.length == 0) return;
        egTransits.abort_transits( transits, refresh_page );
    }

    $scope.abort_transit = function(action, date, transits) {
        abort_transit(transits);
    }

    $scope.add_copies_to_bucket = function() {
        var copy_list = [];
        angular.forEach($scope.grid_controls.selectedItems(), function(transit) {
            copy_list.push(transit['target_copy.id']);
        });
        if (copy_list.length == 0) return;

        // FIXME what follows ought to be refactored into a factory
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


    function gatherSelectedRecordIds () {
        var rid_list = [];
        angular.forEach(
            $scope.grid_controls.selectedItems(),
            function (item) {
                if (rid_list.indexOf(item['target_copy.call_number.record.simple_record.id']) == -1)
                    rid_list.push(item['target_copy.call_number.record.simple_record.id']);
            }
        );
        return rid_list;
    }
    function gatherSelectedHoldingsIds (rid) {
        var cp_id_list = [];
        angular.forEach(
            $scope.grid_controls.selectedItems(),
            function (item) {
                if (rid && item['target_copy.call_number.record.simple_record.id'] != rid) return;
                cp_id_list.push(item['target_copy.id']);
            }
        );
        return cp_id_list;
    }

    var spawnHoldingsEdit = function (hide_vols, hide_copies){
        angular.forEach(gatherSelectedRecordIds(), function (r) {
            egCore.net.request(
                'open-ils.actor',
                'open-ils.actor.anon_cache.set_value',
                null, 'edit-these-copies', {
                    record_id: r,
                    copies: gatherSelectedHoldingsIds(r),
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
   
    $scope.edit_copies = function() { 
        spawnHoldingsEdit(true, false);
    }

    function current_query() {
        var filter = {
            'source_send_time' : { 'between' : date_range() },
            'dest_recv_time'   : null,
            'cancel_time'      : null
        };
        if ($scope.transit_direction == 'to') { filter['dest'] = $scope.context_org.id(); }
        if ($scope.transit_direction == 'from') { filter['source'] = $scope.context_org.id(); }
        return filter;
    }

    $scope.grid_controls = {
        activateItem : load_item,
        setQuery : current_query
    }

    function refresh_page() {
        $scope.grid_controls.setQuery(current_query());
        $scope.grid_controls.refresh();
    }

    $scope.context_org = egCore.org.get(egCore.auth.user().ws_ou());
    $scope.$watch('context_org', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) refresh_page();
    });
    $scope.$watch('transit_direction', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) refresh_page();
    });
    $scope.$watch('dates.start_date', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) refresh_page();
    });
    $scope.$watch('dates.end_date', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) refresh_page();
    });

    function fetch_all_matching_transits(transits) {
        var deferred = $q.defer();
        var filter = current_query();
        egCore.pcrud.search('atc',
            filter, {
                'flesh' : 5,
                // atc -> target_copy       -> call_number -> record -> simple_record
                // atc -> hold_transit_copy -> hold        -> usr    -> card
                'flesh_fields' : {
                    'atc' : ['target_copy','dest','source','hold_transit_copy'],
                    'acp' : ['call_number','location','circ_lib'],
                    'acn' : ['record', 'prefix', 'suffix'],
                    'bre' : ['simple_record'],
                    'ahtc' : ['hold'],
                    'ahr' : ['usr'],
                    'au' : ['card']
                },
                'select' : { 'bre' : ['id'] },
                order_by : { atc : 'source_send_time' },
            }
        ).then(
            deferred.resolve, null,
            function(transit) {
                transits.push(egCore.idl.toHash(transit));
            }
        );
        return deferred.promise;
    }

    $scope.print_full_list = function() {
        var print_data = { transits : [] };

        return fetch_all_matching_transits(print_data.transits).then(function() {
            if (print_data.transits.length == 0) return $q.when();
            return egCore.print.print({
                template : 'transit_list',
                scope : print_data
            });
        });

    }
}])

