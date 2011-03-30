var docid;

function my_init() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        if (typeof JSAN == 'undefined') { throw( document.getElementById("commonStrings").getString('common.jsan.missing') ); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for cat_bib_brief.xul');

        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});

        docid = xul_param('docid');

        var key = location.pathname + location.search + location.hash;
        if (!docid && typeof g.data.modal_xulG_stack != 'undefined' && typeof g.data.modal_xulG_stack[key] != 'undefined') {
            var xulG = g.data.modal_xulG_stack[key][ g.data.modal_xulG_stack[key].length - 1 ];
            if (typeof xulG == 'object') {
                docid = xulG.docid;
            }
        }

        JSAN.use('util.network'); g.network = new util.network();
        JSAN.use('util.date');

        document.getElementById('caption').setAttribute('tooltiptext',document.getElementById('catStrings').getFormattedString('staff.cat.bib_brief.record_id', [docid]));

        if (docid > -1) {

            g.data.last_record = docid; g.data.stash('last_record');

            g.network.simple_request(
                'MODS_SLIM_RECORD_RETRIEVE.authoritative',
                [ docid ],
                function (req) {
                    var mods = req.getResultObject();
                    
                    if (window.xulG && typeof window.xulG.set_tab_name == 'function') {
                        try {
                            window.xulG.set_tab_name(mods.tcn());
                        } catch(E) {
                            g.error.sdump('D_ERROR','bib_brief.xul, set_tab: ' + E);
                        }
                    }

                    g.network.simple_request(
                        'FM_BRE_RETRIEVE_VIA_ID.authoritative',
                        [ ses(), [ docid ] ],
                        function (req) {
                            try {
                                var meta = req.getResultObject();
                                if (typeof meta.ilsevent != 'undefined') throw(meta);
                                meta = meta[0];
                                var t = document.getElementById('caption').getAttribute('label');
                                if (get_bool( meta.deleted() )) { 
                                    t += ' ' + document.getElementById('catStrings').getString('staff.cat.bib_brief.deleted') + ' '; 
                                    document.getElementById('caption').setAttribute('style','background: red; color: white;');
                                }
                                if ( ! get_bool( meta.active() ) ) { 
                                    t += ' ' + document.getElementById('catStrings').getString('staff.cat.bib_brief.inactive') + ' '; 
                                    document.getElementById('caption').setAttribute('style','background: red; color: white;');
                                }
                                document.getElementById('caption').setAttribute('label',t);

                                bib_brief_overlay( { 'mvr' : mods, 'bre' : meta } );

                            } catch(E) {
                                g.error.standard_unexpected_error_alert('meta retrieve',E);
                            }
                        }
                    );
                }
            );

        } else {
            var t = document.getElementById('caption').getAttribute('label');
            t += ' ' + document.getElementById('catStrings').getString('staff.cat.bib_brief.noncat') + ' '; 
            document.getElementById('caption').setAttribute('style','background: red; color: white;');
            document.getElementById('caption').setAttribute('label',t);
        }

    } catch(E) {
        var err_msg = document.getElementById("commonStrings").getFormattedString('common.exception', ['cat/bib_brief.xul', E]);
        try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
        alert(err_msg);
    }
}

function unhide_add_volumes_button() {
    if (xulG && typeof xulG == 'object' && typeof xulG['new_tab'] == 'function') {
        document.getElementById('add_volumes').hidden = false;
        document.getElementById('add_volumes_left_paren').hidden = false;
        document.getElementById('add_volumes_right_paren').hidden = false;
    }
}

function view_marc() {
    try {
        JSAN.use('util.window'); var win = new util.window();
        if (docid < 0) {
            alert(document.getElementById("catStrings").getString('staff.cat.bib_brief.noncat.alert'));
        } else {
            netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
            //win.open( urls.XUL_MARC_VIEW + '?noprint=1&docid=' + docid, 'marc_view', 'chrome,resizable,modal,width=400,height=400');
            win.open( urls.XUL_MARC_VIEW, 'marc_view', 'chrome,resizable,modal,width=400,height=400',{'noprint':1,'docid':docid});
        }
    } catch(E) {
        g.error.standard_unexpected_error_alert('spawning marc display',E);
    }
}

function spawn_patron(span) {
    try {
        if (typeof window.xulG == 'object' && typeof window.xulG.set_patron_tab == 'function') {
            window.xulG.set_patron_tab( {}, { 'id' : span.getAttribute('au_id') } );
        } else {
            copy_to_clipboard( span.textContent );
        }
    } catch(E) {
        g.error.standard_unexpected_error_alert('spawning patron display',E);
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

        var horizontal_interface = String( g.data.hash.aous['ui.cat.volume_copy_editor.horizontal'] ) == 'true';
        var url = window.xulG.url_prefix( horizontal_interface ? urls.XUL_VOLUME_COPY_CREATOR_HORIZONTAL : urls.XUL_VOLUME_COPY_CREATOR );
        var w = xulG.new_tab(
            url,
            { 'tab_name' : title },
            { 'doc_id' : docid, 'ou_ids' : [ ses('ws_ou') ] }
        );
    } catch(E) {
        alert('Error in server/cat/bib_brief.js, add_volumes(): ' + E);
    }
}
