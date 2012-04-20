dump('entering patron.holds.js\n');

function $(id) { return document.getElementById(id); }

if (typeof patron == 'undefined') patron = {};
patron.holds = function (params) {

    JSAN.use('util.error'); this.error = new util.error();
    JSAN.use('util.network'); this.network = new util.network();
    JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

patron.holds.prototype = {

    'hold_interface_type' : null,

    'pull_from_shelf_interface' : {
        '_default' : { 'limit' : 100, 'offset' : 0 },
        'current' : { 'limit' : 100, 'offset' : 0 }
    },

    'filter_lib' : null,

    'hold_subscription_map' : {},
    'hold_part_map' : {},

    'expired' : false,
    'post_clear_shelf_hold_action_map' : {},

    'retrieve_ids' : [],

    'holds_map' : {},

    'flatten_copy' : function(hold) {
        try { if ( hold.current_copy() && typeof hold.current_copy() == 'object') hold.current_copy( hold.current_copy().id() ); } catch(E) { alert('FIXME: Error flattening hold before hold update: ' + E); }
        return hold;
    },

    'init' : function( params ) {

        var obj = this;

        dojo.require("openils.Util");

        obj.patron_id = params['patron_id'];
        obj.patron_barcode = params['patron_barcode'];
        obj.docid = params['docid'];
        obj.shelf = params['shelf'];
        obj.tree_id = params['tree_id'];

        obj.determine_hold_interface_type();

        var progressmeter = document.getElementById('progress');

        JSAN.use('circ.util');
        var columns = circ.util.hold_columns(
            {
                'title' : { 'hidden' : false, 'flex' : '3' },
                'request_time' : { 'hidden' : false },
                'pickup_lib_shortname' : { 'hidden' : false },
                'hold_type' : { 'hidden' : false },
                'current_copy' : { 'hidden' : false },
                'capture_time' : { 'hidden' : false },
                'notify_time' : { 'hidden' : false },
                'notify_count' : { 'hidden' : false },
                'cancel_cause' : { 'hidden' : ! ( obj.data.hash.aous['circ.holds.canceled.display_count'] || obj.data.hash.aous['circ.holds.canceled.display_age'] ) },
                'cancel_note' : { 'hidden' :  ! ( obj.data.hash.aous['circ.holds.canceled.display_count'] || obj.data.hash.aous['circ.holds.canceled.display_age'] ) },
                'cancel_time' : { 'hidden' :  ! ( obj.data.hash.aous['circ.holds.canceled.display_count'] || obj.data.hash.aous['circ.holds.canceled.display_age'] ) },
                'post_clear_shelf_action' : { 'hidden' : obj.shelf ? false : true }
            }
        );

        JSAN.use('util.list'); obj.list = new util.list( obj.tree_id || 'holds_list');
        obj.list.init(
            {
                'columns_saved_under' : 'holds_' + obj.hold_interface_type,
                'columns' : columns.concat(
                    obj.list.fm_columns('acp', {
                        '*' : { 'expanded_label' : true, 'hidden' : true },
                        // example of unhiding some columns by default
                        // 'acp_circ_modifier' : { 'hidden' : false }
                    })
                ),
                'retrieve_row' : function(params) {
                    var row = params.row;
                    try {
                        obj.network.simple_request('FM_AHR_BLOB_RETRIEVE.authoritative', [ ses(), row.my.hold_id ],
                            function(blob_req) {
                                try {
                                    var blob = blob_req.getResultObject();
                                    if (typeof blob.ilsevent != 'undefined') throw(blob);
                                    row.my.ahr = blob.hold;
                                    row.my.status = blob.status;
                                    row.my.ahr.status( blob.status );
                                    row.my.acp = blob.copy;
                                    row.my.acn = blob.volume;
                                    row.my.mvr = blob.mvr;
                                    row.my.part = blob.part;
                                    if (blob.part) {
                                        obj.hold_part_map[ row.my.hold_id ] = row.my.part;
                                    }
                                    row.my.issuance = blob.issuance;
                                    if (blob.issuance) {
                                        row.my.subscription = blob.issuance.subscription();
                                        obj.hold_subscription_map[ row.my.hold_id ] = row.my.subscription;
                                    }
                                    row.my.patron_family_name = blob.patron_last;
                                    row.my.patron_first_given_name = blob.patron_first;
                                    row.my.patron_barcode = blob.patron_barcode;
                                    row.my.patron_alias = blob.patron_alias;
                                    row.my.total_holds = blob.total_holds;
                                    row.my.queue_position = blob.queue_position;
                                    row.my.potential_copies = blob.potential_copies;
                                    row.my.estimated_wait = blob.estimated_wait;
                                    row.my.ahrn_count = blob.hold.notes().length;

                                    var copy_id = row.my.ahr.current_copy();
                                    if (typeof copy_id == 'object') {
                                        if (copy_id == null) {
                                            if (typeof row.my.acp == 'object' && row.my.acp != null) copy_id = row.my.acp.id();
                                        } else {
                                            copy_id = copy_id.id();
                                        }
                                    } else {
                                        copy_id = row.my.acp.id();
                                    }

                                    obj.holds_map[ row.my.ahr.id() ] = blob;
                                    params.treeitem_node.setAttribute('retrieve_id',
                                        js2JSON({
                                            'copy_id':copy_id,
                                            'barcode':row.my.acp ? row.my.acp.barcode() : null,
                                            'id':row.my.ahr.id(),
                                            'type':row.my.ahr.hold_type(),
                                            'target':row.my.ahr.target(),
                                            'usr':row.my.ahr.usr()
                                        })
                                    );
                                    if (typeof params.on_retrieve == 'function') { params.on_retrieve(row); }

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.holds.init.hold_num_error', [row.my.hold_id]), E);
                                }
                            }
                        );
                    } catch(E) {
                        obj.error.sdump('D_ERROR','retrieve_row: ' + E );
                    }
                    return row;
                },
                'on_select' : function(ev) {
                    JSAN.use('util.functional');
                    var sel = obj.list.retrieve_selection();
                    obj.controller.view.sel_clip.setAttribute('disabled',sel.length < 1);
                    obj.retrieve_ids = util.functional.map_list(
                        sel,
                        function(o) { return JSON2js( o.getAttribute('retrieve_id') ); }
                    );
                    if (obj.retrieve_ids.length > 0) {
                        obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','false');
                        obj.controller.view.sel_mark_items_missing.setAttribute('disabled','false');
                        obj.controller.view.sel_copy_details.setAttribute('disabled','false');
                        obj.controller.view.sel_patron.setAttribute('disabled','false');
                        obj.controller.view.cmd_retrieve_patron.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_edit_pickup_lib.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_edit_desire_mint_condition.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_edit_phone_notify.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_edit_email_notify.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_edit_selection_depth.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_edit_expire_time.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_edit_shelf_expire_time.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_edit_thaw_date.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_edit_request_date.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_activate.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_suspend.setAttribute('disabled','false');
                        obj.controller.view.cmd_alt_view.setAttribute('rendering_rows','false');
                        if (obj.controller.view.cmd_alt_view.getAttribute('ready')=='true') {
                            obj.controller.view.cmd_alt_view.setAttribute('disabled','false');
                        }
                        obj.controller.view.cmd_holds_retarget.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_cancel.setAttribute('disabled','false');
                        obj.controller.view.cmd_holds_uncancel.setAttribute('disabled','false');
                        obj.controller.view.cmd_show_catalog.setAttribute('disabled','false');
                    } else {
                        obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','true');
                        obj.controller.view.sel_mark_items_missing.setAttribute('disabled','true');
                        obj.controller.view.sel_copy_details.setAttribute('disabled','true');
                        obj.controller.view.sel_patron.setAttribute('disabled','true');
                        obj.controller.view.cmd_retrieve_patron.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_edit_pickup_lib.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_edit_desire_mint_condition.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_edit_phone_notify.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_edit_email_notify.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_edit_selection_depth.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_edit_expire_time.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_edit_shelf_expire_time.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_edit_thaw_date.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_edit_request_date.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_activate.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_suspend.setAttribute('disabled','true');
                        obj.controller.view.cmd_alt_view.setAttribute('disabled','true');
                        obj.controller.view.cmd_alt_view.setAttribute('rendering_rows','true');
                        obj.controller.view.cmd_holds_retarget.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_cancel.setAttribute('disabled','true');
                        obj.controller.view.cmd_holds_uncancel.setAttribute('disabled','true');
                        obj.controller.view.cmd_show_catalog.setAttribute('disabled','true');
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
                        function() { obj.list.clipboard(); }
                    ],
                    'cmd_broken' : [
                        ['command'],
                        function() { alert($("commonStrings").getString('common.unimplemented')); }
                    ],
                    'sel_patron' : [
                        ['command'],
                        function() {
                            JSAN.use('circ.util');
                            circ.util.show_last_few_circs(obj.retrieve_ids);
                        }
                    ],
                    'alt_view_btn' : [
                        ['render'],
                        function(e) {
                            return function() {
                                e.setAttribute('label', document.getElementById("circStrings").getString('staff.circ.holds.alt_view.label'));
                                e.setAttribute('accesskey', document.getElementById("circStrings").getString('staff.circ.holds.alt_view.accesskey'));
                            };
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
                                    n.setAttribute('label', document.getElementById("circStrings").getString('staff.circ.holds.alt_view.label'));
                                    n.setAttribute('accesskey', document.getElementById("circStrings").getString('staff.circ.holds.alt_view.accesskey'));
                                    obj.controller.view.save_columns.setAttribute('disabled','false');
                                } else {
                                    document.getElementById('deck').selectedIndex = 1;
                                    n.setAttribute('toggle','1');
                                    n.setAttribute('label', document.getElementById("circStrings").getString('staff.circ.holds.list_view.label'));
                                    n.setAttribute('accesskey', document.getElementById("circStrings").getString('staff.circ.holds.list_view.accesskey'));
                                    netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
                                    if (obj.retrieve_ids.length == 0) return;
                                    var f = obj.browser.get_content();
                                    xulG.ahr_id = obj.retrieve_ids[0].id;
                                    xulG.blob = obj.holds_map[ xulG.ahr_id ];
                                    xulG.patron_rendered_elsewhere = (obj.hold_interface_type == 'patron');
                                    xulG.bib_rendered_elsewhere = (obj.hold_interface_type == 'record');
                                    f.xulG = xulG;
                                    f.xulG.clear_and_retrieve = function() { obj.clear_and_retrieve(); };
                                    f.fetch_and_render_all(true);
                                    obj.controller.view.save_columns.setAttribute('disabled','true');
                                }
                            } catch(E) {
                                alert('Error in holds.js, cmd_alt_view handler: ' + E);
                            }
                        },
                    ],
                    'cmd_cancelled_holds_view' : [
                        ['command'],
                        function(ev) {
                            document.getElementById('show_cancelled_deck').selectedIndex = 1;
                            /* For some reason attribute propogation on the <command> element isn't working with hidden */
                            document.getElementById('holds_cancel_btn').setAttribute('hidden','true');
                            document.getElementById('holds_uncancel_btn').setAttribute('hidden','false');
                            document.getElementById('holds_cancel_btn2').setAttribute('hidden','true');
                            document.getElementById('holds_uncancel_btn2').setAttribute('hidden','false');
                            obj.clear_and_retrieve();
                        }
                    ],
                    'cmd_uncancelled_holds_view' : [
                        ['command'],
                        function(ev) {
                            document.getElementById('show_cancelled_deck').selectedIndex = 0;
                            /* For some reason attribute propogation on the <command> element isn't working with hidden */
                            document.getElementById('holds_cancel_btn').setAttribute('hidden','false');
                            document.getElementById('holds_uncancel_btn').setAttribute('hidden','true');
                            document.getElementById('holds_cancel_btn2').setAttribute('hidden','false');
                            document.getElementById('holds_uncancel_btn2').setAttribute('hidden','true');
                            obj.clear_and_retrieve();
                        }
                    ],
                    'sel_mark_items_damaged' : [
                        ['command'],
                        function() {
                            JSAN.use('cat.util'); JSAN.use('util.functional');
                            cat.util.mark_item_damaged( util.functional.map_list( obj.retrieve_ids, function(o) { return o.copy_id; } ) );
                        }
                    ],
                    'sel_mark_items_missing' : [
                        ['command'],
                        function() {
                            JSAN.use('cat.util'); JSAN.use('util.functional');
                            cat.util.mark_item_missing( util.functional.map_list( obj.retrieve_ids, function(o) { return o.copy_id; } ) );
                        }
                    ],
                    'sel_copy_details' : [
                        ['command'],
                        function() {
                            JSAN.use('circ.util');
                            circ.util.item_details_new(
                                util.functional.map_list(
                                    obj.retrieve_ids,
                                    function(o) { return o.barcode; }
                                )
                            );
                        }
                    ],
                    'cmd_holds_print_full' : [
                        ['command'],
                        function() {
                            var x_print_full_pull_list = document.getElementById('print_full_btn');
                            try {
                                if (progressmeter) {
                                    progressmeter.mode = 'undetermined';
                                    progressmeter.hidden = false;
                                    x_print_full_pull_list.disabled = true;
                                }
                                JSAN.use('util.print');
                                var print = new util.print('default');
                                var robj = fieldmapper.standardRequest(
                                    [ api.HTML_HOLD_PULL_LIST.app, api.HTML_HOLD_PULL_LIST.method ],
                                    {   async: false,
                                        timeout: 180,
                                        params: [ses()],
                                    }
                                );
                                if (robj != null) {
                                    if (typeof robj.ilsevent != 'undefined') { throw(robj); }
                                    print.simple( robj.template_output().data() );
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('cmd_holds_print_full',E);
                            }
                            if (progressmeter) {
                                progressmeter.mode = 'determined';
                                progressmeter.hidden = true;
                                x_print_full_pull_list.disabled = false;
                            }
                        }
                    ],
                    'cmd_holds_print_alt' : [
                        ['command'],
                        function() {
                            try {
                                var content_params = {
                                    "session": ses(),
                                    "authtime": ses("authtime"),
                                    "no_xulG": false,
                                    "show_nav_buttons": true,
                                    "show_print_button": true
                                };
                                ["url_prefix", "new_tab", "set_tab",
                                    "close_tab", "new_patron_tab",
                                    "set_patron_tab", "volume_item_creator",
                                    "get_new_session",
                                    "holdings_maintenance_tab", "set_tab_name",
                                    "open_chrome_window", "url_prefix",
                                    "network_meter", "page_meter",
                                    "set_statusbar", "set_help_context"
                                ].forEach(function(k) {
                                    content_params[k] = xulG[k];
                                });

                                var loc = urls.XUL_BROWSER + "?url=" + window.escape(
                                    xulG.url_prefix("/opac/extras/circ/alt_holds_print.html").replace("http:","https:")
                                );
                                xulG.new_tab(
                                    loc, {
                                        "tab_name": "Printable Pull List", /* XXX i18n */
                                        "browser": false
                                    }, content_params
                                );
                            } catch (E) {
                                g.error.sdump("D_ERROR", E);
                            }
                        }
                    ],
                    'cmd_simplified_pull_list' : [
                        ['command'],
                        function() {
                            try {
                                var content_params = {
                                    "session": ses(),
                                    "authtime": ses("authtime"),
                                    "no_xulG": false,
                                    "show_nav_buttons": true,
                                    "show_print_button": true
                                };
                                ["url_prefix", "new_tab", "set_tab",
                                    "close_tab", "new_patron_tab",
                                    "set_patron_tab", "volume_item_creator",
                                    "get_new_session",
                                    "holdings_maintenance_tab", "set_tab_name",
                                    "open_chrome_window", "url_prefix",
                                    "network_meter", "page_meter",
                                    "set_statusbar", "set_help_context"
                                ].forEach(function(k) {
                                    content_params[k] = xulG[k];
                                });

                                var loc = urls.XUL_BROWSER + "?url=" + window.escape(
                                    xulG.url_prefix("/eg/circ/hold_pull_list").replace("http:","https:")
                                );
                                xulG.new_tab(
                                    loc, {
                                        "tab_name": "Simplified Pull List", /* XXX i18n */
                                        "browser": false,
                                        "show_print_button": false
                                    }, content_params
                                );
                            } catch (E) {
                                g.error.sdump("D_ERROR", E);
                            }
                        }
                    ],
                    'cmd_holds_print' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('patron.util');
                                var params = {
                                    'patron' : patron.util.retrieve_au_via_id(ses(),obj.patron_id)
                                };
                                switch(obj.hold_interface_type) {
                                    case 'patron':
                                        params.template = 'holds_for_patron';
                                    break;
                                    case 'record':
                                        params.template = 'holds_on_bib';
                                    break;
                                    case 'shelf':
                                        params.template = 'holds_shelf';
                                    break;
                                    case 'pull':
                                    default:
                                        params.template = 'holds_pull_list';
                                    break;
                                }
                                obj.list.print(params);
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('print 1',E);
                            }
                        }
                    ],
                    'cmd_csv_to_clipboard' : [ ['command'], function() { obj.list.dump_csv_to_clipboard(); } ],
                    'cmd_csv_to_printer' : [ ['command'], function() { obj.list.dump_csv_to_printer(); } ],
                    'cmd_csv_to_file' : [ ['command'], function() { obj.list.dump_csv_to_file( { 'defaultFileName' : 'holds.txt' } ); } ],

                    'cmd_holds_edit_selection_depth' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.widgets'); JSAN.use('util.functional');
                                var ws_type = obj.data.hash.aout[ obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ].ou_type() ];
                                var list = util.functional.map_list(
                                    util.functional.filter_list(
                                        obj.data.list.aout,
                                        function(o) {
                                            if (o.depth() > ws_type.depth()) return false;
                                            if (o.depth() < ws_type.depth()) return true;
                                            return (o.id() == ws_type.id());
                                        }
                                    ),
                                    function(o) {
                                        return [
                                            o.opac_label(),
                                            o.id(),
                                            false,
                                            ( o.depth() * 2),
                                        ];
                                    }
                                );
                                ml = util.widgets.make_menulist( list, obj.data.list.au[0].ws_ou() );
                                ml.setAttribute('id','selection');
                                ml.setAttribute('name','fancy_data');
                                var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                xml += '<description>' + $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.choose_hold_range') + '</description>';
                                xml += util.widgets.serialize_node(ml);
                                xml += '</vbox>';
                                var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                bot_xml += '<spacer flex="1"/><button label="'+ $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.done.label') +'"';
                                bot_xml += 'accesskey="'+ $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.done.accesskey') +'" name="fancy_submit"/>';
                                bot_xml += '<button label="'+ $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.cancel.label') +'"';
                                bot_xml += 'accesskey="'+ $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.cancel.accesskey') +'" name="fancy_cancel"/></hbox>';
                                netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
                                //obj.data.temp_mid = xml; obj.data.stash('temp_mid');
                                //obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
                                JSAN.use('util.window'); var win = new util.window();
                                var fancy_prompt_data = win.open(
                                    urls.XUL_FANCY_PROMPT,
                                    //+ '?xml_in_stash=temp_mid'
                                    //+ '&bottom_xml_in_stash=temp_bot'
                                    //+ '&title=' + window.escape('Choose a Pick Up Library'),
                                    'fancy_prompt', 'chrome,resizable,modal',
                                    { 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.choose_library') }
                                );
                                if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
                                var selection = fancy_prompt_data.selection;

                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg = '';
                                if(obj.retrieve_ids.length > 1) {
                                    msg = $("patronStrings").getformattedString('staff.patron.holds.holds_edit_selection_depth.modify_holds_message.plural', [hold_list.join(', '), obj.data.hash.aout[selection].opac_label()])
                                } else {
                                    msg = $("patronStrings").getformattedString('staff.patron.holds.holds_edit_selection_depth.modify_holds_message.singular', [hold_list.join(', '), obj.data.hash.aout[selection].opac_label()])
                                }

                                var r = obj.error.yns_alert(msg,
                                        $("patronStrings").getString('staff.patron.holds.holds_edit_selection_depth.modify_holds_title'),
                                        $("commonStrings").getString('common.yes'),
                                        $("commonStrings").getString('common.no'),
                                        null,
                                        $("commonStrings").getString('common.check_to_confirm')
                                );
                                if (r == 0) {
                                    circ.util.batch_hold_update(hold_list, { 'selection_depth' : obj.data.hash.aout[selection].depth() }, { 'progressmeter' : progressmeter, 'oncomplete' :  function() { obj.clear_and_retrieve(true); } });
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_not_modified'),E);
                            }
                        }
                    ],

                    'cmd_holds_edit_pickup_lib' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.widgets'); JSAN.use('util.functional');

                                var list = util.functional.map_list(
                                    obj.data.list.aou,
                                    function(o) {
                                        var sname = o.shortname(); for (i = sname.length; i < 20; i++) sname += ' ';
                                        return [
                                            o.name() ? sname + ' ' + o.name() : o.shortname(),
                                            o.id(),
                                            ( !isTrue(obj.data.hash.aout[ o.ou_type() ].can_have_users()) ),
                                            ( obj.data.hash.aout[ o.ou_type() ].depth() * 2),
                                        ];
                                    }
                                );
                                ml = util.widgets.make_menulist( list, obj.data.list.au[0].ws_ou() );
                                ml.setAttribute('id','lib');
                                ml.setAttribute('name','fancy_data');
                                var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                xml += '<description>'+$("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.new_pickup_lib.description')+'</description>';
                                xml += util.widgets.serialize_node(ml);
                                xml += '</vbox>';
                                var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                bot_xml += '<spacer flex="1"/><button label="'+ $("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.done.label') +'"';
                                bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.done.accesskey')+'" name="fancy_submit"/>';
                                bot_xml += '<button label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.cancel.label')+'"';
                                bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.cancel.accesskey')+'" name="fancy_cancel"/></hbox>';
                                netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
                                //obj.data.temp_mid = xml; obj.data.stash('temp_mid');
                                //obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
                                JSAN.use('util.window'); var win = new util.window();
                                var fancy_prompt_data = win.open(
                                    urls.XUL_FANCY_PROMPT,
                                    //+ '?xml_in_stash=temp_mid'
                                    //+ '&bottom_xml_in_stash=temp_bot'
                                    //+ '&title=' + window.escape('Choose a Pick Up Library'),
                                    'fancy_prompt', 'chrome,resizable,modal',
                                    { 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.choose_lib') }
                                );
                                if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
                                var pickup_lib = fancy_prompt_data.lib;

                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg = '';
                                if(obj.retrieve_ids.length > 1) {
                                    msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_pickup_lib.change_pickup_lib_message.plural',[hold_list.join(', '), obj.data.hash.aou[pickup_lib].shortname()]);
                                } else {
                                    msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_pickup_lib.change_pickup_lib_message.singular',[hold_list.join(', '), obj.data.hash.aou[pickup_lib].shortname()]);
                                }
                                var r = obj.error.yns_alert(msg,
                                        $("patronStrings").getString('staff.patron.holds.holds_edit_pickup_lib.change_pickup_lib_title'),
                                        $("commonStrings").getString('common.yes'),
                                        $("commonStrings").getString('common.no'),
                                        null,
                                        $("commonStrings").getString('common.check_to_confirm')
                                );
                                if (r == 0) {
                                    circ.util.batch_hold_update(hold_list, { 'pickup_lib' : pickup_lib }, { 'progressmeter' : progressmeter, 'oncomplete' :  function() { obj.clear_and_retrieve(true); } });
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_not_modified'),E);
                            }
                        }
                    ],
                    'cmd_holds_edit_phone_notify' : [
                        ['command'],
                        function() {
                            try {
                                var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                xml += '<description>'+$("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.new_phone_number')+'</description>';
                                xml += '<textbox id="phone" name="fancy_data" context="clipboard"/>';
                                xml += '</vbox>';
                                var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                bot_xml += '<spacer flex="1"/><button label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.btn_done.label')+'"';
                                bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.btn_done.accesskey')+'" name="fancy_submit"/>';
                                bot_xml += '<button label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.btn_cancel.label')+'"';
                                bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.btn_cancel.accesskey')+'" name="fancy_cancel"/></hbox>';
                                netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
                                //obj.data.temp_mid = xml; obj.data.stash('temp_mid');
                                //obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
                                JSAN.use('util.window'); var win = new util.window();
                                var fancy_prompt_data = win.open(
                                    urls.XUL_FANCY_PROMPT,
                                    //+ '?xml_in_stash=temp_mid'
                                    //+ '&bottom_xml_in_stash=temp_bot'
                                    //+ '&title=' + window.escape('Choose a Hold Notification Phone Number')
                                    //+ '&focus=phone',
                                    'fancy_prompt', 'chrome,resizable,modal',
                                    { 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.choose_phone_number'), 'focus' : 'phone' }
                                );
                                if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
                                var phone = fancy_prompt_data.phone;

                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg = '';
                                if(obj.retrieve_ids.length > 1) {
                                    msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_phone_notify.confirm_phone_number_change.plural',[hold_list.join(', '), phone]);
                                } else {
                                    msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_phone_notify.confirm_phone_number_change.singular',[hold_list.join(', '), phone]);
                                }
                                var r = obj.error.yns_alert(msg,
                                        $("patronStrings").getString('staff.patron.holds.holds_edit_phone_notify.modifying_holds_title'),
                                        $("commonStrings").getString('common.yes'),
                                        $("commonStrings").getString('common.no'),
                                        null,
                                        $("commonStrings").getString('common.check_to_confirm')
                                );
                                if (r == 0) {
                                    circ.util.batch_hold_update(hold_list, { 'phone_notify' : phone }, { 'progressmeter' : progressmeter, 'oncomplete' :  function() { obj.clear_and_retrieve(true); } });
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_not_modified'),E);
                            }
                        }
                    ],

                    'cmd_holds_edit_sms_notify' : [
                        ['command'],
                        function() {
                            try {
                                var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                xml += '<description>'+$("patronStrings").getString('staff.patron.holds.holds_edit_sms_notify.new_phone_number')+'</description>';
                                xml += '<textbox id="phone" name="fancy_data" context="clipboard"/>';
                                xml += '</vbox>';
                                var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                bot_xml += '<spacer flex="1"/><button label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_sms_notify.btn_done.label')+'"';
                                bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_sms_notify.btn_done.accesskey')+'" name="fancy_submit"/>';
                                bot_xml += '<button label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_sms_notify.btn_cancel.label')+'"';
                                bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_sms_notify.btn_cancel.accesskey')+'" name="fancy_cancel"/></hbox>';
                                netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
                                //obj.data.temp_mid = xml; obj.data.stash('temp_mid');
                                //obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
                                JSAN.use('util.window'); var win = new util.window();
                                var fancy_prompt_data = win.open(
                                    urls.XUL_FANCY_PROMPT,
                                    //+ '?xml_in_stash=temp_mid'
                                    //+ '&bottom_xml_in_stash=temp_bot'
                                    //+ '&title=' + window.escape('Choose a Hold Notification Phone Number')
                                    //+ '&focus=phone',
                                    'fancy_prompt', 'chrome,resizable,modal',
                                    { 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.holds.holds_edit_sms_notify.choose_phone_number'), 'focus' : 'phone' }
                                );
                                if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
                                var phone = fancy_prompt_data.phone;

                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg = '';
                                if(obj.retrieve_ids.length > 1) {
                                    msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_sms_notify.confirm_phone_number_change.plural',[hold_list.join(', '), phone]);
                                } else {
                                    msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_sms_notify.confirm_phone_number_change.singular',[hold_list.join(', '), phone]);
                                }
                                var r = obj.error.yns_alert(msg,
                                        $("patronStrings").getString('staff.patron.holds.holds_edit_sms_notify.modifying_holds_title'),
                                        $("commonStrings").getString('common.yes'),
                                        $("commonStrings").getString('common.no'),
                                        null,
                                        $("commonStrings").getString('common.check_to_confirm')
                                );
                                if (r == 0) {
                                    var hparams = {
                                        'sms_notify' : phone == '' ? null : phone 
                                    }
                                    if (phone == '') {
                                        hparams.sms_carrier = null;
                                    }
                                    circ.util.batch_hold_update(hold_list, hparams, { 'progressmeter' : progressmeter, 'oncomplete' :  function() { obj.clear_and_retrieve(true); } });
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_not_modified'),E);
                            }
                        }
                    ],

                    'cmd_holds_edit_sms_carrier' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.widgets'); JSAN.use('util.functional');

                                var list = util.functional.map_list(
                                    obj.data.list.csc,
                                    function(o) {
                                        return [
                                            o.name() + ' (' + o.region() + ')',
                                            o.id(),
                                            ( !isTrue(o.active()) ),
                                            0
                                        ];
                                    }
                                );
                                ml = util.widgets.make_menulist( list, obj.data.list.au[0].ws_ou() );
                                ml.setAttribute('id','carrier');
                                ml.setAttribute('name','fancy_data');
                                var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                xml += '<description>'+$("patronStrings").getString('staff.patron.holds.holds_edit_sms_carrier.new_carrier')+'</description>';
                                xml += util.widgets.serialize_node(ml);
                                xml += '</vbox>';
                                var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                bot_xml += '<spacer flex="1"/><button label="'+ $("patronStrings").getString('staff.patron.holds.holds_edit_sms_carrier.btn_done.label') +'"';
                                bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_sms_carrier.btn_done.accesskey')+'" name="fancy_submit"/>';
                                bot_xml += '<button label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_sms_carrier.btn_cancel.label')+'"';
                                bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_sms_carrier.btn_cancel.accesskey')+'" name="fancy_cancel"/></hbox>';
                                netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
                                //obj.data.temp_mid = xml; obj.data.stash('temp_mid');
                                //obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
                                JSAN.use('util.window'); var win = new util.window();
                                var fancy_prompt_data = win.open(
                                    urls.XUL_FANCY_PROMPT,
                                    //+ '?xml_in_stash=temp_mid'
                                    //+ '&bottom_xml_in_stash=temp_bot'
                                    //+ '&title=' + window.escape('Choose a Pick Up Library'),
                                    'fancy_prompt', 'chrome,resizable,modal',
                                    { 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.holds.holds_edit_sms_carrier.choose_carrier') }
                                );
                                if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
                                var sms_carrier = fancy_prompt_data.carrier;

                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg = '';

                                if(obj.retrieve_ids.length > 1) {
                                    msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_sms_carrier.confirm_carrier_change.plural',[hold_list.join(', '), obj.data.hash.csc[sms_carrier].name()]);
                                } else {
                                    msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_sms_carrier.confirm_carrier_change.singular',[hold_list.join(', '), obj.data.hash.csc[sms_carrier].name()]);
                                }
                                var r = obj.error.yns_alert(msg,
                                        $("patronStrings").getString('staff.patron.holds.holds_edit_sms_carrier.modifying_holds_title'),
                                        $("commonStrings").getString('common.yes'),
                                        $("commonStrings").getString('common.no'),
                                        null,
                                        $("commonStrings").getString('common.check_to_confirm')
                                );
                                if (r == 0) {
                                    circ.util.batch_hold_update(hold_list, { 'sms_carrier' : sms_carrier }, { 'progressmeter' : progressmeter, 'oncomplete' :  function() { obj.clear_and_retrieve(true); } });
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_not_modified'),E);
                            }
                        }
                    ],

                    'cmd_holds_edit_email_notify' : [
                        ['command'],
                        function() {
                            try {
                                var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                xml += '<description>'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.description')+'</description>';
                                xml += '<hbox><button value="email" label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.btn_email.label')+'"';
                                xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.btn_email.accesskey')+'" name="fancy_submit"/>';
                                xml += '<button value="noemail" label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.btn_no_email.label')+'"';
                                xml += '  accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.btn_no_email.accesskey')+'" name="fancy_submit"/></hbox>';
                                xml += '</vbox>';
                                var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                bot_xml += '<spacer flex="1"/><button label="'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.btn_cancel.label')+'"';
                                bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.btn_cancel.accesskey')+'" name="fancy_cancel"/></hbox>';
                                netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
                                //obj.data.temp_mid = xml; obj.data.stash('temp_mid');
                                //obj.data.temp_bot = bot_xml; obj.data.stash('temp_bot');
                                JSAN.use('util.window'); var win = new util.window();
                                var fancy_prompt_data = win.open(
                                    urls.XUL_FANCY_PROMPT,
                                    //+ '?xml_in_stash=temp_mid'
                                    //+ '&bottom_xml_in_stash=temp_bot'
                                    //+ '&title=' + window.escape('Set Email Notification for Holds'),
                                    'fancy_prompt', 'chrome,resizable,modal',
                                    { 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.set_notifs') }
                                );
                                if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
                                var email = fancy_prompt_data.fancy_submit == 'email' ? get_db_true() : get_db_false();

                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg = '';
                                if(get_bool(email)) {
                                    if(obj.retrieve_ids.length > 1) {
                                        msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_email_notify.enable_email.plural', [hold_list.join(', ')]);
                                    } else {
                                        msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_email_notify.enable_email.singular', [hold_list.join(', ')]);
                                    }
                                } else {
                                    if(obj.retrieve_ids.length > 1) {
                                        msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_email_notify.disable_email.plural', [hold_list.join(', ')]);
                                    } else {
                                        msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_edit_email_notify.disable_email.singular', [hold_list.join(', ')]);
                                    }
                                }

                                var r = obj.error.yns_alert(msg,
                                        $("patronStrings").getString('staff.patron.holds.holds_edit_email_notify.mod_holds_title'),
                                        $("commonStrings").getString('common.yes'),
                                        $("commonStrings").getString('common.no'),
                                        null,
                                        $("commonStrings").getString('common.check_to_confirm')
                                );
                                if (r == 0) {
                                    circ.util.batch_hold_update(hold_list, { 'email_notify' : email }, { 'progressmeter' : progressmeter, 'oncomplete' :  function() { obj.clear_and_retrieve(true); } });
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_not_modified'),E);
                            }
                        }
                    ],
                    'cmd_holds_cut_in_line' : [
                        ['command'],
                        function() {
                            try {
                                var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                xml += '<description>'+$("patronStrings").getString('staff.patron.holds.holds_cut_in_line.description')+'</description>';
                                xml += '<hbox><button value="cut" label="'+$("patronStrings").getString('staff.patron.holds.holds_cut_in_line.btn_cut.label')+'"';
                                xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_cut_in_line.btn_cut.accesskey')+'" name="fancy_submit"/>';
                                xml += '<button value="nocut" label="'+$("patronStrings").getString('staff.patron.holds.holds_cut_in_line.btn_no_cut.label')+'"';
                                xml += '  accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_cut_in_line.btn_no_cut.accesskey')+'" name="fancy_submit"/></hbox>';
                                xml += '</vbox>';
                                var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                bot_xml += '<spacer flex="1"/><button label="'+$("patronStrings").getString('staff.patron.holds.holds_cut_in_line.btn_cancel.label')+'"';
                                bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_cut_in_line.btn_cancel.accesskey')+'" name="fancy_cancel"/></hbox>';
                                netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
                                JSAN.use('util.window'); var win = new util.window();
                                var fancy_prompt_data = win.open(
                                    urls.XUL_FANCY_PROMPT,
                                    'fancy_prompt', 'chrome,resizable,modal',
                                    { 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.holds.holds_cut_in_line.set_notifs') }
                                );
                                if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
                                var cut = fancy_prompt_data.fancy_submit == 'cut' ? get_db_true() : get_db_false();

                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg = '';
                                if(get_bool(cut)) {
                                    if(obj.retrieve_ids.length > 1) {
                                        msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_cut_in_line.enable_cut.plural', [hold_list.join(', ')]);
                                    } else {
                                        msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_cut_in_line.enable_cut.singular', [hold_list.join(', ')]);
                                    }
                                } else {
                                    if(obj.retrieve_ids.length > 1) {
                                        msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_cut_in_line.disable_cut.plural', [hold_list.join(', ')]);
                                    } else {
                                        msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_cut_in_line.disable_cut.singular', [hold_list.join(', ')]);
                                    }
                                }

                                var r = obj.error.yns_alert(msg,
                                        $("patronStrings").getString('staff.patron.holds.holds_cut_in_line.mod_holds_title'),
                                        $("commonStrings").getString('common.yes'),
                                        $("commonStrings").getString('common.no'),
                                        null,
                                        $("commonStrings").getString('common.check_to_confirm')
                                );
                                if (r == 0) {
                                    circ.util.batch_hold_update(hold_list, { 'cut_in_line' : cut }, { 'progressmeter' : progressmeter, 'oncomplete' :  function() { obj.clear_and_retrieve(true); } });
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_not_modified'),E);
                            }
                        }
                    ],
                    'cmd_holds_edit_desire_mint_condition' : [
                        ['command'],
                        function() {
                            try {
                                var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                xml += '<description>'+$("patronStrings").getString('staff.patron.holds.holds_desire_mint_condition.description')+'</description>';
                                xml += '<hbox><button value="good" label="'+$("patronStrings").getString('staff.patron.holds.holds_desire_mint_condition.btn_good.label')+'"';
                                xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_desire_mint_condition.btn_good.accesskey')+'" name="fancy_submit"/>';
                                xml += '<button value="nogood" label="'+$("patronStrings").getString('staff.patron.holds.holds_desire_mint_condition.btn_mediocre.label')+'"';
                                xml += '  accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_desire_mint_condition.btn_mediocre.accesskey')+'" name="fancy_submit"/></hbox>';
                                xml += '</vbox>';
                                var bot_xml = '<hbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
                                bot_xml += '<spacer flex="1"/><button label="'+$("patronStrings").getString('staff.patron.holds.holds_desire_mint_condition.btn_cancel.label')+'"';
                                bot_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.holds.holds_desire_mint_condition.btn_cancel.accesskey')+'" name="fancy_cancel"/></hbox>';
                                netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
                                JSAN.use('util.window'); var win = new util.window();
                                var fancy_prompt_data = win.open(
                                    urls.XUL_FANCY_PROMPT,
                                    'fancy_prompt', 'chrome,resizable,modal',
                                    { 'xml' : xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.holds.holds_desire_mint_condition.set_notifs') }
                                );
                                if (fancy_prompt_data.fancy_status == 'incomplete') { return; }
                                var good = fancy_prompt_data.fancy_submit == 'good' ? get_db_true() : get_db_false();

                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg = '';
                                if(get_bool(good)) {
                                    if(obj.retrieve_ids.length > 1) {
                                        msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_desire_mint_condition.enable_good.plural', [hold_list.join(', ')]);
                                    } else {
                                        msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_desire_mint_condition.enable_good.singular', [hold_list.join(', ')]);
                                    }
                                } else {
                                    if(obj.retrieve_ids.length > 1) {
                                        msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_desire_mint_condition.disable_good.plural', [hold_list.join(', ')]);
                                    } else {
                                        msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_desire_mint_condition.disable_good.singular', [hold_list.join(', ')]);
                                    }
                                }

                                var r = obj.error.yns_alert(msg,
                                        $("patronStrings").getString('staff.patron.holds.holds_desire_mint_condition.mod_holds_title'),
                                        $("commonStrings").getString('common.yes'),
                                        $("commonStrings").getString('common.no'),
                                        null,
                                        $("commonStrings").getString('common.check_to_confirm')
                                );
                                if (r == 0) {
                                    circ.util.batch_hold_update(hold_list, { 'mint_condition' : good }, { 'progressmeter' : progressmeter, 'oncomplete' :  function() { obj.clear_and_retrieve(true); } });
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_not_modified'),E);
                            }
                        }
                    ],


                    'cmd_holds_suspend' : [
                        ['command'],
                        function() {
                            try {
                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var r = obj.error.yns_alert(
                                    obj.retrieve_ids.length > 1 ?
                                    document.getElementById('circStrings').getFormattedString('staff.circ.holds.suspend.prompt.plural',[hold_list.join(', ')]) :
                                    document.getElementById('circStrings').getFormattedString('staff.circ.holds.suspend.prompt',[hold_list.join(', ')]),
                                    document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds'),
                                    document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds.yes'),
                                    document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds.no'),
                                    null,
                                    document.getElementById('commonStrings').getString('common.confirm')
                                );
                                if (r == 0) {
                                    var already_suspended = []; var filtered_hold_list = [];
                                    for (var i = 0; i < obj.retrieve_ids.length; i++) {
                                        var hold = obj.holds_map[ obj.retrieve_ids[i].id ].hold;
                                        if ( get_bool( hold.frozen() ) ) {
                                            already_suspended.push( hold.id() );
                                            continue;
                                        }
                                        filtered_hold_list.push( hold.id() );
                                    }
                                    circ.util.batch_hold_update(filtered_hold_list, { 'frozen' : 't', 'thaw_date' : null }, { 'progressmeter' : progressmeter, 'oncomplete' :  function() { 
                                        if (already_suspended.length == 1) {
                                            alert( document.getElementById('circStrings').getFormattedString('staff.circ.holds.already_suspended',[already_suspended[0]]) );
                                        } else if (already_suspended.length > 1) {
                                            alert( document.getElementById('circStrings').getFormattedString('staff.circ.holds.already_suspended.plural',[already_suspended.join(', ')]) );
                                        }
                                        obj.clear_and_retrieve(true); 
                                    } });
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.holds.unexpected_error.not_likely_suspended'),E);
                            }
                        }
                    ],
                    'cmd_holds_activate' : [
                        ['command'],
                        function() {
                            try {
                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var r = obj.error.yns_alert(
                                    obj.retrieve_ids.length > 1 ?
                                    document.getElementById('circStrings').getFormattedString('staff.circ.holds.activate.prompt.plural',[hold_list.join(', ')]) :
                                    document.getElementById('circStrings').getFormattedString('staff.circ.holds.activate.prompt',[hold_list.join(', ')]),
                                    document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds'),
                                    document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds.yes'),
                                    document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds.no'),
                                    null,
                                    document.getElementById('commonStrings').getString('common.confirm')
                                );
                                if (r == 0) {
                                    var already_activated = []; var filtered_hold_list = [];
                                    for (var i = 0; i < obj.retrieve_ids.length; i++) {
                                        var hold = obj.holds_map[ obj.retrieve_ids[i].id ].hold;
                                        if ( ! get_bool( hold.frozen() ) ) {
                                            already_activated.push( hold.id() );
                                            continue;
                                        }
                                        filtered_hold_list.push( hold.id() );
                                    }
                                    circ.util.batch_hold_update(filtered_hold_list, { 'frozen' : 'f', 'thaw_date' : null }, { 'progressmeter' : progressmeter, 'oncomplete' :  function() { 
                                        if (already_activated.length == 1) {
                                            alert( document.getElementById('circStrings').getFormattedString('staff.circ.holds.already_activated',[already_activated[0]]) );
                                        } else if (already_activated.length > 1) {
                                            alert( document.getElementById('circStrings').getFormattedString('staff.circ.holds.already_activated.plural',[already_activated.join(', ')]) );
                                        }
                                        obj.clear_and_retrieve(true); 
                                    } });
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.holds.unexpected_error.not_likely_activated'),E);
                            }
                        }
                    ],
                    'cmd_holds_edit_thaw_date' : [
                        ['command'],
                        function() {
                            try {
                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg_singular = document.getElementById('circStrings').getFormattedString('staff.circ.holds.activation_date.prompt',[hold_list.join(', ')]);
                                var msg_plural = document.getElementById('circStrings').getFormattedString('staff.circ.holds.activation_date.prompt.plural',[hold_list.join(', ')]);
                                var msg = obj.retrieve_ids.length > 1 ? msg_plural : msg_singular;
                                var title = document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds');
                                var desc = document.getElementById('circStrings').getString('staff.circ.holds.activation_date.dialog.description');

                                JSAN.use('util.window'); var win = new util.window();
                                var my_xulG = win.open( 
                                    urls.XUL_TIMESTAMP_DIALOG, 'edit_thaw_date', 'chrome,resizable,modal', 
                                    { 
                                        'title' : title, 
                                        'description' : desc, 
                                        'msg' : msg, 
                                        'allow_unset' : true,
                                        'disallow_future_dates' : false,
                                        'disallow_past_dates' : true,
                                        'disallow_today' : true,
                                        'default_time' : '00:00:00',
                                        'time_readonly' : false
                                    }
                                );
                                if (my_xulG.complete) {
                                    circ.util.batch_hold_update(
                                        hold_list, 
                                        { 'frozen' : 't', 'thaw_date' : my_xulG.timestamp }, 
                                        { 'progressmeter' : progressmeter, 'oncomplete' :  function() { obj.clear_and_retrieve(true); } }
                                    );
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.holds.unexpected_error.not_likely_modified'),E);
                            }
                        }
                    ],
                    'cmd_holds_edit_expire_time' : [
                        ['command'],
                        function() {
                            try {
                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg_singular = document.getElementById('circStrings').getFormattedString('staff.circ.holds.expire_time.prompt',[hold_list.join(', ')]);
                                var msg_plural = document.getElementById('circStrings').getFormattedString('staff.circ.holds.expire_time.prompt.plural',[hold_list.join(', ')]);
                                var msg = obj.retrieve_ids.length > 1 ? msg_plural : msg_singular;
                                var value = 'YYYY-MM-DD';
                                var title = document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds');
                                var desc = document.getElementById('circStrings').getString('staff.circ.holds.expire_time.dialog.description');

                                JSAN.use('util.window'); var win = new util.window();
                                var my_xulG = win.open( 
                                    urls.XUL_TIMESTAMP_DIALOG, 'edit_expire_time', 'chrome,resizable,modal', 
                                    { 
                                        'title' : title, 
                                        'description' : desc, 
                                        'msg' : msg, 
                                        'allow_unset' : true,
                                        'disallow_future_dates' : false,
                                        'disallow_past_dates' : true,
                                        'disallow_today' : true,
                                        'default_time' : '00:00:00',
                                        'time_readonly' : false
                                    }
                                );
                                if (my_xulG.complete) {
                                    circ.util.batch_hold_update(
                                        hold_list, 
                                        { 'expire_time' : my_xulG.timestamp }, 
                                        { 'progressmeter' : progressmeter, 'oncomplete' :  function() { obj.clear_and_retrieve(true); } }
                                    );
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.holds.unexpected_error.not_likely_modified'),E);
                            }
                        }
                    ],
                    'cmd_holds_edit_shelf_expire_time' : [
                        ['command'],
                        function() {
                            try {
                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg_singular = document.getElementById('circStrings').getFormattedString('staff.circ.holds.shelf_expire_time.prompt',[hold_list.join(', ')]);
                                var msg_plural = document.getElementById('circStrings').getFormattedString('staff.circ.holds.shelf_expire_time.prompt.plural',[hold_list.join(', ')]);
                                var msg = obj.retrieve_ids.length > 1 ? msg_plural : msg_singular;
                                var title = document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds');
                                var desc = document.getElementById('circStrings').getString('staff.circ.holds.shelf_expire_time.dialog.description');

                                JSAN.use('util.window'); var win = new util.window();
                                var my_xulG = win.open( 
                                    urls.XUL_TIMESTAMP_DIALOG, 'edit_shelf_expire_time', 'chrome,resizable,modal', 
                                    { 
                                        'title' : title, 
                                        'description' : desc, 
                                        'msg' : msg, 
                                        'allow_unset' : false,
                                        'disallow_future_dates' : false,
                                        'disallow_past_dates' : false,
                                        'disallow_today' : false
                                    }
                                );
                                if (my_xulG.complete) {
                                    circ.util.batch_hold_update(
                                        hold_list, 
                                        { 'shelf_expire_time' : my_xulG.timestamp }, 
                                        { 'progressmeter' : progressmeter, 'oncomplete' :  function() { obj.clear_and_retrieve(true); } }
                                    );
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.holds.unexpected_error.not_likely_modified'),E);
                            }
                        }
                    ],
                    'cmd_holds_edit_request_date' : [
                        ['command'],
                        function() {
                            try {
                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg_singular = document.getElementById('circStrings').getFormattedString('staff.circ.holds.request_date.prompt',[hold_list.join(', ')]);
                                var msg_plural = document.getElementById('circStrings').getFormattedString('staff.circ.holds.request_date.prompt.plural',[hold_list.join(', ')]);
                                var msg = obj.retrieve_ids.length > 1 ? msg_plural : msg_singular;
                                var title = document.getElementById('circStrings').getString('staff.circ.holds.modifying_holds');
                                var desc = document.getElementById('circStrings').getString('staff.circ.holds.request_date.dialog.description');

                                JSAN.use('util.window'); var win = new util.window();
                                var my_xulG = win.open( 
                                    urls.XUL_TIMESTAMP_DIALOG, 'edit_request_date', 'chrome,resizable,modal', 
                                    { 
                                        'title' : title, 
                                        'description' : desc, 
                                        'msg' : msg, 
                                        'allow_unset' : false,
                                        'disallow_future_dates' : true,
                                        'disallow_past_dates' : false,
                                        'disallow_today' : false
                                    }
                                );
                                if (my_xulG.complete) {
                                    circ.util.batch_hold_update(
                                        hold_list, 
                                        { 'request_time' : my_xulG.timestamp }, 
                                        { 'progressmeter' : progressmeter, 'oncomplete' :  function() { obj.clear_and_retrieve(true); } }
                                    );
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.holds.unexpected_error.not_likely_modified'),E);
                            }
                        }
                    ],
                    'cmd_holds_retarget' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.functional');

                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg = '';
                                if(obj.retrieve_ids.length > 1) {
                                    msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_retarget.reset_hold_message.plural',[hold_list.join(', ')]);
                                } else {
                                    msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_retarget.reset_hold_message.singular',[hold_list.join(', ')]);
                                }
                                var r = obj.error.yns_alert(msg,
                                        $("patronStrings").getString('staff.patron.holds.holds_retarget.reset_hold_title'),
                                        $("commonStrings").getString('common.yes'),
                                        $("commonStrings").getString('common.no'),
                                        null,
                                        $("commonStrings").getString('common.check_to_confirm')
                                );
                                if (r == 0) {
                                    for (var i = 0; i < obj.retrieve_ids.length; i++) {
                                        var robj = obj.network.simple_request('FM_AHR_RESET',[ ses(), obj.retrieve_ids[i].id]);
                                        if (typeof robj.ilsevent != 'undefined') throw(robj);
                                    }
                                    obj.clear_and_retrieve();
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_retarget.holds_not_reset'),E);
                            }

                        }
                    ],

                    'cmd_holds_cancel' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.functional');

                                var hold_list = util.functional.map_list(obj.retrieve_ids, function(o){return o.id;});
                                var msg = '';
                                if(obj.retrieve_ids.length > 1 ) {
                                    msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_cancel.cancel_hold_message.plural', [hold_list.join(', ')]);
                                } else {
                                    msg = $("patronStrings").getFormattedString('staff.patron.holds.holds_cancel.cancel_hold_message.singular', [hold_list.join(', ')]);
                                }

                                netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
                                JSAN.use('util.window');
                                var win = new util.window();
                                var my_xulG = win.open(
                                    urls.XUL_HOLD_CANCEL,
                                    'hold_cancel',
                                    'chrome,resizable,modal',
                                    {}
                                );
                                /*var r = obj.error.yns_alert(msg,
                                        $("patronStrings").getString('staff.patron.holds.holds_cancel.cancel_hold_title'),
                                        $("commonStrings").getString('common.yes'),
                                        $("commonStrings").getString('common.no'),
                                        null,
                                        $("commonStrings").getString('common.check_to_confirm')
                                );*/

                                if (my_xulG.proceed) { 
                                    var transits = [];
                                    for (var i = 0; i < obj.retrieve_ids.length; i++) {
                                        var transit = obj.holds_map[ obj.retrieve_ids[i].id ].hold.transit();
                                        if (transit && ! transit.dest_recv_time() ) {
                                            transits.push( obj.retrieve_ids[i].barcode );
                                        }
                                        var robj = obj.network.simple_request('FM_AHR_CANCEL',[ ses(), obj.retrieve_ids[i].id, my_xulG.cancel_reason, my_xulG.note]);
                                        if (typeof robj.ilsevent != 'undefined') throw(robj);
                                    }
                                    if (transits.length > 0) {
                                        var msg2 = $("patronStrings").getFormattedString('staff.patron.holds.holds_cancel.cancel_for_barcodes', [transits.join(', ')]);
                                        var r2 = obj.error.yns_alert(msg2,
                                            $("patronStrings").getString('staff.patron.holds.holds_cancel.cancel_for_barcodes.title'),
                                            $("commonStrings").getString('common.yes'),
                                            $("commonStrings").getString('common.no'),
                                            null,
                                            $("commonStrings").getString('common.check_to_confirm'));
                                        if (r2 == 0) {
                                            try {
                                                for (var i = 0; i < transits.length; i++) {
                                                    var robj = obj.network.simple_request('FM_ATC_VOID',[ ses(), { 'barcode' : transits[i] } ]);
                                                    if (typeof robj.ilsevent != 'undefined') {
                                                        switch(Number(robj.ilsevent)) {
                                                            case 1225 /* TRANSIT_ABORT_NOT_ALLOWED */ :
                                                                alert(robj.desc);
                                                            break;
                                                            case 5000 /* PERM_FAILURE */ :
                                                            break;
                                                            default:
                                                                throw(robj);
                                                            break;
                                                        }
                                                    }
                                                }
                                            } catch(E) {
                                               obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_cancel.hold_transits_not_cancelled'),E);
                                            }
                                        }
                                    }
                                    obj.clear_and_retrieve();
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_cancel.hold_not_cancelled'),E);
                            }
                        }
                    ],
                    'cmd_holds_uncancel' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.functional');
                                for (var i = 0; i < obj.retrieve_ids.length; i++) {
                                    var robj = obj.network.simple_request('FM_AHR_UNCANCEL',[ ses(), obj.retrieve_ids[i].id]);
                                    if (typeof robj.ilsevent != 'undefined') throw(robj);
                                }
                                obj.clear_and_retrieve();
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.holds.holds_uncancel.hold_not_uncancelled'),E);
                            }
                        }
                    ],

                    'cmd_retrieve_patron' : [
                        ['command'],
                        function() {
                            try {
                                var seen = {};
                                for (var i = 0; i < obj.retrieve_ids.length; i++) {
                                    var patron_id = obj.retrieve_ids[i].usr;
                                    if (seen[patron_id]) continue; seen[patron_id] = true;
                                    xulG.new_patron_tab(
                                        {},
                                        { 'id' : patron_id }
                                    );
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('',E);
                            }
                        }
                    ],
                    'cmd_show_catalog' : [
                        ['command'],
                        function() {
                            try {
                                for (var i = 0; i < obj.retrieve_ids.length; i++) {
                                    var htarget = obj.retrieve_ids[i].target;
                                    var htype = obj.retrieve_ids[i].type;
                                    var opac_url;
                                    switch(htype) {
                                        case 'M' :
                                            opac_url = xulG.url_prefix( urls.opac_rresult_metarecord ) + htarget;
                                        break;
                                        case 'T' :
                                            opac_url = xulG.url_prefix( urls.opac_rdetail ) + htarget;
                                        break;
                                        case 'P' :
                                            opac_url = xulG.url_prefix( urls.opac_rdetail )
                                            + obj.hold_part_map[ obj.retrieve_ids[i].id ].record();
                                        break;
                                        case 'I' :
                                            opac_url = xulG.url_prefix( urls.opac_rdetail )
                                            + obj.hold_subscription_map[ obj.retrieve_ids[i].id ].record_entry();
                                        break;
                                        case 'V' :
                                            var my_acn = obj.network.simple_request( 'FM_ACN_RETRIEVE.authoritative', [ htarget ]);
                                            opac_url = xulG.url_prefix( urls.opac_rdetail) + my_acn.record();
                                        break;
                                        case 'C' :
                                        case 'R' :
                                        case 'F' :
                                            var my_acp = obj.network.simple_request( 'FM_ACP_RETRIEVE', [ htarget ]);
                                            var my_acn;
                                            if (typeof my_acp.call_number() == 'object') {
                                                my_acn = my.acp.call_number();
                                            } else {
                                                my_acn = obj.network.simple_request( 'FM_ACN_RETRIEVE.authoritative',
                                                    [ my_acp.call_number() ]);
                                            }
                                            opac_url = xulG.url_prefix( urls.opac_rdetail) + my_acn.record();
                                        break;
                                        default:
                                            obj.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.holds.show_catalog.unknown_htype', [htype]), obj.retrieve_ids[i]);
                                            continue;
                                        break;
                                    }
                                    var content_params = {
                                        'session' : ses(),
                                        'authtime' : ses('authtime'),
                                        'opac_url' : opac_url
                                    };
                                    xulG.new_tab(
                                        xulG.url_prefix(urls.XUL_OPAC_WRAPPER),
                                        {'tab_name': htype == 'M' ? 'Catalog' : $("patronStrings").getString('staff.patron.holds.show_catalog.retrieving_title') },
                                        content_params
                                    );
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('',E);
                            }
                        }
                    ],
                    'cmd_holds_title_transfer' : [
                        ['command'],
                        function() {
                            try {
                                var hids = [];
                                var unique_targets = [];
                                var seen_target = {};
                                for (var i = 0; i < obj.retrieve_ids.length; i++) {
                                    var hid = obj.retrieve_ids[i].id;
                                    var htarget = obj.retrieve_ids[i].id;
                                    var htype = obj.retrieve_ids[i].type;
                                    switch(htype) {
                                        case 'M' :
                                            continue; // not supported
                                        break;
                                        case 'T' :
                                            hids.push( hid );
                                            if (! seen_target[htarget]) {
                                                unique_targets.push( htarget );
                                                seen_target[htarget] = 1;
                                            }
                                        break;
                                        case 'V' :
                                            continue; // not supported
                                        break;
                                        case 'C' :
                                            continue; // not supported
                                        break;
                                        default:
                                            continue; // not supported
                                        break;
                                    }
                                }
                                JSAN.use('cat.util');
                                cat.util.transfer_specific_title_holds(hids,unique_targets);
                                obj.clear_and_retrieve();
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('',E);
                            }
                        }
                    ],

                    'fetch_more' : [
                        ['command'],
                        function() {
                            obj.pull_from_shelf_interface.current.offset += obj.pull_from_shelf_interface.current.limit;
                            obj.retrieve(true);
                        }
                    ],
                    'lib_filter_checkbox' : [
                        ['command'],
                        function(ev) {
                            var x_lib_type_menu = document.getElementById('lib_type_menu');
                            if (x_lib_type_menu) x_lib_type_menu.disabled = ! ev.target.checked;
                            if (obj.controller.view.lib_menu) obj.controller.view.lib_menu.disabled = ! ev.target.checked;
                            obj.clear_and_retrieve();
                            ev.target.setAttribute('checked',ev.target.checked);
                        }
                    ],
                    'cmd_view_expired_onshelf_holds' : [
                        ['command'],
                        function(ev) {
                            var x = document.getElementById('expired_checkbox'); // can't trust ev.explicitOriginalTarget, sometimes gives a "button"
                            obj.expired = x.checked;
                            obj.controller.view.cmd_clear_expired_onshelf_holds.setAttribute('disabled', !obj.expired);
                            obj.clear_and_retrieve();
                        }
                    ],
                    'cmd_clear_expired_onshelf_holds' : [
                        ['command'],
                        function(ev) {
                            obj.cmd_clear_expired_onshelf_holds();
                        }
                    ],
                    'cmd_search_opac' : [
                        ['command'],
                        function(ev) {
                            try {
                                var content_params = {
                                    'show_nav_buttons' : false,
                                    'show_print_button' : true,
                                    'passthru_content_params' : {
                                        'authtoken' : ses(),
                                        'authtime' : ses('authtime'),
                                        'window_open' : function(a,b,c) {
                                            try {
                                                netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
                                                return window.open(a,b,c);
                                            } catch(E) {
                                                obj.error.standard_unexpected_error_alert('window_open',E);
                                            }
                                        },
                                        'opac_hold_placed' : function(hold) {
                                            try {
                                                var hold_id = typeof hold == 'object' ? hold.id() : hold;
                                                obj.list.append(
                                                    {
                                                        'row' : {
                                                            'my' : {
                                                                'hold_id' : hold_id
                                                            }
                                                        }
                                                    }
                                                );
                                                if (window.xulG && typeof window.xulG.on_list_change == 'function') {
                                                    window.xulG.on_list_change(); 
                                                }
                                                obj.list.wrap_in_full_retrieve(
                                                    function() {
                                                        try {
                                                            obj.error.work_log(
                                                                $('offlineStrings').getFormattedString(
                                                                    'staff.circ.work_log_hold_placed.message',
                                                                    [
                                                                        ses('staff_usrname'),
                                                                        obj.holds_map[ hold_id ].patron_last,
                                                                        obj.holds_map[ hold_id ].patron_barcode,
                                                                        hold_id,
                                                                        obj.holds_map[ hold_id ].hold.hold_type()
                                                                    ]
                                                                ), {
                                                                    'au_id' : obj.holds_map[ hold_id ].hold.usr(),
                                                                    'au_family_name' : obj.holds_map[ hold_id ].patron_family_name,
                                                                    'au_barcode' : obj.holds_map[ hold_id ].patron_barcode
                                                                }
                                                            );
                                                        } catch(F) {
                                                            obj.error.standard_unexpected_error_alert('holds.js, opac_hold_placed(), work_log: ',F);
                                                        }
                                                    }
                                                );
                                            } catch(E) {
                                                obj.error.standard_unexpected_error_alert('holds.js, opac_hold_placed(): ',E);
                                            }
                                        },
                                        'get_barcode' : xulG.get_barcode,
                                        'get_barcode_and_settings' : xulG.get_barcode_and_settings,
                                        'patron_barcode' : obj.patron_barcode
                                    },
                                    'url_prefix' : xulG.url_prefix,
                                    'url' : xulG.url_prefix(urls.browser)
                                };
                                xulG.display_window.g.patron.right_deck.set_iframe( urls.XUL_REMOTE_BROWSER + '?patron_hold=1', {}, content_params);
                            } catch(E) {
                                obj.error.sdump('D_ERROR','cmd_search_opac: ' + E);
                            }

                        }
                    ]
                }
            }
        );

        obj.determine_hold_interface_type();
        var x_fetch_more = document.getElementById('fetch_more');
        var x_lib_type_menu = document.getElementById('lib_type_menu');
        var x_lib_menu_placeholder = document.getElementById('lib_menu_placeholder');
        var x_lib_filter_checkbox = document.getElementById('lib_filter_checkbox');
        var x_show_cancelled_deck = document.getElementById('show_cancelled_deck');
        var x_clear_shelf_widgets = document.getElementById('clear_shelf_widgets');
        var x_expired_checkbox = document.getElementById('expired_checkbox');
        var x_print_full_pull_list = document.getElementById('print_full_btn');
        var x_print_full_pull_list_alt = document.getElementById('print_alt_btn');
        var x_simplified_pull_list = document.getElementById('simplified_pull_list_btn');
        switch(obj.hold_interface_type) {
            case 'shelf':
                obj.render_lib_menus({'pickup_lib':true});
                if (x_lib_filter_checkbox) x_lib_filter_checkbox.checked = true;
                if (x_lib_type_menu) x_lib_type_menu.hidden = false;
                if (x_lib_menu_placeholder) x_lib_menu_placeholder.hidden = false;
                if (x_clear_shelf_widgets) x_clear_shelf_widgets.hidden = false;
                if (x_print_full_pull_list_alt) x_print_full_pull_list_alt.hidden = true;
                if (x_simplified_pull_list) x_simplified_pull_list.hidden = true;
            break;
            case 'pull' :
                if (x_fetch_more) x_fetch_more.hidden = false;
                if (x_print_full_pull_list) x_print_full_pull_list.hidden = false;
                if (x_print_full_pull_list_alt) x_print_full_pull_list_alt.hidden = false;
                if (x_lib_type_menu) x_lib_type_menu.hidden = true;
                if (x_lib_menu_placeholder) x_lib_menu_placeholder.hidden = true;
                if (x_simplified_pull_list) x_simplified_pull_list.hidden = false;
            break;
            case 'record' :
                obj.render_lib_menus({'pickup_lib':true,'request_lib':true});
                if (x_lib_filter_checkbox) x_lib_filter_checkbox.hidden = false;
                if (x_lib_type_menu) x_lib_type_menu.hidden = false;
                if (x_print_full_pull_list_alt) x_print_full_pull_list_alt.hidden = true;
                if (x_lib_menu_placeholder) x_lib_menu_placeholder.hidden = false;
                if (x_simplified_pull_list) x_simplified_pull_list.hidden = true;
            break;
            default:
                if (obj.controller.view.cmd_search_opac) obj.controller.view.cmd_search_opac.setAttribute('hidden', false);
                if (x_fetch_more) x_fetch_more.hidden = true;
                if (x_lib_type_menu) x_lib_type_menu.hidden = true;
                if (x_lib_menu_placeholder) x_lib_menu_placeholder.hidden = true;
                if (x_show_cancelled_deck) x_show_cancelled_deck.hidden = false;
                if (x_print_full_pull_list_alt) x_print_full_pull_list_alt.hidden = true;
                if (x_simplified_pull_list) x_simplified_pull_list.hidden = true;
            break;
        }
        setTimeout( // We do this because render_lib_menus above creates and appends a DOM node, but until this thread exits, it doesn't really happen
            function() {
                if (x_lib_filter_checkbox) if (!x_lib_filter_checkbox.checked) {
                    if (x_lib_type_menu) x_lib_type_menu.disabled = true;
                    if (obj.controller.view.lib_menu) obj.controller.view.lib_menu.disabled = true;
                }
                obj.controller.render();
                if (params['clear']) {
                    JSAN.use('util.widgets');
                    var x = document.getElementById('expired_checkbox');
                    x.checked = true;
                    obj.expired = true;
                    util.widgets.dispatch('command','cmd_clear_expired_onshelf_holds');
                } else {
                    obj.retrieve(true);
                }

                obj.controller.view.cmd_retrieve_patron.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_edit_pickup_lib.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_edit_phone_notify.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_edit_email_notify.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_edit_thaw_date.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_activate.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_suspend.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_edit_selection_depth.setAttribute('disabled','true');
                obj.controller.view.cmd_alt_view.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_retarget.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_cancel.setAttribute('disabled','true');
                obj.controller.view.cmd_holds_uncancel.setAttribute('disabled','true');
                obj.controller.view.cmd_show_catalog.setAttribute('disabled','true');
            }, 0
        );

        $('cmd_alt_view').setAttribute('disabled','true');
        xulG.when_done = function() {
            $('cmd_alt_view').setAttribute('ready','true');
            if ($('cmd_alt_view').getAttribute('rendering_rows') != 'true') {
                $('cmd_alt_view').setAttribute('disabled','false');
            }
            dump('hold details UI ready\n');
        }
        netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
        JSAN.use('util.browser');
        obj.browser = new util.browser();
        obj.browser.init(
            {
                'url' : urls.XUL_HOLD_DETAILS,
                'push_xulG' : true,
                'alt_print' : false,
                'browser_id' : 'hold_detail_frame',
                'passthru_content_params' : xulG
            }
        );

    },

    'determine_hold_interface_type' : function() {
        var obj = this;
        if (obj.patron_id) { /*************************************************** PATRON ******************************/
            obj.hold_interface_type = 'patron';
        } else if (obj.docid) { /*************************************************** RECORD ******************************/
            obj.hold_interface_type = 'record';
        } else if (obj.pull) { /*************************************************** PULL ******************************/
            obj.hold_interface_type = 'pull';
        } else if (obj.shelf) { /*************************************************** HOLD SHELF ******************************/
            obj.hold_interface_type = 'shelf';
        } else { /*************************************************** PULL ******************************/
            obj.hold_interface_type = 'pull';
        }
    },

    'clear_and_retrieve' : function() {
        try {
            this.list.clear();
            this.pull_from_shelf_interface.current.offset = this.pull_from_shelf_interface._default.offset;
            this.retrieve();
            if (window.xulG && typeof window.xulG.on_list_change == 'function') {
                window.xulG.on_list_change(); 
            }
        } catch(E) {
            this.error.standard_unexpected_error_alert('holds.js, clear_and_retrieve(): ',E);
        }
    },

    'retrieve' : function() {
        var obj = this; var holds = [];
        if (window.xulG && window.xulG.holds) {
            holds = window.xulG.holds;
        } else {
            var method; var params = [ ses() ];
            switch(obj.hold_interface_type) {
                case 'patron' :
                    if (document.getElementById('show_cancelled_deck').selectedIndex == 0) {
                        method = 'FM_AHR_ID_LIST_RETRIEVE_VIA_AU.authoritative';
                    } else {
                        method = 'FM_AHR_CANCELLED_ID_LIST_RETRIEVE_VIA_AU.authoritative';
                    }
                    params.push( obj.patron_id );
                    obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','true');
                break;
                case 'record' :
                    method = 'FM_AHR_RETRIEVE_ALL_VIA_BRE';
                    params.push( obj.docid );
                    var x_lib_filter = document.getElementById('lib_filter_checkbox');
                    var x_lib_type_menu = document.getElementById('lib_type_menu');
                    if (x_lib_filter) {
                        if (x_lib_filter.checked) {
                            if (x_lib_type_menu && obj.controller.view.lib_menu) {
                                var x = {};
                                x[ x_lib_type_menu.value ] = obj.controller.view.lib_menu.value;
                                params.push( x );
                            }
                        }
                    }
                    obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','false');
                break;
                case 'shelf' :
                    if (obj.expired) {
                        method = 'FM_AHR_ID_LIST_EXPIRED_ONSHELF_RETRIEVE';
                    } else {
                        method = 'FM_AHR_ID_LIST_ONSHELF_RETRIEVE';
                    }
                    params.push( obj.filter_lib || obj.data.list.au[0].ws_ou() );
                    obj.controller.view.cmd_retrieve_patron.setAttribute('hidden','false');
                break;
                case 'pull' :
                default:
                    method = 'FM_AHR_ID_LIST_PULL_LIST';
                    params.push( obj.pull_from_shelf_interface.current.limit ); params.push( obj.pull_from_shelf_interface.current.offset );
                    var x = document.getElementById('hold_count');
                    if (x) {
                        obj.network.simple_request('FM_AHR_PULL_LIST_COUNT',[ses()],function(req) {
                            var count = req.getResultObject();
                            if (typeof count.ilsevent == 'undefined' && count != null) {
                                x.setAttribute('value', document.getElementById('patronStrings').getFormattedString(
                                    'staff.patron.holds.total_count',
                                    [ count ]
                                ));
                                x.hidden = false;
                            }
                        });
                    }
                break;
            }
            var robj = obj.network.simple_request( method, params );
            if (robj != null && typeof robj.ilsevent != 'undefined') throw(robj);
            if (method == 'FM_AHR_RETRIEVE_ALL_VIA_BRE') {
                holds = [];
                if (robj != null) {
                    holds = holds.concat( robj.copy_holds );
                    holds = holds.concat( robj.recall_holds );
                    holds = holds.concat( robj.force_holds );
                    holds = holds.concat( robj.volume_holds );
                    holds = holds.concat( robj.title_holds );
                    holds = holds.concat( robj.part_holds );
                    holds = holds.concat( robj.issuance_holds );
                    holds = holds.concat( robj.metarecord_holds );
                    holds = holds.sort();
                }
            } else {
                if (robj == null ) {
                    holds = [];
                } else {
                    if (typeof robj.length == 'undefined') {
                        holds = [ robj ];
                    } else {
                        holds = robj;
                    }
                }
            }
            holds.reverse();
            //alert('method = ' + method + ' params = ' + js2JSON(params));
        }

        var x_fetch_more = document.getElementById('fetch_more');
        if (holds.length == 0) {
            if (x_fetch_more) x_fetch_more.disabled = true;
        } else {
            if (x_fetch_more) x_fetch_more.disabled = false;
            obj.render(holds);
        }

    },

    'render' : function(holds) {
        try {
            var obj = this;

            function list_append(hold_id) {
                obj.list.append(
                    {
                        'row' : {
                            'my' : {
                                'hold_id' : hold_id,
                                'post_clear_shelf_action' : obj.post_clear_shelf_hold_action_map[ hold_id ]
                            }
                        },
                        'to_bottom' : true
                    }
                );
            }

            function gen_list_append(hold) {
                return function() {
                    if (typeof obj.controller.view.lib_menu == 'undefined') {
                        list_append(typeof hold == 'object' ? hold.id() : hold);
                    } else {
                        list_append(typeof hold == 'object' ? hold.id() : hold);
                    }
                };
            }

            //obj.list.clear();

            JSAN.use('util.exec'); var exec = new util.exec(2);
            var rows = [];
            for (var i in holds) {
                rows.push( gen_list_append(holds[i]) );
            }
            exec.chain( rows );

        } catch(E) {
            this.error.standard_unexpected_error_alert('holds.js, render():',E);
        }
    },

    'render_lib_menus' : function(types) {
        try {
            var obj = this;
            JSAN.use('util.widgets'); JSAN.use('util.functional'); JSAN.use('util.fm_utils');

            var x = document.getElementById('lib_type_menu');
            if (types) {
                var nodes = x.firstChild.childNodes;
                for (var i = 0; i < nodes.length; i++) nodes[i].hidden = true;
                for (var i in types) document.getElementById(i).hidden = false;
            }
            x.setAttribute('oncommand','g.holds.clear_and_retrieve()');

            x = document.getElementById('lib_menu_placeholder');
            util.widgets.remove_children( x );

            JSAN.use('util.file');
            var file = new util.file('offline_ou_list');
            if (file._file.exists()) {
                var list_data = file.get_object(); file.close();
                var ml = util.widgets.make_menulist( list_data[0], obj.data.list.au[0].ws_ou() );
                ml.setAttribute('id','lib_menu');
                x.appendChild( ml );
                ml.addEventListener(
                    'command',
                    function(ev) {
                        obj.filter_lib = ev.target.value;
                        obj.clear_and_retrieve();
                    },
                    false
                );
                obj.controller.view.lib_menu = ml;
            } else {
                throw($("patronStrings").getString('staff.patron.holds.lib_menus.missing_library_list'));
            }

        } catch(E) {
            this.error.standard_unexpected_error_alert('rendering lib menu',E);
        }
    },

    'cmd_clear_expired_onshelf_holds' : function() {
        var obj = this;
        try {
            // Disable anything such as filters that can have us accidentally
            // lose these non-repeatable results.  Well, now that they're cached
            // it's less of an issue.
            if ($('lib_filter_checkbox')) {
                $('lib_filter_checkbox').checked = false;
            }
            if ($('lib_type_menu')) {
                $('lib_type_menu').disabled = true;
            }
            if ($('lib_menu_placeholder')) {
                $('lib_menu_placeholder').firstChild.disabled = true;
            }
            obj.controller.view.cmd_view_expired_onshelf_holds.setAttribute(
                'disabled', 'true');
            obj.controller.view.cmd_clear_expired_onshelf_holds.setAttribute(
                'disabled', 'true');

            // I could put this with the "retrieval" methods, but since it has
            // side effects, seems cleaner to invoke it here
            var robj = obj.network.simple_request(
                'CLEAR_HOLD_SHELF',
                [
                    ses(),
                    obj.filter_lib || obj.data.list.au[0].ws_ou()
                ]
            );
            if (typeof robj.ilsevent != 'undefined') { throw(robj); }
            if (typeof robj.cache_key == 'undefined') { throw(robj); }

            var cache_key = robj.cache_key;

            // id's in xulG.holds will prevent the normal retrieval method from
            // firing.  Let's put our affected hold.id's in here:
            xulG.holds = [];

            // Start the progress meter
            $('progress').value = 0;
            $('progress').hidden = false;

            // Fetch the affected holds
            fieldmapper.standardRequest(
                [ 'open-ils.circ', 'open-ils.circ.hold.clear_shelf.get_cache' ],
                {
                    'async' : true,
                    'params' : [ ses(), cache_key ],
                    'onresponse' : function(r) {
                        dojo.forEach(
                            openils.Util.readResponse(r),
                            function(resp) {
                                if (resp.maximum) {
                                    $('progress').value = Number(resp.progress)
                                        * 100/resp.maximum;
                                    return;
                                }
                                obj.post_clear_shelf_hold_action_map[
                                    resp.hold_details.id
                                ] = resp.action;
                                xulG.holds.push( resp.hold_details.id );
                            }
                        )
                    },
                    'oncomplete' : function() {
                        obj.clear_and_retrieve();
                        $('progress').hidden = true;
                    }
                }
            );

        } catch(E) {
            if (E.ilsevent == 5000 /* PERM_FAILURE */ ) {
                return; /* handled by network.js */
            }
            obj.error.standard_unexpected_error_alert(
                'Error in holds.js, cmd_clear_expired_onshelf_holds', E);
        }
    }
}

dump('exiting patron.holds.js\n');
