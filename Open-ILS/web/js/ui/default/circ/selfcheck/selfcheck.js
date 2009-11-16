dojo.require('openils.CGI');
dojo.require('openils.Util');
dojo.require('openils.User');
dojo.require('openils.Event');

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
}

/**
 * Fetch the org-unit settings, initialize the display, etc.
 */
SelfCheckManager.prototype.init = function() {

    this.staff = openils.User.user;
    this.workstation = openils.User.workstation;
    this.authtoken = openils.User.authtoken;
    this.loadOrgSettings();

    if(this.cgi.param('patron')) {
        // Patron barcode via cgi param.  Mainly used for debugging.
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
            self.updateScanBox(
                'Please enter your password', // TODO i18n 
                false,
                function(pw) { self.loginPatron(barcode, ps); }
            );

            dojo.connect(selfckScanBox, 'onKeyDown', pwHandler);

        } else {
            // password is not required, go ahead and login
            self.loginPatron(barcode);
        }
    };

    this.updateScanBox(
        'Please log in with your library barcode.', // TODO
        false,
        bcHandler
    );
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
 * @param str The context message to display with the box
 * @param clearOnly Don't update the context message, just clear the value and re-focus
 * @param handler Optional "on-enter" handler.  
 */
SelfCheckManager.prototype.updateScanBox = function(str, clearOnly, handler) {

    if(!clearOnly)
        dojo.byId('oils-selfck-scan-text').innerHTML = str;
    selfckScanBox.attr('value', '');
    selfckScanBox.focus();

    if(handler) {
        dojo.connect(selfckScanBox, 'onKeyDown', 
            function(e) {
                if(e.keyCode != dojo.keys.ENTER) 
                    return;
                handler(selfckScanBox.attr('value'));
            }
        );
    }
}

/**
 *  Sets up the checkout/renewal interface
 */
SelfCheckManager.prototype.drawCircPage = function() {

    var self = this;
    this.updateScanBox(
        'Please enter an item barcode', // TODO i18n
        false,
        function(barcode) { self.checkout(barcode); }
    );

    openils.Util.show('oils-selfck-circ-page');

    this.circTbody = dojo.byId('oils-selfck-circ-tbody');
    if(!this.circTemplate)
        this.circTemplate = this.circTbody.removeChild(dojo.byId('oils-selfck-circ-row'));
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

    /*
    if(record.isbn()) {
	    var pic = $n(template, 'jacket');
	    pic.setAttribute('src', '/opac/ac/jacket/small/' + cleanISBN(record.isbn()));
    }
    */

    this.byName('barcode', row).innerHTML = copy.barcode();
    this.byName('title', row).innerHTML = record.title();
    this.byName('author', row).innerHTML = record.author();
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
