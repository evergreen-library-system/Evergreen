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
dojo.require('openils.widget.ProgressDialog');

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
var totalInvoicedBox;
var totalPaidBox;
var invoicePane;
var itemTypes;
var virtualId = -1;
var widgetRegistry = {acqie : {}, acqii : {}};

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
        var item = new fieldmapper.acqii();
        item.id(virtualId--);
        item.isnew(true);
        addInvoiceItem(item);
    }

    updateTotalCost();

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
                flesh_li_details : true,
                flesh_fund_debit : true
            }],
            oncomplete: function(r) { 
                lineitem = openils.Util.readResponse(r);

                if(cgi.param('create')) {
                    // render the invoice using some seed data from the Lineitem
                    var invoiceArgs = {provider : lineitem.provider(), shipper : lineitem.provider()}; 
                    invoicePane = drawInvoicePane(dojo.byId('acq-view-invoice-div'), null, invoiceArgs);
                }

                var entry = new fieldmapper.acqie();
                entry.id(virtualId--);
                entry.isnew(true);
                entry.lineitem(lineitem);
                entry.purchase_order(lineitem.purchase_order());
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
                clear_marc : true,
                flesh_lineitem_details : true,
                flesh_fund_debit : true
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
                        entry.id(virtualId--);
                        entry.isnew(true);
                        entry.lineitem(lineitem);
                        entry.purchase_order(po);
                        lineitem.purchase_order(po);
                        addInvoiceEntry(entry);
                    }
                );
            }
        }
    );
}

function updateTotalCost() {

    var totalCost = 0;    
    if(!totalInvoicedBox) {
        totalInvoicedBox = new dijit.form.CurrencyTextBox(
            {style : 'width: 5em'}, dojo.byId('acq-invoice-total-invoiced'));
    }
    for(var id in widgetRegistry.acqii) 
        if(!widgetRegistry.acqii[id]._object.isdeleted())
            totalCost += widgetRegistry.acqii[id].cost_billed.getFormattedValue();
    for(var id in widgetRegistry.acqie) 
        if(!widgetRegistry.acqie[id]._object.isdeleted())
            totalCost += widgetRegistry.acqie[id].cost_billed.getFormattedValue();
    totalInvoicedBox.attr('value', totalCost);

    totalPaid = 0;    
    if(!totalPaidBox) {
        totalPaidBox = new dijit.form.CurrencyTextBox(
            {style : 'width: 5em'}, dojo.byId('acq-invoice-total-paid'));
    }
    for(var id in widgetRegistry.acqii) 
        if(!widgetRegistry.acqii[id]._object.isdeleted())
            totalPaid += widgetRegistry.acqii[id].amount_paid.getFormattedValue();
    for(var id in widgetRegistry.acqie) 
        if(!widgetRegistry.acqie[id]._object.isdeleted())
            totalPaid += widgetRegistry.acqie[id].amount_paid.getFormattedValue();
    totalPaidBox.attr('value', totalPaid);

    var buttonsDisabled = false;
    if(totalPaid > totalCost || totalPaid < 0) {
        openils.Util.addCSSClass(totalPaidBox.domNode, 'acq-invoice-invalid-amount');
        invoiceSaveButton.attr('disabled', true);
        invoiceProrateButton.attr('disabled', true);
        buttonsDisabled = true;
    } else {
        openils.Util.removeCSSClass(totalPaidBox.domNode, 'acq-invoice-invalid-amount');
        invoiceSaveButton.attr('disabled', false);
        invoiceProrateButton.attr('disabled', false);
    }

    if(totalCost < 0) {
        openils.Util.addCSSClass(totalInvoicedBox.domNode, 'acq-invoice-invalid-amount');
        invoiceSaveButton.attr('disabled', true);
        invoiceProrateButton.attr('disabled', true);
    } else {
        openils.Util.removeCSSClass(totalInvoicedBox.domNode, 'acq-invoice-invalid-amount');
        if(!buttonsDisabled) {
            invoiceSaveButton.attr('disabled', false);
            invoiceProrateButton.attr('disabled', false);
        }
    }
}


function registerWidget(obj, field, widget, callback) {
    var blob = widgetRegistry[obj.classname];
    if(!blob[obj.id()]) 
        blob[obj.id()] = {_object : obj};
    blob[obj.id()][field] = widget;
    widget.build(
        function(w, ww) {
            dojo.connect(w, 'onChange', 
                function(newVal) { 
                    obj.ischanged(true); 
                    updateTotalCost();
                }
            );
            if(callback) callback(w, ww);
        }
    );
    return widget;
}

function addInvoiceItem(item) {
    itemTbody = dojo.byId('acq-invoice-item-tbody');
    if(itemTemplate == null) {
        itemTemplate = itemTbody.removeChild(dojo.byId('acq-invoice-item-template'));
    }

    var row = itemTemplate.cloneNode(true);
    var itemType = itemTypes.filter(function(t) { return (t.code() == item.inv_item_type()) })[0];

    dojo.forEach(
        ['title', 'author', 'cost_billed', 'amount_paid'], 
        function(field) {
            registerWidget(
                item,
                field,
                new openils.widget.AutoFieldWidget({
                    fmClass : 'acqii',
                    fmObject : item,
                    fmField : field,
                    dijitArgs : (field == 'cost_billed' || field == 'amount_paid') ? {required : true, style : 'width: 5em'} : null,
                    parentNode : nodeByName(field, row)
                })
            )
        }
    );


    /* ----------- fund -------------- */
    var fundArgs = {
        fmClass : 'acqii',
        fmObject : item,
        fmField : 'fund',
        labelFormat : fundLabelFormat,
        searchFormat : fundSearchFormat,
        parentNode : nodeByName('fund', row)
    }

    if(item.fund_debit()) {
        fundArgs.searchFilter = {'-or' : [{active : 't'}, {id : item.fund()}]};
    } else {
        fundArgs.searchFilter = {active : 't'}
        if(itemType && openils.Util.isTrue(itemType.prorate()))
            fundArgs.dijitArgs = {disabled : true};
    }

    var fundWidget = new openils.widget.AutoFieldWidget(fundArgs);
    registerWidget(item, 'fund', fundWidget);

    /* ---------- inv_item_type ------------- */

    registerWidget(
        item,
        'inv_item_type',
        new openils.widget.AutoFieldWidget({
            fmObject : item,
            fmField : 'inv_item_type',
            parentNode : nodeByName('inv_item_type', row),
            dijitArgs : {required : true}
        }),
        function(w, ww) {
            // When the inv_item_type is set to prorate=true, don't allow the user the edit the fund
            // since this charge will be prorated against (potentially) multiple funds
            dojo.connect(w, 'onChange', 
                function() {
                    if(!item.fund_debit()) {
                        var itemType = itemTypes.filter(function(t) { return (t.code() == w.attr('value')) })[0];
                        if(!itemType) return;
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
        var cost = widgetRegistry.acqii[item.id()].cost_billed.getFormattedValue();
        var msg = dojo.string.substitute(
            localeStrings.INVOICE_CONFIRM_ITEM_DELETE, [
                cost,
                widgetRegistry.acqii[item.id()].inv_item_type.getFormattedValue()
            ]
        );
        if(!confirm(msg)) return;
        itemTbody.removeChild(row);
        item.isdeleted(true);
        if(item.isnew())
            delete widgetRegistry.acqii[item.id()];
        updateTotalCost();
    }

    itemTbody.appendChild(row);
    updateTotalCost();
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

    var lids = lineitem.lineitem_details();
    var numOrdered = lids.length;
    var numReceived = lids.filter(function(lid) { return (lid.recv_time() != null) }).length;
    var numInvoiced = lids.filter(function(lid) { return !openils.Util.isTrue(lid.fund_debit().encumbrance()) }).length;

    var poName = '';
    var poId = '';
    var po = entry.purchase_order();
    if(po) {
        poName = po.name();
        poId = po.id();
    }

    nodeByName('title_details', row).innerHTML = 
        dojo.string.substitute(
            localeStrings.INVOICE_TITLE_DETAILS, [
                liMarcAttr(lineitem, 'title'),
                liMarcAttr(lineitem, 'author'),
                idents.join(','),
                numOrdered,
                numReceived,
                Number(lineitem.estimated_unit_price()).toFixed(2),
                (Number(lineitem.estimated_unit_price()) * numOrdered).toFixed(2),
                numInvoiced,
                lineitem.id(),
                oilsBasePath,
                poId,
                poName
            ]
        );


    dojo.forEach(
        ['inv_item_count', 'phys_item_count', 'cost_billed', 'amount_paid'],
        function(field) {
            var dijitArgs = {required : true, constraints : {min: 0}, style : 'width:5em'};
            if(entry.isnew() && field == 'phys_item_count') dijitArgs.value = numReceived;
            registerWidget(
                entry, 
                field,
                new openils.widget.AutoFieldWidget({
                    fmObject : entry,
                    fmClass : 'acqie',
                    fmField : field,
                    dijitArgs : dijitArgs,
                    parentNode : nodeByName(field, row)
                })
            );
        }
    );

    nodeByName('detach', row).onclick = function() {
        var cost = widgetRegistry.acqie[entry.id()].cost_billed.getFormattedValue();
        var msg = dojo.string.substitute(
            localeStrings.INVOICE_CONFIRM_ENTRY_DETACH, [
                cost || 0,
                liMarcAttr(lineitem, 'title'),
                liMarcAttr(lineitem, 'author'),
                idents.join(',')
            ]
        );
        if(!confirm(msg)) return;
        entryTbody.removeChild(row);
        entry.isdeleted(true);
        if(entry.isnew())
            delete widgetRegistry.acqie[entry.id()];
        updateTotalCost();
    }

    entryTbody.appendChild(row);
    updateTotalCost();
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

function saveChanges(doProrate) {
    
    progressDialog.show(true);

    var updateItems = [];
    for(var id in widgetRegistry.acqii) {
        var reg = widgetRegistry.acqii[id];
        var item = reg._object;
        if(item.ischanged() || item.isnew() || item.isdeleted()) {
            updateItems.push(item);
            if(item.isnew()) item.id(null);
            for(var field in reg) {
                if(field != '_object')
                    item[field]( reg[field].getFormattedValue() );
            }
            
            // unflesh
            if(item.purchase_order() != null && typeof item.purchase_order() == 'object')
                item.purchase_order( item.purchase_order().id() );
        }
    }

    var updateEntries = [];
    for(var id in widgetRegistry.acqie) {
        var reg = widgetRegistry.acqie[id];
        var entry = reg._object;
        if(entry.ischanged() || entry.isnew() || entry.isdeleted()) {
            entry.lineitem(entry.lineitem().id());
            entry.purchase_order(entry.purchase_order().id());
            updateEntries.push(entry);
            if(entry.isnew()) entry.id(null);

            for(var field in reg) {
                if(field != '_object')
                    entry[field]( reg[field].getFormattedValue() );
            }
            
            // unflesh
            dojo.forEach(['purchase_order', 'lineitem'],
                function(field) {
                    if(entry[field]() != null && typeof entry[field]() == 'object')
                        entry[field]( entry[field]().id() );
                }
            );
        }
    }

    if(!invoice) {
        invoice = new fieldmapper.acqinv();
        invoice.isnew(true);
    } else {
        invoice.ischanged(true); // for now, just always update
    }

    dojo.forEach(invoicePane.fieldList, 
        function(field) {
            invoice[field.name]( field.widget.getFormattedValue() );
        }
    );

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.invoice.update'],
        {
            params : [openils.User.authtoken, invoice, updateEntries, updateItems],
            oncomplete : function(r) {
                progressDialog.hide();
                var invoice = openils.Util.readResponse(r);
                if(invoice) {
                    if(doProrate)
                        return prorateInvoice();
                    location.href = oilsBasePath + '/acq/invoice/view/' + invoice.id();
                }
            }
        }
    );
}

function prorateInvoice() {
    if(!confirm(localeStrings.INVOICE_CONFIRM_PRORATE)) return;
    progressDialog.show(true);

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.invoice.apply_prorate'],
        {
            params : [openils.User.authtoken, invoice.id()],
            oncomplete : function(r) {
                progressDialog.hide();
                var invoice = openils.Util.readResponse(r);
                if(invoice) {
                    location.href = oilsBasePath + '/acq/invoice/view/' + invoice.id();
                }
            }
        }
    );

}



openils.Util.addOnLoad(init);


