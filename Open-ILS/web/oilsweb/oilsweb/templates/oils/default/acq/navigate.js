{   label : "${_('Acquisitions')}", 
    id : 'acq',
    children : [
        {   label : "${_('Picklist')}",
            dest : 'acq/picklist/list',
            id : 'acq-picklist',
            children : [
                <%include file='picklist/navigate.js'/>
            ]
        },
        {   label:"${_('Manage Funds')}", 
            id : 'acq-fund',
            dest : 'acq/fund/list',
            children : [
                <%include file='financial/navigate.js'/>
            ]
        },
        {   label : "${_('PO')}",
            id : 'acq-po',
            dest : 'acq/po/list',
            children : [
                <%include file='po/navigate.js'/>
            ]
        }
    ]
}
