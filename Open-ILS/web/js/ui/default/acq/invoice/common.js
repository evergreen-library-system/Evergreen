dojo.require('dojo.date.stamp');
dojo.require('openils.User');
dojo.require('openils.widget.EditPane');

function drawInvoicePane(parentNode, inv, args) {
    args = args || {};

    var override = {};
    if(!inv) {
        override = {
            recv_date : {widgetValue : dojo.date.stamp.toISOString(new Date())},
            receiver : {widgetValue : openils.User.user.ws_ou()},
            recv_method : {widgetValue : 'PPR'}
        };
    }

    dojo.mixin(override, {
        provider : { dijitArgs : { store_options : { base_filter : { active :"t" } } } },
        shipper  : { dijitArgs : { store_options : { base_filter : { active :"t" } } } }
    });

    for(var field in args) {
        override[field] = {widgetValue : args[field]};
    }

    var pane = new openils.widget.EditPane({
        fmObject : inv,
        paneStackCount : 2,
        fmClass : 'acqinv',
        mode : (inv) ? 'edit' : 'create',
        hideActionButtons : true,
        overrideWidgetArgs : override,
        readOnly : (inv) && openils.Util.isTrue(inv.complete()),
        requiredFields : [
            'inv_ident', 
            'recv_date', 
            'provider', 
            'shipper'
        ],
        fieldOrder : [
            'inv_ident', 
            'recv_date', 
            'recv_method', 
            'inv_type', 
            'provider', 
            'shipper'
        ],
        suppressFields : ['id', 'complete']
    });

    pane.startup();
    parentNode.appendChild(pane.domNode);
    return pane;
}

