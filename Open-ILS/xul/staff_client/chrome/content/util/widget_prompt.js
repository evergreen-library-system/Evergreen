var xulG = {};
var widget;

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for widget_prompt.xul');

        widget = xul_param('widget',{'modal_xulG':true});
        if (widget) {
            $('widget_prompt_main').appendChild(widget);
        }

        var ok_label = xul_param('ok_label',{'modal_xulG':true}) || offlineStrings.getString('common.ok.label');
        $('ok_btn').setAttribute('label',ok_label);

        var ok_accesskey = xul_param('ok_accesskey',{'modal_xulG':true}) || offlineStrings.getString('common.ok.accesskey');
        $('ok_btn').setAttribute('accesskey',ok_accesskey);

        var cancel_label = xul_param('cancel_label',{'modal_xulG':true}) || offlineStrings.getString('common.cancel.label');
        $('cancel_btn').setAttribute('label',cancel_label);

        var cancel_accesskey = xul_param('cancel_accesskey',{'modal_xulG':true}) || offlineStrings.getString('common.cancel.accesskey');
        $('cancel_btn').setAttribute('accesskey',cancel_accesskey);

        var desc = xul_param('desc',{'modal_xulG':true});
        if (desc) {
            $('desc').appendChild( document.createTextNode( desc ) );
        }

        $('ok_btn').addEventListener('command',widget_save,false);
        $('cancel_btn').addEventListener('command',function(ev) { window.close(); },false);

        if (xul_param('title',{'modal_xulG':true})) {
            try { window.title = xul_param('title',{'modal_xulG':true}); } catch(E) {}
            try { document.title = xul_param('title',{'modal_xulG':true}); } catch(E) {}
        }

        xulG[ 'status' ] = 'incomplete';
        update_modal_xulG(xulG);

        try { widget.focus(); } catch(E) {}

    } catch(E) {
        alert('Error in widget_prompt.js, my_init(): ' + E);
    }
}

function widget_save(ev) {
    try {
        if (widget) {
            switch( xul_param('access',{'modal_xulG':true}) ) {
                case 'method' :
                    xulG[ 'value' ] = xulG[ 'method' ]();
                break;
                case 'attribute':
                    xulG[ 'value' ] = widget.getAttribute('value');
                break;
                case 'property':
                default:
                    xulG[ 'value'  ] = widget.value;
                break;
            }
        }
        xulG[ 'status' ] = 'complete';

        update_modal_xulG(xulG);

        window.close();
    } catch(E) {
        alert('Error in widget_prompt.js, widget_save(): ' + E);
    }
}

