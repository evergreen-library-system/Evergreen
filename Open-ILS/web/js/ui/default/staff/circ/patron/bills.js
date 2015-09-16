
/* Billing Service */

angular.module('egPatronApp')

.factory('billSvc', 
       ['$q','egCore','patronSvc',
function($q , egCore , patronSvc) {

    var service = {};

    // fetch org unit settings specific to the bills display
    service.fetchBillSettings = function() {
        if (service.settings) return $q.when(service.settings);
        return egCore.org.settings(
            ['ui.circ.billing.uncheck_bills_and_unfocus_payment_box']
        ).then(function(s) {return service.settings = s});
    }

    // user billing summary
    service.fetchSummary = function() {
        return egCore.pcrud.retrieve(
            'mous', service.userId, {}, {authoritative : true})
        .then(function(summary) {return service.summary = summary})
    }

    service.applyPayment = function(type, payments, note, check) {
        return egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.money.payment',
            egCore.auth.token(), {
                userid : service.userId,
                note : note || '', 
                payment_type : type,
                check_number : check,
                payments : payments,
                patron_credit : 0
            },
            patronSvc.current.last_xact_id()
        ).then(function(resp) {
            console.debug('payments: ' + js2JSON(resp));
            if (evt = egCore.evt.parse(resp)) 
                return alert(evt);

            // payment API returns the update xact id so we can track it
            // for future payments without having to refresh the user.
            patronSvc.current.last_xact_id(resp.last_xact_id);
            return resp.payments;
        });
    }

    service.fetchBills = function(xact_id) {
        var bills = [];
        return egCore.pcrud.search('mb',
            {xact : xact_id}, null,
            {authoritative : true}
        ).then(
            function() {return bills},
            null,
            function(bill) {bills.push(bill); return bill}
        );
    }

    // TODO: no longer needed?
    service.fetchPayments = function(xact_id) {
        return egCore.net.request(
            'open-ils.circ',
            'open-ils.circ.money.payment.retrieve.all.authoritative',
            egCore.auth.token(), xact_id
        );
    }

    service.voidBills = function(bill_ids) {
        return egCore.net.requestWithParamList(
            'open-ils.circ',
            'open-ils.circ.money.billing.void',
            [egCore.auth.token()].concat(bill_ids)
        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) return alert(evt);
            return resp;
        });
    }

    service.updateBillNotes = function(note, ids) {
        return egCore.net.requestWithParamList(
            'open-ils.circ',
            'open-ils.circ.money.billing.note.edit',
            [egCore.auth.token(), note].concat(ids)
        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) return alert(evt);
            return resp;
        });
    }

    service.updatePaymentNotes = function(note, ids) {
        return egCore.net.requestWithParamList(
            'open-ils.circ',
            'open-ils.circ.money.payment.note.edit',
            [egCore.auth.token(), note].concat(ids)
        ).then(function(resp) {
            if (evt = egCore.evt.parse(resp)) return alert(evt);
            return resp;
        });
    }

    return service;
}])


/**
 * Manages Bills
 */
.controller('PatronBillsCtrl',
       ['$scope','$q','$routeParams','egCore','egConfirmDialog','$location',
        'egGridDataProvider','billSvc','patronSvc','egPromptDialog','$modal',
        'egBilling',
function($scope , $q , $routeParams , egCore , egConfirmDialog , $location,
         egGridDataProvider , billSvc , patronSvc , egPromptDialog , $modal,
         egBilling) {

    $scope.initTab('bills', $routeParams.id);
    billSvc.userId = $routeParams.id;

    // set up some defaults
    $scope.check_number = 0;
    $scope.payment_amount = null;
    $scope.session_voided = 0;
    $scope.payment_type = 'cash_payment';
    $scope.focus_payment = true;
    $scope.annotate_payment = false;
    $scope.receipt_count = 1;
    $scope.receipt_on_pay = false;

    // pre-define list-returning funcs in case we access them
    // before the grid instantiates
    $scope.gridControls = {
        focusRowSelector : false,
        selectedItems : function(){return []},
        allItems : function(){return []},
        itemRetrieved : function(item) {
            item.payment_pending = 0;
        },
        activateItem : function(item) {
            $scope.showFullDetails([item]);
        },
        setQuery : function() {    
            return {
                usr : billSvc.userId, 
                xact_finish : null,
                'summary.balance_owed' : {'<>' : 0}
            }
        }, 
        setSort : function() {
            return ['xact_start']; 
        }
    }

    billSvc.fetchSummary().then(function(s) {$scope.summary = s});

    // given a payment amount, determines how much of that is applied
    // to selected transactions and how much is left over (change).
    function pending_payment_info() {
        var amt = $scope.payment_amount || 0;
        if (amt >= $scope.owed_selected()) {
            return {
                payment : $scope.owed_selected(),
                change : amt - $scope.owed_selected()
            }
        } 
        return {payment : amt, change : 0};
    }

    // calculates amount owed, billed, and paid for selected items
    // TODO: move me to service
    function selected_payment_info() {
        var info = {owed : 0, billed : 0, paid : 0};
        angular.forEach($scope.gridControls.selectedItems(), function(item) {
            info.owed   += Number(item['summary.balance_owed']) * 100;
            info.billed += Number(item['summary.total_owed']) * 100;
            info.paid   += Number(item['summary.total_paid']) * 100;
        });
        info.owed /= 100;
        info.billed /= 100;
        info.paid /= 100;
        return info;
    }

    $scope.pending_payment = function() {
        return pending_payment_info().payment;
    }
    $scope.pending_change = function() {
        return pending_payment_info().change;
    }
    $scope.owed_selected = function() {
        return selected_payment_info().owed; 
    }
    $scope.billed_selected = function() {
        return selected_payment_info().billed;
    }
    $scope.paid_selected = function() {
        return selected_payment_info().paid;
    }
    $scope.refunds_available = function() {
        var amount = 0;
        angular.forEach($scope.gridControls.allItems(), function(item) {
            if (item['summary.balance_owed'] < 0) 
                amount += item['summary.balance_owed'] * 100;
        });
        return -(amount / 100);
    }

    // update the item.payment_pending value each time the user
    // selects different transactions to pay against.
    $scope.$watch(
        function() {return $scope.gridControls.selectedItems()},
        function() {updatePendingColumn()},
        true
    );

    // update the item.payment_pending for each (selected) 
    // transaction any time the user-entered payment amount is modified
    $scope.$watch('payment_amount', updatePendingColumn);

    // updates the value of the payment_pending column in the grid.
    // This has to be managed manually since the display value in the grid
    // is derived from the value on the stored item and not the contents
    // of our local scope variables.
    function updatePendingColumn() {
        // reset all to zero..
        angular.forEach($scope.gridControls.allItems(), 
            function(item) {item.payment_pending = 0});

        var payment_amount = $scope.pending_payment();

        var selected = $scope.gridControls.selectedItems();
        for (var i = 0; i < selected.length; i++) { // for/break
            var item = selected[i];
            var owed = Number(item['summary.balance_owed']);

            if (payment_amount > owed) {
                // pending payment exceeds balance of current item.
                // pay the entire item.
                item.payment_pending = owed;
                payment_amount -= owed;

            } else {
                // balance owed on the current item matches or exceeds
                // the pending payment.  Apply the full remainder of
                // the payment to this item.. and we're done.
                item.payment_pending = payment_amount;
                break;
            }
        }
    }

    // builds payment arrays ([xact_id, ammount]) for all transactions
    // which have a pending payment amount.
    function generatePayments() {
        var payments = [];
        angular.forEach($scope.gridControls.selectedItems(), function(item) {
            if (item.payment_pending == 0) return;
            payments.push([item.id, item.payment_pending]);
        });
        return payments;
    }

    function refreshDisplay() {
        patronSvc.fetchUserStats();
        billSvc.fetchSummary().then(function(s) {$scope.summary = s});
        $scope.payment_amount = null;
        $scope.gridControls.refresh();
    }

    // generates payments, collects user note if needed, and sends payment
    // to server.
    function sendPayment(note) {
        var make_payments = generatePayments();
        billSvc.applyPayment(
            $scope.payment_type, make_payments, note, $scope.check_number)
        .then(function(payment_ids) {

            if ($scope.receipt_on_pay) {
                printReceipt(
                    $scope.payment_type, payment_ids, make_payments, note);
            }

            refreshDisplay();
        })
    }

    function printReceipt(type, payment_ids, payments_made, note) {
        var payment_blobs = [];
        angular.forEach(payments_made, function(payment) {
            var xact_id = payment[0];

            // find the original transaction in the grid..
            var xact = $scope.gridControls.allItems().filter(
                function(item) {return item.id == xact_id})[0];

            payment_blobs.push({
                xact : egCore.idl.flatToNestedHash(xact),
                amount : payment[1]
            });
        });

        console.log(js2JSON(payment_blobs[0]));

        // page data not yet refreshed, capture data from current scope
        var print_data = {
            payment_note : note,
            previous_balance : Number($scope.summary.balance_owed()),
            payment_total : Number($scope.payment_amount),
            payment_applied : $scope.pending_payment(),
            amount_voided : Number($scope.session_voided),
            change_given : $scope.pending_change(),
            payments : payment_blobs,
            current_location : egCore.idl.toHash(
                egCore.org.get(egCore.auth.user().ws_ou()))
        }

        print_data.new_balance = (
            print_data.previous_balance * 100 - 
            print_data.payment_applied * 100) / 100;

        for (var i = 0; i < $scope.receipt_count; i++) {
            egCore.print.print({
                context : 'receipt', 
                template : 'bill_payment', 
                scope : print_data
            });
        }
    }

    $scope.showHistory = function() {
        $location.path('/circ/patron/' + 
            patronSvc.current.id() + '/bill_history/transactions');
    }
    
    // For now, only adds billing to first selected item.
    // Could do batches later if needed
    $scope.addBilling = function(all) {
        if (all[0]) {
            egBilling.showBillDialog({
                xact : egCore.idl.flatToNestedHash(all[0]),
                patron : $scope.patron()
            }).then(refreshDisplay);
        }
    }

    $scope.showBillDialog = function($event) {
        egBilling.showBillDialog({
            patron : $scope.patron()
        }).then(refreshDisplay);
    }

    // Select refunds adds all refunds to the existing selection.
    // It does not /only/ select refunds
    $scope.selectRefunds = function() {
        var ids = $scope.gridControls.selectedItems().map(
            function(i) { return i.id });
        angular.forEach($scope.gridControls.allItems(), function(item) {
            if (Number(item['summary.balance_owed']) < 0)
                ids.push(item.id);
        });
        $scope.gridControls.selectItems(ids);
    }

    // -------------
    // determine on initial page load when all of the grid rows should
    // be selected.
    var selectOnLoad = true;
    billSvc.fetchBillSettings().then(function(s) {
        if (s['ui.circ.billing.uncheck_bills_and_unfocus_payment_box']) {
            $scope.focus_payment = false; // de-focus the payment box
            $scope.gridControls.focusRowSelector = true;
            selectOnLoad = false;
            // if somehow the grid finishes rendering before our settings 
            // arrive, manually de-select everything.
            $scope.gridControls.selectItems([]);
        }
    });

    $scope.gridControls.allItemsRetrieved = function() {
        if (selectOnLoad) {
            selectOnLoad = false; // only for initial controller load.
            // select all non-refund items
            $scope.gridControls.selectItems( 
                $scope.gridControls.allItems()
                .filter(function(i) {return i['summary.balance_owed'] > 0})
                .map(function(i){return i.id})
            );
        }
    }
    // -------------


    $scope.printBills = function(selected) {
        if (!selected.length) return;
        // bills print receipt assumes nested hashes, but our grid
        // stores flattener data.  Fetch the selected xacts as
        // fleshed pcrud objects and hashify.  
        // (Consider an alternate approach..)
        var ids = selected.map(function(t){ return t.id });
        var xacts = [];
        egCore.pcrud.search('mbt', 
            {id : ids},
            {flesh : 1, flesh_fields : {'mbt' : ['summary']}},
            {authoritative : true}
        ).then(
            function() {
                egCore.print.print({
                    context : 'receipt', 
                    template : 'bills_current', 
                    scope : {   
                        transactions : xacts,
                        current_location : egCore.idl.toHash(
                            egCore.org.get(egCore.auth.user().ws_ou()))
                    }
                });
            }, 
            null, 
            function(xact) {
                xacts.push(egCore.idl.toHash(xact));
            }
        );
    }

    $scope.applyPayment = function() {
        if ($scope.annotate_payment) {
            egPromptDialog.open(
                egCore.strings.ANNOTATE_PAYMENT_MSG, '',
                {ok : function(value) {sendPayment(value)}}
            );
        } else {
            sendPayment();
        }
    }

    $scope.voidAllBillings = function(items) {
        angular.forEach(items, function(item) {

            billSvc.fetchBills(item.id).then(function(bills) {
                var bill_ids = [];
                var cents = 0;
                angular.forEach(bills, function(b) {
                    if (b.voided() != 't') {
                        cents += b.amount() * 100;
                        bill_ids.push(b.id())
                    }
                });

                $scope.session_voided = 
                    ($scope.session_voided * 100 + cents) / 100;

                if (bill_ids.length == 0) {
                    // TODO: warn
                    return;
                }

                // TODO: alert of pending voiding

                billSvc.voidBills(bill_ids).then(function() {
                    refreshDisplay();
                });
            });
        });
    }

    // note this is functionally equivalent to selecting a neg. transaction
    // then clicking Apply Payment -- this just adds a speed bump (ditto
    // the XUL client).
    $scope.refundXact = function(all) {
        var items = all.filter(function(item) {
            return item['summary.balance_owed'] < 0
        });

        if (items.length == 0) return;

        var ids = items.map(function(item) {return item.id});
            
        egConfirmDialog.open(
            egCore.strings.CONFIRM_REFUND_PAYMENT, '', 
            {   xactIds : ''+ids,
                ok : function() {
                    // reset the received payment amount.  this ensures
                    // we're not mingling payments with refunds.
                    $scope.payment_amount = 0;
                }
            }
        );
    }

    // direct the user to the transaction details page
    $scope.showFullDetails = function(all) {
        if (all[0]) 
            $location.path('/circ/patron/' + 
                patronSvc.current.id() + '/bill/' + all[0].id);
    }

    $scope.activateBill = function(xact) {
        $scope.showFullDetails([xact]);
    }

}])

/**
 * Displays details of a single transaction
 */
.controller('XactDetailsCtrl',
       ['$scope','$q','$routeParams','egCore','egGridDataProvider','patronSvc','billSvc','egPromptDialog','egBilling',
function($scope,  $q , $routeParams , egCore , egGridDataProvider , patronSvc , billSvc , egPromptDialog , egBilling) {

    $scope.initTab('bills', $routeParams.id);
    var xact_id = $routeParams.xact_id;

    var xactGrid = $scope.xactGridControls = {
        setQuery : function() { return {xact : xact_id} },
        setSort : function() { return ['billing_ts'] }
    }

    var paymentGrid = $scope.paymentGridControls = {
        setQuery : function() { return {xact : xact_id} },
        setSort : function() { return ['payment_ts'] }
    }

    // -- actions
    $scope.voidBillings = function(bill_list) {
        var bill_ids = [];
        angular.forEach(bill_list, function(b) {
            if (b.voided != 't') bill_ids.push(b.id);
        });

        if (bill_ids.length == 0) {
            // TODO: warn
            return;
        }

        billSvc.voidBills(bill_ids).then(function() {

            // refresh bills and summary data
            // note: no need to update payments
            patronSvc.fetchUserStats();

            egBilling.fetchXact(xact_id).then(function(xact) {
                $scope.xact = xact
            });

            xactGrid.refresh();
        });
    }

    // batch-edit billing and payment notes, depending on 'type'
    function editNotes(selected, type) {
        var notes = selected.map(function(b){ return b.note }).join(',');
        var ids = selected.map(function(b){ return b.id });

        // show the note edit prompt
        egPromptDialog.open(
            egCore.strings.EDIT_BILL_PAY_NOTE, notes, {
                ids : ''+ids,
                ok : function(value) {

                    var func = 'updateBillNotes';
                    if (type == 'payment') func = 'updatePaymentNotes';

                    billSvc[func](value, ids).then(function() {
                        if (type == 'payment') {
                            paymentGrid.refresh();
                        } else {
                            xactGrid.refresh();
                        }
                    });
                }
            }
        );
    }

    $scope.editBillNotes = function(selected) {
        editNotes(selected, 'bill');
    }

    $scope.editPaymentNotes = function(selected) {
        editNotes(selected, 'payment');
    }

    // -- retrieve our data
    $scope.total_circs = 0; // start with 0 instead of undefined
    egBilling.fetchXact(xact_id).then(function(xact) {
        $scope.xact = xact;

        var copyId = xact.circulation().target_copy().id();
        var circ_count = 0;
        egCore.pcrud.search('circbyyr',
            {copy : copyId}, null, {atomic : true})
        .then(function(counts) {
            angular.forEach(counts, function(count) {
                circ_count += Number(count.count());
            });
            $scope.total_circs = circ_count;
        });
        // set the title.  only needs to be done on initial page load
        if (xact.circulation()) {
            if (xact.circulation().target_copy().call_number().id() == -1) {
                $scope.title = xact.circulation().target_copy().dummy_title();
            } else  {
                // TODO: shared bib service?
                $scope.title = xact.circulation().target_copy()
                    .call_number().record().simple_record().title();
                $scope.title_id = xact.circulation().target_copy()
                    .call_number().record().id();
            }
        }
    });
}])


.controller('BillHistoryCtrl',
       ['$scope','$q','$routeParams','egCore','patronSvc','billSvc','egPromptDialog','$location',
function($scope,  $q , $routeParams , egCore , patronSvc , billSvc , egPromptDialog , $location) {

    $scope.initTab('bills', $routeParams.id);
    billSvc.userId = $routeParams.id;
    $scope.bill_tab = $routeParams.history_tab;
    $scope.totals = {};

    // link page controller actions defined by sub-controllers here
    $scope.actions = {};

    var start = new Date(); // now - 1 year
    start.setFullYear(start.getFullYear() - 1),
    $scope.dates = {
        xact_start : start,
        xact_finish : new Date()
    }

    $scope.date_range = function() {
        var start = $scope.dates.xact_start.toISOString().replace(/T.*/,'');
        var end = $scope.dates.xact_finish.toISOString().replace(/T.*/,'');
        var today = new Date().toISOString().replace(/T.*/,'');
        if (end == today) end = 'now';
        return [start, end];
    }
}])


.controller('BillXactHistoryCtrl',
       ['$scope','$q','egCore','patronSvc','billSvc','egPromptDialog','$location','egBilling',
function($scope,  $q , egCore , patronSvc , billSvc , egPromptDialog , $location , egBilling) {

    // generate a grid query with the current date widget values.
    function current_grid_query() {
        return {
            '-or' : [
                {'summary.balance_owed' : {'<>' : 0}},
                {'summary.last_payment_ts' : {'<>' : null}}
            ],
            xact_start : {between : $scope.date_range()},
            usr : billSvc.userId
        }
    }

    $scope.gridControls = {
        selectedItems : function(){return []},
        activateItem : function(item) {
            $scope.showFullDetails([item]);
        },
        // this sets the query on page load
        setQuery : current_grid_query
    }

    $scope.actions.apply_date_range = function() {
        // tells the grid to re-draw itself with the new query
        $scope.gridControls.setQuery(current_grid_query());
    }

    // TODO; move me to service
    function selected_payment_info() {
        var info = {owed : 0, billed : 0, paid : 0};
        angular.forEach($scope.gridControls.selectedItems(), function(item) {
            info.owed   += Number(item['summary.balance_owed']) * 100;
            info.billed += Number(item['summary.total_owed']) * 100;
            info.paid   += Number(item['summary.total_paid']) * 100;
        });
        info.owed /= 100;
        info.billed /= 100;
        info.paid /= 100;
        return info;
    }

    $scope.totals.selected_billed = function() {
        return selected_payment_info().billed;
    }
    $scope.totals.selected_paid = function() {
        return selected_payment_info().paid;
    }

    $scope.showFullDetails = function(all) {
        if (all[0]) 
            $location.path('/circ/patron/' + 
                patronSvc.current.id() + '/bill/' + all[0].id);
    }

    // For now, only adds billing to first selected item.
    // Could do batches later if needed
    $scope.addBilling = function(all) {
        if (all[0]) {
            egBilling.showBillDialog({
                xact : egCore.idl.flatToNestedHash(all[0]),
                patron : $scope.patron()
            }).then(function() { 
                $scope.gridControls.refresh();
                patronSvc.fetchUserStats();
            })
        }
    }
}])

.controller('BillPaymentHistoryCtrl',
       ['$scope','$q','egCore','patronSvc','billSvc','$location',
function($scope,  $q , egCore , patronSvc , billSvc , $location) {

    // generate a grid query with the current date widget values.
    function current_grid_query() {
        return {
            'payment_ts' : {between : $scope.date_range()},
            'xact.usr' : billSvc.userId
        }
    }

    $scope.gridControls = {
        selectedItems : function(){return []},
        activateItem : function(item) {
            $scope.showFullDetails([item]);
        },
        setSort : function() {
            return [{'payment_ts' : 'DESC'}, 'id'];
        },
        setQuery : current_grid_query
    }

    $scope.actions.apply_date_range = function() {
        // tells the grid to re-draw itself with the new query
        $scope.gridControls.setQuery(current_grid_query());
    }

    $scope.showFullDetails = function(all) {
        if (all[0]) 
            $location.path('/circ/patron/' + 
                patronSvc.current.id() + '/bill/' + all[0]['xact.id']);
    }

    $scope.totals.selected_paid = function() {
        var paid = 0;
        angular.forEach($scope.gridControls.selectedItems(), function(payment) {
            paid += Number(payment.amount) * 100;
        });
        return paid / 100;
    }
}])



