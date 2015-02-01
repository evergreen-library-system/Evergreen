/**
 * Checkout items to patrons
 */

angular.module('egPatronApp').controller('PatronCheckoutCtrl',

       ['$scope','$q','$modal','$routeParams','egCore','egUser','patronSvc',
        'egGridDataProvider','$location','$timeout','egCirc',

function($scope , $q , $modal , $routeParams , egCore , egUser , patronSvc , 
         egGridDataProvider , $location , $timeout , egCirc) {

    $scope.initTab('checkout', $routeParams.id).finally(function(){
        $scope.focusMe = true;
    });
    $scope.checkouts = patronSvc.checkouts;
    $scope.checkoutArgs = {
        noncat_type : 'barcode',
        due_date : new Date()
    };

    $scope.gridDataProvider = egGridDataProvider.instance({
        get : function(offset, count) {
            return this.arrayNotifier($scope.checkouts, offset, count);
        }
    });

    $scope.disable_checkout = function() {
        return (
            !patronSvc.current ||
            patronSvc.current.active() == 'f' ||
            patronSvc.current.deleted() == 't' ||
            patronSvc.current.card().active() == 'f'
        );
    }

    $scope.using_hatch = egCore.hatch.usingHatch();

    egCore.hatch.getItem('circ.checkout.strict_barcode')
        .then(function(sb){ $scope.strict_barcode = sb });

    // avoid multiple, in-flight attempts on the same barcode
    var pending_barcodes = {};

    var printOnComplete = true;
    egCore.org.settings([
        'circ.staff_client.do_not_auto_attempt_print'
    ]).then(function(settings) { 
        printOnComplete = !Boolean(
            settings['circ.staff_client.do_not_auto_attempt_print']);
    });

    egCirc.get_noncat_types().then(function(list) {
        $scope.nonCatTypes = list;
    });

    $scope.selectedNcType = function() {
        if (!egCore.env.cnct) return null; // too soon
        var type = egCore.env.cnct.map[$scope.checkoutArgs.noncat_type];
        return type ? type.name() : null;
    }

    $scope.checkout = function(args) {
        var params = angular.copy(args);
        params.patron_id = patronSvc.current.id();

        if (args.sticky_date) {
            params.due_date = args.due_date.toISOString();
        } else {
            delete params.due_date;
        }
        delete params.sticky_date;

        if (params.noncat_type == 'barcode') {
            if (!args.copy_barcode) return;

            args.copy_barcode = ''; // reset UI input
            params.noncat_type = ''; // "barcode"

            if (pending_barcodes[params.copy_barcode]) {
                console.log(
                    "Skipping checkout of redundant barcode " 
                    + params.copy_barcode
                );
                return;
            }

            pending_barcodes[params.copy_barcode] = true;
            send_checkout(params);

        } else {
            egCirc.noncat_dialog(params).then(function() {
                send_checkout(params)
            });
        }

        $scope.focusMe = true; // return focus to barcode input
    }

    function send_checkout(params) {

        params.noncat_type = params.noncat ? params.noncat_type : '';

        // populate the grid row before we send the request so that the
        // order of actions is maintained and so the user gets an 
        // immediate reaction to their barcode input action.
        var row_item = {
            index : $scope.checkouts.length,
            copy_barcode : params.copy_barcode,
            noncat_type : params.noncat_type
        };

        $scope.checkouts.unshift(row_item);
        $scope.gridDataProvider.refresh();

        egCore.hatch.setItem('circ.checkout.strict_barcode', $scope.strict_barcode);
        var options = {check_barcode : $scope.strict_barcode};

        egCirc.checkout(params, options).then(
            function(co_resp) {
                // update stats locally so we don't have to fetch them w/
                // each checkout.
                patronSvc.patron_stats.checkouts.out++;
                patronSvc.patron_stats.checkouts.total_out++;

                // copy the response event into the original grid row item
                // note: angular.copy clobbers the destination
                row_item.evt = co_resp.evt;
                angular.forEach(co_resp.data, function(val, key) {
                    row_item[key] = val;
                });
                munge_checkout_resp(co_resp, row_item);
            },
            function() {
                // Circ was rejected somewhere along the way.
                // Remove the copy from the grid since there was no action.
                // note: since checkouts are unshifted onto the array, the
                // index value does not (generally) match the array position.
                var pos = -1;
                angular.forEach($scope.checkouts, function(co, idx) {
                    if (co.index == row_item.index) pos = idx;
                });
                $scope.checkouts.splice(pos, 1);
                $scope.gridDataProvider.refresh();
            }

        ).finally(function() {

            // regardless of the outcome of the circ, remove the 
            // barcode from the pending list.
            if (params.copy_barcode)
                delete pending_barcodes[params.copy_barcode];

            $scope.focusMe = true; // return focus to barcode input
        });
    }

    // add some checkout-specific additions for display
    function munge_checkout_resp(co_resp, row_item) {
        var params = co_resp.params;
        if (params.noncat) {
            row_item.title = egCore.env.cnct.map[params.noncat_type].name();
            row_item.noncat_count = params.noncat_count;
            row_item.circ = new egCore.idl.circ();
            row_item.circ.due_date(co_resp.evt.payload.noncat_circ.duedate());
        }
    }

    $scope.print_receipt = function() {
        var print_data = {circulations : []}

        if ($scope.checkouts.length == 0) return $q.when();

        angular.forEach($scope.checkouts, function(co) {
            if (co.circ) {
                print_data.circulations.push({
                    circ : egCore.idl.toHash(co.circ),
                    copy : egCore.idl.toHash(co.acp),
                    call_number : egCore.idl.toHash(co.acn),
                    title : co.title,
                    author : co.author
                })
            };
        });

        return egCore.print.print({
            context : 'default', 
            template : 'checkout', 
            scope : print_data,
            show_dialog : $scope.show_print_dialog
        });
    }

    // Redirect the user to the barcode entry page to load a new patron.
    // If configured to do so, print the receipt first
    $scope.done = function() {
        if (printOnComplete) {

            $scope.print_receipt().then(function() {
                $location.path('/circ/patron/bcsearch');
            });

        } else {
            $location.path('/circ/patron/bcsearch');
        }
    }
}])

