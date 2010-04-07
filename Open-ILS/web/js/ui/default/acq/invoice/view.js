dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.CurrencyTextBox');
dojo.require('dijit.form.NumberTextBox');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.CGI');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.EditPane');
dojo.require('openils.widget.AutoFieldWidget');

dojo.requireLocalization('openils.acq', 'acq');
var localeStrings = dojo.i18n.getLocalization('openils.acq', 'acq');

var fundLabelFormat = ['${0} (${1})', 'code', 'year'];
var fundSearchFormat = ['${0} (${1})', 'code', 'year'];

var cgi = new openils.CGI();
var pcrud = new openils.PermaCrud();
var attachLi;
var attachPo;
var invoice;
var itemTbody;
var itemTemplate;
var entryTemplate;
var totalAmountBox;
var invoicePane;
var itemTypes;

function nodeByName(name, context) {
    return dojo.query('[name='+name+']', context)[0];
}

function init() {

    attachLi = cgi.param('attach_li');
    attachPo = cgi.param('attach_po');

    itemTypes = pcrud.retrieveAll('aiit');

    if(cgi.param('create')) {
        renderInvoice();

    } else {
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.invoice.retrieve'],
            {
                params : [openils.User.authtoken, invoiceId],
                oncomplete : function(r) {
                    invoice = openils.Util.readResponse(r);     
                    renderInvoice();
                }
            }
        );
    }
}

function renderInvoice() {

    // in create mode, let the LI or PO render the invoice with seed data
    if( !(cgi.param('create') && (attachPo || attachLi)) ) {
        invoicePane = drawInvoicePane(dojo.byId('acq-view-invoice-div'), invoice);
    }

    dojo.byId('acq-invoice-new-item').onclick = function() {
        addInvoiceItem(new fieldmapper.acqii()); 
    }

    addToTotal(0);

    if(invoice) {
        dojo.forEach(
            invoice.items(),
            function(item) {
                addInvoiceItem(item);
            }
        );

        dojo.forEach(
            invoice.entries(),
            function(entry) {
                addInvoiceEntry(entry);
            }
        );
    }

    if(attachLi) doAttachLi();
    if(attachPo) doAttachPo();
}

function doAttachLi() {

    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.lineitem.retrieve"], {
            async: true,
            params: [openils.User.authtoken, attachLi, {
                clear_marc : true,
                flesh_attrs : true,
                flesh_po : true,
            }],
            oncomplete: function(r) { 
                lineitem = openils.Util.readResponse(r);

                if(cgi.param('create')) {
                    // render the invoice using some seed data from the Lineitem
                    var invoiceArgs = {provider : lineitem.provider(), shipper : lineitem.provider()}; 
                    invoicePane = drawInvoicePane(dojo.byId('acq-view-invoice-div'), null, invoiceArgs);
                }

                var entry = new fieldmapper.acqie();
                entry.isnew(true);
                entry.lineitem(lineitem);
                addInvoiceEntry(entry);
            }
        }
    );
}

function doAttachPo() {
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.purchase_order.retrieve'],
        {   async: true,
            params: [openils.User.authtoken, attachPo, {
                flesh_lineitems : true,
                clear_marc : true
            }],
            oncomplete: function(r) {
                var po = openils.Util.readResponse(r);

                if(cgi.param('create')) {
                    // render the invoice using some seed data from the PO
                    var invoiceArgs = {provider : po.provider(), shipper : po.provider()}; 
                    invoicePane = drawInvoicePane(dojo.byId('acq-view-invoice-div'), null, invoiceArgs);
                }

                dojo.forEach(po.lineitems(), 
                    function(lineitem) {
                        var entry = new fieldmapper.acqie();
                        entry.isnew(true);
                        entry.lineitem(lineitem);
                        addInvoiceEntry(entry);
                    }
                );
            }
        }
    );
}

function addToTotal(amount) {

    var oldTotal = 0;
    if(totalAmountBox) {
        oldTotal = totalAmountBox.attr('value');
    } else {
        totalAmountBox = new dijit.form.CurrencyTextBox(
            {style : 'width: 5em'}, dojo.byId('acq-invoice-total-invoiced'));
    }

    totalAmountBox.attr('value', Number(oldTotal + amount));
}

function addInvoiceItem(item) {
    itemTbody = dojo.byId('acq-invoice-item-tbody');
    if(itemTemplate == null) {
        itemTemplate = itemTbody.removeChild(dojo.byId('acq-invoice-item-template'));
    }

    var row = itemTemplate.cloneNode(true);
    var itemType = itemTypes.filter(function(t) { return (t.code() == item.inv_item_type()) })[0];

    new dijit.form.TextBox({}, nodeByName('title', row));
    new dijit.form.TextBox({}, nodeByName('author', row));
    new dijit.form.CurrencyTextBox({required : true, style : 'width: 5em'}, nodeByName('cost_billed', row));


    var fundDebit = item.fund_debit();
    var fundFilter = {active : 't'};
    if(fundDebit) {
        
        // If a fund debit exists, this item has been "applied" to the invoice
        fundFilter = {'-or' : [{id : fundDebit.fund()}, fundFilter]}

    } else {

        fundDebit = new fieldmapper.acqfdeb();
        //new dijit.form.CheckBox({}, nodeByName('prorate', row));
    }

    var itemType = itemTypes.filter(function(t) { return (t.code() == item.inv_item_type()) })[0];

    var fundWidget = new openils.widget.AutoFieldWidget({
        fmObject : fundDebit,
        fmField : 'fund',
        labelFormat : fundLabelFormat,
        searchFormat : fundSearchFormat,
        searchFilter : fundFilter,
        dijitArgs : 
            (!item.fund_debit() && itemType && openils.Util.isTrue(itemType.prorate())) ? 
                {disabled : true} : {},
        parentNode : nodeByName('fund', row)
    });
    fundWidget.build();


    new openils.widget.AutoFieldWidget({
        fmObject : item,
        fmField : 'inv_item_type',
        parentNode : nodeByName('inv_item_type', row),
        dijitArgs : {required : true}
    }).build(
        function(w, ww) {
            // When the inv_item_type is set to prorate=true, don't allow the user the edit the fund
            // since this charge will be prorated against (potentially) multiple funds
            dojo.connect(w, 'onChange', 
                function() {
                    if(!item.fund_debit()) {
                        var itemType = itemTypes.filter(function(t) { return (t.code() == w.attr('value')) })[0];
                        if(openils.Util.isTrue(itemType.prorate())) {
                            fundWidget.widget.attr('disabled', true);
                            fundWidget.widget.attr('value', '');
                        } else {
                            fundWidget.widget.attr('disabled', false);
                        }
                    }
                }
            );
        }
    );

    nodeByName('delete', row).onclick = function() {
        // TODO: confirm, etc.
        itemTbody.removeChild(row);
    }

    itemTbody.appendChild(row);
}

function addInvoiceEntry(entry) {
    entryTbody = dojo.byId('acq-invoice-entry-tbody');
    if(entryTemplate == null) {
        entryTemplate = entryTbody.removeChild(dojo.byId('acq-invoice-entry-template'));
    }

    if(dojo.query('[lineitem=' + entry.lineitem().id() +']', entryTbody)[0])
        // Is it ever valid to have multiple entries for 1 lineitem in a single invoice?
        return;

    var row = entryTemplate.cloneNode(true);
    row.setAttribute('lineitem', entry.lineitem().id());
    var lineitem = entry.lineitem();

    var idents = [];
    if(liMarcAttr(lineitem, 'isbn')) idents.push(liMarcAttr(lineitem, 'isbn'));
    if(liMarcAttr(lineitem, 'upc')) idents.push(liMarcAttr(lineitem, 'upc'));
    if(liMarcAttr(lineitem, 'issn')) idents.push(liMarcAttr(lineitem, 'issn'));

    nodeByName('title', row).innerHTML = liMarcAttr(lineitem, 'title');
    nodeByName('author', row).innerHTML = liMarcAttr(lineitem, 'author');
    nodeByName('idents', row).innerHTML = idents.join(',');

    if(entry.purchase_order()) {
        openils.Util.show(nodeByName('purchase_order_span', row), 'inline');
        nodeByName('purchase_order', row).innerHTML = entry.purchase_order().name();
        nodeByName('purchase_order', row).onclick = function() {
            location.href = oilsBasePath + '/acq/po/view/ ' + entry.purchase_order().id();
        }
    }

    new dijit.form.NumberTextBox(
        {value : entry.inv_item_count(), required : true, constraints : {min: 0}, style : 'width:5em'}, 
        nodeByName('inv_item_count', row));

    new dijit.form.NumberTextBox(
        {value : entry.phys_item_count(), required : true, constraints : {min: 0}, style : 'width:5em'}, 
        nodeByName('phys_item_count', row));

    new dijit.form.CurrencyTextBox(
        {value : entry.cost_billed(), required : true, style : 'width: 5em'}, 
        nodeByName('cost_billed', row));

    nodeByName('detach', row).onclick = function() {
        // TODO: confirm, etc.
        entryTbody.removeChild(row);
    }

    entryTbody.appendChild(row);
}

function liMarcAttr(lineitem, name) {
    var attr = lineitem.attributes().filter(
        function(attr) { 
            if(
                attr.attr_type() == 'lineitem_marc_attr_definition' && 
                attr.attr_name() == name) 
                    return attr 
        } 
    )[0];
    return (attr) ? attr.attr_value() : '';
}



openils.Util.addOnLoad(init);


