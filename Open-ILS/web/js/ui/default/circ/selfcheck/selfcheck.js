dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');
dojo.require('openils.CGI');
dojo.require('openils.Util');
dojo.require('openils.User');
dojo.require('openils.Event');

dojo.requireLocalization('openils.circ', 'selfcheck');
var localeStrings = dojo.i18n.getLocalization('openils.circ', 'selfcheck');


const SET_BARCODE_REGEX = 'opac.barcode_regex';
const SET_PATRON_TIMEOUT = 'circ.selfcheck.patron_login_timeout';
const SET_ALERT_ON_CHECKOUT_EVENT = 'circ.selfcheck.alert_on_checkout_event';
const SET_AUTO_OVERRIDE_EVENTS = 'circ.selfcheck.auto_override_checkout_events';
const SET_PATRON_PASSWORD_REQUIRED = 'circ.selfcheck.patron_password_required';

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

    // is a transaction pending?
    this.pendingXact = false; 

    // dict of org unit settings for "here"
    this.orgSettings = {};

    
    // Construct a mock checkout for debugging purposes
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



/**
 * Fetch the org-unit settings, initialize the display, etc.
 */
SelfCheckManager.prototype.init = function() {

    this.staff = openils.User.user;
    this.workstation = openils.User.workstation;
    this.authtoken = openils.User.authtoken;
    this.loadOrgSettings();

    // add onclick handlers for nav links

    var self = this;
    dojo.connect(
        dojo.byId('oils-selfck-hold-details-link'),
        'onclick',
        function() { self.drawHoldsPage(); }
    );

    dojo.connect(
        dojo.byId('oils-selfck-pay-fines-link'),
        'onclick',
        function() { self.drawPayFinesPage(); }
    );


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
                handler : function(pw) { self.loginPatron(barcode, ps); }
            });

            dojo.connect(selfckScanBox, 'onKeyDown', pwHandler);

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
            return alert('login failed'); // TODO
        }
    } 

    // retrieve the fleshed user by barcode
    this.patron = fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.user.fleshed.retrieve_by_barcode'],
        {params : [this.authtoken, barcode]}
    );

    var evt = openils.Event.parse(this.patron);
    if(evt) {

        // User login failed, why?
        
        switch(evt.textcode) {

            case 'ACTOR_USER_NOT_FOUND':
                return alert('user not found'); // TODO

            case 'NO_SESSION':
                return alert('staff login timed out'); // TODO

            default:
                return alert('unexpected patron login error occured: ' + evt.textcode); // TODO
        }
    }

    // patron login succeeded
    dojo.byId('oils-selfck-user-banner').innerHTML = 'Welcome, ' + this.patron.usrname(); // TODO i18n
    this.drawCircPage();
}


/**
 * Manages the main input box
 * @param msg The context message to display with the box
 * @param clearOnly Don't update the context message, just clear the value and re-focus
 * @param handler Optional "on-enter" handler.  
 */
SelfCheckManager.prototype.updateScanBox = function(args) {

    selfckScanBox.attr('value', '');

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
    if(this.cgi.param('mock-circ')) {
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


    if(dojo.isArray(result)) {
        // list of results.  See if we can override all of them.

    } else {
        var evt = openils.Event.parse(result);

        switch(evt.textcode) {
            // standard result events
            
            case 'SUCCESS':
                this.displayCheckout(evt);
                break;

            case 'OPEN_CIRCULATION_EXISTS':
                // TODO renewal
                break;

            case 'NO_SESSION':
                // TODO logout staff
                break;
        }
    }

    console.log("Circ resulted in " + js2JSON(result));
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

    this.circTbody.appendChild(row);
}


SelfCheckManager.prototype.byName = function(node, name) {
    return dojo.query('[name=' + name+']', node)[0];
}

/**
 * Print a receipt
 */
SelfCheckManager.prototype.printReceipt = function() {
}

/**
 * Build the patron holds table
 */
SelfCheckManager.prototype.displayHolds = function() {
}


/**
 * Logout the patron and return to the login page
 */
SelfCheckManager.prototype.logoutPatron = function() {
}


/**
 * Fire up the manager on page load
 */
openils.Util.addOnLoad(
    function() {
        new SelfCheckManager().init();
    }
);
