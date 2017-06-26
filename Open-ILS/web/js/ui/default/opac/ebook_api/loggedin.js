/*
 * variables defined in base_js.tt2:
 *
 * ou
 * vendor_list = [ 'ebook_test' ]
 * authtoken
 * patron_id (barcode)
 * myopac_page
 * progress_icon (probably not done right)
 *
 * base_js.tt2 also "imports" dojo.cookie and a bunch of ebook_api JS
 */

// Array of objects representing this patron's relationship with a specific vendor.
var relations = [];

// Transaction cache.
var xacts = {
    checkouts: [],
    holds_pending: [],
    holds_ready: []
};

// Ebook to perform actions on.
var active_ebook;
if (typeof ebook_action.title_id !== 'undefined') {
    active_ebook = new Ebook(ebook_action.vendor, ebook_action.title_id);
}

dojo.addOnLoad(function() {

    dojo.forEach(vendor_list, function(v) {
        var rel = new Relation(v, patron_id);
        relations.push(rel);
    });

    // Pull patron transaction info from cache (cookie), if available.
    // Otherwise, do a live lookup against all enabled vendors.
    if (dojo.cookie('ebook_xact_cache')) {
        getCachedTransactions();
        addTotalsToPage();
        addTransactionsToPage();
    } else {
        console.log('retrieving patron transaction info for all vendors');
        dojo.forEach(relations, function(rel) {
            checkSession(rel.vendor, function(ses) {
                rel.getTransactions( function(r) {
                    addTransactionsToCache(r);
                });
            });
        });
    }

});

// Update current page with cross-vendor transaction totals.
function addTotalsToPage() {
    console.log('updating page with transaction totals');
    updateDashboard();
    updateMyAccountSummary();
}

// Update current page with detailed transaction info, where appropriate.
function addTransactionsToPage() {
    if (myopac_page) {
        console.log('updating page with cached transaction details, if applicable');
        if (myopac_page === 'ebook_circs')
            updateCheckoutView();
        if (myopac_page === 'ebook_holds')
            updateHoldView();
        if (myopac_page === 'ebook_holds_ready')
            updateHoldView();
        if (myopac_page === 'ebook_checkout')
            getReadyForCheckout();
        if (myopac_page === 'ebook_place_hold')
            getReadyForHold();
    }
}
        
function updateDashboard() {
    console.log('updating dashboard');
    var total_checkouts = (typeof xacts.checkouts === 'undefined') ? '-' : xacts.checkouts.length;
    var total_holds_pending = (typeof xacts.holds_pending === 'undefined') ? '-' : xacts.holds_pending.length;
    var total_holds_ready = (typeof xacts.holds_ready === 'undefined') ? '-' : xacts.holds_ready.length;
    // update totals
    dojo.byId('dash_e_checked').innerHTML = total_checkouts;
    dojo.byId('dash_e_holds').innerHTML = total_holds_pending;
    dojo.byId('dash_e_pickup').innerHTML = total_holds_ready;
    // unhide ebook dashboard
    dojo.removeClass('dashboard_e', "hidden");
}

function updateMyAccountSummary() {
    if (myopac_page === 'main') {
        console.log('updating account summary');
        var total_checkouts = (typeof xacts.checkouts === 'undefined') ? '-' : xacts.checkouts.length;
        var total_holds_pending = (typeof xacts.holds_pending === 'undefined') ? '-' : xacts.holds_pending.length;
        var total_holds_ready = (typeof xacts.holds_ready === 'undefined') ? '-' : xacts.holds_ready.length;
        // update totals
        dojo.byId('acct_sum_ebook_circ_total').innerHTML = total_checkouts;
        dojo.byId('acct_sum_ebook_hold_total').innerHTML = total_holds_pending;
        dojo.byId('acct_sum_ebook_hold_ready_total').innerHTML = total_holds_ready;
        // unhide display elements
        dojo.removeClass('acct_sum_ebook_circs', "hidden");
        dojo.removeClass('acct_sum_ebook_holds', "hidden");
        dojo.removeClass('acct_sum_ebook_holds_ready', "hidden");
    }
}

function updateCheckoutView() {
    if (xacts.checkouts.length < 1) {
        dojo.removeClass('no_ebook_circs', "hidden");
    } else {
        dojo.forEach(xacts.checkouts, function(x) {
            dojo.empty('ebook_circs_main_table_body');
            var dl_link = '<a href="' + x.download_url + '">' + l_strings.download + '</a>';
            var tr = dojo.create("tr", null, dojo.byId('ebook_circs_main_table_body'));
            dojo.create("td", { innerHTML: x.title }, tr);
            dojo.create("td", { innerHTML: x.author }, tr);
            dojo.create("td", { innerHTML: x.due_date }, tr);
            dojo.create("td", { innerHTML: dl_link}, tr);
            // TODO: more actions (renew, checkin)
        });
        dojo.addClass('no_ebook_circs', "hidden");
        dojo.removeClass('ebook_circs_main', "hidden");
    }
}

function updateHoldView() {
    if (myopac_page === 'ebook_holds_ready') {
        // only show holds that are ready for checkout
        var holds = xacts.holds_ready;
    } else {
        var holds_pending = xacts.holds_pending;
        var holds_ready = xacts.holds_ready;

        // combine all holds into a single list, ready-for-checkout holds first
        var holds = holds_ready.concat(holds_pending);
    }

    if (holds.length < 1) {
        dojo.removeClass('no_ebook_holds', "hidden");
    } else {
        dojo.forEach(holds, function(h) {
            var hold_status;
            if (h.is_ready) {
                hold_status = l_strings.ready_for_checkout;
            } else if (h.is_frozen) {
                hold_status = l_strings.suspended;
            } else {
                hold_status = h.queue_position + ' / ' + h.queue_size;
            }
            h.doCancelHold = function() {
                var ebook = new Ebook(this.vendor, this.title_id);
                ebook.cancelHold(authtoken, patron_id, function(resp) {
                    if (resp.error_msg) {
                        console.log('Cancel hold failed: ' . resp.error_msg);
                        dojo.removeClass('ebook_cancel_hold_failed', "hidden");
                    } else {
                        console.log('Cancel hold succeeded!');
                        dojo.destroy("hold-" + ebook.id);
                        dojo.removeClass('ebook_cancel_hold_succeeded', "hidden");
                        // Updating the transaction cache to remove the canceled hold
                        // is inconvenient, so we skip cleanupAfterAction() and merely
                        // clear transaction cache to force a refresh on next page load.
                        dojo.cookie('ebook_xact_cache', '', {path: '/', expires: '-1h'});
                    }
                });
            };
            dojo.empty('ebook_holds_main_table_body');
            var tr = dojo.create("tr", { id: "hold-" + h.title_id }, dojo.byId('ebook_holds_main_table_body'));
            dojo.create("td", { innerHTML: h.title }, tr);
            dojo.create("td", { innerHTML: h.author }, tr);
            dojo.create("td", { innerHTML: h.expire_date }, tr);
            dojo.create("td", { innerHTML: hold_status }, tr);
            var actions_td = dojo.create("td", null, tr);
            var button = dojo.create("input", { id: "cancel-hold-" + h.title_id, type: "button", value: l_strings.cancel_hold }, actions_td);
            dojo.connect(button, 'onclick', h, "doCancelHold");
        });
        dojo.addClass('no_ebook_holds', "hidden");
        dojo.removeClass('ebook_holds_main', "hidden");
    }
}

// set up page for user to perform a checkout
function getReadyForCheckout() {
    if (typeof active_ebook === 'undefined') {
        console.log('No active ebook specified, cannot prepare for checkout');
        dojo.removeClass('ebook_checkout_failed', "hidden");
    } else {
        active_ebook.getDetails( function(ebook) {
            dojo.empty('ebook_circs_main_table_body');
            var tr = dojo.create("tr", null, dojo.byId('ebook_circs_main_table_body'));
            dojo.create("td", { innerHTML: ebook.title }, tr);
            dojo.create("td", { innerHTML: ebook.author }, tr);
            dojo.create("td", null, tr);
            dojo.create("td", { id: "checkout-button-td" }, tr);
            var button = dojo.create("input", { id: "checkout-button", type: "button", value: l_strings.checkout }, dojo.byId('checkout-button-td'));
            ebook.conns.checkout = dojo.connect(button, 'onclick', "doCheckout");
            dojo.removeClass('ebook_circs_main', "hidden");
        });
    }
}

// set up page for user to place a hold
function getReadyForHold() {
    if (typeof active_ebook === 'undefined') {
        console.log('No active ebook specified, cannot prepare for hold');
        dojo.removeClass('ebook_hold_failed', "hidden");
    } else {
        active_ebook.getDetails( function(ebook) {
            dojo.empty('ebook_holds_main_table_body');
            var tr = dojo.create("tr", null, dojo.byId('ebook_holds_main_table_body'));
            dojo.create("td", { innerHTML: ebook.title }, tr);
            dojo.create("td", { innerHTML: ebook.author }, tr);
            dojo.create("td", null, tr); // Expire Date
            dojo.create("td", null, tr); // Status
            dojo.create("td", { id: "hold-button-td" }, tr);
            if (ebook_action.type == 'place_hold') {
                var button = dojo.create("input", { id: "hold-button", type: "button", value: l_strings.place_hold }, dojo.byId('hold-button-td'));
                ebook.conns.checkout = dojo.connect(button, 'onclick', "doPlaceHold");
            }
            dojo.removeClass('ebook_holds_main', "hidden");
        });
    }
}

function cleanupAfterAction() {
    // unset variables related to the transaction we have performed,
    // to avoid any weirdness on page reload
    ebook_action = {};
    // update page to account for successful checkout
    addTotalsToPage();
    addTransactionsToPage();
    // clear transaction cache to force a refresh on next page load
    dojo.cookie('ebook_xact_cache', '', {path: '/', expires: '-1h'});
}

// check out our active ebook
function doCheckout() {
    active_ebook.checkout(authtoken, patron_id, function(resp) {
        if (resp.due_date) {
            console.log('Checkout succeeded!');
            dojo.destroy('checkout-button');
            dojo.removeClass('ebook_checkout_succeeded', "hidden");
            // add our successful checkout to top of transaction cache
            var new_xact = {
                title_id: active_ebook.id,
                title: active_ebook.title,
                author: active_ebook.author,
                due_date: resp.due_date,
                download_url: '' // TODO - for OverDrive, user must "lock in" a format first!
            };
            xacts.checkouts.unshift(new_xact);
            cleanupAfterAction();
        } else {
            console.log('Checkout failed: ' + resp.error_msg);
            dojo.removeClass('ebook_checkout_failed', "hidden");
        }
        // When we switch to jQuery, we can use .one() instead of .on(),
        // obviating the need for an explicit disconnect here.
        dojo.disconnect(active_ebook.conns.checkout);
    });
}

// place hold on our active ebook
function doPlaceHold() {
    active_ebook.placeHold(authtoken, patron_id, function(resp) {
        if (resp.error_msg) {
            console.log('Place hold failed: ' . resp.error_msg);
            dojo.removeClass('ebook_place_hold_failed', "hidden");
        } else {
            console.log('Place hold succeeded!');
            dojo.destroy('hold-button');
            dojo.removeClass('ebook_place_hold_succeeded', "hidden");
            var new_hold = {
                title_id: active_ebook.id,
                title: active_ebook.title,
                author: active_ebook.author,
                queue_position: resp.queue_position,
                queue_size: resp.queue_size,
                expire_date: resp.expire_date
            };
            if ( resp.is_ready || (resp.queue_position === 1 && resp.queue_size === 1) ) {
                xacts.holds_ready.unshift(new_hold);
            } else {
                xacts.holds_pending.unshift(new_hold);
            }
            cleanupAfterAction();
        }
    });
}

// deserialize transactions from cache, returning them as a JS object
function getCachedTransactions() {
    console.log('retrieving cached transaction details');
    var cache_obj;
    var current_cache = dojo.cookie('ebook_xact_cache');
    if (current_cache) {
        cache_obj = JSON.parse(current_cache);
        xacts.checkouts = cache_obj.checkouts;
        xacts.holds_pending = cache_obj.holds_pending;
        xacts.holds_ready = cache_obj.holds_ready;
    }
    return cache_obj;
}

// add a single vendor's transactions to transaction cache
function addTransactionsToCache(rel) {
    console.log('updating transaction cache');
    var v = rel.vendor;
    var updated_xacts = {
        checkouts: [],
        holds_pending: [],
        holds_ready: []
    };
    // preserve any transactions with other vendors
    dojo.forEach(xacts.checkouts, function(xact) {
        if (xact.vendor !== v)
            updated_xacts.checkouts.push(xact);
    });
    dojo.forEach(xacts.holds_pending, function(xact) {
        if (xact.vendor !== v)
            updated_xacts.holds_pending.push(xact);
    });
    dojo.forEach(xacts.holds_ready, function(xact) {
        if (xact.vendor !== v)
            updated_xacts.holds_ready.push(xact);
    });
    // add transactions from current vendor
    dojo.forEach(rel.checkouts, function(xact) {
        updated_xacts.checkouts.push(xact);
    });
    dojo.forEach(rel.holds_pending, function(xact) {
        updated_xacts.holds_pending.push(xact);
    });
    dojo.forEach(rel.holds_ready, function(xact) {
        updated_xacts.holds_ready.push(xact);
    });
    // TODO sort transactions by date
    // save transactions to cache
    xacts = updated_xacts;
    var new_cache = JSON.stringify(xacts);
    dojo.cookie('ebook_xact_cache', new_cache, {path: '/'});
    // update current page
    addTotalsToPage();
    addTransactionsToPage();
}

