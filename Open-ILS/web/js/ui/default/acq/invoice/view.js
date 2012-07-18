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
dojo.require('openils.acq.Lineitem');

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
var balanceOwedBox;
var invoicePane;
var itemTypes;
var virtualId = -1;
var extraCopies = {};
var extraCopiesFund;
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
            ['open-ils.acq', 'open-ils.acq.invoice.retrieve.authoritative'],
            {
                params : [openils.User.authtoken, invoiceId],
                oncomplete : function(r) {
                    invoice = openils.Util.readResponse(r);     
                    renderInvoice();
                }
            }
        );
    }

    extraCopiesFund = new openils.widget.AutoFieldWidget({
        fmField : 'fund',
        fmClass : 'acqlid',
        searchFilter : {active : 't'},
        labelFormat : fundLabelFormat,
        searchFormat : fundSearchFormat,
        dijitArgs : {required : true},
        parentNode : dojo.byId('acq-invoice-extra-copies-fund')
    });
    extraCopiesFund.build();
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

    if(invoice && openils.Util.isTrue(invoice.complete())) {

        dojo.forEach( // hide widgets that should not be visible for a completed invoice
            dojo.query('.hide-complete'), 
            function(node) { openils.Util.hide(node); }
        );

        new openils.User().getPermOrgList(
            'ACQ_INVOICE_REOPEN', 
            function (orgs) {
                if(orgs.indexOf(invoice.receiver()) >= 0)
                    openils.Util.show('acq-invoice-reopen-button-wrapper', 'inline');
            }, 
            true, 
            true
        );
    }

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

    //var invoiceArgs = {provider : lineitem.provider(), shipper : lineitem.provider()}; 
    if(cgi.param('create')) {

        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.retrieve.authoritative'],
            {
                params : [openils.User.authtoken, attachLi, {clear_marc:1}],
                oncomplete : function(r) {
                    var li = openils.Util.readResponse(r);
                    invoicePane = drawInvoicePane(
                        dojo.byId('acq-view-invoice-div'), null, 
                        {provider : li.provider(), shipper : li.provider()}
                    );
                }
            }
        );
    }

    var entry = new fieldmapper.acqie();
    entry.id(virtualId--);
    entry.isnew(true);
    entry.lineitem(attachLi);
    addInvoiceEntry(entry);
}

function doAttachPo() {

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.purchase_order.retrieve'],
        {   async: true,
            params: [
                openils.User.authtoken, attachPo, 
                {flesh_lineitem_ids : true, flesh_po_items : true}
            ],
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
                        addInvoiceEntry(entry);
                    }
                );

                dojo.forEach(po.po_items(),
                    function(poItem) {
                        var item = new fieldmapper.acqii();
                        item.id(virtualId--);
                        item.isnew(true);
                        item.fund(poItem.fund());
                        item.title(poItem.title());
                        item.author(poItem.author());
                        item.note(poItem.note());
                        item.inv_item_type(poItem.inv_item_type());
                        item.purchase_order(po);
                        item.po_item(poItem);
                        addInvoiceItem(item);
                    }
                );
            }
        }
    );
}

function updateTotalCost() {

    var totalCost = 0;    
    for(var id in widgetRegistry.acqii) 
        if(!widgetRegistry.acqii[id]._object.isdeleted())
            totalCost += Number(widgetRegistry.acqii[id].cost_billed.getFormattedValue());
    for(var id in widgetRegistry.acqie) 
        if(!widgetRegistry.acqie[id]._object.isdeleted())
            totalCost += Number(widgetRegistry.acqie[id].cost_billed.getFormattedValue());
    totalInvoicedBox.attr('value', totalCost);

    totalPaid = 0;    
    for(var id in widgetRegistry.acqii) 
        if(!widgetRegistry.acqii[id]._object.isdeleted())
            totalPaid += Number(widgetRegistry.acqii[id].amount_paid.getFormattedValue());
    for(var id in widgetRegistry.acqie) 
        if(!widgetRegistry.acqie[id]._object.isdeleted())
            totalPaid += Number(widgetRegistry.acqie[id].amount_paid.getFormattedValue());
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

    if(totalPaid == totalCost) { // XXX: too rigid?
        invoiceCloseButton.attr('disabled', false);
    } else {
        invoiceCloseButton.attr('disabled', true);
    }

    balanceOwedBox.attr('value', (totalCost - totalPaid));
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
            
            var args;
            if(field == 'title' || field == 'author') {
                //args = {style : 'width:10em'};
            } else if(field == 'cost_billed' || field == 'amount_paid') {
                args = {required : true, style : 'width: 8em'};
            }
            registerWidget(
                item,
                field,
                new openils.widget.AutoFieldWidget({
                    fmClass : 'acqii',
                    fmObject : item,
                    fmField : field,
                    readOnly : invoice && openils.Util.isTrue(invoice.complete()),
                    dijitArgs : args,
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
        readOnly : invoice && openils.Util.isTrue(invoice.complete()),
        dijitArgs : {required : true},
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

    if(item.po_item()) {

        // read-only item view for items that were the result of a po-item
        var po = item.purchase_order();
        var po_item = item.po_item();
        var node = nodeByName('inv_item_type', row);
        var itemType = itemTypes.filter(function(t) { return (t.code() == item.inv_item_type()) })[0];
        orderDate = (!po.order_date()) ? '' : 
                dojo.date.locale.format(dojo.date.stamp.fromISOString(po.order_date()), {selector:'date'});

        node.innerHTML = dojo.string.substitute(
            localeStrings.INVOICE_ITEM_PO_DETAILS, 
            [ 
                itemType.name(),
                oilsBasePath, 
                po.id(), 
                po.name(), 
                orderDate,
                po_item.estimated_cost() 
            ]
        );

    } else {

        registerWidget(
            item,
            'inv_item_type',
            new openils.widget.AutoFieldWidget({
                fmObject : item,
                fmField : 'inv_item_type',
                parentNode : nodeByName('inv_item_type', row),
                readOnly : invoice && openils.Util.isTrue(invoice.complete()),
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
    }

    nodeByName('delete', row).onclick = function() {
        var cost = widgetRegistry.acqii[item.id()].cost_billed.getFormattedValue();
        var msg = dojo.string.substitute(
            localeStrings.INVOICE_CONFIRM_ITEM_DELETE, [
                cost || 0,
                widgetRegistry.acqii[item.id()].inv_item_type.getFormattedValue() || ''
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

function updateReceiveLink(li) {
    if (!invoiceId)
        return; /* can't do this with unsaved invoices */

    var link = dojo.byId("acq-view-invoice-receive-link");
    if (link.onclick) return; /* only need to do this once */

    /* don't do this if there's nothing receivable on the lineitem */
    if (li.order_summary().recv_count() + li.order_summary().cancel_count() >=
        li.order_summary().item_count())
        return;

    openils.Util.show("acq-view-invoice-receive");
    link.onclick = function() { location.href =  oilsBasePath + '/acq/invoice/receive/' + invoiceId; };
}

function addInvoiceEntry(entry) {

    openils.Util.removeCSSClass(dojo.byId('acq-invoice-entry-header'), 'hidden');
    openils.Util.removeCSSClass(dojo.byId('acq-invoice-entry-thead'), 'hidden');
    openils.Util.removeCSSClass(dojo.byId('acq-invoice-entry-tbody'), 'hidden');

    entryTbody = dojo.byId('acq-invoice-entry-tbody');
    if(entryTemplate == null) {
        entryTemplate = entryTbody.removeChild(dojo.byId('acq-invoice-entry-template'));
    }

    if(dojo.query('[lineitem=' + entry.lineitem() +']', entryTbody)[0])
        // Is it ever valid to have multiple entries for 1 lineitem in a single invoice?
        return;

    var row = entryTemplate.cloneNode(true);
    row.setAttribute('lineitem', entry.lineitem());

    openils.acq.Lineitem.fetchAndRender(
        entry.lineitem(), {}, 
        function(li, html) { 
            entry.lineitem(li);
            entry.purchase_order(li.purchase_order());
            nodeByName('title_details', row).innerHTML = html;

            updateReceiveLink(li);

            dojo.forEach(
                ['inv_item_count', 'phys_item_count', 'cost_billed', 'amount_paid'],
                function(field) {
                    var dijitArgs = {required : true, constraints : {min: 0}, style : 'width:6em'};
                    if(!field.match(/count/)) dijitArgs.style = 'width:9em';
                    if(entry.isnew() && field == 'phys_item_count') {
                        // by default, attempt to pay for all non-canceled and as-of-yet-un-invoiced items
                        var count = Number(li.order_summary().item_count() || 0) - 
                                    Number(li.order_summary().cancel_count() || 0) -
                                    Number(li.order_summary().invoice_count() || 0);
                        if(count < 0) count = 0;
                        dijitArgs.value = count;
                    }
                    registerWidget(
                        entry, 
                        field,
                        new openils.widget.AutoFieldWidget({
                            fmObject : entry,
                            fmClass : 'acqie',
                            fmField : field,
                            dijitArgs : dijitArgs,
                            readOnly : invoice && openils.Util.isTrue(invoice.complete()),
                            parentNode : nodeByName(field, row)
                        }),
                        function(w) {    
                            if(field == 'phys_item_count') {
                                dojo.connect(w, 'onChange', 
                                    function() {
                                        // staff entered a higher number in the receive field than was originally ordered
                                        // taking into account already invoiced items
                                        var extra = Number(this.attr('value')) - 
                                            (Number(entry.lineitem().item_count()) - Number(entry.lineitem().order_summary().invoice_count()));
                                        if(extra > 0) {
                                            storeExtraCopies(entry, extra);
                                        }
                                    }
                                )
                            }
                        }
                    );
                }
            );
        }
    );

    nodeByName('detach', row).onclick = function() {
        var cost = widgetRegistry.acqie[entry.id()].cost_billed.getFormattedValue();
        var idents = [];
        dojo.forEach(['isbn', 'upc', 'issn'], 
            function(ident) { 
                var val = liMarcAttr(entry.lineitem(), ident);
                if(val) idents.push(val); 
            }
        );

        var msg = dojo.string.substitute(
            localeStrings.INVOICE_CONFIRM_ENTRY_DETACH, [
                cost || 0,
                liMarcAttr(entry.lineitem(), 'title'),
                liMarcAttr(entry.lineitem(), 'author'),
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

function saveChanges(doProrate, doClose, doReopen) {
    createExtraCopies(
        function() {
            saveChangesPartTwo(doProrate, doClose, doReopen);
        }
    );
}

// Define a helper function to 'unflesh' sub-objects from an fmclass object.
// 'this' specifies the object; the arguments specify a list of names of
// sub-objects.
function unflesh() {
    var _, $ = this;
    dojo.forEach(arguments, function (n) {
        _ = $[n]();
        if (_ !== null && typeof _ === 'object')
            $[n]( _.id() );
    });
}

function saveChangesPartTwo(doProrate, doClose, doReopen) {
    

    if(doReopen) {
        invoice.complete('f');

    } else {

        // Prepare an invoice for submission
        if(!invoice) {
            invoice = new fieldmapper.acqinv();
            invoice.isnew(true);
        } else {
            invoice.ischanged(true); // for now, just always update
        }

        var e = invoicePane.mapValues(function (n, v) { invoice[n](v); });
        if (e instanceof Error) {
            alert(e.message);
            return;
        }

        if(doClose)
            invoice.complete('t');


        // Prepare any charge items
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
                
                unflesh.call(item, 'purchase_order');

            }
        }

        // Prepare any line items
        var updateEntries = [];
        for(var id in widgetRegistry.acqie) {
            var reg = widgetRegistry.acqie[id];
            var entry = reg._object;
            if(entry.ischanged() || entry.isnew() || entry.isdeleted()) {
                updateEntries.push(entry);
                if(entry.isnew()) entry.id(null);

                for(var field in reg) {
                    if(field != '_object')
                        entry[field]( reg[field].getFormattedValue() );
                }
                
                unflesh.call(entry, 'purchase_order', 'lineitem');
            }
        }
    }

    progressDialog.show(true);
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.invoice.update'],
        {
            params : [openils.User.authtoken, invoice, updateEntries, updateItems],
            oncomplete : function(r) {
                progressDialog.hide();
                var invoice = openils.Util.readResponse(r);
                if(invoice) {
                    if(doProrate)
                        return prorateInvoice(invoice);
                    location.href = oilsBasePath + '/acq/invoice/view/' + invoice.id();
                }
            }
        }
    );
}

function prorateInvoice(invoice) {
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

function storeExtraCopies(entry, numExtra) {

    dojo.byId('acq-invoice-extra-copies-message').innerHTML = 
        dojo.string.substitute(
            localeStrings.INVOICE_EXTRA_COPIES, [numExtra]);

    var addCopyHandler;
    addCopyHandler = dojo.connect(
        extraCopiesGo, 
        'onClick',
        function() {
            extraCopies[entry.lineitem().id()] = {
                numExtra : numExtra, 
                fund : extraCopiesFund.widget.attr('value')
            }
            extraItemsDialog.hide();
            dojo.disconnect(addCopyHandler);
        }
    );

    dojo.connect(
        extraCopiesCancel, 
        'onClick',
        function() { 
            widgetRegistry.acqie[entry.id()].phys_item_count.widget.attr('value', '');
            extraItemsDialog.hide() 
        }
    );

    extraItemsDialog.show();
}

function createExtraCopies(oncomplete) {

    var lids = [];
    for(var liId in extraCopies) {
        var data = extraCopies[liId];
        for(var i = 0; i < data.numExtra; i++) {
            var lid = new fieldmapper.acqlid();
            lid.isnew(true);
            lid.lineitem(liId);
            lid.fund(data.fund);
            lid.recv_time('now');
            lids.push(lid);
        }
    }

    if(lids.length == 0) 
        return oncomplete();

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem_detail.cud.batch'],
        {
            params : [openils.User.authtoken, lids, true],
            oncomplete : function(r) {
                if(openils.Util.readResponse(r))
                    oncomplete();
            }
        }
    );

}


openils.Util.addOnLoad(init);


