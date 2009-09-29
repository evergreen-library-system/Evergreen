function $(id) { return document.getElementById(id); }

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
            g.funcs.push( gen_func(g.mbts_ids[i]) );
        }
    }
}

function init_lists() {
    JSAN.use('util.list'); JSAN.use('circ.util'); 
    g.bill_list = new util.list('bill_tree');

    g.bill_list.init( {
        'columns' : 
            patron.util.mbts_columns({
                'xact_finish' : { 'hidden' : xul_param('current') ? true : false }
            }).concat( 
            circ.util.columns({ 
                'title' : { 'hidden' : false, 'flex' : '3' }
            }) 
        ),
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
        },
        'retrieve_row' : function(params) {
            var id = params.retrieve_id;
            var row = params.row;
            if (id) {
                if (typeof row.my == 'undefined') row.my = {};
                if (typeof row.my.mbts == 'undefined' ) {
                    g.network.simple_request('BLOB_MBTS_DETAILS_RETRIEVE',[ses(),id], function(req) {
                        var blob = req.getResultObject();
                        row.my.mbts = blob.transaction;
                        row.my.circ = blob.circ;
                        row.my.acp = blob.copy;
                        row.my.mvr = blob.record;
                        if (typeof params.on_retrieve == 'function') {
                            params.on_retrieve(row);
                        }
                    } );
                }
            }
            return row;
        },
    } );

    $('bill_list_actions').appendChild( g.bill_list.render_list_actions() );
    g.bill_list.set_list_actions();
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

        if (xul_param('current')) {
            $('caption').setAttribute('label',$("patronStrings").getString('staff.patron.bill_history.my_init.current_bills'));
            document.title = $("patronStrings").getString('staff.patron.bill_history.my_init.current_bills');
        } else {
            $('caption').setAttribute('label',$("patronStrings").getString('staff.patron.bill_history.my_init.bill_history'));
            document.title = $("patronStrings").getString('staff.patron.bill_history.my_init.bill_history');
        }

        g.funcs = [];

        g.patron_id = xul_param('patron_id');

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

        JSAN.use('util.exec'); var exec = new util.exec(20); 
        exec.on_error = function(E) { alert(E); return true; }
        exec.timer(g.funcs,100);
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


