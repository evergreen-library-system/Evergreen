if(!dojo._hasResource['openils.acq.Fund']) {
dojo._hasResource['openils.acq.Fund'] = true;
dojo.provide('openils.acq.Fund');
dojo.require('util.Dojo');

/** Declare the Fund class with dojo */
dojo.declare('openils.acq.Fund', null, {
    /* add instance methods here if necessary */
});


openils.acq.Fund.loadGrid = function(domId, columns) {
    /** Fetches the list of funds and builds a grid from them */

    var ses = new OpenSRF.ClientSession('open-ils.acq');
    var req = ses.request('open-ils.acq.fund.org.retrieve', 
        oilsAuthtoken, null, {flesh_summary:1}); /* XXX make this a streaming call */

    req.oncomplete = function(r) {
        var funds = r.recv().content();
        var items = [];

        for(var f in funds) {
            var fund = funds[f];

            items.push({
                id:fund.id(),
                name:fund.name(), 
                org: findOrgUnit(fund.org()).name(),
                currency_type:fund.currency_type(),
                year:fund.year(),
                combined_balance:fund.summary()['combined_balance']
            });
        }
        util.Dojo.buildSimpleGrid(domId, columns, items);
    };
    req.send();
};
}

