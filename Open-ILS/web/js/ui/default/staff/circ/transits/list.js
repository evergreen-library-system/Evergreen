angular.module('egTransitListApp', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

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
       ['$scope','$q','$routeParams','$window','egCore','egTransits','egGridDataProvider',
function($scope , $q , $routeParams , $window , egCore , egTransits , egGridDataProvider) {

    var transits = [];
    var provider = egGridDataProvider.instance({});
    $scope.grid_data_provider = provider;
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

    $scope.grid_controls = {
        activateItem : load_item
    }

    function refresh_page() {
        transits = [];
        provider.refresh();
    }

    provider.get = function(offset, count) {
        var deferred = $q.defer();
        var recv_index = 0;

        var filter = {
            'source_send_time' : { 'between' : date_range() }
        };
        if ($scope.transit_direction == 'to') { filter['dest'] = $scope.context_org.id(); }
        if ($scope.transit_direction == 'from') { filter['source'] = $scope.context_org.id(); }

        egCore.pcrud.search('atc',
            filter, {
                'flesh' : 5,
                // atc -> target_copy       -> call_number -> record -> simple_record
                // atc -> hold_transit_copy -> hold        -> usr    -> card
                'flesh_fields' : {
                    'atc' : ['target_copy','dest','source','hold_transit_copy'],
                    'acp' : ['call_number','location','circ_lib'],
                    'acn' : ['record'],
                    'bre' : ['simple_record'],
                    'ahtc' : ['hold'],
                    'ahr' : ['usr'],
                    'au' : ['card']
                },
                'select' : { 'bre' : ['id'] }
            }
        ).then(
            deferred.resolve, null, 
            function(transit) {
                transits[offset + recv_index++] = transit;
                deferred.notify(transit);
            }
        );

        return deferred.promise;
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
}])

