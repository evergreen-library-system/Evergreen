angular.module('egCheckinApp', ['ngRoute', 'ui.bootstrap', 
    'egCoreMod', 'egUiMod', 'egGridMod', 'egUserMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
    var resolver = {delay : 
        ['egStartup', function(egStartup) {return egStartup.go()}]}

    $routeProvider.when('/circ/checkin/checkin', {
        templateUrl: './circ/checkin/t_checkin',
        controller: 'CheckinCtrl',
        resolve : resolver
    });

    $routeProvider.when('/circ/checkin/capture', {
        templateUrl: './circ/checkin/t_checkin',
        controller: 'CheckinCtrl',
        resolve : resolver
    });

    $routeProvider.otherwise({redirectTo : '/circ/checkin/checkin'});
})

.factory('checkinSvc', [function() {
    var service = {};
    service.checkins = [];
    return service;
}])


/**
 * Manages checkin
 */
.controller('CheckinCtrl',
       ['$scope','$q','$window','$location', '$timeout','egCore','checkinSvc','egGridDataProvider','egCirc', 'egItem',
function($scope , $q , $window , $location , $timeout , egCore , checkinSvc , egGridDataProvider , egCirc, itemSvc)  {

    $scope.focusMe = true;
    $scope.checkins = checkinSvc.checkins;
    var today = new Date();
    $scope.checkinArgs = {backdate : today}
    $scope.modifiers = {};
    $scope.fine_total = 0;
    $scope.is_capture = $location.path().match(/capture$/);
    var suppress_popups = false;
    $scope.grid_persist_key = $scope.is_capture ? 
        'circ.checkin.capture' : 'circ.checkin.checkin';

    egCore.hatch.usePrinting().then(function(useHatch) {
        $scope.using_hatch_printer = useHatch;
    });

    // TODO: add this to the setting batch lookup below
    egCore.hatch.getItem('circ.checkin.strict_barcode')
        .then(function(sb){ $scope.strict_barcode = sb });

    egCore.org.settings([
        'ui.circ.suppress_checkin_popups' // add other settings as needed
    ]).then(function(set) {
        suppress_popups = set['ui.circ.suppress_checkin_popups'];
    });

    $scope.sort_money = function (a,b) {
        var ma = parseFloat(a);
        var mb = parseFloat(b);
        if (ma < mb) return -1;
        if (ma > mb) return 1;
        return 0
    }

    // checkin & hold capture modifiers
    var modifiers = [
        'void_overdues', 
        'clear_expired',
        'hold_as_transit',
        'manual_float',
        'no_precat_alert',
        'retarget_holds',
        'retarget_holds_all'
    ];

    if ($scope.is_capture) {
        // in hold capture mode, some values are forced, regardless
        // of stored preferences.
        $scope.modifiers.noop = false;
        $scope.modifiers.auto_print_holds_transits = true;
    } else {
        modifiers.push('noop'); // AKA suppress holds and transits
        modifiers.push('auto_print_holds_transits');
        modifiers.push('do_inventory_update');
    }

    // set modifiers from stored preferences
    var snames = modifiers.map(function(m) {return 'eg.circ.checkin.' + m;});
    egCore.hatch.getItemBatch(snames).then(function(settings) {
        angular.forEach(settings, function(val, key) {
            if (val === true) {
                var parts = key.split('.')
                var mod = parts.pop();
                $scope.modifiers[mod] = true;
            }
        })
    });

    // set / unset a checkin modifier
    // when set, store the preference
    $scope.toggle_mod = function(mod) {
        if ($scope.modifiers[mod]) {
            $scope.modifiers[mod] = false;
            egCore.hatch.removeItem('eg.circ.checkin.' + mod);
        } else {
            $scope.modifiers[mod] = true;
            egCore.hatch.setItem('eg.circ.checkin.' + mod, true);
        }
    }


    // ensure the backdate is not in the future
    // note: input type=date max=foo not yet supported anywhere
    $scope.$watch('checkinArgs.backdate', function(newval) {
        if (newval && newval > today) 
            $scope.checkinArgs.backdate = today;
    });

    $scope.is_backdate = function() {
        return $scope.checkinArgs.backdate < today;
    }

    var checkinGrid = $scope.gridControls = {};

    $scope.gridDataProvider = egGridDataProvider.instance({
        get : function(offset, count) {
            return this.arrayNotifier($scope.checkins, offset, count);
        }
    });

    // turns the various inputs (form args, modifiers, etc.) into
    // checkin params and options.
    function compile_checkin_args(args) {
        var params = angular.copy(args);

        // a backdate of 'today' is not really a backdate
        // (and this particularly matters when checking in hourly
        // loans, as backdated checkins currently get the time
        // portion of the checkin time from the due date; this will
        // stop mattering when FIXME bug 1793817 is dealt with)
        if (!$scope.is_backdate())
            delete params.backdate;

        if (params.backdate) {
            params.backdate = 
                params.backdate.toISOString().replace(/T.*/,'');
        }

        angular.forEach(['noop','void_overdues',
                'clear_expired','hold_as_transit','manual_float'],
            function(opt) {
                if ($scope.modifiers[opt]) params[opt] = true;
            }
        );

        if ($scope.modifiers.retarget_holds) {
            if ($scope.modifiers.retarget_holds_all) {
                params.retarget_mode = 'retarget.all';
            } else {
                params.retarget_mode = 'retarget';
            }
        }
        if ($scope.modifiers.do_inventory_update) params.do_inventory_update = true;

        egCore.hatch.setItem('circ.checkin.strict_barcode', $scope.strict_barcode);
        egCore.hatch.setItem('circ.checkin.do_inventory_update', $scope.modifiers.do_inventory_update);
        var options = {
            check_barcode : $scope.strict_barcode,
            no_precat_alert : $scope.modifiers.no_precat_alert,
            auto_print_holds_transits : 
                $scope.modifiers.auto_print_holds_transits,
            suppress_popups : suppress_popups,
            do_inventory_update : $scope.modifiers.do_inventory_update
        };

        return {params : params, options: options};
    }

    $scope.checkin = function(args) {

        var compiled = compile_checkin_args(args);
        args.copy_barcode = ''; // reset UI for next scan
        $scope.focusMe = true;
        delete $scope.alert;
        delete $scope.billable_amount;
        delete $scope.billable_barcode;
        delete $scope.billable_user_id;

        var params = compiled.params;
        var options = compiled.options;

        if (!params.copy_barcode) return;
        delete $scope.alert;

        var row_item = {
            index : checkinSvc.checkins.length,
            input_barcode : params.copy_barcode
        };

        // track the item in the grid before sending the request
        checkinSvc.checkins.unshift(row_item);
        egCirc.checkin(params, options).then(
        function(final_resp) {
            
            row_item.evt = final_resp.evt;
            angular.forEach(final_resp.data, function(val, key) {
                row_item[key] = val;
            });
            
            row_item['copy_barcode'] = row_item.acp.barcode();

            if (row_item.acp.latest_inventory() && row_item.acp.latest_inventory().inventory_date() == "now")
                row_item.acp.latest_inventory().inventory_date(Date.now());

            if (row_item.mbts) {
                var amt = Number(row_item.mbts.balance_owed());
                if (amt != 0) {
                    $scope.billable_barcode = row_item.copy_barcode;
                    $scope.billable_amount = amt;
                    $scope.billable_user_id = row_item.circ.usr();
                    $scope.fine_total = 
                        ($scope.fine_total * 100 + amt * 100) / 100;
                }
            }

            if (final_resp.evt.textcode == 'NO_CHANGE') {
                $scope.alert = 
                    {already_checked_in : final_resp.evt.copy_barcode};
            }

            if ($scope.trim_list && checkinSvc.checkins.length > 20) {
                //cut array short at 20 items
                checkinSvc.checkins.length = 20;
                checkinGrid.prepend(20);
            } else {
                checkinGrid.prepend();
            }
        },
        function() {
            // Checkin was rejected somewhere along the way.
            // Remove the copy from the grid since there was no action.
            // note: since checkins are unshifted onto the array, the
            // index value does not (generally) match the array position.
            var pos = -1;
            angular.forEach(checkinSvc.checkins, function(ci, idx) {
                if (ci.index == row_item.index) pos = idx;
            });
            checkinSvc.checkins.splice(pos, 1);

        })['finally'](function() {
            // when all is said and done, refocus
            $scope.focusMe = true;
        });
    }

    $scope.print_receipt = function() {
        var print_data = {checkins : []}

        if (checkinSvc.checkins.length == 0) return $q.when();

        angular.forEach(checkinSvc.checkins, function(checkin) {

            var checkin = {
                copy : egCore.idl.toHash(checkin.acp) || {},
                call_number : egCore.idl.toHash(checkin.acn) || {},
                copy_barcode : checkin.copy_barcode,
                title : checkin.title,
                author : checkin.author
            }

            print_data.checkins.push(checkin);
        });

        return egCore.print.print({
            template : 'checkin', 
            scope : print_data,
            show_dialog : $scope.show_print_dialog
        });
    }


    // --- context menu actions
    //
    $scope.fetchLastCircPatron = function(items) {
        var checkin = items[0];
        if (!checkin || !checkin.acp) return;

        egCirc.last_copy_circ(checkin.acp.id())
        .then(function(circ) {

            if (circ) {
                // jump to the patron UI (separate app)
                $window.location.href = $location
                    .path('/circ/patron/' + circ.usr() + '/checkout')
                    .absUrl();
                return;
            }

            $scope.alert = {item_never_circed : checkin.acp.barcode()};
        });
    }

    $scope.showBackdateDialog = function(items) {
        var circ_ids = [];

        angular.forEach(items, function(item) {
            if (item.circ) circ_ids.push(item.circ.id());
        });

        if (circ_ids.length) {
            egCirc.backdate_dialog(circ_ids).then(function(result) {
                angular.forEach(items, function(item) {
                    item.circ.checkin_time(result.backdate);
                })
            });
            // TODO: support grid row styling
            checkinGrid.refresh();
        }
    }

    $scope.showMarkDamaged = function(items) {
        var copy_ids = [];
        angular.forEach(items, function(item) {
            if (item.acp) {
                egCirc.mark_damaged({
                    id: item.acp.id(),
                    barcode: item.acp.barcode()
                })

            }
        });

    }

    $scope.showMarkDiscard = function(items) {
        var copies = [];
        angular.forEach(items, function(item) {
            if (item.acp) {
                copies.push(egCore.idl.toHash(item.acp));
            }
        });
        if (copies.length) {
            egCirc.mark_discard(copies).then(function() {
                // update grid items?
            });
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

    $scope.add_copies_to_bucket = function(items){
        var itemsIds = [];
        angular.forEach(items, function(cp){
            itemsIds.push(cp.acp.id());
        });

        itemSvc.add_copies_to_bucket(itemsIds);
    }

    $scope.showBibHolds = function(items){
        var recordIds = [];
        angular.forEach(items, function(i){
            recordIds.push(i.acn.record());
        });
        angular.forEach(recordIds, function (r) {
            var url = egCore.env.basePath + 'cat/catalog/record/' + r + '/holds';
            $timeout(function() { $window.open(url, '_blank') });
        });
    }

    $scope.showLastCircs = function(items){
        var itemIds = [];
        angular.forEach(items, function(cp){
            itemIds.push(cp.acp.id());
        });
        angular.forEach(itemIds, function (id) {
            var url = egCore.env.basePath + 'cat/item/' + id + '/circs';
            $timeout(function() { $window.open(url, '_blank') });
        });
    }

    $scope.selectedHoldingsVolCopyEdit = function (items) {
        var itemObjs = [];
        angular.forEach(items, function(i){
            var h = egCore.idl.toHash(i);
            itemObjs.push({
                'call_number.record.id': h.record.doc_id,
                'id' : h.acp.id
            });
        });
        itemSvc.spawnHoldingsEdit(itemObjs,false,false);
    }

    $scope.show_mark_missing_pieces = function(items){
        angular.forEach(items, function(i){
            i.acp.call_number(i.acn);
            i.acp.call_number().record(i.record);
            itemSvc.mark_missing_pieces(i.acp,$scope);
        });
    }

    $scope.printSpineLabels = function(items){
        var copy_ids = [];
        angular.forEach(items, function(item) {
            if (item.acp) copy_ids.push(item.acp.id());
        });
        itemSvc.print_spine_labels(copy_ids);
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

}])

