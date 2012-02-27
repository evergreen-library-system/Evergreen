var offlineStrings;
var local_lock = false;

function my_init() {
    try {
        offlineStrings = $('offlineStrings');
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for offline_renew.xul');

        if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
            try { window.xulG.set_tab_name('Standalone'); } catch(E) { alert(E); }
        }

        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});

        JSAN.use('util.list'); g.list = new util.list('checkout_list');
        JSAN.use('circ.util');
        g.list.init( {
            'columns' : circ.util.offline_renew_columns(),
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

        $('p_barcode').addEventListener('keypress',handle_lock,false);
        $('p_barcode').addEventListener('change',test_patron,false);

        $('p_barcode').addEventListener('keypress',handle_keypress,false);
        $('p_barcode').focus();    

        $('i_barcode').addEventListener('keypress',handle_lock,false);
        $('i_barcode').addEventListener('keypress',handle_keypress,false);
        $('enter').addEventListener('command',handle_enter,false);

        $('duedate_menu').addEventListener('command',handle_duedate_menu,false);

        $('submit').addEventListener('command',next_patron,false);
        $('cancel').addEventListener('command',function(){next_patron('cancel');},false);

        JSAN.use('util.file');
        var file = new util.file('offline_delta'); 
        if (file._file.exists()) { g.delta = file.get_object()[0]; file.close(); } else { g.delta = 0; }

    } catch(E) {
        var err_msg = "!! This software has encountered an error.  Please tell your friendly " +
            "system administrator or software developer the following:\ncirc/offline_renew.xul\n" + E + '\n';
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
            var r = g.error.yns_alert('This barcode has a bad checkdigit.','Barcode Warning','Ok','Clear',null,'Check here to confirm this message');
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
            var msg = 'Warning: As of ' + g.data.bad_patrons_date.substr(0,15) + ', this barcode (' + barcode + ') was flagged ';
            switch(g.data.bad_patrons[barcode]) {
                case 'L' : msg += 'Lost'; break;
                case 'E' : msg += 'Expired'; break;
                case 'B' : msg += 'Barred'; break;
                case 'D' : msg += 'Blocked'; break;
                default : msg += ' with an unknown code: ' + g.data.bad_patrons[barcode]; break;
            }
            var r = g.error.yns_alert(msg,'Barcode Warning','Ok','Clear',null,'Check here to confirm this message');
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

function handle_keypress(ev) {
    if ( (! ev.keyCode) || (ev.keyCode != 13) ) return;
    switch(ev.target) {
        case $('p_barcode') : setTimeout( function() { $('i_barcode').focus(); },0 ); break;
        case $('i_barcode') : handle_enter(); break;
        default: break;
    }
}

function handle_enter(ev) {
    JSAN.use('util.barcode');
    if ( ($('strict_i_barcode').checked) && (! util.barcode.check($('i_barcode').value)) ) {
        var r = g.error.yns_alert('This barcode has a bad checkdigit.','Barcode Warning','Ok','Clear',null,'Check here to confirm this message');
        if (r == 1) {
            setTimeout(
                function() {
                    ev.target.value = '';
                    ev.target.focus();
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

function check_date(ev) {
    JSAN.use('util.date');
    try {
        if (! util.date.check('YYYY-MM-DD',ev.target.value) ) { throw('Invalid Date'); }
        if (util.date.check_past('YYYY-MM-DD',ev.target.value) ) { throw('Due date needs to be after today.'); }
        if ( util.date.formatted_date(new Date(),'%F') == ev.target.value) { throw('Due date needs to be after today.'); }
    } catch(E) {
        alert(E);
        var today = new Date();
        var todayPlus = new Date(); todayPlus.setTime( today.getTime() + 24*60*60*1000*14 );
        todayPlus = util.date.formatted_date(todayPlus,"%F");
        ev.target.value = todayPlus;
    }
}

function append_to_list(checkout_type,count) {

    try {

        var my = {};

        my.type = 'renew';
        my.timestamp = parseInt( new Date().getTime() / 1000) + g.delta;
        my.checkout_time = util.date.formatted_date(new Date(),"%F %H:%M:%s");

        var p_barcode = $('p_barcode').value;
        if (! p_barcode) {
            /* Not strictly necessary for a renewal
            alert('Please enter a patron barcode first.');
            return;
            */
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
                        g.error.yns_alert('This barcode has already been scanned.','Duplicate Scan','Ok',null,null,'Check here to confirm this message');
                        return;
                    }
                }

                my.barcode = i_barcode; 
            break;
            default: alert("Please report that this happened."); break;
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

function next_patron(cancel) {
    try {

        if (cancel!='cancel') {
                JSAN.use('util.file'); var file = new util.file('pending_xacts');
                var rows = g.list.dump_with_keys();
                for (var i = 0; i < rows.length; i++) {
                    var row = rows[i]; row.delta = g.delta;
                    if (row.patron_barcode == '') {
                        delete(row.patron_barcode);
                    }
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
                            'patron_barcode' : $('p_barcode').value,
                            'template' : 'offline_renew',
                            'printer_context' : 'offline',
                            'callback' : function() {
                                g.list.clear();
                                var x = $('i_barcode'); x.value = '';
                                x = $('p_barcode'); x.value = ''; x.focus();
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
                    x = $('p_barcode'); x.value = ''; x.focus();
                }
        }
    } catch(E) {
        dump(E+'\n'); alert(E);
    }
}
