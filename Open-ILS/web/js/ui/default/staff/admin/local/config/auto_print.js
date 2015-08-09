
angular.module('egAdminConfig',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod','egUiMod'])

.controller('AutoPrintCtl',
       ['$scope','egCore',
function($scope , egCore) {

    $scope.allowed_orgs = [];
    $scope.cant_use_org = function(org_id) {
        return $scope.allowed_orgs.indexOf(org_id) == -1;
    }

    // The org setting stores the values as English words.
    // Map those to scope-storable bools
    var values_map = {
        co_recpt : 'Checkout',
        bill_recpt : 'Bill Pay',
        hold_slip : 'Hold Slip',
        transit_slip : 'Transit Slip',
        hold_transit_slip : 'Hold/Transit Slip'
    }

    // fetch and display values for the currently selected org unit
    $scope.show_org_values = function(org) {
        egCore.org.settings(
            ['circ.staff_client.do_not_auto_attempt_print'], org.id()
        ).then(function(values) { 
            list = values['circ.staff_client.do_not_auto_attempt_print'] || [];
            angular.forEach(values_map, function(val, key) {
                if (list.indexOf(val) > -1) {
                    $scope[key] = true;
                } else {
                    $scope[key] = false;
                }
            });
        });
    }

    function fetch_data() {
        // TODO: The XUL app tested the ADMIN_ORG_UNIT_SETTING_TYPE perm
        // to see wher the user could change the print settings.  There
        // should be a separate, less powerful permission that allows 
        // users to change this value.
        egCore.perm.hasPermAt(['ADMIN_ORG_UNIT_SETTING_TYPE'], true)
        .then(function(settings) { 
            $scope.allowed_orgs = settings.ADMIN_ORG_UNIT_SETTING_TYPE;
        });
        $scope.show_org_values(egCore.org.get(egCore.auth.user().ws_ou()));
    }

    $scope.update_auto_print = function() {
        $scope.in_flight = true;
        var values = [];
        angular.forEach(values_map, function(val, key) {
            if ($scope[key]) { values.push(val) }
        });

        console.log('updating for ' + $scope.context_org.id());
        egCore.net.request(
            'open-ils.actor',
            'open-ils.actor.org_unit.settings.update',
            egCore.auth.token(),
            $scope.context_org.id(),
            {"circ.staff_client.do_not_auto_attempt_print": values}
        ).then(function() {
            $scope.in_flight = false; // re-enable the submit button
        });
    }

    // This is a standalone with page w/ no startup resolver.
    // Kick off startup locally.
    egCore.startup.go().then(fetch_data);

}])
