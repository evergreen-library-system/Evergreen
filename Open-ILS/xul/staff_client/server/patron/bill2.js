function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');

        JSAN.use('util.error'); g.error = new util.error();
        JSAN.use('util.network'); g.network = new util.network();
        JSAN.use('util.date');
        JSAN.use('util.money');
        JSAN.use('util.widgets');
        JSAN.use('patron.util');
        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
        g.data.voided_billings = []; g.data.stash('voided_billings');

        g.error.sdump('D_TRACE','my_init() for bill2.xul');

        document.title = $("patronStrings").getString('staff.patron.bill_history.my_init.current_bills');

        g.funcs = []; g.bill_map = {}; g.row_map = {}; g.check_map = {};

        g.patron_id = xul_param('patron_id');

        $('circulating_hint').hidden = true;

        init_lists();

        retrieve_mbts_for_list();

        event_listeners();

        JSAN.use('util.exec'); var exec = new util.exec(20); 
        exec.on_error = function(E) { alert(E); return true; }
        exec.timer(g.funcs,100);

        $('credit_forward').setAttribute('value','???');
        if (!g.patron) {
            refresh_patron();
        } else {
            $('credit_forward').setAttribute('value',util.money.sanitize( g.patron.credit_forward_balance() ));
        }

        if (g.data.hash.aous['ui.circ.billing.uncheck_bills_and_unfocus_payment_box']) {
            g.funcs.push(
                function() {
                    $('uncheck_all').focus();
                    tally_all();
                }
            );
        } else {
            g.funcs.push(
                function() {
                    default_focus();
                    tally_all();
                }
            );
        }

    } catch(E) {
        var err_msg = $("commonStrings").getFormattedString('common.exception', ['patron/bill2.xul', E]);
        try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
        alert(err_msg);
    }
}

function event_listeners() {
    try {
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

        $('voidall').addEventListener(
            'command',
            handle_void_all,
            false
        );

        $('refund').addEventListener(
            'command',
            handle_refund,
            false
        );

        $('opac').addEventListener(
            'command',
            handle_opac,
            false
        );

        $('copy_details').addEventListener(
            'command',
            handle_copy_details,
            false
        );

        $('payment').addEventListener(
            'change',
            function(ev) {
                if ($('payment_type').value == 'credit_payment') {
                    JSAN.use('util.money');
                    JSAN.use('patron.util'); g.patron = patron.util.retrieve_fleshed_au_via_id(ses(),g.patron_id,null);
                    var proposed = util.money.dollars_float_to_cents_integer(ev.target.value);
                    var available = util.money.dollars_float_to_cents_integer(g.patron.credit_forward_balance());
                    if (proposed > available) {
                        alert($("patronStrings").getFormattedString('staff.patron.bills.bill_payment_amount.credit_amount', [g.patron.credit_forward_balance()]));
                        ev.target.value = util.money.cents_as_dollars( available );
                        ev.target.setAttribute('value',ev.target.value);
                    }
                }
                distribute_payment(); 
            },
            false
        );

        $('payment').addEventListener(
            'focus',
            function(ev) { ev.target.select(); },
            false
        );

        $('payment').addEventListener(
            'keypress',
            function(ev) {
                if (! (ev.keyCode == 13 /* enter */ || ev.keyCode == 77 /* mac enter */) ) { return; }
                distribute_payment();
                $('apply_payment_btn').focus();
            },
            false
        );

        $('bill_patron_btn').addEventListener(
            'command',
            function() {
                JSAN.use('util.window'); var win = new util.window();
                var my_xulG = win.open(
                    urls.XUL_PATRON_BILL_WIZARD,
                    'billwizard',
                    'chrome,resizable,modal',
                    { 'patron_id' : g.patron_id }
                );
                if (my_xulG.xact_id) {
                    g.funcs.push( gen_list_append_func( my_xulG.xact_id ) );
                    if (typeof window.xulG == 'object' && typeof window.xulG.on_money_change == 'function') window.xulG.on_money_change();
                }
            },
            false
        );

        $('bill_history_btn').addEventListener(
            'command',
            function() {
                xulG.display_window.g.patron.right_deck.reset_iframe( 
                    urls.XUL_PATRON_BILL_HISTORY,
                    {},
                    {
                        'patron_id' : g.patron_id,
                        'refresh' : function() { refresh(); },
                        'new_tab' : xulG.new_tab,
                        'url_prefix' : xulG.url_prefix
                    }
                );
            },
            false
        );

        $('convert_change_to_credit').addEventListener(
            'command',
            function(ev) {
                if (ev.target.checked) {
                    addCSSClass( $('change_due'), 'change_to_credit' );
                } else {
                    removeCSSClass( $('change_due'), 'change_to_credit' );
                }
            },
            false
        );

        $('apply_payment_btn').addEventListener(
            'command',
            function(ev) {
                try {
                    $('apply_payment_btn').disabled = true;
                    apply_payment();
                    tally_all();
                    $('apply_payment_btn').disabled = false;
                } catch(E) {
                    alert('Error in bill2.js, apply_payment_btn: ' + E);
                }
            },
            false
        );

    } catch(E) {
        alert('Error in bill2.js, event_listeners(): ' + E);
    }
}

function $(id) { return document.getElementById(id); }

function default_focus() {
    try { $('payment').focus(); } catch(E) { alert('Error in default_focus(): ' + E); }
}

function tally_pending() {
    try {
        var payments = [];
        JSAN.use('util.money');
        var tb = $('payment');
        var payment_tendered = util.money.dollars_float_to_cents_integer( tb.value );
        var payment_pending = 0;
        var retrieve_ids = g.bill_list.dump_retrieve_ids();
        for (var i = 0; i < retrieve_ids.length; i++) {
            var row_params = g.row_map[retrieve_ids[i]];
            if (g.check_map[retrieve_ids[i]]) { 
                var value = util.money.dollars_float_to_cents_integer( row_params.row.my.payment_pending );
                payment_pending += value;
                if (value != '0.00') { payments.push( [ retrieve_ids[i], util.money.cents_as_dollars(value) ] ); }
            }
        }
        var change_pending = payment_tendered - payment_pending;
        $('pending_payment').value = util.money.cents_as_dollars( payment_pending );
        $('pending_change').value = util.money.cents_as_dollars( change_pending );
        $('change_due').value = util.money.cents_as_dollars( change_pending );
        return { 'payments' : payments, 'change' : util.money.cents_as_dollars( change_pending ) };
    } catch(E) {
        alert('Error in bill2.js, tally_pending(): ' + E);
    }
}

function tally_selected() {
    try {
        JSAN.use('util.money');
        var selected_billed = 0;
        var selected_paid = 0;
        var selected_balance = 0;

        for (var i = 0; i < g.bill_list_selection.length; i++) {
            var bill = g.bill_map[g.bill_list_selection[i]];
            if (!bill) {
                //$('checked_owed').setAttribute('value', '???');
                //$('checked_billed').setAttribute('value', '???');
                //$('checked_paid').setAttribute('value', '???');
                return;
            }
            var to = util.money.dollars_float_to_cents_integer( bill.transaction.total_owed() );
            var tp = util.money.dollars_float_to_cents_integer( bill.transaction.total_paid() );
            var bo = util.money.dollars_float_to_cents_integer( bill.transaction.balance_owed() );
            selected_billed += to;
            selected_paid += tp;
            selected_balance += bo;
        }
        //$('checked_billed').setAttribute('value', util.money.cents_as_dollars( selected_billed ) );
        //$('checked_paid').setAttribute('value', util.money.cents_as_dollars( selected_paid ) );
        //$('checked_owed').setAttribute('value', util.money.cents_as_dollars( selected_balance ) );
    } catch(E) {
        alert('Error in bill2.js, tally_selected(): ' + E);
    }
}

function tally_voided() {
    try {
        JSAN.use('util.money');
        var voided_total = 0;

        g.data.stash_retrieve();

        for (var i = 0; i < g.data.voided_billings.length; i++) {
            var billing = g.data.voided_billings[i];
            var bv = util.money.dollars_float_to_cents_integer( billing.amount() );
            voided_total += bv;
        }
        $('currently_voided').setAttribute('value', util.money.cents_as_dollars( voided_total ) );
    } catch(E) {
        alert('Error in bill2.js, tally_voided(): ' + E);
    }
}

function tally_all() {
    try {
        JSAN.use('util.money');
        var checked_billed = 0;
        var checked_paid = 0;
        var checked_balance = 0;
        var total_billed = 0;
        var total_paid = 0;
        var total_balance = 0;
        var refunds_owed = 0;

        var retrieve_ids = g.bill_list.dump_retrieve_ids();
        for (var i = 0; i < retrieve_ids.length; i++) {
            var bill = g.bill_map[retrieve_ids[i]];
            if (!bill) {
                $('checked_owed').value = '???';
                $('checked_owed2').setAttribute('value', '???');
                $('checked_billed').value = '???';
                $('checked_paid').value = '???';
                $('tb_total_owed').value = '???';
                $('total_owed2').setAttribute('value', '???');
                $('total_billed').value = '???';
                $('tb_total_paid').value = '???';
                $('refunds_owed').setAttribute('value', '???');
                return;
            }
            var to = util.money.dollars_float_to_cents_integer( bill.transaction.total_owed() );
            var tp = util.money.dollars_float_to_cents_integer( bill.transaction.total_paid() );
            var bo = util.money.dollars_float_to_cents_integer( bill.transaction.balance_owed() );
            total_billed += to;
            total_paid += tp;
            total_balance += bo;
            if ( bo < 0 ) refunds_owed += bo;
            if (g.check_map[retrieve_ids[i]]) {
                checked_billed += to;
                checked_paid += tp;
                checked_balance += bo;
            }
        }
        $('checked_billed').value = util.money.cents_as_dollars( checked_billed );
        $('checked_paid').value = util.money.cents_as_dollars( checked_paid );
        $('checked_owed').value = util.money.cents_as_dollars( checked_balance );
        $('checked_owed2').setAttribute('value', util.money.cents_as_dollars( checked_balance ) );
        $('total_billed').value = util.money.cents_as_dollars( total_billed );
        $('tb_total_paid').value = util.money.cents_as_dollars( total_paid );
        $('tb_total_owed').value = util.money.cents_as_dollars( total_balance );
        $('total_owed2').setAttribute('value', util.money.cents_as_dollars( total_balance ) );
        $('refunds_owed').setAttribute('value', util.money.cents_as_dollars( Math.abs( refunds_owed ) ) );
        // tally_selected();
    } catch(E) {
        alert('Error in bill2.js, tally_all(): ' + E);
    }
}

function handle_refund() {
    if(g.bill_list_selection.length > 1) {
        var msg = $("patronStrings").getFormattedString('staff.patron.bills.handle_refund.message_plural', [g.bill_list_selection]);
    } else {
        var msg = $("patronStrings").getFormattedString('staff.patron.bills.handle_refund.message_singular', [g.bill_list_selection]);
    }
        
    var r = g.error.yns_alert(msg,
        $("patronStrings").getString('staff.patron.bills.handle_refund.title'),
        $("patronStrings").getString('staff.patron.bills.handle_refund.btn_yes'),
        $("patronStrings").getString('staff.patron.bills.handle_refund.btn_no'),null,
        $("patronStrings").getString('staff.patron.bills.handle_refund.confirm_message'));
    if (r == 0) {
        for (var i = 0; i < g.bill_list_selection.length; i++) {
            var bill_id = g.bill_list_selection[i];
            //alert('g.check_map['+bill_id+'] = '+g.check_map[bill_id]+' bill_map['+bill_id+'] = ' + js2JSON(g.bill_map[bill_id]));
            g.check_map[bill_id] = true;
            var row_params = g.row_map[bill_id];
            row_params.row.my.checked = true;
            g.bill_list.refresh_row(row_params);
        }
    }
    tally_all();
    distribute_payment();
}


function check_all() {
    try {
        for (var i in g.bill_map) {
            g.check_map[i] = true;
            var row_params = g.row_map[i];
            row_params.row.my.checked = true;
            g.bill_list.refresh_row(row_params);
        }
        tally_all();
        distribute_payment();
    } catch(E) {
        alert('Error in bill2.js, check_all(): ' + E);
    }

}

function uncheck_all() {
    try {
        for (var i in g.bill_map) {
            g.check_map[i] = false;
            var row_params = g.row_map[i];
            row_params.row.my.checked = false;
            g.bill_list.refresh_row(row_params);
        }
        tally_all();
        distribute_payment();
    } catch(E) {
        alert('Error in bill2.js, check_all(): ' + E);
    }

}

function check_all_refunds() {
    try {
        for (var i in g.bill_map) {
            if ( Number( g.bill_map[i].transaction.balance_owed() ) < 0 ) {
                g.check_map[i] = true;
                var row_params = g.row_map[i];
                row_params.row.my.checked = true;
                g.bill_list.refresh_row(row_params);
            }
        }
        tally_all();
        distribute_payment();
    } catch(E) {
        alert('Error in bill2.js, check_all_refunds(): ' + E);
    }
}

function gen_list_append_func(r) {
    return function() {
        var default_check_state = g.data.hash.aous[
            'ui.circ.billing.uncheck_bills_and_unfocus_payment_box'
        ] ? false : true;
        if (typeof r == 'object') {
            g.row_map[ r.id() ] = g.bill_list.append( {
                'retrieve_id' : r.id(),
                'flesh_immediately' : true,
                'row' : {
                    'my' : {
                        'checked' : default_check_state,
                        'mbts' : r
                    }
                }
            } );
        } else {
            g.row_map[r] = g.bill_list.append( {
                'retrieve_id' : r,
                'flesh_immediately' : true,
                'row' : {
                    'my' : {
                        'checked' : default_check_state
                    }
                }
            } );
        }
    }
}

function retrieve_mbts_for_list() {
    var method = 'FM_MBTS_IDS_RETRIEVE_ALL_HAVING_BALANCE.authoritative';
    g.mbts_ids = g.network.simple_request(method,[ses(),g.patron_id]);
    if (g.mbts_ids.ilsevent) {
        switch(Number(g.mbts_ids.ilsevent)) {
            case -1: g.error.standard_network_error_alert($("patronStrings").getString('staff.patron.bill_history.retrieve_mbts_for_list.close_win_try_again')); break;
            default: g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.bill_history.retrieve_mbts_for_list.close_win_try_again'),g.mbts_ids); break;
        }
    } else if (g.mbts_ids == null) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.bill_history.retrieve_mbts_for_list.close_win_try_again'),null);
    } else {
   
        g.mbts_ids.reverse();
 
        for (var i = 0; i < g.mbts_ids.length; i++) {
            dump('i = ' + i + ' g.mbts_ids[i] = ' + g.mbts_ids[i] + '\n');
            g.funcs.push( gen_list_append_func(g.mbts_ids[i]) );
        }
    }
}

function init_lists() {
    JSAN.use('util.list'); JSAN.use('circ.util'); 

    g.bill_list_selection = [];

    g.bill_list = new util.list('bill_tree');

    g.bill_list.init( {
        'columns' : 
            [
                {
                    'id' : 'select', 'primary' : true, 'type' : 'checkbox', 'editable' : true, 'label' : '', 'style' : 'min-width: 3em;',
                    'render' : function(my) { return String( my.checked ) == 'true'; }, 
                }
            ].concat(
                patron.util.mbts_columns({
                    'mbts_xact_finish' : { 'hidden' : true }
                }
            ).concat( 
                circ.util.columns({ 
                    'title' : { 'hidden' : false, 'flex' : '3' }
                }
            ).concat( 
                [
                    {
                        'id' : 'payment_pending', 'editable' : false, 'sort_type' : 'money', 
                        'label' : $('patronStrings').getString('staff.patron.bill_interface.payment_pending.column_header'),
                        'render' : function(my) { return my.payment_pending || '0.00'; }, 
                    }
                ]
            ))),
        'on_select' : function(ev) {
            JSAN.use('util.functional');
            g.bill_list_selection = util.functional.map_list(
                g.bill_list.retrieve_selection(),
                function(o) { return o.getAttribute('retrieve_id'); }
            );
            //tally_selected();
            $('details').setAttribute('disabled', g.bill_list_selection.length == 0);
            $('add').setAttribute('disabled', g.bill_list_selection.length == 0);
            $('voidall').setAttribute('disabled', g.bill_list_selection.length == 0);
            $('refund').setAttribute('disabled', g.bill_list_selection.length == 0);
            $('opac').setAttribute('disabled', g.bill_list_selection.length == 0);
            $('copy_details').setAttribute('disabled', g.bill_list_selection.length == 0);
        },
        'on_click' : function(ev) {
            var row = {}; var col = {}; var nobj = {};
            g.bill_list.node.treeBoxObject.getCellAt(ev.clientX,ev.clientY,row,col,nobj);
            if (row.value == -1) return;
            var treeItem = g.bill_list.node.contentView.getItemAtIndex(row.value);
            if (treeItem.nodeName != 'treeitem') return;
            var treeRow = treeItem.firstChild;
            var treeCell = treeRow.firstChild.nextSibling;
            if (g.check_map[ treeItem.getAttribute('retrieve_id') ] != (treeCell.getAttribute('value') == 'true')) {
                g.check_map[ treeItem.getAttribute('retrieve_id') ] = treeCell.getAttribute('value') == 'true';
                g.row_map[ treeItem.getAttribute('retrieve_id') ].row.my.checked = treeCell.getAttribute('value') == 'true';
                tally_all();
                distribute_payment();
            }
        },
        'on_sort' : function() {
            tally_all();
        },
        'on_checkbox_toggle' : function(toggle) {
            try {
                var retrieve_ids = g.bill_list.dump_retrieve_ids();
                for (var i = 0; i < retrieve_ids.length; i++) {
                    g.check_map[ retrieve_ids[i] ] = (toggle=='on');
                    g.row_map[ retrieve_ids[i] ].row.my.checked = (toggle=='on');
                }
                tally_all();
            } catch(E) {
                alert('error in on_checkbox_toggle(): ' + E);
            }
        },
        'retrieve_row' : function(params) {
            try {
                var id = params.retrieve_id;
                var row = params.row;

                function handle_props(row) {
                    try {
                        if ( row && row.my && row.my.mbts && Number( row.my.mbts.balance_owed() ) < 0 ) {
                            util.widgets.addProperty(params.treeitem_node.firstChild,'refundable');
                            util.widgets.addProperty(params.treeitem_node.firstChild.childNodes[ g.payment_pending_column_idx ],'refundable');
                        }
                        if ( row && row.my && row.my.circ && ! row.my.circ.checkin_time() ) {
                            $('circulating_hint').hidden = false;
                            util.widgets.addProperty(params.treeitem_node.firstChild,'circulating');
                            util.widgets.addProperty(params.treeitem_node.firstChild.childNodes[ g.title_column_idx ],'circulating');
                        }
                    } catch(E) {
                        g.error.sdump('D_WARN','Error setting list properties in bill2.js: ' + E);
                        alert('Error setting list properties in bill2.js: ' + E);
                    }
                }

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
                                if ( row.my.mbts && Number( row.my.mbts.balance_owed() ) < 0 ) {
                                    row.my.checked = false;
                                }
                                handle_props(row);
                                params.on_retrieve(row);
                            };
                            g.bill_map[ id ] = blob;
                            g.check_map[ id ] = row.my.checked;
                            tally_all();
                        } );
                    } else {
                        if (typeof params.on_retrieve == 'function') { 
                            handle_props(row);
                            params.on_retrieve(row); 
                        }
                    }
                } else {
                    if (typeof params.on_retrieve == 'function') { 
                        params.on_retrieve(row); 
                    }
                }

                return row;
            } catch(E) {
                alert('Error in bill2.js, retrieve_row(): ' + E);
            }
        }
    } );

    g.title_column_idx = util.functional.map_list( g.bill_list.columns, function(o) { return o.id; } ).indexOf( 'title' );
    g.payment_pending_column_idx = util.functional.map_list( g.bill_list.columns, function(o) { return o.id; } ).indexOf( 'payment_pending' );
    $('bill_list_actions').appendChild( g.bill_list.render_list_actions() );
    g.bill_list.set_list_actions();
}

function handle_add() {
    if(g.bill_list_selection.length > 1) {
        var msg = $("patronStrings").getFormattedString('staff.patron.bill_history.handle_add.message_plural', [g.bill_list_selection]);
    } else {
        var msg = $("patronStrings").getFormattedString('staff.patron.bill_history.handle_add.message_singular', [g.bill_list_selection]);
    }
        
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
        refresh();
        if (typeof window.xulG == 'object' && typeof window.xulG.refresh == 'function') window.xulG.refresh();
    }
}

function handle_void_all() {
    if(g.bill_list_selection.length > 1) {
        var msg = $("patronStrings").getFormattedString('staff.patron.bill_history.handle_void.message_plural', [g.bill_list_selection]);
    } else {
        var msg = $("patronStrings").getFormattedString('staff.patron.bill_history.handle_void.message_singular', [g.bill_list_selection]);
    }
        
    var r = g.error.yns_alert(msg,
        $("patronStrings").getString('staff.patron.bill_history.handle_void.title'),
        $("patronStrings").getString('staff.patron.bill_history.handle_void.btn_yes'),
        $("patronStrings").getString('staff.patron.bill_history.handle_void.btn_no'),null,
        $("patronStrings").getString('staff.patron.bill_history.handle_void.confirm_message'));
    if (r == 0) {
        for (var i = 0; i < g.bill_list_selection.length; i++) {
            void_all_billings( g.bill_list_selection[i] );
        }
        refresh();
        if (typeof window.xulG == 'object' && typeof window.xulG.refresh == 'function') window.xulG.refresh();
        if (typeof window.xulG == 'object' && typeof window.xulG.on_money_change == 'function') window.xulG.on_money_change();
    }
}

function handle_opac() {
    try {
        var ids = [];
        for (var i = 0; i < g.bill_list_selection.length; i++) {
            var my_mvr = g.bill_map[ g.bill_list_selection[i] ].record;
            var my_acp = g.bill_map[ g.bill_list_selection[i] ].copy;
            if (typeof my_mvr != 'undefined' && my_mvr != null) {
                ids.push( { 'barcode' : my_acp.barcode(), 'doc_id' : my_mvr.doc_id() } );
            }
        }
        JSAN.use('cat.util');
        cat.util.show_in_opac( ids );
    } catch(E) {
        alert('Error in bill2.js, handle_opac: ' + E);
    }
}

function handle_copy_details() {
    try {
        var ids = [];
        for (var i = 0; i < g.bill_list_selection.length; i++) {
            var my_acp = g.bill_map[ g.bill_list_selection[i] ].copy;
            if (typeof my_acp != 'undefined' && my_acp != null) {
                ids.push( my_acp.barcode() );
            }
        }
        JSAN.use('circ.util');
        circ.util.item_details_new( ids );
    } catch(E) {
        alert('Error in bill2.js, handle_opac: ' + E);
    }
}

function handle_details() {
    JSAN.use('util.window'); var win = new util.window();
    for (var i = 0; i < g.bill_list_selection.length; i++) {
        var my_xulG = win.open(
            urls.XUL_PATRON_BILL_DETAILS,
            'test_billdetails_' + g.bill_list_selection[i],
            'chrome,resizable',
            {
                'patron_id' : g.patron_id,
                'mbts_id' : g.bill_list_selection[i],
                'refresh' : function() {
                    refresh(); 
                    if (typeof window.xulG == 'object' && typeof window.xulG.refresh == 'function') window.xulG.refresh();
                }, 
                'new_tab' : xulG.new_tab,
                'url_prefix' : xulG.url_prefix
            }
        );
    }
}

function print_bills() {
    try {
        var template = 'bills_current';
        JSAN.use('patron.util');
        g.patron = patron.util.retrieve_fleshed_au_via_id(ses(),g.patron_id,null); 
        g.bill_list.print({ 
              'patron' : g.patron
            , 'printer_context' : 'receipt'
            , 'template' : template
            , 'data' : {
                  grand_total_owed:   $('tb_total_owed').value
                , grand_total_billed: $('total_billed').value
                , grand_total_paid:   $('tb_total_paid').value
            }
         });
    } catch(E) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.bill_history.print_bills.print_error'), E);
    }
}

function distribute_payment() {
    try {
        JSAN.use('util.money');
        var tb = $('payment');
        tb.value = util.money.cents_as_dollars( util.money.dollars_float_to_cents_integer( tb.value ) );
        tb.setAttribute('value', tb.value );
        var total = util.money.dollars_float_to_cents_integer( tb.value );
        if (total < 0) { tb.value = '0.00'; tb.setAttribute('value','0.00'); total = 0; }
        var retrieve_ids = g.bill_list.dump_retrieve_ids();
        for (var i = 0; i < retrieve_ids.length; i++) {
            var row_params = g.row_map[retrieve_ids[i]];
            if (g.check_map[retrieve_ids[i]]) { 
                var bill = g.bill_map[retrieve_ids[i]].transaction;
                var bo = util.money.dollars_float_to_cents_integer( bill.balance_owed() );
                if ( bo > total ) {
                    row_params.row.my.payment_pending = util.money.cents_as_dollars( total );
                    total = 0;
                } else {
                    row_params.row.my.payment_pending = util.money.cents_as_dollars( bo );
                    total = total - bo;
                }
            } else {
                row_params.row.my.payment_pending = '0.00';
            }
            g.bill_list.refresh_row(row_params);
        }
        tally_pending();
    } catch(E) {
        alert('Error in bill2.js, distribute_payment(): ' + E);
    }
}

function apply_payment() {
    try {
        var payment_blob = {};
        JSAN.use('util.window');
        var win = new util.window();
        switch($('payment_type').value) {
            case 'credit_card_payment' :
                g.data.temp = '';
                g.data.stash('temp');
                var my_xulG = win.open(
                    urls.XUL_PATRON_BILL_CC_INFO,
                    'billccinfo',
                    'chrome,resizable,modal',
                    {'patron_id': g.patron_id}
                );
                g.data.stash_retrieve();
                payment_blob = JSON2js( g.data.temp ); // FIXME - replace with my_xulG and update_modal_xulG, though it looks like we were using that before and moved away from it
            break;
            case 'check_payment' :
                g.data.temp = '';
                g.data.stash('temp');
                var my_xulG = win.open(
                    urls.XUL_PATRON_BILL_CHECK_INFO,
                    'billcheckinfo',
                    'chrome,resizable,modal'
                );
                g.data.stash_retrieve();
                payment_blob = JSON2js( g.data.temp );
            break;
        }
        if (
            (typeof payment_blob == 'undefined') || 
            payment_blob=='' || 
            payment_blob.cancelled=='true'
        ) { 
            alert( $('commonStrings').getString('common.cancelled') ); 
            return; 
        }
        payment_blob.userid = g.patron_id;
        payment_blob.note = payment_blob.note || '';
        //payment_blob.cash_drawer = 1; // FIXME: get new Config() to work
        payment_blob.payment_type = $('payment_type').value;
        var tally_blob = tally_pending();
        payment_blob.payments = tally_blob.payments;
        // Handle patron credit
        if ( payment_blob.payment_type == 'credit_payment' ) { // paying with patron credit
            if ( $('convert_change_to_credit').checked ) {
                // No need to convert credit into credit, handled automatically
                payment_blob.patron_credit = '0.00';
            } else {
                // Cashing out extra credit as change
                payment_blob.patron_credit = 0 - tally_blob.change;
            }
        } else if ( $('convert_change_to_credit').checked ) {
            // Saving change from a non-credit payment as patron credit on server
            payment_blob.patron_credit = tally_blob.change;
        } else {
            payment_blob.patron_credit = '0.00';
        }
        if ( payment_blob.payments.length == 0 && payment_blob.patron_credit == '0.00' ) {
            alert($("patronStrings").getString('staff.patron.bills.apply_payment.nothing_applied'));
            return;
        }
        if ( pay( payment_blob ) ) {

            $('payment').value = ''; $('payment').select(); $('payment').focus();
            refresh({'clear_voided_summary':true});
            if (typeof window.xulG == 'object' && typeof window.xulG.refresh == 'function') window.xulG.refresh();
            if (typeof window.xulG == 'object' && typeof window.xulG.on_money_change == 'function') window.xulG.on_money_change();
            if ( $('payment_type').value == 'credit_payment' || $('convert_change_to_credit').checked ) {
                refresh_patron();
            }
            try {
                if ( ! $('receipt_upon_payment').hasAttribute('checked') ) { return; } // Skip print attempt
                if ( ! $('receipt_upon_payment').getAttribute('checked') ) { return; } // Skip print attempt
                var no_print_prompting = g.data.hash.aous['circ.staff_client.do_not_auto_attempt_print'];
                if (no_print_prompting) {
                    if (no_print_prompting.indexOf( "Bill Pay" ) > -1) { return; } // Skip print attempt
                }
                g.data.stash_retrieve();
                var template = 'bill_payment';
                JSAN.use('patron.util'); JSAN.use('util.functional');
                var params = { 
                    'patron' : g.patron,
                    'lib' : g.data.hash.aou[ ses('ws_ou') ],
                    'staff' : ses('staff'),
                    'header' : g.data.print_list_templates[template].header,
                    'line_item' : g.data.print_list_templates[template].line_item,
                    'footer' : g.data.print_list_templates[template].footer,
                    'type' : g.data.print_list_templates[template].type,
                    'list' : util.functional.map_list(
                        payment_blob.payments,
                        function(o) {
                            return {
                                'bill_id' : o[0],
                                'payment' : o[1],
                                'last_billing_type' : g.bill_map[ o[0] ].transaction.last_billing_type(),
                                'last_billing_note' : g.bill_map[ o[0] ].transaction.last_billing_note(),
                                'title' : typeof g.bill_map[ o[0] ].record != 'undefined' ? g.bill_map[ o[0] ].record.title() : '', 
                                'barcode' : typeof g.bill_map[ o[0] ].copy != 'undefined' ? g.bill_map[ o[0] ].copy.barcode() : ''
                            };
                        }
                    ),
                    'data' : g.previous_summary,
                    'context' : g.data.print_list_templates[template].context,
                };
                g.error.sdump('D_DEBUG',js2JSON(params));
                if ($('printer_prompt').hasAttribute('checked')) {
                    if ($('printer_prompt').getAttribute('checked')) {
                            params.no_prompt = false;
                    } else {
                            params.no_prompt = true;
                    }
                } else {
                    params.no_prompt = true;
                }
                JSAN.use('util.print'); var print = new util.print('receipt');
                for (var i = 0; i < $('num_of_receipts').value; i++) {
                    print.tree_list( params );
                }
            } catch(E) {
                g.error.standard_unexpected_error_alert('bill receipt', E);
            }
        }
    } catch(E) {
        alert('Error in bill2.js, apply_payment(): ' + E);
    }
}

function pay(payment_blob) {
    try {
        var x = $('annotate_payment');
        if (x && x.checked && (! payment_blob.note)) {
            payment_blob.note = window.prompt(
                $("patronStrings").getString('staff.patron.bills.pay.annotate_payment'),
                '', 
                $("patronStrings").getString('staff.patron.bills.pay.annotate_payment.title')
            );
        }
        g.previous_summary = {
            original_balance : $('tb_total_owed').value,
            voided_balance : $('currently_voided').value,
            payment_received : $('payment').value,
            payment_applied : $('pending_payment').value,
            change_given : $('convert_change_to_credit').checked ? 0 : $('pending_change').value,
            credit_given : $('convert_change_to_credit').checked ? $('pending_change').value : 0,
            new_balance : util.money.cents_as_dollars( 
                util.money.dollars_float_to_cents_integer( $('tb_total_owed').value ) - 
                util.money.dollars_float_to_cents_integer( $('pending_payment').value )
            ),
            payment_type : $('payment_type').getAttribute('label'),
            note : payment_blob.note
        }
        var robj = g.network.simple_request( 'BILL_PAY', [ ses(), payment_blob, g.patron.last_xact_id() ]);

        try {
            g.error.work_log(
                $('circStrings').getFormattedString(
                    robj && robj.payments
                        ? 'staff.circ.work_log_payment_attempt.success.message'
                        : 'staff.circ.work_log_payment_attempt.failure.message',
                    [
                        ses('staff_usrname'), // 1 - Staff Username
                        g.patron.family_name(), // 2 - Patron Family
                        g.patron.card().barcode(), // 3 - Patron Barcode
                        g.previous_summary.original_balance, // 4 - Original Balance
                        g.previous_summary.voided_balance, // 5 - Voided Balance
                        g.previous_summary.payment_received, // 6 - Payment Received
                        g.previous_summary.payment_applied, // 7 - Payment Applied
                        g.previous_summary.change_given, // 8 - Change Given
                        g.previous_summary.credit_given, // 9 - Credit Given
                        g.previous_summary.new_balance, // 10 - New Balance
                        g.previous_summary.payment_type, // 11 - Payment Type
                        g.previous_summary.note, // 12 - Note
                        robj && robj.textcode ? robj.textcode : robj // 13 - API call result
                    ]
                ), {
                    'au_id' : g.patron.id(),
                    'au_family_name' : g.patron.family_name(),
                    'au_barcode' : g.patron.card().barcode()
                }
            );
        } catch(E) {
            alert('Error logging payment in bill2.js: ' + E);
        }

        if (typeof robj.ilsevent != 'undefined') {
            switch(robj.textcode) {
                case 'SUCCESS' : return true; break;
                case 'REFUND_EXCEEDS_DESK_PAYMENTS' : alert($("patronStrings").getFormattedString('staff.patron.bills.pay.refund_exceeds_desk_payment', [robj.desc])); return false; break;
                case 'INVALID_USER_XACT_ID' :
                    refresh(); default_focus();
                    alert($("patronStrings").getFormattedString('staff.patron.bills.pay.invalid_user_xact_id', [robj.desc])); return false; break;
                default: throw(robj); break;
            }
        }
        return true;
    } catch(E) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.bills.pay.payment_failed'),E);
        return false;
    }
}

function refresh(params) {
    try {
        if (params && params.clear_voided_summary) {
            g.data.voided_billings = []; g.data.stash('voided_billings');
        }
        refresh_patron();
        g.bill_list.clear();
        retrieve_mbts_for_list();
        tally_voided();
        distribute_payment(); 
    } catch(E) {
        alert('Error in bill2.js, refresh(): ' + E);
    }
}

function void_all_billings(mobts_id) {
    try {
        JSAN.use('util.functional');
        
        var mb_list = g.network.simple_request( 'FM_MB_RETRIEVE_VIA_MBTS_ID.authoritative', [ ses(), mobts_id ] );
        if (typeof mb_list.ilsevent != 'undefined') throw(mb_list);

        mb_list = util.functional.filter_list( mb_list, function(o) { return ! get_bool( o.voided() ) });

        if (mb_list.length == 0) { alert($("patronStrings").getString('staff.patron.bills.void_all_billings.all_voided')); return; }

        var sum = 0;
        for (var i = 0; i < mb_list.length; i++) sum += util.money.dollars_float_to_cents_integer( mb_list[i].amount() );
        sum = util.money.cents_as_dollars( sum );

        var msg = $("patronStrings").getFormattedString('staff.patron.bills.void_all_billings.void.message', [sum]);
        var r = g.error.yns_alert(msg,
            $("patronStrings").getString('staff.patron.bills.void_all_billings.void.title'),
            $("patronStrings").getString('staff.patron.bills.void_all_billings.void.yes'),
            $("patronStrings").getString('staff.patron.bills.void_all_billings.void.no'), null,
            $("patronStrings").getString('staff.patron.bills.void_all_billings.void.confirm_message'));
        if (r == 0) {
            var robj = g.network.simple_request('FM_MB_VOID',[ses()].concat(util.functional.map_list(mb_list,function(o){return o.id();})));
            if (robj.ilsevent) {
                switch(Number(robj.ilsevent)) {
                    case 5000 /* PERM_FAILURE */:
                        return;
                    break;
                    default: 
                        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.bills.void_all_billings.error_voiding_bills'),robj); 
                        return; 
                    break;
                }
            }

            g.data.stash_retrieve(); if (! g.data.voided_billings ) g.data.voided_billings = []; 
            for (var i = 0; i < mb_list.length; i++) {
                    g.data.voided_billings.push( mb_list[i] );
            }
            g.data.stash('voided_billings');
        }
    } catch(E) {
        try { g.error.standard_unexpected_error_alert('bill2.js, void_all_billings():',E); } catch(F) { alert(E); }
    }
}

function refresh_patron() {
    JSAN.use('patron.util'); JSAN.use('util.money');
    patron.util.retrieve_fleshed_au_via_id(ses(),g.patron_id,null,function(req) {
        var au_obj = req.getResultObject();
        if (typeof au_obj.ilsevent == 'undefined') {
            g.patron = au_obj;
            $('credit_forward').setAttribute('value',util.money.sanitize( g.patron.credit_forward_balance() ));
        }
    });
}
