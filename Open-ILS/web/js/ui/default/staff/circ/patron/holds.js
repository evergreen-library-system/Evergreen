/**
 * List of patron holds
 */

angular.module('egPatronApp').controller('PatronHoldsCtrl',

       ['$scope','$q','$routeParams','egCore','egUser','patronSvc',
        'egGridDataProvider','egHolds','$window','$location','egCirc','egHoldGridActions',
function($scope,  $q,  $routeParams,  egCore,  egUser,  patronSvc,  
        egGridDataProvider , egHolds , $window , $location , egCirc, egHoldGridActions) {

    $scope.initTab('holds', $routeParams.id);
    $scope.holds_display = 'main';
    $scope.detail_hold_id = $routeParams.hold_id;
    $scope.grid_actions = egHoldGridActions;

    function refresh_all() {
        patronSvc.refreshPrimary();
        patronSvc.holds = [];
        patronSvc.hold_ids = [];
        provider.refresh() 
    }
    $scope.grid_actions.refresh = refresh_all;

    $scope.show_main_list = function() {
        // don't need a full reset_page() to swap tabs
        $scope.holds_display = 'main';
        patronSvc.holds = [];
        patronSvc.hold_ids = [];
        provider.refresh();
    }

    $scope.show_alt_list = function() {
        // don't need a full reset_page() to swap tabs
        $scope.holds_display = 'alt';
        patronSvc.holds = [];
        patronSvc.hold_ids = [];
        provider.refresh();
    }

    $scope.hide_cancel_hold = function(action) { 
        return $scope.holds_display == 'alt';
    }

    $scope.hide_uncancel_hold = function(action) {
        return !$scope.hide_cancel_hold();
    }

    var provider = egGridDataProvider.instance({});
    $scope.gridDataProvider = provider;

    function fetchHolds(offset, count) {
        var ids = patronSvc.hold_ids.slice(offset, offset + count);
        return egHolds.fetch_holds(ids).then(null, null,
            function(hold_data) { 
                patronSvc.holds.push(hold_data);
                return hold_data;
            }
        );
    }

    provider.get = function(offset, count) {

        // see if we have the requested range cached
        if (patronSvc.holds[offset]) {
            return provider.arrayNotifier(patronSvc.holds, offset, count);
        }

        // see if we have the holds IDs for this range already loaded
        if (patronSvc.hold_ids[offset]) {
            return fetchHolds(offset, count);
        }

        var deferred = $q.defer();
        patronSvc.hold_ids = [];

        var method = 'open-ils.circ.holds.id_list.retrieve.authoritative';
        if ($scope.holds_display == 'alt')
            method = 'open-ils.circ.holds.canceled.id_list.retrieve.authoritative';

        egCore.net.request(
            'open-ils.circ', method,
            egCore.auth.token(), $scope.patron_id

        ).then(function(hold_ids) {
            if (!hold_ids.length) { deferred.resolve(); return; }

            patronSvc.hold_ids = hold_ids;
            fetchHolds(offset, count)
            .then(deferred.resolve, null, deferred.notify);
        });

        return deferred.promise;
    }

    $scope.print = function() {
        var holds = [];
        angular.forEach(patronSvc.holds, function(item) {
            holds.push({
                hold : egCore.idl.toHash(item.hold),
                copy : egCore.idl.toHash(item.copy),
                volume : egCore.idl.toHash(item.volume),
                title : item.mvr.title(),
                author : item.mvr.author()
            });
        });

        egCore.print.print({
            context : 'receipt', 
            template : 'holds_for_patron', 
            scope : {holds : holds}
        });
    }

    $scope.detail_view = function(action, user_data, items) {
        if (h = items[0]) {
            $location.path('/circ/patron/' + 
                $scope.patron_id + '/holds/' + h.hold.id());
        }
    }

    $scope.list_view = function(items) {
        $location.path('/circ/patron/' + $scope.patron_id + '/holds');
    }

    $scope.place_hold = function() {
        $location.path($location.path() + '/create');
    }

    // when the detail hold is fetched (and updated), update the bib
    // record summary display record id.
    $scope.set_hold = function(hold_data) {
        $scope.detail_hold_record_id = hold_data.mvr.doc_id();
    }

}])


.controller('PatronHoldsCreateCtrl',
       ['$scope','$routeParams','$location','egCore','patronSvc',
function($scope , $routeParams , $location , egCore , patronSvc) {

    $scope.handlers = {
        opac_hold_placed : function() {
            // FIXME: this isn't getting called.. not sure why
            patronSvc.fetchUserStats(); // update hold counts
        }
    }

    $scope.initTab('holds', $routeParams.id).then(function(isAlert) {
        if (isAlert) return;
        // not guarenteed to have a barcode until init fetches the user
        $scope.handlers.patron_barcode = patronSvc.current.card().barcode();
    });

    $scope.catalog_url = 
        $location.absUrl().replace(/\/staff.*/, '/opac/advanced');

    $scope.handle_page = function(url) {
    }

}])
 
