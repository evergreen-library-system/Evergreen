var offlineStrings;
var local_lock = false;

function my_init() {
    try {
        offlineStrings = $('offlineStrings');

        if (typeof JSAN == 'undefined') { throw(offlineStrings.getString('common.jsan.missing')); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for offline_checkout.xul');

        JSAN.use('util.widgets'); JSAN.use('util.file');

        if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
            try { window.xulG.set_tab_name(offlineStrings.getString('circ.standalone')); } catch(E) { alert(E); }
        }

        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});

        JSAN.use('util.list'); g.list = new util.list('checkout_list');
        JSAN.use('circ.util');
        g.list.init( {
            'columns' : circ.util.offline_checkout_columns(),
            'map_row_to_column' : circ.util.std_map_row_to_column(),
        } );

        JSAN.use('util.date');
        var today = new Date();
        var todayPlus = new Date(); todayPlus.setTime( today.getTime() + 24*60*60*1000*14 );
        todayPlus = util.date.formatted_date(todayPlus,"%F");

        function handle_lock(ev) {
            if (!(ev.altKey || ev.ctrlKey || ev.metakey)) {
                if (!local_lock) {
                    local_lock = true;
                    xulG.lock();
                }
            }
        }

        $('duedate').setAttribute('value',todayPlus);
        $('duedate').addEventListener('change',check_date,false);

        $('p_barcode').addEventListener('change',test_patron,false);
        $('p_barcode').addEventListener('keypress',handle_lock,false);

        $('p_barcode').addEventListener('keypress',handle_keypress,false);
        $('p_barcode').focus();    

        $('i_barcode').addEventListener('keypress',handle_lock,false);
        $('i_barcode').addEventListener('keypress',handle_keypress,false);
        $('enter').addEventListener('command',handle_enter,false);

        $('duedate_menu').addEventListener('command',handle_duedate_menu,false);

        $('submit').addEventListener('command',function(ev){
            save_xacts(); next_patron();
        },false);
        $('cancel').addEventListener('command',function(ev){
            next_patron('cancel');
        },false);

        var file; var list_data; var ml;

        file = new util.file('offline_cnct_list'); 
        if (file._file.exists()) {
            list_data = file.get_object(); file.close();
            ml = util.widgets.make_menulist( 
                [ [offlineStrings.getString('circ.offline_checkout.nonbarcoded'), ''] ].concat(list_data[0]), 
                list_data[1] 
            );
            ml.setAttribute('id','noncat_type_menu'); $('x_noncat_type').appendChild(ml);
            ml.addEventListener(
                'command',
                function(ev) { 
                    var count = window.prompt(offlineStrings.getString('circ.offline_checkout.items'),1,ml.getAttribute('label'));
                    append_to_list('noncat',count);    
                    ml.value = '';
                },
                false
            );
        } else {
            alert(offlineStrings.getString('circ.offline_checkout.download.warning'));
        }

        var file = new util.file('offline_delta'); 
        if (file._file.exists()) { g.delta = file.get_object()[0]; file.close(); } else { g.delta = 0; }

    } catch(E) {
        var err_msg = offlineStrings.getFormattedString('common.exception', ["circ/offline_checkout.xul", E]);
        try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
        alert(err_msg);
    }
}

function $(id) { return document.getElementById(id); }

function test_patron(ev) {
    try {
        var barcode = ev.target.value;
        JSAN.use('util.barcode');
        if ( ($('strict_p_barcode').checked) && (! util.barcode.check(barcode)) ) {
            var r = g.error.yns_alert(offlineStrings.getString('circ.bad_checkdigit'),offlineStrings.getString('circ.barcode.warning'),offlineStrings.getString('common.ok'),offlineStrings.getString('common.clear'),null,offlineStrings.getString('common.confirm'));
            if (r == 1) {
                setTimeout(
                    function() {
                        ev.target.value = '';
                        ev.target.focus();
                    },0
                );
            }

        }

        if (g.data.bad_patrons[barcode]) {
            var code;
            switch(g.data.bad_patrons[barcode]) {
                case 'L' : code = offlineStrings.getString('common.barcode.status.warning.lost'); break;
                case 'E' : code = offlineStrings.getString('common.barcode.status.warning.expired'); break;
                case 'B' : code = offlineStrings.getString('common.barcode.status.warning.barred'); break;
                case 'D' : code = offlineStrings.getString('common.barcode.status.warning.blocked'); break;
                default : code = offlineStrings.getFormattedString('common.barcode.status.warning.blocked', [g.data.bad_patrons[barcode]]); break;
            }

            var msg = offlineStrings.getFormattedString('common.barcode.status.warning', [g.data.bad_patrons_date.substr(0,15), barcode, code]);
            var r = g.error.yns_alert(msg,offlineStrings.getString('circ.barcode.warning'),offlineStrings.getString('common.ok'),offlineStrings.getString('common.clear'),null,offlineStrings.getString('common.confirm'));
            if (r == 1) {
                setTimeout(
                    function() {
                        ev.target.value = '';
                        ev.target.focus();
                    },0
                );
            }
        }
    } catch(E) {
        alert(E);
    }
}

function check_date(ev) {
    JSAN.use('util.date');
    try {
        if (! util.date.check('YYYY-MM-DD',ev.target.value) ) { throw(offlineStrings.getString('common.date.invalid')); }
        if (util.date.check_past('YYYY-MM-DD',ev.target.value) ) { throw(offlineStrings.getString('circ.offline_checkout.date.early')); }
        if (util.date.formatted_date(new Date(),'%F') == ev.target.value) { throw(offlineStrings.getString('circ.offline_checkout.date.early')); }
    } catch(E) {
        alert(E);
        var today = new Date();
        var todayPlus = new Date(); todayPlus.setTime( today.getTime() + 24*60*60*1000*14 );
        todayPlus = util.date.formatted_date(todayPlus,"%F");
        ev.target.value = todayPlus;
    }
}

function handle_keypress(ev) {
    if ( (! ev.keyCode) || (ev.keyCode != 13) ) return;
    switch(ev.target) {
        case $('p_barcode') : /*$('p_barcode').disabled = true;*/ setTimeout( function() { $('i_barcode').focus(); },0 ); break;
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
            append_to_list('barcode');
        }
    } else {
        append_to_list('barcode');
    }
}

function handle_duedate_menu(ev) {
    if (ev.target.value=='0') return; 
    JSAN.use('util.date'); 
    var today = new Date(); 
    var todayPlus = new Date(); 
    todayPlus.setTime( today.getTime() + 24*60*60*1000*ev.target.value ); 
    todayPlus = util.date.formatted_date(todayPlus,'%F'); 
    $('duedate').setAttribute('value',todayPlus); 
    $('duedate').value = todayPlus;
}

function append_to_list(checkout_type,count) {

    try {

        var my = {};

        my.type = 'checkout';
        my.timestamp = parseInt( new Date().getTime() / 1000) + g.delta;
        my.checkout_time = util.date.formatted_date(new Date(),"%F %H:%M:%s");

        var p_barcode = $('p_barcode').value;
        if (! p_barcode) {
            g.error.yns_alert(offlineStrings.getString('circ.barcode.enter'),offlineStrings.getString('circ.offline_checkout.required_field'),offlineStrings.getString('common.ok'),null,null,offlineStrings.getString('common.confirm'));
            return;
        } else {

            // Need to validate patron barcode against bad patron list
            my.patron_barcode = p_barcode;
        }

        var due_date = $('duedate').value; // Need to validate this
        my.due_date = due_date;

        var i_barcode = $('i_barcode').value;
        switch(checkout_type) {
            case 'barcode' : 
                if (! i_barcode) return; 
                
                var rows = g.list.dump_with_keys();
                for (var i = 0; i < rows.length; i++) {
                    if (rows[i].barcode == i_barcode) {
                        g.error.yns_alert(offlineStrings.getString('circ.duplicate_scan.msg'),offlineStrings.getString('circ.duplicate_scan.field'),offlineStrings.getString('common.ok'),null,null,offlineStrings.getString('common.confirm'));
                        return;
                    }
                }

                my.barcode = i_barcode; 
            break;
            case 'noncat' :
                count = parseInt(count); if (! (count>0) ) {
                    g.error.yns_alert(offlineStrings.getString('circ.offline_checkout.valid_count'),offlineStrings.getString('circ.offline_checkout.required_value'),offlineStrings.getString('common.ok'),null,null,offlineStrings.getString('common.confirm'));
                    return;
                }
                my.barcode = $('noncat_type_menu').getAttribute('label');
                my.noncat = 1;
                my.noncat_type = JSON2js($('noncat_type_menu').value)[0];
                my.noncat_count = count;
            break;
            default: alert(offlineStrings.getString('common.error.default')); break;
        }
    
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


function save_xacts() {
    JSAN.use('util.file'); var file = new util.file('pending_xacts');
    var rows = g.list.dump_with_keys();
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i]; row.delta = g.delta;
        if (row.noncat == 1) {
            delete(row.barcode);
        } else {
            delete(row.noncat);
            delete(row.noncat_type);
            delete(row.noncat_count);
        }
        file.append_object(row);
    }
    file.close();

    if (local_lock) {
        local_lock = false;
        xulG.unlock();
    }
}

function next_patron(cancel) {
    try {
    
        if ($('print_receipt').checked && (cancel!='cancel')) {
            try {
                var params = {
                    'patron_barcode' : $('p_barcode').value,
                    'template' : 'offline_checkout',
                    'printer_context' : 'offline',
                    'callback' : function() {
                        g.list.clear();
                        var x = $('i_barcode'); x.value = '';
                        x = $('p_barcode'); x.value = ''; 
                        x.setAttribute('disabled','false'); x.disabled = false; 
                        x.focus();
                    }
                };
                g.list.print( params );
            } catch(E) {
                g.error.sdump('D_ERROR','print: ' + E);
                alert('print: ' + E);
            }
        } else {
            g.list.clear();
            var x = $('i_barcode'); x.value = '';
            x = $('p_barcode'); x.value = ''; 
            x.setAttribute('disabled','false'); x.disabled = false; 
            x.focus();
        }
    } catch(E) {
        dump(E+'\n'); alert(E);
    }
}
