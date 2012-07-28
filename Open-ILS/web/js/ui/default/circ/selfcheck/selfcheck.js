dojo.require('dojo.date.locale');
dojo.require('dojo.cookie');
dojo.require('dojo.date.stamp');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.NumberSpinner');
dojo.require('openils.CGI');
dojo.require('openils.Util');
dojo.require('openils.User');
dojo.require('openils.Event');
dojo.require('openils.widget.ProgressDialog');
dojo.require('openils.widget.OrgUnitFilteringSelect');


dojo.requireLocalization('openils.circ', 'selfcheck');
var localeStrings = dojo.i18n.getLocalization('openils.circ', 'selfcheck');


const SET_BARCODE_REGEX = 'opac.barcode_regex';
const SET_PATRON_TIMEOUT = 'circ.selfcheck.patron_login_timeout';
const SET_AUTO_OVERRIDE_EVENTS = 'circ.selfcheck.auto_override_checkout_events';
const SET_PATRON_PASSWORD_REQUIRED = 'circ.selfcheck.patron_password_required';
const SET_AUTO_RENEW_INTERVAL = 'circ.checkout_auto_renew_age';
const SET_WORKSTATION_REQUIRED = 'circ.selfcheck.workstation_required';
const SET_ALERT_POPUP = 'circ.selfcheck.alert.popup';
const SET_ALERT_SOUND = 'circ.selfcheck.alert.sound';
const SET_CC_PAYMENT_ALLOWED = 'credit.payments.allow';
// This setting only comes into play if COPY_NOT_AVAILABLE is in the SET_AUTO_OVERRIDE_EVENTS list
const SET_BLOCK_CHECKOUT_ON_COPY_STATUS = 'circ.selfcheck.block_checkout_on_copy_status';

// set before the login dialog is rendered
openils.User.default_login_agent = 'selfcheck';

function SelfCheckManager() {

    this.cgi = new openils.CGI();
    this.staff = null; 
    this.workstation = null;
    this.authtoken = null;

    this.patron = null; 
    this.patronBarcodeRegex = null;

    this.checkouts = [];
    this.itemsOut = [];

    // During renewals, keep track of the ID of the previous circulation. 
    // Previous circ is used for tracking failed renewals (for receipts).
    this.prevCirc = null;

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

    this.initPrinter();
}

SelfCheckManager.prototype.setupStaffLogin = function(verify) {

    if(verify) oilsSetupUser(); 
    this.staff = openils.User.user;
    this.workstation = openils.User.workstation;
    this.authtoken = openils.User.authtoken;
}



/**
 * Fetch the org-unit settings, initialize the display, etc.
 */
SelfCheckManager.prototype.init = function() {

    this.setupStaffLogin();
    this.loadOrgSettings();

    this.circTbody = dojo.byId('oils-selfck-circ-tbody');
    this.itemsOutTbody = dojo.byId('oils-selfck-circ-out-tbody');

    // workstation is required but none provided
    if(this.orgSettings[SET_WORKSTATION_REQUIRED] && !this.workstation) {
        if(confirm(dojo.string.substitute(localeStrings.WORKSTATION_REQUIRED))) {
            this.registerWorkstation();
        }
        return;
    }
    
    var self = this;
    // connect onclick handlers to the various navigation links
    var linkHandlers = {
        'oils-selfck-hold-details-link' : function() { self.drawHoldsPage(); },
        'oils-selfck-view-fines-link' : function() { self.drawFinesPage(); },
        'oils-selfck-pay-fines-link' : function() {
            self.goToTab("payment");
            self.drawPayFinesPage(
                self.patron,
                self.getSelectedFinesTotal(),
                self.getSelectedFineTransactions(),
                function(resp) {
                    var evt = openils.Event.parse(resp);
                    if(evt) {
                        var message = evt + '';
                        if(evt.textcode == 'CREDIT_PROCESSOR_DECLINED_TRANSACTION' && evt.payload)
                            message += '\n' + evt.payload.error_message;
                        if(evt.textcode == 'INVALID_USER_XACT_ID')
                            message += '\n' + localeStrings.PAYMENT_INVALID_USER_XACT_ID;
                        self.handleAlert(message, true, 'payment-failure');
                        return;
                    }

                    self.patron.last_xact_id(resp.last_xact_id); // update to match latest from server
                    self.printPaymentReceipt(
                        resp,
                        function() {
                            self.updateFinesSummary();
                            self.drawFinesPage();
                        }
                    );
                }
            );
        },
        'oils-selfck-nav-home' : function() { self.drawCircPage(); },
        'oils-selfck-nav-logout' : function() { self.logoutPatron(); },
        'oils-selfck-nav-logout-print' : function() { self.logoutPatron(true); },
        'oils-selfck-items-out-details-link' : function() { self.drawItemsOutPage(); },
        'oils-selfck-print-list-link' : function() { self.printList(); }
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

    /**
     * To test printing, pass a URL param of 'testprint'.  The value for the param
     * should be a JSON string like so:  [{circ:<circ_id>}, ...]
     */
    var testPrint = this.cgi.param('testprint');
    if(testPrint) {
        this.checkouts = JSON2js(testPrint);
        this.printSessionReceipt();
        this.checkouts = [];
    }
}


SelfCheckManager.prototype.getSelectedFinesTotal = function() {
    var total = 0;
    dojo.forEach(
        dojo.query("[name=selector]", this.finesTbody),
        function(input) {
            if(input.checked)
                total += Number(input.getAttribute("balance_owed"));
        }
    );
    return total.toFixed(2);
};

SelfCheckManager.prototype.getSelectedFineTransactions = function() {
    return dojo.query("[name=selector]", this.finesTbody).
        filter(function (o) { return o.checked }).
        map(
            function (o) {
                return [
                    o.getAttribute("xact"),
                    Number(o.getAttribute("balance_owed")).toFixed(2)
                ];
            }
        );
};

/**
 * Registers a new workstion
 */
SelfCheckManager.prototype.registerWorkstation = function() {
    
    oilsSelfckWsDialog.show();

    new openils.User().buildPermOrgSelector(
        'REGISTER_WORKSTATION', 
        oilsSelfckWsLocSelector, 
        this.staff.home_ou()
    );


    var self = this;
    dojo.connect(oilsSelfckWsSubmit, 'onClick', 

        function() {
            oilsSelfckWsDialog.hide();
            var name = oilsSelfckWsLocSelector.attr('displayedValue') + '-' + oilsSelfckWsName.attr('value');

            var res = fieldmapper.standardRequest(
                ['open-ils.actor', 'open-ils.actor.workstation.register'],
                { params : [
                        self.authtoken, name, oilsSelfckWsLocSelector.attr('value')
                    ]
                }
            );

            if(evt = openils.Event.parse(res)) {
                if(evt.textcode == 'WORKSTATION_NAME_EXISTS') {
                    if(confirm(localeStrings.WORKSTATION_EXISTS)) {
                        location.href = location.href.replace(/\?.*/, '') + '?ws=' + name;
                    } else {
                        self.registerWorkstation();
                    }
                    return;
                } else {
                    alert(evt);
                }
            } else {
                location.href = location.href.replace(/\?.*/, '') + '?ws=' + name;
            }
        }
    );
}

/**
 * Loads the org unit settings
 */
SelfCheckManager.prototype.loadOrgSettings = function() {

    var settings = fieldmapper.aou.fetchOrgSettingBatch(
        this.staff.ws_ou(), [
            SET_BARCODE_REGEX,
            SET_PATRON_TIMEOUT,
            SET_ALERT_POPUP,
            SET_ALERT_SOUND,
            SET_AUTO_OVERRIDE_EVENTS,
            SET_BLOCK_CHECKOUT_ON_COPY_STATUS,
            SET_PATRON_PASSWORD_REQUIRED,
            SET_AUTO_RENEW_INTERVAL,
            SET_WORKSTATION_REQUIRED,
            SET_CC_PAYMENT_ALLOWED
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

    var bcHandler = function(barcode_or_usrname) {
        // handle patron barcode/usrname entry

        if(self.orgSettings[SET_PATRON_PASSWORD_REQUIRED]) {
            
            // password is required.  wire up the scan box to read it
            self.updateScanBox({
                msg : 'Please enter your password', // TODO i18n 
                handler : function(pw) { self.loginPatron(barcode_or_usrname, pw); },
                password : true
            });

        } else {
            // password is not required, go ahead and login
            self.loginPatron(barcode_or_usrname);
        }
    };

    this.updateScanBox({
        msg : 'Please log in with your username or library barcode.', // TODO
        handler : bcHandler
    });
}

/**
 * Login the patron.  
 */
SelfCheckManager.prototype.loginPatron = function(barcode_or_usrname, passwd) {

    this.setupStaffLogin(true); // verify still valid

    var barcode = null;
    var usrname = null;
    console.log('testing ' + barcode_or_usrname);
    if (barcode_or_usrname.match(this.patronBarcodeRegex)) {
        console.log('barcode');
        barcode = barcode_or_usrname;
    } else {
        console.log('usrname');
        usrname = barcode_or_usrname;
    }

    if(this.orgSettings[SET_PATRON_PASSWORD_REQUIRED]) {
        
        if(!passwd) {
            // would only happen in dev/debug mode when using the patron= param
            alert('password required by org setting.  remove patron= from URL'); 
            return;
        }

        // patron password is required.  Verify it.

        var self = this;
        new openils.User().auth_verify(
            {   username : usrname, barcode : barcode, 
                type : 'opac', passwd : passwd, agent : 'selfcheck' },
            function(OK) {
                if (OK) {
                    self.fetchPatron(barcode, usrname);

                } else {
                    // auth verify failed
                    self.handleAlert(
                        dojo.string.substitute(localeStrings.LOGIN_FAILED, [barcode_or_usrname]),
                        false, 'login-failure'
                    );
                    self.drawLoginPage();
                }
            }
        );

    } else {
        this.fetchPatron(barcode, usrname);
    }
};

SelfCheckManager.prototype.fetchPatron = function(barcode, usrname) {

    var patron_id = fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.user.retrieve_id_by_barcode_or_username'],
        {params : [this.authtoken, barcode, usrname]}
    );

    // retrieve the fleshed user by id
    this.patron = fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.user.fleshed.retrieve.authoritative'],
        {params : [this.authtoken, patron_id]}
    );

    var evt = openils.Event.parse(this.patron);
    
    // verify validity of the card used to log in
    var inactiveCard = false;
    if(!evt) {
        var card;
        if (barcode) {
            card = this.patron.cards().filter(
                function(c) { return (c.barcode() == barcode); })[0];
        } else {
            card = this.patron.card();
        }
        inactiveCard = !openils.Util.isTrue(card.active());
    }

    if(evt || inactiveCard) {
        this.handleAlert(
            dojo.string.substitute(localeStrings.LOGIN_FAILED, [barcode || usrname]),
            false, 'login-failure'
        );
        this.drawLoginPage();

    } else {

        this.handleAlert('', false, 'login-success');
        dojo.byId('oils-selfck-user-banner').innerHTML = 
            dojo.string.substitute(localeStrings.WELCOME_BANNER, [this.patron.first_given_name()]);
        this.drawCircPage();
    }
}


SelfCheckManager.prototype.handleAlert = function(message, shouldPopup, sound) {

    console.log("Handling alert " + message);

    dojo.byId('oils-selfck-status-div').innerHTML = message;

    if(shouldPopup)
        openils.Util.addCSSClass( dojo.byId('oils-selfck-status-div'), 'checkout_failure' );
    else
        openils.Util.removeCSSClass( dojo.byId('oils-selfck-status-div'), 'checkout_failure' );

    if(shouldPopup && this.orgSettings[SET_ALERT_POPUP]) 
        alert(message);

    if(sound && this.orgSettings[SET_ALERT_SOUND])
        openils.Util.playAudioUrl(SelfCheckManager.audioConfig[sound]);
}


/**
 * Manages the main input box
 * @param msg The context message to display with the box
 * @param clearOnly Don't update the context message, just clear the value and re-focus
 * @param handler Optional "on-enter" handler.  
 */
SelfCheckManager.prototype.updateScanBox = function(args) {
    args = args || {};

    if(args.select) {
        selfckScanBox.domNode.select();
    } else {
        selfckScanBox.attr('value', '');
    }

    if(args.password) {
        selfckScanBox.domNode.setAttribute('type', 'password');
    } else {
        selfckScanBox.domNode.setAttribute('type', '');
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

    openils.Util.show('oils-selfck-circ-tbody', 'table-row-group');
    this.goToTab('checkout');

    while(this.itemsOutTbody.childNodes[0])
        this.itemsOutTbody.removeChild(this.itemsOutTbody.childNodes[0]);

    var self = this;
    this.updateScanBox({
        msg : 'Please enter an item barcode', // TODO i18n
        handler : function(barcode) { self.checkout(barcode); }
    });

    if(!this.circTemplate)
        this.circTemplate = this.circTbody.removeChild(dojo.byId('oils-selfck-circ-row'));

    // fines summary
    this.updateFinesSummary();

    // holds summary
    this.updateHoldsSummary();

    // items out summary
    this.updateCircSummary();

    // render mock checkouts for debugging?
    if(this.mockCheckouts) {
        for(var i in [1,2,3]) 
            this.displayCheckout(this.mockCheckout, 'checkout');
    }
}


SelfCheckManager.prototype.updateFinesSummary = function() {
    var self = this; 

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

                self.creditPayableBalance = summary.balance_owed();
            }
        }
    );
}


SelfCheckManager.prototype.drawItemsOutPage = function() {
    openils.Util.hide('oils-selfck-circ-tbody');

    this.goToTab('items_out');

    while(this.itemsOutTbody.childNodes[0])
        this.itemsOutTbody.removeChild(this.itemsOutTbody.childNodes[0]);

    progressDialog.show(true);
    
    var self = this;
    fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.actor.user.checked_out.atomic'],
        {
            async : true,
            params : [this.authtoken, this.patron.id()],
            oncomplete : function(r) {

                var resp = openils.Util.readResponse(r);

                var circs = resp.sort(
                    function(a, b) {
                        if(a.circ.due_date() > b.circ.due_date())
                            return -1;
                        return 1;
                    }
                );

                progressDialog.hide();

                self.itemsOut = [];
                dojo.forEach(circs,
                    function(circ) {
                        self.itemsOut.push(circ.circ.id());
                        self.displayCheckout(
                            {payload : circ}, 
                            (circ.circ.parent_circ()) ? 'renew' : 'checkout',
                            true
                        );
                    }
                );
            }
        }
    );
}


SelfCheckManager.prototype.goToTab = function(name) {
    this.tabName = name;

    openils.Util.hide('oils-selfck-fines-page');
    openils.Util.hide('oils-selfck-payment-page');
    openils.Util.hide('oils-selfck-holds-page');
    openils.Util.hide('oils-selfck-circ-page');
    openils.Util.hide('oils-selfck-pay-fines-link');
    
    switch(name) {
        case 'checkout':
            openils.Util.show('oils-selfck-circ-page');
            break;
        case 'items_out':
            openils.Util.show('oils-selfck-circ-page');
            break;
        case 'holds':
            openils.Util.show('oils-selfck-holds-page');
            break;
        case 'fines':
            openils.Util.show('oils-selfck-fines-page');
            break;
        case 'payment':
            openils.Util.show('oils-selfck-payment-page');
            break;
    }
}


SelfCheckManager.prototype.printList = function() {
    switch(this.tabName) {
        case 'checkout':
            this.printSessionReceipt();
            break;
        case 'items_out':
            this.printItemsOutReceipt();
            break;
        case 'holds':
            this.printHoldsReceipt();
            break;
        case 'fines':
            this.printFinesReceipt();
            break;
    }
}

SelfCheckManager.prototype.updateHoldsSummary = function() {

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

    this.goToTab('holds');

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
                    ['open-ils.circ', 'open-ils.circ.hold.details.batch.retrieve'],
                    {   async : true,
                        params : [self.authtoken, ids],
                        onresponse : function(rr) {
                            progressDialog.hide();
                            self.insertHold(openils.Util.readResponse(rr));
                        }
                    }
                );
            }
        }
    );
}

SelfCheckManager.prototype.insertHold = function(data) {
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

    // find the correct place the table to slot in the hold based on queue position

    var position = (data.status == 4) ? 0 : data.queue_position;
    row.setAttribute('position', position);

    for(var i = 0; i < this.holdTbody.childNodes.length; i++) {
        var node = this.holdTbody.childNodes[i];
        if(Number(node.getAttribute('position')) >= position) {
            this.holdTbody.insertBefore(row, node);
            return;
        }
    }

    this.holdTbody.appendChild(row);
}


SelfCheckManager.prototype.drawFinesPage = function() {

    // TODO add option to hid scanBox
    // this.updateScanBox(...)

    this.goToTab('fines');
    progressDialog.show(true);

    if(this.creditPayableBalance > 0 && this.orgSettings[SET_CC_PAYMENT_ALLOWED]) {
        openils.Util.show('oils-selfck-pay-fines-link', 'inline');
    }

    this.finesTbody = dojo.byId('oils-selfck-fines-tbody');
    if(!this.finesTemplate)
        this.finesTemplate = this.finesTbody.removeChild(dojo.byId('oils-selfck-fines-row'));
    while(this.finesTbody.childNodes[0])
        this.finesTbody.removeChild(this.finesTbody.childNodes[0]);

    // when user clicks on a selector checkbox, update the total owed
    var updateSelected = function() {
        var total = 0;
        dojo.forEach(
            dojo.query('[name=selector]', this.finesTbody),
            function(input) {
                if(input.checked)
                    total += Number(input.getAttribute('balance_owed'));
            }
        );

        total = total.toFixed(2);
        dojo.byId('oils-selfck-selected-total').innerHTML = 
            dojo.string.substitute(localeStrings.TOTAL_FINES_SELECTED, [total]);
    }

    // wire up the batch on/off selector
    var sel = dojo.byId('oils-selfck-fines-selector');
    sel.onchange = function() {
        dojo.forEach(
            dojo.query('[name=selector]', this.finesTbody),
            function(input) {
                input.checked = sel.checked;
            }
        );
    };

    var self = this;
    var handler = function(dataList) {

        self.finesCount = dataList.length;
        self.finesData = dataList;

        for(var i in dataList) {

            var data = dataList[i];
            var row = self.finesTemplate.cloneNode(true);
            var type = data.transaction.xact_type();

            if(type == 'circulation') {
                self.byName(row, 'type').innerHTML = type;
                self.byName(row, 'details').innerHTML = data.record.title();

            } else if(type == 'grocery') {
                self.byName(row, 'type').innerHTML = 'Miscellaneous'; // Go ahead and head off any confusion around "grocery".  TODO i18n
                self.byName(row, 'details').innerHTML = data.transaction.last_billing_type();
            }

            self.byName(row, 'total_owed').innerHTML = data.transaction.total_owed();
            self.byName(row, 'total_paid').innerHTML = data.transaction.total_paid();
            self.byName(row, 'balance').innerHTML = data.transaction.balance_owed();

            // row selector
            var selector = self.byName(row, 'selector')
            selector.onchange = updateSelected;
            selector.setAttribute('xact', data.transaction.id());
            selector.setAttribute('balance_owed', data.transaction.balance_owed());
            selector.checked = true;

            self.finesTbody.appendChild(row);
        }

        updateSelected();
    }


    fieldmapper.standardRequest( 
        ['open-ils.actor', 'open-ils.actor.user.transactions.have_balance.fleshed'],
        {   async : true,
            params : [this.authtoken, this.patron.id()],
            oncomplete : function(r) { 
                progressDialog.hide();
                handler(openils.Util.readResponse(r));
            }
        }
    );
}

SelfCheckManager.prototype.checkin = function(barcode, abortTransit) {

    var resp = fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.transit.abort'],
        {params : [this.authtoken, {barcode : barcode}]}
    );

    // resp == 1 on success
    if(openils.Event.parse(resp))
        return false;

    var resp = fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.checkin.override'],
        {params : [
            this.authtoken, {
                patron_id : this.patron.id(),
                copy_barcode : barcode,
                noop : true
            }
        ]}
    );

    if(!resp.length) resp = [resp];
    for(var i = 0; i < resp.length; i++) {
        var tc = openils.Event.parse(resp[i]).textcode;
        if(tc == 'SUCCESS' || tc == 'NO_CHANGE') {
            continue;
        } else {
            return false;
        }
    }

    return true;
}

/**
 * Check out a single item.  If the item is already checked 
 * out to the patron, redirect to renew()
 */
SelfCheckManager.prototype.checkout = function(barcode, override) {

    this.prevCirc = null;

    if(!barcode) {
        this.updateScanbox(null, true);
        return;
    }

    if(this.mockCheckouts) {
        // if we're in mock-checkout mode, just insert another
        // fake circ into the table and get out of here.
        this.displayCheckout(this.mockCheckout, 'checkout');
        return;
    }

    // TODO see if it's a patron barcode
    // TODO see if this item has already been checked out in this session

    var method = 'open-ils.circ.checkout.full';
    if(override) method += '.override';

    console.log("Checkout out item " + barcode + " with method " + method);

    var result = fieldmapper.standardRequest(
        ['open-ils.circ', method],
        {params: [
            this.authtoken, {
                patron_id : this.patron.id(),
                copy_barcode : barcode
            }
        ]}
    );

    var stat = this.handleXactResult('checkout', barcode, result);

    if(stat.override) {
        this.checkout(barcode, true);
    } else if(stat.doOver) {
        this.checkout(barcode);
    } else if(stat.renew) {
        this.renew(barcode);
    }
}

SelfCheckManager.prototype.failPartMessage = function(result) {
    if (result.payload && result.payload.fail_part) {
        var stringKey = "FAIL_PART_" +
            result.payload.fail_part.replace(/\./g, "_");
        return localeStrings[stringKey];
    } else {
        return null;
    }
}

SelfCheckManager.prototype.handleXactResult = function(action, item, result) {

    var displayText = '';

    // If true, the display message is important enough to pop up.  Whether or not
    // an alert() actually occurs, depends on org unit settings
    var popup = false;  
    var sound = ''; // sound file reference
    var payload = result.payload || {};
    var overrideEvents = this.orgSettings[SET_AUTO_OVERRIDE_EVENTS];
    var blockStatuses = this.orgSettings[SET_BLOCK_CHECKOUT_ON_COPY_STATUS];
        
    if(result.textcode == 'NO_SESSION') {

        return this.logoutStaff();

    } else if(result.textcode == 'SUCCESS') {

        if(action == 'checkout') {

            displayText = dojo.string.substitute(localeStrings.CHECKOUT_SUCCESS, [item]);
            this.displayCheckout(result, 'checkout');

            if(payload.holds_fulfilled && payload.holds_fulfilled.length) {
                // A hold was fulfilled, update the hold numbers in the circ summary
                console.log("fulfilled hold " + payload.holds_fulfilled + " during checkout");
                this.holdsSummary = null;
                this.updateHoldsSummary();
            }

            this.updateCircSummary(true);

        } else if(action == 'renew') {

            displayText = dojo.string.substitute(localeStrings.RENEW_SUCCESS, [item]);
            this.displayCheckout(result, 'renew');
        }

        this.checkouts.push({circ : result.payload.circ.id()});
        sound = 'checkout-success';
        this.updateScanBox();

    } else if(result.textcode == 'OPEN_CIRCULATION_EXISTS' && action == 'checkout') {

        // Server says the item is already checked out.  If it's checked out to the
        // current user, we may need to renew it.  

        if(payload.old_circ) { 

            /*
            old_circ refers to the previous checkout IFF it's for the same user. 
            If no auto-renew interval is not defined, assume we should renew it
            If an auto-renew interval is defined and the payload comes back with
            auto_renew set to true, do the renewal.  Otherwise, let the patron know
            the item is already checked out to them.  */

            if( !this.orgSettings[SET_AUTO_RENEW_INTERVAL] ||
                (this.orgSettings[SET_AUTO_RENEW_INTERVAL] && payload.auto_renew) ) {
                this.prevCirc = payload.old_circ.id();
                return { renew : true };
            }

            popup = true;
            sound = 'checkout-failure';
            displayText = dojo.string.substitute(localeStrings.ALREADY_OUT, [item]);

        } else {

            if( // copy is marked lost.  if configured to do so, check it in and try again.
                result.payload.copy && 
                result.payload.copy.status() == /* LOST */ 3 &&
                overrideEvents && overrideEvents.length &&
                overrideEvents.indexOf('COPY_STATUS_LOST') != -1) {

                    if(this.checkin(item)) {
                        return { doOver : true };
                    }
            }

            
            // item is checked out to some other user
            popup = true;
            sound = 'checkout-failure';
            displayText = dojo.string.substitute(localeStrings.OPEN_CIRCULATION_EXISTS, [item]);
        }

        this.updateScanBox({select:true});

    } else {

    
        if(overrideEvents && overrideEvents.length) {
            
            // see if the events we received are all in the list of
            // events to override
    
            if(!result.length) result = [result];
    
            var override = true;
            for(var i = 0; i < result.length; i++) {

                var match = overrideEvents.filter(function(e) { return (e == result[i].textcode); })[0];

                if(!match) {
                    override = false;
                    break;
                }

                if(result[i].textcode == 'COPY_NOT_AVAILABLE' && blockStatuses && blockStatuses.length) {

                    var stat = result[i].payload.status(); // copy status
                    if(typeof stat == 'object') stat = stat.id();

                    var match2 = blockStatuses.filter(function(e) { return (e == stat); })[0];

                    if(match2) { // copy is in a blocked status
                        override = false;
                        break;
                    }
                }

                if(result[i].textcode == 'COPY_IN_TRANSIT') {
                    // to override a transit, we have to abort the transit and check it in first
                    if(this.checkin(item, true)) {
                        return { doOver : true };
                    } else {
                        override = false;
                    }
                }
            }

            if(override) 
                return { override : true };
        }
    
        this.updateScanBox({select : true});
        popup = true;
        sound = 'checkout-failure';

        if(action == 'renew')
            this.checkouts.push({circ : this.prevCirc, renewal_failure : true});

        if(result.length) 
            result = result[0];

        switch(result.textcode) {

            // TODO custom handler for blocking penalties

            case 'MAX_RENEWALS_REACHED' :
                displayText = dojo.string.substitute(
                    localeStrings.MAX_RENEWALS, [item]);
                break;

            case 'ITEM_NOT_CATALOGED' :
                displayText = dojo.string.substitute(
                    localeStrings.ITEM_NOT_CATALOGED, [item]);
                break;

            case 'OPEN_CIRCULATION_EXISTS' :
                displayText = dojo.string.substitute(
                    localeStrings.OPEN_CIRCULATION_EXISTS, [item]);

                break;

            default:
                console.error('Unhandled event ' + result.textcode);

                if (!(displayText = this.failPartMessage(result))) {
                    if (action == 'checkout' || action == 'renew') {
                        displayText = dojo.string.substitute(
                            localeStrings.GENERIC_CIRC_FAILURE, [item]);
                    } else {
                        displayText = dojo.string.substitute(
                            localeStrings.UNKNOWN_ERROR, [result.textcode]);
                    }
                }
        }
    }

    this.handleAlert(displayText, popup, sound);
    return {};
}


/**
 * Renew an item
 */
SelfCheckManager.prototype.renew = function(barcode, override) {

    var method = 'open-ils.circ.renew';
    if(override) method += '.override';

    console.log("Renewing item " + barcode + " with method " + method);

    var result = fieldmapper.standardRequest(
        ['open-ils.circ', method],
        {params: [
            this.authtoken, {
                patron_id : this.patron.id(),
                copy_barcode : barcode
            }
        ]}
    );

    console.log(js2JSON(result));

    var stat = this.handleXactResult('renew', barcode, result);

    if(stat.override)
        this.renew(barcode, true);
}

/**
 * Display the result of a checkout or renewal in the items out table
 */
SelfCheckManager.prototype.displayCheckout = function(evt, type, itemsOut) {

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
    openils.Util.show(this.byName(row, type));

    var date = dojo.date.stamp.fromISOString(circ.due_date());
    this.byName(row, 'due_date').innerHTML = 
        dojo.date.locale.format(date, {selector : 'date'});

    // put new circs at the top of the list
    var tbody = this.circTbody;
    if(itemsOut) tbody = this.itemsOutTbody;
    tbody.insertBefore(row, tbody.getElementsByTagName('tr')[0]);
}


SelfCheckManager.prototype.byName = function(node, name) {
    return dojo.query('[name=' + name+']', node)[0];
}


SelfCheckManager.prototype.initPrinter = function() {
    try { // Mozilla only
		netscape.security.PrivilegeManager.enablePrivilege("UniversalBrowserRead");
        netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
        netscape.security.PrivilegeManager.enablePrivilege('UniversalPreferencesRead');
        netscape.security.PrivilegeManager.enablePrivilege('UniversalPreferencesWrite');
        var pref = Components.classes["@mozilla.org/preferences-service;1"].getService(Components.interfaces.nsIPrefBranch);
        if (pref)
            pref.setBoolPref('print.always_print_silent', true);
    } catch(E) {
        console.log("Unable to initialize auto-printing"); 
    }
}

/**
 * Print a receipt for this session's checkouts
 */
SelfCheckManager.prototype.printSessionReceipt = function(callback) {

    var circIds = [];
    var circCtx = []; // circ context data.  in this case, renewal_failure info

    // collect the circs and failure info
    dojo.forEach(
        this.checkouts, 
        function(blob) {
            circIds.push(blob.circ);
            circCtx.push({renewal_failure:blob.renewal_failure});
        }
    );

    var params = [
        this.authtoken, 
        this.staff.ws_ou(),
        null,
        'format.selfcheck.checkout',
        'print-on-demand',
        circIds,
        circCtx
    ];

    var self = this;
    fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.fire_circ_trigger_events'],
        {   
            async : true,
            params : params,
            oncomplete : function(r) {
                var resp = openils.Util.readResponse(r);
                var output = resp.template_output();
                if(output) {
                    self.printData(output.data(), self.checkouts.length, callback); 
                } else {
                    var error = resp.error_output();
                    if(error) {
                        throw new Error("Error creating receipt: " + error.data());
                    } else {
                        throw new Error("No receipt data returned from server");
                    }
                }
            }
        }
    );
}

SelfCheckManager.prototype.printData = function(data, numItems, callback) {

    var win = window.open('', '', 'resizable,width=700,height=500,scrollbars=1,chrome'); 
    win.document.body.innerHTML = data;
    win.print();

    /*
     * There is no way to know when the browser is done printing.
     * Make a best guess at when to close the print window by basing
     * the setTimeout wait on the number of items to be printed plus
     * a small buffer
     */
    var sleepTime = 1000;
    if(numItems > 0) 
        sleepTime += (numItems / 2) * 1000;

    setTimeout(
        function() { 
            win.close(); // close the print window
            if(callback)
                callback(); // fire optional post-print callback
        },
        sleepTime 
    );
}


/**
 * Print a receipt for this user's items out
 */
SelfCheckManager.prototype.printItemsOutReceipt = function(callback) {

    if(!this.itemsOut.length) return;

    progressDialog.show(true);

    var params = [
        this.authtoken, 
        this.staff.ws_ou(),
        null,
        'format.selfcheck.items_out',
        'print-on-demand',
        this.itemsOut
    ];

    var self = this;
    fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.fire_circ_trigger_events'],
        {   
            async : true,
            params : params,
            oncomplete : function(r) {
                progressDialog.hide();
                var resp = openils.Util.readResponse(r);
                var output = resp.template_output();
                if(output) {
                    self.printData(output.data(), self.itemsOut.length, callback); 
                } else {
                    var error = resp.error_output();
                    if(error) {
                        throw new Error("Error creating receipt: " + error.data());
                    } else {
                        throw new Error("No receipt data returned from server");
                    }
                }
            }
        }
    );
}

/**
 * Print a receipt for this user's items out
 */
SelfCheckManager.prototype.printHoldsReceipt = function(callback) {

    if(!this.holds.length) return;

    progressDialog.show(true);

    var holdIds = [];
    var holdData = [];

    dojo.forEach(this.holds,
        function(data) {
            holdIds.push(data.hold.id());
            if(data.status == 4) {
                holdData.push({ready : true});
            } else {
                holdData.push({
                    queue_position : data.queue_position, 
                    potential_copies : data.potential_copies
                });
            }
        }
    );

    var params = [
        this.authtoken, 
        this.staff.ws_ou(),
        null,
        'format.selfcheck.holds',
        'print-on-demand',
        holdIds,
        holdData
    ];

    var self = this;
    fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.fire_hold_trigger_events'],
        {   
            async : true,
            params : params,
            oncomplete : function(r) {
                progressDialog.hide();
                var resp = openils.Util.readResponse(r);
                var output = resp.template_output();
                if(output) {
                    self.printData(output.data(), self.holds.length, callback); 
                } else {
                    var error = resp.error_output();
                    if(error) {
                        throw new Error("Error creating receipt: " + error.data());
                    } else {
                        throw new Error("No receipt data returned from server");
                    }
                }
            }
        }
    );
}


SelfCheckManager.prototype.printPaymentReceipt = function(response, callback) {
    
    var self = this;
    progressDialog.show(true);

    fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.money.payment_receipt.print'],
        {
            async : true,
            params : [this.authtoken, response.payments],
            oncomplete : function(r) {
                var resp = openils.Util.readResponse(r);
                var output = resp.template_output();
                progressDialog.hide();
                if(output) {
                    self.printData(output.data(), 1, callback); 
                } else {
                    var error = resp.error_output();
                    if(error) {
                        throw new Error("Error creating receipt: " + error.data());
                    } else {
                        throw new Error("No receipt data returned from server");
                    }
                }
            }
        }
    );
}

/**
 * Print a receipt for this user's items out
 */
SelfCheckManager.prototype.printFinesReceipt = function(callback) {

    progressDialog.show(true);

    var params = [
        this.authtoken, 
        this.staff.ws_ou(),
        null,
        'format.selfcheck.fines',
        'print-on-demand',
        [this.patron.id()]
    ];

    var self = this;
    fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.fire_user_trigger_events'],
        {   
            async : true,
            params : params,
            oncomplete : function(r) {
                progressDialog.hide();
                var resp = openils.Util.readResponse(r);
                var output = resp.template_output();
                if(output) {
                    self.printData(output.data(), self.finesCount, callback); 
                } else {
                    var error = resp.error_output();
                    if(error) {
                        throw new Error("Error creating receipt: " + error.data());
                    } else {
                        throw new Error("No receipt data returned from server");
                    }
                }
            }
        }
    );
}




/**
 * Logout the patron and return to the login page
 */
SelfCheckManager.prototype.logoutPatron = function(print) {
    progressDialog.show(true); // prevent patron from clicking logout link twice
    if(print && this.checkouts.length) {
        this.printSessionReceipt(
            function() {
                location.href = location.href;
            }
        );
    } else {
        location.href = location.href;
    }
}


/**
 * Fire up the manager on page load
 */
openils.Util.addOnLoad(
    function() {
        new SelfCheckManager().init();
    }
);
