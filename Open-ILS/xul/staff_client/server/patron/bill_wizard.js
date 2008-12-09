function $(id) { return document.getElementById(id); }

function retrieve_mbts() {
    g.network.simple_request('FM_MBTS_RETRIEVE.authoritative',[ses(),g.mbts_id],
        function(req) {
            try {
                g.mbts = req.getResultObject();
                $('mbts_id').value = g.mbts.id();
                $('mbts_xact_type').value = g.mbts.xact_type();
                $('mbts_xact_start').value = g.mbts.xact_start().toString().substr(0,19);
                $('mbts_xact_finish').value = g.mbts.xact_finish() ? g.mbts.xact_finish().toString().substr(0,19) : '';
                $('mbts_total_owed').value = g.mbts.total_owed() ? util.money.sanitize( g.mbts.total_owed() ) : '';
                $('mbts_total_paid').value = g.mbts.total_paid() ? util.money.sanitize( g.mbts.total_paid() ) : '';
                $('mbts_balance_owed').value = g.mbts.balance_owed() ? util.money.sanitize( g.mbts.balance_owed() ) : '';
                $('xact_type').value = g.mbts.xact_type(); $('xact_type').disabled = true;
            } catch(E) {
                g.error.sdump('D_ERROR',E);
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
                $('checked_out').value = r_circ.xact_start() ? r_circ.xact_start().toString().substr(0,10) : '';
                $('checked_in').value = r_circ.checkin_time() ? r_circ.checkin_time().toString().substr(0,10) : '';
                $('due').value = r_circ.due_date() ? r_circ.due_date().toString().substr(0,10) : '';

                g.network.simple_request(
                    'MODS_SLIM_RECORD_RETRIEVE_VIA_COPY.authoritative',
                    [ r_circ.target_copy() ],
                    function (rreq) {
                        var r_mvr = rreq.getResultObject();
                        if (instanceOf(r_mvr,mvr)) {
                            util.widgets.remove_children('title');
                            $('title').appendChild( document.createTextNode( r_mvr.title() ) );
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

function retrieve_patron() {
    g.patron_id = xul_param('patron_id',{'modal_xulG':true});

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

function patron_bill_init() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); g.error = new util.error();
        g.error.sdump('D_TRACE','my_init() for patron_display.xul');
        g.OpenILS = {}; JSAN.use('OpenILS.data'); g.OpenILS.data = new OpenILS.data();
        g.OpenILS.data.init({'via':'stash'});
        JSAN.use('util.network'); g.network = new util.network();
        JSAN.use('util.date');
        JSAN.use('util.money');
        JSAN.use('util.widgets');
        JSAN.use('util.functional');
        var billing_list = util.functional.filter_list( g.OpenILS.data.list.cbt, function (x) { x.id() < 100 } );
        var ml = util.widgets.make_menulist(
            util.functional.map_list(
                billing_list.sort( function(a,b) { if (a.name()>b.name()) return 1; if (a.name()<b.name()) return -1; return 0; } ), //g.OpenILS.data.list.billing_type.sort(),
                function(obj) { return [ obj.name(), obj.id() ]; } //function(obj) { return [ obj, obj ]; }
            ),
            billing_list.sort( function(a,b) { if (a.name()>b.name()) return 1; if (a.name()<b.name()) return -1; return 0; } )[0]
        );
        ml.setAttribute('id','billing_type');
        document.getElementById('menu_placeholder').appendChild(ml);
        ml.addEventListener(
            'command',
            function() {
                $('bill_amount').value = billing_list[ ml.value ].default_price();
            },
            false
        ); 

        retrieve_patron();

        $('billing_location').setAttribute('value', g.OpenILS.data.hash.aou[ g.OpenILS.data.list.au[0].ws_ou() ].name() );

        $('bill_amount').value = billing_list[ ml.value ].default_price();
        $('bill_amount').select(); $('bill_amount').focus();

        if (xul_param('xact_id',{'modal_xulG':true})) { 
            g.mbts_id = xul_param('xact_id',{'modal_xulG':true});
            $('summary').hidden = false; 
            retrieve_mbts();
            retrieve_circ();
        }

    } catch(E) {
        var err_msg = $("commonStrings").getFormattedString('common.exception', ['patron/bill_wizard.xul', E]);
        try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
        alert(err_msg);
    }

}

function patron_bill_finish() {
    try {
        var xact_id = xul_param('xact_id',{'modal_xulG':true});
        if (!xact_id) {
                var grocery = new mg();
                    grocery.isnew('1');
                    grocery.billing_location( g.OpenILS.data.list.au[0].ws_ou() );
                    grocery.usr( g.au_obj.id() );
                    grocery.note( $('bill_note').value );
                xact_id = g.network.request(
                    api.FM_MG_CREATE.app,
                    api.FM_MG_CREATE.method,
                    [ ses(), grocery ]
                );
        }
        if (typeof xact_id.ilsevent == 'undefined') {
            JSAN.use('util.money');
            var billing = new mb();
                billing.isnew('1');
                billing.note( $('bill_note').value );
                billing.xact( xact_id );
                billing.amount( util.money.sanitize( $('bill_amount').value ) );
                billing.btype( $('billing_type').value );
                billing.billing_type( g.OpenILS.data.hash.cbt[$('billing_type').value].name() );
            var mb_id = g.network.request(
                api.FM_MB_CREATE.app,
                api.FM_MB_CREATE.method,
                [ ses(), billing ]
            );
            if (typeof mb_id.ilsevent != 'undefined') throw(mb_id);
            //alert($('patronStrings').getString('staff.patron.bill_wizard.patron_bill_finish.billing_added'));
        } else {
            throw(xact_id);
        }
    } catch(E) {
        g.error.standard_unexpected_error_alert('bill_wizard',E);
    }
}


