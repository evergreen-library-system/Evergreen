dump('entering circ.copy_status.js\n');
// vim:noet:sw=4:ts=4:

if (typeof circ == 'undefined') { circ = {}; }
circ.copy_status = function (params) {

    JSAN.use('util.error'); this.error = new util.error();
    JSAN.use('util.network'); this.network = new util.network();
    JSAN.use('util.barcode');
    JSAN.use('util.date');
    JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
    JSAN.use('util.sound'); this.sound = new util.sound();
    JSAN.use('cat.util');

};

circ.copy_status.prototype = {
    'selection_list' : [],
    'list_copyid_map' : {},
    'detail_map' : {},

    'init' : function( params ) {

        var obj = this;

        JSAN.use('circ.util');
        var columns = circ.util.columns( 
            { 
                'barcode' : { 'hidden' : false },
                'title' : { 'hidden' : false },
                'location' : { 'hidden' : false },
                'call_number' : { 'hidden' : false },
                'acp_status' : { 'hidden' : false },
                'alert_message' : { 'hidden' : false },
                'due_date' : { 'hidden' : false }
            },
            {
                'except_these' : [
                    'route_to', 'message', 'uses'
                ]
            }
        );

        JSAN.use('util.list'); obj.list = new util.list('copy_status_list');
        obj.list.init(
            {
                'columns' : columns,
                'on_select' : function(ev) {
                    try {
                        JSAN.use('util.functional');
                        var sel = obj.list.retrieve_selection();
                        obj.selection_list = util.functional.map_list(
                            sel,
                            function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
                        );
                        obj.error.sdump('D_TRACE','circ/copy_status: selection list = ' + js2JSON(obj.selection_list) );
                        if (obj.selection_list.length == 0) {
                            obj.controller.view.sel_checkin.setAttribute('disabled','true');
                            obj.controller.view.cmd_replace_barcode.setAttribute('disabled','true');
                            obj.controller.view.sel_edit.setAttribute('disabled','true');
                            obj.controller.view.sel_vol_copy_edit.setAttribute('disabled','true');
                            obj.controller.view.sel_opac.setAttribute('disabled','true');
                            obj.controller.view.sel_bucket.setAttribute('disabled','true');
                            obj.controller.view.sel_record_bucket.setAttribute('disabled','true');
                            obj.controller.view.sel_copy_details.setAttribute('disabled','true');
                            obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','true');
                            obj.controller.view.sel_mark_items_missing.setAttribute('disabled','true');
                            obj.controller.view.sel_patron.setAttribute('disabled','true');
                            obj.controller.view.cmd_triggered_events.setAttribute('disabled','true');
                            obj.controller.view.cmd_create_brt.setAttribute('disabled','true');
                            obj.controller.view.cmd_book_item_now.setAttribute('disabled','true');
                            obj.controller.view.cmd_request_items.setAttribute('disabled','true');
                            obj.controller.view.cmd_find_acq_po.setAttribute('disabled','true');
                            obj.controller.view.sel_spine.setAttribute('disabled','true');
                            obj.controller.view.sel_transit_abort.setAttribute('disabled','true');
                            obj.controller.view.sel_clip.setAttribute('disabled','true');
                            obj.controller.view.sel_renew.setAttribute('disabled','true');
                            obj.controller.view.cmd_add_items.setAttribute('disabled','true');
                            obj.controller.view.cmd_delete_items.setAttribute('disabled','true');
                            obj.controller.view.cmd_transfer_items.setAttribute('disabled','true');
                            obj.controller.view.cmd_add_volumes.setAttribute('disabled','true');
                            obj.controller.view.cmd_edit_volumes.setAttribute('disabled','true');
                            obj.controller.view.cmd_delete_volumes.setAttribute('disabled','true');
                            obj.controller.view.cmd_mark_volume.setAttribute('disabled','true');
                            obj.controller.view.cmd_mark_library.setAttribute('disabled','true');
                            obj.controller.view.cmd_transfer_volume.setAttribute('disabled','true');
                        } else {
                            obj.controller.view.sel_checkin.setAttribute('disabled','false');
                            obj.controller.view.cmd_replace_barcode.setAttribute('disabled','false');
                            obj.controller.view.sel_edit.setAttribute('disabled','false');
                            obj.controller.view.sel_vol_copy_edit.setAttribute('disabled','false');
                            obj.controller.view.sel_opac.setAttribute('disabled','false');
                            obj.controller.view.sel_patron.setAttribute('disabled','false');
                            obj.controller.view.cmd_triggered_events.setAttribute('disabled','false');
                            obj.controller.view.sel_bucket.setAttribute('disabled','false');
                            obj.controller.view.sel_record_bucket.setAttribute('disabled','false');
                            obj.controller.view.sel_copy_details.setAttribute('disabled','false');
                            obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','false');
                            obj.controller.view.sel_mark_items_missing.setAttribute('disabled','false');
                            if (obj.selected_one_unique_owning_lib()) {
                                obj.controller.view.cmd_book_item_now.setAttribute('disabled','false');
                            } else {
                                obj.controller.view.cmd_book_item_now.setAttribute('disabled','true');
                            }
                            obj.controller.view.cmd_request_items.setAttribute('disabled','false');
                            obj.controller.view.cmd_create_brt.setAttribute('disabled','false');
                            obj.controller.view.cmd_find_acq_po.setAttribute("disabled", obj.selection_list.length == 1 ? "false" : "true");
                            obj.controller.view.sel_spine.setAttribute('disabled','false');
                            obj.controller.view.sel_transit_abort.setAttribute('disabled','false');
                            obj.controller.view.sel_clip.setAttribute('disabled','false');
                            obj.controller.view.sel_renew.setAttribute('disabled','false');
                            obj.controller.view.cmd_add_items.setAttribute('disabled','false');
                            obj.controller.view.cmd_delete_items.setAttribute('disabled','false');
                            obj.controller.view.cmd_transfer_items.setAttribute('disabled','false');
                            obj.controller.view.cmd_add_volumes.setAttribute('disabled','false');
                            obj.controller.view.cmd_edit_volumes.setAttribute('disabled','false');
                            obj.controller.view.cmd_delete_volumes.setAttribute('disabled','false');
                            obj.controller.view.cmd_mark_volume.setAttribute('disabled','false');
                            obj.controller.view.cmd_mark_library.setAttribute('disabled','false');
                            obj.controller.view.cmd_transfer_volume.setAttribute('disabled','false');
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
                    'list_actions' : [
                        ['render'],
                        function(e) {
                            return function() {
                                e.appendChild( obj.list.render_list_actions() );
                                obj.list.set_list_actions(
                                    {
                                        'on_complete' : function() { obj.controller.view.copy_status_barcode_entry_textbox.focus(); } 
                                    }
                                );
                            };
                        }
                    ],
                    'sel_clip' : [ ['command'], function() { obj.list.clipboard(); obj.controller.view.copy_status_barcode_entry_textbox.focus(); } ],
                    'save_columns' : [ ['command'], function() { obj.list.save_columns(); obj.controller.view.copy_status_barcode_entry_textbox.focus(); } ],
                    'alt_view_btn' : [
                        ['render'],
                        function(e) {
                            e.setAttribute('label', document.getElementById("circStrings").getString('staff.circ.copy_status.alt_view.label'));
                            e.setAttribute('accesskey', document.getElementById("circStrings").getString('staff.circ.copy_status.alt_view.accesskey'));
                        }
                    ],
                    'cmd_alt_view' : [
                        ['command'],
                        function(ev) {
                            try {
                                var n = obj.controller.view.alt_view_btn;
                                if (n.getAttribute('toggle') == '1') {
                                    document.getElementById('deck').selectedIndex = 0;
                                    n.setAttribute('toggle','0');
                                    n.setAttribute('label', document.getElementById("circStrings").getString('staff.circ.copy_status.alt_view.label'));
                                    n.setAttribute('accesskey', document.getElementById("circStrings").getString('staff.circ.copy_status.alt_view.accesskey'));
                                    obj.controller.view.copy_status_barcode_entry_textbox.focus();
                                } else {
                                    document.getElementById('deck').selectedIndex = 1;
                                    n.setAttribute('toggle','1');
                                    n.setAttribute('label', document.getElementById("circStrings").getString('staff.circ.copy_status.list_view.label'));
                                    n.setAttribute('accesskey', document.getElementById("circStrings").getString('staff.circ.copy_status.list_view.accesskey'));
                                    obj.controller.view.copy_status_barcode_entry_textbox.focus();
                                    if (obj.selection_list.length == 0) return;
                                    var f = obj.browser.get_content();
                                    xulG.barcode = obj.selection_list[0].barcode; 
                                    f.xulG = xulG;
                                    f.load_item();
                                }
                            } catch(E) {
                                alert('Error in copy_status.js, cmd_alt_view handler: ' + E);
                            }
                        },
                    ],
                    'cmd_triggered_events' : [
                        ['command'],
                        function() {
                            try {
                                for (var i = 0; i < obj.selection_list.length; i++) {
                                    xulG.new_tab(
                                        xulG.url_prefix(urls.XUL_REMOTE_BROWSER),
                                        {
                                            'tab_name' : document.getElementById('commonStrings').getFormattedString('tab.label.triggered_events_for_copy',[ obj.selection_list[i].barcode ])
                                        },
                                        {
                                            'url': urls.EG_TRIGGER_EVENTS + "?copy_id=" + obj.selection_list[i].copy_id,
                                            'show_print_button': false,
                                            'show_nav_buttons': false
                                        }
                                    );
                                }
                            } catch(E) {
                                alert('Error in copy_status.js, cmd_triggered_events: ' + E);
                            }
                        }
                    ],
                    'cmd_create_brt' : [
                        ['command'],
                        function() {
                            JSAN.use("cat.util");
                            JSAN.use("util.functional");

                            var results = cat.util.make_bookable(
                                util.functional.map_list(
                                    obj.selection_list, function (o) {
                                        return o.copy_id;
                                    }
                                )
                            );
                            if (results && results["brsrc"]) {
                                cat.util.edit_new_brsrc(results["brsrc"]);
                            }
                        }
                    ],
                    'cmd_book_item_now' : [
                        ['command'],
                        function() {
                            JSAN.use("cat.util");
                            JSAN.use("util.functional");

                            var results = cat.util.make_bookable(
                                util.functional.map_list(
                                    obj.selection_list, function (o) {
                                        return o.copy_id;
                                    }
                                )
                            );
                            if (results) {
                                cat.util.edit_new_bresv(results);
                            }
                        }
                    ],
                    'cmd_request_items' : [
                        ['command'],
                        function() {
                            JSAN.use('cat.util'); JSAN.use('util.functional');

                            var list = util.functional.map_list(
                                obj.selection_list, function (o) {
                                    return o.copy_id;
                                }
                            );

                            cat.util.request_items( list );
                        }
                    ],
                    "cmd_find_acq_po" : [
                        ["command"],
                        function() {
                            JSAN.use("circ.util");
                            circ.util.find_acq_po(
                                ses(), obj.selection_list[0].copy_id
                            );
                        }
                    ],
                    'sel_checkin' : [
                        ['command'],
                        function() {
                            try {
                                var funcs = [];
                                var auto_print = document.getElementById('checkin_auto_print_slips');
                                if (auto_print) auto_print = auto_print.getAttribute('checked') == 'true';
                                JSAN.use('circ.util');
                                for (var i = 0; i < obj.selection_list.length; i++) {
                                    var barcode = obj.selection_list[i].barcode;
                                    var checkin = circ.util.checkin_via_barcode(
                                        ses(),
                                        { 'barcode' : barcode },
                                        false /* backdate */,
                                        auto_print
                                    );
                                    funcs.push( function(a) { return function() { obj.copy_status( a, true ); }; }(barcode) );
                                }
                                for (var i = 0; i < funcs.length; i++) { funcs[i](); }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.copy_status.sel_checkin.error'),E);
                            }
                        }
                    ],
                    'cmd_replace_barcode' : [
                        ['command'],
                        function() {
                            try {
                                var funcs = [];
                                JSAN.use('cat.util');
                                for (var i = 0; i < obj.selection_list.length; i++) {
                                    try { 
                                        var barcode = obj.selection_list[i].barcode;
                                        var new_bc = cat.util.replace_barcode( barcode );
                                        funcs.push( function(a) { return function() { obj.copy_status( a, true ); }; }(new_bc) );
                                    } catch(E) {
                                        obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getFormattedString('staff.circ.copy_status.cmd_replace_barcode.error', [barcode]), E);
                                    }
                                }
                                for (var i = 0; i < funcs.length; i++) { funcs[i](); }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.copy_status.cmd_replace_barcodes.error'), E);
                            }
                        }
                    ],
                    'sel_edit' : [
                        ['command'],
                        function() {
                            try {
                                var funcs = [];
                                obj.spawn_copy_editor();
                                for (var i = 0; i < obj.selection_list.length; i++) {
                                        var barcode = obj.selection_list[i].barcode;
                                        funcs.push( function(a) { return function() { obj.copy_status( a, true ); }; }(barcode) );
                                }
                                for (var i = 0; i < funcs.length; i++) { funcs[i](); }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.copy_status.sel_edit.error'), E);
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
                            var funcs = [];
                            JSAN.use('circ.util');
                            circ.util.abort_transits(obj.selection_list);
                            for (var i = 0; i < obj.selection_list.length; i++) {
                                var barcode = obj.selection_list[i].barcode;
                                funcs.push( function(a) { return function() { obj.copy_status( a, true ); }; }(barcode) );
                            }
                            for (var i = 0; i < funcs.length; i++) { funcs[i](); }
                        }
                    ],
                    'sel_patron' : [
                        ['command'],
                        function() {
                            JSAN.use('circ.util');
                            circ.util.show_last_few_circs(obj.selection_list);
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
                    'sel_renew' : [
                        ['command'],
                        function() {
                            var funcs = [];
                            JSAN.use('circ.util');
                            for (var i = 0; i < obj.selection_list.length; i++) {
                                var test = obj.selection_list[i].renewable;
                                var barcode = obj.selection_list[i].barcode;
                                if (test == 't') {
                                    circ.util.renew_via_barcode( { 'barcode' : barcode } );
                                    funcs.push( function(a) { return function() { obj.copy_status( a, true ); }; }(barcode) );
                                } else {
                                    alert(document.getElementById('circStrings').getFormattedString('staff.circ.copy_status.sel_renew.not_circulating', [barcode]));
                                }
                            }
                            for (var i = 0; i < funcs.length; i++) { funcs[i](); }
                        }
                    ],

                    'sel_mark_items_damaged' : [
                        ['command'],
                        function() {
                            var funcs = [];
                            JSAN.use('cat.util'); JSAN.use('util.functional');
                            cat.util.mark_item_damaged( util.functional.map_list( obj.selection_list, function(o) { return o.copy_id; } ) );
                            for (var i = 0; i < obj.selection_list.length; i++) {
                                var barcode = obj.selection_list[i].barcode;
                                funcs.push( function(a) { return function() { obj.copy_status( a, true ); }; }(barcode) );
                            }
                            for (var i = 0; i < funcs.length; i++) { funcs[i](); }
                        }
                    ],
                    'sel_mark_items_missing' : [
                        ['command'],
                        function() {
                            var funcs = [];
                            JSAN.use('cat.util'); JSAN.use('util.functional');
                            cat.util.mark_item_missing( util.functional.map_list( obj.selection_list, function(o) { return o.copy_id; } ) );
                            for (var i = 0; i < obj.selection_list.length; i++) {
                                var barcode = obj.selection_list[i].barcode;
                                funcs.push( function(a) { return function() { obj.copy_status( a, true ); }; }(barcode) );
                            }
                            for (var i = 0; i < funcs.length; i++) { funcs[i](); }
                        }
                    ],
                    'sel_bucket' : [
                        ['command'],
                        function() {
                            JSAN.use('cat.util');
                            cat.util.add_copies_to_bucket(obj.selection_list);
                        }
                    ],
                    'sel_record_bucket' : [
                        ['command'],
                        function() {
                            JSAN.use('cat.util'); JSAN.use('util.functional');
                            cat.util.add_titles_to_bucket(
                                util.functional.map_list(
                                    obj.selection_list, function (o) {
                                        return o.doc_id;
                                    }
                                )
                            );
                        }
                    ],
                    'copy_status_barcode_entry_textbox' : [
                        ['keypress'],
                        function(ev) {
                            if (ev.keyCode && ev.keyCode == 13) {
                                obj.copy_status();
                            }
                        }
                    ],
                    'cmd_broken' : [
                        ['command'],
                        function() { alert(document.getElementById('circStrings').getString('staff.circ.unimplemented')); }
                    ],
                    'cmd_copy_status_submit_barcode' : [
                        ['command'],
                        function() {
                            obj.copy_status();
                        }
                    ],
                    'cmd_copy_status_upload_file' : [
                        ['command'],
                        function() {
                            JSAN.use('util.file');
                            var f = new util.file('');
                            var content = f.import_file( { 'title' : document.getElementById('circStrings').getString('staff.circ.copy_status.upload_file.title'), 'not_json' : true } );
                            if (!content) { return; }
                            var barcodes = content.split(/[,\s]+/);
                            if (barcodes.length > 0) {
                                JSAN.use('util.exec'); var exec = new util.exec();
                                var funcs = [];
                                for (var i = 0; i < barcodes.length; i++) {
                                    funcs.push(
                                        function(b){
                                            return function() {
                                                obj.copy_status(b);
                                            };
                                        }(barcodes[i])
                                    );
                                }
                                funcs.push( function() { alert(document.getElementById('circStrings').getString('staff.circ.copy_status.upload_file.complete')); } );
                                exec.chain( funcs );
                            } else {
                                alert(document.getElementById('circStrings').getString('staff.circ.copy_status.upload_file.no_barcodes'));
                            }

                        }
                    ],
                    'cmd_copy_status_print' : [
                        ['command'],
                        function() {
                            try {
                                var p = { 
                                    'template' : 'item_status'
                                };
                                obj.list.print(p);
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('print',E); 
                            }
                        }
                    ],
                    'cmd_add_items' : [
                        ['command'],
                        function() {
                            try {

                                JSAN.use('util.functional');
                                var list = util.functional.map_list( obj.selection_list, function(o) { return o.acn_id; } );
                                if (list.length == 0) { return; }

                                var copy_shortcut = {}; var map_acn = {};

                                for (var i = 0; i < list.length; i++) {
                                    var volume_id = list[i];
                                    if (volume_id == -1) { 
                                        continue; /* ignore magic pre-cat volume */
                                    }
                                    if (! map_acn[volume_id]) {
                                        map_acn[ volume_id ] = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ volume_id ]);
                                    }
                                    var call_number = map_acn[volume_id];
                                    var record_id = call_number.record();
                                    var ou_id = call_number.owning_lib();
                                    var label = call_number.label();
                                    var acnc_id = typeof call_number.label_class() == 'object'
                                        ? call_number.label_class().id()
                                        : call_number.label_class();
                                    var acnp_id = typeof call_number.prefix() == 'object'
                                        ? call_number.prefix().id()
                                        : call_number.prefix();
                                    var acns_id = typeof call_number.suffix() == 'object'
                                        ? call_number.suffix().id()
                                        : call_number.suffix();
                                    var callnumber_composite_key = acnc_id + ':' + acnp_id + ':' + label + ':' + acns_id;
                                    if (!copy_shortcut[record_id]) {
                                        copy_shortcut[record_id] = {};
                                    }
                                    if (!copy_shortcut[record_id][ou_id]) {
                                        copy_shortcut[record_id][ou_id] = {};
                                    }
                                    copy_shortcut[record_id][ou_id][ callnumber_composite_key ] = volume_id;

                                }

                                for (var r in copy_shortcut) {

                                    /* quick fix */  /* what was this fixing? */
                                    list = []; for (var i in copy_shortcut[r]) { list.push( i ); }

                                    var edit = 0;
                                    try {
                                        edit = obj.network.request(
                                            api.PERM_MULTI_ORG_CHECK.app,
                                            api.PERM_MULTI_ORG_CHECK.method,
                                            [ 
                                                ses(), 
                                                obj.data.list.au[0].id(), 
                                                list,
                                                [ 'CREATE_COPY' ]
                                            ]
                                        ).length == 0 ? 1 : 0;
                                    } catch(E) {
                                        obj.error.sdump('D_ERROR','batch permission check: ' + E);
                                    }
    
                                    if (edit==0) { 
                                        return; // no read-only view for this interface
                                    }
    
                                    var title = document.getElementById('circStrings').getFormattedString('staff.circ.copy_status.add_items.title', [r]);
    
                                    var url;
                                    var unified_interface = String( obj.data.hash.aous['ui.unified_volume_copy_editor'] ) == 'true';
                                    if (unified_interface) {
                                        var horizontal_interface = String( obj.data.hash.aous['ui.cat.volume_copy_editor.horizontal'] ) == 'true';
                                        url = window.xulG.url_prefix( horizontal_interface ? 'XUL_VOLUME_COPY_CREATOR_HORIZONTAL' : 'XUL_VOLUME_COPY_CREATOR' );
                                    } else {
                                        url = window.xulG.url_prefix('XUL_VOLUME_COPY_CREATOR_ORIGINAL');
                                    }

                                    var w = xulG.new_tab(
                                        url,
                                        { 'tab_name' : title },
                                        { 'doc_id' : r, 'ou_ids' : list, 'copy_shortcut' : copy_shortcut[r] }
                                    );
                                }

                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('copy status -> add copies',E);
                            }
                        }

                    ],
                    'cmd_delete_items' : [
                        ['command'],
                        function() {
                            try {

                                JSAN.use('util.functional');

                                var list = util.functional.map_list( obj.selection_list, function(o) { return o.copy_id; } );

                                var copies = util.functional.map_list(
                                    list,
                                    function (acp_id) {
                                        return obj.network.simple_request('FM_ACP_RETRIEVE',[acp_id]);
                                    }
                                );

                                for (var i = 0; i < copies.length; i++) {
                                    copies[i].ischanged(1);
                                    copies[i].isdeleted(1);
                                }

                                if (! window.confirm(document.getElementById('circStrings').getFormattedString('staff.circ.copy_status.del_items.confirm', [util.functional.map_list( copies, function(o) { return o.barcode(); }).join(", ")]))) {
                                    return;
                                }

                                var robj = obj.network.simple_request('FM_ACP_FLESHED_BATCH_UPDATE',[ ses(), copies, true]);
                                var robj = obj.network.simple_request(
                                    'FM_ACP_FLESHED_BATCH_UPDATE', 
                                    [ ses(), copies, true ], 
                                    null,
                                    {
                                        'title' : document.getElementById('circStrings').getString('staff.circ.copy_status.del_items.title'),
                                        'overridable_events' : [
                                            1208 /* TITLE_LAST_COPY */,
                                            1227 /* COPY_DELETE_WARNING */
                                        ]
                                    }
                                );
    
                                if (typeof robj.ilsevent != 'undefined') {
                                    switch(Number(robj.ilsevent)) {
                                        case 1208 /* TITLE_LAST_COPY */:
                                        case 1227 /* COPY_DELETE_WARNING */:
                                        case 5000 /* PERM_DENIED */:
                                        break;
                                        default:
                                            obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.copy_status.del_items.success.error'), robj);
                                        break;
                                    }
                                } else { alert(document.getElementById('circStrings').getString('staff.circ.copy_status.del_items.success')); }

                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('copy status -> delete items',E);
                            }
                        }
                    ],
                    'cmd_transfer_items' : [
                        ['command'],
                        function() {
                                try {
                                    obj.data.stash_retrieve();
                                    if (!obj.data.marked_volume) {
                                        alert(document.getElementById('circStrings').getString('staff.circ.copy_status.transfer_items.mark_destination'));
                                        return;
                                    }
                                    
                                    JSAN.use('util.functional');

                                    var list = util.functional.map_list( obj.selection_list, function(o) { return o.copy_id; } );

                                    var volume = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ obj.data.marked_volume ]);

                                    JSAN.use('cat.util'); cat.util.transfer_copies( { 
                                        'copy_ids' : list, 
                                        'docid' : volume.record(),
                                        'volume_label' : volume.label(),
                                        'owning_lib' : volume.owning_lib()
                                    } );

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.copy_status.transfer_items.problem'), E);
                                }
                            }

                    ],
                    'cmd_add_volumes' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.functional');
                                var list = util.functional.map_list( obj.selection_list, function(o) { return o.acn_id; } );
                                if (list.length == 0) { return; }

                                var aou_hash = {}; var map_acn = {};

                                for (var i = 0; i < list.length; i++) {
                                    var volume_id = list[i];
                                    if (volume_id == -1) {
                                        continue; /* ignore magic pre-cat volume */
                                    }
                                    if (! map_acn[volume_id]) {
                                        map_acn[ volume_id ] = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ volume_id ]);
                                    }
                                    var record_id = map_acn[ volume_id ].record();
                                    var ou_id = map_acn[ volume_id ].owning_lib();
                                    var label = map_acn[ volume_id ].label();
                                    if (!aou_hash[record_id]) aou_hash[record_id] = {};
                                    aou_hash[record_id][ou_id] = 1;

                                }

                                for (var r in aou_hash) {

                                    list = []; for (var org in aou_hash[r]) list.push(org);

                                    var edit = 0;
                                    try {
                                        edit = obj.network.request(
                                            api.PERM_MULTI_ORG_CHECK.app,
                                            api.PERM_MULTI_ORG_CHECK.method,
                                            [ 
                                                ses(), 
                                                obj.data.list.au[0].id(), 
                                                list,
                                                [ 'CREATE_VOLUME', 'CREATE_COPY' ]
                                            ]
                                        ).length == 0 ? 1 : 0;
                                    } catch(E) {
                                        obj.error.sdump('D_ERROR','batch permission check: ' + E);
                                    }

                                    if (edit==0) {
                                        alert(document.getElementById('circStrings').getString('staff.circ.copy_status.add_volumes.perm_failure'));
                                        return; // no read-only view for this interface
                                    }

                                    var title = document.getElementById('circStrings').getFormattedString('staff.circ.copy_status.add_volumes.title', [r]);

                                    var url;
                                    var unified_interface = String( obj.data.hash.aous['ui.unified_volume_copy_editor'] ) == 'true';
                                    if (unified_interface) {
                                        var horizontal_interface = String( obj.data.hash.aous['ui.cat.volume_copy_editor.horizontal'] ) == 'true';
                                        url = window.xulG.url_prefix( horizontal_interface ? 'XUL_VOLUME_COPY_CREATOR_HORIZONTAL' : 'XUL_VOLUME_COPY_CREATOR' );
                                    } else {
                                        url = window.xulG.url_prefix('XUL_VOLUME_COPY_CREATOR_ORIGINAL');
                                    }

                                    var w = xulG.new_tab(
                                        url,
                                        { 'tab_name' : title },
                                        { 'doc_id' : r, 'ou_ids' : list }
                                    );

                                }

                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('copy status -> add volumes',E);
                            }
                        }

                    ],

                    'sel_vol_copy_edit' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.functional');

                                var list = util.functional.map_list( obj.selection_list, function(o) { return o.copy_id; } );

                                var copies = obj.network.simple_request('FM_ACP_FLESHED_BATCH_RETRIEVE',[list]);

                                if (list.length == 0) { return; }

                                var map_acn = {};
                                var rec_copy_map = {};

                                for (var i = 0; i < copies.length; i++) {
                                    var volume_id = copies[i].call_number();
                                    if (! map_acn[volume_id]) {
                                        map_acn[ volume_id ] = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ volume_id ]);
                                    }
                                    copies[i].call_number( map_acn[ volume_id ] );
                                    var record_id = map_acn[ volume_id ].record();
                                    if (!rec_copy_map[record_id]) {
                                        rec_copy_map[record_id] = [];
                                    }
                                    rec_copy_map[record_id].push( copies[i] );
                                }

                                var timeout = 0; // FIXME: stagger invocation of each tab or they'll break for someone unknown reason
                                var vol_item_creator = function(items) {
                                    setTimeout(
                                        function() {
                                            xulG.volume_item_creator({ 'existing_copies' : items });
                                        }, timeout
                                    );
                                    timeout += 1000;
                                }
                                for (var r in rec_copy_map) {
                                    if (r == -1) { /* no unified interface for pre-cats */ 
                                        cat.util.spawn_copy_editor( { 'copy_ids' : rec_copy_map[r], 'edit' : 1 } );
                                    } else {
                                        vol_item_creator( rec_copy_map[r] );
                                    }
                                }

                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('copy status -> edit items/volumes per bib',E);
                            }
                        }
                    ],

                    'cmd_edit_volumes' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.functional');
                                var list = util.functional.map_list( obj.selection_list, function(o) { return o.acn_id; } );
                                if (list.length == 0) { return; }

                                var volumes = []; var seen = {};

                                for (var i = 0; i < list.length; i++) {
                                    var volume_id = list[i];
                                    if (volume_id == -1) {
                                        continue; /* ignore magic pre-cat volume */
                                    }
                                    if (! seen[volume_id]) {
                                        seen[volume_id] = 1;
                                        var volume = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ volume_id ]);
                                        if (volume && typeof volume.ilsevent == 'undefined') {
                                            volumes.push( volume );
                                        }
                                    }
                                }

                                JSAN.use('cat.util'); cat.util.batch_edit_volumes( volumes );

                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('Copy Status -> Volume Edit',E);
                            }
                        }

                    ],
                    'cmd_delete_volumes' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.functional');
                                var list = util.functional.map_list( obj.selection_list, function(o) { return o.acn_id; } );
                                if (list.length == 0) { return; }

                                var map_acn = {};

                                for (var i = 0; i < list.length; i++) {
                                    var volume_id = list[i];
                                    if (volume_id == -1) {
                                        continue; /* ignore magic pre-cat volume */
                                    }
                                    if (! map_acn[volume_id]) {
                                        map_acn[ volume_id ] = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ volume_id ]);
                                    }
                                }

                                list = [];
                                for (var v in map_acn) {
                                    list.push( map_acn[v] );
                                }

                                var confirm_prompt;
                                if (list.length == 1) {
                                    confirm_prompt = document.getElementById('circStrings').getString('staff.circ.copy_status.delete_volumes.singular');
                                } else {
                                    confirm_prompt = document.getElementById('circStrings').getString('staff.circ.copy_status.delete_volumes.plural');
                                }    

                                var r = obj.error.yns_alert(
                                    confirm_prompt,
                                    document.getElementById('circStrings').getString('staff.circ.copy_status.delete_volumes.title'),
                                    document.getElementById('circStrings').getString('staff.circ.copy_status.delete_volumes.delete'),
                                    document.getElementById('circStrings').getString('staff.circ.copy_status.delete_volumes.cancel'),
                                    null,
                                    document.getElementById('circStrings').getString('staff.circ.confirm')
                                );

                                if (r == 0) {
                                    for (var i = 0; i < list.length; i++) {
                                        list[i].isdeleted('1');
                                    }
                                    var params = {};
                                    loop: while(true) {
                                        var robj = obj.network.simple_request(
                                            'FM_ACN_TREE_UPDATE', 
                                            [ ses(), list, true, params ],
                                            null,
                                            {
                                                'title' : document.getElementById('circStrings').getString('staff.circ.copy_status.delete_volumes.override'),
                                                'overridable_events' : [
                                                    1208 /* TITLE_LAST_COPY */,
                                                    1227 /* COPY_DELETE_WARNING */
                                                ]
                                            }
                                        );
                                        if (robj == null) throw(robj);
                                        if (typeof robj.ilsevent != 'undefined') {
                                            if (robj.ilsevent == 1206 /* VOLUME_NOT_EMPTY */) {
                                                var r2 = obj.error.yns_alert(
                                                    document.getElementById('circStrings').getString('staff.circ.copy_status.delete_volumes.delete_copies'),
                                                    document.getElementById('circStrings').getString('staff.circ.copy_status.delete_volumes.title'),
                                                    document.getElementById('circStrings').getString('staff.circ.copy_status.delete_volumes.delete_copies.confirm'),
                                                    document.getElementById('circStrings').getString('staff.circ.copy_status.delete_volumes.delete_copies.cancel'),
                                                    null,
                                                    document.getElementById('commonStrings').getString('common.confirm')
                                                );
                                                if (r2 == 0) { // delete vols and copies
                                                    params.force_delete_copies = true;
                                                    continue loop;
                                                }
                                            } else {
                                                if (typeof robj.ilsevent != 'undefined') {
                                                    if (
                                                        (robj.ilsevent != 0)
                                                        && (robj.ilsevent != 1227 /* COPY_DELETE_WARNING */)
                                                        && (robj.ilsevent != 1208 /* TITLE_LAST_COPY */)
                                                        && (robj.ilsevent != 5000 /* PERM_DENIED */)
                                                    ) {
                                                        throw(robj);
                                                    }
                                                }
                                            }
                                        }
                                        break loop;
                                    }
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('copy status -> delete volumes',E);
                            }

                        }

                    ],
                    'cmd_mark_volume' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.functional');
                                var list = util.functional.map_list( obj.selection_list, function(o) { return o.acn_id; } );

                                if (list.length == 1) {
                                    obj.data.marked_volume = list[0];
                                    obj.data.stash('marked_volume');
                                    alert(document.getElementById('circStrings').getString('staff.circ.copy_status.mark_volume.status'));
                                } else {
                                    obj.error.yns_alert(
                                        document.getElementById('circStrings').getString('staff.circ.copy_status.mark_volume.prompt'),
                                        document.getElementById('circStrings').getString('staff.circ.copy_status.mark_volume.title'),
                                        document.getElementById('circStrings').getString('staff.circ.copy_status.ok'),
                                        null,
                                        null,
                                        document.getElementById('circStrings').getString('staff.circ.confirm')
                                    );
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('copy status -> mark volume',E);
                            }
                        }
                    ],
                    'cmd_mark_library' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.functional');
                                var list = util.functional.map_list( obj.selection_list, function(o) { return o.acn_id; } );

                                if (list.length == 1) {
                                    var v = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[list[0]]);
                                    var owning_lib = v.owning_lib();
                                    if (typeof owning_lib == 'object') {
                                        owning_lib = owning_lib.id();
                                    }

                                    obj.data.marked_library = { 'lib' : owning_lib, 'docid' : v.record() };
                                    obj.data.stash('marked_library');
                                    alert(document.getElementById('circStrings').getString('staff.circ.copy_status.mark_library'));
                                } else {
                                    obj.error.yns_alert(
                                        document.getElementById('circStrings').getString('staff.circ.copy_status.mark_library.limit_one'),
                                        document.getElementById('circStrings').getString('staff.circ.copy_status.mark_library.limit_one.title'),
                                        document.getElementById('circStrings').getString('staff.circ.copy_status.ok'),
                                        null,
                                        null,
                                        document.getElementById('circStrings').getString('staff.circ.confirm')
                                    );
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('copy status -> mark library',E);
                            }
                        }
                    ],
                    'cmd_transfer_volume' : [
                        ['command'],
                        function() {
                            try {
                                    obj.data.stash_retrieve();
                                    if (!obj.data.marked_library) {
                                        alert(document.getElementById('circStrings').getString('staff.circ.copy_status.transfer_volume.none'));
                                        return;
                                    }
                                    
                                    JSAN.use('util.functional');

                                    var list = util.functional.map_list( obj.selection_list, function(o) { return o.acn_id; } );
                                    if (list.length == 0) { return; }

                                    var map_acn = {};

                                    for (var i = 0; i < list.length; i++) {
                                        var volume_id = list[i];
                                        if (volume_id == -1) {
                                            continue; /* ignore magic pre-cat volume */
                                        }
                                        if (! map_acn[volume_id]) {
                                            map_acn[ volume_id ] = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ volume_id ]);
                                        }
                                    }

                                    list = [];
                                    for (v in map_acn) {
                                        list.push(map_acn[v]);
                                    }

                                    var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: auto">';
                                    xml += '<description>';

                                    var vols = util.functional.map_list(list,
                                        function (o) {
                                            return o.label();
                                        }
                                    ).join(", ");

                                    var volume_list = document.getElementById('circStrings').getFormattedString('staff.circ.copy_status.transfer_volume.confirm', 
                                        [vols, obj.data.hash.aou[ obj.data.marked_library.lib ].shortname()]);

                                    xml += volume_list;
                                    xml += '</description>';
                                    xml += '<hbox><button label="';
                                    xml += document.getElementById('circStrings').getString('staff.circ.copy_status.transfer_volume.transfer.label');
                                    xml += '" name="fancy_submit"/>';
                                    xml += '<button label="';
                                    xml += document.getElementById('circStrings').getString('staff.circ.copy_status.transfer_volume.cancel.label');
                                    xml += '" accesskey="';
                                    xml += document.getElementById('circStrings').getString('staff.circ.copy_status.transfer_volume.cancel.accesskey');
                                    xml += '" name="fancy_cancel"/></hbox>';
                                    xml += '<iframe style="overflow: scroll" flex="1" src="' + urls.XUL_BIB_BRIEF + '?docid=' + obj.data.marked_library.docid + '" oils_force_external="true"/>';
                                    xml += '</vbox>';
                                    JSAN.use('OpenILS.data');
                                    //var data = new OpenILS.data(); data.init({'via':'stash'});
                                    //data.temp_transfer = xml; data.stash('temp_transfer');
                                    JSAN.use('util.window'); var win = new util.window();
                                    var fancy_prompt_data = win.open(
                                        urls.XUL_FANCY_PROMPT,
                                        //+ '?xml_in_stash=temp_transfer'
                                        //+ '&title=' + window.escape('Volume Transfer'),
                                        'fancy_prompt', 'chrome,resizable,modal,width=500,height=300',
                                        { 'xml' : xml, 'title' : document.getElementById('circStrings').getString('staff.circ.copy_status.transfer_volume.title') }
                                    );
                                
                                    if (fancy_prompt_data.fancy_status == 'incomplete') { 
                                        alert(document.getElementById('circStrings').getString('staff.circ.copy_status.transfer_volume.aborted'));
                                        return;
                                    }

                                    var robj = obj.network.simple_request(
                                        'FM_ACN_TRANSFER', 
                                        [ ses(), { 'docid' : obj.data.marked_library.docid, 'lib' : obj.data.marked_library.lib, 'volumes' : util.functional.map_list( list, function(o) { return o.id(); }) } ],
                                        null,
                                        {
                                            'title' : document.getElementById('circStrings').getString('staff.circ.copy_status.transfer_volume.override_failure'),
                                            'overridable_events' : [
                                                1208 /* TITLE_LAST_COPY */,
                                                1219 /* COPY_REMOTE_CIRC_LIB */
                                            ]
                                        }
                                    );

                                    if (typeof robj.ilsevent != 'undefined') {
                                        if (robj.ilsevent == 1221 /* ORG_CANNOT_HAVE_VOLS */) {
                                            alert(document.getElementById('circStrings').getString('staff.circ.copy_status.transfer_volume.cannot_have_vols'));
                                        } else {
                                            throw(robj);
                                        }
                                    } else {
                                        alert(document.getElementById('circStrings').getString('staff.circ.copy_status.transfer_volume.success'));
                                    }

                            } catch(E) {
                                obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.copy_status.transfer_volume.error'),E);
                            }
                        }

                    ]
                }
            }
        );
        this.controller.render();
        this.controller.view.copy_status_barcode_entry_textbox.focus();

        JSAN.use('util.browser');
        obj.browser = new util.browser();
        obj.browser.init(
            {
                'url' : 'alternate_copy_summary.xul',
                'push_xulG' : true,
                'alt_print' : false,
                'browser_id' : 'copy_status_frame',
                'passthru_content_params' : xulG,
            }
        );

    },

    'selected_one_unique_owning_lib': function () {
        JSAN.use('util.functional');
        var list = util.functional.map_list(
            this.selection_list,
            function(o) { return o.owning_lib; }
        );
        return util.functional.unique_list_values(list).length == 1;
    },

    'test_barcode' : function(bc) {
        var obj = this;
        var x = document.getElementById('strict_barcode');
        if (x && x.checked != true) { return true; }
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

    'copy_status' : function(barcode,refresh) {
        var obj = this;
        try {
            try { document.getElementById('last_scanned').setAttribute('value',''); } catch(E) {}
            if (!barcode) {
                // No barcode provided = get barcode
                barcode = obj.controller.view.copy_status_barcode_entry_textbox.value;
                // Complete the barcode - just items
                var barcode_object = xulG.get_barcode(window, 'asset', barcode);
                // user_false is user said "None of the above" - Abort before other errors/prompts can result
                if(barcode_object == "user_false") return;
                // Got a barcode and no error? Use the barcode. Otherwise, fall through with entered barcode.
                if(barcode_object && typeof barcode_object.ilsevent == 'undefined')
                    barcode = barcode_object.barcode;
            }
            if (!barcode) { return; }
            if (barcode) {
                if ( obj.test_barcode(barcode) ) { /* good */ } else { /* bad */ return; }
            }
            JSAN.use('circ.util');
            function handle_req(req) {
                try {
                    var details = req.getResultObject();
                    if (details == null) {
                        throw(document.getElementById('circStrings').getString('staff.circ.copy_status.status.null_result'));
                    } else if (details.ilsevent) {
                        switch(Number(details.ilsevent)) {
                            case -1: 
                                obj.error.standard_network_error_alert(); 
                                obj.controller.view.copy_status_barcode_entry_textbox.select();
                                obj.controller.view.copy_status_barcode_entry_textbox.focus();
                                return;
                            break;
                            case 1502 /* ASSET_COPY_NOT_FOUND */ :
                                try { document.getElementById('last_scanned').setAttribute('value', document.getElementById('circStrings').getFormattedString('staff.circ.copy_status.status.copy_not_found', [barcode])); } catch(E) {}
                                obj.error.yns_alert(
                                    document.getElementById('circStrings').getFormattedString('staff.circ.copy_status.status.copy_not_found', [barcode]),
                                    document.getElementById('circStrings').getString('staff.circ.copy_status.status.not_cataloged'),
                                    document.getElementById('circStrings').getString('staff.circ.copy_status.ok'),
                                    null,
                                    null,
                                    document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                                );
                                obj.controller.view.copy_status_barcode_entry_textbox.select();
                                obj.controller.view.copy_status_barcode_entry_textbox.focus();
                                return;
                            break;
                            default: 
                                throw(details); 
                            break;
                        }
                    }
                    var msg = details.copy.barcode() + ' -- ';
                    if (details.copy.call_number() == -1) {
                        msg += document.getElementById('circStrings').getString('staff.circ.copy_status.status.pre_cat') + '  ';
                    }
                    if (details.hold) {
                        msg += document.getElementById('circStrings').getString('staff.circ.copy_status.status.hold') + '  ';
                    }
                    if (details.transit) {
                        msg += document.getElementById('circStrings').getString('staff.circ.copy_status.status.transit') + '  ';
                    }
                    if (details.circ && ! details.circ.checkin_time()) {
                        msg += document.getElementById('circStrings').getString('staff.circ.copy_status.status.circ') + '  ';
                    }
                    try { document.getElementById('last_scanned').setAttribute('value',msg); } catch(E) {}
                    if (document.getElementById('trim_list')) {
                        var x = document.getElementById('trim_list');
                        if (x.checked) { obj.list.trim_list = 20; } else { obj.list.trim_list = null; }
                    }
                    var params = {
                        'retrieve_id' : js2JSON( 
                            { 
                                'renewable' : details.circ ? 't' : 'f', 
                                'copy_id' : details.copy.id(), 
                                'acn_id' : details.volume ? details.volume.id() : -1, 
                                'owning_lib' : details.volume ? details.volume.owning_lib() : -1, 
                                'barcode' : barcode, 
                                'doc_id' : details.mvr ? details.mvr.doc_id() : null  
                            } 
                        ),
                        'row' : {
                            'my' : {
                                'mvr' : details.mvr,
                                'acp' : details.copy,
                                'acn' : details.volume,
                                'atc' : details.transit,
                                'circ' : details.circ,
                                'ahr' : details.hold
                            }
                        },
                        'to_top' : true
                    };
                    if (!refresh) {
                        var nparams = obj.list.append(params);
                        if (!document.getElementById('trim_list').checked) {
                            if (typeof obj.list_copyid_map[details.copy.id()] == 'undefined') obj.list_copyid_map[details.copy.id()] =[];
                            obj.list_copyid_map[details.copy.id()].push(nparams);
                        }
                    } else {
                        if (!document.getElementById('trim_list').checked) {
                            if (typeof obj.list_copyid_map[details.copy.id()] != 'undefined') {
                                for (var i = 0; i < obj.list_copyid_map[details.copy.id()].length; i++) {
                                    if (typeof obj.list_copyid_map[details.copy.id()][i] == 'undefined') {
                                        obj.list.append(params);
                                    } else {
                                        params.treeitem_node = obj.list_copyid_map[details.copy.id()][i].treeitem_node;
                                        obj.list.refresh_row(params);
                                    }
                                }
                            } else {
                                obj.list.append(params);
                            }
                        } else {
                            obj.list.append(params);
                        }
                    }
                } catch(E) {
                    obj.error.standard_unexpected_error_alert('barcode = ' + barcode,E);
                }
            }
            var result = obj.network.simple_request('FM_ACP_DETAILS_VIA_BARCODE.authoritative', [ ses(), barcode ]);
            handle_req({'getResultObject':function(){return result;}}); // used to be async
            if (result.copy && document.getElementById('deck').selectedIndex == 1) {
                var f = obj.browser.get_content();
                xulG.barcode = result.copy.barcode(); // FIXME: We could pass the already-fetched data, but need to figure out how to manage that and honor Trim List, the whole point of which is to limit memory consumption
                if (f) {
                    if (!xulG.from_item_details_new) {
                        /* We don't want to call load_item() in this case
                         * because we're going to call copy_status() later
                         * (which gets action menus populated, unlike
                         * load_item()). */
                        f.xulG = xulG;
                        f.load_item();
                    }
                } else {
                    alert('hrmm');
                }
            }
            obj.controller.view.copy_status_barcode_entry_textbox.value = '';
            obj.controller.view.copy_status_barcode_entry_textbox.focus();
            return result; // In some cases we're going to want to save this
        } catch(E) {
            obj.error.standard_unexpected_error_alert('barcode = ' + barcode,E);
            obj.controller.view.copy_status_barcode_entry_textbox.select();
            obj.controller.view.copy_status_barcode_entry_textbox.focus();
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

    },

}

dump('exiting circ.copy_status.js\n');
