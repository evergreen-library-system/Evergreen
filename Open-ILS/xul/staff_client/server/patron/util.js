dump('entering patron/util.js\n');

if (typeof patron == 'undefined') var patron = {};
patron.util = {};

patron.util.EXPORT_OK    = [ 
    'columns', 'mbts_columns', 'mb_columns', 'mp_columns',
    'retrieve_au_via_id', 'retrieve_fleshed_au_via_id', 'retrieve_fleshed_au_via_barcode', 'set_penalty_css', 'retrieve_name_via_id',
    'merge', 'ausp_columns', 'format_name', 'work_log_patron_edit'
];
patron.util.EXPORT_TAGS    = { ':all' : patron.util.EXPORT_OK };

patron.util.mbts_columns = function(modify,params) {

    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
    JSAN.use('util.money'); JSAN.use('util.date');

    var commonStrings = document.getElementById('commonStrings');

    var c = [
        {
            'persist' : 'hidden width ordinal', 'id' : 'mbts_id', 'label' : commonStrings.getString('staff.mbts_id_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return my.mbts.id(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'usr', 'label' : commonStrings.getString('staff.mbts_usr_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.mbts.usr() ? "Id = " + my.mbts.usr() : ""; }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'xact_type', 'label' : commonStrings.getString('staff.mbts_xact_type_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return my.mbts.xact_type(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'balance_owed', 'label' : commonStrings.getString('staff.mbts_balance_owed_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return util.money.sanitize( my.mbts.balance_owed() ); },
            'sort_type' : 'money'
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'total_owed', 'label' : commonStrings.getString('staff.mbts_total_owed_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return util.money.sanitize( my.mbts.total_owed() ); },
            'sort_type' : 'money'
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'total_paid', 'label' : commonStrings.getString('staff.mbts_total_paid_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return util.money.sanitize( my.mbts.total_paid() ); },
            'sort_type' : 'money'
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'last_billing_note', 'label' : commonStrings.getString('staff.mbts_last_billing_note_label'), 'flex' : 2,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.mbts.last_billing_note(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'last_billing_type', 'label' : commonStrings.getString('staff.mbts_last_billing_type_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.mbts.last_billing_type(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'last_billing_ts', 'label' : commonStrings.getString('staff.mbts_last_billing_timestamp_label'), 'flex' : 1,
            'sort_type' : 'date',
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.mbts.last_billing_ts(), "%{localized}" ); }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.mbts
                    ? my.mbts.last_billing_ts()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'last_payment_note', 'label' : commonStrings.getString('staff.mbts_last_payment_note_label'), 'flex' : 2,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.mbts.last_payment_note(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'last_payment_type', 'label' : commonStrings.getString('staff.mbts_last_payment_type_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.mbts.last_payment_type(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'last_payment_ts', 'label' : commonStrings.getString('staff.mbts_last_payment_timestamp_label'), 'flex' : 1,
            'sort_type' : 'date',
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.mbts.last_payment_ts(), "%{localized}" ); }
            ,'sort_value' : function(my) { return util.date.db_date2Date(
                    my.mbts
                    ? my.mbts.last_payment_ts()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'mbts_xact_start', 'label' : commonStrings.getString('staff.mbts_xact_start_label'), 'flex' : 1,
            'sort_type' : 'date',
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return my.mbts.xact_start() ? util.date.formatted_date( my.mbts.xact_start(), "%{localized}" ) : ""; }
            ,'sort_value' : function(my) { return util.date.db_date2Date(
                    my.mbts
                    ? my.mbts.xact_start()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'mbts_xact_finish', 'label' : commonStrings.getString('staff.mbts_xact_finish_label'), 'flex' : 1,
            'sort_type' : 'date',
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return my.mbts.xact_finish() ? util.date.formatted_date( my.mbts.xact_finish(), "%{localized}" ) : ""; }
            ,'sort_value' : function(my) { return util.date.db_date2Date(
                    my.mbts
                    ? my.mbts.xact_finish()
                    : null
                ).getTime();
            }
        },
    ];
    for (var i = 0; i < c.length; i++) {
        if (modify[ c[i].id ]) {
            for (var j in modify[ c[i].id ]) {
                c[i][j] = modify[ c[i].id ][j];
            }
        }
    }
    if (params) {
        if (params.just_these) {
            JSAN.use('util.functional');
            var new_c = [];
            for (var i = 0; i < params.just_these.length; i++) {
                var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
                new_c.push( function(y){ return y; }( x ) );
            }
            c = new_c;
        }
        if (params.except_these) {
            JSAN.use('util.functional');
            var new_c = [];
            for (var i = 0; i < c.length; i++) {
                var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
                if (!x) new_c.push(c[i]);
            }
            c = new_c;
        }
    }
    return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
}

patron.util.mb_columns = function(modify,params) {

    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
    JSAN.use('util.money'); JSAN.use('util.date');

    var commonStrings = document.getElementById('commonStrings');

    var c = [
        {
            'persist' : 'hidden width ordinal', 'id' : 'mb_id', 'label' : commonStrings.getString('staff.mb_id_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.mb.id(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'voided', 'label' : commonStrings.getString('staff.mb_voided_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return get_bool( my.mb.voided() ) ? "Yes" : "No"; }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'voider', 'label' : commonStrings.getString('staff.mb_voider_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.mb.voider() ? "Id = " + my.mb.voider() : ""; }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'void_time', 'label' : commonStrings.getString('staff.mb_void_time_label'), 'flex' : 1,
            'sort_type' : 'date',
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.mb.void_time(), "%{localized}" ); }
            ,'sort_value' : function(my) { return util.date.db_date2Date(
                    my.mbts
                    ? my.mb.void_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'amount', 'label' : commonStrings.getString('staff.mb_amount_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return util.money.sanitize( my.mb.amount() ); },
            'sort_type' : 'money'
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'billing_type', 'label' : commonStrings.getString('staff.mb_billing_type_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return my.mb.billing_type(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'billing_ts', 'label' : commonStrings.getString('staff.mb_billing_ts_label'), 'flex' : 1,
            'sort_type' : 'date',
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.mb.billing_ts(), "%{localized}" ); }
            ,'sort_value' : function(my) { return util.date.db_date2Date(
                    my.mb
                    ? my.mb.billing_ts()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'note', 'label' : commonStrings.getString('staff.mb_note_label'), 'flex' : 2,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return my.mb.note(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'xact', 'label' : commonStrings.getString('staff.mb_xact_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.mb.xact(); }
        },
    ];
    for (var i = 0; i < c.length; i++) {
        if (modify[ c[i].id ]) {
            for (var j in modify[ c[i].id ]) {
                c[i][j] = modify[ c[i].id ][j];
            }
        }
    }
    if (params) {
        if (params.just_these) {
            JSAN.use('util.functional');
            var new_c = [];
            for (var i = 0; i < params.just_these.length; i++) {
                var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
                new_c.push( function(y){ return y; }( x ) );
            }
            c = new_c;
        }
        if (params.except_these) {
            JSAN.use('util.functional');
            var new_c = [];
            for (var i = 0; i < c.length; i++) {
                var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
                if (!x) new_c.push(c[i]);
            }
            c = new_c;
        }

    }
    return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
}

patron.util.mp_columns = function(modify,params) {

    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
    JSAN.use('util.money'); JSAN.use('util.date'); JSAN.use('patron.util');

    var commonStrings = document.getElementById('commonStrings');

    var c = [
        {
            'persist' : 'hidden width ordinal', 'id' : 'mp_id', 'label' : commonStrings.getString('staff.mp_id_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.mp.id(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'mp_amount', 'label' : commonStrings.getString('staff.mp_amount_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return util.money.sanitize( my.mp.amount() ); },
            'sort_type' : 'money'
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'mp_payment_type', 'label' : commonStrings.getString('staff.mp_payment_type_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return my.mp.payment_type(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'mp_payment_ts', 'label' : commonStrings.getString('staff.mp_payment_timestamp_label'), 'flex' : 1,
            'sort_type' : 'date',
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.mp.payment_ts(), "%{localized}" ); }
            ,'sort_value' : function(my) { return util.date.db_date2Date(
                    my.mp
                    ? my.mp.payment_ts()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'mp_note', 'label' : commonStrings.getString('staff.mp_note_label'), 'flex' : 2,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return my.mp.note(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'mp_ws', 'label' : commonStrings.getString('staff.mp_cash_drawer_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return my.mp.cash_drawer().name(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'mp_staff', 'label' : commonStrings.getString('staff.mp_accepting_usr_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { var s = my.mp.accepting_usr(); if (s && typeof s != "object") s = patron.util.retrieve_fleshed_au_via_id(ses(),s,["card"]); return s.family_name() + " (" + s.card().barcode() + ") @ " + data.hash.aou[ s.home_ou() ].shortname(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'mp_xact', 'label' : commonStrings.getString('staff.mp_xact_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.mp.xact(); }
        },
    ];
    for (var i = 0; i < c.length; i++) {
        if (modify[ c[i].id ]) {
            for (var j in modify[ c[i].id ]) {
                c[i][j] = modify[ c[i].id ][j];
            }
        }
    }
    if (params) {
        if (params.just_these) {
            JSAN.use('util.functional');
            var new_c = [];
            for (var i = 0; i < params.just_these.length; i++) {
                var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
                new_c.push( function(y){ return y; }( x ) );
            }
            c = new_c;
        }
        if (params.except_these) {
            JSAN.use('util.functional');
            var new_c = [];
            for (var i = 0; i < c.length; i++) {
                var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
                if (!x) new_c.push(c[i]);
            }
            c = new_c;
        }

    }
    return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
}

patron.util.ausp_columns = function(modify,params) {

    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
    JSAN.use('util.functional');

    var commonStrings = document.getElementById('commonStrings');

    var c = [
        {
            'persist' : 'hidden width ordinal', 'id' : 'csp_id', 'label' : commonStrings.getString('staff.csp_id_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return typeof my.csp == 'object' ? my.csp.id() : my.csp; }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'csp_name', 'label' : commonStrings.getString('staff.csp_name_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return typeof my.csp == 'object' ? my.csp.name() : data.hash.csp[ my.csp ].name(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'csp_label', 'label' : commonStrings.getString('staff.csp_label_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { return typeof my.csp == 'object' ? my.csp.label() : data.hash.csp[ my.csp ].label(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'csp_block_list', 'label' : commonStrings.getString('staff.csp_block_list_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return typeof my.csp == 'object' ? my.csp.block_list() : data.hash.csp[ my.csp ].block_list(); }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'csp_block_circ', 'label' : commonStrings.getString('staff.csp_block_circ_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { 
                var my_csp = typeof my.csp == 'object' ? my.csp : data.hash.csp[ my.csp ];
                return String( my_csp.block_list() ).match('CIRC') ? commonStrings.getString('staff.csp_block_circ_yes') : commonStrings.getString('staff.csp_block_circ_no'); 
            }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'csp_block_renew', 'label' : commonStrings.getString('staff.csp_block_renew_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { 
                var my_csp = typeof my.csp == 'object' ? my.csp : data.hash.csp[ my.csp ];
                return String( my_csp.block_list() ).match('RENEW') ? commonStrings.getString('staff.csp_block_renew_yes') : commonStrings.getString('staff.csp_block_renew_no'); 

            }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'csp_block_hold', 'label' : commonStrings.getString('staff.csp_block_hold_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { 
                var my_csp = typeof my.csp == 'object' ? my.csp : data.hash.csp[ my.csp ];
                return String( my_csp.block_list() ).match('HOLD') ?  commonStrings.getString('staff.csp_block_hold_yes') : commonStrings.getString('staff.csp_block_hold_no'); 
            }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'ausp_id', 'label' : commonStrings.getString('staff.ausp_id_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.ausp ? my.ausp.id() : ''; }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'ausp_staff', 'label' : commonStrings.getString('staff.ausp_staff_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { 
                return my.ausp ? my.ausp.staff() : '';
            }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'ausp_set_date', 'label' : commonStrings.getString('staff.ausp_set_date_label'), 'flex' : 1,
            'sort_type' : 'date',
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { 
                return my.ausp ? util.date.formatted_date( my.ausp.set_date(), "%{localized}" ) : '';
            }
            ,'sort_value' : function(my) { return util.date.db_date2Date(
                    my.ausp
                    ? my.ausp.set_date()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'ausp_note', 'label' : commonStrings.getString('staff.ausp_note_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { 
                return my.ausp ? my.ausp.note() : '';
            }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'ausp_org_unit', 'label' : commonStrings.getString('staff.ausp_org_unit_label'), 'flex' : 1,
            'primary' : false, 'hidden' : false, 'editable' : false, 'render' : function(my) { 
                return my.ausp ? data.hash.aou[ my.ausp.org_unit() ].shortname() : '';
            }
        }
    ];
    for (var i = 0; i < c.length; i++) {
        if (modify[ c[i].id ]) {
            for (var j in modify[ c[i].id ]) {
                c[i][j] = modify[ c[i].id ][j];
            }
        }
    }
    if (params) {
        if (params.just_these) {
            var new_c = [];
            for (var i = 0; i < params.just_these.length; i++) {
                var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
                new_c.push( function(y){ return y; }( x ) );
            }
            c = new_c;
        }
        if (params.except_these) {
            var new_c = [];
            for (var i = 0; i < c.length; i++) {
                var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
                if (!x) new_c.push(c[i]);
            }
            c = new_c;
        }

    }
    return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
}


patron.util.columns = function(modify,params) {
    
    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});

    var commonStrings = document.getElementById('commonStrings');

    var c = [
        {
            'persist' : 'hidden width ordinal', 'id' : 'au_barcode', 'label' : commonStrings.getString('staff.card_barcode_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.card().barcode(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'usrname', 'label' : commonStrings.getString('staff.au_usrname_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.usrname(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'profile', 'label' : commonStrings.getString('staff.au_profile_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return data.hash.pgt[ my.au.profile() ].name(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'active', 'label' : commonStrings.getString('staff.au_active_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return get_bool( my.au.active() ) ? "Yes" : "No"; }
        },
        {
            'persist' : 'hidden width ordinal', 'id' : 'barred', 'label' : commonStrings.getString('staff.au_barred_label'), 'flex' : 1,
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return get_bool( my.au.barred() ) ? "Yes" : "No"; }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'au_id', 'label' : document.getElementById('commonStrings').getString('staff.au_id_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.id(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'prefix', 'label' : document.getElementById('commonStrings').getString('staff.au_name_prefix_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.prefix(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'family_name', 'label' : document.getElementById('commonStrings').getString('staff.au_family_name_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.family_name(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'first_given_name', 'label' : document.getElementById('commonStrings').getString('staff.au_first_given_name_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.first_given_name(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'second_given_name', 'label' : document.getElementById('commonStrings').getString('staff.au_second_given_name_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.second_given_name(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'suffix', 'label' : document.getElementById('commonStrings').getString('staff.au_name_suffix_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.suffix(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'au_alert_message', 'label' : commonStrings.getString('staff.au_alert_message_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.alert_message(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'claims_returned_count', 'label' : commonStrings.getString('staff.au_claims_returned_count_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.claims_returned_count(); },
            'sort_type' : 'number'
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'au_create_date', 'label' : commonStrings.getString('staff.au_create_date_label'), 'flex' : 1, 
            'sort_type' : 'date',
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.au.create_date(), "%{localized}" ); }
            ,'sort_value' : function(my) { return util.date.db_date2Date(
                    my.au
                    ? my.au.create_date()
                    : null
                ).getTime();
            }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'au_last_update_time', 'label' : commonStrings.getString('staff.au_last_update_time_label'), 'flex' : 1, 
            'sort_type' : 'date',
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.au.last_update_time(), "%{localized}" ); }
            ,'sort_value' : function(my) { return util.date.db_date2Date(
                    my.au
                    ? my.au.last_update_time()
                    : null
                ).getTime();
            }
        },

        { 
            'persist' : 'hidden width ordinal', 'id' : 'expire_date', 'label' : commonStrings.getString('staff.au_expire_date_label'), 'flex' : 1, 
            'sort_type' : 'date',
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.au.expire_date(), "%{localized_date}" ); }
            ,'sort_value' : function(my) { return util.date.db_date2Date(
                    my.au
                    ? my.au.expire_date()
                    : null
                ).getTime();
            }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'home_ou', 'label' : commonStrings.getString('staff.au_home_library_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return data.hash.aou[ my.au.home_ou() ].shortname(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'home_ou_fullname', 'label' : commonStrings.getString('staff.au_home_library_fullname_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return data.hash.aou[ my.au.home_ou() ].name(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'credit_forward_balance', 'label' : commonStrings.getString('staff.au_credit_forward_balance_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.credit_forward_balance(); },
            'sort_type' : 'money'
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'day_phone', 'label' : commonStrings.getString('staff.au_day_phone_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.day_phone(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'evening_phone', 'label' : commonStrings.getString('staff.au_evening_phone_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.evening_phone(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'other_phone', 'label' : commonStrings.getString('staff.au_other_phone_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.other_phone(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'email', 'label' : commonStrings.getString('staff.au_email_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.email(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'alias', 'label' : commonStrings.getString('staff.au_alias_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.alias(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'dob', 'label' : commonStrings.getString('staff.au_birth_date_label'), 'flex' : 1, 
            'sort_type' : 'date',
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.au.dob(), "%{localized_date}" ); }
            ,'sort_value' : function(my) { return util.date.db_date2Date(
                    my.au
                    ? my.au.dob()
                    : null
                ).getTime();
            }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'ident_type', 'label' : commonStrings.getString('staff.au_ident_type_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return data.hash.cit[ my.au.ident_type() ].name(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'ident_value', 'label' : commonStrings.getString('staff.au_ident_value_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.ident_value(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'ident_type2', 'label' : commonStrings.getString('staff.au_ident_type2_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return data.hash.cit[ my.au.ident_type2() ].name(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'ident_value2', 'label' : commonStrings.getString('staff.au_ident_value2_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.ident_value2(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'net_access_level', 'label' : commonStrings.getString('staff.au_net_access_level_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.net_access_level(); }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'master_account', 'label' : commonStrings.getString('staff.au_master_account_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return get_bool( my.au.master_account() ) ? "Yes" : "No"; }
        },
        { 
            'persist' : 'hidden width ordinal', 'id' : 'usrgroup', 'label' : commonStrings.getString('staff.au_group_id_label'), 'flex' : 1, 
            'primary' : false, 'hidden' : true, 'editable' : false, 'render' : function(my) { return my.au.usrgroup(); }
        },
    ];
    for (var i = 0; i < c.length; i++) {
        if (modify[ c[i].id ]) {
            for (var j in modify[ c[i].id ]) {
                c[i][j] = modify[ c[i].id ][j];
            }
        }
    }
    if (params) {
        if (params.just_these) {
            JSAN.use('util.functional');
            var new_c = [];
            for (var i = 0; i < params.just_these.length; i++) {
                var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
                new_c.push( function(y){ return y; }( x ) );
            }
            c = new_c;
        }
        if (params.except_these) {
            JSAN.use('util.functional');
            var new_c = [];
            for (var i = 0; i < c.length; i++) {
                var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
                if (!x) new_c.push(c[i]);
            }
            c = new_c;
        }

    }
    return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
}

patron.util.retrieve_au_via_id = function(session, id, f) {
    JSAN.use('util.network');
    var network = new util.network();
    var patron_obj = network.simple_request(
        'FM_AU_RETRIEVE_VIA_ID.authoritative',
        [ session, id ],
        f
    );
    return patron_obj;
}

patron.util.retrieve_name_via_id = function(session, id) {
    JSAN.use('util.network');
    var network = new util.network();
    var parts = network.simple_request(
        'BLOB_AU_PARTS_RETRIEVE',
        [ session, id, ['family_name', 'first_given_name', 'second_given_name', 'home_ou' ] ]
    );
    return parts;
}

patron.util.retrieve_fleshed_au_via_id = function(session, id, fields, func) {
    JSAN.use('util.network');
    var network = new util.network();
    var patron_obj = network.simple_request(
        'FM_AU_FLESHED_RETRIEVE_VIA_ID.authoritative',
        [ session, id, fields ],
        typeof func == 'function' ? func : null
    );
    if (typeof func != 'function') {
        if (!fields) { patron.util.set_penalty_css(patron_obj); }
        return patron_obj;
    }
}

patron.util.retrieve_fleshed_au_via_barcode = function(session, id) {
    JSAN.use('util.network');
    var network = new util.network();
    var patron_obj = network.simple_request(
        'FM_AU_RETRIEVE_VIA_BARCODE.authoritative',
        [ session, id ]
    );
    if (typeof patron_obj.ilsevent == 'undefined') patron.util.set_penalty_css(patron_obj);
    return patron_obj;
}

var TIME = { minute : 60, hour : 60*60, day : 60*60*24, year : 60*60*24*365 };

patron.util.set_penalty_css = function(patron) {
    try {
        removeCSSClass(document.documentElement,'PATRON_HAS_BILLS');
        removeCSSClass(document.documentElement,'PATRON_HAS_OVERDUES');
        removeCSSClass(document.documentElement,'PATRON_HAS_NOTES');
        removeCSSClass(document.documentElement,'PATRON_EXCEEDS_CHECKOUT_COUNT');
        removeCSSClass(document.documentElement,'PATRON_EXCEEDS_OVERDUE_COUNT');
        removeCSSClass(document.documentElement,'PATRON_EXCEEDS_FINES');
        removeCSSClass(document.documentElement,'NO_PENALTIES');
        removeCSSClass(document.documentElement,'ONE_PENALTY');
        removeCSSClass(document.documentElement,'MULTIPLE_PENALTIES');
        removeCSSClass(document.documentElement,'INVALID_PATRON_EMAIL_ADDRESS');
        removeCSSClass(document.documentElement,'INVALID_PATRON_DAY_PHONE');
        removeCSSClass(document.documentElement,'INVALID_PATRON_EVENING_PHONE');
        removeCSSClass(document.documentElement,'INVALID_PATRON_OTHER_PHONE');
        removeCSSClass(document.documentElement,'PATRON_HAS_ALERT');
        removeCSSClass(document.documentElement,'PATRON_BARRED');
        removeCSSClass(document.documentElement,'PATRON_INACTIVE');
        removeCSSClass(document.documentElement,'PATRON_EXPIRED');
        removeCSSClass(document.documentElement,'PATRON_HAS_INVALID_DOB');
        removeCSSClass(document.documentElement,'PATRON_HAS_INVALID_ADDRESS');
        removeCSSClass(document.documentElement,'PATRON_AGE_GE_65');
        removeCSSClass(document.documentElement,'PATRON_AGE_LT_65');
        removeCSSClass(document.documentElement,'PATRON_AGE_GE_24');
        removeCSSClass(document.documentElement,'PATRON_AGE_LT_24');
        removeCSSClass(document.documentElement,'PATRON_AGE_GE_21');
        removeCSSClass(document.documentElement,'PATRON_AGE_LT_21');
        removeCSSClass(document.documentElement,'PATRON_AGE_GE_18');
        removeCSSClass(document.documentElement,'PATRON_AGE_LT_18');
        removeCSSClass(document.documentElement,'PATRON_AGE_GE_13');
        removeCSSClass(document.documentElement,'PATRON_AGE_LT_13');
        removeCSSClass(document.documentElement,'PATRON_NET_ACCESS_1');
        removeCSSClass(document.documentElement,'PATRON_NET_ACCESS_2');
        removeCSSClass(document.documentElement,'PATRON_NET_ACCESS_3');

        JSAN.use('util.network'); var net = new util.network();
        net.simple_request('FM_MOUS_RETRIEVE.authoritative',[ ses(), patron.id() ], function(req) {
            var summary = req.getResultObject();
            if (summary && summary.balance_owed() > 0) addCSSClass(document.documentElement,'PATRON_HAS_BILLS');
        });
        net.simple_request('FM_CIRC_COUNT_RETRIEVE_VIA_USER.authoritative',[ ses(), patron.id() ], function(req) {
            try {
                var co = req.getResultObject();
                if (co.overdue > 0 || co.long_overdue > 0) addCSSClass(document.documentElement,'PATRON_HAS_OVERDUES');
            } catch(E) {
                alert(E);
            }
        });
        net.simple_request('FM_AUN_RETRIEVE_ALL.authoritative',[ ses(), { 'patronid' : patron.id() } ], function(req) {
            var notes = req.getResultObject();
            if (notes.length > 0) addCSSClass(document.documentElement,'PATRON_HAS_NOTES');
        });

        /*
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
        data.last_patron = patron.id(); data.stash('last_patron');
        */

        var penalties = patron.standing_penalties() || [];
        penalties = penalties.filter(
            function(p) {
                return (!(p.isdeleted() || p.stop_date()));
            }
        );
        for (var i = 0; i < penalties.length; i++) {
            /* this comes from /opac/common/js/utils.js */
            addCSSClass(document.documentElement,penalties[i].standing_penalty().name());
            if (penalties[i].standing_penalty().id() >= 100) {
                addCSSClass(document.documentElement,'PATRON_HAS_CUSTOM_PENALTY');
            }
            if (get_bool( penalties[i].standing_penalty().staff_alert() )) {
                addCSSClass(document.documentElement,'PATRON_HAS_STAFF_ALERT');
            }
            var block_list = penalties[i].standing_penalty().block_list();
            if (block_list) {
                addCSSClass(document.documentElement,'PATRON_HAS_BLOCK');
                // TODO: futureproofing, split and loop on block_list to produce these classnames
                if (block_list.match('CIRC')) {
                    addCSSClass(document.documentElement,'PATRON_HAS_CIRC_BLOCK');
                }
                if (block_list.match('RENEW')) {
                    addCSSClass(document.documentElement,'PATRON_HAS_RENEW_BLOCK');
                }
                if (block_list.match('HOLD')) {
                    addCSSClass(document.documentElement,'PATRON_HAS_HOLD_BLOCK');
                }
                if (block_list.match('CAPTURE')) {
                    addCSSClass(document.documentElement,'PATRON_HAS_CAPTURE_BLOCK');
                }
                if (block_list.match('FULFILL')) {
                    addCSSClass(document.documentElement,'PATRON_HAS_FULFILL_BLOCK');
                }
            }
        }

        switch(penalties.length) {
            case 0: addCSSClass(document.documentElement,'NO_PENALTIES'); break;
            case 1: addCSSClass(document.documentElement,'ONE_PENALTY'); break;
            default: addCSSClass(document.documentElement,'MULTIPLE_PENALTIES'); break;
        }

        if (patron.alert_message()) {
            addCSSClass(document.documentElement,'PATRON_HAS_ALERT');
        }

        if (get_bool( patron.barred() )) {
            addCSSClass(document.documentElement,'PATRON_BARRED');
        }

        if (!get_bool( patron.active() )) {
            addCSSClass(document.documentElement,'PATRON_INACTIVE');
        }

        try { addCSSClass(document.documentElement,'PATRON_NET_ACCESS_' + patron.net_access_level()); } catch(E) {}

        var now = new Date();
        now = now.getTime()/1000;

        var expire_parts = patron.expire_date().substr(0,10).split('-');
        expire_parts[1] = expire_parts[1] - 1;

        var expire = new Date();
        expire.setFullYear(expire_parts[0], expire_parts[1], expire_parts[2]);
        expire = expire.getTime()/1000

        if (expire < now) addCSSClass(document.documentElement,'PATRON_EXPIRED');

        if (patron.dob()) {
            var age_parts = patron.dob().substr(0,10).split('-');
            age_parts[1] = age_parts[1] - 1;

            var born = new Date();
            born.setFullYear(age_parts[0], age_parts[1], age_parts[2]);
            born = born.getTime()/1000

            var patron_age = now - born;
            var years_old = Number(patron_age / TIME.year);

            addCSSClass(document.documentElement,'PATRON_AGE_IS_' + years_old);

            if ( years_old >= 65 ) addCSSClass(document.documentElement,'PATRON_AGE_GE_65');
            if ( years_old < 65 )  addCSSClass(document.documentElement,'PATRON_AGE_LT_65');
        
            if ( years_old >= 24 ) addCSSClass(document.documentElement,'PATRON_AGE_GE_24');
            if ( years_old < 24 )  addCSSClass(document.documentElement,'PATRON_AGE_LT_24');
            
            if ( years_old >= 21 ) addCSSClass(document.documentElement,'PATRON_AGE_GE_21');
            if ( years_old < 21 )  addCSSClass(document.documentElement,'PATRON_AGE_LT_21');
        
            if ( years_old >= 18 ) addCSSClass(document.documentElement,'PATRON_AGE_GE_18');
            if ( years_old < 18 )  addCSSClass(document.documentElement,'PATRON_AGE_LT_18');
        
            if ( years_old >= 13 ) addCSSClass(document.documentElement,'PATRON_AGE_GE_13');
            if ( years_old < 13 )  addCSSClass(document.documentElement,'PATRON_AGE_LT_13');
        } else {
            addCSSClass(document.documentElement,'PATRON_HAS_INVALID_DOB');
        }

        if ( get_bool( patron.juvenile() ) ) addCSSClass(document.documentElement,'PATRON_JUVENILE');
        else removeCSSClass(document.documentElement,'PATRON_JUVENILE');

        if (patron.mailing_address() && typeof patron.mailing_address() == 'object') {
            if (!get_bool(patron.mailing_address().valid())) {
                addCSSClass(document.documentElement,'PATRON_HAS_INVALID_ADDRESS');
            }
        }
        if (patron.billing_address() && typeof patron.billing_address() == 'object') {
            if (!get_bool(patron.billing_address().valid())) {
                addCSSClass(document.documentElement,'PATRON_HAS_INVALID_ADDRESS');
            }
        }

    } catch(E) {
        dump('patron.util.set_penalty_css: ' + E + '\n');
        alert('patron.util.set_penalty_css: ' + E + '\n');
    }
}

patron.util.merge = function(record_ids) {
    var error;
    try {
        JSAN.use('util.error'); error = new util.error();
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
        var horizontal_interface = String( data.hash.aous['ui.circ.patron_summary.horizontal'] ) == 'true';
        var top_xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" >';
        top_xml += '<description>' + $("patronStrings").getString('staff.patron.usr_buckets.merge_records.merge_lead') + '</description>';
        top_xml += '<hbox>';
        top_xml += '<button id="lead" disabled="true" label="'
                + $("patronStrings").getString('staff.patron.usr_buckets.merge_records.button.label') + '" name="fancy_submit"/>';
        top_xml += '<button label="' + $("patronStrings").getString('staff.patron.usr_buckets.merge_records.cancel_button.label') +'" accesskey="'
                + $("patronStrings").getString('staff.patron.usr_buckets.merge_records.cancel_button.accesskey') +'" name="fancy_cancel"/></hbox></vbox>';

        var xml = '<form xmlns="http://www.w3.org/1999/xhtml">';
        xml += '<table>';

        function table_cell_with_lead_button(id) {
            var xml = '';
            xml += '<td><input value="' + $("patronStrings").getString('staff.patron.usr_buckets.merge_records.lead')
            xml += '" id="record_' + id + '" type="radio" name="lead"';
            xml += ' onclick="' + "try { var x = $('lead'); x.setAttribute('value',";
            xml += id + '); x.disabled = false; } catch(E) { alert(E); }">';
            xml += '</input>' + $("patronStrings").getFormattedString('staff.patron.usr_buckets.merge_records.lead_record_number',[id]) + '</td>';
            return xml;
        }

        var iframe_css;
        if (!horizontal_interface) {
            xml += '<tr valign="top">';
            for (var i = 0; i < record_ids.length; i++) {
                xml += table_cell_with_lead_button( record_ids[i] );
            }
            xml += '</tr><tr valign="top">';
            iframe_css = 'min-height: 1000px; min-width: 300px;';
        } else {
            iframe_css = 'min-height: 200px; min-width: 1000px;';
        }
        for (var i = 0; i < record_ids.length; i++) {
            if (horizontal_interface) {
                xml += '<tr valign="top">' + table_cell_with_lead_button( record_ids[i] );
            }
            xml += '<td nowrap="nowrap"><iframe style="' + iframe_css + '" flex="1" src="' + urls.XUL_PATRON_SUMMARY; 
            xml += '?id=' + record_ids[i] + '&amp;show_name=1" oils_force_external="true"/></td>';
            if (horizontal_interface) {
                xml += '</tr>';
            }
        }
        if (!horizontal_interface) {
            xml += '</tr>';
        }
        xml += '</table></form>';
        JSAN.use('util.window'); var win = new util.window();
        var fancy_prompt_data = win.open(
            urls.XUL_FANCY_PROMPT,
            'fancy_prompt', 'chrome,resizable,modal,width=1000,height=700',
            {
                'top_xml' : top_xml, 'xml' : xml, 'title' : $("patronStrings").getString('staff.patron.usr_buckets.merge_records.fancy_prompt_title')
            }
        );

        if (typeof fancy_prompt_data.fancy_status == 'undefined' || fancy_prompt_data.fancy_status == 'incomplete') {
            alert($("patronStrings").getString('staff.patron.usr_buckets.merge_records.fancy_prompt.alert'));
            return false;
        }

        JSAN.use('util.functional'); JSAN.use('util.network'); var network = new util.network();
        var robj = network.simple_request('FM_AU_MERGE', 
            [ 
                ses(), 
                fancy_prompt_data.lead,
                util.functional.filter_list( record_ids,
                    function(o) {
                        return o != fancy_prompt_data.lead;
                    }
                )
            ]
        );
        if (Number(robj) != 1) { throw(robj); }
        return fancy_prompt_data.lead;
    } catch(E) {
        dump('patron.util.merge: ' + js2JSON(E) + '\n');
        try { error.standard_unexpected_error_alert('Error in patron.util.merge',E); } catch(F) { alert('patron.util.merge: ' + E + '\n'); }
        return false;
    }
}

patron.util.format_name = function(patron_obj) {
    var patron_name = ( patron_obj.prefix() ? patron_obj.prefix() + ' ' : '') +
        patron_obj.family_name() + ', ' +
        patron_obj.first_given_name() + ' ' +
        ( patron_obj.second_given_name() ? patron_obj.second_given_name() + ' ' : '' ) +
        ( patron_obj.suffix() ? patron_obj.suffix() : ''); 
    return patron_name;
}

patron.util.work_log_patron_edit = function(p) {
    var error;
    try {
        JSAN.use('util.error'); error = new util.error();
        error.work_log(
            document.getElementById('patronStrings').getFormattedString(
                'staff.circ.work_log_patron_edit.message',
                [
                    ses('staff_usrname'),
                    p.family_name(),
                    p.card().barcode()
                ]
            ), {
                'au_id' : p.id(),
                'au_family_name' : p.family_name(),
                'au_barcode' : p.card().barcode()
            }
        );
    } catch(E) {
        error.sdump('D_ERROR','Error with work_logging in menu.js, cmd_patron_register:' + E);
    }
}


dump('exiting patron/util.js\n');
