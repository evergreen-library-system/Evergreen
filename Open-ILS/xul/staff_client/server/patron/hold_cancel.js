var data; var error; 

function default_focus() { document.getElementById('note_tb').focus(); } // parent interfaces often call this

function hold_cancel_init() {
    try {

        commonStrings = document.getElementById('commonStrings');
        patronStrings = document.getElementById('patronStrings');

        if (typeof JSAN == 'undefined') {
            throw(
                commonStrings.getString('common.jsan.missing')
            );
        }

        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');

        JSAN.use('OpenILS.data'); data = new OpenILS.data(); data.stash_retrieve();

        JSAN.use('util.error'); error = new util.error();
        JSAN.use('util.widgets');

        build_cancel_reason_menu();

        /* set widget behavior */
        document.getElementById('cancel_btn').addEventListener(
            'command', function() { window.close(); }, false
        );
        document.getElementById('apply_btn').addEventListener(
            'command', 
            function() {
                var note = document.getElementById('note_tb').value;
                xulG.cancel_reason = document.getElementById('ahrcc_menupopup').getAttribute('value');
                xulG.note = note;
                xulG.proceed = 1;
                window.close();
            }, 
            false
        );

        default_focus();

    } catch(E) {
        var err_prefix = 'hold_cancel.js -> hold_cancel_init() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }

}

function build_cancel_reason_menu() {
    try {

        var ahrcc_menupopup = document.getElementById('ahrcc_menupopup');
        util.widgets.remove_children(ahrcc_menupopup);
        for (var i = 0; i < data.list.ahrcc.length; i++) {
            //if (data.list.ahrcc[i].id() > 100) {
                var menuitem = document.createElement('menuitem'); ahrcc_menupopup.appendChild(menuitem);
                menuitem.setAttribute('label',data.list.ahrcc[i].label());
                menuitem.setAttribute('value',data.list.ahrcc[i].id());
                menuitem.setAttribute('id','ahrcc_'+data.list.ahrcc[i].id());
                menuitem.setAttribute('oncommand',"var p = this.parentNode; p.parentNode.setAttribute('label',this.getAttribute('label')); p.setAttribute('value'," + data.list.ahrcc[i].id() + ")");
                if (data.list.ahrcc[i].id() == 5) { // default Staff forced
                    ahrcc_menupopup.setAttribute('value',data.list.ahrcc[i].id());
                    ahrcc_menupopup.parentNode.setAttribute('label',data.list.ahrcc[i].label());
                }
            //}
        }

    } catch(E) {
        var err_prefix = 'hold_cancel.js -> build_cancel_reason_menu() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

