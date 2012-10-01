var docid; var marc_html; var top_pane; var bottom_pane; var opac_browser; var opac_url;

var marc_view_reset = true;
var marc_edit_reset = true;
var copy_browser_reset = true;
var manage_parts_reset = true;
var manage_multi_home_reset = true;
var hold_browser_reset = true;
var serctrl_view_reset = true;

function $(id) { return document.getElementById(id); }

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw(document.getElementById('offlineStrings').getString('common.jsan.missing')); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for cat/opac.xul');

        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
        XML_HTTP_SERVER = g.data.server_unadorned;

        // Pull in local customizations
        var r = new XMLHttpRequest();
        var custom_js = xulG.url_prefix('CUSTOM_JS');
        r.open("GET", custom_js, false);
        r.send(null);
        if (r.status == 200) {
            dump('Evaluating ' + custom_js + '\n');
            eval( r.responseText );
        }

        window.help_context_set_locally = true;

        JSAN.use('util.network'); g.network = new util.network();

        g.cgi = new CGI();
        try { authtime = g.cgi.param('authtime') || xulG.authtime; } catch(E) { g.error.sdump('D_ERROR',E); }
        try { docid = g.cgi.param('docid') || xulG.docid; } catch(E) { g.error.sdump('D_ERROR',E); }
        try { opac_url = g.cgi.param('opac_url') || xulG.opac_url; } catch(E) { g.error.sdump('D_ERROR',E); }
        try { g.view_override = g.cgi.param('default_view') || xulG.default_view; } catch(E) { g.error.sdump('D_ERROR',E); }

        JSAN.use('util.deck');
        top_pane = new util.deck('top_pane');
        bottom_pane = new util.deck('bottom_pane');

        set_opac();

    } catch(E) {
        var err_msg = document.getElementById("offlineStrings").getFormattedString("common.exception", ["cat/opac.xul", E]);
        try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
        alert(err_msg);
    }
}

function default_focus() {
    opac_wrapper_set_help_context(); 
}

function opac_wrapper_set_help_context() {
    try {
        dump('Entering opac.js, opac_wrapper_set_help_context\n');
        var cw = bottom_pane.get_contentWindow(); 
        if (cw && typeof cw['location'] != 'undefined') {
            if (typeof cw.help_context_set_locally == 'undefined') {
                var help_params = {
                    'protocol' : cw.location.protocol,
                    'hostname' : cw.location.hostname,
                    'port' : cw.location.port,
                    'pathname' : cw.location.pathname,
                    'src' : ''
                };
                xulG.set_help_context(help_params);
            } else {
                dump('\tcw.help_context_set_locally = ' + cw.help_context_set_locally + '\n');
                if (typeof cw.default_focus == 'function') {
                    cw.default_focus();
                }
            }
        } else {
            dump('opac.js: problem in opac_wrapper_set_help_context(): bottom_pane = ' + bottom_pane + ' cw = ' + cw + '\n');
            dump('\tcw.location = ' + cw.location + '\n');
        }
    } catch(E) {
        // We can expect some errors here if this called before the DOM is ready.  Easiest to just trap and ignore
        dump('Error in opac.js, opac_wrapper_set_help_context(): ' + E + '\n');
    }
}

function set_brief_view() {
    var url = xulG.url_prefix( 'XUL_BIB_BRIEF?docid=' ) + window.escape(docid); 
    dump('spawning ' + url + '\n');

    var content_params = {
        'set_tab_name' : function(n) {
            if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
                try { window.xulG.set_tab_name(document.getElementById('offlineStrings').getFormattedString("cat.bib_record", [n])); } catch(E) { alert(E); }
            } else {
                dump('no set_tab_name\n');
            }
        }
    };

    ["url_prefix", "new_tab", "set_tab", "close_tab", "new_patron_tab",
        "set_patron_tab", "volume_item_creator", "get_new_session",
        "holdings_maintenance_tab", "open_chrome_window", "url_prefix",
        "network_meter", "page_meter", "set_statusbar", "set_help_context",
        "get_barcode", "reload_opac", "get_barcode_and_settings"
    ].forEach(function(k) { content_params[k] = xulG[k]; });

    top_pane.set_iframe( 
        url,
        {},
        content_params
    );
}

function set_marc_view() {
    g.view = 'marc_view';
    if (marc_view_reset) {
        bottom_pane.reset_iframe( xulG.url_prefix( 'XUL_MARC_VIEW?docid=' ) + window.escape(docid),{},xulG);
        marc_view_reset = false;
    } else {
        bottom_pane.set_iframe( xulG.url_prefix( 'XUL_MARC_VIEW?docid=' ) + window.escape(docid),{},xulG);
    }
    opac_wrapper_set_help_context(); 
    bottom_pane.get_contentWindow().addEventListener('load',opac_wrapper_set_help_context,false);
}

function set_marc_edit() {
    g.view = 'marc_edit';
    var a =    xulG.url_prefix( 'XUL_MARC_EDIT' );
    var b =    {};
    var c =    {
            'marc_control_number_identifier' : g.data.hash.aous['cat.marc_control_number_identifier'] || 'Set cat.marc_control_number_identifier in Library Settings',
            'record' : { 'url' : '/opac/extras/supercat/retrieve/marcxml/record/' + docid, "id": docid, "rtype": "bre" },
            'fast_add_item' : function(doc_id,cn_label,cp_barcode) {
                try {
                    var cat = { util: {} }; /* FIXME: kludge since we can't load remote JSAN libraries into chrome */
                    cat.util.spawn_copy_editor = function(params) {
                        try {
                            if (!params.copy_ids && !params.copies) return;
                            if (params.copy_ids && params.copy_ids.length == 0) return;
                            if (params.copies && params.copies.length == 0) return;
                            if (params.copy_ids) params.copy_ids = js2JSON(params.copy_ids); // legacy
                            if (!params.caller_handles_update) params.handle_update = 1; // legacy

                            var obj = {};
                            JSAN.use('util.network'); obj.network = new util.network();
                            JSAN.use('util.error'); obj.error = new util.error();
                        
                            var title = '';
                            if (params.copy_ids && params.copy_ids.length > 1 && params.edit == 1)
                                title = $("offlineStrings").getString('staff.cat.util.copy_editor.batch_edit');
                            else if(params.copies && params.copies.length > 1 && params.edit == 1)
                                title = $("offlineStrings").getString('staff.cat.util.copy_editor.batch_view');
                            else if(params.copy_ids && params.copy_ids.length == 1)
                                title = $("offlineStrings").getString('staff.cat.util.copy_editor.edit');
                            else
                                title = $("offlineStrings").getString('staff.cat.util.copy_editor.view');

                            JSAN.use('util.window'); var win = new util.window();
                            var my_xulG = win.open(
                                (urls.XUL_COPY_EDITOR),
                                title,
                                'chrome,modal,resizable',
                                params
                            );
                            if (!my_xulG.copies && params.edit) {
                            } else {
                                return my_xulG.copies;
                            }
                            return [];
                        } catch(E) {
                            JSAN.use('util.error'); var error = new util.error();
                            error.standard_unexpected_error_alert('Error in chrome/content/cat/opac.js, cat.util.spawn_copy_editor',E);
                        }
                    }
                    cat.util.fast_item_add = function(doc_id,cn_label,cp_barcode) {
                        var error;
                        try {

                            JSAN.use('util.error'); error = new util.error();
                            JSAN.use('util.network'); var network = new util.network();

                            var acn_blob = network.simple_request(
                                'FM_ACN_FIND_OR_CREATE',
                                [ ses(), cn_label, doc_id, ses('ws_ou') ]
                            );

                            if (typeof acn_blob.ilsevent != 'undefined') {
                                error.standard_unexpected_error_alert('Error in chrome/content/cat/opac.js, cat.util.fast_item_add', acn_blob);
                                return;
                            }

                            // Get the default copy status; default to available if unset, per 1.6
                            var fast_ccs = g.data.hash.aous['cat.default_copy_status_fast'] || 0;

                            var copy_obj = new acp();
                            copy_obj.id( -1 );
                            copy_obj.isnew('1');
                            copy_obj.barcode( cp_barcode );
                            copy_obj.call_number( acn_blob.acn_id );
                            copy_obj.circ_lib( ses('ws_ou') );
                            /* FIXME -- use constants */
                            copy_obj.deposit(0);
                            copy_obj.price(0);
                            copy_obj.deposit_amount(0);
                            copy_obj.fine_level(2); // Normal
                            copy_obj.loan_duration(2); // Normal
                            copy_obj.location(1); // Stacks
                            copy_obj.status(fast_ccs);
                            copy_obj.circulate(get_db_true());
                            copy_obj.holdable(get_db_true());
                            copy_obj.opac_visible(get_db_true());
                            copy_obj.ref(get_db_false());
                            copy_obj.mint_condition(get_db_true());

                            JSAN.use('util.window'); var win = new util.window();

                            var unified_interface = String( data.hash.aous['ui.unified_volume_copy_editor'] ) == 'true';
                            if (unified_interface) {
                                var horizontal_interface = String( data.hash.aous['ui.cat.volume_copy_editor.horizontal'] ) == 'true';
                                var url = window.xulG.url_prefix( horizontal_interface ? 'XUL_VOLUME_COPY_CREATOR_HORIZONTAL' : 'XUL_VOLUME_COPY_CREATOR' );
                                var w = xulG.set_tab(
                                    url,
                                    {
                                        'tab_name' : document.getElementById('offlineStrings').getFormattedString(
                                            'cat.bib_record',
                                            [ doc_id ]
                                        )
                                    },
                                    {
                                        'doc_id' : doc_id, 
                                        'existing_copies' : [ copy_obj ],
                                        'load_opac_when_done' : true,
                                        'labels_in_new_tab' : true
                                    }
                                );

                            } else {
                                var x = cat.util.spawn_copy_editor( { 'handle_update' : 1, 'edit' : 1, 'docid' : doc_id, 'copies' : [ copy_obj ] });
                                xulG.reload_opac();
                                return x;
                            }

                        } catch(E) {
                            if (error) error.standard_unexpected_error_alert('Error in chrome/content/cat/opac.js, cat.util.fast_item_add #2',E); else alert('FIXME: ' + E);
                        }
                    }
                    return cat.util.fast_item_add(doc_id,cn_label,cp_barcode);
                } catch(E) {
                    alert('Error in chrome/content/cat/opac.js, set_marc_edit, fast_item_add: ' + E);
                }
            },
            'save' : {
                'label' : document.getElementById('offlineStrings').getString('cat.save_record'),
                'func' : function (new_marcxml) {
                    try {
                        var r = g.network.simple_request('MARC_XML_RECORD_UPDATE', [ ses(), docid, new_marcxml ]);
                        marc_view_reset = true;
                        copy_browser_reset = true;
                        hold_browser_reset = true;
                        xulG.reload_opac();
                        if (typeof r.ilsevent != 'undefined') {
                            throw(r);
                        } else {
                            return {
                                'id' : r.id(),
                                'oncomplete' : function() {}
                            };
                        }
                    } catch(E) {
                            g.error.standard_unexpected_error_alert(document.getElementById('offlineStrings').getString("cat.save.failure"), E);
                    }
                }
            },
            'lock_tab' : xulG.lock_tab,
            'unlock_tab' : xulG.unlock_tab
        };
    if (marc_edit_reset) {
        bottom_pane.reset_iframe( a,b,c );
        marc_edit_reset = false;
    } else {
        bottom_pane.set_iframe( a,b,c );
    }
    opac_wrapper_set_help_context(); 
    bottom_pane.get_contentWindow().addEventListener('load',opac_wrapper_set_help_context,false);
}

function set_copy_browser() {
    g.view = 'copy_browser';
    if (copy_browser_reset) {
        bottom_pane.reset_iframe( xulG.url_prefix( 'XUL_COPY_VOLUME_BROWSE?docid=' ) + window.escape(docid),{},xulG);
        copy_browser_reset =false;
    } else {
        bottom_pane.set_iframe( xulG.url_prefix( 'XUL_COPY_VOLUME_BROWSE?docid=' ) + window.escape(docid),{},xulG);
    }
    opac_wrapper_set_help_context(); 
    bottom_pane.get_contentWindow().addEventListener('load',opac_wrapper_set_help_context,false);
}

function set_hold_browser() {
    g.view = 'hold_browser';
    if (hold_browser_reset) {
        bottom_pane.reset_iframe( xulG.url_prefix( 'XUL_HOLDS_BROWSER?docid=' ) + window.escape(docid),{},xulG);
        hold_browser_reset = false;
    } else {
        bottom_pane.set_iframe( xulG.url_prefix( 'XUL_HOLDS_BROWSER?docid=' ) + window.escape(docid),{},xulG);
    }
    opac_wrapper_set_help_context(); 
    bottom_pane.get_contentWindow().addEventListener('load',opac_wrapper_set_help_context,false);
}


function open_acq_orders() {
    try {
        var content_params = {
            "session": ses(),
            "authtime": ses("authtime"),
            "no_xulG": false,
            "show_nav_buttons": true,
            "show_print_button": false
        };

        ["url_prefix", "new_tab", "set_tab", "close_tab", "new_patron_tab",
            "set_patron_tab", "volume_item_creator", "get_new_session",
            "holdings_maintenance_tab", "set_tab_name", "open_chrome_window",
            "url_prefix", "network_meter", "page_meter", "set_statusbar",
            "set_help_context", "get_barcode", "reload_opac", 
            "get_barcode_and_settings"
        ].forEach(function(k) { content_params[k] = xulG[k]; });

        var loc = urls.XUL_BROWSER + "?url=" + window.escape(
            xulG.url_prefix("ACQ_LINEITEM") +
            docid + "?target=bib"
        );
        xulG.new_tab(
            loc, {
                "tab_name": $("offlineStrings").getString(
                    "staff.cat.opac.related_items"
                ),
                "browser": false
            }, content_params
        );
    } catch (E) {
        g.error.sdump("D_ERROR", E);
    }
}

function open_alt_serial_mgmt() {
    try {
        var content_params = {
            "session": ses(),
            "authtime": ses("authtime"),
            "show_nav_buttons": true,
            "no_xulG": false,
            "show_print_button": false,
            "passthru_content_params": {
                "reload_opac": xulG.reload_opac
            }
        };

        ["url_prefix", "new_tab", "set_tab", "close_tab", "new_patron_tab",
            "set_patron_tab", "volume_item_creator", "get_new_session",
            "holdings_maintenance_tab", "set_tab_name", "open_chrome_window",
            "url_prefix", "network_meter", "page_meter", "set_statusbar",
            "set_help_context", "get_barcode", "reload_opac",
            "get_barcode_and_settings"
        ].forEach(function(k) { content_params[k] = xulG[k]; });

        var loc = urls.XUL_BROWSER + "?url=" + window.escape(
            xulG.url_prefix("SERIAL_LIST_SUBSCRIPTION?record_entry=") +
            docid
        );
        xulG.new_tab(
            loc, {
                "tab_name": $("offlineStrings").getString(
                    "staff.cat.opac.serial_alt_mgmt"
                ),
                "browser": false
            }, content_params
        );
    } catch (E) {
        g.error.sdump("D_ERROR", E);
    }
}

function set_opac() {
    g.view = 'opac';
    try {
        var content_params = { 
            'show_nav_buttons' : true,
            'show_print_button' : true,
            'passthru_content_params' : { 
                'authtoken' : ses(), 
                'authtime' : ses('authtime'),
                'window_open' : function(a,b,c) {
                    try {
                        return window.open(a,b,c);
                    } catch(E) {
                        g.error.standard_unexpected_error_alert('window_open',E);
                    }
                },
                'get_barcode' : xulG.get_barcode,
                'get_barcode_and_settings' : xulG.get_barcode_and_settings,
                'opac_hold_placed' : function(hold) {
                    try {
                        var hold_id = typeof hold == 'object' ? hold.id() : hold;
                        g.network.simple_request('FM_AHR_BLOB_RETRIEVE.authoritative', [ ses(), hold_id ],
                            function(blob_req) {
                                try {
                                    var blob = blob_req.getResultObject();
                                    if (typeof blob.ilsevent != 'undefined') throw(blob);
                                    g.error.work_log(
                                        $('offlineStrings').getFormattedString(
                                            'staff.circ.work_log_hold_placed.message',
                                            [
                                                ses('staff_usrname'),
                                                blob.patron_last,
                                                blob.patron_barcode,
                                                hold_id,
                                                blob.hold.hold_type()
                                            ]
                                        ), {
                                            'au_id' : blob.hold.usr(),
                                            'au_family_name' : blob.patron_family_name,
                                            'au_barcode' : blob.patron_barcode
                                        }
                                    );
                                } catch(E) {
                                    g.error.standard_unexpected_error_alert('opac.js, opac_hold_placed(), work_log #2: ',E);
                                }
                            }
                        );
                    } catch(F) {
                        g.error.standard_unexpected_error_alert('opac.js, opac_hold_placed(), work_log #1: ',F);
                    }
                }
            },
            'on_url_load' : function(f) {
                var win;
                try {
                    if (typeof f.contentWindow.wrappedJSObject.attachEvt != 'undefined') {
                        win = f.contentWindow.wrappedJSObject;
                    } else {
                        win = f.contentWindow;
                    }
                } catch(E) {
                    win = f.contentWindow;
                }
                win.attachEvt("rdetail", "recordRetrieved",
                    function(id){
                        try {
                            if (docid == id) return;
                            docid = id;
                            refresh_display(id);
                        } catch(E) {
                            g.error.standard_unexpected_error_alert('rdetail -> recordRetrieved',E);
                        }
                    }
                );
                
                g.f_record_start = null; g.f_record_prev = null;
                g.f_record_next = null; g.f_record_end = null;
                g.f_record_back_to_results = null;
                $('record_start').disabled = true; $('record_next').disabled = true;
                $('record_prev').disabled = true; $('record_end').disabled = true;
                $('record_back_to_results').disabled = true;
                $('record_pos').setAttribute('value','');

                function safe_to_proceed() {
                    if (typeof xulG.is_tab_locked == 'undefined') { return true; }
                    if (! xulG.is_tab_locked()) { return true; }
                    var r = window.confirm(
                        document.getElementById('offlineStrings').getString(
                           'generic.unsaved_data_warning'
                        )
                    );
                    if (r) {
                        while ( xulG.unlock_tab() > 0 ) {};
                        return true;
                    } else {
                        return false;
                    }
                }

                win.attachEvt("rdetail", "nextPrevDrawn",
                    function(rIndex,rCount){
                        $('record_pos').setAttribute('value', document.getElementById('offlineStrings').getFormattedString('cat.record.counter', [(1+rIndex), rCount ? rCount : 1]));
                        if (win.rdetailNext) {
                            g.f_record_next = function() {
                                if (safe_to_proceed()) {
                                    g.view_override = g.view;
                                    win.rdetailNext();
                                }
                            }
                            $('record_next').disabled = false;
                        }
                        if (win.rdetailPrev) {
                            g.f_record_prev = function() {
                                if (safe_to_proceed()) {
                                    g.view_override = g.view;
                                    win.rdetailPrev();
                                }
                            }
                            $('record_prev').disabled = false;
                        }
                        if (win.rdetailStart) {
                            g.f_record_start = function() { 
                                if (safe_to_proceed()) {
                                    g.view_override = g.view;
                                    win.rdetailStart();
                                }
                            }
                            $('record_start').disabled = false;
                        }
                        if (win.rdetailEnd) {
                            g.f_record_end = function() { 
                                if (safe_to_proceed()) {
                                    g.view_override = g.view;
                                    win.rdetailEnd();
                                }
                            }
                            $('record_end').disabled = false;
                        }
                        if (win.rdetailBackToResults) {
                            g.f_record_back_to_results = function() {
                                if (safe_to_proceed()) {
                                    g.view_override = g.view;
                                    win.rdetailBackToResults();
                                    if (g.view != "opac") {
                                        set_opac();
                                        opac_wrapper_set_help_context();
                                    }
                                }
                            }
                            $('record_back_to_results').disabled = false;
                        }
                    }
                );

                $('mfhd_add').setAttribute('oncommand','create_mfhd()');
                var mfhd_edit_menu = $('mfhd_edit');
                var mfhd_delete_menu = $('mfhd_delete');

                // clear menus on subsequent loads
                if (mfhd_edit_menu.firstChild) {
                    mfhd_edit_menu.removeChild(mfhd_edit_menu.firstChild);
                    mfhd_delete_menu.removeChild(mfhd_delete_menu.firstChild);
                }

                mfhd_edit_menu.disabled = true;
                mfhd_delete_menu.disabled = true;

                win.attachEvt("rdetail", "MFHDDrawn",
                    function() {
                        if (win.mfhdDetails && win.mfhdDetails.length > 0) {
                            g.mfhd = {};
                            g.mfhd.details = win.mfhdDetails;
                            mfhd_edit_menu.disabled = false;
                            mfhd_delete_menu.disabled = false;
                            for (var i = 0; i < win.mfhdDetails.length; i++) {
                                var mfhd_details = win.mfhdDetails[i];
                                var num = mfhd_details.entryNum;
                                num++;
                                var label = mfhd_details.label + ' (' + num + ')';
                                var item = mfhd_edit_menu.appendItem(label);
                                item.setAttribute('oncommand','open_mfhd_editor('+mfhd_details.id+')');
                                item = mfhd_delete_menu.appendItem(label);
                                item.setAttribute('oncommand','delete_mfhd('+mfhd_details.id+')');
                            }
                        } else if (g.mfhd) { // clear from previous runs if deleting last MFHD
                            delete g.mfhd;
                        }
                        var change_event = document.createEvent("Event");
                        change_event.initEvent("MFHDChange",false,false);
                        window.dispatchEvent(change_event);
                    }
                );
            },
            'url_prefix' : xulG.url_prefix,
        };
        content_params.new_tab = xulG.new_tab;
        content_params.set_tab = xulG.set_tab;
        content_params.close_tab = xulG.close_tab;
        content_params.lock_tab = xulG.lock_tab;
        content_params.unlock_tab = xulG.unlock_tab;
        content_params.inspect_tab = xulG.inspect_tab;
        content_params.is_tab_locked = xulG.is_tab_locked;
        content_params.new_patron_tab = xulG.new_patron_tab;
        content_params.set_patron_tab = xulG.set_patron_tab;
        content_params.volume_item_creator = xulG.volume_item_creator;
        content_params.get_new_session = xulG.get_new_session;
        content_params.holdings_maintenance_tab = xulG.holdings_maintenance_tab;
        content_params.set_tab_name = xulG.set_tab_name;
        content_params.open_chrome_window = xulG.open_chrome_window;
        content_params.url_prefix = xulG.url_prefix;
        content_params.network_meter = xulG.network_meter;
        content_params.page_meter = xulG.page_meter;
        content_params.set_statusbar = xulG.set_statusbar;
        content_params.set_help_context = xulG.set_help_context;
        content_params.get_barcode = xulG.get_barcode;
        content_params.get_barcode_and_settings = xulG.get_barcode_and_settings;

        var secure_opac = true; // default to secure
        var prefs = Components.classes['@mozilla.org/preferences-service;1'].getService(Components.interfaces['nsIPrefBranch']);
        if (prefs.prefHasUserValue('oils.secure_opac')) {
            secure_opac = prefs.getBoolPref('oils.secure_opac');
        }
        dump('secure_opac = ' + secure_opac + '\n');

        if (opac_url) {
            content_params.url = xulG.url_prefix( opac_url, secure_opac );
        } else {
            content_params.url = xulG.url_prefix( 'browser', secure_opac );
        }
        if (g.data.adv_pane) {
            // For fun, we can have no extra params, extra params with &, or extra params with ;.
            if (content_params.url.indexOf('?') < 0)
                content_params.url += '?';
            else if (content_params.url.indexOf('&') >= 0)
                content_params.url += '&';
            else
                content_params.url += ';';
            content_params.url += 'pane=' + g.data.adv_pane;
        }
        browser_frame = bottom_pane.set_iframe( xulG.url_prefix('XUL_BROWSER?name=Catalog'), {}, content_params);
        /* // Remember to use the REMOTE_BROWSER if we ever try to move this to remote xul again
        browser_frame = bottom_pane.set_iframe( xulG.url_prefix('XUL_REMOTE_BROWSER?name=Catalog'), {}, content_params);
        */
    } catch(E) {
        g.error.sdump('D_ERROR','set_opac: ' + E);
    }
    opac_wrapper_set_help_context();
    opac_browser = bottom_pane.get_contentWindow();
    opac_browser.addEventListener('load',opac_wrapper_set_help_context,false);
}

xulG.reload_opac = function() {
    try {
        JSAN.use('util.widgets');
        opac_browser.g.browser.reload();
    } catch(E) {
        g.error.sdump("D_ERROR", 'error reloading opac: ' + E + '\n');
    }
}

function set_serctrl_view() {
    g.view = 'serctrl_view';
    if (serctrl_view_reset) {
        bottom_pane.reset_iframe( xulG.url_prefix( 'XUL_SERIAL_SERCTRL_MAIN?docid=' ) + window.escape(docid), {}, xulG);
        serctrl_view_reset =false;
    } else {
        bottom_pane.set_iframe( xulG.url_prefix( 'XUL_SERIAL_SERCTRL_MAIN?docid=' ) + window.escape(docid), {}, xulG);
    }
}

function create_mfhd() {
    // Check if the source is allowed to have copies, first.
    try {
        var bibObj = g.network.request(
            api.FM_BRE_RETRIEVE_VIA_ID.app,
            api.FM_BRE_RETRIEVE_VIA_ID.method,
            [ ses(), [docid] ]
        );

        bibObj = bibObj[0];

        var cbsObj = g.network.request(
            api.FM_CBS_RETRIEVE_VIA_PCRUD.app,
            api.FM_CBS_RETRIEVE_VIA_PCRUD.method,
            [ ses(), bibObj.source() ]
        );

        if (cbsObj && cbsObj.can_have_copies() != get_db_true()) {
            alert(document.getElementById('offlineStrings').getFormattedString('staff.cat.bib_source.can_have_copies.false', [cbsObj.source()]));
            return;
        }
    } catch(E) {
        g.error.sdump('D_ERROR','can have copies check: ' + E);
        alert('Error in chrome/content/cat/opac.js, create_mfhd(): ' + E);
        return;
    }

    try {
        JSAN.use('util.window'); var win = new util.window();
        var select_aou_window = win.open(
            xulG.url_prefix('XUL_SERIAL_SELECT_AOU'),
            '_blank',
            'chrome,resizable,modal,centerscreen',
            {'server_unadorned' : g.data.server_unadorned}
        );
        if (!select_aou_window.create_mfhd_aou) {
            return;
        }
        var r = g.network.simple_request(
                'MFHD_XML_RECORD_CREATE',
                [ ses(), 1, select_aou_window.create_mfhd_aou, docid ]
            );
        if (typeof r.ilsevent != 'undefined') {
            throw(r);
        }
        alert("MFHD record created."); //TODO: better success message
        xulG.reload_opac(); // browser_frame.contentWindow.g.browser.controller.view.cmd_reload.doCommand();
    } catch(E) {
        g.error.standard_unexpected_error_alert("Create MFHD failed", E); //TODO: better error handling
    }
}

function delete_mfhd(sre_id) {
    if (g.error.yns_alert(
        document.getElementById('offlineStrings').getFormattedString('serial.delete_record.confirm', [sre_id]),
        document.getElementById('offlineStrings').getString('cat.opac.delete_record'),
        document.getElementById('offlineStrings').getString('cat.opac.delete'),
        document.getElementById('offlineStrings').getString('cat.opac.cancel'),
        null,
        document.getElementById('offlineStrings').getString('cat.opac.record_deleted.confirm')) == 0) {
        var robj = g.network.request(
                'open-ils.permacrud',
                'open-ils.permacrud.delete.sre',
                [ses(),sre_id]);
        if (typeof robj.ilsevent != 'undefined') {
            alert(document.getElementById('offlineStrings').getFormattedString('cat.opac.record_deleted.error',  [docid, robj.textcode, robj.desc]) + '\n');
        } else {
            alert(document.getElementById('offlineStrings').getString('cat.opac.record_deleted'));
            xulG.reload_opac(); // browser_frame.contentWindow.g.browser.controller.view.cmd_reload.doCommand();
        }
    }
}

function open_mfhd_editor(sre_id) {
    try {
        var r = g.network.simple_request(
                'FM_SRE_RETRIEVE',
                [ ses(), sre_id ]
              );
        if (typeof r.ilsevent != 'undefined') {
            throw(r);
        }
        open_marc_editor(r, 'MFHD');
    } catch(E) {
        g.error.standard_unexpected_error_alert("Create MFHD failed", E); //TODO: better error handling
    }
}

function open_marc_editor(rec, label) {
    /* Prevent the spawned MARC editor from making its title bar inaccessible */
    var initHeight = self.outerHeight - 40;
    /* Setting an explicit height results in a super skinny window, so fix that up */
    var initWidth = self.outerWidth / 2;
    win = window.open( xulG.url_prefix('XUL_MARC_EDIT'), '', 'chrome,resizable,height=' + initHeight + ',width=' + initWidth );

    win.xulG = {
        record : {marc : rec.marc()},
        save : {
            label: 'Save ' + label,
            func: function(xmlString) {  // TODO: switch to pcrud, or define an sre update method in Serial.pm?
                var method = 'open-ils.permacrud.update.' + rec.classname;
                rec.marc(xmlString);
                g.network.request(
                    'open-ils.permacrud', method,
                    [ses(), rec]
                );
                xulG.reload_opac();
            }
        }
    };
}

function bib_in_new_tab() {
    try {
        var url = browser_frame.contentWindow.g.browser.controller.view.browser_browser.contentWindow.wrappedJSObject.location.href;
        var content_params = { 'session' : ses(), 'authtime' : ses('authtime'), 'opac_url' : url };
        content_params.url_prefix = xulG.url_prefix;
        content_params.new_tab = xulG.new_tab;
        content_params.set_tab = xulG.set_tab;
        content_params.close_tab = xulG.close_tab;
        content_params.lock_tab = xulG.lock_tab;
        content_params.unlock_tab = xulG.unlock_tab;
        content_params.inspect_tab = xulG.inspect_tab;
        content_params.is_tab_locked = xulG.is_tab_locked;
        content_params.new_patron_tab = xulG.new_patron_tab;
        content_params.set_patron_tab = xulG.set_patron_tab;
        content_params.volume_item_creator = xulG.volume_item_creator;
        content_params.get_new_session = xulG.get_new_session;
        content_params.holdings_maintenance_tab = xulG.holdings_maintenance_tab;
        content_params.set_tab_name = xulG.set_tab_name;
        content_params.open_chrome_window = xulG.open_chrome_window;
        content_params.url_prefix = xulG.url_prefix;
        content_params.network_meter = xulG.network_meter;
        content_params.page_meter = xulG.page_meter;
        content_params.set_statusbar = xulG.set_statusbar;
        content_params.set_help_context = xulG.set_help_context;
        content_params.get_barcode = xulG.get_barcode;
        content_params.get_barcode_and_settings = xulG.get_barcode_and_settings;

        xulG.new_tab(xulG.url_prefix('XUL_OPAC_WRAPPER'), {}, content_params);
    } catch(E) {
        g.error.sdump('D_ERROR',E);
    }
}

function batch_receive_in_new_tab() {
    try {
        var content_params = {"session": ses(), "authtime": ses("authtime")};

        ["url_prefix", "new_tab", "set_tab", "close_tab", "new_patron_tab",
            "set_patron_tab", "volume_item_creator", "get_new_session",
            "holdings_maintenance_tab", "set_tab_name", "open_chrome_window",
            "url_prefix", "network_meter", "page_meter", "set_statusbar",
            "set_help_context", "get_barcode", "reload_opac",
            "get_barcode_and_settings"
        ].forEach(function(k) { content_params[k] = xulG[k]; });

        xulG.new_tab(
            xulG.url_prefix('XUL_SERIAL_BATCH_RECEIVE?docid=') +
                window.escape(docid), {
                "tab_name": $("offlineStrings").getString(
                    "menu.cmd_serial_batch_receive.tab"
                )
            }, content_params
        );
    } catch (E) {
        g.error.sdump("D_ERROR", E);
    }
}

function remove_me() {
    var url = xulG.url_prefix( 'XUL_BIB_BRIEF?docid=' ) + window.escape(docid);
    dump('removing ' + url + '\n');
    try { top_pane.remove_iframe( url ); } catch(E) { dump(E + '\n'); }
    $('nav').setAttribute('hidden','true');
}

function add_to_bucket() {
    JSAN.use('util.window'); var win = new util.window();
    win.open(
        xulG.url_prefix('XUL_RECORD_BUCKETS_QUICK'),
        '_blank',
        'chrome,resizable,modal,centerscreen',
        {
            record_ids: [ docid ]
        }
    );
}

// FIXME: now duplicated in cat.util, which we can't import here, though maybe
// we can do something at build time
function mark_for_overlay() {
    g.data.marked_record = docid;
    g.data.stash('marked_record');
    var robj = g.network.simple_request('MODS_SLIM_RECORD_RETRIEVE.authoritative',[docid]);
    if (typeof robj.ilsevent == 'undefined') {
        g.data.marked_record_mvr = robj;
    } else {
        g.data.marked_record_mvr = null;
        g.error.standard_unexpected_error_alert('in mark_for_overlay',robj);
    }
    g.data.stash('marked_record_mvr');
    if (g.data.marked_record_mvr) {
        alert(document.getElementById('offlineStrings').getFormattedString('cat.opac.record_marked_for_overlay.tcn.alert',[ g.data.marked_record_mvr.tcn() ]));
        xulG.set_statusbar(
            1,
            $("offlineStrings").getFormattedString('staff.cat.z3950.marked_record_for_overlay_indicator.tcn.label',[g.data.marked_record_mvr.tcn()]),
            $("offlineStrings").getFormattedString('staff.cat.z3950.marked_record_for_overlay_indicator.record_id.label',[g.data.marked_record]),
            gen_statusbar_click_handler('marked_record')
        );
    } else {
        alert(document.getElementById('offlineStrings').getFormattedString('cat.opac.record_marked_for_overlay.record_id.alert',[ g.data.marked_record  ]));
        xulG.set_statusbar(
            1,
            $("offlineStrings").getFormattedString('staff.cat.z3950.marked_record_for_overlay_indicator.record_id.label',[g.data.marked_record]),
            '',
            gen_statusbar_click_handler('marked_record')
        );
    }
}

function mark_for_hold_transfer() {
    g.data.marked_record_for_hold_transfer = docid;
    g.data.stash('marked_record_for_hold_transfer');
    var robj = g.network.simple_request('MODS_SLIM_RECORD_RETRIEVE.authoritative',[docid]);
    if (typeof robj.ilsevent == 'undefined') {
        g.data.marked_record_for_hold_transfer_mvr = robj;
    } else {
        g.data.marked_record_for_hold_transfer_mvr = null;
        g.error.standard_unexpected_error_alert('in mark_for_hold_transfer',robj);
    }
    g.data.stash('marked_record_for_hold_transfer_mvr');
    if (g.data.marked_record_mvr) {
        var m = $("offlineStrings").getFormattedString('staff.cat.opac.marked_record_for_hold_transfer_indicator.tcn.label',[g.data.marked_record_for_hold_transfer_mvr.tcn()]);
        alert(m);
        xulG.set_statusbar(
            3,
            m,
            '',
            gen_statusbar_click_handler('marked_record_for_hold_transfer')
        );
    } else {
        var m = $("offlineStrings").getFormattedString('staff.cat.opac.marked_record_for_hold_transfer_indicator.record_id.label',[g.data.marked_record_for_hold_transfer]);
        alert(m);
        xulG.set_statusbar(
            3,
            m,
            '',
            gen_statusbar_click_handler('marked_record_for_hold_transfer')
        );
    }
}

function transfer_title_holds() {
    g.data.stash_retrieve();
    var target = g.data.marked_record_for_hold_transfer;
    if (!target) {
        var m = $("offlineStrings").getString('staff.cat.opac.title_for_hold_transfer.destination_needed.label');
        alert(m);
        return;
    }
    var robj = g.network.simple_request('TRANSFER_TITLE_HOLDS',[ ses(), target, [ docid ] ]);
    if (robj == 1) {
        var m = $("offlineStrings").getString('staff.cat.opac.title_for_hold_transfer.success.label');
        alert(m);
    } else {
        var m = $("offlineStrings").getString('staff.cat.opac.title_for_hold_transfer.failure.label');
        alert(m);
    }
    hold_browser_reset = true;
    if (g.view == 'hold_browser') { set_hold_browser(); };
}

function delete_record() {
    if (g.error.yns_alert(
        document.getElementById('offlineStrings').getFormattedString('cat.opac.delete_record.confirm', [docid]),
        document.getElementById('offlineStrings').getString('cat.opac.delete_record'),
        document.getElementById('offlineStrings').getString('cat.opac.delete'),
        document.getElementById('offlineStrings').getString('cat.opac.cancel'),
        null,
        document.getElementById('offlineStrings').getString('cat.opac.record_deleted.confirm')) == 0) {
        var robj = g.network.simple_request('FM_BRE_DELETE',[ses(),docid]);
        if (typeof robj.ilsevent != 'undefined') {
            alert(document.getElementById('offlineStrings').getFormattedString('cat.opac.record_deleted.error',  [docid, robj.textcode, robj.desc]) + '\n');
        } else {
            alert(document.getElementById('offlineStrings').getString('cat.opac.record_deleted'));
            refresh_display(docid);
        }
    }
}

function undelete_record() {
    if (g.error.yns_alert(
        document.getElementById('offlineStrings').getFormattedString('cat.opac.undelete_record.confirm', [docid]),
        document.getElementById('offlineStrings').getString('cat.opac.undelete_record'),
        document.getElementById('offlineStrings').getString('cat.opac.undelete'),
        document.getElementById('offlineStrings').getString('cat.opac.cancel'),
        null,
        document.getElementById('offlineStrings').getString('cat.opac.record_undeleted.confirm')) == 0) {

        var robj = g.network.simple_request('FM_BRE_UNDELETE',[ses(),docid]);
        if (typeof robj.ilsevent != 'undefined') {
            alert(document.getElementById('offlineStrings').getFormattedString('cat.opac.record_undeleted.error',  [docid, robj.textcode, robj.desc]) + '\n');
        } else {
            alert(document.getElementById('offlineStrings').getString('cat.opac.record_undeleted'));
            refresh_display(docid);
        }
    }
}

function refresh_display(id) {
    try { 
        marc_view_reset = true;
        marc_edit_reset = true;
        copy_browser_reset = true;
        hold_browser_reset = true;
        manage_parts_reset = true;
        manage_multi_home_reset = true;
        serctrl_view_reset = true;
        while(top_pane.node.lastChild) top_pane.node.removeChild( top_pane.node.lastChild );
        var children = bottom_pane.node.childNodes;
        for (var i = 0; i < children.length; i++) {
            if (children[i] != browser_frame) bottom_pane.node.removeChild(children[i]);
        }

        set_brief_view();
        $('nav').setAttribute('hidden','false');
        var settings = g.network.simple_request(
            'FM_AUS_RETRIEVE',
            [ ses(), g.data.list.au[0].id() ]
        );
        var view = settings['staff_client.catalog.record_view.default'];
        if (g.view_override) {
            view = g.view_override;
            g.view_override = null;
        }
        switch(view) {
            case 'marc_view' : set_marc_view(); break;
            case 'marc_edit' : set_marc_edit(); break;
            case 'copy_browser' : set_copy_browser(); break;
            case 'hold_browser' : set_hold_browser(); break;
            case 'serctrl_view' : set_serctrl_view(); break;
            case 'opac' :
            default: set_opac(); break;
        }
        opac_wrapper_set_help_context(); 
    } catch(E) {
        g.error.standard_unexpected_error_alert('in refresh_display',E);
    }
}

function set_default() {
    var robj = g.network.simple_request(
        'FM_AUS_UPDATE',
        [ ses(), g.data.list.au[0].id(), { 'staff_client.catalog.record_view.default' : g.view } ]
    )
    if (typeof robj.ilsevent != 'undefined') {
        if (robj.ilsevent != 0) g.error.standard_unexpected_error_alert(document.getElementById('offlineStrings').getString('cat.preference.error'), robj);
    }
}

function add_volumes() {
    try {
        var edit = 0;
        try {
            edit = g.network.request(
                api.PERM_MULTI_ORG_CHECK.app,
                api.PERM_MULTI_ORG_CHECK.method,
                [ 
                    ses(), 
                    ses('staff_id'), 
                    [ ses('ws_ou') ],
                    [ 'CREATE_VOLUME', 'CREATE_COPY' ]
                ]
            ).length == 0 ? 1 : 0;
        } catch(E) {
            g.error.sdump('D_ERROR','batch permission check: ' + E);
        }

        if (edit==0) {
            alert(document.getElementById('offlineStrings').getString('staff.circ.copy_status.add_volumes.perm_failure'));
            return; // no read-only view for this interface
        }

        // Check if the source is allowed to have copies.
        try {
            var bibObj = g.network.request(
                api.FM_BRE_RETRIEVE_VIA_ID.app,
                api.FM_BRE_RETRIEVE_VIA_ID.method,
				[ ses(), [docid] ]
            );

			bibObj = bibObj[0];

            var cbsObj = g.network.request(
                api.FM_CBS_RETRIEVE_VIA_PCRUD.app,
                api.FM_CBS_RETRIEVE_VIA_PCRUD.method,
                [ ses(), bibObj.source() ]
            );

            if (cbsObj && cbsObj.can_have_copies() != get_db_true()) {
                alert(document.getElementById('offlineStrings').getFormattedString('staff.cat.bib_source.can_have_copies.false', [cbsObj.source()]));
                return;
            }
        } catch(E) {
            g.error.sdump('D_ERROR','can have copies check: ' + E);
            alert('Error in chrome/content/cat/opac.js, add_volumes(): ' + E);
            return;
        }

        var title = document.getElementById('offlineStrings').getFormattedString('staff.circ.copy_status.add_volumes.title', [docid]);

        var url;
        var unified_interface = String( g.data.hash.aous['ui.unified_volume_copy_editor'] ) == 'true';
        if (unified_interface) {
            var horizontal_interface = String( g.data.hash.aous['ui.cat.volume_copy_editor.horizontal'] ) == 'true';
            url = window.xulG.url_prefix( horizontal_interface ? 'XUL_VOLUME_COPY_CREATOR_HORIZONTAL' : 'XUL_VOLUME_COPY_CREATOR' );
        } else {
            url = window.xulG.url_prefix( 'XUL_VOLUME_COPY_CREATOR_ORIGINAL' );
        }

        var w = xulG.new_tab(
            url,
            { 'tab_name' : title },
            { 'doc_id' : docid, 'ou_ids' : [ ses('ws_ou') ], 'reload_opac' : xulG.reload_opac }
        );
    } catch(E) {
        alert('Error in chrome/content/cat/opac.js, add_volumes(): ' + E);
    }
}

function manage_parts() {
    try {
        g.view = 'manage_parts';
        var loc = urls.XUL_BROWSER + "?url=" + window.escape(
            window.xulG.url_prefix('CONIFY_MANAGE_PARTS?r=') + docid
        );
        if (manage_parts_reset) {
            bottom_pane.reset_iframe( loc,{},xulG);
            manage_parts_reset =false;
        } else {
            bottom_pane.set_iframe( loc,{},xulG);
        }
        opac_wrapper_set_help_context();
        bottom_pane.get_contentWindow().addEventListener('load',opac_wrapper_set_help_context,false);
    } catch(E) {
        alert('Error in chrome/content/cat/opac.js, manage_parts(): ' + E);
    }
}

function manage_multi_home_items() {
    try {
        g.view = 'manage_multi_home';
        var loc = window.xulG.url_prefix('MANAGE_MULTI_HOME_ITEMS');
        if (manage_multi_home_reset) {
            bottom_pane.reset_iframe( loc,{},{'docid':docid,'no_bib_summary':true,'url_prefix':xulG.url_prefix,'new_tab':xulG.new_tab});
            manage_multi_home_reset =false;
        } else {
            bottom_pane.set_iframe( loc,{},{'docid':docid,'no_bib_summary':true,'url_prefix':xulG.url_prefix,'new_tab':xulG.new_tab});
        }
        opac_wrapper_set_help_context();
        bottom_pane.get_contentWindow().addEventListener('load',opac_wrapper_set_help_context,false);
    } catch(E) {
        alert('Error in chrome/content/cat/opac.js, manage_multi_home_items(): ' + E);
    }
}

function mark_for_multi_home() {
    g.data.marked_multi_home_record = docid;
    g.data.stash('marked_multi_home_record');
    var robj = g.network.simple_request('MODS_SLIM_RECORD_RETRIEVE.authoritative',[docid]);
    if (typeof robj.ilsevent == 'undefined') {
        g.data.marked_multi_home_record_mvr = robj;
    } else {
        g.data.marked_multi_home_record_mvr = null;
        g.error.standard_unexpected_error_alert('in mark_for_multi_home',robj);
    }
    g.data.stash('marked_multi_home_record_mvr');

    if (g.data.marked_multi_home_record_mvr) {
        alert(document.getElementById('offlineStrings').getFormattedString('cat.opac.record_marked_for_multi_home.tcn.alert',[ g.data.marked_multi_home_record_mvr.tcn() ]));
        xulG.set_statusbar(
            2,
            $("offlineStrings").getFormattedString('staff.cat.copy_browser.marked_record_for_multi_home_indicator.tcn.label',[g.data.marked_multi_home_record_mvr.tcn()]),
            $("offlineStrings").getFormattedString('staff.cat.copy_browser.marked_record_for_multi_home_indicator.record_id.label',[g.data.marked_multi_home_record]),
            gen_statusbar_click_handler('marked_multi_home_record')
        );
    } else {
        alert(document.getElementById('offlineStrings').getFormattedString('cat.opac.record_marked_for_multi_home.record_id.alert',[ g.data.marked_multi_home_record ]));
        xulG.set_statusbar(
            2,
            $("offlineStrings").getFormattedString('staff.cat.copy_browser.marked_record_for_multi_home_indicator.record_id.label',[g.data.marked_multi_home_record]),
            '',
            gen_statusbar_click_handler('marked_multi_home_record')
        );
    }
}

function gen_statusbar_click_handler(data_key) {
    return function (ev) {

        if (! g.data[data_key]) {
            return;
        }

        if (ev.button == 0 /* left click, spawn opac */) {
            var opac_url = xulG.url_prefix( 'opac_rdetail' ) + g.data[data_key];
            var content_params = {
                'session' : ses(),
                'authtime' : ses('authtime'),
                'opac_url' : opac_url,
            };
            xulG.new_tab(
                xulG.url_prefix('XUL_OPAC_WRAPPER'),
                {'tab_name':'Retrieving title...'},
                content_params
            );
        }

        if (ev.button == 2 /* right click, remove mark */) {
            if ( window.confirm( document.getElementById('offlineStrings').getString('cat.opac.clear_statusbar') ) ) {
                g.data[data_key] = null;
                g.data.stash(data_key);
                ev.target.setAttribute('label','');
                if (ev.target.hasAttribute('tooltiptext')) {
                    ev.target.removeAttribute('tooltiptext');
                }
            }
        }
    }
}


