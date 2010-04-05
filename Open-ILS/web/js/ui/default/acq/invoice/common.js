dojo.require('dojo.date.stamp');
dojo.require('openils.User');
dojo.require('openils.widget.EditPane');

function drawInvoicePane(parentNode, inv) {

    var override;
    if(!inv) {
        override = {
            recv_date : {widgetValue : dojo.date.stamp.toISOString(new Date())},
            receiver : {widgetValue : openils.User.user.ws_ou()},
            recv_method : {widgetValue : 'PPR'}
        };
    }

    var pane = new openils.widget.EditPane({
        fmObject : inv,
        fmClass : 'acqinv',
        mode : (inv) ? 'edit' : 'create',
        hideActionButtons : true,
        overrideWidgetArgs : override,
        fieldOrder : [
            'inv_ident', 
            'recv_date', 
            'recv_method', 
            'inv_type', 
            'provider', 
            'shipper'
        ]
    });

    pane.startup();
    parentNode.appendChild(pane.domNode);
    return pane;
}

