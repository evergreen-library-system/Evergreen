dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');
dojo.require('openils.CGI');
dojo.require('openils.Util');
dojo.require('openils.User');
dojo.require('openils.Event');
dojo.require('openils.widget.ProgressDialog');

dojo.requireLocalization('openils.circ', 'selfcheck');
var localeStrings = dojo.i18n.getLocalization('openils.circ', 'selfcheck');


const SET_BARCODE_REGEX = 'opac.barcode_regex';
const SET_PATRON_TIMEOUT = 'circ.selfcheck.patron_login_timeout';
const SET_ALERT_ON_CHECKOUT_EVENT = 'circ.selfcheck.alert_on_checkout_event';
const SET_AUTO_OVERRIDE_EVENTS = 'circ.selfcheck.auto_override_checkout_events';
const SET_PATRON_PASSWORD_REQUIRED = 'circ.selfcheck.patron_password_required';

//openils.Util.playAudioUrl('/xul/server/skin/media/audio/bonus.wav');

function SelfCheckManager() {

    this.cgi = new openils.CGI();
    this.staff = null; 
    this.workstation = null;
    this.authtoken = null;

    this.patron = null; 
    this.patronBarcodeRegex = null;

    // current item barcode
    this.itemBarcode = null; 

    // are we currently performing a renewal?
    this.isRenewal = false; 

    // dict of org unit settings for "here"
    this.orgSettings = {};

    // Construct a mock checkout for debugging purposes
    if(this.mockCheckouts = this.cgi.param('mock-circ')) {

        this.mockCheckout = {
            payload : {
                record : new fieldmapper.mvr(),
                copy : new fieldmapper.acp(),
                circ : new fieldmapper.circ()
            }
        };

        this.mockCheckout.payload.record.title('Jazz improvisation for guitar');
        this.mockCheckout.payload.record.author('Wise, Les');
        this.mockCheckout.payload.record.isbn('0634033565');
        this.mockCheckout.payload.copy.barcode('123456789');
        this.mockCheckout.payload.circ.renewal_remaining(1);
        this.mockCheckout.payload.circ.parent_circ(1);
        this.mockCheckout.payload.circ.due_date('2012-12-21');
    }
}



/**
 * Fetch the org-unit settings, initialize the display, etc.
 */
SelfCheckManager.prototype.init = function() {

    this.staff = openils.User.user;
    this.workstation = openils.User.workstation;
    this.authtoken = openils.User.authtoken;
    this.loadOrgSettings();

    
    var self = this;
    // connect onclick handlers to the various navigation links
    var linkHandlers = {
        'oils-selfck-hold-details-link' : function() { self.drawHoldsPage(); },
        'oils-selfck-nav-holds' : function() { self.drawHoldsPage(); },
        'oils-selfck-pay-fines-link' : function() { self.drawFinesPage(); },
        'oils-selfck-nav-fines' : function() { self.drawFinesPage(); },
        'oils-selfck-nav-home' : function() { self.drawCircPage(); },
        'oils-selfck-nav-logout' : function() { self.logoutPatron(); }
    }

    for(var id in linkHandlers) 
        dojo.connect(dojo.byId(id), 'onclick', linkHandlers[id]);


    if(this.cgi.param('patron')) {
        
        // Patron barcode via cgi param.  Mainly used for debugging and
        // only works if password is not required by policy
        this.loginPatron(this.cgi.param('patron'));

    } else {
        this.drawLoginPage();
    }
}

/**
 * Loads the org unit settings
 */
SelfCheckManager.prototype.loadOrgSettings = function() {

    var settings = fieldmapper.aou.fetchOrgSettingBatch(
        this.staff.ws_ou(), [
            SET_BARCODE_REGEX,
            SET_PATRON_TIMEOUT,
            SET_ALERT_ON_CHECKOUT_EVENT,
            SET_AUTO_OVERRIDE_EVENTS,
        ]
    );

    for(k in settings) {
        if(settings[k])
            this.orgSettings[k] = settings[k].value;
    }

    if(settings[SET_BARCODE_REGEX]) 
        this.patronBarcodeRegex = new RegExp(settings[SET_BARCODE_REGEX].value);
}

SelfCheckManager.prototype.drawLoginPage = function() {
    var self = this;

    var bcHandler = function(barcode) {
        // handle patron barcode entry

        if(self.orgSettings[SET_PATRON_PASSWORD_REQUIRED]) {
            
            // password is required.  wire up the scan box to read it
            self.updateScanBox({
                msg : 'Please enter your password', // TODO i18n 
                handler : function(pw) { self.loginPatron(barcode, pw); }
            });

        } else {
            // password is not required, go ahead and login
            self.loginPatron(barcode);
        }
    };

    this.updateScanBox({
        msg : 'Please log in with your library barcode.', // TODO
        handler : bcHandler
    });
}

/**
 * Login the patron.  
 */
SelfCheckManager.prototype.loginPatron = function(barcode, passwd) {

    if(this.orgSettings[SET_PATRON_PASSWORD_REQUIRED]) {

        // patron password is required.  Verify it.

        var res = fieldmapper.standardRequest(
            ['open-ils.actor', 'open-ils.actor.verify_user_password'],
            {params : [this.authtoken, barcode, null, hex_md5(passwd)]}
        );

        if(res == 0) {
            // user-not-found results in login failure
            this.handleXactResult('login', barcode, {textcode : 'ACTOR_USER_NOT_FOUND'});
        }
    } 

    // retrieve the fleshed user by barcode
    this.patron = fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.user.fleshed.retrieve_by_barcode'],
        {params : [this.authtoken, barcode]}
    );

    var evt = openils.Event.parse(this.patron);
    if(evt) {
        this.handleXactResult('login', barcode, evt);

    } else {

        dojo.byId('oils-selfck-status-div').innerHTML = '';
        dojo.byId('oils-selfck-user-banner').innerHTML = 'Welcome, ' + this.patron.usrname(); // TODO i18n
        this.drawCircPage();
    }
}


/**
 * Manages the main input box
 * @param msg The context message to display with the box
 * @param clearOnly Don't update the context message, just clear the value and re-focus
 * @param handler Optional "on-enter" handler.  
 */
SelfCheckManager.prototype.updateScanBox = function(args) {

    if(args.select) {
        selfckScanBox.domNode.select();
    } else {
        selfckScanBox.attr('value', '');
    }

    if(args.value)
        selfckScanBox.attr('value', args.value);

    if(args.msg) 
        dojo.byId('oils-selfck-scan-text').innerHTML = args.msg;

    if(selfckScanBox._lastHandler && (args.handler || args.clearHandler)) {
        dojo.disconnect(selfckScanBox._lastHandler);
    }

    if(args.handler) {
        selfckScanBox._lastHandler = dojo.connect(
            selfckScanBox, 
            'onKeyDown', 
            function(e) {
                if(e.keyCode != dojo.keys.ENTER) 
                    return;
                args.handler(selfckScanBox.attr('value'));
            }
        );
    }

    selfckScanBox.focus();
}

/**
 *  Sets up the checkout/renewal interface
 */
SelfCheckManager.prototype.drawCircPage = function() {

    var self = this;
    this.updateScanBox({
        msg : 'Please enter an item barcode', // TODO i18n
        handler : function(barcode) { self.checkout(barcode); }
    });

    openils.Util.hide('oils-selfck-payment-page');
    openils.Util.hide('oils-selfck-holds-page');
    openils.Util.show('oils-selfck-circ-page');

    this.circTbody = dojo.byId('oils-selfck-circ-tbody');
    if(!this.circTemplate)
        this.circTemplate = this.circTbody.removeChild(dojo.byId('oils-selfck-circ-row'));

    // items out, holds, and fines summaries

    // fines summary
    fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.user.fines.summary'],
        {   async : true,
            params : [this.authtoken, this.patron.id()],
            oncomplete : function(r) {
                var summary = openils.Util.readResponse(r);
                dojo.byId('oils-selfck-fines-total').innerHTML = 
                    dojo.string.substitute(
                        localeStrings.TOTAL_FINES_ACCOUNT, 
                        [summary.balance_owed()]
                    );
            }
        }
    );

    // holds summary
    this.updateHoldsSummary();

    // items out summary
    this.updateCircSummary();

    // render mock checkouts for debugging?
    if(this.mockCheckouts) {
        for(var i in [1,2,3]) 
            this.displayCheckout(this.mockCheckout);
    }
}

SelfCheckManager.prototype.updateHoldsSummary = function(decrement) {

    if(!this.holdsSummary) {
        var summary = fieldmapper.standardRequest(
            ['open-ils.circ', 'open-ils.circ.holds.user_summary'],
            {params : [this.authtoken, this.patron.id()]}
        );

        this.holdsSummary = {};
        this.holdsSummary.ready = Number(summary['4']);
        this.holdsSummary.total = 0;

        for(var i in summary) 
            this.holdsSummary.total += Number(summary[i]);
    }

    if(this.decrement) 
        this.holdsSummary.ready -= 1;

    dojo.byId('oils-selfck-holds-total').innerHTML = 
        dojo.string.substitute(
            localeStrings.TOTAL_HOLDS, 
            [this.holdsSummary.total]
        );

    dojo.byId('oils-selfck-holds-ready').innerHTML = 
        dojo.string.substitute(
            localeStrings.HOLDS_READY_FOR_PICKUP, 
            [this.holdsSummary.ready]
        );
}


SelfCheckManager.prototype.updateCircSummary = function(increment) {

    if(!this.circSummary) {

        var summary = fieldmapper.standardRequest(
            ['open-ils.actor', 'open-ils.actor.user.checked_out.count'],
            {params : [this.authtoken, this.patron.id()]}
        );

        this.circSummary = {
            total : Number(summary.out) + Number(summary.overdue),
            overdue : Number(summary.overdue),
            session : 0
        };
    }

    if(increment) {
        // local checkout occurred.  Add to the total and the session.
        this.circSummary.total += 1;
        this.circSummary.session += 1;
    }

    dojo.byId('oils-selfck-circ-account-total').innerHTML = 
        dojo.string.substitute(
            localeStrings.TOTAL_ITEMS_ACCOUNT, 
            [this.circSummary.total]
        );

    dojo.byId('oils-selfck-circ-session-total').innerHTML = 
        dojo.string.substitute(
            localeStrings.TOTAL_ITEMS_SESSION, 
            [this.circSummary.session]
        );
}


SelfCheckManager.prototype.drawHoldsPage = function() {

    // TODO add option to hid scanBox
    // this.updateScanBox(...)

    openils.Util.hide('oils-selfck-circ-page');
    openils.Util.hide('oils-selfck-payment-page');
    openils.Util.show('oils-selfck-holds-page');

    this.holdTbody = dojo.byId('oils-selfck-hold-tbody');
    if(!this.holdTemplate)
        this.holdTemplate = this.holdTbody.removeChild(dojo.byId('oils-selfck-hold-row'));
    while(this.holdTbody.childNodes[0])
        this.holdTbody.removeChild(this.holdTbody.childNodes[0]);

    progressDialog.show(true);

    var self = this;
    fieldmapper.standardRequest( // fetch the hold IDs

        ['open-ils.circ', 'open-ils.circ.holds.id_list.retrieve'],
        {   async : true,
            params : [this.authtoken, this.patron.id()],

            oncomplete : function(r) { 
                var ids = openils.Util.readResponse(r);
                if(!ids || ids.length == 0) {
                    progressDialog.hide();
                    return;
                }

                fieldmapper.standardRequest( // fetch the hold objects with fleshed details
                    ['open-ils.circ', 'open-ils.circ.hold.details.batch.retrieve.atomic'],
                    {   async : true,
                        params : [self.authtoken, ids],

                        oncomplete : function(rr) {
                            self.drawHolds(openils.Util.readResponse(rr));
                        }
                    }
                );
            }
        }
    );
}

/**
 * Fetch and add a single hold to the list of holds
 */
SelfCheckManager.prototype.drawHolds = function(holds) {

    holds = holds.sort(
        // sort available holds to the top of the list
        // followed by queue position order
        function(a, b) {
            if(a.status == 4) return -1;
            if(a.queue_position < b.queue_position) return -1;
            return 1;
        }
    );

    progressDialog.hide();

    for(var i in holds) {

        var data = holds[i];
        var row = this.holdTemplate.cloneNode(true);

        if(data.mvr.isbn()) {
            this.byName(row, 'jacket').setAttribute('src', '/opac/extras/ac/jacket/small/' + data.mvr.isbn());
        }

        this.byName(row, 'title').innerHTML = data.mvr.title();
        this.byName(row, 'author').innerHTML = data.mvr.author();

        if(data.status == 4) {

            // hold is ready for pickup
            this.byName(row, 'status').innerHTML = localeStrings.HOLD_STATUS_READY;

        } else {

            // hold is still pending
            this.byName(row, 'status').innerHTML = 
                dojo.string.substitute(
                    localeStrings.HOLD_STATUS_WAITING,
                    [data.queue_position, data.potential_copies]
                );
        }

        this.holdTbody.appendChild(row);
    }
}



/**
 * Check out a single item.  If the item is already checked 
 * out to the patron, redirect to renew()
 */
SelfCheckManager.prototype.checkout = function(barcode, override) {

    if(!barcode) {
        this.updateScanbox(null, true);
        return;
    }

    if(this.mockCheckouts) {
        // if we're in mock-checkout mode, just insert another
        // fake circ into the table and get out of here.
        this.displayCheckout(this.mockCheckout);
        return;
    }

    // TODO see if it's a patron barcode
    // TODO see if this item has already been checked out in this session

    var method = 'open-ils.circ.checkout.full';
    if(override) method += '.override';

    var result = fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.checkout.full'],
        {params: [
            this.authtoken, {
                patron_id : this.patron.id(),
                copy_barcode : barcode
            }
        ]}
    );

    var stat = this.handleXactResult('checkout', barcode, result);

    console.log("Circ resulted in " + js2JSON(result));

    if(stat.override)
        this.checkout(barcode, true);

}


SelfCheckManager.prototype.handleXactResult = function(action, item, result) {

    var displayText = '';
    var popup = false;

    // TODO handle lost/missing/etc checkin+checkout override steps
        
    if(result.textcode == 'NO_SESSION') {

        return this.logoutStaff();

    } else if(result.textcode == 'SUCCESS') {

        if(action == 'checkout') {

            displayText = dojo.string.substitute(
                localeStrings.CHECKOUT_SUCCESS, [item]);
                this.displayCheckout(result);

        } else if(action == 'renew') {

            displayText = dojo.string.substitute(
                localeStrings.RENEW_SUCCESS, [item]);
                this.displayCheckout(result);
        }

        this.updateScanBox();

    } else if(result.textcode == 'OPEN_CIRCULATION_EXISTS' && action == 'checkout') {

        this.renew(item);

    } else {

        var overrideEvents = this.orgSettings[SET_AUTO_OVERRIDE_EVENTS];
    
        if(overrideEvents && overrideEvents.length) {
            
            // see if the events we received are all in the list of
            // events to override
    
            if(!result.length) result = [result];
    
            var override = true;
            for(var i = 0; i < result.length; i++) {
                var match = overrideEvents.filter(
                    function(e) { return (e == result[i].textcode); })[0];
                if(!match) {
                    override = false;
                    break;
                }
            }

            if(override) 
                return { override : true };
        }
    
        this.updateScanBox({select : true});
        popup = true;

        if(result.length) 
            result = result[0];

        switch(result.textcode) {

            case 'ACTOR_USER_NOT_FOUND' : 
                displayText = dojo.string.substitute(
                    localeStrings.LOGIN_FAILED, [item]);
                break;

            case 'already-out' : 
                    displayText = dojo.string.substitute(
                        localeStrings.ALREADY_OUT, [item]);

            default:
                console.error('Unhandled event ' + result.textcode);

                if(action == 'checkout' || action == 'renew') {
                    displayText = dojo.string.substitute(
                        localeStrings.GENERIC_CIRC_FAILURE, [item]);
                } else {
                    displayText = dojo.string.substitute(
                        localeStrings.UNKNOWN_ERROR, [result.textcode]);
                }
        }
    }

    dojo.byId('oils-selfck-status-div').innerHTML = displayText;

    if(popup && this.orgSettings[SET_ALERT_ON_CHECKOUT_EVENT]) 
        alert(displayText);

    return {};
}


/**
 * Renew an item
 */
SelfCheckManager.prototype.renew = function() {
}

/**
 * Display the result of a checkout or renewal in the items out table
 */
SelfCheckManager.prototype.displayCheckout = function(evt) {

    var copy = evt.payload.copy;
    var record = evt.payload.record;
    var circ = evt.payload.circ;
    var row = this.circTemplate.cloneNode(true);

    if(record.isbn()) {
        this.byName(row, 'jacket').setAttribute('src', '/opac/extras/ac/jacket/small/' + record.isbn());
    }

    this.byName(row, 'barcode').innerHTML = copy.barcode();
    this.byName(row, 'title').innerHTML = record.title();
    this.byName(row, 'author').innerHTML = record.author();
    this.byName(row, 'remaining').innerHTML = circ.renewal_remaining();

    var date = dojo.date.stamp.fromISOString(circ.due_date());
    this.byName(row, 'due_date').innerHTML = 
        dojo.date.locale.format(date, {selector : 'date'});

    // put new circs at the top of the list
    this.circTbody.insertBefore(row, this.circTbody.getElementsByTagName('tr')[0]);
}


SelfCheckManager.prototype.byName = function(node, name) {
    return dojo.query('[name=' + name+']', node)[0];
}


SelfCheckManager.prototype.drawFinesPage = function() {

    openils.Util.hide('oils-selfck-circ-page');
    openils.Util.hide('oils-selfck-holds-page');
    openils.Util.show('oils-selfck-payment-page');

}

/**
 * Print a receipt
 */
SelfCheckManager.prototype.printReceipt = function() {
}


/**
 * Logout the patron and return to the login page
 */
SelfCheckManager.prototype.logoutPatron = function() {

    this.patron = null;
    this.holdsSummary = null;
    this.circSummary = null;

    this.drawLoginPage();
}


/**
 * Fire up the manager on page load
 */
openils.Util.addOnLoad(
    function() {
        new SelfCheckManager().init();
    }
);
