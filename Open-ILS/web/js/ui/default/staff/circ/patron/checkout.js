/**
 * Checkout items to patrons
 */

angular.module('egPatronApp').controller('PatronCheckoutCtrl',

       ['$scope','$q','$routeParams','egCore','egUser','patronSvc',
        'egGridDataProvider','$location','$timeout','egCirc','ngToast',

function($scope , $q , $routeParams , egCore , egUser , patronSvc , 
         egGridDataProvider , $location , $timeout , egCirc , ngToast) {

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
            patronSvc.current.card().active() == 'f' ||
            patronSvc.fetchedWithInactiveCard()
        );
    }

    function setting_value (user, setting) {
        if (user) {
            var list = user.settings().filter(function(s){
                return s.name() == setting;
            });

            if (list.length) return list[0].value();
        }
    }

    $scope.has_email_address = function() {
        return (
            patronSvc.current &&
            patronSvc.current.email() &&
            patronSvc.current.email().match(/.*@.*/).length
        );
    }

    $scope.may_email_receipt = function() {
        return (
            $scope.has_email_address() &&
            setting_value(
                patronSvc.current,
                'circ.send_email_checkout_receipts'
            ) == 'true'
        );
    }

    $scope.using_hatch_printer = egCore.hatch.usePrinting();

    egCore.hatch.getItem('circ.checkout.strict_barcode')
        .then(function(sb){ $scope.strict_barcode = sb });

    // avoid multiple, in-flight attempts on the same barcode
    var pending_barcodes = {};

    var printOnComplete = true;
    egCore.org.settings([
        'circ.staff_client.do_not_auto_attempt_print'
    ]).then(function(settings) { 
        printOnComplete = !Boolean(
            angular.isArray(settings['circ.staff_client.do_not_auto_attempt_print']) &&
            (settings['circ.staff_client.do_not_auto_attempt_print'].indexOf('Checkout') > -1)
        );
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
            input_barcode : params.copy_barcode,
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

                // Avoid updating checkout counts when a checkout turns
                // into a renewal via auto_renew.
                if (!co_resp.auto_renew && !params.noncat) {
                    patronSvc.patron_stats.checkouts.out++;
                    patronSvc.patron_stats.checkouts.total_out++;
                }

                // copy the response event into the original grid row item
                // note: angular.copy clobbers the destination
                row_item.evt = co_resp.evt;
                angular.forEach(co_resp.data, function(val, key) {
                    row_item[key] = val;
                });
               
                row_item['copy_barcode'] = row_item.acp.barcode();

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
            row_item.circ.due_date(co_resp.evt[0].payload.noncat_circ.duedate());
            // Non-cat circs don't return the full list of circs.
            // Refresh the list of non-cat circs from the server.
            patronSvc.getUserNonCats(patronSvc.current.id());
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

    $scope.email_receipt = function() {
        if ($scope.has_email_address() && $scope.checkouts.length) {
            return egCore.net.request(
                'open-ils.circ',
                'open-ils.circ.checkout.batch_notify.session.atomic',
                egCore.auth.token(),
                patronSvc.current.id(),
                $scope.checkouts.map(function (c) { return c.circ.id() })
            ).then(function() {
                ngToast.create(egCore.strings.EMAILED_CHECKOUT_RECEIPT);
                return $q.when();
            });
        }
        return $q.when();
    }

    $scope.print_or_email_receipt = function() {
        if ($scope.may_email_receipt()) return $scope.email_receipt();
        $scope.print_receipt();
    }

    // set of functions to issue a receipt (if desired), then
    // redirect
    $scope.done_auto_receipt = function() {
        if ($scope.may_email_receipt()) {
            $scope.email_receipt().then(function() {
                $scope.done_redirect();
            });
        } else {
            if (printOnComplete) {

                $scope.print_receipt().then(function() {
                    $scope.done_redirect();
                });

            } else {
                $scope.done_redirect();
            }
        }
    }
    $scope.done_print_receipt = function() {
        $scope.print_receipt().then( function () {
            $scope.done_redirect();
        });
    }
    $scope.done_email_receipt = function() {
        $scope.email_receipt().then( function () {
            $scope.done_redirect();
        });
    }
    $scope.done_no_receipt = function() {
        $scope.done_redirect();
    }

    // Redirect the user to the barcode entry page to load a new patron.
    $scope.done_redirect = function() {
        $location.path('/circ/patron/bcsearch');
    }
}])

