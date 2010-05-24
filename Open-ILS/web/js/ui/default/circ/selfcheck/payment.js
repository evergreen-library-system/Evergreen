var proto = (
    (typeof(SelfCheckManager) == "undefined") ?
        (function PaymentForm() {}) : SelfCheckManager
).prototype;

proto.drawPayFinesPage = function(patron, onPaymentSubmit) {
    if (!this.finesTBody)
        this.finesTBody = dojo.byId("oils-selfck-fines-tbody");

    // find the total selected amount
    var total = 0;
    dojo.forEach(
        dojo.query('[name=selector]', this.finesTbody),
        function(input) {
            if(input.checked)
                total += Number(input.getAttribute('balance_owed'));
        }
    );
    total = total.toFixed(2);

    dojo.query("span", "oils-selfck-cc-payment-summary")[0].innerHTML = total;

    oilsSelfckCCNumber.attr('value', '');
    oilsSelfckCCMonth.attr('value', '01');
    oilsSelfckCCYear.attr('value', new Date().getFullYear());
    oilsSelfckCCFName.attr('value', patron.first_given_name());
    oilsSelfckCCLName.attr('value', patron.family_name());
    var addr = patron.billing_address() || patron.mailing_address();

    if(addr) {
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
            progressDialog.show(true);
            self.sendCCPayment(onPaymentSubmit);
        }
    );
}

// In this form, this code only supports global on/off credit card
// payments and does not dissallow payments to transactions that started
// at remote locations or transactions that have accumulated billings at
// remote locations that dissalow credit card payments.
// TODO add per-transaction blocks for orgs that do not support CC payments

proto.sendCCPayment = function(onPaymentSubmit) {

    var args = {
        userid : this.patron.id(),
        payment_type : 'credit_card_payment',
        payments : [],
        cc_args : {
            where_process : 1,
            number : oilsSelfckCCNumber.attr('value'),
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


    // find the selected transactions
    dojo.forEach(
        dojo.query('[name=selector]', this.finesTbody),
        function(input) {
            if(input.checked) {
                args.payments.push([
                    input.getAttribute('xact'),
                    Number(input.getAttribute('balance_owed')).toFixed(2)
                ]);
            }
        }
    );


    var resp = fieldmapper.standardRequest(
        ['open-ils.circ', 'open-ils.circ.money.payment'],
        {params : [this.authtoken, args]}
    );

    progressDialog.hide();

    var evt = openils.Event.parse(resp);
    if (evt)
        alert(evt);
    else if (typeof(onPaymentSubmit) == "function")
        onPaymentSubmit();
}
