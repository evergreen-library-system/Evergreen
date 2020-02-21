/**
 * Renewal
 */

angular.module('egRenewApp', 
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export    
	
	var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/circ/renew/renew', {
        templateUrl: './circ/renew/t_renew',
        controller: 'RenewCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/renew/renew', {
        templateUrl: './circ/renew/t_renew',
        controller: 'RenewCtrl',
        resolve : resolver
    });
    
    $routeProvider.otherwise({redirectTo : '/circ/renew/renew'});
})




.controller('RenewCtrl',
       ['$scope','$window','$location','egCore','egGridDataProvider','egCirc',
function($scope , $window , $location , egCore , egGridDataProvider , egCirc) {
    var now = new Date();

    egCore.hatch.getItem('circ.renew.strict_barcode')
        .then(function(sb){ $scope.strict_barcode = sb });
    $scope.focusBarcode = true;
    $scope.outOfRange = false;
    $scope.minDate = new Date(now);
    $scope.renewals = [];

    $scope.renewalArgs = {due_date : new Date(now)};

    $scope.sort_money = function (a,b) {
        var ma = parseFloat(a);
        var mb = parseFloat(b);
        if (ma < mb) return -1;
        if (ma > mb) return 1;
        return 0
    }

    $scope.gridDataProvider = egGridDataProvider.instance({
        get : function(offset, count) {
            return this.arrayNotifier($scope.renewals, offset, count);
        }
    });

    // avoid multiple, in-flight attempts on the same barcode
    var pending_barcodes = {};

    $scope.renew = function(args) {
        var params = angular.copy(args);

        if (args.sticky_date) {
            params.due_date = args.due_date.toISOString();
        } else {
            delete params.due_date;
        }
        delete params.sticky_date;
         if (!args.copy_barcode) return;

        args.copy_barcode = ''; // reset UI input

        if (pending_barcodes[params.copy_barcode]) {
            console.log(
                "Skipping renewals of redundant barcode " 
                + params.copy_barcode
            );
            return;
        }

        pending_barcodes[params.copy_barcode] = true;
        send_renewal(params);

        $scope.focusBarcode = true; // return focus to barcode input
    }

    function send_renewal(params) {

        params.noncat_type = params.noncat ? params.noncat_type : '';

        // populate the grid row before we send the request so that the
        // order of actions is maintained and so the user gets an 
        // immediate reaction to their barcode input action.
        var row_item = {
            index : $scope.renewals.length,
            input_barcode : params.copy_barcode,
            noncat_type : params.noncat_type
        };

        $scope.renewals.unshift(row_item);
        $scope.gridDataProvider.refresh();

        egCore.hatch.setItem('circ.renew.strict_barcode', $scope.strict_barcode);
        var options = {check_barcode : $scope.strict_barcode};

        egCirc.renew(params, options).then(
            function(final_resp) {

                row_item.evt = final_resp.evt;
                angular.forEach(final_resp.data, function(val, key) {
                    row_item[key] = val;
                });

                row_item['copy_barcode'] = row_item.acp.barcode();

                if (row_item.mbts) {
                    var amt = Number(row_item.mbts.balance_owed());
                    if (amt != 0) {
                        $scope.billable_barcode = row_item.copy_barcode;
                        $scope.billable_amount = amt;
                        $scope.fine_total = 
                            ($scope.fine_total * 100 + amt * 100) / 100;
                    }
                }

                if ($scope.trim_list && checkinSvc.checkins.length > 20)
                    checkinSvc.checkins = checkinSvc.checkins.splice(0, 20);

            },
            function() {
                // Circ was rejected somewhere along the way.
                // Remove the copy from the grid since there was no action.
                // note: since renewals are unshifted onto the array, the
                // index value does not (generally) match the array position.
                var pos = -1;
                angular.forEach($scope.renewals, function(co, idx) {
                    if (co.index == row_item.index) pos = idx;
                });
                $scope.renewals.splice(pos, 1);
                $scope.gridDataProvider.refresh();
            }

        )['finally'](function() {

            // regardless of the outcome of the circ, remove the 
            // barcode from the pending list.
            if (params.copy_barcode)
                delete pending_barcodes[params.copy_barcode];
        });
    }

    $scope.fetchLastCircPatron = function(items) {
        var renewal = items[0];
        if (!renewal || !renewal.acp) return;

        egCirc.last_copy_circ(renewal.acp.id())
        .then(function(circ) {

            if (circ) {
                // jump to the patron UI (separate app)
                $window.location.href = $location
                    .path('/circ/patron/' + circ.usr() + '/checkout')
                    .absUrl();
                return;
            }

            $scope.alert = {item_never_circed : renewal.acp.barcode()};
        });
    }

    $scope.showMarkDamaged = function(items) {
        var copy_ids = [];
        angular.forEach(items, function(item) {
            if (item.acp) copy_ids.push(item.acp.id());
        });

        if (copy_ids.length) {
            egCirc.mark_damaged(copy_ids).then(function() {
                // update grid items?
            });
        }
    }

    $scope.showMarkDiscard = function(items) {
        var copies = [];
        angular.forEach(items, function(item) {
            if (item.acp) copies.push(egCore.idl.toHash(item.acp));
        });

        if (copies.length) {
            egCirc.mark_discard(copies).then(function() {
                // update grid items?
            });
        }
    }

    $scope.showLastFewCircs = function(items) {
        if (items.length && (copy = items[0].acp)) {
            var url = $location.path(
                '/cat/item/' + copy.id() + '/circ_list').absUrl();
            $window.open(url, '_blank').focus();
        }
    }

    $scope.abortTransit = function(items) {
        var transit_ids = [];
        angular.forEach(items, function(item) {
            if (item.transit) transit_ids.push(item.transit.id());
        });

        egCirc.abort_transits(transit_ids).then(function() {
            // update grid items?
        });
    }

    $scope.addCopyAlerts = function(items) {
        var copy_ids = [];
        angular.forEach(items, function(item) {
            if (item.acp) copy_ids.push(item.acp.id());
        });
        egCirc.add_copy_alerts(copy_ids).then(function() {
            // update grid items?
        });
    }

    $scope.manageCopyAlerts = function(items) {
        var copy_ids = [];
        angular.forEach(items, function(item) {
            if (item.acp) copy_ids.push(item.acp.id());
        });
        egCirc.manage_copy_alerts(copy_ids).then(function() {
            // update grid items?
        });
    }

    $scope.print_receipt = function() {
        var print_data = {circulations : []}

        if ($scope.renewals.length == 0) return $q.when();

        angular.forEach($scope.renewals, function(renewal) {
            if (renewal.circ) {
                print_data.circulations.push({
                    circ : egCore.idl.toHash(renewal.circ),
                    copy : egCore.idl.toHash(renewal.acp),
                    title : egCore.idl.toHash(renewal.title),
                    author : egCore.idl.toHash(renewal.author)
                });
                // Flesh selected fields of this circulation 
                print_data.circulations[0].copy.call_number =
                    egCore.idl.toHash(renewal.acn);
                print_data.circulations[0].copy.owning_lib =
	            egCore.idl.toHash(renewal.aou);
            }
        });

        return egCore.print.print({
            context : 'default', 
            template : 'renew', 
            scope : print_data,
        });
    }
}])

