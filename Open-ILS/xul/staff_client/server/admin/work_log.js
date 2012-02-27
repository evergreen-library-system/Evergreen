var error;
var list1; var selected1 = [];
var list2; var selected2 = [];
var data;
var max_work_log_entries;
var max_patron_log_entries;

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); error = new util.error();
        error.sdump('D_TRACE','my_init() for main_test.xul');

        JSAN.use('OpenILS.data'); data = new OpenILS.data(); data.stash_retrieve();

        max_work_log_entries = data.hash.aous['ui.admin.work_log.max_entries'] || 20;
        max_patron_log_entries = data.hash.aous['ui.admin.patron_log.max_entries'] || 10;

        init_lists();
        set_behavior();
        populate_lists();
        default_focus();

    } catch(E) {
        try { error.standard_unexpected_error_alert('admin/work_log.xul,my_init():',E); } catch(F) { alert(E); }
    }
}

function default_focus() {
    var btn = document.getElementById('refresh_btn');
    if (btn) btn.focus();
}

function init_lists() {
    try {
        var cmd_retrieve_item = document.getElementById('cmd_retrieve_item');
        var cmd_retrieve_patron1 = document.getElementById('cmd_retrieve_patron1');
        var cmd_retrieve_patron2 = document.getElementById('cmd_retrieve_patron2');

        JSAN.use('util.list');

        list1 = new util.list('work_action_log');
        list2 = new util.list('work_patron_log');

        JSAN.use('circ.util'); var columns = circ.util.work_log_columns({});

        list1.init( {
            'columns' : columns,
            'on_select' : function(ev) {
                JSAN.use('util.functional'); var sel = list1.retrieve_selection();
                selected1 = util.functional.map_list( sel, function(o) { return JSON2js(o.getAttribute('retrieve_id')); });
                if (selected1.length == 0) { 
                    cmd_retrieve_patron1.setAttribute('disabled','true');
                    cmd_retrieve_item.setAttribute('disabled','true');
                } else { 
                    cmd_retrieve_patron1.setAttribute('disabled','false');
                    cmd_retrieve_item.setAttribute('disabled','false');
                }
            }
        } );

        list2.init( {
            'columns' : columns,
            'on_select' : function(ev) {
                JSAN.use('util.functional'); var sel = list2.retrieve_selection();
                selected2 = util.functional.map_list( sel, function(o) { return JSON2js(o.getAttribute('retrieve_id')); });
                if (selected2.length == 0) { 
                    cmd_retrieve_patron2.setAttribute('disabled','true');
                } else { 
                    cmd_retrieve_patron2.setAttribute('disabled','false');
                }
            }
        } );

    } catch(E) {

        try { error.standard_unexpected_error_alert('admin/work_log.xul,init_lists():',E); } catch(F) { alert(E); }
    }
}

function populate_lists() {
    try {
        list1.clear();
        data.stash_retrieve();
        if (data.work_log) {
            var count = data.work_log.length;
            var x = document.getElementById('desire_number_of_work_log_entries');
            if (x) {
                if (Number(x.value) < count) { count = Number(x.value); }
            }
            for (var i = 0; i < count; i++ ) { 
                list1.append( data.work_log[i] );
            }
        }
        list2.clear();
        if (data.patron_log) {
            var count = data.patron_log.length;
            var y = document.getElementById('desire_number_of_patron_log_entries');
            if (y) {
                if (Number(y.value) < count) { count = Number(y.value); }
            }
            for (var i = 0; i < count; i++ ) { 
                list2.append( data.patron_log[i] );
            }
        }
    } catch(E) {
        try { error.standard_unexpected_error_alert('admin/work_log.xul,populate_lists():',E); } catch(F) { alert(E); }
    }
}

function set_behavior() {
    try {

        var x = document.getElementById('desire_number_of_work_log_entries');
        if (x) {
            x.setAttribute('max',max_work_log_entries);
            if (!x.value) { x.setAttribute('value',max_work_log_entries); x.value = max_work_log_entries; }
        }
        var y = document.getElementById('desire_number_of_patron_log_entries');
        if (y) {
            y.setAttribute('max',max_patron_log_entries);
            if (!y.value) { y.setAttribute('value',max_patron_log_entries); y.value = max_patron_log_entries; }
        }

        var cmd_refresh = document.getElementById('cmd_refresh');
        var cmd_retrieve_item = document.getElementById('cmd_retrieve_item');
        var cmd_retrieve_patron1 = document.getElementById('cmd_retrieve_patron1');
        var cmd_retrieve_patron2 = document.getElementById('cmd_retrieve_patron2');

        if (cmd_refresh) cmd_refresh.addEventListener('command', function() { populate_lists(); }, false);

        function gen_patron_retrieval_func(which) {
            return function(ev) {
               try {
                    var selected = which == 1 ? selected1 : selected2;
                    var seen = {};
                    for (var i = 0; i < selected.length; i++) {
                        var patron_id = selected[i].au_id;
                        if (typeof patron_id == 'null') continue;
                        if (seen[patron_id]) continue; seen[patron_id] = true;
                        xulG.new_patron_tab(
                            {},
                            { 'id' : patron_id }
                        );
                    }
                } catch(E) {
                    error.standard_unexpected_error_alert('Error in work_log.js, patron_retrieval_func():',E);
                }
            };
        }
        if (cmd_retrieve_patron1) cmd_retrieve_patron1.addEventListener('command', gen_patron_retrieval_func(1), false);
        if (cmd_retrieve_patron2) cmd_retrieve_patron2.addEventListener('command', gen_patron_retrieval_func(2), false);

        if (cmd_retrieve_item) cmd_retrieve_item.addEventListener(
            'command',
            function(ev) {
                try {
                    var seen = {}; var barcodes = [];
                    for (var i = 0; i < selected1.length; i++) {
                        var barcode = selected1[i].acp_barcode;
                        if (typeof barcode == 'null') continue;
                        if (seen[barcode]) continue; seen[barcode] = true;
                        barcodes.push( barcode );
                    }
                    if (barcodes.length > 0) {
                        xulG.new_tab(
                            urls.XUL_COPY_STATUS,
                            {},
                            { 'barcodes' : barcodes }
                        );
                    }
                } catch(E) {
                    error.standard_unexpected_error_alert('Error in work_log.js, retrieve_item():',E);
                }
            },
            false
        );

    } catch(E) {
        try { error.standard_unexpected_error_alert('admin/work_log.xul,set_behavior():',E); } catch(F) { alert(E); }
    }
}

