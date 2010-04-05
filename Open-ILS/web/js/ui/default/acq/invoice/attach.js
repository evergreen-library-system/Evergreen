dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');
dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.NumberTextBox');
dojo.require('dijit.form.CurrencyTextBox');
dojo.require('openils.User');
dojo.require('openils.Util');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.AutoFieldWidget');

dojo.requireLocalization('openils.acq', 'acq');
var localeStrings = dojo.i18n.getLocalization('openils.acq', 'acq');

var pcrud = new openils.PermaCrud();
var cgi = new openils.CGI();
var doCreate = false;
var invoiceId;
var lineitem;
var invoicePane;
var entryPane;

function init() {

    invoiceId = cgi.param('invoice_id');
    doCreate = cgi.param('create');
    attachLi = cgi.param('attach_li');

    invoicePane = drawInvoicePane(dojo.byId('acq-view-invoice-div'));

    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.lineitem.retrieve"], {
            async: true,
            params: [openils.User.authtoken, attachLi, {
                flesh_attrs: true,
                flesh_li_details: true,
                flesh_cancel_reason: true,
                flesh_po : true,
                flesh_pl : true
            }],
            oncomplete: function(r) { 
                lineitem = openils.Util.readResponse(r);
                drawPage(); 
            }
        }
    );

    dojo.connect(createInvoiceButton, 'onClick', function() { createInvoice(); });
}

function liMarcAttr(name) {
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

function drawPage() {

    var idents = [];
    if(liMarcAttr('isbn')) idents.push(liMarcAttr('isbn'));
    if(liMarcAttr('upc')) idents.push(liMarcAttr('upc'));
    if(liMarcAttr('issn')) idents.push(liMarcAttr('issn'));

    var orderDate = '';
    var po = lineitem.purchase_order();
    if(po.order_date()) {
        var dt = dojo.date.stamp.fromISOString(po.order_date());
        orderDate = dojo.date.locale.format(dt, {selector:'date'});
    }

    dojo.byId('acq-invoice-li-details').innerHTML = 
        dojo.string.substitute(
            localeStrings.INVOICE_ITEM_DETAILS,
            [
                liMarcAttr('title'),
                liMarcAttr('author'),
                idents.join(','),
                lineitem.estimated_unit_price() || '',
                lineitem.id(),
                lineitem.purchase_order().name(),
                orderDate
            ]
        );

    //invoicePo.attr('value', lineitem.purchase_order().name());
    //invoicePo.attr('disabled', true);

    //numCopiesInvoiced.attr('value', lineitem.lineitem_details().length);
    
    var numReceived = 0;
    dojo.forEach(lineitem.lineitem_details(), function(lid) { if(lid.recv_time) numReceived++ });
    //numCopiesReceived.attr('value', numReceived);

    entryPane = new openils.widget.EditPane({
        fmClass : 'acqie',
        mode : 'create',
        hideActionButtons : true,
        existingTable : invoicePane.table,
        overrideWidgetArgs : {
            inv_item_count : {widgetValue : numReceived},
            phys_item_count : {widgetValue : numReceived}
        },
        fieldOrder : [
            'purchase_order', 
            'inv_item_count',
            'phys_item_count',
            'cost_billed',
            'note'
        ],
        suppressFields : [
            'invoice',
            'purchase_order',
            'lineitem',
            'actual_cost'
        ]
    });
    entryPane.startup();

}


function createInvoice() {

    var inv = new fieldmapper.acqinv();
    dojo.forEach(invoicePane.fieldList, 
        function(field) {
            inv[field.name]( field.widget.getFormattedValue() );
        }
    );

    var entry = new fieldmapper.acqie();
    dojo.forEach(entryPane.fieldList, 
        function(field) {
            entry[field.name]( field.widget.getFormattedValue() );
        }
    );
    entry.purchase_order(lineitem.purchase_order().id());
    entry.lineitem(lineitem.id());

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.invoice.create'],
        {
            params : [openils.User.authtoken, inv, [entry]],
            oncomplete : function(r) {
                var resp = openils.Util.readResponse(r);
                if(resp) {
                    location.href = 
                        location.href.replace(/invoice\/attach.*/, 'invoice/view/' + resp.id());
                }
            }
        }
    );
}

openils.Util.addOnLoad(init);

