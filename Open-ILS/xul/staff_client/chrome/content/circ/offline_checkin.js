var offlineStrings;
var local_lock = false;

function my_init() {
    try {
        offlineStrings = $('offlineStrings');

        if (typeof JSAN == 'undefined') { throw(offlineStrings.getString('common.jsan.missing')); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for offline_checkin.xul');

        if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
            try { window.xulG.set_tab_name(offlineStrings.getString('circ.standalone')); } catch(E) { alert(E); }
        }

        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});

        JSAN.use('util.list'); g.list = new util.list('checkin_list');
        JSAN.use('circ.util');
        g.list.init( {
            'columns' : circ.util.offline_checkin_columns(),
            'map_row_to_column' : circ.util.std_map_row_to_column(),
        } );

        JSAN.use('util.date');

        function handle_lock(ev) {
            if (!(ev.altKey || ev.ctrlKey || ev.metakey)) {
                if (!local_lock) {
                    local_lock = true;
                    xulG.lock();
                }
            }
        }
        $('i_barcode').addEventListener('keypress',handle_lock,false);
        $('i_barcode').addEventListener('keypress',handle_keypress,false);
        $('i_barcode').focus();    

        $('enter').addEventListener('command',handle_enter,false);

        $('submit').addEventListener('command',next_patron,false);

        JSAN.use('util.file');
        var file = new util.file('offline_delta'); 
        if (file._file.exists()) { g.delta = file.get_object()[0]; file.close(); } else { g.delta = 0; }

    } catch(E) {
        var err_msg = offlineStrings.getFormattedString('common.exception', ["circ/offline_checkin.xul", E]);
        try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
        alert(err_msg);
    }
}

function $(id) { return document.getElementById(id); }

function handle_keypress(ev) {
    if ( (! ev.keyCode) || (ev.keyCode != 13) ) return;
    switch(ev.target) {
        case $('i_barcode') : handle_enter(); break;
        default: break;
    }
}

function handle_enter(ev) {
    JSAN.use('util.barcode');
    if ( ($('strict_i_barcode').checked) && (! util.barcode.check($('i_barcode').value)) ) {
        var r = g.error.yns_alert(offlineStrings.getString('circ.bad_checkdigit'),offlineStrings.getString('circ.barcode.warning'),offlineStrings.getString('common.ok'),offlineStrings.getString('common.clear'),null,offlineStrings.getString('common.confirm'));
        if (r == 1) {
            setTimeout(
                function() {
                    $('i_barcode').value = '';
                    $('i_barcode').focus();
                },0
            );
        } else {
            append_to_list();
        }
    } else {
        append_to_list();
    }
}

function append_to_list() {

    try {

        var my = {};

        my.type = 'checkin';
        my.timestamp = parseInt( new Date().getTime() / 1000) + g.delta;
        /* I18N to-do: enable localized date formats */
        my.backdate = util.date.formatted_date(new Date(),"%F %H:%M:%s");

        var i_barcode = $('i_barcode').value;
        if (! i_barcode) return; 
        my.barcode = i_barcode; 
    
        g.list.append( { 'row' : { 'my' : my }, 'to_top' : true } );

        var x = $('i_barcode'); x.value = ''; x.focus();

        if (!local_lock) {
            local_lock = true;
            xulG.lock();
        }

    } catch(E) {

        dump(E+'\n'); alert(E);

    }
}

function next_patron() {
    try {
        JSAN.use('util.file'); var file = new util.file('pending_xacts');
        var rows = g.list.dump_with_keys();
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i]; row.delta = g.delta;
            file.append_object(row);
        }
        file.close();

        if (local_lock) {
            local_lock = false;
            xulG.unlock();
        }

        if ($('print_receipt').checked) {
            try {
                var params = {
                    'template' : 'offline_checkin',
                    'printer_context' : 'offline',
                    'callback' : function() {
                        g.list.clear();
                        var x = $('i_barcode'); x.value = ''; x.focus();
                    }
                };
                g.list.print( params );
            } catch(E) {
                g.error.sdump('D_ERROR','print: ' + E);
                alert('print: ' + E);
            }
        } else {
            g.list.clear();
            var x = $('i_barcode'); x.value = ''; x.focus();
        }

    } catch(E) {
        dump(E+'\n'); alert(E);
    }
}
