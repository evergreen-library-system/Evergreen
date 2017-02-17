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
            updateHoldReadyView();
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
    var holds_pending = xacts.holds_pending;
    var holds_ready = xacts.holds_ready;

    // combine all holds into a single list, ready-for-checkout holds first
    var holds = holds_ready.concat(holds_pending);

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
            dojo.empty('ebook_holds_main_table_body');
            var tr = dojo.create("tr", null, dojo.byId('ebook_holds_main_table_body'));
            dojo.create("td", { innerHTML: h.title }, tr);
            dojo.create("td", { innerHTML: h.author }, tr);
            dojo.create("td", { innerHTML: h.expire_date }, tr);
            dojo.create("td", { innerHTML: hold_status }, tr);
            dojo.create("td", null, tr); // TODO actions
        });
        dojo.addClass('no_ebook_holds', "hidden");
        dojo.removeClass('ebook_holds_main', "hidden");
    }
}

function updateHoldReadyView() {
    var holds = xacts.holds_ready;
    if (holds.length < 1) {
        dojo.removeClass('no_ebook_holds', "hidden");
    } else {
        dojo.forEach(holds, function(h) {
            dojo.empty('ebook_holds_main_table_body');
            var tr = dojo.create("tr", null, dojo.byId('ebook_holds_main_table_body'));
            dojo.create("td", { innerHTML: h.title }, tr);
            dojo.create("td", { innerHTML: h.author }, tr);
            dojo.create("td", { innerHTML: h.expire_date }, tr);
            dojo.create("td", null, tr); // TODO actions
        });
        dojo.addClass('no_ebook_holds', "hidden");
        dojo.removeClass('ebook_holds_main', "hidden");
    }
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

