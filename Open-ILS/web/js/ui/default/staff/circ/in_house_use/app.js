angular.module('egInHouseUseApp', 
    ['ngRoute', 'egCoreMod', 'egUiMod', 'egGridMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export

})

.controller('InHouseUseCtrl',
       ['$scope','egCore','egGridDataProvider','egConfirmDialog', 
        'egAlertDialog','egBibDisplay',
function($scope , egCore , egGridDataProvider , egConfirmDialog, 
         egAlertDialog , egBibDisplay) {

    var countCap;
    var countMax;

    $scope.do_inventory_update = false;

    egCore.startup.go().then(function() {

        // grab our non-cat types after startup
        egCore.pcrud.search('cnct', 
            {owning_lib : 
                egCore.org.fullPath(egCore.auth.user().ws_ou(), true)},
            null, {atomic : true}
        ).then(function(list) { 
            egCore.env.absorbList(list, 'cnct');
            $scope.nonCatTypes = list 
        });

        // org settings for max and warning in-house-use counts
        
        egCore.org.settings([
            'ui.circ.in_house_use.entry_cap',
            'ui.circ.in_house_use.entry_warn',
            'circ.in_house_use.copy_alert',
            'circ.in_house_use.checkin_alert'
        ]).then(function(set) {
            countWarn = set['ui.circ.in_house_use.entry_warn'] || 20;
            $scope.countMax = countMax = 
                set['ui.circ.in_house_use.entry_cap'] || 99;
            $scope.copyAlert = copyAlert =
                set['circ.in_house_use.copy_alert'] || false;
            $scope.checkinAlert = checkinAlert =
                set['circ.in_house_use.checkin_alert'] || false;
        });

        egCore.hatch.getItem('eg.circ.in_house.do_inventory_update')
            .then(function(doInventoryUpdate) {
                $scope.do_inventory_update = doInventoryUpdate;
            });
    });

    $scope.bcFocus = true;
    $scope.args = {noncat_type : 'barcode', num_uses : 1, needsCountWarnModal: false };
    var checkouts = [];

    var provider = egGridDataProvider.instance({});
    provider.get = function(offset, count) {
        return provider.arrayNotifier(checkouts, offset, count);
    }
    $scope.gridDataProvider = provider;

    // currently selected non-cat type
    $scope.selectedNcType = function() {
        if (!egCore.env.cnct) return null; // too soon
        var type = egCore.env.cnct.map[$scope.args.noncat_type];
        return type ? type.name() : null;
    }

    $scope.onNumUsesChanged = function(){
        $scope.args.needsCountWarnModal = countWarn < $scope.args.num_uses;
    }

    $scope.checkout = function(args){
        if ($scope.args.needsCountWarnModal) {
            // show modal to allow warning/confirmation
            egConfirmDialog.open(egCore.strings.CONFIRM_IN_HOUSE_NUM_USES_COUNT_TITLE, '',
                { num_uses: $scope.args.num_uses }
            ).result.then(function(){
                $scope.args.needsCountWarnModal = false
                $scope.checkoutStart(args)
            });
        } else {
            $scope.checkoutStart(args);
        }
    }

    $scope.checkoutStart = function(args) {
        $scope.copyNotFound = false;

        var coArgs = {
            count : args.num_uses,
            'location' : egCore.auth.user().ws_ou()
        };

        if (args.noncat_type == 'barcode') {

            egCore.pcrud.search('acp',
                {barcode : args.barcode, deleted : 'f'},
                {   flesh : 3, 
                    flesh_fields : {
                        acp : ['call_number','location','status'],
                        acn : ['record', 'prefix', 'suffix'],
                        // We don't need to display a wide range of bib
                        // fields in this UI.  Fetch the flat display since
                        // it requires less DB-side munging (and as an example).  
                        bre : ['flat_display_entries']
                    },
                    select : { bre : ['id'] } // avoid fleshing MARC
                }
            ).then(function(copy) {

                if (!copy) {
                    egCore.audio.play('error.in_house.copy_not_found');
                    $scope.copyNotFound = true;
                    return;
                }

                coArgs.copyid = copy.id();

                if ($scope.do_inventory_update) {
                    coArgs.do_inventory_update = true;
                }

                copy.call_number().record().flat_display_entries(
                    egBibDisplay.mfdeToHash(
                        copy.call_number().record().flat_display_entries())
                );

                // LP1507807: Display the copy alert if the setting is on.
                if ($scope.copyAlert && copy.alert_message()) {
                    egAlertDialog.open(copy.alert_message()).result;
                }

                // LP1507807: Display the location alert if the setting is on.
                if ($scope.checkinAlert && copy.location().checkin_alert() == 't') {
                    egAlertDialog.open(egCore.strings.LOCATION_ALERT_MSG, {copy: copy}).result;
                }

                performCheckout(
                    'open-ils.circ.in_house_use.create',
                    coArgs, {copy:copy}
                );
            });

        } else {
            coArgs.non_cat_type = args.noncat_type;
            performCheckout(
                'open-ils.circ.non_cat_in_house_use.create',
                coArgs, {title : $scope.selectedNcType()}
            );
        }
        $scope.args.barcode='';
    }

    function performCheckout(method, args, data) {

        // FIXME: make this API stream
        egCore.net.request(
            'open-ils.circ', method, egCore.auth.token(), args

        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) {
                egCore.audio.play('error.in_house');
                return alert(evt);
            }

            egCore.audio.play('success.in_house');

            var item = {num_uses : resp.length};
            item.copy = data.copy;
            item.title = data.title || 
                data.copy.call_number().record().flat_display_entries().title;
            item.index = checkouts.length;

            checkouts.unshift(item);
            provider.refresh();
        });
    }

    $scope.print_list = function() {
        var print_data = { in_house_uses : [] };

        if (checkouts.length == 0) return $q.when();

        angular.forEach(checkouts, function(ihu) {
            print_data.in_house_uses.push({
                num_uses : ihu.num_uses,
                copy : egCore.idl.toHash(ihu.copy),
                title : ihu.title
            })
        });

        return egCore.print.print({
            template : 'in_house_use_list',
            scope : print_data
        });
    }

    $scope.toggle_do_inventory_update = function() {
        var key = 'eg.circ.in_house.do_inventory_update';
        if ($scope.do_inventory_update) {
            egCore.hatch.setItem(key, true);
        } else {
            egCore.hatch.removeItem(key);
        }
    };

    $scope.isBarcodeMode = function() {
        return $scope.args.noncat_type === 'barcode';
    };

}])
