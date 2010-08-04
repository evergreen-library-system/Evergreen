function PaymentForm() {}
var proto = (typeof(SelfCheckManager) == "undefined" ?
    PaymentForm : SelfCheckManager).prototype;

proto.drawPayFinesPage = function(patron, total, xacts, onPaymentSubmit) {
    if (typeof(this.authtoken) == "undefined")
        this.authtoken = patron.session;

    dojo.query("span", "oils-selfck-cc-payment-summary")[0].innerHTML = total;

    oilsSelfckCCNumber.attr('value', '');
    oilsSelfckCCCVV.attr('value', '');
    oilsSelfckCCMonth.attr('value', '01');
    oilsSelfckCCYear.attr('value', new Date().getFullYear());
    oilsSelfckCCFName.attr('value', patron.first_given_name());
    oilsSelfckCCLName.attr('value', patron.family_name());

    var addr = patron.billing_address() || patron.mailing_address();

    if (typeof(addr) != "object") {
        /* still don't have usable address? try getting better user object. */
        fieldmapper.standardRequest(
            ["open-ils.actor", "open-ils.actor.user.fleshed.retrieve"], {
                "params": [
                    patron.session, patron.id(), [
                        "billing_address", "mailing_address"
                    ]
                ],
                "async": false,
                "oncomplete": function(r) {
                    var usr = openils.Util.readResponse(r);
                    if (usr)
                        addr = usr.billing_address() || usr.mailing_address();
                }
            }
        );
    }

    if (addr) {
        oilsSelfckCCStreet.attr('value', addr.street1()+' '+addr.street2());
        oilsSelfckCCCity.attr('value', addr.city());
        oilsSelfckCCState.attr('value', addr.state());
        oilsSelfckCCZip.attr('value', addr.post_code());
    }

    dojo.connect(oilsSelfckEditDetails, 'onChange',
        function(newVal) {
            dojo.forEach(
                [   oilsSelfckCCFName,
                    oilsSelfckCCLName,
                    oilsSelfckCCStreet,
                    oilsSelfckCCCity,
                    oilsSelfckCCState,
                    oilsSelfckCCZip
                ],
                function(dij) { dij.attr('disabled', !newVal); }
            );
        }
    );


    var self = this;
    dojo.connect(oilsSelfckCCSubmit, 'onClick',
        function() {
            /* XXX better to replace this check on progressDialog with some
             * kind of passed-in function to support different use cases */
            if (typeof(progressDialog) != "undefined")
                progressDialog.show(true);

            self.sendCCPayment(patron, xacts, onPaymentSubmit);
        }
    );
}

// In this form, this code only supports global on/off credit card
// payments and does not dissallow payments to transactions that started
// at remote locations or transactions that have accumulated billings at
// remote locations that dissalow credit card payments.
// TODO add per-transaction blocks for orgs that do not support CC payments

proto.sendCCPayment = function(patron, xacts, onPaymentSubmit) {

    var args = {
        userid : patron.id(),
        payment_type : 'credit_card_payment',
        payments : xacts,
        cc_args : {
            where_process : 1,
            //type : oilsSelfckCCType.attr('value'),
            number : oilsSelfckCCNumber.attr('value'),
            cvv2 : oilsSelfckCCCVV.attr('value'),
            expire_year : oilsSelfckCCYear.attr('value'),
            expire_month : oilsSelfckCCMonth.attr('value'),
            billing_first : oilsSelfckCCFName.attr('value'),
            billing_last : oilsSelfckCCLName.attr('value'),
            billing_address : oilsSelfckCCStreet.attr('value'),
            billing_city : oilsSelfckCCCity.attr('value'),
            billing_state : oilsSelfckCCState.attr('value'),
            billing_zip : oilsSelfckCCZip.attr('value')
        }
    }

    var resp = fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.money.payment'],
        {params : [this.authtoken, args, patron.last_xact_id()]}
    );

    if (typeof(progressDialog) != "undefined")
        progressDialog.hide();

    if (typeof(onPaymentSubmit) == "function") {
        onPaymentSubmit(resp);
    } else {
        var evt = openils.Event.parse(resp);
        if (evt) alert(evt);
    }
}
