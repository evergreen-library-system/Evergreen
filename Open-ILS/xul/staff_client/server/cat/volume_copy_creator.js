const g_max_copies_that_can_be_added_at_a_time_per_volume = 999;
var g = {};

function my_init() {
    try {

        /***********************************************************************************************************/
        /* Initial setup */

        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for cat/volume_copy_creator.xul');

        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
        JSAN.use('util.widgets'); JSAN.use('util.functional');

        JSAN.use('util.network'); g.network = new util.network();

        g.refresh = xul_param('onrefresh');

        /***********************************************************************************************************/
        /* Am I adding just copies or copies and volumes?  Or am I rebarcoding existing copies? */

        // g.copy_shortcut = { ou_id : { callnumber_label : callnumber_id }, ... }
        g.copy_shortcut = xul_param('copy_shortcut');
        // g.existing_copies = [ copy1, copy2, ... ]
        g.existing_copies = xul_param('existing_copies') || [];

        function set_attr(id,attr,msgcat_key) {
            var x = $(id);
            if (x) {
                x.setAttribute(
                    attr,
                    $('catStrings').getString(msgcat_key)
                );
            }
        }
        if (g.existing_copies.length > 0) {
            set_attr('EditThenCreate','label','staff.cat.volume_copy_creator.edit_then_rebarcode.btn.label');
            set_attr('EditThenCreate','accesskey','staff.cat.volume_copy_creator.edit_then_rebarcode.btn.accesskey');
            set_attr('CreateWithDefaults','label','staff.cat.volume_copy_creator.rebarcode.btn.label');
            set_attr('CreateWithDefaults','accesskey','staff.cat.volume_copy_creator.rebarcode.btn.accesskey');
        } else {
            set_attr('EditThenCreate','label','staff.cat.volume_copy_creator.edit_then_create.btn.label');
            set_attr('EditThenCreate','accesskey','staff.cat.volume_copy_creator.edit_then_create.btn.accesskey');
            set_attr('CreateWithDefaults','label','staff.cat.volume_copy_creator.create_with_defaults.btn.label');
            set_attr('CreateWithDefaults','accesskey','staff.cat.volume_copy_creator.create_with_defaults.btn.accesskey');
        }

        //g.error.sdump('D_ERROR','location.href = ' + location.href + '\n\ncopy_short cut = ' + g.copy_shortcut + '\n\nou_ids = ' + xul_param('ou_ids'));

        var ou_ids = xul_param('ou_ids',{'concat' : true}) || [];

        // Get the default callnumber classification scheme from OU settings
        dojo.require('fieldmapper.OrgUtils');
        var label_class = g.data.hash.aous['cat.default_classification_scheme']; //fieldmapper.aou.fetchOrgSettingDefault(ses('ws_ou'), 'cat.default_classification_scheme');

        // Assign a default value if none was returned 
        if (!label_class) {
            label_class = 1;
        }

        /***********************************************************************************************************/
        /* If we're passed existing_copies, rig up a copy_shortcut object to leverage existing code for rendering the volume labels, etc. 
         * Also make a lookup object for existing copies keyed on org id and callnumber label, and another keyed on copy id. */

        // g.org_label_existing_copy_map = { ou_id : { callnumber_label : [ copy1, copy2, ... ] }, ... }
        g.org_label_existing_copy_map = {};
        // g.id_copy_map = { acp_id : acp, ... }
        g.id_copy_map = {};
        for (var i = 0; i < g.existing_copies.length; i++) {
            if (! g.copy_shortcut) { g.copy_shortcut = {}; }
            var copy = g.existing_copies[i];
            g.id_copy_map[ copy.id() ] = copy;
            var call_number = copy.call_number();
            g.doc_id = call_number.record();
            if (!g.copy_shortcut[ call_number.owning_lib() ]) {
                ou_ids.push( call_number.owning_lib() );
                g.copy_shortcut[ call_number.owning_lib() ] = {};
                g.org_label_existing_copy_map[ call_number.owning_lib() ] = {};
            }
            g.copy_shortcut[ call_number.owning_lib() ][ call_number.label() ] = call_number.id();
            if (! g.org_label_existing_copy_map[ call_number.owning_lib() ][ call_number.label() ]) {
                g.org_label_existing_copy_map[ call_number.owning_lib() ][ call_number.label() ] = [];
            }
            g.org_label_existing_copy_map[ call_number.owning_lib() ][ call_number.label() ].push( copy );
        }

        /***********************************************************************************************************/
        /* What record am I dealing with?  */

        g.doc_id = g.doc_id || xul_param('doc_id');
        if (! g.doc_id) {
            alert('Error in volume_copy_creator.js, g.doc_id not valid');
            window.close(); return;
        }
        var sb = document.getElementById('summary_box'); while(sb.firstChild) sb.removeChild(sb.lastChild);
        var summary = document.createElement('iframe'); sb.appendChild(summary);
        summary.setAttribute('src',urls.XUL_BIB_BRIEF);
        summary.setAttribute('flex','1');
        get_contentWindow(summary).xulG = { 'docid' : g.doc_id };

        /***********************************************************************************************************/
        /* For the call number drop down */

        if (g.existing_copies.length > 0 || !g.copy_shortcut) {
            g.list_callnumbers(g.doc_id, label_class);
        }

        /***********************************************************************************************************/
        /* render the orgs and volumes/input */

        var rows = document.getElementById('rows');

        var node_id = 0;
        for (var i = 0; i < ou_ids.length; i++) {
            try {
                var org = g.data.hash.aou[ ou_ids[i] ];
                if ( get_bool( g.data.hash.aout[ org.ou_type() ].can_have_vols() ) ) {
                    var row = document.createElement('row'); rows.appendChild(row); row.setAttribute('ou_id',ou_ids[i]);
                    g.render_library_label(row,ou_ids[i]);
                    g.render_volume_count_entry( row, ou_ids[i] );
                }
            } catch(E) {
                g.error.sdump('D_ERROR',E);
            }
        }

        g.load_prefs();

    } catch(E) {
        var err_msg = $("commonStrings").getFormattedString('common.exception', ['cat/volume_copy_creator.js', E]);
        try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); dump(js2JSON(E)); }
        alert(err_msg);
    }
}

g.render_library_label = function(row,ou_id) {
    var label = document.createElement('label'); row.appendChild(label);
    label.setAttribute('ou_id',ou_id);
    label.setAttribute('value',g.data.hash.aou[ ou_id ].shortname());
}

g.render_volume_count_entry = function(row,ou_id) {
    var hb = document.createElement('vbox'); row.appendChild(hb);
    var tb = document.createElement('textbox'); hb.appendChild(tb);
    tb.setAttribute('ou_id',ou_id); tb.setAttribute('size','3'); tb.setAttribute('cols','3');
    tb.setAttribute('rel_vert_pos','1'); 
    if ( (!g.copy_shortcut) && (!g.last_focus) ) { tb.focus(); g.last_focus = tb; }
    var node;
    function render_copy_count_entry(ev) {
        if (ev.target.disabled) return;
        if (! isNaN( Number( ev.target.value) ) ) {
            if ( Number( ev.target.value ) > g_max_copies_that_can_be_added_at_a_time_per_volume ) {
                g.error.yns_alert($("catStrings").getFormattedString('staff.cat.volume_copy_creator.render_volume_count_entry.message', [g_max_copies_that_can_be_added_at_a_time_per_volume]),
                    $("catStrings").getString('staff.cat.volume_copy_creator.render_volume_count_entry.title'),
                    $("catStrings").getString('staff.cat.volume_copy_creator.render_volume_count_entry.ok_label'),null,null,'');
                return;
            }
            if (node) { row.removeChild(node); node = null; }
            //ev.target.disabled = true;
            node = g.render_callnumber_copy_count_entry(row,ou_id,ev.target.value);
        }
    }
    util.widgets.apply_vertical_tab_on_enter_handler( 
        tb, 
        function() { render_copy_count_entry({'target':tb}); setTimeout(function(){util.widgets.vertical_tab(tb);},0); }
    );
    tb.addEventListener( 'change', render_copy_count_entry, false);
    tb.addEventListener( 'focus', function(ev) { g.last_focus = ev.target; }, false );
    setTimeout(
        function() {
            try {
                if (g.copy_shortcut) {
                    JSAN.use('util.functional');
                    tb.value = util.functional.map_object_to_list(
                        g.copy_shortcut[ou_id],
                        function(o,i) {
                            return g.copy_shortcut[ou_id][i];
                        }
                    ).length;
                    render_copy_count_entry({'target':tb});
                    tb.disabled = true;
                }
            } catch(E) {
                alert(E);
            }
        }, 0
    );
}

g.render_callnumber_copy_count_entry = function(row,ou_id,count) {
    var grid = util.widgets.make_grid( [ {}, {} ] ); row.appendChild(grid);
    grid.setAttribute('flex','1');
    grid.setAttribute('ou_id',ou_id);
    var rows = grid.lastChild;
    var r = document.createElement('row'); rows.appendChild( r );
    var x = document.createElement('label'); r.appendChild(x);
    x.setAttribute('value', $("catStrings").getString('staff.cat.volume_copy_creator.render_callnumber_copy_count_entry.call_nums')); x.setAttribute('style','font-weight: bold');
    x = document.createElement('label'); r.appendChild(x);
    x.setAttribute('value',$("catStrings").getString('staff.cat.volume_copy_creator.render_callnumber_copy_count_entry.num_of_copies')); x.setAttribute('style','font-weight: bold');
    x.setAttribute('size','3'); x.setAttribute('cols','3');

    function handle_change(call_number_column_textbox,number_of_copies_column_textbox,barcode_column_box) {
        if (call_number_column_textbox.value == '') return;
        if (isNaN( Number( number_of_copies_column_textbox.value ) )) return;
        if ( Number( number_of_copies_column_textbox.value ) > g_max_copies_that_can_be_added_at_a_time_per_volume ) {
            g.error.yns_alert($("catStrings").getFormattedString('staff.cat.volume_copy_creator.render_volume_count_entry.message', [g_max_copies_that_can_be_added_at_a_time_per_volume]),
                $("catStrings").getString('staff.cat.volume_copy_creator.render_volume_count_entry.title'),
                $("catStrings").getString('staff.cat.volume_copy_creator.render_volume_count_entry.ok_label'),null,null,'');
            return;
        }

        while (barcode_column_box.childNodes.length > Number(number_of_copies_column_textbox.value)) {
            barcode_column_box.removeChild( barcode_column_box.lastChild );
        }
        g.render_barcode_entry(
            barcode_column_box,
            call_number_column_textbox.value,
            Number(number_of_copies_column_textbox.value),
            ou_id
        );

        document.getElementById("EditThenCreate").disabled = false;
        document.getElementById("CreateWithDefaults").disabled = false;
    }

    function handle_change_call_number_column_textbox(ev) {
        var _call_number_column_textbox = ev.target;    
        var _call_number_column_box = _call_number_column_textbox.parentNode;
        var _number_of_copies_column_box = _call_number_column_box.nextSibling;
        var _number_of_copies_column_textbox = _number_of_copies_column_box.firstChild;
        var _barcode_column_box = _number_of_copies_column_box.nextSibling;
        handle_change(_call_number_column_textbox,_number_of_copies_column_textbox,_barcode_column_box);
    }

    function handle_change_number_of_copies_column_textbox(ev) {
        var _number_of_copies_column_textbox = ev.target;    
        var _number_of_copies_column_box = _number_of_copies_column_textbox.parentNode;
        var _call_number_column_box = _number_of_copies_column_box.previousSibling;
        var _call_number_column_textbox = _call_number_column_box.firstChild;
        var _barcode_column_box = _number_of_copies_column_box.nextSibling;
        handle_change(_call_number_column_textbox,_number_of_copies_column_textbox,_barcode_column_box);
    }

    for (var i = 0; i < count; i++) {
        var r = document.createElement('row'); rows.appendChild(r);
        var call_number_column_box = document.createElement('vbox'); r.appendChild(call_number_column_box);
        var number_of_copies_column_box = document.createElement('vbox'); r.appendChild(number_of_copies_column_box);
        var barcode_column_box = document.createElement('vbox'); r.appendChild(barcode_column_box);
        var call_number_column_textbox = document.createElement('textbox'); call_number_column_box.appendChild(call_number_column_textbox);
        call_number_column_textbox.setAttribute('rel_vert_pos','2');
        call_number_column_textbox.setAttribute('ou_id',ou_id);
        util.widgets.apply_vertical_tab_on_enter_handler( 
            call_number_column_textbox, 
            function() { handle_change_call_number_column_textbox({'target':call_number_column_textbox}); setTimeout(function(){util.widgets.vertical_tab(call_number_column_textbox);},0); }
        );
        var number_of_copies_column_textbox = document.createElement('textbox'); number_of_copies_column_box.appendChild(number_of_copies_column_textbox);
        number_of_copies_column_textbox.setAttribute('size','3'); number_of_copies_column_textbox.setAttribute('cols','3');
        number_of_copies_column_textbox.setAttribute('rel_vert_pos','3');
        number_of_copies_column_textbox.setAttribute('ou_id',ou_id);
        util.widgets.apply_vertical_tab_on_enter_handler( 
            number_of_copies_column_textbox, 
            function() { handle_change_number_of_copies_column_textbox({'target':number_of_copies_column_textbox}); setTimeout(function(){util.widgets.vertical_tab(number_of_copies_column_textbox);},0); }
        );

        call_number_column_textbox.addEventListener( 'change', handle_change_call_number_column_textbox, false);
        call_number_column_textbox.addEventListener( 'focus', function(ev) { g.last_focus = ev.target; }, false );
        number_of_copies_column_textbox.addEventListener( 'change', handle_change_number_of_copies_column_textbox, false);
        number_of_copies_column_textbox.addEventListener( 'focus', function(ev) { g.last_focus = ev.target; }, false );
        if ( !g.last_focus ) { number_of_copies_column_textbox.focus(); g.last_focus = number_of_copies_column_textbox; }

        setTimeout(
            function(idx,call_number_column_textbox,number_of_copies_column_textbox){
                return function() {
                    try {
                        JSAN.use('util.functional');
                        if (g.copy_shortcut) {
                            var label = util.functional.map_object_to_list(
                                g.copy_shortcut[ou_id],
                                function(o,i) {
                                    return i;
                                }
                            )[idx];
                            if (g.org_label_existing_copy_map[ou_id]) {
                                var num_of_copies = g.org_label_existing_copy_map[ou_id][label].length;
                                if (num_of_copies>0) {
                                    number_of_copies_column_textbox.value = num_of_copies;
                                    number_of_copies_column_textbox.disabled = true;
                                }
                            }
                            call_number_column_textbox.value = label; 
                            handle_change_call_number_column_textbox({'target':call_number_column_textbox});
                            if (g.existing_copies.length < 1) {
                                call_number_column_textbox.disabled = true;
                            }
                        }
                    } catch(E) {
                        alert(E);
                    }
                }
            }(i,call_number_column_textbox,number_of_copies_column_textbox),0
        );
    }

    return grid;
}

g.render_barcode_entry = function(node,callnumber,count,ou_id) {
    try {
        function ready_to_create(ev) {
            document.getElementById("EditThenCreate").disabled = false;
            document.getElementById("CreateWithDefaults").disabled = false;
        }

        JSAN.use('util.barcode'); 

        for (var i = 0; i < count; i++) {
            var tb; var set_handlers = false;
            if (typeof node.childNodes[i] == 'undefined') {
                tb = document.createElement('textbox'); node.appendChild(tb);
                set_handlers = true;
            } else {
                tb = node.childNodes[i];
            }
            tb.setAttribute('ou_id',ou_id);
            tb.setAttribute('callnumber',callnumber);
            tb.setAttribute('rel_vert_pos','4');
            if (!tb.value && g.org_label_existing_copy_map[ ou_id ]) {
                tb.value = g.org_label_existing_copy_map[ ou_id ][ callnumber ][i].barcode();
                tb.setAttribute('acp_id', g.org_label_existing_copy_map[ ou_id ][ callnumber ][i].id());
                tb.select();
                if (! g.first_focus) { g.first_focus = tb; }
            }
            if (set_handlers) {
                util.widgets.apply_vertical_tab_on_enter_handler( 
                    tb, 
                    function() { ready_to_create({'target':tb}); setTimeout(function(){util.widgets.vertical_tab(tb);},0); }
                );
                tb.addEventListener('change', function(ev) {
                    var barcode = String( ev.target.value ).replace(/\s/g,'');
                    if (barcode != ev.target.value) ev.target.value = barcode;
                    if ($('check_barcodes').checked && ! util.barcode.check(barcode) ) {
                        g.error.yns_alert($("catStrings").getFormattedString('staff.cat.volume_copy_creator.render_barcode_entry.alert_message', [barcode]),
                            $("catStrings").getString('staff.cat.volume_copy_creator.render_barcode_entry.alert_title'),
                            $("catStrings").getString('staff.cat.volume_copy_creator.render_barcode_entry.alert_ok_button'),null,null,
                            $("catStrings").getString('staff.cat.volume_copy_creator.render_barcode_entry.alert_confirm'));
                        setTimeout( function() { ev.target.select(); ev.target.focus(); }, 0);
                    }
                }, false);
                tb.addEventListener( 'focus', function(ev) { g.last_focus = ev.target; }, false );
            }
        }
        
        setTimeout( function() { if (g.first_focus) { g.first_focus.focus(); } }, 0 ); 

    } catch(E) {
        g.error.sdump('D_ERROR','g.render_barcode_entry: ' + E);
    }
}

g.generate_barcodes = function() {
    try {
        var nodes = document.getElementsByAttribute('rel_vert_pos','4');
        if (nodes.length < 1) { return; }
        var first_barcode = nodes[0].value;

        if (! first_barcode) { return; }

        var barcodes = g.network.simple_request(
            'AUTOGENERATE_BARCODES',
            [
                ses(),
                first_barcode,
                nodes.length - 1,
                $('check_barcodes').checked ? {} : { "checkdigit" : false }
            ]
        );

        if (typeof barcodes.ilsevent != 'undefined') {
            throw(barcodes);
        }

        for (var i = 0; i < barcodes.length; i++) {
            nodes[i+1].value = barcodes[i];
            nodes[i+1].select();
        }

    } catch(E) {
        g.error.sdump('D_ERROR','g.generate_barcodes: ' + E);
    }
}

g.new_node_id = -1;

g.stash_and_close = function(param) {

    try {

        var nl = document.getElementsByTagName('textbox');

        var volumes_hash = {};

        var barcodes = [];
        
        for (var i = 0; i < nl.length; i++) {
            if ( nl[i].getAttribute('rel_vert_pos') == 4 ) barcodes.push( nl[i] );
            if ( nl[i].getAttribute('rel_vert_pos') == 2 )  {
                var ou_id = nl[i].getAttribute('ou_id');
                var callnumber = nl[i].value;
                if (typeof volumes_hash[ou_id] == 'undefined') { volumes_hash[ou_id] = {} }
                if (typeof volumes_hash[ou_id][callnumber] == 'undefined') { volumes_hash[ou_id][callnumber] = [] }
            }
        };
    
        for (var i = 0; i < barcodes.length; i++) {
            var acp_id = barcodes[i].getAttribute('acp_id') || g.new_node_id--;
            var ou_id = barcodes[i].getAttribute('ou_id');
            var callnumber = barcodes[i].getAttribute('callnumber');
            var barcode = barcodes[i].value;

            if (typeof volumes_hash[ou_id] == 'undefined') { volumes_hash[ou_id] = {} }
            if (typeof volumes_hash[ou_id][callnumber] == 'undefined') { volumes_hash[ou_id][callnumber] = [] }

            if (barcode != '') volumes_hash[ou_id][callnumber].push( { 'barcode' : barcode, 'acp_id' : acp_id } );
        }

        var volumes = [];
        var copies = [];
        var volume_labels = {};

        function new_copy(acp_id,ou_id,acn_id,barcode) {
            var copy = new acp();
            copy.id( acp_id );
            copy.isnew('1');
            copy.barcode( barcode );
            copy.call_number( acn_id );
            copy.circ_lib(ou_id);
            /* FIXME -- use constants */
            copy.deposit(0);
            copy.price(0);
            copy.deposit_amount(0);
            copy.fine_level(2); // Normal
            copy.loan_duration(2); // Normal
            copy.location(1); // Stacks
            copy.status(5); // In Process
            copy.circulate(get_db_true());
            copy.holdable(get_db_true());
            copy.opac_visible(get_db_true());
            copy.ref(get_db_false());
            copy.mint_condition(get_db_true());
            return copy;
        }

        for (var ou_id in volumes_hash) {
            for (var cn_label in volumes_hash[ou_id]) {

                var acn_id = g.network.simple_request(
                    'FM_ACN_FIND_OR_CREATE',
                    [ ses(), cn_label, g.doc_id, ou_id ]
                );

                if (typeof acn_id.ilsevent != 'undefined') {
                    g.error.standard_unexpected_error_alert($("catStrings").getFormattedString('staff.cat.volume_copy_creator.stash_and_close.problem_with_volume', [cn]), acn_id);
                    continue;
                }

                volume_labels[ acn_id ] = { 'label' : cn_label, 'owning_lib' : ou_id };

                for (var i = 0; i < volumes_hash[ou_id][cn_label].length; i++) {
                    var barcode = volumes_hash[ou_id][cn_label][i].barcode;
                    var acp_id = volumes_hash[ou_id][cn_label][i].acp_id;
                    var copy;
                    if (acp_id < 0) {
                        copy = new_copy(acp_id,ou_id,acn_id,barcode);
                    } else {
                        copy = g.id_copy_map[ acp_id ];
                        copy.barcode( barcode );
                        copy.call_number( acn_id );
                        copy.ischanged('1');
                    }
                    copies.push( copy );
                }
            }
        }

        var dont_close = false;
        JSAN.use('util.window'); var win = new util.window();
        if (copies.length > 0) {
            JSAN.use('cat.util');
            if (param == 'edit') {
                copies = cat.util.spawn_copy_editor( { 'edit' : true, 'docid' : g.doc_id, 'copies' : copies, 'caller_handles_update' : true });
            }
            if (typeof xul_param('update_copy') == 'function') {
                xul_param('update_copy')(copies);
            } else {
                 var r = g.network.simple_request(
                    'FM_ACP_FLESHED_BATCH_UPDATE',
                    [ ses(),copies, true ]
                );
                if (typeof r.ilsevent != 'undefined') {
                    g.error.standard_unexpected_error_alert('copy update',r);
                }
            }
            try {
                //case 1706 /* ITEM_BARCODE_EXISTS */ :
                if (copies && copies.length > 0 && $('print_labels').checked) {
                    JSAN.use('util.functional');
                    dont_close = true;
                    xulG.set_tab(
                        urls.XUL_SPINE_LABEL,
                        { 'tab_name' : $("catStrings").getString('staff.cat.util.spine_editor.tab_name') },
                        {
                            'barcodes' : util.functional.map_list( copies, function(o){return o.barcode();}) 
                        }
                    );
                }
            } catch(E) {
                g.error.standard_unexpected_error_alert($(catStrings).getString('staff.cat.volume_copy_creator.stash_and_close.tree_err2'),E);
            }
        }

        try { if (typeof window.refresh == 'function') { window.refresh(); } } catch(E) { dump(E+'\n'); }
        try { if (typeof g.refresh == 'function') { g.refresh(); } } catch(E) { dump(E+'\n'); }

        if (! dont_close) { xulG.close_tab(); }

    } catch(E) {
        g.error.standard_unexpected_error_alert($(catStrings).getString('staff.cat.volume_copy_creator.stash_and_close.tree_err3'),E);
    }
}

g.load_prefs = function() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
        JSAN.use('util.file'); var file = new util.file('volume_copy_creator.prefs');
        if (file._file.exists()) {
            var prefs = file.get_object(); file.close();
            if (prefs.check_barcodes) {
                if ( prefs.check_barcodes == 'false' ) {
                    $('check_barcodes').checked = false;
                } else {
                    $('check_barcodes').checked = prefs.check_barcodes;
                }
            } else {
                $('check_barcodes').checked = false;
            }
            if (prefs.print_labels) {
                if ( prefs.print_labels == 'false' ) {
                    $('print_labels').checked = false;
                } else {
                    $('print_labels').checked = prefs.print_labels;
                }
            } else {
                $('print_labels').checked = false;
            }

        }
    } catch(E) {
        g.error.standard_unexpected_error_alert($(catStrings).getString('staff.cat.volume_copy_creator.load_prefs.err_retrieving_prefs'),E);
        
    }
}

g.save_prefs = function () {
    try {
        netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
        JSAN.use('util.file'); var file = new util.file('volume_copy_creator.prefs');
        file.set_object(
            {
                'check_barcodes' : $('check_barcodes').checked,
                'print_labels' : $('print_labels').checked,
            }
        );
        file.close();
    } catch(E) {
        g.error.standard_unexpected_error_alert($(catStrings).getString('staff.cat.volume_copy_creator.save_prefs.err_storing_prefs'),E);
    }
}

g.list_callnumbers = function(doc_id, label_class) {
    var cn_blob;
    try {
        cn_blob = g.network.simple_request('BLOB_MARC_CALLNUMBERS_RETRIEVE',[g.doc_id, label_class]);
    } catch(E) {
        cn_blob = [];
    }
    var hbox = document.getElementById('marc_cn');
    var ml = util.widgets.make_menulist(
        util.functional.map_list(
            cn_blob,
            function(o) {
                for (var i in o) {
                    return [ o[i], i ];
                }
            }
        )
    ); hbox.appendChild(ml);
    ml.setAttribute('editable','true');
    ml.setAttribute('width', '200');
    var btn = document.createElement('button');
    btn.setAttribute('label',$('catStrings').getString('staff.cat.volume_copy_creator.my_init.btn.label'));
    btn.setAttribute('accesskey',$('catStrings').getString('staff.cat.volume_copy_creator.my_init.btn.accesskey'));
    btn.setAttribute('image','/xul/server/skin/media/images/down_arrow.gif');
    hbox.appendChild(btn);
    btn.addEventListener(
        'command',
        function() {
            var nl = document.getElementsByTagName('textbox');
            for (var i = 0; i < nl.length; i++) {
                if (nl[i].getAttribute('rel_vert_pos')==2 
                    && !nl[i].disabled) 
                {
                    nl[i].value = ml.value;
                    util.widgets.dispatch('change',nl[i]);
                }
            }
            if (g.last_focus) setTimeout( function() { g.last_focus.focus(); }, 0 );
        }, 
        false
    );
}
