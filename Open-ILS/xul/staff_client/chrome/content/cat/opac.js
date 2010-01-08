var docid; var marc_html; var top_pane; var bottom_pane; var opac_frame; var opac_url;

var marc_view_reset = true;
var marc_edit_reset = true;
var copy_browser_reset = true;
var hold_browser_reset = true;

function $(id) { return document.getElementById(id); }

function my_init() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        if (typeof JSAN == 'undefined') { throw(document.getElementById('offlineStrings').getString('common.jsan.missing')); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('..');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for cat/opac.xul');

        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
        XML_HTTP_SERVER = g.data.server_unadorned;

        JSAN.use('util.network'); g.network = new util.network();

        g.cgi = new CGI();
        try { authtime = g.cgi.param('authtime') || xulG.authtime; } catch(E) { g.error.sdump('D_ERROR',E); }
        try { docid = g.cgi.param('docid') || xulG.docid; } catch(E) { g.error.sdump('D_ERROR',E); }
        try { opac_url = g.cgi.param('opac_url') || xulG.opac_url; } catch(E) { g.error.sdump('D_ERROR',E); }

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

function set_brief_view() {
    var url = xulG.url_prefix( urls.XUL_BIB_BRIEF ) + '?docid=' + window.escape(docid); 
    dump('spawning ' + url + '\n');
    top_pane.set_iframe( 
        url,
        {}, 
        { 
            'set_tab_name' : function(n) { 
                if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
                    try { window.xulG.set_tab_name(document.getElementById('offlineStrings').getFormattedString("cat.bib_record", [n])); } catch(E) { alert(E); }
                } else {
                    dump('no set_tab_name\n');
                }
            }
        }  
    );
}

function set_marc_view() {
    g.view = 'marc_view';
    if (marc_view_reset) {
        bottom_pane.reset_iframe( xulG.url_prefix( urls.XUL_MARC_VIEW ) + '?docid=' + window.escape(docid),{},xulG);
        marc_view_reset = false;
    } else {
        bottom_pane.set_iframe( xulG.url_prefix( urls.XUL_MARC_VIEW ) + '?docid=' + window.escape(docid),{},xulG);
    }
}

function set_marc_edit() {
    g.view = 'marc_edit';
    var a =    xulG.url_prefix( urls.XUL_MARC_EDIT );
    var b =    {};
    var c =    {
            'record' : { 'url' : '/opac/extras/supercat/retrieve/marcxml/record/' + docid },
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

                            var acn_id = network.simple_request(
                                'FM_ACN_FIND_OR_CREATE',
                                [ ses(), cn_label, doc_id, ses('ws_ou') ]
                            );

                            if (typeof acn_id.ilsevent != 'undefined') {
                                error.standard_unexpected_error_alert('Error in chrome/content/cat/opac.js, cat.util.fast_item_add', acn_id);
                                return;
                            }

                            var copy_obj = new acp();
                            copy_obj.id( -1 );
                            copy_obj.isnew('1');
                            copy_obj.barcode( cp_barcode );
                            copy_obj.call_number( acn_id );
                            copy_obj.circ_lib( ses('ws_ou') );
                            /* FIXME -- use constants */
                            copy_obj.deposit(0);
                            copy_obj.price(0);
                            copy_obj.deposit_amount(0);
                            copy_obj.fine_level(2);
                            copy_obj.loan_duration(2);
                            copy_obj.location(1);
                            copy_obj.status(0);
                            copy_obj.circulate(get_db_true());
                            copy_obj.holdable(get_db_true());
                            copy_obj.opac_visible(get_db_true());
                            copy_obj.ref(get_db_false());

                            JSAN.use('util.window'); var win = new util.window();
                            return cat.util.spawn_copy_editor( { 'handle_update' : 1, 'edit' : 1, 'docid' : doc_id, 'copies' : [ copy_obj ] });

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
            }
        };
    if (marc_edit_reset) {
        bottom_pane.reset_iframe( a,b,c );
        marc_edit_reset = false;
    } else {
        bottom_pane.set_iframe( a,b,c );
    }
}

function set_copy_browser() {
    g.view = 'copy_browser';
    if (copy_browser_reset) {
        bottom_pane.reset_iframe( xulG.url_prefix( urls.XUL_COPY_VOLUME_BROWSE ) + '?docid=' + window.escape(docid),{},xulG);
        copy_browser_reset =false;
    } else {
        bottom_pane.set_iframe( xulG.url_prefix( urls.XUL_COPY_VOLUME_BROWSE ) + '?docid=' + window.escape(docid),{},xulG);
    }
}

function set_hold_browser() {
    g.view = 'hold_browser';
    if (hold_browser_reset) {
        bottom_pane.reset_iframe( xulG.url_prefix( urls.XUL_HOLDS_BROWSER ) + '?docid=' + window.escape(docid),{},xulG);
        hold_browser_reset = false;
    } else {
        bottom_pane.set_iframe( xulG.url_prefix( urls.XUL_HOLDS_BROWSER ) + '?docid=' + window.escape(docid),{},xulG);
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
                        netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');
                        return window.open(a,b,c);
                    } catch(E) {
                        g.error.standard_unexpected_error_alert('window_open',E);
                    }
                }
            },
            'on_url_load' : function(f) {
                netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
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
                
                g.f_record_start = null; g.f_record_prev = null; g.f_record_next = null; g.f_record_end = null;
                $('record_start').disabled = true; $('record_next').disabled = true;
                $('record_prev').disabled = true; $('record_end').disabled = true;
                $('record_pos').setAttribute('value','');

                win.attachEvt("rdetail", "nextPrevDrawn",
                    function(rIndex,rCount){
                        $('record_pos').setAttribute('value', document.getElementById('offlineStrings').getFormattedString('cat.record.counter', [(1+rIndex), rCount ? rCount : 1]));
                        if (win.rdetailNext) {
                            g.f_record_next = function() { 
                                g.view_override = g.view; 
                                win.rdetailNext(); 
                            }
                            $('record_next').disabled = false;
                        }
                        if (win.rdetailPrev) {
                            g.f_record_prev = function() { 
                                g.view_override = g.view; 
                                win.rdetailPrev(); 
                            }
                            $('record_prev').disabled = false;
                        }
                        if (win.rdetailStart) {
                            g.f_record_start = function() { 
                                g.view_override = g.view; 
                                win.rdetailStart(); 
                            }
                            $('record_start').disabled = false;
                        }
                        if (win.rdetailEnd) {
                            g.f_record_end = function() { 
                                g.view_override = g.view; 
                                win.rdetailEnd(); 
                            }
                            $('record_end').disabled = false;
                        }
                    }
                );
            },
            'url_prefix' : xulG.url_prefix,
        };
        if (opac_url) { content_params.url = opac_url; } else { content_params.url = xulG.url_prefix( urls.browser ); }
        browser_frame = bottom_pane.set_iframe( xulG.url_prefix(urls.XUL_BROWSER) + '?name=Catalog', {}, content_params);
        /* // Remember to use the REMOTE_BROWSER if we ever try to move this to remote xul again
        browser_frame = bottom_pane.set_iframe( xulG.url_prefix(urls.XUL_REMOTE_BROWSER) + '?name=Catalog', {}, content_params);
        */
    } catch(E) {
        g.error.sdump('D_ERROR','set_opac: ' + E);
    }
}

function bib_in_new_tab() {
    try {
        var url = browser_frame.contentWindow.g.browser.controller.view.browser_browser.contentWindow.wrappedJSObject.location.href;
        var content_params = { 'session' : ses(), 'authtime' : ses('authtime'), 'opac_url' : url };
        xulG.new_tab(xulG.url_prefix(urls.XUL_OPAC_WRAPPER), {}, content_params);
    } catch(E) {
        g.error.sdump('D_ERROR',E);
    }
}

function remove_me() {
    var url = xulG.url_prefix( urls.XUL_BIB_BRIEF ) + '?docid=' + window.escape(docid);
    dump('removing ' + url + '\n');
    try { top_pane.remove_iframe( url ); } catch(E) { dump(E + '\n'); }
    $('nav').setAttribute('hidden','true');
}

function add_to_bucket() {
    JSAN.use('util.window'); var win = new util.window();
    win.open(
        xulG.url_prefix(urls.XUL_RECORD_BUCKETS_QUICK),
        'sel_bucket_win' + win.window_name_increment(),
        'chrome,resizable,modal,center',
        {
            record_ids: [ docid ]
        }
    );
}

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
    } else {
        alert(document.getElementById('offlineStrings').getFormattedString('cat.opac.record_marked_for_overlay.record_id.alert',[ g.data.marked_record  ]));
    }
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
            case 'opac' :
            default: set_opac(); break;
        }
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

        var title = document.getElementById('offlineStrings').getFormattedString('staff.circ.copy_status.add_volumes.title', [docid]);

        JSAN.use('util.window'); var win = new util.window();
        var w = win.open(
            window.xulG.url_prefix(urls.XUL_VOLUME_COPY_CREATOR),
            title,
            'chrome,resizable',
            { 'doc_id' : docid, 'ou_ids' : [ ses('ws_ou') ] }
        );
    } catch(E) {
        alert('Error in chrome/content/cat/opac.js, add_volumes(): ' + E);
    }
}
