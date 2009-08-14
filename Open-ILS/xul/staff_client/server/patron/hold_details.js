
function $(id) { return document.getElementById(id); }

function my_init() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');


        dojo.require('openils.PermaCrud');
        JSAN.use('util.error'); g.error = new util.error();
        JSAN.use('util.network'); g.network = new util.network();
        JSAN.use('util.date'); JSAN.use('util.money'); JSAN.use('patron.util');
        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});

        g.error.sdump('D_TRACE','my_init() for hold_notices.xul');

        g.ahr_id = xul_param('ahr_id');

        g.ahr = g.network.simple_request('FM_AHR_RETRIEVE',[ ses(), g.ahr_id ]);
        if (typeof g.ahr.ilsevent != 'undefined') { throw(g.ahr); }
        g.ahr = g.ahr[0];

        render_patron();

        a_list_of_one();

        var x = document.getElementById('bib_brief_box'); while (x.firstChild) x.removeChild(x.lastChild);
        var bib_brief = document.createElement('iframe'); x.appendChild(bib_brief);
        bib_brief.setAttribute('flex',1);
        bib_brief.setAttribute('src',urls.XUL_BIB_BRIEF);
        get_contentWindow(bib_brief).xulG = { 'docid' : g.ahr.target() };

        refresh();

    } catch(E) {
        try { g.error.standard_unexpected_error_alert('/xul/server/patron/hold_notices.xul',E); } catch(E) { alert('FIXME: ' + js2JSON(E)); }
    }
}

function render_patron() {
    if (g.ahr.usr()) {
        JSAN.use('patron.util');
        var au_obj = patron.util.retrieve_fleshed_au_via_id( ses(), g.ahr.usr() );

        $('patron_name').setAttribute('value',
                                      ( au_obj.prefix() ? au_obj.prefix() + ' ' : '') +
                                      au_obj.family_name() + ', ' +
                                      au_obj.first_given_name() + ' ' +
                                      ( au_obj.second_given_name() ? au_obj.second_given_name() + ' ' : '' ) +
                                      ( au_obj.suffix() ? au_obj.suffix() : '')
                                      + ' : ' + au_obj.card().barcode()
                                      );
    }
}

function a_list_of_one() {
    JSAN.use('circ.util');
    var columns = circ.util.hold_columns(
                                         {
                                             'status' : { 'hidden' : true },
                                             'request_time' : { 'hidden' : false },
                                             'pickup_lib_shortname' : { 'hidden' : false },
                                             'current_copy' : { 'hidden' : false },
                                             'phone_notify' : { 'hidden' : false },
                                             'email_notify' : { 'hidden' : false },
                                         }
                                          );
    JSAN.use('util.list'); g.list = new util.list('holds_list');
    g.list.init(
                {
                    'columns' : columns,
                        'map_row_to_columns' : circ.util.std_map_row_to_columns(),
                        'retrieve_row' : function(params) {
                        var row = params.row;
                        try {
                            switch(row.my.ahr.hold_type()) {
                            case 'M' :
                                row.my.mvr = g.network.request(
                                                               api.MODS_SLIM_METARECORD_RETRIEVE.app,
                                                               api.MODS_SLIM_METARECORD_RETRIEVE.method,
                                                               [ row.my.ahr.target() ]
                                                               );
                                break;
                            default:
                                row.my.mvr = g.network.simple_request(
                                                                      'MODS_SLIM_RECORD_RETRIEVE.authoritative',
                                                                      [ row.my.ahr.target() ]
                                                                      );
                                if (row.my.ahr.current_copy()) {
                                    row.my.acp = g.network.simple_request( 'FM_ACP_RETRIEVE', [ row.my.ahr.current_copy() ]);
                                }
                                break;
                            }
                        } catch(E) {
                            g.error.sdump('D_ERROR','retrieve_row: ' + E );
                        }
                        if (typeof params.on_retrieve == 'function') {
                            params.on_retrieve(row);
                        }
                        return row;
                    },
                        }
                );
    g.list.append(
                  {
                      'row' : {
                          'my' : {
                              'ahr' : g.ahr,
                                  }
                      },
                          'no_auto_select' : true,
                              }
                  );
}

function refresh() {
    retrieve_notifications(); render_notifications(); retrieve_notes(); render_notes();
}

function retrieve_notifications() {
    g.notifications = g.network.simple_request('FM_AHN_RETRIEVE_VIA_AHR',[ ses(), g.ahr_id ]).reverse();
}

function retrieve_notes() {
    try{
        g.ahr_id = xul_param('ahr_id');

        g.notes = new openils.PermaCrud(
                                      {
                                          authtoken :ses()
                                      }
                                       ).search('ahrn', {hold:g.ahr_id});
    }
    catch(E){alert(E);}

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
        apply(node,'notify_time',g.notifications[i].notify_time() ? g.notifications[i].notify_time().toString().substr(0,10) : '');
    }

}

function render_notes() {

    JSAN.use('util.widgets'); util.widgets.remove_children('notes_panel');
    var notep = $('notes_panel');

    for (var i = 0; i < g.notes.length; i++) {

        // template
        var notenode = $('note_template').cloneNode(true); notep.appendChild(notenode); notenode.hidden = false;

        /* alert('notenode = '
              + notenode + ' title = ' + g.notes[i].title() + ' note = ' +
              g.notes[i].body() + ' pub = ' + g.notes[i].pub() + ' slip = ' +
              g.notes[i].slip() );*/

        apply(notenode,'title',g.notes[i].title() ? g.notes[i].title() : '');
        apply(notenode,'note',g.notes[i].body() ? g.notes[i].body() : '');
        apply(notenode,'pub',g.notes[i].pub() ? g.notes[i].pub() : '');
        apply(notenode,'slip',g.notes[i].slip() ? g.notes[i].slip() : '');
    }
}
function new_notification() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect UniversalBrowserWrite");
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
            setTimeout(function(){refresh();},0);
        }
    } catch(E) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.hold_notices.new_notification.not_created'),E);
        setTimeout(function(){refresh();},0);
    }
}

function new_note() {
     try{
     var newNote = new fieldmapper.ahrn();
     newNote.isnew("t");
     newNote.body(document.getElementById('hold_note_text').value);
     newNote.hold(g.ahr_id);
     newNote.title(document.getElementById('hold_note_title').value);

     if($('pub_bool').checked){
         newNote.pub("t");
     }else {
         newNote.pub("f");
     }
     if($('print_bool').checked){
         newNote.slip("t");
     }else{
         newNote.slip("f");
     }
     newNote.staff("t");

     new openils.PermaCrud({authtoken :ses()}).create(newNote);

     }
     catch(E) {
         alert('new_note FAILED');
     }
     refresh();
}