function $(id) { return document.getElementById(id); }

function retrieve_patron() {
    g.patron_id = xul_param('patron_id');

    if (g.patron_id) {
        JSAN.use('patron.util'); 
        g.au_obj = patron.util.retrieve_fleshed_au_via_id( ses(), g.patron_id );
        
        $('patron_name').setAttribute('value', 
            ( g.au_obj.prefix() ? g.au_obj.prefix() + ' ' : '') + 
            g.au_obj.family_name() + ', ' + 
            g.au_obj.first_given_name() + ' ' +
            ( g.au_obj.second_given_name() ? g.au_obj.second_given_name() + ' ' : '' ) +
            ( g.au_obj.suffix() ? g.au_obj.suffix() : '')
            + ' : ' + g.au_obj.card().barcode() 
        );
    }

}

function retrieve_mbts_for_list() {
    //var method = 'FM_MBTS_IDS_RETRIEVE_ALL_HAVING_CHARGE';
    var method = 'FM_MBTS_IDS_RETRIEVE_FOR_HISTORY.authoritative';
    if (xul_param('current')) method = 'FM_MBTS_IDS_RETRIEVE_ALL_HAVING_BALANCE.authoritative';
    g.mbts_ids = g.network.simple_request(method,[ses(),g.patron_id]);
    if (g.mbts_ids.ilsevent) {
        switch(Number(g.mbts_ids.ilsevent)) {
            case -1: g.error.standard_network_error_alert($("patronStrings").getString('staff.patron.bill_history.retrieve_mbts_for_list.close_win_try_again')); break;
            default: g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.bill_history.retrieve_mbts_for_list.close_win_try_again'),g.mbts_ids); break;
        }
    } else if (g.mbts_ids == null) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.bill_history.retrieve_mbts_for_list.close_win_try_again'),null);
    } else {
        //g.mbts_ids.reverse();
        var funcs = [];
    
                function gen_func(r) {
                    return function() {
                        if (typeof r == 'object') {
                            g.bill_list.append( 
                                { 
                                    'retrieve_id' : r.id(), 
                                    'row' : { 
                                        'my' : { 
                                            'mbts' : r 
                                        } 
                                    } 
                                } 
                            );
                        } else {
                            g.bill_list.append( 
                                { 
                                    'retrieve_id' : r, 
                                    'row' : { 
                                        'my' : {} 
                                    } 
                                } 
                            );
                        }
                    }
                }
    
        for (var i = 0; i < g.mbts_ids.length; i++) {
            dump('i = ' + i + ' g.mbts_ids[i] = ' + g.mbts_ids[i] + '\n');
            funcs.push( gen_func(g.mbts_ids[i]) );
        }
        JSAN.use('util.exec'); var exec = new util.exec(4);
        exec.on_error = function(E) { alert(E); return true; }
        exec.chain(funcs);
    }
}

function retrieve_specific_mbts() {
    if (g.mbts_id) g.network.simple_request('FM_MBTS_RETRIEVE.authoritative',[ses(),g.mbts_id],
        function(req) {
            try {
                g.mbts = req.getResultObject();
                if (g.mbts.ilsevent) {
                    switch(Number(g.mbts.ilsevent)) {
                        case -1: g.error.standard_network_error_alert('mbts_id = ' + g.mbts_id); break;
                        default: g.error.standard_unexpected_error_alert('mbts_id = ' + g.mbts_id,g.mbts); break;
                    }
                } else {
                    $('mbts_id').value = g.mbts_id;
                    $('mbts_xact_type').value = g.mbts.xact_type();
                    $('mbts_xact_start').value = g.mbts.xact_start().toString().substr(0,19);
                    $('mbts_xact_finish').value = g.mbts.xact_finish() ? g.mbts.xact_finish().toString().substr(0,19) : '';
                    $('mbts_total_owed').value = g.mbts.total_owed() ? util.money.sanitize( g.mbts.total_owed() ) : '';
                    $('mbts_total_paid').value = g.mbts.total_paid() ? util.money.sanitize( g.mbts.total_paid() ) : '';
                    $('mbts_balance_owed').value = g.mbts.balance_owed() ? util.money.sanitize( g.mbts.balance_owed() ) : '';
                }
            } catch(E) {
                g.error.sdump('D_ERROR',E);
            }
        }
    );
}

function retrieve_circ() {
    JSAN.use('util.widgets');
    util.widgets.remove_children('title');
    $('title_label').hidden = true;
    $('checked_out_label').hidden = true;
    $('due_label').hidden = true;
    $('checked_in_label').hidden = true;
    $('checked_out').value = '';
    $('checked_in').value = '';
    $('due').value = '';
    $('copy_summary').hidden=true;

    g.network.simple_request('FM_CIRC_RETRIEVE_VIA_ID', [ ses(), g.mbts_id ],
        function (req) {
            var r_circ = req.getResultObject();
            if (instanceOf(r_circ,circ)) {

                $('title_label').hidden = false;
                $('checked_out_label').hidden = false;
                $('due_label').hidden = false;
                $('checked_in_label').hidden = false;
                $('checked_out').value = r_circ.xact_start() ? r_circ.xact_start().toString().substr(0,10) : '';
                $('checked_in').value = r_circ.checkin_time() ? r_circ.checkin_time().toString().substr(0,10) : '';
                $('due').value = r_circ.due_date() ? r_circ.due_date().toString().substr(0,10) : '';

                netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
                $('copy_summary').setAttribute('src',urls.XUL_COPY_SUMMARY + '?copy_id=' + r_circ.target_copy());
                //get_contentWindow($('copy_summary')).xulG = { 'copy_id' : r_circ.target_copy() };
                $('copy_summary').hidden=false;

                g.network.simple_request(
                    'MODS_SLIM_RECORD_RETRIEVE_VIA_COPY.authoritative',
                    [ r_circ.target_copy() ],
                    function (rreq) {
                        var r_mvr = rreq.getResultObject();
                        if (instanceOf(r_mvr,mvr)) {
                            $('title').appendChild( document.createTextNode( String(r_mvr.title()).substr(0,50) ) );
                        } else {
                            g.network.simple_request(
                                'FM_ACP_RETRIEVE',
                                [ r_circ.target_copy() ],
                                function (rrreq) {
                                    var r_acp = rrreq.getResultObject();
                                    if (instanceOf(r_acp,acp)) {
                                        $('title').appendChild( document.createTextNode( r_acp.dummy_title() ) );
                                    }
                                }
                            );
                        }
                    }
                );

            }
        }
    );
}

function init_lists() {
    JSAN.use('util.list'); 
    g.bill_list = new util.list('bill_tree');

    g.bill_list.init( {
        'columns' : patron.util.mbts_columns({}),
        'map_row_to_columns' : patron.util.std_map_row_to_columns(' '),
        'on_select' : function(ev) {
            JSAN.use('util.functional');
            g.bill_list_selection = util.functional.map_list(
                g.bill_list.retrieve_selection(),
                function(o) { return o.getAttribute('retrieve_id'); }
            );
            $('details').disabled = g.bill_list_selection.length == 0;
            $('add').disabled = g.bill_list_selection.length == 0;
            $('summary').hidden = g.bill_list_selection.length == 0;
            $('copy_summary').hidden = g.bill_list_selection.length == 0;
            g.mbts_id = g.bill_list_selection[0];
            retrieve_specific_mbts();
            retrieve_circ();
        },
        'retrieve_row' : function(params) {
            var id = params.retrieve_id;
            var row = params.row;
            if (id) {
                if (typeof row.my == 'undefined') row.my = {};
                if ( typeof row.my.mbts == 'undefined' ) {
                    var mbts_obj = g.network.simple_request('FM_MBTS_RETRIEVE.authoritative',[ses(),id]);
                    row.my.mbts = mbts_obj;
                }
            }
            if (typeof params.on_retrieve == 'function') {
                params.on_retrieve(row);
            }
            return row;
        },
    } );

}

function my_init() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');

        JSAN.use('util.error'); g.error = new util.error();
        JSAN.use('util.network'); g.network = new util.network();
        JSAN.use('util.date');
        JSAN.use('util.money');
        JSAN.use('patron.util');
        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
        //g.data.temp = ''; g.data.stash('temp');

        g.error.sdump('D_TRACE','my_init() for bill_history.xul');

        retrieve_patron();

        init_lists();

        retrieve_mbts_for_list();

        $('details').addEventListener(
            'command',
            handle_details,
            false
        );

        $('add').addEventListener(
            'command',
            handle_add,
            false
        );

        if (xul_param('current')) {
            $('caption').setAttribute('label',$("patronStrings").getString('staff.patron.bill_history.my_init.current_bills'));
            document.title = $("patronStrings").getString('staff.patron.bill_history.my_init.current_bills');
        } else {
            $('caption').setAttribute('label',$("patronStrings").getString('staff.patron.bill_history.my_init.bill_history'));
            document.title = $("patronStrings").getString('staff.patron.bill_history.my_init.bill_history');
        }

    } catch(E) {
        var err_msg = $("commonStrings").getFormattedString('common.exception', ['patron/bill_history.xul', E]);
        try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
        alert(err_msg);
    }
}

function handle_add() {
    if(g.bill_list_selection.length > 1)
        var msg = $("patronStrings").getFormattedString('staff.patron.bill_history.handle_add.message_plural', [g.bill_list_selection]);
    else
        var msg = $("patronStrings").getFormattedString('staff.patron.bill_history.handle_add.message_singular', [g.bill_list_selection]);
        
    var r = g.error.yns_alert(msg,
        $("patronStrings").getString('staff.patron.bill_history.handle_add.title'),
        $("patronStrings").getString('staff.patron.bill_history.handle_add.btn_yes'),
        $("patronStrings").getString('staff.patron.bill_history.handle_add.btn_no'),null,
        $("patronStrings").getString('staff.patron.bill_history.handle_add.confirm_message'));
    if (r == 0) {
        JSAN.use('util.window');
        var win = new util.window();
        var w = win.open(
            urls.XUL_PATRON_BILL_WIZARD,
                //+ '?patron_id=' + window.escape(g.patron_id)
                //+ '&xact_id=' + window.escape( g.bill_list_selection[0] ),
            'billwizard',
            'chrome,resizable,modal',
            { 'patron_id' : g.patron_id, 'xact_id' : g.bill_list_selection[0] }
        );
        g.bill_list.clear();
        retrieve_mbts_for_list();
        if (typeof window.refresh == 'function') window.refresh();
        if (typeof window.xulG == 'object' && typeof window.xulG.refresh == 'function') window.xulG.refresh();
    }
}

function handle_details() {
    JSAN.use('util.window'); var win = new util.window();
    var my_xulG = win.open(
        urls.XUL_PATRON_BILL_DETAILS,
        //+ '?patron_id=' + window.escape(g.patron_id)
        //+ '&mbts_id=' + window.escape( g.bill_list_selection[0] ),
        'test_billdetails',
        'chrome,resizable',
        {
            'patron_id' : g.patron_id,
            'mbts_id' : g.bill_list_selection[0],
            'refresh' : function() { 
                if (typeof window.refresh == 'function') window.refresh();
                if (typeof window.xulG == 'object' && typeof window.xulG.refresh == 'function') window.xulG.refresh();
            }, 
        }
    );
}

function print_bills() {
    try {
        var template = 'bills_historical'; if (xul_param('current')) template = 'bills_current';
        JSAN.use('patron.util');
        var params = { 
            'patron' : patron.util.retrieve_au_via_id(ses(),g.patron_id), 
            'template' : template
        };
        g.bill_list.print(params);
    } catch(E) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.bill_history.print_bills.print_error'), E);
    }
}


