dump('entering circ.checkin.js\n');

if (typeof circ == 'undefined') circ = {};
circ.checkin = function (params) {

    JSAN.use('util.error'); this.error = new util.error();
    JSAN.use('util.network'); this.network = new util.network();
    JSAN.use('util.barcode');
    JSAN.use('util.date');
    this.OpenILS = {}; JSAN.use('OpenILS.data'); this.OpenILS.data = new OpenILS.data(); this.OpenILS.data.init({'via':'stash'});
    this.data = this.OpenILS.data;
}

circ.checkin.prototype = {

    'selection_list' : [],
    'row_map' : {},

    'init' : function( params ) {

        var obj = this;

        JSAN.use('circ.util'); JSAN.use('patron.util');
        var columns = circ.util.columns( 
            { 
                'barcode' : { 'hidden' : false },
                'title' : { 'hidden' : false },
                'location' : { 'hidden' : false },
                'status' : { 'hidden' : false },
                'route_to' : { 'hidden' : false },
                'alert_message' : { 'hidden' : false },
                'checkin_time' : { 'hidden' : false }
            },
            {
                'except_these' : [ 'uses', 'checkin_time_full' ]
            }
        ).concat(
            patron.util.columns( { 'family_name' : { 'hidden' : 'false' } } )

        ).concat(
            patron.util.mbts_columns( {}, { 'except_these' : [ 'total_paid', 'total_owed', 'xact_start', 'xact_finish', 'xact_type' ] } )

        ).sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );

        JSAN.use('util.list'); obj.list = new util.list('checkin_list');
        obj.list.init(
            {
                'columns' : columns,
                'retrieve_row' : obj.gen_list_retrieve_row_func(),
                'on_select' : function(ev) {
                    try {
                        JSAN.use('util.functional');
                        var sel = obj.list.retrieve_selection();
                        obj.selection_list = util.functional.map_list(
                            sel,
                            function(o) { 
                                if (o.getAttribute('retrieve_id')) {
                                    try {
                                        var p = JSON2js(o.getAttribute('retrieve_id')); 
                                        p.unique_row_counter = o.getAttribute('unique_row_counter'); 
                                        o.setAttribute('id','_checkin_list_row_'+p.unique_row_counter);
                                        return p; 
                                    } catch(E) {
                                        return -1;
                                    }
                                } else {
                                    return -1;
                                }
                            }
                        );
                        obj.selection_list = util.functional.filter_list(
                            obj.selection_list,
                            function(o) {
                                return o != -1;
                            }
                        );
                        obj.error.sdump('D_TRACE', 'circ/copy_status: selection list = ' + js2JSON(obj.selection_list) );
                        if (obj.selection_list.length == 0) {
                            obj.controller.view.sel_edit.setAttribute('disabled','true');
                            obj.controller.view.sel_backdate.setAttribute('disabled','true');
                            obj.controller.view.sel_opac.setAttribute('disabled','true');
                            obj.controller.view.sel_patron.setAttribute('disabled','true');
                            obj.controller.view.sel_last_patron.setAttribute('disabled','true');
                            obj.controller.view.sel_copy_details.setAttribute('disabled','true');
                            obj.controller.view.sel_bucket.setAttribute('disabled','true');
                            obj.controller.view.sel_spine.setAttribute('disabled','true');
                            obj.controller.view.sel_transit_abort.setAttribute('disabled','true');
                            obj.controller.view.sel_clip.setAttribute('disabled','true');
                            obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','true');
                            obj.controller.view.sel_mark_missing_pieces.setAttribute('disabled','true');
                        } else {
                            obj.controller.view.sel_edit.setAttribute('disabled','false');
                            obj.controller.view.sel_backdate.setAttribute('disabled','false');
                            obj.controller.view.sel_opac.setAttribute('disabled','false');
                            obj.controller.view.sel_patron.setAttribute('disabled','false');
                            obj.controller.view.sel_last_patron.setAttribute('disabled','false');
                            obj.controller.view.sel_copy_details.setAttribute('disabled','false');
                            obj.controller.view.sel_bucket.setAttribute('disabled','false');
                            obj.controller.view.sel_spine.setAttribute('disabled','false');
                            obj.controller.view.sel_transit_abort.setAttribute('disabled','false');
                            obj.controller.view.sel_clip.setAttribute('disabled','false');
                            obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','false');
                            obj.controller.view.sel_mark_missing_pieces.setAttribute('disabled','false');
                        }

                        // This is for updating that label in the upper left of the UI that shows Item already checked-in, etc.
                        // Our purpose here is to show the bill amount associated with a specific transaction whenever that
                        // transaction is selected in the list
                        if (obj.selection_list.length == 1) {
                            var unique_row_counter = obj.selection_list[0].unique_row_counter;
                            var node = $('_checkin_list_row_'+unique_row_counter);
                            if (node && node.getAttribute('no_change_label_label')) {
                                $('no_change_label').setAttribute('unique_row_counter',unique_row_counter);
                                $('no_change_label').setAttribute('value',node.getAttribute('no_change_label_label'));
                                $('no_change_label').setAttribute('onclick',node.getAttribute('no_change_label_click'));
                                $('no_change_label').setAttribute('hidden','false');
                                addCSSClass($('no_change_label'),'click_link'); 
                            }
                        }
                    } catch(E) {
                        alert('FIXME: ' + E);
                    }
                }
            }
        );
        
        JSAN.use('util.controller'); obj.controller = new util.controller();
        obj.controller.init(
            {
                'control_map' : {
                    'save_columns' : [ [ 'command' ], function() { obj.list.save_columns(); } ],
                    'sel_clip' : [
                        ['command'],
                        function() { 
                            obj.list.clipboard(); 
                            obj.controller.view.checkin_barcode_entry_textbox.focus();
                        }
                    ],
                    'sel_edit' : [
                        ['command'],
                        function() {
                            try {
                                obj.spawn_copy_editor();
                            } catch(E) {
                                alert(E);
                            }
                        }
                    ],
                    'sel_spine' : [
                        ['command'],
                        function() {
                            JSAN.use('cat.util');
                            cat.util.spawn_spine_editor(obj.selection_list);
                        }
                    ],
                    'sel_opac' : [
                        ['command'],
                        function() {
                            JSAN.use('cat.util');
                            cat.util.show_in_opac(obj.selection_list);
                        }
                    ],
                    'sel_transit_abort' : [
                        ['command'],
                        function() {
                            JSAN.use('circ.util');
                            circ.util.abort_transits(obj.selection_list);
                        }
                    ],
                    'sel_patron' : [
                        ['command'],
                        function() {
                            JSAN.use('circ.util');
                            circ.util.show_last_few_circs(obj.selection_list);
                        }
                    ],
                    'sel_last_patron' : [
                        ['command'],
                        function() {
                            var patrons = {};
                            for (var i = 0; i < obj.selection_list.length; i++) {
                                var circs = obj.network.simple_request('FM_CIRC_RETRIEVE_VIA_COPY',[ses(),obj.selection_list[i].copy_id,1]);
                                if (circs.length > 0) {
                                    patrons[circs[0].usr()] = 1;
                                } else {
                                    alert(document.getElementById('circStrings').getFormattedString('staff.circ.item_no_circs', [obj.selection_list[i].barcode]));
                                }
                            }
                            for (var i in patrons) {
                                xulG.new_patron_tab({},{'id' : i});
                            }
                        }
                    ],
                    'sel_copy_details' : [
                        ['command'],
                        function() {
                            JSAN.use('circ.util');
                            circ.util.item_details_new(
                                util.functional.map_list(
                                    obj.selection_list,
                                    function(o) { return o.barcode; }
                                )
                            );
                        }
                    ],
                    'sel_backdate' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('circ.util');
                                var circ_ids = []; var circ_row_map = {};
                                for (var i = 0; i < obj.selection_list.length; i++) {
                                    var circ_id = obj.selection_list[i].circ_id; 
                                    var copy_id = obj.selection_list[i].copy_id; 
                                    if (!circ_id) {
                                        var blob = obj.network.simple_request('FM_ACP_DETAILS',[ses(),copy_id]);
                                        if (blob.circ) circ_id = blob.circ.id();
                                    }
                                    if (!circ_id) continue;
                                    if (! circ_row_map[ circ_id ]) { circ_row_map[ circ_id ] = []; }
                                    circ_row_map[ circ_id ].push( obj.selection_list[i].unique_row_counter );
                                    circ_ids.push( circ_id );
                                }
                                var robj = circ.util.backdate_post_checkin( circ_ids );
                                if (robj.complete) {
                                    var bad_circs = {};
                                    for (var i = 0; i < robj.bad_circs.length; i++) {
                                        bad_circs[ robj.bad_circs[i].circ_id ] = robj.bad_circs[i].result;
                                    }
                                    for (var circ_id in circ_row_map) {
                                        var row_array = circ_row_map[circ_id];
                                        for (var i = 0; i < row_array.length; i++) {
                                            var row_data = obj.row_map[ row_array[i] ];
                                            if (row_data.row.my.circ) {
                                                if (bad_circs[ circ_id ]) {
                                                    row_data.row_properties = 'backdate_failed';
                                                } else {
                                                    row_data.row_properties = 'backdate_succeeded';
                                                    row_data.row.my.circ.checkin_time( robj.backdate );
                                                }
                                            }
                                            obj.list.refresh_row( row_data );
                                        } 
                                    }
                                }
                            } catch(E) {
                                alert('Error in checkin.js, sel_backdate: ' + E);
                            }
                        }
                    ],
                    'sel_mark_items_damaged' : [
                        ['command'],
                        function() {
                            var funcs = [];
                            JSAN.use('cat.util'); JSAN.use('util.functional');
                            cat.util.mark_item_damaged( util.functional.map_list( obj.selection_list, function(o) { return o.copy_id; } ) );
                        }
                    ],
                    'sel_mark_missing_pieces' : [
                        ['command'],
                        function() {
                            var funcs = [];
                            JSAN.use('cat.util'); JSAN.use('util.functional');
                            cat.util.mark_item_as_missing_pieces( util.functional.map_list( obj.selection_list, function(o) { return o.copy_id; } ) );
                        }
                    ],
                    'sel_bucket' : [
                        ['command'],
                        function() {
                            JSAN.use('cat.util');
                            cat.util.add_copies_to_bucket(obj.selection_list);
                        }
                    ],
                    'checkin_barcode_entry_textbox' : [
                        ['keypress'],
                        function(ev) {
                            if (ev.keyCode && ev.keyCode == 13) {
                                obj.checkin();
                            }
                        }
                    ],
                    'checkin_effective_date_label' : [
                        ['render'],
                        function(e) {
                            return function() {
                                obj.controller.view.checkin_effective_datepicker.value =
                                    util.date.formatted_date(new Date(),'%F');
                            };
                        }
                    ],
                    'checkin_effective_datepicker' : [
                        ['change'],
                        function(ev) {
                            if (ev.target.nodeName == 'datepicker') {
                                try {
                                    if ( ev.target.dateValue > new Date() ) throw(document.getElementById('circStrings').getString('staff.circ.future_date'));
                                    var x = document.getElementById('background');
                                    if (x) {
                                        if ( ev.target.value == util.date.formatted_date(new Date(),'%F') ) {
                                            //addCSSClass(x,'checkin_screen_normal');
                                            removeCSSClass(x,'checkin_screen_backdating');
                                            removeCSSClass(document.getElementById('background'),'checkin_screen_do_not_alert_on_precat');
                                            removeCSSClass(document.getElementById('background'),'checkin_screen_suppress_holds_and_transits');
                                            removeCSSClass(document.getElementById('background'),'checkin_screen_amnesty_mode');
                                            removeCSSClass(document.getElementById('background'),'checkin_screen_checkin_auto_print_slips');
                                            document.getElementById('background-text').setAttribute('value',document.getElementById('circStrings').getString('staff.circ.process_item'));
                                        } else {
                                            addCSSClass(x,'checkin_screen_backdating');
                                            //removeCSSClass(x,'checkin_screen_normal');
                                            document.getElementById('background-text').setAttribute('value',document.getElementById('circStrings').getFormattedString('staff.circ.backdated_checkin', [ev.target.value]));
                                        }
                                    }
                                } catch(E) {
                                    var x = document.getElementById('background');
                                    if (x) {
                                        //addCSSClass(x,'checkin_screen_normal');
                                        removeCSSClass(x,'checkin_screen_backdating');
                                        removeCSSClass(document.getElementById('background'),'checkin_screen_do_not_alert_on_precat');
                                        removeCSSClass(document.getElementById('background'),'checkin_screen_suppress_holds_and_transits');
                                        removeCSSClass(document.getElementById('background'),'checkin_screen_amnesty_mode');
                                        removeCSSClass(document.getElementById('background'),'checkin_screen_checkin_auto_print_slips');
                                        document.getElementById('background-text').setAttribute('value',document.getElementById('circStrings').getString('staff.circ.process_item'));
                                    }
                                    dump('checkin:effective_date: ' + E + '\n');
                                    ev.target.disabled = true;
                                    //alert(document.getElementById('circStrings').getFormattedString('staff.circ.backdate.exception', [E]));
                                    ev.target.value = util.date.formatted_date(new Date(),'%F');
                                    ev.target.disabled = false;
                                    JSAN.use('util.sound'); var sound = new util.sound(); sound.bad();
                                    
                                }
                            }
                        }
                    ],
                    'cmd_broken' : [
                        ['command'],
                        function() { alert(document.getElementById('circStrings').getString('staff.circ.unimplemented')); }
                    ],
                    'cmd_checkin_submit_barcode' : [
                        ['command'],
                        function() {
                            obj.checkin();
                        }
                    ],
                    'cmd_checkin_print' : [
                        ['command'],
                        function() {
                            var p = { 
                                'printer_context' : 'receipt',
                                'template' : 'checkin'
                            };
                            obj.list.print(p);
                        }
                    ],
                    'cmd_csv_to_clipboard' : [ ['command'], function() { 
                        obj.list.dump_csv_to_clipboard(); 
                        obj.controller.view.checkin_barcode_entry_textbox.focus();
                    } ],
                    'cmd_csv_to_printer' : [ ['command'], function() { 
                        obj.list.dump_csv_to_printer(); 
                        obj.controller.view.checkin_barcode_entry_textbox.focus();
                    } ],
                    'cmd_csv_to_file' : [ ['command'], function() { 
                        obj.list.dump_csv_to_file( { 'defaultFileName' : 'checked_in.txt' } ); 
                        obj.controller.view.checkin_barcode_entry_textbox.focus();
                    } ],
                    'cmd_do_not_alert_on_precat' : [ ['command'], function(ev) {
                        dump('in cmd_do_not_alert_on_precat\n');
                        var bg = document.getElementById('background');
                        var cb = document.getElementById('do_not_alert_on_precat');
                        var ind = document.getElementById('do_not_alert_on_precat_indicator');
                        var cn = 'checkin_screen_do_not_alert_on_precat';
                        if (cb.getAttribute('checked') == 'true') { addCSSClass(bg,cn); } else { removeCSSClass(bg,cn); }
                        ind.hidden = cb.getAttribute('checked') != 'true'; 
                        document.getElementById('checkin_barcode_entry_textbox').focus();
                        return true;
                    } ],
                    'cmd_suppress_holds_and_transits' : [ ['command'], function(ev) {
                        dump('in cmd_suppress_holds_and_transits\n');
                        var bg = document.getElementById('background');
                        var cb = document.getElementById('suppress_holds_and_transits');
                        var ind = document.getElementById('suppress_holds_and_transits_indicator');
                        var cn = 'checkin_screen_suppress_holds_and_transits';
                        if (cb.getAttribute('checked') == 'true') { addCSSClass(bg,cn); } else { removeCSSClass(bg,cn); }
                        ind.hidden = cb.getAttribute('checked') != 'true'; 
                        document.getElementById('checkin_barcode_entry_textbox').focus();
                        return true;
                    } ],
                    'cmd_amnesty_mode' : [ ['command'], function(ev) {
                        dump('in cmd_amnesty_mode\n');
                        var bg = document.getElementById('background');
                        var cb = document.getElementById('amnesty_mode');
                        var ind = document.getElementById('amnesty_mode_indicator');
                        var cn = 'checkin_screen_amnesty_mode';
                        if (cb.getAttribute('checked') == 'true') { addCSSClass(bg,cn); } else { removeCSSClass(bg,cn); }
                        ind.hidden = cb.getAttribute('checked') != 'true'; 
                        document.getElementById('checkin_barcode_entry_textbox').focus();
                        return true;
                    } ],
                    'cmd_checkin_auto_print_slips' : [ ['command'], function(ev) {
                        dump('in cmd_checkin_auto_print_slips\n');
                        var bg = document.getElementById('background');
                        var cb = document.getElementById('checkin_auto_print_slips');
                        var ind = document.getElementById('checkin_auto_print_slips_indicator');
                        var cn = 'checkin_screen_checkin_auto_print_slips';
                        if (cb.getAttribute('checked') == 'true') { addCSSClass(bg,cn); } else { removeCSSClass(bg,cn); }
                        ind.hidden = cb.getAttribute('checked') != 'true'; 
                        document.getElementById('checkin_barcode_entry_textbox').focus();
                        return true;
                    } ],
                    'cmd_checkin_clear_shelf_expired' : [ ['command'], function(ev) {
                        dump('in cmd_checkin_clear_shelf_expired\n');
                        var bg = document.getElementById('background');
                        var cb = document.getElementById('checkin_clear_shelf_expired');
                        var ind = document.getElementById('checkin_clear_shelf_expired_indicator');
                        var cn = 'checkin_screen_checkin_clear_shelf_expired';
                        if (cb.getAttribute('checked') == 'true') { addCSSClass(bg,cn); } else { removeCSSClass(bg,cn); }
                        ind.hidden = cb.getAttribute('checked') != 'true'; 
                        document.getElementById('checkin_barcode_entry_textbox').focus();
                        return true;
                    } ],
                    'cmd_checkin_auto_retarget' : [ ['command'], function(ev) {
                        dump('in cmd_checkin_auto_retarget\n');
                        var bg = document.getElementById('background');
                        var cb = document.getElementById('checkin_auto_retarget');
                        var cb2 = document.getElementById('checkin_auto_retarget_all');
                        var ind = document.getElementById('checkin_auto_retarget_indicator');
                        var ind2 = document.getElementById('checkin_auto_retarget_all_indicator');
                        var cn = 'checkin_screen_checkin_auto_retarget';
                        var cn2 = 'checkin_screen_checkin_auto_retarget_all';
                        if (cb.getAttribute('checked') == 'true') {
                            if(cb2.getAttribute('checked') == 'true') {
                                removeCSSClass(bg,cn);
                                addCSSClass(bg,cn2);
                                ind.hidden = true;
                                ind2.hidden = false;
                            } else {
                                addCSSClass(bg,cn);
                                removeCSSClass(bg,cn2);
                                ind.hidden = false;
                                ind2.hidden = true;
                            }
                        } else {
                            removeCSSClass(bg,cn);
                            removeCSSClass(bg,cn2);
                            ind.hidden = true;
                            ind2.hidden = true;
                        }
                        document.getElementById('checkin_barcode_entry_textbox').focus();
                        return true;
                    } ],
                    'cmd_checkin_local_hold_as_transit' : [ ['command'], function(ev) {
                        dump('in cmd_checkin_local_hold_as_transit\n');
                        var bg = document.getElementById('background');
                        var cb = document.getElementById('checkin_local_hold_as_transit');
                        var ind = document.getElementById('checkin_local_hold_as_transit_indicator');
                        var cn = 'checkin_screen_checkin_local_hold_as_transit';
                        if (cb.getAttribute('checked') == 'true') { addCSSClass(bg,cn); } else { removeCSSClass(bg,cn); }
                        ind.hidden = cb.getAttribute('checked') != 'true'; 
                        document.getElementById('checkin_barcode_entry_textbox').focus();
                        return true;

                    } ]
                }
            }
        );
        this.controller.render();
        this.controller.view.checkin_barcode_entry_textbox.focus();

    },

    'update_no_change_label' : function (node,row) {
        var obj = this;
        var no_change_label = document.getElementById('no_change_label');
        var incumbent_row = no_change_label.getAttribute('unique_row_counter');
        var incoming_row = node.getAttribute('unique_row_counter');
        if (!incumbent_row) { incumbent_row = incoming_row; }
        if (row.my.mbts && ( no_change_label || document.getElementById('fine_tally') ) ) {
            var bill = row.my.mbts;
            if (Number(bill.balance_owed()) == 0) { return; }
            if (no_change_label) {
                var msg = incumbent_row != incoming_row
                    ? '' // clear out label if for a different transaction
                    : no_change_label.getAttribute('value');
                var new_msg = document.getElementById('circStrings').getFormattedString(
                    'staff.circ.utils.billable.amount', [
                        row.my.acp.barcode(),
                        util.money.sanitize(bill.balance_owed())
                    ]
                );
                no_change_label.setAttribute(
                    'value', 
                    msg.indexOf(new_msg) > -1 ? msg : msg + new_msg + '  '
                );
                no_change_label.setAttribute('hidden','false');
                no_change_label.setAttribute('onclick','xulG.new_patron_tab({},{"id" : '+bill.usr()+', "show" : "bills" })');
                no_change_label.setAttribute('unique_row_counter',incoming_row);
                addCSSClass(no_change_label,'click_link'); 
                node.setAttribute('no_change_label_label', no_change_label.getAttribute('value'));
                node.setAttribute('no_change_label_click', no_change_label.getAttribute('onclick'));
            }
        }
    },

    'gen_list_retrieve_row_func' : function() {
        var obj = this;
        return function(params) {
            try {
                var row = params.row;
                if (typeof params.on_retrieve == 'function') params.on_retrieve(row);
                obj.update_no_change_label(params.treeitem_node,row);
                var bill = row.my.mbts;
                if (bill && document.getElementById('fine_tally') && ! row.already_tallied) {
                    params.row.already_tallied = true;
                    var amount = util.money.cents_as_dollars(
                        Number( util.money.dollars_float_to_cents_integer( document.getElementById('fine_tally').getAttribute('amount') ) ) 
                        + Number( util.money.dollars_float_to_cents_integer( bill.balance_owed() ) )
                    );
                    document.getElementById('fine_tally').setAttribute('amount',amount);
                    document.getElementById('fine_tally').setAttribute(
                        'value',
                        document.getElementById('circStrings').getFormattedString('staff.circ.utils.fine_tally_text', [ util.money.sanitize( amount ) ])
                    );
                    document.getElementById('fine_tally').setAttribute('hidden','false');
                }
            } catch(E) {
                alert('Error in checkin.js, list_retrieve_row(): ' + E);
            }
            return row;
        };
    },

    'test_barcode' : function(bc) {
        var obj = this;
        var x = document.getElementById('strict_barcode');
        if (x && x.checked != true) return true;
        var good = util.barcode.check(bc);
        if (good) {
            return true;
        } else {
            if ( 1 == obj.error.yns_alert(
                        document.getElementById('circStrings').getFormattedString('staff.circ.check_digit.bad', [bc]),
                        document.getElementById('circStrings').getString('staff.circ.barcode.bad'),
                        document.getElementById('circStrings').getString('staff.circ.cancel'),
                        document.getElementById('circStrings').getString('staff.circ.barcode.accept'),
                        null,
                        document.getElementById('circStrings').getString('staff.circ.confirm'),
                        '/xul/server/skin/media/images/bad_barcode.png'
            ) ) {
                return true;
            } else {
                return false;
            }
        }
    },

    'checkin' : function() {
        var obj = this;
        try {
            var textbox = obj.controller.view.checkin_barcode_entry_textbox;
            var async = false;
            var async_checkbox = document.getElementById('async_checkin');
            if (async_checkbox) { async = async_checkbox.getAttribute('checked') == 'true'; }
            var barcode = textbox.value;
            // Auto-complete the barcode, items only
            var barcode_object = xulG.get_barcode(window, 'asset', barcode);
            if (async) {
                textbox.value = ''; textbox.focus();
            }
            // user_false means the user selected "None of the above", abort before other prompts/errors
            if(barcode_object == "user_false") return;
            // Got a barcode without an error? Use it. Otherwise fall through.
            if(barcode_object && typeof barcode_object.ilsevent == 'undefined')
                barcode = barcode_object.barcode;
            if ( obj.test_barcode(barcode) ) { /* good */ } else { /* bad */ return; }
            var placeholder_item = new acp();
            placeholder_item.barcode( barcode );
            var row_params = obj.list.append( { 
                    'row' : {
                        'my' : { 
                            'acp' : placeholder_item
                        } 
                    },
                    'to_top' : true,
                    'flesh_immediately' : !async,
                    'on_append' : function(rparams) { obj.row_map[ rparams.unique_row_counter ] = rparams; },
                    'on_remove' : function(unique_row_counter) { delete obj.row_map[ unique_row_counter ]; }
            } );
            
            var backdate = obj.controller.view.checkin_effective_datepicker.value;
            var auto_print = document.getElementById('checkin_auto_print_slips');
            if (auto_print) auto_print = auto_print.getAttribute('checked') == 'true';
            JSAN.use('circ.util');
            var params = { 
                'barcode' : barcode,
                'disable_textbox' : function() { 
                    if (!async) {
                        textbox.blur();
                        textbox.disabled = true; 
                        textbox.setAttribute('disabled', 'true'); 
                    }
                },
                'enable_textbox' : function() { 
                    textbox.disabled = false; 
                    textbox.setAttribute('disabled', 'false'); 
                    textbox.focus();
                },
                'checkin_result' : function(checkin) {
                    textbox.disabled = false;
                    textbox.focus();
                    //obj.controller.view.cmd_checkin_submit_barcode.setAttribute('disabled', 'false'); 
                    obj.checkin2(checkin,backdate,row_params);
                },
                'info_blurb' : function(text) {
                    try { row_params.row.my.acp.alert_message( text ); } catch(E) {dump('error: ' + E + '\n');}
                }
            }; 
            var suppress_holds_and_transits = document.getElementById('suppress_holds_and_transits');
            if (suppress_holds_and_transits) suppress_holds_and_transits = suppress_holds_and_transits.getAttribute('checked') == 'true';
            if (suppress_holds_and_transits) params.noop = 1;
            var amnesty_mode = document.getElementById('amnesty_mode');
            if (amnesty_mode) amnesty_mode = amnesty_mode.getAttribute('checked') == 'true';
            if (amnesty_mode) params.void_overdues = 1;
            var clear_shelf_expired_holds = document.getElementById('checkin_clear_shelf_expired');
            if (clear_shelf_expired_holds) clear_shelf_expired_holds = clear_shelf_expired_holds.getAttribute('checked') == 'true';
            if (clear_shelf_expired_holds) params.clear_expired = 1;
            var auto_retarget = document.getElementById('checkin_auto_retarget');
            if (auto_retarget) auto_retarget = auto_retarget.getAttribute('checked') == 'true';
            if (auto_retarget) {
                var retarget_all = document.getElementById('checkin_auto_retarget_all');
                if (retarget_all) retarget_all = retarget_all.getAttribute('checked') == 'true';
                if (retarget_all) params.retarget_mode = 'retarget.all';
                else params.retarget_mode = 'retarget';
            }
            var hold_as_transit = document.getElementById('checkin_local_hold_as_transit');
            if (hold_as_transit) hold_as_transit = hold_as_transit.getAttribute('checked') == 'true';
            if (hold_as_transit) params.hold_as_transit = 1;
            circ.util.checkin_via_barcode(
                ses(), 
                params,
                backdate, 
                auto_print,
                async
            );
        } catch(E) {
            obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getFormattedString('staff.circ.checkin.exception', [E]), E);
            if (typeof obj.on_failure == 'function') {
                obj.on_failure(E);
            }
            if (typeof window.xulG == 'object' && typeof window.xulG.on_failure == 'function') {
                obj.error.sdump('D_CIRC', document.getElementById('circStrings').getString('staff.circ.util.checkin.exception.external') + '\n');
                window.xulG.on_failure(E);
            } else {
                obj.error.sdump('D_CIRC', document.getElementById('circStrings').getString('staff.circ.util.checkin.exception.no_external') + '\n');
            }
        }

    },

    'checkin2' : function(checkin,backdate,row_params) {
        var obj = this;
        try {
            if (!checkin) {/* circ.util.checkin used to be sole handler of errors and returns null currently */
                obj.list.refresh_row( row_params ); /* however, let's refresh the row because we're shoving error text into the dummy placeholder item's alert_message field  */
                return obj.on_failure();
            }
            if (checkin.ilsevent == 7010 /* COPY_ALERT_MESSAGE */
                || checkin.ilsevent == 1203 /* COPY_BAD_STATUS */
                || checkin.ilsevent == -1 /* offline */
                || checkin.ilsevent == 1502 /* ASSET_COPY_NOT_FOUND */
                || checkin.ilsevent == 1203 /* COPY_BAD_STATUS */
                || checkin.ilsevent == 7009 /* CIRC_CLAIMS_RETURNED */ 
                || checkin.ilsevent == 7011 /* COPY_STATUS_LOST */ 
                || checkin.ilsevent == 7012 /* COPY_STATUS_MISSING */) {
                obj.list.refresh_row( row_params ); 
                return obj.on_failure();
            }
            var retrieve_id = js2JSON( { 'circ_id' : checkin.circ ? checkin.circ.id() : null , 'copy_id' : checkin.copy.id(), 'barcode' : checkin.copy.barcode(), 'doc_id' : (typeof checkin.record != 'undefined' ? ( typeof checkin.record.ilsevent == 'undefined' ? checkin.record.doc_id() : null ) : null ) } );
            if (checkin.circ && checkin.circ.checkin_time() == 'now') checkin.circ.checkin_time(backdate);
            if (document.getElementById('trim_list')) {
                var x = document.getElementById('trim_list');
                if (x.checked) { obj.list.trim_list = 20; } else { obj.list.trim_list = null; }
            }
            row_params['retrieve_id'] = retrieve_id;
            row_params['row'] =  {
                'already_tallied' : false,
                'my' : {
                    'circ' : checkin.circ,
                    'mbts' : checkin.circ ? checkin.circ.billable_transaction().summary() : null,
                    'mvr' : checkin.record,
                    'acp' : checkin.copy,
                    'acn' : checkin.volume,
                    'au' : checkin.patron,
                    'status' : checkin.status,
                    'route_to' : checkin.route_to,
                    'message' : checkin.message
                }
            };
            obj.list.refresh_row( row_params );
            obj.list.node.view.selection.select(0);

            JSAN.use('util.sound'); var sound = new util.sound(); sound.circ_good();

            if (typeof obj.on_checkin == 'function') {
                obj.on_checkin(checkin);
            }
            if (typeof window.xulG == 'object' && typeof window.xulG.on_checkin == 'function') {
                obj.error.sdump('D_CIRC', document.getElementById('circStrings').getString('staff.circ.checkin.exception.external') + '\n');
                window.xulG.on_checkin(checkin);
            } else {
                obj.error.sdump('D_CIRC', document.getElementById('circStrings').getString('staff.circ.checkin.exception.no_external') + '\n');
            }

            return true;

        } catch(E) {
            obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getFormattedString('staff.circ.checkin2.exception', [E]));
            if (typeof obj.on_failure == 'function') {
                obj.on_failure(E);
            }
            if (typeof window.xulG == 'object' && typeof window.xulG.on_failure == 'function') {
                obj.error.sdump('D_CIRC', document.getElementById('circStrings').getString('staff.circ.checkin2.exception.external') + '\n');
                window.xulG.on_failure(E);
            } else {
                obj.error.sdump('D_CIRC', document.getElementById('circStrings').getString('staff.circ.checkin2.exception.no_external') + '\n');
            }
        }

    },

    'on_checkin' : function() {
        var async = false;
        var async_checkbox = document.getElementById('async_checkin');
        if (async_checkbox) { async = async_checkbox.getAttribute('checked') == 'true'; }
        if (!async) {
            this.controller.view.checkin_barcode_entry_textbox.disabled = false;
            this.controller.view.checkin_barcode_entry_textbox.select();
            this.controller.view.checkin_barcode_entry_textbox.value = '';
            this.controller.view.checkin_barcode_entry_textbox.focus();
        }
    },

    'on_failure' : function() {
        var async = false;
        var async_checkbox = document.getElementById('async_checkin');
        if (async_checkbox) { async = async_checkbox.getAttribute('checked') == 'true'; }
        if (!async) {
            this.controller.view.checkin_barcode_entry_textbox.disabled = false;
            this.controller.view.checkin_barcode_entry_textbox.select();
            this.controller.view.checkin_barcode_entry_textbox.focus();
        }
    },
    
    'spawn_copy_editor' : function() {

        var obj = this;

        JSAN.use('util.functional');

        var list = obj.selection_list;

        list = util.functional.map_list(
            list,
            function (o) {
                return o.copy_id;
            }
        );

        JSAN.use('cat.util'); cat.util.spawn_copy_editor( { 'copy_ids' : list, 'edit' : 1 } );

    }

}

dump('exiting circ.checkin.js\n');
