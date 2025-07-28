/**
 * Checkout items to patrons
 */

angular.module('egPatronApp').controller('PatronCheckoutCtrl',

       ['$scope','$q','$routeParams','egCore','egUser','patronSvc',
        'egGridDataProvider','$location','$timeout','egCirc','ngToast',

function($scope , $q , $routeParams , egCore , egUser , patronSvc , 
         egGridDataProvider , $location , $timeout , egCirc , ngToast) {
    var now = new Date();

    $scope.initTab('checkout', $routeParams.id).finally(function(){
        $scope.focusMe = true;
    });
    $scope.checkouts = patronSvc.checkouts;
    $scope.checkoutArgs = {
        noncat_type : 'barcode',
        due_date : new Date(now)
    };

    $scope.minDate = new Date(now);
    $scope.outOfRange = false;
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
            patronSvc.fetchedWithInactiveCard() ||
            $scope.outOfRange == true
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

    $scope.date_options = {
        due_date : egCore.hatch.getSessionItem('eg.circ.checkout.due_date'),
        has_sticky_date : egCore.hatch.getSessionItem('eg.circ.checkout.is_until_logout'),
        is_until_logout : egCore.hatch.getSessionItem('eg.circ.checkout.is_until_logout')
    };

    if ($scope.date_options.is_until_logout) { // If until_logout is set there should also be a date set.
        $scope.checkoutArgs.due_date = new Date($scope.date_options.due_date);
        $scope.checkoutArgs.sticky_date = true;
    }

    $scope.toggle_opt = function(opt) {
        if ($scope.date_options[opt]) {
            $scope.date_options[opt] = false;
        } else {
            $scope.date_options[opt] = true;
        }
    };

    // The interactions between these options are complicated enough that $watch'ing them all is the only safe way to keep things sane.
    $scope.$watch('date_options.has_sticky_date', function(newval) {
        if ( newval ) { // was false, is true
            // $scope.date_options.due_date = checkoutArgs.due_date;
        } else {
            $scope.date_options.is_until_logout = false;
        }
        $scope.checkoutArgs.sticky_date = newval;
    });

    $scope.$watch('date_options.is_until_logout', function(newval) {
        if ( newval ) { // was false, is true
            $scope.date_options.has_sticky_date = true;
            $scope.date_options.due_date = $scope.checkoutArgs.due_date;
            egCore.hatch.setSessionItem('eg.circ.checkout.is_until_logout', true);
            egCore.hatch.setSessionItem('eg.circ.checkout.due_date', $scope.checkoutArgs.due_date);
        } else {
            egCore.hatch.removeSessionItem('eg.circ.checkout.is_until_logout');
            egCore.hatch.removeSessionItem('eg.circ.checkout.due_date');
        }
    });

    $scope.$watch('checkoutArgs.due_date', function(newval) {
        if ( $scope.date_options.is_until_logout && !isNaN(newval)) {
            if (!$scope.outOfRange) {
                egCore.hatch.setSessionItem('eg.circ.checkout.due_date', newval);
            } else {
                egCore.hatch.setSessionItem('eg.circ.checkout.due_date', $scope.checkoutArgs.due_date);
            }
        }
    });

    $scope.has_email_address = function() {
        return (
            patronSvc.current &&
            patronSvc.current.email() &&
            patronSvc.current.email().match(/.*@.*/)
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

    egCore.hatch.usePrinting().then(function(useHatch) {
        $scope.using_hatch_printer = useHatch;
    });

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
        $scope.gridDataProvider.prepend();

        var options = {check_barcode : $scope.strict_barcode};

        egCirc.checkout(params, options).then(
            function(co_resp) {
                // update stats locally so we don't have to fetch them w/
                // each checkout.

                // Avoid updating checkout counts when a checkout turns
                // into a renewal via auto_renew.
                if (!co_resp.auto_renew && !params.noncat && !options.sameCopyCheckout) {
                    patronSvc.patron_stats.checkouts.out++;
                    patronSvc.patron_stats.checkouts.total_out++;
                }

                // update balance owed if necessary
                if (co_resp.evt.length) {
                    if (co_resp.evt[0].payload.deposit_billing ||
                        co_resp.evt[0].payload.rental_billing) {
                        patronSvc.patron_stats.fines.balance_owed
                            = co_resp.evt[0].payload.patron_money.balance_owed();
                    }
                }

                // copy the response event into the original grid row item
                // note: angular.copy clobbers the destination
                row_item.evt = co_resp.evt;
                angular.forEach(co_resp.data, function(val, key) {
                    row_item[key] = val;
                });
               
                if (row_item.acp) { // unset for non-cat items.
                    row_item['copy_barcode'] = row_item.acp.barcode();
                }

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
            row_item.copy_alert_count = 0;
        } else {
            row_item.copy_alert_count = 0;
            egCore.pcrud.search(
                'aca',
                { copy : co_resp.data.acp.id(), ack_time : null },
                null,
                { atomic : true }
            ).then(function(list) {
                row_item.copy_alert_count = list.length;
            });
        }
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

    $scope.gridCellHandlers = {};
    $scope.gridCellHandlers.copyAlertsEdit = function(id) {
        egCirc.manage_copy_alerts([id]).then(function() {
            // update grid items?
        });
    };

    $scope.onStrictBarcodeChange = function() {
        egCore.hatch.setItem(
            'circ.checkout.strict_barcode',
            $scope.strict_barcode
        );
    };

    $scope.print_receipt = function() {
        var print_data = {circulations : []};
        var cusr = patronSvc.current;

        if ($scope.checkouts.length == 0) return $q.when();

        angular.forEach($scope.checkouts, function(co) {
            if (co.circ) {
                print_data.circulations.push({
                    circ : egCore.idl.toHash(co.circ),
                    copy : egCore.idl.toHash(co.acp),
                    call_number : egCore.idl.toHash(co.acn), // Wrong?
                    owning_lib : egCore.idl.toHash(co.aou), // Wrong?
                    title : co.title,
                    author : co.author
                });
            };
        });

        // This is repeated in patron.* so everything is in one place but left here so existing templates don't break.
        print_data.patron_money = patronSvc.patron_stats.fines;
        print_data.patron = {
            prefix : cusr.prefix(),
            first_given_name : cusr.first_given_name(),
            second_given_name : cusr.second_given_name(),
            family_name : cusr.family_name(),
            suffix : cusr.suffix(),
            pref_prefix : cusr.pref_prefix(),
            pref_first_given_name : cusr.pref_first_given_name(),
            pref_secondg_given_name : cusr.second_given_name(),
            pref_family_name : cusr.pref_family_name(),
            suffix : cusr.suffix(),
            card : { barcode : cusr.card().barcode() },
            money_summary : patronSvc.patron_stats.fines,
            expire_date : cusr.expire_date(),
            alias : cusr.alias(),
            has_email : Boolean($scope.has_email_address()),
            has_phone : Boolean(cusr.day_phone() || cusr.evening_phone() || cusr.other_phone()),
            juvenile : cusr.juvenile()
        };

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
        egCore.strings.setPageTitle( egCore.strings.PAGE_TITLE_PATRON_SEARCH );
        $location.path('/circ/patron/bcsearch');
    }
}])

