function $(id) { return document.getElementById(id); }

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');

        dojo.require('openils.PermaCrud');
        JSAN.use('util.error'); g.error = new util.error();
        JSAN.use('util.network'); g.network = new util.network();
        JSAN.use('util.date'); JSAN.use('util.money'); JSAN.use('patron.util');
        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});

        g.error.sdump('D_TRACE','my_init() for hold_notices.xul');

        g.pcrud = new openils.PermaCrud({authtoken :ses()});

        init_list();

        if (xulG.ahr_id) fetch_and_render_all();

        if (xul_param('when_done')) {
            xul_param('when_done')();
        }

    } catch(E) {
        try { g.error.standard_unexpected_error_alert('/xul/server/patron/hold_notices.xul',E); } catch(E) { alert('FIXME: ' + js2JSON(E)); }
    }
}

function fetch_and_render_all(do_not_refresh_parent_interface) {
    try {
        if (!xulG.ahr_id) { return; }

        fetch_hold();

        if (xulG.patron_rendered_elsewhere) {
            // Hide patron line
        } else {
            render_patron();
        }

        a_list_of_one();

        var x = document.getElementById('bib_brief_box'); while (x.firstChild) x.removeChild(x.lastChild);
        if (xulG.bib_rendered_elsewhere) {
            // No bib summary     
            x.hidden = true;
        } else {
            x.hidden = false;
            var bib_brief = document.createElement('iframe'); x.appendChild(bib_brief);
            bib_brief.setAttribute('flex',1);
            bib_brief.setAttribute('src',urls.XUL_BIB_BRIEF); 
            get_contentWindow(bib_brief).xulG = { 'docid' : g.blob.mvr.doc_id() };
        }

        retrieve_notes(); render_notes();

        retrieve_notifications(); render_notifications();

        if (!do_not_refresh_parent_interface) {
            if (typeof xulG.clear_and_retrieve == 'function') {
                xulG.clear_and_retrieve();
            }
        }

    } catch(E) {
        alert('Error in hold_details.js, fetch_and_render_all(): ' + E);
    }
}

function fetch_hold(id) {
    try {
        g.ahr_id = xulG.ahr_id;
        if (xulG.blob) {
            g.blob = xulG.blob;
            delete xulG.blob; // one-time deal for speed
        } else {
            g.blob = g.network.simple_request('FM_AHR_BLOB_RETRIEVE',[ ses(), g.ahr_id ]);
            if (typeof g.ahr.ilsevent != 'undefined') { throw(g.ahr); }
        }
        g.ahr = g.blob.hold;
        g.ahr.status( g.blob.status );
    } catch(E) {
        alert('Error in hold_details.js, fetch_hold(): ' + E);
    }
}

function render_patron() {
    if (g.ahr.usr()) {
        JSAN.use('patron.util'); 
        var au_obj = patron.util.retrieve_fleshed_au_via_id( ses(), g.ahr.usr() );
        
        $('patron_name').setAttribute('value', 
            patron.util.format_name( au_obj ) + ' : ' + au_obj.card().barcode() 
        );
    }
}

function init_list() {
    JSAN.use('circ.util');
    var columns = circ.util.hold_columns( 
        { 
            'status' : { 'hidden' : true },
            'request_time' : { 'hidden' : false },
            'pickup_lib_shortname' : { 'hidden' : false },
            'current_copy' : { 'hidden' : false },
            'phone_notify' : { 'hidden' : false },
            'email_notify' : { 'hidden' : false },
            'hold_type' : { 'hidden' : false },
        } 
    );
    JSAN.use('util.list'); g.list = new util.list('holds_list');
    g.list.init(
        {
            'columns' : columns,
            'retrieve_row' : function(params) {
                var row = params.row;
                if (typeof params.on_retrieve == 'function') {
                    params.on_retrieve(row);
                }
                return row;
            },
        }
    );
    dump('hold details init_list done\n');
}

function a_list_of_one() {
    try {
        g.list.clear();
        g.list.append(
            {
                'row' : {
                    'my' : {
                        'ahr' : g.ahr,
                        'status' : g.blob.status,
                        'acp' : g.blob.copy,
                        'acn' : g.blob.volume,
                        'mvr' : g.blob.mvr,
                        'patron_family_name' : g.blob.patron_last,
                        'patron_first_given_name' : g.blob.patron_first,
                        'patron_barcode' : g.blob.patron_barcode,
                        'patron_alias' : g.blob.patron_alias,
                        'total_holds' : g.blob.total_holds,
                        'queue_position' : g.blob.queue_position,
                        'potential_copies' : g.blob.potential_copies,
                        'estimated_wait' : g.blob.estimated_wait,
                        'ahrn_count' : g.blob.hold.notes().length,
                        'blob' : g.blob
                    }
                },
                'no_auto_select' : true,
            }
        );
    } catch(E) {
        alert('Error in hold_details.js, a_list_of_one(): ' + E);
    }
}

function retrieve_notifications() {
    g.notifications = g.network.simple_request('FM_AHN_RETRIEVE_VIA_AHR.authoritative',[ ses(), g.ahr_id ]).reverse();
}

function retrieve_notes() {
    g.notes = g.pcrud.search('ahrn',{'hold':g.ahr_id});
    g.notes = g.notes.reverse();
}

function apply(node,field,value) {
    util.widgets.apply(
        node,'name',field,
        function(n) {
            switch(n.nodeName) {
                case 'description' : n.appendChild( document.createTextNode( value ) ); break;
                case 'label' : n.value = value; break;
                default : n.value = value; break;
            }
        }
    );
}

function render_notifications() {
    JSAN.use('util.widgets'); util.widgets.remove_children('notifications_panel');
    var np = $('notifications_panel');

    for (var i = 0; i < g.notifications.length; i++) {

        /* template */
        var node = $('notification_template').cloneNode(true); np.appendChild(node); node.hidden = false;
        util.widgets.apply(node,'name','notify_time',
            function(n){
                n.setAttribute(
                    "tooltiptext", 
                    $("patronStrings").getFormattedString('staff.patron.hold_notices.tooltiptext',[g.notifications[i].id(), g.notifications[i].hold(), g.notifications[i].notify_staff()])
                );
            }
        );
        apply(node,'method',g.notifications[i].method() ? g.notifications[i].method() : '');
        apply(node,'note',g.notifications[i].note() ? g.notifications[i].note() : '');
        apply(node,'notify_time',g.notifications[i].notify_time() ? util.date.formatted_date( g.notifications[i].notify_time(), '%{localized}' ) : '');
    }

}

function render_notes() {
    JSAN.use('util.widgets'); util.widgets.remove_children('notes_panel');
    var np = $('notes_panel');

    for (var i = 0; i < g.notes.length; i++) {

        /* template */
        var node = $('note_template').cloneNode(true); np.appendChild(node); node.hidden = false;
        util.widgets.apply(node,'name','create_date',
            function(n){
                n.setAttribute(
                    "tooltiptext", 
                    $("patronStrings").getFormattedString('staff.patron.hold_notes.tooltiptext',[g.notes[i].id(), g.notes[i].hold(), g.notes[i].staff()])
                );
            }
        );
        apply(node,'title',g.notes[i].title() ? g.notes[i].title() : '');
        apply(node,'note',g.notes[i].body() ? g.notes[i].body() : '');
        apply(node,'pub',get_bool( g.notes[i].pub() ) ? $("patronStrings").getString('staff.patron.hold_notes.public') : $("patronStrings").getString('staff.patron.hold_notes.private') )
        apply(node,'slip',get_bool( g.notes[i].slip() ) ? $("patronStrings").getString('staff.patron.hold_notes.print_on_slip') : $("patronStrings").getString('staff.patron.hold_notes.no_print_on_slip') )
        apply(node,'staff',get_bool( g.notes[i].staff() ) ? $("patronStrings").getString('staff.patron.hold_notes.by_staff') : $("patronStrings").getString('staff.patron.hold_notes.by_patron') )
    }

}


function new_notification() {
    try {
        var xml = '<groupbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1">';
        xml += '<caption label="' + $("patronStrings").getString('staff.patron.hold_notices.new_notification_record') + '"/><grid flex="1"><columns><column/><column flex="1"/></columns><rows>';
        xml += '<row><label value="' + $("patronStrings").getString('staff.patron.hold_notices.method') + '"/><textbox id="method" name="fancy_data" context="clipboard"/></row>';
        xml += '<row><label value="' + $("patronStrings").getString('staff.patron.hold_notices.note') + '"/><textbox multiline="true" id="note" name="fancy_data" context="clipboard"/></row>';
        xml += '<row><spacer/><hbox><button label="' + $("patronStrings").getString('staff.patron.hold_notices.cancel') + '" name="fancy_cancel" ';
        xml += 'accesskey="' + $("patronStrings").getString('staff.patron.hold_notices.cancel_accesskey') + '"/>';
        xml += '<button label="' + $("patronStrings").getString('staff.patron.hold_notices.add_notif_record') + '" ';
        xml += 'accesskey="' + $("patronStrings").getString('staff.patron.hold_notices.add_notif_record_accesskey') + '" name="fancy_submit"/></hbox></row></rows></grid></groupbox>';
        JSAN.use('util.window'); var win = new util.window();
        var fancy_prompt_data = win.open(
            urls.XUL_FANCY_PROMPT,
            'fancy_prompt', 'chrome,resizable,modal,width=700,height=500',
            { 'xml' : xml, 'focus' : 'method', 'title' : $("patronStrings").getString('staff.patron.hold_notices.add_notif_record') }
        );
        if (fancy_prompt_data.fancy_status == 'complete') {
            var notification = new ahn();
            notification.isnew(1);
            notification.hold(g.ahr_id);
            notification.method( fancy_prompt_data.method );
            notification.note( fancy_prompt_data.note );
            var r = g.network.simple_request('FM_AHN_CREATE',[ ses(), notification ]); if (typeof r.ilsevent != 'undefined') throw(r);
            setTimeout(function(){fetch_and_render_all();},0);
        }
    } catch(E) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.hold_notices.new_notification.not_created'),E);
        setTimeout(function(){fetch_and_render_all();},0);
    }
}

function new_note() {
    try {
        var xml = '<groupbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1">';
        xml += '<caption label="' + $("patronStrings").getString('staff.patron.hold_notes.new_note') + '"/><grid flex="1"><columns><column/><column flex="1"/></columns><rows>';
        xml += '<row><label value="' + $('patronStrings').getString('staff.patron.hold_notes.new_note.public') + '"/><checkbox id="pub" name="fancy_data" checked="false"/></row>';
        xml += '<row><label value="' + $('patronStrings').getString('staff.patron.hold_notes.new_note.slip') + '"/><checkbox id="slip" name="fancy_data" checked="false"/></row>';
        xml += '<row><label value="' + $("patronStrings").getString('staff.patron.hold_notes.title') + '"/><textbox id="title" name="fancy_data" context="clipboard"/></row>';
        xml += '<row><label value="' + $("patronStrings").getString('staff.patron.hold_notes.body') + '"/><textbox multiline="true" id="note" name="fancy_data" context="clipboard"/></row>';
        xml += '<row><spacer/><hbox><button label="' + $("patronStrings").getString('staff.patron.hold_notes.cancel') + '" name="fancy_cancel" ';
        xml += 'accesskey="' + $("patronStrings").getString('staff.patron.hold_notes.cancel_accesskey') + '"/>';
        xml += '<button label="' + $("patronStrings").getString('staff.patron.hold_notes.add_note') + '" ';
        xml += 'accesskey="' + $("patronStrings").getString('staff.patron.hold_notes.add_note.accesskey') + '" name="fancy_submit"/></hbox></row></rows></grid></groupbox>';
        JSAN.use('util.window'); var win = new util.window();
        var fancy_prompt_data = win.open(
            urls.XUL_FANCY_PROMPT,
            'fancy_prompt', 'chrome,resizable,modal,width=700,height=500',
            { 'xml' : xml, 'focus' : 'title', 'title' : $("patronStrings").getString('staff.patron.hold_notes.add_note') }
        );
        if (fancy_prompt_data.fancy_status == 'complete') {
            var note = new ahrn();
            note.isnew(1);
            note.hold(g.ahr_id);
            note.title( fancy_prompt_data.title );
            note.body( fancy_prompt_data.note );
            note.pub( get_bool( fancy_prompt_data.pub ) ? get_db_true() : get_db_false() );
            note.slip( get_bool( fancy_prompt_data.slip ) ? get_db_true() : get_db_false() );
            note.staff( true );
            var r = g.network.simple_request('FM_AHRN_CREATE',[ ses(), note ]); if (typeof r.ilsevent != 'undefined') throw(r);
            //g.pcrud.create(note);
            setTimeout(function(){fetch_and_render_all();},0);
        }
    } catch(E) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.hold_notes.new_note.not_created'),E);
        setTimeout(function(){fetch_and_render_all();},0);
    }
}


