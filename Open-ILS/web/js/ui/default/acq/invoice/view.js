dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');
dojo.require('dojo.cookie');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.Button');
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
var focusLineitem;
var searchInitDone = false;
var termManager;
var resultManager;

function nodeByName(name, context) {
    return dojo.query('[name='+name+']', context)[0];
}

function init() {

    attachLi = cgi.param('attach_li') || [];
    if (!dojo.isArray(attachLi)) 
        attachLi = [attachLi];

    attachPo = cgi.param('attach_po') || [];
    if (!dojo.isArray(attachPo)) 
        attachPo = [attachPo];

    focusLineitem = new openils.CGI().param('focus_li');

    totalInvoicedBox = dojo.byId('acq-total-invoiced-box');
    totalPaidBox = dojo.byId('acq-total-paid-box');
    balanceOwedBox = dojo.byId('acq-total-balance-box');

    itemTypes = pcrud.retrieveAll('aiit');

    dojo.byId('acq-invoice-summary-toggle-off').onclick = function() {
        openils.Util.hide(dojo.byId('acq-invoice-summary'));
        openils.Util.show(dojo.byId('acq-invoice-summary-small'));
    };

    dojo.byId('acq-invoice-summary-toggle-on').onclick = function() {
        openils.Util.show(dojo.byId('acq-invoice-summary'));
        openils.Util.hide(dojo.byId('acq-invoice-summary-small'));
    }

    if(cgi.param('create')) {
        renderInvoice();

        // show summary info by default for new invoices
        dojo.byId('acq-invoice-summary-toggle-on').onclick();

    } else {
        dojo.byId('acq-invoice-summary-toggle-off').onclick();
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
    if( !(cgi.param('create') && (attachPo.length || attachLi.length)) ) {
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

    // display items and entries in ID order 
    // which effectively equates to add order.
    function idsort(a, b) { return a.id() < b.id() ? -1 : 1 }

    if(invoice) {
        dojo.forEach(
            invoice.items().sort(idsort),
            function(item) {
                addInvoiceItem(item);
            }
        );

        dojo.forEach(
            invoice.entries().sort(idsort),
            function(entry) {
                addInvoiceEntry(entry);
            }
        );
    }

    if(attachLi.length) doAttachLi();
    if(attachPo.length) doAttachPo(0);
}

function doAttachLi(skipInit) {

    //var invoiceArgs = {provider : lineitem.provider(), shipper : lineitem.provider()}; 
    if(cgi.param('create') && !skipInit) {

        // use the first LI in the list to determine the default provider
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.retrieve.authoritative'],
            {
                params : [openils.User.authtoken, attachLi[0], {clear_marc:1}],
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

    dojo.forEach(attachLi,
        function(li) {
            var entry = new fieldmapper.acqie();
            entry.id(virtualId--);
            entry.isnew(true);
            entry.lineitem(li);
            addInvoiceEntry(entry);
        }
    );
}

function doAttachPo(idx) {

    if (idx == attachPo.length) return;
    var poId = attachPo[idx];

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.purchase_order.retrieve'],
        {   async: true,
            params: [
                openils.User.authtoken, poId,
                {flesh_lineitem_ids : true, flesh_po_items : true}
            ],
            oncomplete: function(r) {
                var po = openils.Util.readResponse(r);

                if(cgi.param('create') && idx == 0) {
                    // render the invoice using some seed data from the first PO
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

                doAttachPo(++idx);
            }
        }
    );
}

function performSearch(pageDir) {
    clearSearchResTable(); 
    var searchObject = termManager.buildSearchObject();
    dojo.cookie('invs', base64Encode(searchObject));
    dojo.cookie('invc', dojo.byId("acq-unified-conjunction").getValue());

    if (pageDir == 0) { // new search
        resultsLoader.displayOffset = 0;
    } else {
        resultsLoader.displayOffset += pageDir * resultsLoader.displayLimit;
    }

    if (resultsLoader.displayOffset == 0) {
        openils.Util.hide('acq-inv-search-prev');
    } else {
        openils.Util.show('acq-inv-search-prev', 'inline');
    }

    if (dojo.byId('acq-invoice-search-limit-invoiceable').checked) {
        if (!searchObject.jub) 
            searchObject.jub = [];

        // exclude lineitems that are "cancelled" (sidebar: 'Mericans spell it 'canceled')
        searchObject.jub.push({state : 'cancelled', '__not' : true});

        // exclude lineitems already linked to this invoice
        if (invoice && invoice.id() > 0) { 
            if (!searchObject.acqinv)
                searchObject.acqinv = [];
            searchObject.acqinv.push({id : invoice.id(), '__not' : true});
        }

        // limit to lineitems that have invoiceable copies
        searchObject.acqlisumi = [{item_count : 1, '_gte' : true}];

        // limit to provider if a provider is selected
        var provider = invoicePane.getFieldValue('provider');
        if (provider) {
            if (!searchObject.jub.filter(function(i) { return i.provider != null }).length)
                searchObject.jub.push({provider : provider});
        }
    }

    if (dojo.byId('acq-invoice-search-sort-title').checked) {
        uriManager.order_by = 
            [ {"class": "acqlia", "field":"attr_value", "transform":"first"} ];
    }

    resultsLoader.lastSearch = searchObject;
    resultManager.go(searchObject)
    console.log('Lineitem Search: ' + js2JSON(searchObject));
    focusLastSearchInput();
}


function renderUnifiedSearch() {

    if (!searchInitDone) {

        searchInitDone = true;
        termManager = new TermManager();
        resultManager = new ResultManager();
        resultsLoader = new searchResultsLoader();
        uriManager = new URIManager();

        // define custom lineitem result handler
        resultManager.result_types = {
            "lineitem": {
                "search_options": { "id_list": true },
                "revealer": function() { },
                "finisher": function() {
                    resultsLoader.batch_length = resultManager.count_results;
                },
                "adder": function(li) {
                    resultsLoader.addLineitem(li);
                },
                "interface": resultsLoader
            },
            "no_results": {
                "revealer": function() { }
            }
        };

        var searchObject = dojo.cookie('invs');
        console.log('loaded ' + searchObject);
        if (searchObject) {
            // if there is a search object cookie, populate the search form
            termManager.reflect(base64Decode(searchObject));
            dojo.byId("acq-unified-conjunction").setValue(dojo.cookie('invc'));
        } else {
            console.log('adding row');
            termManager.addRow();
        }
    }

    dojo.addClass(dojo.byId('oils-acq-invoice-table'), 'hidden');
    dojo.removeClass(dojo.byId('oils-acq-invoice-search'), 'hidden');
    focusLastSearchInput();
}

function focusLastSearchInput() {
    // TODO: see about making this better and moving it into search/unified.js
    var wnodes = dojo.query('[name=widget]');
    var inputNode = wnodes.item(wnodes.length - 1).firstChild;
    if (inputNode) {
        try {
            inputNode.select();
        } catch(E) {
            inputNode.focus();
        }
    }
}

var resultsTbody, resultsRow;
function searchResultsLoader() {
    this.displayOffset = 0;
    this.displayLimit = 10;

    if (!resultsTbody) {
        resultsTbody = dojo.byId('acq-invoice-search-results-tbody');
        resultsRow = resultsTbody.removeChild(dojo.byId('acq-invoice-search-results-tr'));
    }

    this.addLineitem = function(li_id) {
        console.log('Adding search result lineitem ' + li_id);
        var row = resultsRow.cloneNode(true);
        resultsTbody.appendChild(row);
        var checkbox = dojo.query('[name=search-results-checkbox]', row)[0];
        checkbox.setAttribute('lineitem', li_id);

        // this lineitem is already part of the invoice
        if (dojo.query('[entry_lineitem_row=' + li_id + ']')[0]) {
            checkbox.disabled = true;
            dojo.addClass(checkbox.parentNode, 'search-results-already-invoiced');
        }

        openils.acq.Lineitem.fetchAndRender(
            li_id, {}, 
            function(li, html) { 
                dojo.query('[name=search-results-content-div]', row)[0].innerHTML = html;
            }
        );
    }
}

function addSelectedToInvoice() {
    var inputs = dojo.query('[name=search-results-checkbox]');
    attachLi = [];
    dojo.forEach(inputs,
        function(checkbox) {
            if (checkbox.checked) {
                attachLi.push(checkbox.getAttribute('lineitem'));
                checkbox.disabled = true;
                checkbox.checked = false;
                dojo.addClass(checkbox.parentNode, 'search-results-already-invoiced');
            }
        }
    );
    doAttachLi(true);
}

function clearSearchResTable() {
    while (resultsTbody.childNodes[0])
        resultsTbody.removeChild(resultsTbody.childNodes[0]);
}

function updateTotalCost() {

    var totalCost = 0;    
    for(var id in widgetRegistry.acqii) 
        if(!widgetRegistry.acqii[id]._object.isdeleted())
            totalCost += Number(widgetRegistry.acqii[id].cost_billed.getFormattedValue());
    for(var id in widgetRegistry.acqie) 
        if(!widgetRegistry.acqie[id]._object.isdeleted())
            totalCost += Number(widgetRegistry.acqie[id].cost_billed.getFormattedValue());
    totalInvoicedBox.innerHTML = totalCost.toFixed(2);

    totalPaid = 0;    
    for(var id in widgetRegistry.acqii) 
        if(!widgetRegistry.acqii[id]._object.isdeleted())
            totalPaid += Number(widgetRegistry.acqii[id].amount_paid.getFormattedValue());
    for(var id in widgetRegistry.acqie) 
        if(!widgetRegistry.acqie[id]._object.isdeleted())
            totalPaid += Number(widgetRegistry.acqie[id].amount_paid.getFormattedValue());
    totalPaidBox.innerHTML = totalPaid.toFixed(2);

    var buttonsDisabled = false;

    if(totalPaid > totalCost || totalPaid < 0) {
        openils.Util.addCSSClass(totalPaidBox, 'acq-invoice-invalid-amount');
        invoiceSaveButton.attr('disabled', true);
        invoiceProrateButton.attr('disabled', true);
        buttonsDisabled = true;
    } else {
        openils.Util.removeCSSClass(totalPaidBox, 'acq-invoice-invalid-amount');
        invoiceSaveButton.attr('disabled', false);
        invoiceProrateButton.attr('disabled', false);
    }

    if(totalCost < 0) {
        openils.Util.addCSSClass(totalInvoicedBox, 'acq-invoice-invalid-amount');
        invoiceSaveButton.attr('disabled', true);
        invoiceProrateButton.attr('disabled', true);
    } else {
        openils.Util.removeCSSClass(totalInvoicedBox, 'acq-invoice-invalid-amount');
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

    balanceOwedBox.innerHTML = (totalCost - totalPaid).toFixed(2);

    updateExpectedCost();
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

/*
 * Ensures focusLineitem is in view and causes a brief 
 * border around the lineitem to come to life then fade.
 */
function focusLi() {
    if (!focusLineitem) return;

    // set during addLineitem()
    var node = dojo.byId('li-title-ref-' + focusLineitem);

    console.log('focus: li-title-ref-' + focusLineitem + ' : ' + node);

    // LI may not yet be rendered
    if (!node) return; 

    console.log('focusing ' + focusLineitem);

    // prevent numerous re-focuses
    focusLineitem = null; 

    // causes the full row to be visible
    dijit.scrollIntoView(node);

    dojo.require('dojox.fx');

    setTimeout(
        function() {
            dojox.fx.highlight({color : '#BB4433', node : node, duration : 2000}).play();
        }, 
    100);
}


// expected cost is totalCostInvoiced + totalCostNotYetInvoiced
function updateExpectedCost() {

    var cost = Number(totalInvoicedBox.innerHTML || 0);

    // for any LI's that are not yet billed (i.e. filled in)
    // use the total expected cost for that lineitem.
    for(var id in widgetRegistry.acqie) {
        var entry = widgetRegistry.acqie[id]._object;
        if(!entry.isdeleted()) {
            if (Number(widgetRegistry.acqie[id].cost_billed.getFormattedValue()) == 0) {
                var li = entry.lineitem();
                cost += 
                    Number(li.order_summary().estimated_amount()) - 
                    Number(li.order_summary().paid_amount());
            }
        }
    }

    dojo.byId('acq-invoice-summary-cost').innerHTML = cost.toFixed(2);
}

var invoicEntryWidgets = {};
function addInvoiceEntry(entry) {
    console.log('Adding new entry for lineitem ' + entry.lineitem());

    openils.Util.removeCSSClass(dojo.byId('acq-invoice-entry-header'), 'hidden');
    openils.Util.removeCSSClass(dojo.byId('acq-invoice-entry-thead'), 'hidden');
    openils.Util.removeCSSClass(dojo.byId('acq-invoice-entry-tbody'), 'hidden');

    dojo.byId('acq-invoice-summary-count').innerHTML = 
        Number(dojo.byId('acq-invoice-summary-count').innerHTML) + 1;

    entryTbody = dojo.byId('acq-invoice-entry-tbody');
    if(entryTemplate == null) {
        entryTemplate = entryTbody.removeChild(dojo.byId('acq-invoice-entry-template'));
    }

    if(dojo.query('[lineitem=' + entry.lineitem() +']', entryTbody)[0])
        // Is it ever valid to have multiple entries for 1 lineitem in a single invoice?
        return;

    var row = entryTemplate.cloneNode(true);
    row.setAttribute('lineitem', entry.lineitem());
    row.setAttribute('entry_lineitem_row', entry.lineitem());

    openils.acq.Lineitem.fetchAndRender(
        entry.lineitem(), {}, 
        function(li, html) { 
            entry.lineitem(li);
            entry.purchase_order(li.purchase_order());
            nodeByName('title_details', row).innerHTML = html;

            nodeByName('title_details', row).parentNode.id = 'li-title-ref-' + li.id();
            console.log(dojo.byId('li-title-ref-' + li.id()));

            updateReceiveLink(li);

            // set some default values if otherwise unset
            if (!invoicePane.getFieldValue('receiver')) {
                invoicePane.setFieldValue('receiver', li.purchase_order().ordering_agency());
            }
            if (!invoicePane.getFieldValue('provider')) {
                invoicePane.setFieldValue('provider', li.purchase_order().provider());
            }

            dojo.forEach(
                ['inv_item_count', 'phys_item_count', 'cost_billed', 'amount_paid'],
                function(field) {
                    var dijitArgs = {required : true, constraints : {min: 0}, style : 'width:6em'};
                    if(field.match(/count/)) {
                        dijitArgs.style = 'width:4em;';
                    } else {
                        dijitArgs.style = 'width:9em;';
                    }
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
                            } // if

                            if(field == 'inv_item_count' || field == 'cost_billed') {
                                setPerCopyPrice(row, entry);
                                // update the per-copy count as invoice count and cost billed change 
                                dojo.connect(w, 'onChange', function() { setPerCopyPrice(row, entry) } );
                            } 

                        } // func
                    );
                }
            );

            updateTotalCost();
            if (focusLineitem == li.id())
                focusLi();
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
}

function setPerCopyPrice(row, entry) {
    var inv_w = widgetRegistry.acqie[entry.id()].inv_item_count;
    var bill_w = widgetRegistry.acqie[entry.id()].cost_billed;

    if (inv_w && bill_w) {
        var invoiced = Number(inv_w.getFormattedValue());
        var billed = Number(bill_w.getFormattedValue());
        console.log(invoiced + ' : ' + billed);
        if (invoiced > 0) {
            nodeByName('amount_paid_per_copy', row).innerHTML = (billed / invoiced).toFixed(2);
        } else {
            nodeByName('amount_paid_per_copy', row).innerHTML = '0.00';
        }
    }
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

function saveChanges(args) {
    args = args || {};
    createExtraCopies(function() { saveChangesPartTwo(args); });
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

function saveChangesPartTwo(args) {
    args = args || {};

    if(args.reopen) {
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

        if(args.close)
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
                    if(args.prorate)
                        return prorateInvoice(invoice);
                    if (args.clear) {
                        location.href = oilsBasePath + '/acq/invoice/view?create=1';
                    } else {
                        location.href = oilsBasePath + '/acq/invoice/view/' + invoice.id();
                    }
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


