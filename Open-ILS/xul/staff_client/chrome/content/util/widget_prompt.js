var widget;

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for widget_prompt.xul');

        widget = xul_param('widget');
        if (widget) {
            $('widget_prompt_main').appendChild(widget);
        }

        if (typeof offlineStrings == 'undefined') {
            offlineStrings = $('offlineStrings');
        }

        var ok_label = xul_param('ok_label') || offlineStrings.getString('common.ok.label');
        $('ok_btn').setAttribute('label',ok_label);

        var ok_accesskey = xul_param('ok_accesskey') || offlineStrings.getString('common.ok.accesskey');
        $('ok_btn').setAttribute('accesskey',ok_accesskey);

        var cancel_label = xul_param('cancel_label') || offlineStrings.getString('common.cancel.label');
        $('cancel_btn').setAttribute('label',cancel_label);

        var cancel_accesskey = xul_param('cancel_accesskey') || offlineStrings.getString('common.cancel.accesskey');
        $('cancel_btn').setAttribute('accesskey',cancel_accesskey);

        var desc = xul_param('desc');
        if (desc) {
            $('desc').appendChild( document.createTextNode( desc ) );
        }

        $('ok_btn').addEventListener('command',widget_save,false);
        $('cancel_btn').addEventListener('command',function(ev) { window.close(); },false);

        if (xul_param('title')) {
            try { window.title = xul_param('title'); } catch(E) {}
            try { document.title = xul_param('title'); } catch(E) {}
        }

        xulG[ 'status' ] = 'incomplete';

        try { widget.focus(); } catch(E) {}

    } catch(E) {
        alert('Error in widget_prompt.js, my_init(): ' + E);
    }
}

function widget_save(ev) {
    try {
        if (widget) {
            switch( xul_param('access') ) {
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

        window.close();
    } catch(E) {
        alert('Error in widget_prompt.js, widget_save(): ' + E);
    }
}

