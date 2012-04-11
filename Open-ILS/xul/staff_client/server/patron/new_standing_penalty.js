var data; var error; 

function default_focus() { document.getElementById('note_tb').focus(); } // parent interfaces often call this

function new_penalty_init() {
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

        build_penalty_menu();

        var show_initials = String( data.hash.aous['ui.staff.require_initials'] ) == 'true';
        if (show_initials) {
            document.getElementById('initials_box').hidden = false;
        }

        /* set widget behavior */
        document.getElementById('csp_menulist').addEventListener(
            'command',
            function() {
                document.getElementById('note_btn').checked = false;
                document.getElementById('alert_btn').checked = false;
                document.getElementById('block_btn').checked = false;
            },
            false
        );
        document.getElementById('note_btn').addEventListener(
            'command', 
            function() { 
                document.getElementById('csp_menulist').setAttribute('label',''); 
                document.getElementById('csp_menupopup').setAttribute('value','21'); // SILENT_NOTE
            }, 
            false
        );
        document.getElementById('alert_btn').addEventListener(
            'command', 
            function() { 
                document.getElementById('csp_menulist').setAttribute('label',''); 
                document.getElementById('csp_menupopup').setAttribute('value','20'); // ALERT_NOTE
            }, 
            false
        );
        document.getElementById('block_btn').addEventListener(
            'command', 
            function() { 
                document.getElementById('csp_menulist').setAttribute('label',''); 
                document.getElementById('csp_menupopup').setAttribute('value','25'); // STAFF_CHR
            }, 
            false
        );
        document.getElementById('cancel_btn').addEventListener(
            'command', function() { window.close(); }, false
        );
        document.getElementById('apply_btn').addEventListener(
            'command', 
            function() {
                var note = document.getElementById('note_tb').value;
                if (!document.getElementById('initials_box').hidden) {
                    var initials_tb = document.getElementById('initials_tb');
                    if (initials_tb.value == '') {
                        initials_tb.focus(); return;
                    } else {
                        JSAN.use('util.date');
                        note = note + commonStrings.getFormattedString('staff.initials.format',[initials_tb.value,util.date.formatted_date(new Date(),'%F'), ses('ws_ou_shortname')]);
                    }
                }
                xulG.id = document.getElementById('csp_menupopup').getAttribute('value');
                xulG.note = note;
                xulG.modify = 1;
                window.close();
            }, 
            false
        );

        default_focus();

    } catch(E) {
        var err_prefix = 'standing_penalties.js -> penalty_init() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }

}

function build_penalty_menu() {
    try {

        var csp_menupopup = document.getElementById('csp_menupopup');
        util.widgets.remove_children(csp_menupopup);
        for (var i = 0; i < data.list.csp.length; i++) {
            if (data.list.csp[i].id() > 100) {
                var menuitem = document.createElement('menuitem'); csp_menupopup.appendChild(menuitem);
                menuitem.setAttribute('label',data.list.csp[i].label());
                menuitem.setAttribute('value',data.list.csp[i].id());
                menuitem.setAttribute('id','csp_'+data.list.csp[i].id());
                menuitem.setAttribute('oncommand',"var p = this.parentNode; p.parentNode.setAttribute('label',this.getAttribute('label')); p.setAttribute('value'," + data.list.csp[i].id() + ")");
            }
        }

    } catch(E) {
        var err_prefix = 'new_standing_penalty.js -> build_penalty_menu() : ';
        if (error) error.standard_unexpected_error_alert(err_prefix,E); else alert(err_prefix + E);
    }
}

