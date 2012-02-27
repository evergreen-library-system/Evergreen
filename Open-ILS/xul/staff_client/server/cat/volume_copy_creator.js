const g_max_copies_that_can_be_added_at_a_time_per_volume = 999;
const rel_vert_pos_volume_count = 1;
const rel_vert_pos_call_number_classification = 2;
const rel_vert_pos_call_number_prefix = 3;
const rel_vert_pos_call_number = 4;
const rel_vert_pos_call_number_suffix = 5;
const rel_vert_pos_copy_count = 6;
const rel_vert_pos_barcode = 7;
const rel_vert_pos_part = 8;
const update_timer = 1000;
var g = {};
g.use_defaults = true;
g.acn_map = {}; // store retrieved acn objects here by id

function my_init() {
    try {

        /***********************************************************************************************************/
        /* Initial setup */

        if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for cat/volume_copy_creator.xul');

        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
        JSAN.use('util.widgets'); JSAN.use('util.functional'); JSAN.use('util.fm_utils');

        JSAN.use('util.network'); g.network = new util.network();

        g.refresh = xul_param('onrefresh');

        if (xulG.unified_interface) {
            $('non_unified_buttons').hidden = true;
            xulG.reset_batch_menus = function() {
                $('batch_class_menulist').value = false;
                util.widgets.dispatch('command',$('batch_class_menulist'));
                $('batch_prefix_menulist').value = false;
                util.widgets.dispatch('command',$('batch_prefix_menulist'));
                $('batch_suffix_menulist').value = false;
                util.widgets.dispatch('command',$('batch_suffix_menulist'));
            }
            xulG.apply_template_to_batch = function(id,value) {
                if (!isNaN(Number(value))) {
                    $(id).value = value;
                    util.widgets.dispatch('command',$(id));
                }
                setTimeout(
                    function() {
                        // TODO:  Only apply batch to columns that haven't been adjusted manually?
                        util.widgets.dispatch('command',$('batch_button'));
                    },0
                );
            }
            xulG.lock_save_button = function() {
                g.save_button_locked = true;
                document.getElementById("Create").disabled = true;
            }
            xulG.unlock_save_button = function() {
                g.save_button_locked = false;
                document.getElementById("Create").disabled = false;
            }
            xulG.clear_update_copy_editor_timeout = function() {
                if (g.update_copy_editor_timeoutID) {
                    clearTimeout(g.update_copy_editor_timeoutID);
                    g.gather_copies();
                }
            }
        } else {
            $('Create').hidden = true;
        }

        /***********************************************************************************************************/
        /* Am I adding just copies or copies and volumes?  Or am I rebarcoding existing copies? */

        // g.copy_shortcut = { ou_id : { callnumber_composite_key : callnumber_id, callnumber_label : callnumber_id, ... }, ... }
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
            set_attr('Create','label','staff.cat.volume_copy_creator.rebarcode.btn.label');
            set_attr('Create','accesskey','staff.cat.volume_copy_creator.rebarcode.btn.accesskey');
        } else {
            set_attr('EditThenCreate','label','staff.cat.volume_copy_creator.edit_then_create.btn.label');
            set_attr('EditThenCreate','accesskey','staff.cat.volume_copy_creator.edit_then_create.btn.accesskey');
            set_attr('CreateWithDefaults','label','staff.cat.volume_copy_creator.create_with_defaults.btn.label');
            set_attr('CreateWithDefaults','accesskey','staff.cat.volume_copy_creator.create_with_defaults.btn.accesskey');
            set_attr('Create','label','staff.cat.volume_copy_creator.create.btn.label');
            set_attr('Create','accesskey','staff.cat.volume_copy_creator.create.btn.accesskey');
        }

        //g.error.sdump('D_ERROR','location.href = ' + location.href + '\n\ncopy_short cut = ' + g.copy_shortcut + '\n\nou_ids = ' + xul_param('ou_ids'));

        var ou_ids = xul_param('ou_ids',{'concat' : true}) || [];

        // Get the default callnumber classification scheme from OU settings
        // or a reasonable fall-back
        function get_default_label_class() {
            g.label_class = g.data.hash.aous['cat.default_classification_scheme'];

            // Assign a default value if none was returned
            // Begin by looking for the "Generic" label class by name
            if (!g.label_class) {
                for (var i = 0; i < g.data.list.acnc.length; i++) {
                    if (g.data.list.acnc[i].name() == 'Generic') {
                        g.label_class = g.data.list.acnc[i].id();
                        break;
                    }
                }
            }
            // Maybe this database has renamed or removed their Generic
            // entry; in that case, just return the first one that we
            // know exists
            if (!g.label_class) {
                g.label_class = g.data.list.acnc[0].id();
            }
        }

        get_default_label_class();

        /***********************************************************************************************************/
        /* If we're passed existing_copies, rig up a copy_shortcut object to leverage existing code for rendering the volume labels, etc.
         * Also make a lookup object for existing copies keyed on org id and callnumber composite key, and another keyed on copy id. */

        // g.org_label_existing_copy_map = { ou_id : { callnumber_composite_key : [ copy1, copy2, ... ] }, ... }
        g.org_label_existing_copy_map = {};
        // g.id_copy_map = { acp_id : acp, ... }
        g.id_copy_map = {};
        for (var i = 0; i < g.existing_copies.length; i++) {
            if (! g.copy_shortcut) { g.copy_shortcut = {}; }
            var copy = g.existing_copies[i];
            g.id_copy_map[ copy.id() ] = copy;
            var call_number = copy.call_number();
            if (typeof call_number != 'object') {
                if (typeof g.acn_map[call_number] == 'undefined') {
                    var temp_acn = g.network.simple_request(
                        'FM_ACN_RETRIEVE.authoritative',
                        [ call_number ]
                    );
                    if (typeof temp_acn.ilsevent != 'undefined') {
                        alert('Error in my_init(), acn_id = ' + call_number + ' temp_acn = ' + js2JSON(temp_acn));
                        continue;
                    }
                    g.acn_map[ call_number ] = temp_acn;
                }
                call_number = g.acn_map[call_number];
            }
            g.doc_id = call_number.record();
            if (!g.copy_shortcut[ call_number.owning_lib() ]) {
                ou_ids.push( call_number.owning_lib() );
                g.copy_shortcut[ call_number.owning_lib() ] = {};
                g.org_label_existing_copy_map[ call_number.owning_lib() ] = {};
            }
            var acnc_id = call_number.label_class() ?
                ( typeof call_number.label_class() == 'object' ? call_number.label_class().id() : call_number.label_class() )
                : g.label_class;
            var acnp_id = typeof call_number.prefix() == 'object' ? call_number.prefix().id() : call_number.prefix();
            var acns_id = typeof call_number.suffix() == 'object' ? call_number.suffix().id() : call_number.suffix();
            var callnumber_composite_key = acnc_id + ':' + acnp_id + ':' + call_number.label() + ':' + acns_id;
            g.copy_shortcut[ call_number.owning_lib() ][ callnumber_composite_key ] = call_number.id();
            if (! g.org_label_existing_copy_map[ call_number.owning_lib() ][ callnumber_composite_key ]) {
                g.org_label_existing_copy_map[ call_number.owning_lib() ][ callnumber_composite_key ] = [];
            }
            g.org_label_existing_copy_map[ call_number.owning_lib() ][ callnumber_composite_key ].push( copy );
        }

        /***********************************************************************************************************/
        /* What record am I dealing with?  */

        g.doc_id = g.doc_id || xul_param('doc_id');
        if (! g.doc_id) {
            alert('Error in volume_copy_creator.js, g.doc_id not valid');
            window.close(); return;
        }

        var sb = document.getElementById('summary_box');
        if (xul_param('no_bib_summary')) {
            sb.hidden = true;
            sb.nextSibling.hidden = true; /* splitter */
        } else {
            while(sb.firstChild) sb.removeChild(sb.lastChild);
            var summary = document.createElement('iframe'); sb.appendChild(summary);
            summary.setAttribute('src',urls.XUL_BIB_BRIEF);
            summary.setAttribute('flex','1');
            get_contentWindow(summary).xulG = { 'docid' : g.doc_id };
        }

        /***********************************************************************************************************/
        /* Setup pcrud and fetch the monographic parts for this bib */

        dojo.require('openils.PermaCrud');
        g.pcrud = new openils.PermaCrud({'authtoken':ses()});
        g.parts = g.pcrud.search('bmp',{'record':g.doc_id},{'order_by': { 'bmp' : 'label_sortkey' } });
        g.parts_hash = util.functional.convert_object_list_to_hash( g.parts );

        /***********************************************************************************************************/
        /* For the batch drop downs */

        g.list_classes();
        JSAN.use('cat.util');
        cat.util.render_callnumbers_for_bib_menu('marc_cn',g.doc_id, g.label_class);
        g.render_batch_button();

        /***********************************************************************************************************/
        /* render the orgs and volumes/input */

        var rows = document.getElementById('rows');

        g.ou_ids = [];
        for (var i = 0; i < ou_ids.length; i++) {
            try {
                var org = g.data.hash.aou[ ou_ids[i] ];
                if ( get_bool( g.data.hash.aout[ org.ou_type() ].can_have_vols() ) ) {
                    var row = document.createElement('row'); rows.appendChild(row); row.setAttribute('ou_id',ou_ids[i]);
                    g.render_library_label(row,ou_ids[i]);
                    g.render_volume_count_entry( row, ou_ids[i] );
                    g.ou_ids.push( ou_ids[i] );
                }
            } catch(E) {
                g.error.sdump('D_ERROR',E);
            }
        }
        g.common_ancestor_ou_ids = util.fm_utils.find_common_aou_ancestors( g.ou_ids ).reverse();

        /***********************************************************************************************************/
        /* For the remainder batch drop downs */

        g.list_prefixes();
        g.list_suffixes();

        /************/

        g.load_prefs();

        if (g.existing_copies.length > 0) {
            g.gather_copies_soon(true);
        }

        try {
            $('main').parentNode.scrollLeft = 9999;
        } catch(E) {
            dump('Error in volume_copy_creator.js, my_init(), trying to auto-scroll to the far right: ' + E + '\n');
        }

        if (typeof xulG.volume_ui_callback_for_unified_interface == 'function') {
            xulG.volume_ui_callback_for_unified_interface();
        }

    } catch(E) {
        var err_msg = $("commonStrings").getFormattedString('common.exception', ['cat/volume_copy_creator.js', E]);
        try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); dump(js2JSON(E)); }
        alert(err_msg);
    }
}

g.render_library_label = function(row,ou_id) {
    dump('g.render_library_label(row='+row+',ou_id='+ou_id+')\n');
    var label = document.createElement('label'); row.appendChild(label);
    label.setAttribute('ou_id',ou_id);
    label.setAttribute('value',g.data.hash.aou[ ou_id ].shortname());
}

g.render_volume_count_entry = function(row,ou_id) {
    dump('g.render_volume_count_entry(row='+row+',ou_id='+ou_id+')\n');
    var hb = document.createElement('vbox'); row.appendChild(hb);
    var tb = document.createElement('textbox'); hb.appendChild(tb);
    if (g.use_defaults) {
        tb.value = 1; // default to 1 volume per org
        tb.select();
    }
    tb.setAttribute('ou_id',ou_id); tb.setAttribute('size','3'); tb.setAttribute('cols','3');
    tb.setAttribute('rel_vert_pos',rel_vert_pos_volume_count);
    if ( (!g.copy_shortcut) && (!g.last_focus) ) { tb.focus(); g.last_focus = tb; }
    var node;
    function render_copy_count_entry(ev) {
        dump('\t\trender_copy_count_entry()\n');
        if (ev.target.disabled) return;
        if (! isNaN( Number( ev.target.value) ) ) {
            if ( Number( ev.target.value ) > g_max_copies_that_can_be_added_at_a_time_per_volume ) {
                g.error.yns_alert($("catStrings").getFormattedString('staff.cat.volume_copy_creator.render_volume_count_entry.message', [g_max_copies_that_can_be_added_at_a_time_per_volume]),
                    $("catStrings").getString('staff.cat.volume_copy_creator.render_volume_count_entry.title'),
                    $("catStrings").getString('staff.cat.volume_copy_creator.render_volume_count_entry.ok_label'),null,null,'');
                return;
            }
            if (node) { row.removeChild(node); node = null; }
            node = g.render_callnumber_copy_count_entry(row,ou_id,ev.target.value);
        }
    }
    util.widgets.apply_vertical_tab_on_enter_handler(
        tb,
        function() { render_copy_count_entry({'target':tb}); setTimeout(function(){util.widgets.vertical_tab(tb);},0); }
        ,function() { g.delay_gather_copies_soon(false); }
    );
    tb.addEventListener( 'change', render_copy_count_entry, false);
    //tb.addEventListener( 'change', g.gather_copies_soon, false);
    tb.addEventListener( 'focus', function(ev) { g.last_focus = ev.target; }, false );
    setTimeout(
        function() {
            try {
                if (g.copy_shortcut) {
                    dump('\t\tg.render_volume_count_entry, using g.copy_shortcut\n');
                    JSAN.use('util.functional');
                    tb.value = util.functional.map_object_to_list(
                        g.copy_shortcut[ou_id],
                        function(o,i) {
                            return g.copy_shortcut[ou_id][i];
                        }
                    ).length;
                    dump('\t\tnumber of volumes = ' + tb.value + '\n');
                    render_copy_count_entry({'target':tb});
                    tb.disabled = true;
                } else if (tb.value) {
                    dump('\t\tg.render_volume_count_entry, number of volumes = ' + tb.value + '\n');
                    // since we're now supplying a default
                    render_copy_count_entry({'target':tb});
                    setTimeout(
                        function() {
                            util.widgets.vertical_tab(tb);
                        }, 0
                    );
                }
            } catch(E) {
                alert(E);
            }
        }, 0
    );
}

g.render_callnumber_copy_count_entry = function(row,ou_id,count) {
    dump('g.render_call_number_copy_count_entry(row='+row+',ou_id='+ou_id+',count='+count+')\n');
    var grid = util.widgets.make_grid( [ {}, {} ] ); row.appendChild(grid);
    grid.setAttribute('flex','1');
    grid.setAttribute('ou_id',ou_id);
    var rows = grid.lastChild;
    var r = document.createElement('row'); rows.appendChild( r );
    var x = document.createElement('label'); r.appendChild(x);
        x.setAttribute('value', $("catStrings").getString('staff.cat.volume_copy_creator.render_callnumber_copy_count_entry.classification'));
        x.setAttribute('style','font-weight: bold');
        x.setAttribute('class','cn_class');
    x = document.createElement('label'); r.appendChild(x);
        x.setAttribute('value', $("catStrings").getString('staff.cat.volume_copy_creator.render_callnumber_copy_count_entry.prefix'));
        x.setAttribute('style','font-weight: bold');
        x.setAttribute('class','cn_prefix');
    x = document.createElement('label'); r.appendChild(x);
        x.setAttribute('value', $("catStrings").getString('staff.cat.volume_copy_creator.render_callnumber_copy_count_entry.call_nums'));
        x.setAttribute('style','font-weight: bold');
    x = document.createElement('label'); r.appendChild(x);
        x.setAttribute('value', $("catStrings").getString('staff.cat.volume_copy_creator.render_callnumber_copy_count_entry.suffix'));
        x.setAttribute('style','font-weight: bold');
        x.setAttribute('class','cn_suffix');
    x = document.createElement('label'); r.appendChild(x);
        x.setAttribute('value',$("catStrings").getString('staff.cat.volume_copy_creator.render_callnumber_copy_count_entry.num_of_copies'));
        x.setAttribute('style','font-weight: bold');
    x = document.createElement('label'); r.appendChild(x);
        x.setAttribute('value',$("catStrings").getString('staff.cat.volume_copy_creator.render_callnumber_copy_count_entry.barcodes_and_parts'));
        x.setAttribute('style','font-weight: bold');

    function handle_change_precipitating_barcode_rendering(
        callnumber_composite_key,
        number_of_copies_column_textbox,
        barcode_column_box
    ) {
        dump('handle_change_precipitating_barcode_rendering('+callnumber_composite_key+',number_of_copies = '+number_of_copies_column_textbox.value+','+ barcode_column_box + ')\n');

        if (isNaN( Number( number_of_copies_column_textbox.value ) )) {
            dump('1:handle_change_precipitating_barcode_rendering early return\n');
            return;
        }
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
            callnumber_composite_key,
            Number(number_of_copies_column_textbox.value),
            ou_id
        );

        if (! xulG.unified_interface) {
            document.getElementById("EditThenCreate").disabled = false;
            document.getElementById("CreateWithDefaults").disabled = false;
        } else {
            if (! g.save_button_locked) {
                document.getElementById("Create").disabled = false;
            }
        }
    }

    function handle_change_to_callnumber_data(ev) {
        dump('handle_change_to_callnumber_data\n');
        var _call_number_column_textbox = ev.target;
        var _call_number_column_box = _call_number_column_textbox.parentNode;

        var _classification_column_box = _call_number_column_box.previousSibling.previousSibling; /* two over to the left */
        var _classification_column_menulist = _classification_column_box.firstChild;

        var _prefix_column_box = _call_number_column_box.previousSibling; /* one over to the left */
        var _prefix_column_menulist = _prefix_column_box.firstChild;

        var _suffix_column_box = _call_number_column_box.nextSibling; /* one over to the right */
        var _suffix_column_menulist = _suffix_column_box.firstChild;

        var _number_of_copies_column_box = _call_number_column_box.nextSibling.nextSibling; /* two over to the right */
        var _number_of_copies_column_textbox = _number_of_copies_column_box.firstChild;

        var _barcode_column_box = _number_of_copies_column_box.nextSibling;

        var acn_label = _call_number_column_textbox.value;
        var acnc_id = _classification_column_menulist.value;
        var acnp_id = _prefix_column_menulist.value;
        var acns_id = _suffix_column_menulist.value;
        var callnumber_composite_key = acnc_id + ':' + acnp_id + ':' + acn_label + ':' + acns_id;
        dump('\tcomposite_key = ' + callnumber_composite_key + '\n');

        _call_number_column_textbox.setAttribute('callkey',callnumber_composite_key);
        //_call_number_column_textbox.setAttribute('tooltiptext',callnumber_composite_key);
        _call_number_column_textbox.setAttribute('acnc_id',acnc_id);
        _call_number_column_textbox.setAttribute('acnp_id',acnp_id);
        _call_number_column_textbox.setAttribute('acns_id',acns_id);

        handle_change_precipitating_barcode_rendering(
            callnumber_composite_key,
            _number_of_copies_column_textbox,
            _barcode_column_box
        );
    }

    function handle_change_number_of_copies_column_textbox(ev) {
        dump('handle_change_number_of_copies_column_textbox\n');
        var _number_of_copies_column_textbox = ev.target;
        var _number_of_copies_column_box = _number_of_copies_column_textbox.parentNode;
        var _call_number_column_box = _number_of_copies_column_box.previousSibling.previousSibling; /* two over */
        var _call_number_column_textbox = _call_number_column_box.firstChild;
        handle_change_to_callnumber_data({'target':_call_number_column_textbox}); // let this guy do the work
    }

    for (var i = 0; i < count; i++) {
        var r = document.createElement('row'); rows.appendChild(r);

            /**** CLASSIFICATION COLUMN ****/
            var classification_column_box = document.createElement('vbox');
            classification_column_box.setAttribute('class','cn_class');
            r.appendChild(classification_column_box);
            classification_column_box.width = $('batch_class').parentNode.boxObject.width;

            /**** PREFIX COLUMN ****/
            var prefix_column_box = document.createElement('vbox');
            prefix_column_box.setAttribute('class','cn_prefix');
            r.appendChild(prefix_column_box);
            prefix_column_box.width = $('batch_prefix').parentNode.boxObject.width;

            /**** CALLNUMBER COLUMN ****/
            var call_number_column_box = document.createElement('vbox');
            r.appendChild(call_number_column_box);
            call_number_column_box.width = $('marc_cn').parentNode.boxObject.width;
                var call_number_column_textbox = document.createElement('textbox');
                call_number_column_box.appendChild(call_number_column_textbox);
                    if (g.use_defaults && $('marc_cn').firstChild) {
                        // default to first real value from batch callnumber menu
                        var menupopup = $('marc_cn').firstChild.firstChild;
                        if (menupopup.childNodes.length > 1) {
                            call_number_column_textbox.value = menupopup.childNodes[1].getAttribute('label');
                            call_number_column_textbox.select();
                        }
                    }
                    call_number_column_textbox.setAttribute('rel_vert_pos',rel_vert_pos_call_number);
                    call_number_column_textbox.setAttribute('ou_id',ou_id);
                    util.widgets.apply_vertical_tab_on_enter_handler(
                        call_number_column_textbox,
                        function() {
                            handle_change_to_callnumber_data({'target':call_number_column_textbox});
                            setTimeout(
                                function(){
                                    util.widgets.vertical_tab(call_number_column_textbox);
                                },0
                            );
                        }
                        ,function() { g.delay_gather_copies_soon(false); }
                    );
                    call_number_column_textbox.addEventListener( 'change', handle_change_to_callnumber_data, false);
                    //call_number_column_textbox.addEventListener( 'change', g.gather_copies_soon, false);
                    call_number_column_textbox.addEventListener( 'focus', function(ev) { g.last_focus = ev.target; }, false );

                    /**** CLASSIFICATION COLUMN revisited ****/
                    var classification_column_menulist = g.render_class_menu(
                        call_number_column_textbox,
                        handle_change_to_callnumber_data
                    );
                    classification_column_box.appendChild(classification_column_menulist);
                    classification_column_menulist.value = g.label_class;

                    /**** PREFIX COLUMN revisited ****/
                    var prefix_column_menulist = g.render_prefix_menu(
                        call_number_column_textbox,
                        handle_change_to_callnumber_data
                    );

                    prefix_column_box.appendChild(prefix_column_menulist);

            /**** SUFFIX COLUMN ****/
            var suffix_column_box = document.createElement('vbox');
            suffix_column_box.setAttribute('class','cn_suffix');
            r.appendChild(suffix_column_box);
            suffix_column_box.width = $('batch_suffix').parentNode.boxObject.width;
                var suffix_column_menulist = g.render_suffix_menu(
                    call_number_column_textbox,
                    handle_change_to_callnumber_data
                );
                suffix_column_box.appendChild(suffix_column_menulist);

            /**** NUMBER OF COPIES COLUMN ****/
            var number_of_copies_column_box = document.createElement('vbox');
            r.appendChild(number_of_copies_column_box);
                var number_of_copies_column_textbox = document.createElement('textbox');
                number_of_copies_column_box.appendChild(number_of_copies_column_textbox);
                    if (g.use_defaults) {
                        // default to one copy per call number
                        number_of_copies_column_textbox.value = 1;
                        number_of_copies_column_textbox.select();
                    }
                    number_of_copies_column_textbox.setAttribute('size','3'); number_of_copies_column_textbox.setAttribute('cols','3');
                    number_of_copies_column_textbox.setAttribute('rel_vert_pos',rel_vert_pos_copy_count);
                    number_of_copies_column_textbox.setAttribute('ou_id',ou_id);
                    util.widgets.apply_vertical_tab_on_enter_handler(
                        number_of_copies_column_textbox,
                        function() {
                            handle_change_number_of_copies_column_textbox({'target':number_of_copies_column_textbox});
                            setTimeout(
                                function(){
                                    util.widgets.vertical_tab(number_of_copies_column_textbox);
                                },0
                            );
                        }
                        ,function() { g.delay_gather_copies_soon(false); }
                    );
                    number_of_copies_column_textbox.addEventListener( 'change', handle_change_number_of_copies_column_textbox, false);
                    //number_of_copies_column_textbox.addEventListener( 'change', g.gather_copies_soon, false);
                    number_of_copies_column_textbox.addEventListener( 'focus', function(ev) { g.last_focus = ev.target; }, false );
                    if ( !g.last_focus ) { number_of_copies_column_textbox.focus(); g.last_focus = number_of_copies_column_textbox; }

            /**** BARCODE COLUMN ****/
            var barcode_column_box = document.createElement('vbox');
            r.appendChild(barcode_column_box);

        setTimeout(
            function(idx,call_number_column_textbox,number_of_copies_column_textbox){
                return function() {
                    try {
                        JSAN.use('util.functional');
                        if (g.copy_shortcut) {
                            dump('\t\tg.render_call_number_copy_count_entry() using g.copy_shortcut\n');
                            var callnumber_composite_key = util.functional.map_object_to_list(
                                g.copy_shortcut[ou_id],
                                function(o,i) {
                                    return i;
                                }
                            )[idx];
                            dump('\tcallnumber_composite_key = ' + callnumber_composite_key + '\n');
                            if (g.org_label_existing_copy_map[ou_id]) {
                                var num_of_copies = g.org_label_existing_copy_map[ou_id][callnumber_composite_key].length;
                                if (num_of_copies>0) {
                                    number_of_copies_column_textbox.value = num_of_copies;
                                    number_of_copies_column_textbox.disabled = true;
                                }
                            }
                            var acn_label = callnumber_composite_key.split(/:/).slice(2,-1).join(':');
                            var acnc_id = callnumber_composite_key.split(/:/)[0];
                            var acnp_id = callnumber_composite_key.split(/:/)[1];
                            var acns_id = callnumber_composite_key.split(/:/).slice(-1)[0];
                            call_number_column_textbox.value = acn_label;

                            var _call_number_column_box = call_number_column_textbox.parentNode;

                            var _classification_column_box =
                                _call_number_column_box.previousSibling.previousSibling; /* two over to the left */
                            var _classification_column_menulist =
                                _classification_column_box.firstChild;
                            var _prefix_column_box =
                                _call_number_column_box.previousSibling; /* one over to the left */
                            var _prefix_column_menulist =
                                _prefix_column_box.firstChild;
                            var _suffix_column_box =
                                _call_number_column_box.nextSibling; /* one over to the right */
                            var _suffix_column_menulist =
                                _suffix_column_box.firstChild;

                            _classification_column_menulist.value = acnc_id;
                            _prefix_column_menulist.value = acnp_id;
                            _suffix_column_menulist.value = acns_id;
                            dump('\tacn_label = ' + acn_label + ' acnc_id = ' + acnc_id + ' acnp_id = ' + acnp_id + ' acns_id = ' + acns_id + '\n');
                            handle_change_to_callnumber_data({'target':call_number_column_textbox});
                        } else {
                            dump('\t\tg.render_call_number_copy_count_entry() using defaults\n');

                            // if we're providing defaults, keep on rendering
                            if (call_number_column_textbox.value) {
                                util.widgets.dispatch('change',call_number_column_textbox);
                            }
                            if (number_of_copies_column_textbox.value) {
                                util.widgets.dispatch('change',number_of_copies_column_textbox);
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

g.render_part_menu = function(barcode_tb) {
    var hbox = document.createElement('hbox');
    var menulist = document.createElement('menulist');
        menulist.setAttribute('editable','true');
        hbox.appendChild(menulist);
    var button = document.createElement('button');
        button.setAttribute('label',$('catStrings').getString('staff.cat.volume_copy_creator.create_part.btn.label'));
        button.hidden = true;
        hbox.appendChild(button);

    var menupopup = document.createElement('menupopup');
        menulist.appendChild(menupopup);
        g.render_part_menuitems(menupopup);

    button.addEventListener(
        'command',
        function(ev) {
            var new_part = new bmp();
                new_part.isnew(1);
                new_part.label(menulist.value);
                new_part.record(g.doc_id);
            g.pcrud.create(new_part, {
                "oncomplete": function (r, objs) {
                    var db_part = objs[0];
                    if (!db_part) { return; }
                    g.parts.push( db_part );
                    g.parts_hash[ db_part.id() ] = db_part;
                    g.render_part_menuitems(menupopup);
                    if (menulist.selectedItem) {
                        barcode_tb.setAttribute('bmp_id',menulist.selectedItem.value);
                        button.hidden = true;
                    }
                    g.gather_copies_soon(true);
                }
            });
        },
        false
    );

    menulist.addEventListener(
        'change',
        function(ev) {
            if (! ev.target.selectedItem) {
                button.hidden = false;
            }
        },
        false
    );
    menulist.addEventListener('change',function() { g.gather_copies_soon(true); },false);
    menulist.addEventListener(
        'command',
        function(ev) {
            barcode_tb.setAttribute('bmp_id',menulist.selectedItem.value);
            button.hidden = true;
        },
        false
    );
    menulist.addEventListener('command',function() { g.gather_copies_soon(true); },false);

    return hbox;
}

g.render_part_menuitems = function(menupopup) {
    util.widgets.remove_children(menupopup);
    var menuitem = document.createElement('menuitem');
    menuitem.setAttribute('label','');
    menuitem.setAttribute('value','');
    menupopup.appendChild(menuitem);
    for (var i = 0; i < g.parts.length; i++) {
        var menuitem = document.createElement('menuitem');
        menuitem.setAttribute('label',g.parts[i].label());
        menuitem.setAttribute('value',g.parts[i].id());
        menupopup.appendChild(menuitem);
    }

}

g.render_barcode_entry = function(node,callnumber_composite_key,count,ou_id) {
    try {
        dump('g.render_barcode_entry(node,'+callnumber_composite_key+',count='+count+',ou_id='+ou_id+'\n');
        function ready_to_create(ev) {
            if (! xulG.unified_interface) {
                document.getElementById("EditThenCreate").disabled = false;
                document.getElementById("CreateWithDefaults").disabled = false;
            } else {
                if (! g.save_button_locked) {
                    document.getElementById("Create").disabled = false;
                }
            }
        }

        JSAN.use('util.barcode');

        for (var i = 0; i < count; i++) {
            var tb_part_box;
            var tb;
            var part_menu;
            var set_handlers = false;
            if (typeof node.childNodes[i] == 'undefined') {
                tb_part_box = document.createElement('hbox');
                node.appendChild(tb_part_box);
                tb = document.createElement('textbox');
                tb_part_box.appendChild(tb);
                part_menu = g.render_part_menu(tb);
                part_menu.setAttribute('class','part_column');
                tb_part_box.appendChild(part_menu);
                set_handlers = true;
            } else {
                tb_part_box = node.childNodes[i];
                tb = tb_part_box.firstChild;
                part_menu = tb_part_box.lastChild;
            }
            tb.setAttribute('ou_id',ou_id);
            tb.setAttribute('callkey',callnumber_composite_key);
            //tb.setAttribute('tooltiptext',callnumber_composite_key);
            tb.setAttribute('rel_vert_pos',rel_vert_pos_barcode);
            part_menu.firstChild.setAttribute('rel_vert_pos',rel_vert_pos_part);
            if (!tb.value && g.org_label_existing_copy_map[ ou_id ]) {
                tb.value = g.org_label_existing_copy_map[ ou_id ][ callnumber_composite_key ][i].barcode();
                tb.setAttribute('acp_id', g.org_label_existing_copy_map[ ou_id ][ callnumber_composite_key ][i].id());
                var temp_parts = g.org_label_existing_copy_map[ ou_id ][ callnumber_composite_key ][i].parts();
                temp_parts = util.functional.filter_list(
                    temp_parts || [],
                    function(p) {
                        return p.record() == g.doc_id; // filter out foreign parts
                    }
                );
                if (temp_parts.length > 0) {
                    tb.setAttribute('bmp_id',temp_parts[0].id());
                    part_menu.firstChild.value = g.parts_hash[ temp_parts[0].id() ].label();
                }
                tb.select();
                if (! g.first_focus) { g.first_focus = tb; }
            }
            if (g.use_defaults && ! g.first_focus) {
                g.first_focus = tb;
                tb.focus();
            }
            if (set_handlers) {
                util.widgets.apply_vertical_tab_on_enter_handler(
                    tb,
                    function() { ready_to_create({'target':tb}); setTimeout(function(){util.widgets.vertical_tab(tb);},0); },
                    function() { g.delay_gather_copies_soon(true); }
                );
                util.widgets.apply_vertical_tab_on_enter_handler(
                    part_menu.firstChild,
                    function() { setTimeout(function(){util.widgets.vertical_tab(part_menu.firstChild);},0); },
                    function() { g.delay_gather_copies_soon(true); }
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
                //tb.addEventListener('change', g.gather_copies_soon, false);
                tb.addEventListener( 'focus', function(ev) { g.last_focus = ev.target; }, false );
            }
        }

        g.gather_copies_soon(true);
        setTimeout( function() { if (g.first_focus) { g.first_focus.focus(); } }, 0 );

    } catch(E) {
        g.error.sdump('D_ERROR','g.render_barcode_entry: ' + E);
    }
}

g.generate_barcodes = function() {
    try {
        var nodes = document.getElementsByAttribute('rel_vert_pos',rel_vert_pos_barcode);
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
            util.widgets.dispatch('change',nodes[i+1]);
        }

        setTimeout(
            function() {
                g.gather_copies_soon(true);
            },0
        );

    } catch(E) {
        g.error.sdump('D_ERROR','g.generate_barcodes: ' + E);
    }
}

g.delay_gather_copies_soon = function(enable_copy_editor) {
    if (xulG.unified_interface) {
        dump('g.delay_gather_copies_soon()\n');
        g.gather_copies_soon(enable_copy_editor);
    }
}

g.gather_copies_soon = function(enable_copy_editor) {
    try {
        if (!xulG.unified_interface) { return; }
        dump('g.gather_copies_soon()\n');
        if (typeof xulG.disable_copy_editor == 'function') {
            xulG.disable_copy_editor();
        }
        if (g.update_copy_editor_timeoutID) {
            clearTimeout(g.update_copy_editor_timeoutID);
        }
        // This function is expensive when it comes to keeping the UI responsive, so let's give it a delay
        // that quick entry of consecutive fields can override
        g.update_copy_editor_timeoutID = setTimeout(
            function() {
                try {
                    g.gather_copies();
                    if (enable_copy_editor) {
                        xulG.enable_copy_editor();
                    }
                    xulG.refresh_copy_editor();
                } catch(E) {
                    dump('Error in volume_copy_editor.js with g.gather_copies_soon setTimeout func(): ' + E + '\n');
                }
            }, update_timer
        );
    } catch(E) {
        alert('Error in volume_copy_creator.js, g.gather_copies_soon(): ' + E);
    }
}

g.new_acp_id = -1;
g.new_acn_id = -1;

g.gather_copies = function() {
    dump('g.gather_copies()\n');
    try {
        var nl = document.getElementsByTagName('textbox');

        g.volumes_scaffold = {};
        /*
            g.volumes_scaffold = {
                '#ou_id' : {
                    '#class_id:#prefix_id:#callnumber label:#suffix_id' : {
                        'callnumber_data' : {
                            'acn_id' : '#callnumber id',
                            'acn_label' : '#callnumber label',
                            'acnc_id' : '#classification_id',
                            'acnp_id' : '#prefix_id',
                            'acns_id' : '#suffix_id'
                        },
                        'barcode_data' :
                            [
                                {
                                    'barcode' : '#barcode',
                                    'acp_id' : '#copy_id',
                                    'bmp_id' : '#part_id'
                                }, ...
                            ]
                    }
                }, ...
            }
        */

        var barcodes = [];
        var v_count = 0;
        for (var i = 0; i < nl.length; i++) {
            if ( nl[i].getAttribute('rel_vert_pos') == rel_vert_pos_barcode ) barcodes.push( nl[i] );
            if ( nl[i].getAttribute('rel_vert_pos') == rel_vert_pos_call_number )  {
                v_count++;
                var ou_id = nl[i].getAttribute('ou_id');
                var acn_id = nl[i].getAttribute('acn_id');
                if (!acn_id) {
                    acn_id = g.new_acn_id--;
                    nl[i].setAttribute('acn_id',acn_id);
                }
                var acnc_id = nl[i].getAttribute('acnc_id') || g.label_class;
                var acnp_id = nl[i].getAttribute('acnp_id') || -1;
                var acns_id = nl[i].getAttribute('acns_id') || -1;
                var callnumber = nl[i].value;
                if (typeof g.volumes_scaffold[ou_id] == 'undefined') {
                    g.volumes_scaffold[ou_id] = {}
                }
                var composite_key = acnc_id + ':' + acnp_id + ':' + callnumber + ':' + acns_id;
                if (typeof g.volumes_scaffold[ou_id][composite_key] == 'undefined') {
                    g.volumes_scaffold[ou_id][composite_key] = {
                        //'node' : nl[i],
                        'callnumber_data' : {
                            'acn_id' : acn_id,
                            'acn_label' : callnumber,
                            'acnc_id' : acnc_id,
                            'acnp_id' : acnp_id,
                            'acns_id' : acns_id
                        },
                        'barcode_data' : []
                    }
                    dump('fleshing volumes scaffold with ou_id = ' + ou_id + ' composite_key = ' + composite_key + ' acn_id = ' + acn_id + '\n');
                }
            }
        };
        dump('volume_copy_creator: processed ' + nl.length + ' textbox nodes, consisting of ' + barcodes.length + ' barcodes and ' + v_count + 'volumes\n');
        dump('volume scaffold = ' + js2JSON(g.volumes_scaffold) + '\n');

        for (var i = 0; i < barcodes.length; i++) {
            var acp_id = barcodes[i].getAttribute('acp_id') || g.new_acp_id--;
            if (acp_id < 0) {
                barcodes[i].setAttribute('acp_id',acp_id);
            }
            var ou_id = barcodes[i].getAttribute('ou_id');
            var callnumber_composite_key = barcodes[i].getAttribute('callkey');
            var barcode = barcodes[i].value;
            var bmp_id = barcodes[i].getAttribute('bmp_id');

            dump('placing ' + barcode + ' for ou = ' + ou_id + ' into composite_key bin ' + callnumber_composite_key + '\n');

            if (typeof g.volumes_scaffold[ou_id] == 'undefined') {
                dump('1: I want to remove this soon, so alert me if it is getting used, ou_id = ' + ou_id + '\n');
                g.volumes_scaffold[ou_id] = {}
            }
            if (typeof g.volumes_scaffold[ou_id][callnumber_composite_key] == 'undefined') {
                dump('2: when does this happen, and why? ou_id = ' + ou_id + ' callnumber_composite_key = ' + callnumber_composite_key + '\n');
                // one way this can happen, race condition between this function and editing a widget
                g.volumes_scaffold[ou_id][callnumber_composite_key] = {
                    'callnumber_data' : {
                        // not ideal, but hey...
                        'acn_label' : callnumber_composite_key.split(/:/).slice(2,-1).join(':'),
                        'acnc_id' : callnumber_composite_key.split(/:/)[0],
                        'acnp_id' : callnumber_composite_key.split(/:/)[1],
                        'acns_id' : callnumber_composite_key.split(/:/).slice(-1)[0]
                    },
                    'barcode_data' : []
                }
            }

            if (barcode != '') {
                g.volumes_scaffold[ou_id][callnumber_composite_key].barcode_data.push(
                    {
                        'barcode' : barcode,
                        'acp_id' : acp_id,
                        'bmp_id' : bmp_id
                    }
                );
            }
        }

        var volumes = [];
        var copies = [];
        var volume_data = {};

        // Get the default copy status; default to "In Process" if unset, per 1.6
        var normal_ccs = g.data.hash.aous['cat.default_copy_status_normal'] || 5;

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
            copy.status(normal_ccs);
            copy.circulate(get_db_true());
            copy.holdable(get_db_true());
            copy.opac_visible(get_db_true());
            copy.ref(get_db_false());
            copy.mint_condition(get_db_true());
            return copy;
        }

        for (var ou_id in g.volumes_scaffold) {
            for (var composite_key in g.volumes_scaffold[ou_id]) {
                for (var i = 0; i < g.volumes_scaffold[ou_id][composite_key].barcode_data.length; i++) {
                    var barcode = g.volumes_scaffold[ou_id][composite_key].barcode_data[i].barcode;
                    var acp_id = g.volumes_scaffold[ou_id][composite_key].barcode_data[i].acp_id;
                    var bmp_id = g.volumes_scaffold[ou_id][composite_key].barcode_data[i].bmp_id;
                    var acn_id = g.volumes_scaffold[ou_id][composite_key].callnumber_data.acn_id;
                    dump('gather_copies(): barcode = ' + barcode + ' acp_id = ' + acp_id + ' bmp_id = ' + bmp_id + ' acn_id = ' + acn_id + ' composite_key = ' + composite_key + '\n');
                    var copy = g.id_copy_map[ acp_id ];
                    if (!copy) {
                        copy = new_copy(acp_id,ou_id,acn_id,barcode);
                        g.id_copy_map[ acp_id ] = copy;
                    } else {
                        copy.ischanged( get_db_true() );
                    }
                    copy.barcode( barcode );
                    copy.call_number( acn_id );
                    var temp_parts = util.functional.filter_list(
                        copy.parts() || [],
                        function(p) {
                            return (p.record() != g.doc_id); // filter out parts for this bib
                        }
                    );
                    if (bmp_id) {
                        temp_parts.push( g.parts_hash[ bmp_id ] );
                    }
                    copy.parts( temp_parts );
                    copies.push( copy );
                }
            }
        }

        xulG.copies = copies;
        return copies;

    } catch(E) {
        alert('Error in volume_copy_creator.js, g.gather_copies():' + E);
    }
}

g.vivicate_update_volumes = function() {
    try {
        var volumes = [];
        for (var ou_id in g.volumes_scaffold) {
            for (var composite_key in g.volumes_scaffold[ou_id]) {

                var callnumber_data = g.volumes_scaffold[ou_id][composite_key].callnumber_data;
                var acn_id = callnumber_data.acn_id;
                var acnp_id = callnumber_data.acnp_id;
                var acns_id = callnumber_data.acns_id;
                var acnc_id = callnumber_data.acnc_id;

                if (acn_id < 0) {

                    var acn_blob = g.network.simple_request(
                        'FM_ACN_FIND_OR_CREATE',
                        [ ses(), callnumber_data.acn_label, g.doc_id, ou_id, acnp_id, acns_id, acnc_id ]
                    );
                    dump('FM_ACN_FIND_OR_CREATE: label = ' + callnumber_data.acn_label
                        + ' doc = ' + g.doc_id + ' ou = ' + ou_id + ' acnp = ' + acnp_id + ' acns = ' + acns_id + ' acnc = ' + acnc_id + '\n');

                    if (typeof acn_blob.ilsevent != 'undefined') {
                        alert('Error in g.vivicate_update_volumes, acn_id = ' + acn_id + ' acn_blob = ' + js2JSON(acn_blob));
                        continue;
                    }

                    acn_id = acn_blob.acn_id;

                    if (typeof g.acn_map[ acn_id ] == 'undefined') {
                        var temp_acn = g.network.simple_request(
                            'FM_ACN_RETRIEVE.authoritative',
                            [ acn_id ]
                        );
                        if (typeof temp_acn.ilsevent != 'undefined') {
                            alert('Error in g.vivicate_update_volumes, acn_id = ' + acn_id + ' temp_acn = ' + js2JSON(temp_acn));
                            continue;
                        }
                        g.acn_map[ acn_id ] = temp_acn;
                    }

                    if (typeof g.acn_map[ callnumber_data.acn_id ] == 'undefined') {
                        g.acn_map[ callnumber_data.acn_id ] = g.acn_map[ acn_id ];
                    }

                }
            }
        }
        if (volumes.length > 0) {
            if (typeof xul_param('update_volume') == 'function') {
                xul_param('update_volume')(volumes);
            } else {
                 var r = g.network.simple_request(
                    'FM_ACN_TREE_UPDATE',
                    [ ses(),volumes, false, { 'auto_merge_vols' : false } ]
                );
                if (typeof r.ilsevent != 'undefined') {
                    alert('error with volume update: ' + js2JSON(r));
                }
            }
        }
    } catch(E) {
        alert('Error in volume_copy_creator.js, vivicate_volumes(): ' + E);
    }
}

g.stash_and_close = function(param) {

    try {

        if (g.update_copy_editor_timeoutID) {
            clearTimeout(g.update_copy_editor_timeoutID);
        }

        var copies;
        if (xulG.unified_interface) {
            g.gather_copies();
            xulG.refresh_copy_editor();
            copies = xulG.copies;
        } else {
            copies = g.gather_copies();
        }

        var dont_close = false;

        g.vivicate_update_volumes();
        for (var i = 0; i < copies.length; i++) {
            var acn_id = copies[i].call_number();
            if (typeof g.acn_map[acn_id] != 'undefined') {
                // handle vivicated-callnumbers
                copies[i].call_number( g.acn_map[acn_id].id() );
            } else {
                alert('error in stash and close, acn_id = ' + acn_id);
            }
        }

        var label_editor_func;
        if (copies.length > 0) {
            if (param == 'edit') {
                JSAN.use('cat.util');
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
                    alert('error with copy update:' + js2JSON(r));
                }
            }
            try {
                //case 1706 /* ITEM_BARCODE_EXISTS */ :
                if (copies && copies.length > 0 && $('print_labels').checked) {
                    dont_close = true;
                    var tab_name = $("catStrings").getString('staff.cat.util.spine_editor.tab_name');
                    var tab_method = xul_param('labels_in_new_tab') ? 'new_tab' : 'set_tab';
                    label_editor_func = function() {
                        JSAN.use('util.functional');
                        xulG[tab_method](
                            urls.XUL_SPINE_LABEL,
                            { 'tab_name' : tab_name },
                            {
                                'barcodes' : util.functional.map_list( copies, function(o){return o.barcode();})
                            }
                        );
                    };
                }
            } catch(E) {
                alert('2: Error in volume_copy_creator.js with g.stash_and_close(): ' + E);
            }
        }

        try { if (typeof window.refresh == 'function') { window.refresh(); } } catch(E) { dump(E+'\n'); }
        try { if (typeof g.refresh == 'function') { g.refresh(); } } catch(E) { dump(E+'\n'); }

        if (typeof xulG.unlock_copy_editor == 'function') {
            xulG.unlock_copy_editor();
        }

        if (typeof xulG.reload_opac == 'function') {
            xulG.reload_opac();
        }
        if (xul_param('load_opac_when_done')) {
            var opac_url = xulG.url_prefix('opac_rdetail') + g.doc_id;
            var content_params = {
                'session' : ses(),
                'authtime' : ses('authtime'),
                'opac_url' : opac_url
            };
            xulG.set_tab(
                xulG.url_prefix('XUL_OPAC_WRAPPER'),
                {
                    'tab_name':'Retrieving title...',
                    'on_tab_load' : function(cw) {
                        if (typeof label_editor_func == 'function') {
                            label_editor_func();
                        }
                    }
                },
                content_params
            );
        } else {
            if (typeof label_editor_func == 'function') {
                label_editor_func();
            }
            if (! dont_close) { xulG.close_tab(); }
        }

    } catch(E) {
        alert('3: Error in volume_copy_creator.js with g.stash_and_close(): ' + E);
    }
}

g.load_prefs = function() {
    try {
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
        alert('Error in volume_copy_creator.js with g.load_prefs(): ' + E);
    }
}

g.save_prefs = function () {
    try {
        JSAN.use('util.file'); var file = new util.file('volume_copy_creator.prefs');
        file.set_object(
            {
                'check_barcodes' : $('check_barcodes').checked,
                'print_labels' : $('print_labels').checked,
            }
        );
        file.close();
    } catch(E) {
        alert('Error in volume_copy_creator.js with g.save_prefs(): ' + E);
    }
}

g.render_class_menu = function(call_number_tb,update_func) {
    var ml = cat.util.render_cn_class_menu();
    ml.setAttribute('rel_vert_pos',rel_vert_pos_call_number_classification);
    ml.addEventListener(
        'command',
        function() {
            call_number_tb.setAttribute('acnc_id',ml.value);
            update_func({'target':call_number_tb});
        },
        false
    );
    return ml;
}

g.render_prefix_menu = function(call_number_tb,update_func) {
    var ou_id = call_number_tb.getAttribute('ou_id');
    var menulist = cat.util.render_cn_prefix_menu([ou_id]);
    menulist.setAttribute('rel_vert_pos',rel_vert_pos_call_number_prefix);
    menulist.addEventListener(
        'command',
        function() {
            call_number_tb.setAttribute('acnp_id',menulist.value);
            update_func({'target':call_number_tb});
        },
        false
    );
    return menulist;
}

g.render_suffix_menu = function(call_number_tb,update_func) {
    var ou_id = call_number_tb.getAttribute('ou_id');
    var menulist = cat.util.render_cn_suffix_menu([ou_id]);
    menulist.setAttribute('rel_vert_pos',rel_vert_pos_call_number_suffix);
    menulist.addEventListener(
        'command',
        function() {
            call_number_tb.setAttribute('acns_id',menulist.value);
            update_func({'target':call_number_tb});
        },
        false
    );
    return menulist;
}

g.list_classes = function() {
    var hbox = $('batch_class');
    var ml = cat.util.render_cn_class_menu(
        [
            [ '<No Change>', false ]
        ]
    ); hbox.appendChild(ml);
    ml.setAttribute('id','batch_class_menulist');
    ml.addEventListener(
        'command',
        function() {
            if (!isNaN(Number(ml.value))) {
                addCSSClass(hbox,'copy_editor_field_changed');
                if (xulG.unified_interface) {
                    xulG.notify_of_templatable_field_change('batch_class_menulist',ml.value);
                }
            } else {
                removeCSSClass(hbox,'copy_editor_field_changed');
            }
        },
        false
    );
}

g.list_prefixes = function() {
    var hbox = $('batch_prefix');
    var ml = cat.util.render_cn_prefix_menu(
        g.common_ancestor_ou_ids,
        [
            [ '<No Change>', false ]
        ]
    );
    ml.setAttribute('id','batch_prefix_menulist');
    hbox.appendChild(ml);
    ml.addEventListener(
        'command',
        function() {
            if (!isNaN(Number(ml.value))) {
                addCSSClass(hbox,'copy_editor_field_changed');
                if (xulG.unified_interface) {
                    xulG.notify_of_templatable_field_change('batch_prefix_menulist',ml.value);
                }
            } else {
                removeCSSClass(hbox,'copy_editor_field_changed');
            }
        },
        false
    );
}

g.list_suffixes = function() {
    var hbox = $('batch_suffix');
    var ml = cat.util.render_cn_suffix_menu(
        g.common_ancestor_ou_ids,
        [
            [ '<No Change>', false ]
        ]
    );
    ml.setAttribute('id','batch_suffix_menulist');
    hbox.appendChild(ml);
    ml.addEventListener(
        'command',
        function() {
            if (!isNaN(Number(ml.value))) {
                addCSSClass(hbox,'copy_editor_field_changed');
                if (xulG.unified_interface) {
                    xulG.notify_of_templatable_field_change('batch_suffix_menulist',ml.value);
                }
            } else {
                removeCSSClass(hbox,'copy_editor_field_changed');
            }
        },
        false
    );
}

g.render_batch_button = function() {
    var hbox = $('batch_button_box');
    var btn = document.createElement('button');
    btn.setAttribute('id','batch_button');
    btn.setAttribute('label',$('catStrings').getString('staff.cat.volume_copy_creator.my_init.btn.label'));
    btn.setAttribute('accesskey',$('catStrings').getString('staff.cat.volume_copy_creator.my_init.btn.accesskey'));
    btn.setAttribute('image','/xul/server/skin/media/images/down_arrow.gif');
    hbox.appendChild(btn);
    btn.addEventListener(
        'command',
        function() {
            var nl = document.getElementsByTagName('textbox');
            for (var i = 0; i < nl.length; i++) {
                /* label */
                if (nl[i].getAttribute('rel_vert_pos')==rel_vert_pos_call_number && !nl[i].disabled) {
                    var label =  $('marc_cn').firstChild.value;
                    if (label != '') {
                        nl[i].value = label;
                        util.widgets.dispatch('change',nl[i]);
                    }
                }
            }
            nl = document.getElementsByTagName('menulist');
            for (var i = 0; i < nl.length; i++) {
                /* classification */
                if (nl[i].getAttribute('rel_vert_pos')==rel_vert_pos_call_number_classification && !nl[i].disabled) {
                    var value =  $('batch_class_menulist').value;
                    if (!isNaN( Number(value) )) {
                        nl[i].value = value;
                        util.widgets.dispatch('command',nl[i]);
                    }
                }
                /* prefix */
                if (nl[i].getAttribute('rel_vert_pos')==rel_vert_pos_call_number_prefix && !nl[i].disabled) {
                    var value =  $('batch_prefix_menulist').value;
                    if (!isNaN( Number(value) )) {
                        nl[i].value = value;
                        util.widgets.dispatch('command',nl[i]);
                    }
                }
                /* suffix */
                if (nl[i].getAttribute('rel_vert_pos')==rel_vert_pos_call_number_suffix && !nl[i].disabled) {
                    var value =  $('batch_suffix_menulist').value;
                    if (!isNaN( Number(value) )) {
                        nl[i].value = value;
                        util.widgets.dispatch('command',nl[i]);
                    }
                }
            }
            setTimeout(
                function() {
                    g.gather_copies_soon(true);
                },0
            );
            if (g.last_focus) setTimeout( function() { g.last_focus.focus(); }, 0 );
        },
        false
    );
}
