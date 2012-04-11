var docid;

function bib_brief_init(mode) {
    try {

        ui_init(); // JSAN, etc.

        if (! mode) { mode = 'horizontal'; }

        JSAN.use('OpenILS.data');
        g.data = new OpenILS.data();
        g.data.stash_retrieve();

        docid = xul_param('docid');

        JSAN.use('util.network'); g.network = new util.network();
        JSAN.use('util.date');

        document.getElementById('caption').setAttribute(
            'tooltiptext',
            document.getElementById('catStrings').getFormattedString(
                'staff.cat.bib_brief.record_id', [docid]
            )
        );

        if (docid > -1) {

            g.data.last_record = docid; g.data.stash('last_record');

            g.network.simple_request(
                'MODS_SLIM_RECORD_RETRIEVE.authoritative',
                [ docid ],
                function (req) {
                    try {
                        g.mods = req.getResultObject();
                        set_tab_name();
                        g.network.simple_request(
                            'FM_BRE_RETRIEVE_VIA_ID.authoritative',
                            [ ses(), [ docid ] ],
                            function (req2) {
                                try {
                                    g.meta = req2.getResultObject()[0];
                                    set_caption();
                                    dynamic_grid_replacement(mode);
                                    bib_brief_overlay({
                                        'mvr' : g.mods,
                                        'bre' : g.meta
                                    });
                                } catch(E) {
                                    alert('Error in bib_brief.js, '
                                        + 'req handler 2: ' + E + '\n');
                                }
                            }
                        );
                    } catch(E) {
                        alert('Error in bib_brief.js, req handler 1: '
                            + E + '\n');
                    }
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

function set_tab_name() {
    try {
        window.xulG.set_tab_name(g.mods.tcn());
    } catch(E) {
        dump('Error in bib_brief.js, set_tab_name(): ' + E + '\n');
    }
}

function set_caption() {
    try {
        var t = document.getElementById('caption').getAttribute('label');
        if (get_bool( g.meta.deleted() )) {
            t += ' ' + document.getElementById('catStrings').getString('staff.cat.bib_brief.deleted') + ' ';
            document.getElementById('caption').setAttribute('style','background: red; color: white;');
        }
        if ( ! get_bool( g.meta.active() ) ) {
            t += ' ' + document.getElementById('catStrings').getString('staff.cat.bib_brief.inactive') + ' ';
            document.getElementById('caption').setAttribute('style','background: red; color: white;');
        }
        document.getElementById('caption').setAttribute('label',t);

    } catch(E) {
        dump('Error in bib_brief.js, set_caption(): ' + E + '\n');
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

        try {
            JSAN.use('cat.util');
            var cbsObj = cat.util.get_cbs_for_bre_id(docid);
            if (cbsObj && cbsObj.can_have_copies() != get_db_true()) {
                alert(document.getElementById('offlineStrings').getFormattedString('staff.cat.bib_source.can_have_copies.false', [cbsObj.source()]));
                return;
            }
        } catch(E) {
            g.error.sdump('D_ERROR','can have copies check: ' + E);
            alert('Error in server/cat/bib_brief.js, add_volumes(): ' + E);
            return;
        }

        var title = document.getElementById('offlineStrings').getFormattedString('staff.circ.copy_status.add_volumes.title', [docid]);

        var url;
        var unified_interface = String( g.data.hash.aous['ui.unified_volume_copy_editor'] ) == 'true';
        if (unified_interface) {
            var horizontal_interface = String( g.data.hash.aous['ui.cat.volume_copy_editor.horizontal'] ) == 'true';
            url = window.xulG.url_prefix( horizontal_interface ? 'XUL_VOLUME_COPY_CREATOR_HORIZONTAL' : 'XUL_VOLUME_COPY_CREATOR' );
        } else {
            url = window.xulG.url_prefix('XUL_VOLUME_COPY_CREATOR_ORIGINAL');
        }
        var w = xulG.new_tab(
            url,
            { 'tab_name' : title },
            { 'doc_id' : docid, 'ou_ids' : [ ses('ws_ou') ], 'reload_opac' : xulG.reload_opac }
        );
    } catch(E) {
        alert('Error in server/cat/bib_brief.js, add_volumes(): ' + E);
    }
}

function ui_init() {
    if (typeof JSAN == 'undefined') {
        throw(
            document.getElementById("commonStrings").getString(
                'common.jsan.missing'
            )
        );
    }
    JSAN.errorLevel = "die"; // none, warn, or die
    JSAN.addRepository('/xul/server/');
    JSAN.use('util.error'); g.error = new util.error();
    g.error.sdump('D_TRACE','my_init() for cat_bib_brief.xul');
}

function dynamic_grid_replacement(mode) {
    var prefs = Components.classes[
        '@mozilla.org/preferences-service;1'
    ].getService(
        Components.interfaces['nsIPrefBranch']
    );
    if (! prefs.prefHasUserValue(
            'oils.bib_brief.'+mode+'.dynamic_grid_replacement.data'
        )
    ) {
        return false;
    }

    var gridData = JSON2js(
        prefs.getCharPref(
            'oils.bib_brief.'+mode+'.dynamic_grid_replacement.data'
        )
    );

    var grid = document.getElementById('bib_brief_grid');
    if (!grid) { return false; }

    JSAN.use('util.widgets');

    util.widgets.remove_children(grid);

    var columns = document.createElement('columns');
    grid.appendChild(columns);

    var maxColumns = 0;
    for (var i = 0; i < gridData.length; i++) {
        if (gridData[i].length > maxColumns) {
            maxColumns = gridData[i].length;
        }
    }

    for (var i = 0; i < maxColumns; i++) {
        var columnA = document.createElement('column');
        columns.appendChild(columnA);
        var columnB = document.createElement('column');
        columns.appendChild(columnB);
    }

    // Flex the column where the title usually goes
    columns.firstChild.nextSibling.setAttribute('flex','1');

    var rows = document.createElement('rows');
    grid.appendChild(rows);

/*
    <row id="bib_brief_grid_row1" position="1">
        <label control="title" class="emphasis"
            value="&staff.cat.bib_brief.title.label;"
            accesskey="&staff.cat.bib_brief.title.accesskey;"/>
        <textbox id="title"
            name="title" readonly="true" context="clipboard"
            class="plain" onfocus="this.select()"/>
    </row>
*/

    var catStrings = document.getElementById('catStrings');

    for (var i = 0; i < gridData.length; i++) {
        var row = document.createElement('row');
        row.setAttribute('id','bib_brief_grid_row'+i);
        rows.appendChild(row);

        for (var j = 0; j < gridData[i].length; j++) {
            var name = gridData[i][j];

            var label = document.createElement('label');
            label.setAttribute('control',name);
            label.setAttribute('class','emphasis');
            label.setAttribute('value',
                catStrings.testString('staff.cat.bib_brief.'+name+'.label')
                ? catStrings.getString('staff.cat.bib_brief.'+name+'.label')
                : name
            );
            label.setAttribute('accesskey',
                catStrings.testString('staff.cat.bib_brief.'+name+'.accesskey')
                ? catStrings.getString('staff.cat.bib_brief.'+name+'.accesskey')
                : name
            );
            row.appendChild(label);

            var textbox = document.createElement('textbox');
            textbox.setAttribute('id',name);
            textbox.setAttribute('name',name);
            textbox.setAttribute('readonly','true');
            textbox.setAttribute('context','clipboard');
            textbox.setAttribute('class','plain');
            textbox.setAttribute('onfocus','this.select()');
            row.appendChild(textbox);
        }
    }
    return true;
}

