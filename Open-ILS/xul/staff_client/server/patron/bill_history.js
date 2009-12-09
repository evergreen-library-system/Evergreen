function $(id) { return document.getElementById(id); }
var payment_history_fetched = false;

function tally_selected() {
    try {
        JSAN.use('util.money');
        var selected_billed = 0;
        var selected_paid = 0;

        for (var i = 0; i < g.bill_list_selection.length; i++) {
            var bill = g.bill_map[g.bill_list_selection[i]];
            if (!bill) {
                $('billed_tally').setAttribute('value', '???');
                $('paid_tally').setAttribute('value', '???');
                return;
            }
            var to = util.money.dollars_float_to_cents_integer( bill.transaction.total_owed() );
            var tp = util.money.dollars_float_to_cents_integer( bill.transaction.total_paid() );
            selected_billed += to;
            selected_paid += tp;
        }
        $('billed_tally').setAttribute('value', '$' + util.money.cents_as_dollars( selected_billed ) );
        $('paid_tally').setAttribute('value', '$' + util.money.cents_as_dollars( selected_paid ) );
    } catch(E) {
        alert('Error in bill_history.js, tally_selected(): ' + E);
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

    init_main_list();
    init_payments_list();
}

function init_main_list() {
    g.bill_list_selection = [];

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
            tally_selected();
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
                        g.bill_map[ id ] = blob;
                        if (typeof params.on_retrieve == 'function') {
                            params.on_retrieve(row);
                        };
                        tally_selected();
                    } );
                }
            }
            return row;
        },
    } );

    $('bill_list_actions').appendChild( g.bill_list.render_list_actions() );
    g.bill_list.set_list_actions();
}

function init_payments_list() {
    g.payments_list_selection = [];

    g.payments_list = new util.list('payments_tree');

    g.payments_list.init( {
        'columns' : g.payments_list.fm_columns('mp'),
        'on_select' : function(ev) {
            JSAN.use('util.functional');
            g.payments_list_selection = util.functional.map_list(
                g.payments_list.retrieve_selection(),
                function(o) { return JSON2js( o.getAttribute('retrieve_id') ); }
            );
            $('payments_details').disabled = g.payments_list_selection.length == 0;
        },
        'retrieve_row' : function(params) {
            var id = params.retrieve_id;
            var row = params.row;
            if (typeof params.on_retrieve == 'function') {
                params.on_retrieve(row);
            };
            return row;
        },
    } );

    $('payments_list_actions').appendChild( g.payments_list.render_list_actions() );
    g.payments_list.set_list_actions();
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

        g.funcs = []; g.bill_map = {};

        g.patron_id = xul_param('patron_id');

        init_lists();

        retrieve_mbts_for_list();

        $('details').addEventListener(
            'command',
            gen_handle_details('bills'),
            false
        );

        $('payments_details').addEventListener(
            'command',
            gen_handle_details('payments'),
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
        for (var i = 0; i < g.bill_list_selection.length; i++) {
            var w = win.open(
                urls.XUL_PATRON_BILL_WIZARD,
                'billwizard',
                'chrome,resizable,modal',
                { 'patron_id' : g.patron_id, 'xact_id' : g.bill_list_selection[i] }
            );
        }
        g.bill_list.clear();
        retrieve_mbts_for_list();
        if (typeof window.refresh == 'function') window.refresh();
        if (typeof window.xulG == 'object' && typeof window.xulG.refresh == 'function') window.xulG.refresh();
    }
}

function gen_handle_details(which_list) {
    return function() {
        JSAN.use('util.functional');
        var selection;
        switch(which_list) {
            case 'payments': selection = util.functional.map_list( g.payments_list_selection, function(o) { return o.xact; } ); break;
            default: selection = g.bill_list_selection; break;
        }
        JSAN.use('util.window'); var win = new util.window();
        for (var i = 0; i < selection.length; i++) {
            var my_xulG = win.open(
                urls.XUL_PATRON_BILL_DETAILS,
                'test_billdetails_' + selection[i],
                'chrome,resizable',
                {
                    'patron_id' : g.patron_id,
                    'mbts_id' : selection[i],
                    'refresh' : function() { 
                        if (typeof window.refresh == 'function') window.refresh();
                        if (typeof window.xulG == 'object' && typeof window.xulG.refresh == 'function') window.xulG.refresh();
                    }, 
                }
            );
        }
    };
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

function payment_history_init() {
    try {
        if (payment_history_fetched) { return; } else { payment_history_fetched = true; }

        $('payments_date1').year = $('payments_date1').year - 1;

        retrieve_payments();

    } catch(E) {
        alert('Error in bill_history.js, payment_history_init(): ' + E);
    }
}

function retrieve_payments() {
    try {

        g.payments_list.clear();

        $('payments_meter').hidden = false;

        var filters = {
            'where' : {
                'payment_ts' : {
                    'between' : [
                        $('payments_date1').value,
                        $('payments_date2').value == util.date.formatted_date(new Date(),'%F') ? 'now' : $('payments_date2').value 
                    ]
                }
            }
        };

        fieldmapper.standardRequest(
            [ api.FM_MP_RETRIEVE_VIA_USER.app, api.FM_MP_RETRIEVE_VIA_USER.method ],
            {   async: true,
                params: [ses(), g.patron_id, filters],
                onresponse: function(r) {
                    try {
                        var result = r.recv().content();

                        if (result && typeof result.ilsevent == 'undefined') {
                            g.payments_list.append( 
                                { 
                                    'retrieve_id' : js2JSON( { 'id' : result.id(), 'xact' : result.xact() } ),
                                    'row' : { 
                                        'my' : { 
                                            'mp' : result 
                                        } 
                                    } 
                                } 
                            );
                        } else {
                            throw( js2JSON(result) );
                        }
                    } catch(E) {
                        alert('Error retrieving payment in bill_history.js, onresponse: ' + E);                        
                    }
                },
                oncomplete: function() {
                    $('payments_meter').hidden = true;
                },
                onerror: function(r) {
                    var result = r.recv().content();
                    alert('Error retrieving payment in bill_history.js, onerror: ' + js2JSON(result));                        
                }
            }
        );

    } catch(E) {
        alert('Error in bill_history.js, retrieve_payments(): ' + E);
    }
}
