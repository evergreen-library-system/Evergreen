function $(id) { return document.getElementById(id); }

function retrieve_patron() {
    g.patron_id = xul_param('patron_id');

    if (g.patron_id) {
        JSAN.use('patron.util'); 
        g.au_obj = patron.util.retrieve_fleshed_au_via_id( ses(), g.patron_id, null );
        
        $('patron_name').setAttribute('value', 
            patron.util.format_name( g.au_obj ) + ' : ' + g.au_obj.card().barcode() 
        );
    }

}

function retrieve_mbts() {
    g.network.simple_request('FM_MBTS_RETRIEVE.authoritative',[ses(),g.mbts_id],
        function(req) {
            try {
                g.mbts = req.getResultObject();
                $('mbts_id').value = g.mbts.id();
                $('mbts_xact_type').value = g.mbts.xact_type();
                $('mbts_xact_start').value = util.date.formatted_date( g.mbts.xact_start(), '%{localized}' );
                $('mbts_xact_finish').value = g.mbts.xact_finish() ? util.date.formatted_date( g.mbts.xact_finish(), '%{localized}' ) : '';
                $('mbts_total_owed').value = g.mbts.total_owed() ? util.money.sanitize( g.mbts.total_owed() ) : '';
                $('mbts_total_paid').value = g.mbts.total_paid() ? util.money.sanitize( g.mbts.total_paid() ) : '';
                $('mbts_balance_owed').value = g.mbts.balance_owed() ? util.money.sanitize( g.mbts.balance_owed() ) : '';

                switch(g.mbts.xact_type()) {
                    case 'circulation' : retrieve_circ(); break;
                    case 'grocery' : retrieve_grocery(); $('copy_summary_vbox').hidden = true; $('copy_summary_splitter').hidden = true; break;
                    case 'reservation' : retrieve_reservation(); $('copy_summary_vbox').hidden = true; $('copy_summary_splitter').hidden = true; break;
                    default: $('copy_summary_vbox').hidden = true; $('copy_summary_splitter').hidden = true; break;
                }

            } catch(E) {
                g.error.sdump('D_ERROR',E);
            }
        }
    );
}

function retrieve_grocery() {
    JSAN.use('util.widgets');
    g.network.simple_request('FM_MG_RETRIEVE', [ ses(), g.mbts_id ],
        function (req) {
            var r_mg = req.getResultObject();
            if (instanceOf(r_mg,mg)) {
                $('billing_location').value = g.data.hash.aou[ r_mg.billing_location() ].shortname() + ' : ' + g.data.hash.aou[ r_mg.billing_location() ].name();
            }
        }
    );
}

function retrieve_reservation() {
    JSAN.use('util.widgets');
    g.network.simple_request('FM_BRESV_RETRIEVE', [ ses(), g.mbts_id ],
        function (req) {
            var r_bresv = req.getResultObject();
            if (instanceOf(r_bresv,bresv)) {
                $('billing_location').value = g.data.hash.aou[ r_bresv.pickup_lib() ].shortname() + ' : ' + g.data.hash.aou[ r_bresv.pickup_lib() ].name();
            }
        }
    );
}

function retrieve_circ() {
    JSAN.use('util.widgets');
    g.network.simple_request('FM_CIRC_RETRIEVE_VIA_ID', [ ses(), g.mbts_id ],
        function (req) {
            var r_circ = req.getResultObject();
            if (instanceOf(r_circ,circ)) {

                $('title_label').hidden = false;
                $('checked_out_label').hidden = false;
                $('due_label').hidden = false;
                $('checked_in_label').hidden = false;
                $('checked_out').value = r_circ.xact_start() ? util.date.formatted_date( r_circ.xact_start(), '%{localized}' ) : '';
                $('checked_in').value = r_circ.checkin_time() ? util.date.formatted_date( r_circ.checkin_time(), '%{localized}' ) : '';
                $('due').value = r_circ.due_date() ? util.date.formatted_date( r_circ.due_date(), '%{localized}' ) : '';
                $('billing_location').value = g.data.hash.aou[ r_circ.circ_lib() ].shortname() + ' : ' + g.data.hash.aou[ r_circ.circ_lib() ].name();
                var r = '';
                if (get_bool( r_circ.desk_renewal() ) ) r += 'DESK ';
                if (get_bool(r_circ.opac_renewal() ) ) r += 'OPAC ';
                if (get_bool(r_circ.phone_renewal() ) ) r += 'PHONE ';
                $('renewal').value = r || 'No';

                var csb = $('copy_summary_vbox'); while (csb.firstChild) csb.removeChild(csb.lastChild);
                var copy_summary = document.createElement('iframe'); csb.appendChild(copy_summary);
                copy_summary.setAttribute('src',urls.XUL_COPY_SUMMARY); // + '?copy_id=' + r_circ.target_copy());
                copy_summary.setAttribute('flex','1');
                get_contentWindow(copy_summary).xulG = { 'circ' : r_circ, 'copy_id' : r_circ.target_copy(), 'new_tab' : xulG.new_tab, 'url_prefix' : xulG.url_prefix };

                g.network.simple_request(
                    'MODS_SLIM_RECORD_RETRIEVE_VIA_COPY.authoritative',
                    [ r_circ.target_copy() ],
                    function (rreq) {
                        var r_mvr = rreq.getResultObject();
                        if (instanceOf(r_mvr,mvr)) {
                            util.widgets.remove_children('title');
                            $('title').appendChild( document.createTextNode( String(r_mvr.title()).substr(0,50) ) );
                        } else {
                            g.network.simple_request(
                                'FM_ACP_RETRIEVE',
                                [ r_circ.target_copy() ],
                                function (rrreq) {
                                    var r_acp = rrreq.getResultObject();
                                    if (instanceOf(r_acp,acp)) {
                                        util.widgets.remove_children('title');
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
    g.payment_list = new util.list('payment_tree');

    g.bill_list.init( {
        'columns' : patron.util.mb_columns({}),
        'on_select' : function(ev) {
            JSAN.use('util.functional');
            g.bill_list_selection = util.functional.map_list(
                g.bill_list.retrieve_selection(),
                function(o) { return o.getAttribute('retrieve_id'); }
            );
            $('void').disabled = g.bill_list_selection.length == 0;
            $('edit_bill_note').disabled = g.bill_list_selection.length == 0;
        },
    } );

    $('bill_list_actions').appendChild( g.bill_list.render_list_actions() );
    g.bill_list.set_list_actions();

    g.payment_list.init( {
        'columns' : patron.util.mp_columns({}),
        'on_select' : function(ev) {
            JSAN.use('util.functional');
            g.payment_list_selection = util.functional.map_list(
                g.payment_list.retrieve_selection(),
                function(o) { return o.getAttribute('retrieve_id'); }
            );
            $('edit_payment_note').disabled = g.payment_list_selection.length == 0;
        },
    } );

    $('payment_list_actions').appendChild( g.payment_list.render_list_actions() );
    g.payment_list.set_list_actions();
}

function retrieve_mb() {
    g.mb_list = g.network.simple_request( 'FM_MB_RETRIEVE_VIA_MBTS_ID.authoritative', [ ses(), g.mbts_id ] );
    //g.error.sdump('D_DEBUG',g.error.pretty_print( js2JSON(g.mb_list) ));

    var mb_funcs = [];

    function gen_mb_func(i,r) {
        return function() {
            g.bill_list.append( { 'retrieve_id' : i, 'row' : { my : { 'mb' : r } } } );
        }
    }

    for (var i = 0; i < g.mb_list.length; i++) {
        mb_funcs.push( gen_mb_func(i,g.mb_list[i]) );
    }

    JSAN.use('util.exec');
    var mb_exec = new util.exec(4); mb_exec.chain(mb_funcs);
}

function retrieve_mp() {
    g.mp_list = g.network.simple_request( 'FM_MP_RETRIEVE_VIA_MBTS_ID.authoritative', [ ses(), g.mbts_id ]);
    //g.error.sdump('D_DEBUG',g.error.pretty_print( js2JSON(mp_list) ));

    var mp_funcs = [];

    function gen_mp_func(i,r) {
        return function() {
            g.payment_list.append( { 'retrieve_id' : i, 'row' : { my : { 'mp' : r } } } );
        }
    }

    for (var i = 0; i < g.mp_list.length; i++) {
        mp_funcs.push( gen_mp_func(i,g.mp_list[i]) );
    }

    JSAN.use('util.exec');
    var mp_exec = new util.exec(4); mp_exec.chain(mp_funcs);
}

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');

        JSAN.use('util.error'); g.error = new util.error();
        JSAN.use('util.network'); g.network = new util.network();
        JSAN.use('util.date');
        JSAN.use('util.money');
        JSAN.use('patron.util');
        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});

        g.error.sdump('D_TRACE','my_init() for bill_details.xul');

        g.mbts_id = xul_param('mbts_id');

        retrieve_patron();

        retrieve_mbts();

        init_lists();

        retrieve_mb();
        retrieve_mp();

        $('void').addEventListener(
            'command',
            handle_void,
            false
        );

        $('edit_bill_note').addEventListener(
            'command',
            handle_edit_bill_note,
            false
        );

        $('edit_payment_note').addEventListener(
            'command',
            handle_edit_payment_note,
            false
        );

    } catch(E) {
        try { g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.bill_details.my_init.error'),E); } catch(F) { alert(E); }
    }
}

function handle_edit_bill_note() {
    try {
        var mb_list = util.functional.map_list(g.bill_list_selection, function(o){return g.mb_list[o].id();}); 
        if (mb_list.length == 0) return;
        var new_note = window.prompt(
            $("patronStrings").getString('staff.patron.bill_details.handle_edit_bill_note.note_dialog.prompt'),
            util.functional.map_list(g.bill_list_selection, function(o){return g.mb_list[o].note();}).join(", "),           
            $("patronStrings").getString('staff.patron.bill_details.handle_edit_bill_note.note_dialog.title')
        );
        if (new_note) {
            var r = g.network.simple_request('FM_MB_NOTE_EDIT',[ ses(), new_note ].concat(mb_list));
            if (r == 1 /* success */) {
                g.bill_list.clear();
                retrieve_mb();
            } else {
                if (r.ilsevent != 5000 /* PERM_FAILURE */) {
                    alert( $("patronStrings").getString('staff.patron.bill_details.handle_edit_bill_note.failure') );
                }
            } 
        }
    } catch(E) {
        try { g.error.standard_unexpected_error_alert('bill_details.xul, handle_edit_bill_note:',E); } catch(F) { alert(E); }
    }
};

function handle_edit_payment_note() {
    try {
        var mp_list = util.functional.map_list(g.payment_list_selection, function(o){return g.mp_list[o].id();}); 
        if (mp_list.length == 0) return;
        var new_note = window.prompt(
            $("patronStrings").getString('staff.patron.bill_details.handle_edit_payment_note.note_dialog.prompt'),
            util.functional.map_list(g.payment_list_selection, function(o){return g.mp_list[o].note();}).join(", "),           
            $("patronStrings").getString('staff.patron.bill_details.handle_edit_payment_note.note_dialog.title')
        );
        if (new_note) {
            var r = g.network.simple_request('FM_MP_NOTE_EDIT',[ ses(), new_note ].concat(mp_list));
            if (r == 1 /* success */) {
                g.payment_list.clear();
                retrieve_mp();
            } else {
                if (r.ilsevent != 5000 /* PERM_FAILURE */) {
                    alert( $("patronStrings").getString('staff.patron.bill_details.handle_edit_payment_note.failure') );
                }
            } 
        }
    } catch(E) {
        try { g.error.standard_unexpected_error_alert('bill_details.xul, handle_edit_payment_note:',E); } catch(F) { alert(E); }
    }
};

function handle_void() {
    try {
        var mb_list = util.functional.map_list(g.bill_list_selection, function(o){return g.mb_list[o];}); 
        mb_list = util.functional.filter_list( mb_list, function(o) { return ! get_bool( o.voided() ) });

        if (mb_list.length == 0) { alert($("patronStrings").getString('staff.patron.bill_details.handle_void.voided_billings.alert')); return; }

        var sum = 0;
        for (var i = 0; i < mb_list.length; i++) sum += util.money.dollars_float_to_cents_integer( mb_list[i].amount() );
        sum = util.money.cents_as_dollars( sum );

        var msg = $("patronStrings").getFormattedString('staff.patron.bill_details.handle_void.confirm_void_billing', sum);
        var r = g.error.yns_alert(msg,
            $("patronStrings").getString('staff.patron.bill_details.handle_void.confirm_void_billing_title'),
            $("patronStrings").getString('staff.patron.bill_details.handle_void.confirm_void_billing_yes'),
            $("patronStrings").getString('staff.patron.bill_details.handle_void.confirm_void_billing_no'),null,
            $("patronStrings").getString('staff.patron.bill_details.handle_void.confirm_void_billing_confirm_message'));
        if (r == 0) {
            var robj = g.network.simple_request('FM_MB_VOID',[ses()].concat(util.functional.map_list(mb_list,function(o){return o.id();})));
            if (robj.ilsevent) {
                switch(Number(robj.ilsevent)) {
                    default: 
                        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.bill_details.handle_void.voiding_error'),robj); 
                        retrieve_mbts();
                        g.bill_list.clear();
                        retrieve_mb();
                        if (typeof window.xulG == 'object' && typeof window.xulG.refresh == 'function') { window.xulG.refresh(); }
                        return; 
                    break;
                }
            }

            g.data.stash_retrieve(); if (! g.data.voided_billings ) g.data.voided_billings = []; 
            for (var i = 0; i < mb_list.length; i++) {
                    g.data.voided_billings.push( mb_list[i] );
            }
            g.data.stash('voided_billings');
            retrieve_mbts();
            g.bill_list.clear();
            retrieve_mb();
            if (typeof window.xulG == 'object' && typeof window.xulG.refresh == 'function') { window.xulG.refresh(); }
        }

    } catch(E) {
        try { g.error.standard_unexpected_error_alert('bill_details.xul, handle_void:',E); } catch(F) { alert(E); }
    }
}

