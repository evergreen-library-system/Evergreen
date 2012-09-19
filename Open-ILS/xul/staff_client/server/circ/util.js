dump('entering circ/util.js\n');
// vim:noet:sw=4:ts=4:

if (typeof circ == 'undefined') { var circ = {}; }
circ.util = {};

circ.util.EXPORT_OK    = [
    'offline_checkout_columns', 'offline_checkin_columns', 'offline_renew_columns', 'offline_inhouse_use_columns',
    'columns', 'hold_columns', 'checkin_via_barcode', 'std_map_row_to_columns',
    'show_last_few_circs', 'abort_transits', 'transit_columns', 'work_log_columns', 'renew_via_barcode', 'backdate_post_checkin', 'batch_hold_update'
];
circ.util.EXPORT_TAGS    = { ':all' : circ.util.EXPORT_OK };

circ.util.abort_transits = function(selection_list) {
    var obj = {};
    JSAN.use('util.error'); obj.error = new util.error();
    JSAN.use('util.network'); obj.network = new util.network();
    JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
    JSAN.use('util.functional');
    var copies = util.functional.map_list( selection_list, function(o){return o.copy_id;}).join(', ');
    var msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.abort_transits.confirm', [copies]);
    var r = obj.error.yns_alert(
        msg,
        document.getElementById('circStrings').getString('staff.circ.utils.abort_transits.title'),
        document.getElementById('circStrings').getString('staff.circ.utils.yes'),
        document.getElementById('circStrings').getString('staff.circ.utils.no'),
        null,
        document.getElementById('circStrings').getString('staff.circ.confirm')
    );
    if (r == 0) {
        try {
            for (var i = 0; i < selection_list.length; i++) {
                var copy_id = selection_list[i].copy_id;
                var robj = obj.network.simple_request('FM_ATC_VOID',[ ses(), { 'copyid' : copy_id } ]);
                if (typeof robj.ilsevent != 'undefined') {
                    switch(Number(robj.ilsevent)) {
                        case 1225 /* TRANSIT_ABORT_NOT_ALLOWED */ :
                            alert(document.getElementById('circString').getFormattedString('staff.circ.utils.abort_transits.not_allowed', [copy_id]) + '\n' + robj.desc);
                        break;
                        case 1504 /* ACTION_TRANSIT_COPY_NOT_FOUND */ :
                            alert(document.getElementById('circString').getString('staff.circ.utils.abort_transits.not_found'));
                        break;
                        case 5000 /* PERM_FAILURE */ :
                        break;
                        default:
                            throw(robj);
                        break;
                    }
                }
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert(document.getElementById('circString').getString('staff.circ.utils.abort_transits.unexpected_error'),E);
        }
    }
};

circ.util.show_copy_details = function(copy_id) {
    var obj = {};
    JSAN.use('util.error'); obj.error = new util.error();
    JSAN.use('util.window'); obj.win = new util.window();
    JSAN.use('util.network'); obj.network = new util.network();
    JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

    if (typeof copy_id == 'object' && copy_id != null) copy_id = copy_id.id();

    try {
        var url = xulG.url_prefix('XUL_COPY_DETAILS'); // + '?copy_id=' + copy_id;
        var my_xulG = obj.win.open( url, 'show_copy_details', 'chrome,resizable,modal', { 'copy_id' : copy_id, 'new_tab' : xulG.new_tab, 'url_prefix' : xulG.url_prefix } );

        if (typeof my_xulG.retrieve_these_patrons == 'undefined') return;
        var patrons = my_xulG.retrieve_these_patrons;
        for (var j = 0; j < patrons.length; j++) {
            if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') {
                try {
                    window.xulG.new_patron_tab( {}, { 'id' : patrons[j] } );
                } catch(E) {
                    obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.utils.retrieve_patron.failure'), E);
                }
            }
        }

    } catch(E) {
        obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.utils.retrieve_copy.failure'),E);
    }
};

circ.util.item_details_new = function(barcodes) {
    try {
        var content_params = {
            'from_item_details_new': true,
            'barcodes': barcodes
        };
        xulG.new_tab(urls.XUL_COPY_STATUS, {}, content_params);
    } catch(E) {
        JSAN.use('util.error');
        (new util.error()).standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.utils.retrieve_copy.failure'),E);
    }
};

circ.util.backdate_post_checkin = function(circ_ids) {
    var obj = {};
    JSAN.use('util.error'); obj.error = new util.error();
    JSAN.use('util.window'); obj.win = new util.window();
    JSAN.use('util.network'); obj.network = new util.network();
    JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
    JSAN.use('util.sound'); obj.sound = new util.sound();

    var circStrings = document.getElementById('circStrings');

    dojo.forEach(
        circ_ids,
        function(element,idx,list) {
            if (typeof element == 'object' && element != null) list[idx] = element.id();
        }
    );

    try {
        var url = xulG.url_prefix('XUL_BACKDATE');
        var my_xulG = obj.win.open( url, 'backdate_post_checkin', 'chrome,resizable,modal', { 'circ_ids' : circ_ids } );

        return my_xulG;

    } catch(E) {
        obj.error.standard_unexpected_error_alert(circStrings.getString('staff.circ.utils.retrieve_copy.failure'),E);
    }
};


circ.util.show_last_few_circs = function(selection_list) {
    var obj = {};
    JSAN.use('util.error'); obj.error = new util.error();
    JSAN.use('util.window'); obj.win = new util.window();
    JSAN.use('util.network'); obj.network = new util.network();
    JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

    for (var i = 0; i < selection_list.length; i++) {
        try {
            if (typeof selection_list[i].copy_id == 'undefined' || selection_list[i].copy_id == null) continue;
            var url = xulG.url_prefix('XUL_CIRC_SUMMARY'); // + '?copy_id=' + selection_list[i].copy_id + '&count=' + count;
            var my_xulG = obj.win.open( url, 'show_last_few_circs', 'chrome,resizable,modal', { 'copy_id' : selection_list[i].copy_id, 'new_tab' : xulG.new_tab, 'url_prefix': xulG.url_prefix } );

            if (typeof my_xulG.retrieve_these_patrons == 'undefined') continue;
            var patrons = my_xulG.retrieve_these_patrons;
            for (var j = 0; j < patrons.length; j++) {
                if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') {
                    try {
                        window.xulG.new_patron_tab( {}, { 'id' : patrons[j] } );
                    } catch(E) {
                        obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.utils.retrieve_patron.failure') ,E);
                    }
                }
            }

        } catch(E) {
            obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.utils.retrieve_circs.failure') ,E);
        }
    }
};

circ.util.offline_checkout_columns = function(modify,params) {

    var c = [
        {
            'id' : 'timestamp',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.timestamp'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.timestamp; }
        },
        {
            'id' : 'checkout_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.checkout_time'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.checkout_time; }
        },
        {
            'id' : 'type',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.type'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.type; }
        },
        {
            'id' : 'noncat',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.noncat'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.noncat; }
        },
        {
            'id' : 'noncat_type',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.noncat_type'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.noncat_type; }
        },
        {
            'id' : 'noncat_count',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.count'),
            'sort_type' : 'number',
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return my.noncat_count; }
        },
        {
            'id' : 'patron_barcode',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.patron_barcode'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.patron_barcode; }
        },
        {
            'id' : 'barcode',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.item_barcode'),
            'flex' : 2,
            'primary' : true,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return my.barcode; }
        },
        {
            'id' : 'due_date',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.due_date'),
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return my.due_date; }
        },
        {
            'id' : 'due_time',
            'label' : document.getElementById('commonStrings').getString('staff.circ_label_due_time'),
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return my.due_time; }
        }

    ];
    if (modify) for (var i = 0; i < c.length; i++) {
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
};

circ.util.offline_checkin_columns = function(modify,params) {

    var c = [
        {
            'id' : 'timestamp',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.timestamp'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.timestamp; }
        },
        {
            'id' : 'backdate',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.backdate'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.backdate; }
        },
        {
            'id' : 'type',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.type'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.type; }
        },
        {
            'id' : 'barcode',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.item_barcode'),
            'flex' : 2,
            'primary' : true,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return my.barcode; }
        }
    ];
    if (modify) for (var i = 0; i < c.length; i++) {
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
};

circ.util.offline_renew_columns = function(modify,params) {

    var c = [
        {
            'id' : 'timestamp',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.timestamp'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.timestamp; }
        },
        {
            'id' : 'checkout_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.checkout_time'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.checkout_time; }
        },
        {
            'id' : 'type',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.type'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.type; }
        },
        {
            'id' : 'patron_barcode',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.patron_barcode'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.patron_barcode; }
        },
        {
            'id' : 'barcode',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.item_barcode'),
            'flex' : 2,
            'primary' : true,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return my.barcode; }
        },
        {
            'id' : 'due_date',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.due_date'),
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return my.due_date; }
        },
        {
            'id' : 'due_time',
            'label' : document.getElementById('commonStrings').getString('staff.circ_label_due_time'),
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return my.due_time; }
        }
    ];
    if (modify) for (var i = 0; i < c.length; i++) {
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
};

circ.util.offline_inhouse_use_columns = function(modify,params) {

    var c = [
        {
            'id' : 'timestamp',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.timestamp'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.timestamp; }
        },
        {
            'id' : 'use_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.use_time'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.use_time; }
        },
        {
            'id' : 'type',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.type'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.type; }
        },
        {
            'id' : 'count',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.count'),
            'sort_type' : 'number',
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return my.count; }
        },
        {
            'id' : 'barcode',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.item_barcode'),
            'flex' : 2,
            'primary' : true,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return my.barcode; }
        }
    ];
    if (modify) for (var i = 0; i < c.length; i++) {
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
};

circ.util.columns = function(modify,params) {

    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
    JSAN.use('util.network'); var network = new util.network();
    JSAN.use('util.money');

    var c = [
        {
            'id' : 'acp_id',
            'fm_class' : 'acp',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_id'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.acp.id(); },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'circ_id',
            'fm_class' : 'circ',
            'label' : document.getElementById('commonStrings').getString('staff.circ_label_id'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.circ ? my.circ.id() : ""; },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'mvr_doc_id',
            'fm_class' : 'mvr',
            'label' : document.getElementById('commonStrings').getString('staff.mvr_label_doc_id'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.mvr.doc_id(); },
            'persist' : 'hidden width ordinal'
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'service',
            'label' : 'Service',
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.service; }
        },
        {
            'id' : 'barcode',
            'fm_class' : 'acp',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_barcode'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.acp.barcode(); },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'call_number',
            'fm_class' : 'acp',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_call_number'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my,scratch_data) {
                var acn_id;
                if (my.acn) {
                    if (typeof my.acn == 'object') {
                        acn_id = my.acn.id();
                    } else {
                        acn_id = my.acn;
                    }
                } else if (my.acp) {
                    if (typeof my.acp.call_number() == 'object' && my.acp.call_number() != null) {
                        acn_id = my.acp.call_number().id();
                    } else {
                        acn_id = my.acp.call_number();
                    }
                }
                if (!acn_id && acn_id != 0) {
                    return '';
                } else if (acn_id == -1) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.not_cataloged');
                } else if (acn_id == -2) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.retrieving');
                } else {
                    if (!my.acn) {
                        if (typeof scratch_data == 'undefined' || scratch_data == null) {
                            scratch_data = {};
                        }
                        if (typeof scratch_data['acn_map'] == 'undefined') {
                            scratch_data['acn_map'] = {};
                        }
                        if (typeof scratch_data['acn_map'][ acn_id ] == 'undefined') {
                            var x = network.simple_request("FM_ACN_RETRIEVE.authoritative",[ acn_id ]);
                            if (x.ilsevent) {
                                return document.getElementById('circStrings').getString('staff.circ.utils.not_cataloged');
                            } else {
                                my.acn = x;
                                scratch_data['acn_map'][ acn_id ] = my.acn;
                            }
                        } else {
                            my.acn = scratch_data['acn_map'][ acn_id ];
                        }
                    }
                    return my.acn.label();
                }
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'owning_lib',
            'fm_class' : 'acn',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.owning_lib'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (Number(my.acn.owning_lib())>=0) {
                    return data.hash.aou[ my.acn.owning_lib() ].shortname();
                } else {
                    return my.acn.owning_lib().shortname();
                }
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'prefix',
            'fm_class' : 'acn',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.prefix'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my,scratch_data) {
                var acn_id;
                if (my.acn) {
                    if (typeof my.acn == 'object') {
                        acn_id = my.acn.id();
                    } else {
                        acn_id = my.acn;
                    }
                } else if (my.acp) {
                    if (typeof my.acp.call_number() == 'object' && my.acp.call_number() != null) {
                        acn_id = my.acp.call_number().id();
                    } else {
                        acn_id = my.acp.call_number();
                    }
                }
                if (!acn_id && acn_id != 0) {
                    return '';
                } else if (acn_id == -1) {
                    return '';
                } else if (acn_id == -2) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.retrieving');
                } else {
                    if (!my.acn) {
                        if (typeof scratch_data == 'undefined' || scratch_data == null) {
                            scratch_data = {};
                        }
                        if (typeof scratch_data['acn_map'] == 'undefined') {
                            scratch_data['acn_map'] = {};
                        }
                        if (typeof scratch_data['acn_map'][ acn_id ] == 'undefined') {
                            var x = network.simple_request("FM_ACN_RETRIEVE.authoritative",[ acn_id ]);
                            if (x.ilsevent) {
                                return document.getElementById('circStrings').getString('staff.circ.utils.not_cataloged');
                            } else {
                                my.acn = x;
                                scratch_data['acn_map'][ acn_id ] = my.acn;
                            }
                        } else {
                            my.acn = scratch_data['acn_map'][ acn_id ];
                        }
                    }
                }

                if (typeof my.acn != 'object') return '';
                return (typeof my.acn.prefix() == 'object')
                    ? my.acn.prefix().label()
                    : data.lookup("acnp", my.acn.prefix() ).label();
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'suffix',
            'fm_class' : 'acn',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.suffix'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my,scratch_data) {
                var acn_id;
                if (my.acn) {
                    if (typeof my.acn == 'object') {
                        acn_id = my.acn.id();
                    } else {
                        acn_id = my.acn;
                    }
                } else if (my.acp) {
                    if (typeof my.acp.call_number() == 'object' && my.acp.call_number() != null) {
                        acn_id = my.acp.call_number().id();
                    } else {
                        acn_id = my.acp.call_number();
                    }
                }
                if (!acn_id && acn_id != 0) {
                    return '';
                } else if (acn_id == -1) {
                    return '';
                } else if (acn_id == -2) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.retrieving');
                } else {
                    if (!my.acn) {
                        if (typeof scratch_data == 'undefined' || scratch_data == null) {
                            scratch_data = {};
                        }
                        if (typeof scratch_data['acn_map'] == 'undefined') {
                            scratch_data['acn_map'] = {};
                        }
                        if (typeof scratch_data['acn_map'][ acn_id ] == 'undefined') {
                            var x = network.simple_request("FM_ACN_RETRIEVE.authoritative",[ acn_id ]);
                            if (x.ilsevent) {
                                return document.getElementById('circStrings').getString('staff.circ.utils.not_cataloged');
                            } else {
                                my.acn = x;
                                scratch_data['acn_map'][ acn_id ] = my.acn;
                            }
                        } else {
                            my.acn = scratch_data['acn_map'][ acn_id ];
                        }
                    }
                }

                if (typeof my.acn != 'object') return '';
                return (typeof my.acn.suffix() == 'object')
                    ? my.acn.suffix().label()
                    : data.lookup("acns", my.acn.suffix() ).label();
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'label_class',
            'fm_class' : 'acn',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.label_class'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my,scratch_data) {
                var acn_id;
                if (my.acn) {
                    if (typeof my.acn == 'object') {
                        acn_id = my.acn.id();
                    } else {
                        acn_id = my.acn;
                    }
                } else if (my.acp) {
                    if (typeof my.acp.call_number() == 'object' && my.acp.call_number() != null) {
                        acn_id = my.acp.call_number().id();
                    } else {
                        acn_id = my.acp.call_number();
                    }
                }
                if (!acn_id && acn_id != 0) {
                    return '';
                } else if (acn_id == -1) {
                    return '';
                } else if (acn_id == -2) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.retrieving');
                } else {
                    if (!my.acn) {
                        if (typeof scratch_data == 'undefined' || scratch_data == null) {
                            scratch_data = {};
                        }
                        if (typeof scratch_data['acn_map'] == 'undefined') {
                            scratch_data['acn_map'] = {};
                        }
                        if (typeof scratch_data['acn_map'][ acn_id ] == 'undefined') {
                            var x = network.simple_request("FM_ACN_RETRIEVE.authoritative",[ acn_id ]);
                            if (x.ilsevent) {
                                return document.getElementById('circStrings').getString('staff.circ.utils.not_cataloged');
                            } else {
                                my.acn = x;
                                scratch_data['acn_map'][ acn_id ] = my.acn;
                            }
                        } else {
                            my.acn = scratch_data['acn_map'][ acn_id ];
                        }
                    }
                }

                if (typeof my.acn != 'object') return '';
                return (typeof my.acn.label_class() == 'object') ? my.acn.label_class().name() : my.acn.label_class();
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'parts',
            'fm_class' : 'acp',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_parts'),
            'flex' : 1,
            'sort_type' : 'number',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (! my.acp.parts()) return '';
                var parts = my.acp.parts();
                var display_string = '';
                for (var i = 0; i < parts.length; i++) {
                    if (my.doc_id) {
                        if (my.doc_id == parts[i].record()) {
                            return parts[i].label();
                        }
                    } else {
                        if (i != 0) display_string += ' : ';
                        display_string += parts[i].label();
                    }
                }
                return display_string;
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'copy_number',
            'fm_class' : 'acp',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_copy_number'),
            'flex' : 1,
            'sort_type' : 'number',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.acp.copy_number(); },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'location',
            'fm_class' : 'acp',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_location'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (Number(my.acp.location())>=0) {
                    return data.lookup("acpl", my.acp.location() ).name();
                } else {
                    return my.acp.location().name();
                }
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'loan_duration',
            'fm_class' : 'acp',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_loan_duration'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                switch(Number(my.acp.loan_duration())) {
                    case 1:
                        return document.getElementById('circStrings').getString('staff.circ.utils.loan_duration.short');
                        break;
                    case 2:
                        return document.getElementById('circStrings').getString('staff.circ.utils.loan_duration.normal');
                        break;
                    case 3:
                        return document.getElementById('circStrings').getString('staff.circ.utils.loan_duration.long');
                        break;
                };
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'circ_lib',
            'fm_class' : 'acp',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_circ_lib'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (Number(my.acp.circ_lib())>=0) {
                    return data.hash.aou[ my.acp.circ_lib() ].shortname();
                } else {
                    return my.acp.circ_lib().shortname();
                }
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'fine_level',
            'fm_class' : 'acp',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_fine_level'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                switch(Number(my.acp.fine_level())) {
                    case 1:
                        return document.getElementById('circStrings').getString('staff.circ.utils.fine_level.low');
                        break;
                    case 2:
                        return document.getElementById('circStrings').getString('staff.circ.utils.fine_level.normal');
                        break;
                    case 3:
                        return document.getElementById('circStrings').getString('staff.circ.utils.fine_level.high');
                        break;
                };
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'circulate',
            'fm_class' : 'acp',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.circulate'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (get_bool( my.acp.circulate() )) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.yes');
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.no');
                }
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'deleted',
            'fm_class' : 'acp',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.deleted'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (get_bool( my.acp.deleted() )) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.yes');
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.no');
                }
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'holdable',
            'fm_class' : 'acp',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.holdable'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (get_bool( my.acp.holdable() )) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.yes');
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.no');
                }
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'floating',
            'fm_class' : 'acp',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.floating'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (get_bool( my.acp.floating() )) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.yes');
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.no');
                }
            },
            'persist' : 'hidden width ordinal'
        },

        {
            'id' : 'opac_visible',
            'fm_class' : 'acp',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.opac_visible'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (get_bool( my.acp.opac_visible() )) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.yes');
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.no');
                }
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'acp_mint_condition',
            'fm_class' : 'acp',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.acp_mint_condition'),
            'flex' : 0,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (get_bool( my.acp.mint_condition() )) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.acp_mint_condition.true');
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.acp_mint_condition.false');
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'acp',
            'id' : 'ref',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.reference'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (get_bool( my.acp.ref() )) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.yes');
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.no');
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'acp',
            'id' : 'deposit',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.deposit'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (get_bool( my.acp.deposit() )) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.yes');
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.no');
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'acp',
            'id' : 'deposit_amount',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_deposit_amount'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.acp.price() == null) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.unset');
                } else {
                    return util.money.sanitize(my.acp.deposit_amount());
                }
            },
            'sort_type' : 'money'
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'acp',
            'id' : 'price',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_price'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.acp.price() == null) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.unset');
                } else {
                    return util.money.sanitize(my.acp.price());
                }
            },
            'sort_type' : 'money'
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'acp',
            'id' : 'circ_as_type',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_circ_as_type'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                return my.acp.circ_as_type() != null && my.acp.circ_as_type() == 'object'
                    ? my.acp.circ_as_type()
                    : ( typeof data.hash.citm[ my.acp.circ_as_type() ] != 'undefined'
                        ? data.hash.citm[ my.acp.circ_as_type() ].value
                        : ''
                    );
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'acp',
            'id' : 'circ_modifier',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_circ_modifier'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { var cm = my.acp.circ_modifier(); return document.getElementById('commonStrings').getFormattedString('staff.circ_modifier.display',[cm,data.hash.ccm[cm].name(),data.hash.ccm[cm].description()]); }
        },
        {
            'id' : 'status_changed_time',
            'fm_class' : 'acp',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.status_changed_time'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.acp.status_changed_time(), '%{localized}' ); },
            'persist' : 'hidden width ordinal'
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.acp
                    ? my.acp.status_changed_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'circ',
            'id' : 'checkout_lib',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.checkout_lib'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.circ) {
                    return data.hash.aou[ my.circ.circ_lib() ].shortname();
                } else {
                    return "";
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'circ',
            'id' : 'xact_start',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.xact_start'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.circ) {
                    return util.date.formatted_date( my.circ.xact_start(), '%{localized}' );
                } else {
                    return "";
                }
            }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.circ
                    ? my.circ.xact_start()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'circ',
            'id' : 'checkin_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.checkin_time'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.circ) {
                    return util.date.formatted_date( my.circ.checkin_time(), '%{localized}' );
                } else {
                    return "";
                }
            }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.circ
                    ? my.circ.checkin_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'circ',
            'id' : 'xact_finish',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.xact_finish'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.circ ? util.date.formatted_date( my.circ.xact_finish(), '%{localized}' ) : ""; },
            'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.circ
                    ? my.circ.xact_finish()
                    : null
                ).getTime(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'circ',
            'id' : 'due_date',
            'label' : document.getElementById('commonStrings').getString('staff.circ_label_due_date'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.circ) {
                    return util.date.formatted_date( my.circ.due_date(), '%{localized}' );
                } else {
                    return "";
                }
            }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.circ
                    ? my.circ.due_date()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'acp',
            'id' : 'acp_create_date',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.create_date'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.acp.create_date(), '%{localized}' ); }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.acp
                    ? my.acp.create_date()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'acp',
            'id' : 'acp_edit_date',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.edit_date'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.acp.edit_date(), '%{localized}' ); }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.acp
                    ? my.acp.edit_date()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'mvr',
            'id' : 'title',
            'label' : document.getElementById('commonStrings').getString('staff.mvr_label_title'),
            'flex' : 2,
            'sort_type' : 'title',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.mvr) {
                    if (my.mvr.doc_id() == -1) {
                        return my.acp.dummy_title();
                    } else {
                        return my.mvr.title();
                    }
                } else {
                    return my.acp.dummy_title();
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'mvr',
            'id' : 'author',
            'label' : document.getElementById('commonStrings').getString('staff.mvr_label_author'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.mvr) {
                    if (my.mvr.doc_id() == -1) {
                        return my.acp.dummy_author();
                    } else {
                        return my.mvr.author();
                    }
                } else {
                    return my.acp.dummy_author();
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'mvr',
            'id' : 'edition',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.edition'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.mvr.edition(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'mvr',
            'id' : 'isbn',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.isbn'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { 
                if (my.mvr) {
                    if (my.mvr.doc_id() == -1) {
                        return my.acp.dummy_isbn();
                    } else {
                        return my.mvr.isbn();
                    }
                } else {
                    return my.acp.dummy_isbn();
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'mvr',
            'id' : 'pubdate',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.pubdate'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.mvr.pubdate(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'mvr',
            'id' : 'publisher',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.publisher'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.mvr.publisher(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'mvr',
            'id' : 'tcn',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.tcn'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.mvr.tcn(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'circ',
            'id' : 'renewal_remaining',
            'label' : document.getElementById('commonStrings').getString('staff.circ_label_renewal_remaining'),
            'flex' : 0,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.circ) {
                    return my.circ.renewal_remaining();
                } else {
                    return "";
                }
            },
            'sort_type' : 'number'
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'circ',
            'id' : 'stop_fines',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.stop_fines'),
            'flex' : 0,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.circ) {
                    return my.circ.stop_fines();
                } else {
                    return "";
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'circ',
            'id' : 'stop_fines_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.stop_fines_time'),
            'flex' : 0,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.circ) {
                    return util.date.formatted_date( my.circ.stop_fines_time(), '%{localized}' );
                } else {
                    return "";
                }
            }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.circ
                    ? my.circ.stop_fines_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'acp',
            'id' : 'acp_status',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_status'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (Number(my.acp.status())>=0) {
                    return data.hash.ccs[ my.acp.status() ].name();
                } else {
                    return my.acp.status().name();
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'route_to',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.route_to'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.route_to.toString(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'message',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.message'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.message.toString(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'uses',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.uses'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.uses; },
            'sort_type' : 'number'
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'acp',
            'id' : 'alert_message',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.alert_message'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.acp.alert_message(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'circ',
            'id' : 'checkin_workstation',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.checkin_workstation'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.circ ? ( typeof my.circ.checkin_workstation() == 'object' ? my.circ.checkin_workstation().name() : my.circ.checkin_workstation() ) : ""; },
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'circ',
            'id' : 'checkout_workstation',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.checkout_workstation'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.circ ? ( typeof my.circ.workstation() == 'object' ? my.circ.workstation().name() : my.circ.workstation() ) : ""; },
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'circ',
            'id' : 'checkout_workstation_top_of_chain',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.checkout_workstation_top_of_chain'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { if (my.circ&&!my.original_circ) { if(!get_bool(my.circ.desk_renewal())&&!get_bool(my.circ.opac_renewal())&&!get_bool(my.circ.phone_renewal())){my.original_circ = my.circ;}}; return my.original_circ ? ( typeof my.original_circ.workstation() == 'object' ? my.original_circ.workstation().name() : my.original_circ.workstation() ) : ""; },
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'circ',
            'id' : 'checkin_scan_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.checkin_scan_time'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.circ ? util.date.formatted_date( my.circ.checkin_scan_time(), '%{localized}' ) : ""; },
            'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.circ
                    ? my.circ.checkin_scan_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'bre',
            'id' : 'owner',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.owner'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.bre ? (typeof my.bre.owner() == 'object' ? my.bre.owner().shortname() : data.hash.aou[my.bre.owner()].shortname() ) : ''; }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'bre',
            'id' : 'creator',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.creator'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.bre ? (typeof my.bre.creator() == 'object' ? my.bre.creator().usrname() : '#' + my.bre.creator() ) : ''; }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'bre',
            'id' : 'editor',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.editor'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.bre ? (typeof my.bre.editor() == 'object' ? my.bre.editor().usrname() : '#' + my.bre.editor() ) : ''; }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'bre',
            'id' : 'create_date',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.bre.create_date'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.bre ? util.date.formatted_date( my.bre.create_date(), '%{localized}' ) : ''; }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.bre
                    ? my.bre.create_date()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'bre',
            'id' : 'edit_date',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.bre.edit_date'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.bre ? util.date.formatted_date( my.bre.edit_date(), '%{localized}' ) : ''; }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.bre
                    ? my.bre.edit_date()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'bre',
            'id' : 'tcn_value',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.tcn'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.bre ? my.bre.tcn_value() : ''; }
        },
        {
            'persist' : 'hidden width ordinal',
            'fm_class' : 'bre',
            'id' : 'tcn_source',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.tcn_source'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.bre ? my.bre.tcn_source() : ''; }
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
};

circ.util.work_log_columns = function(modify,params) {

    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});

    var c = [
        {
            'persist' : 'hidden width ordinal',
            'id' : 'message',
            'label' : document.getElementById('circStrings').getString('staff.circ.work_log_column.message'),
            'flex' : 3,
            'primary' : true,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return my.message; }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'when',
            'label' : document.getElementById('circStrings').getString('staff.circ.work_log_column.when'),
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return String( my.when ); }
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
};

circ.util.transit_columns = function(modify,params) {

    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});

    var c = [
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_item_barcode',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.barcode'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.acp.barcode(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_item_title',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.title'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                try { return my.mvr.title(); }
                catch(E) { return my.acp.dummy_title(); }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_item_author',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.author'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                try { return my.mvr.author(); }
                catch(E) { return my.acp.dummy_author(); }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_item_callnumber',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.callnumber'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.acn.label(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_id',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.transit_id'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.atc.id(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_source',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.transit_source'),
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) {
                if (typeof my.atc.source() == "object") {
                    return my.atc.source().shortname();
                } else {
                    return data.hash.aou[ my.atc.source() ].shortname();
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_source_send_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.transit_source_send_time'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.atc.source_send_time(), '%{localized}' ); }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.atc
                    ? my.atc.source_send_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_dest_lib',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.transit_dest'),
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) {
                if (typeof my.atc.dest() == "object") {
                    return my.atc.dest().shortname();
                } else {
                    return data.hash.aou[ my.atc.dest() ].shortname();
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_dest_recv_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.transit_dest_recv_time'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.atc.dest_recv_time(), '%{localized}' ); }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.atc
                    ? my.atc.dest_recv_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_target_copy',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.transit_target_copy'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.atc.target_copy(); }
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
};

circ.util.hold_columns = function(modify,params) {

    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});

    var c = [
        {
            'id' : 'post_clear_shelf_action',
            'flex' : 1, 'primary' : false, 'hidden' : true, 'editable' : false, 
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.hold_post_clear_shelf_action.label'),
            'render' : function(my) { 
                return my.post_clear_shelf_action ? document.getElementById('circStrings').getString('staff.circ.utils.hold_post_clear_shelf_action.' + my.post_clear_shelf_action) : '';
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'cancel_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.hold_cancel_time'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.ahr.cancel_time(), '%{localized}' ); }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.ahr
                    ? my.ahr.cancel_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'cancel_cause',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.hold_cancel_cause'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return typeof my.ahr.cancel_cause == 'object' ? my.ahr.cancel_cause().label() : data.hash.ahrcc[ my.ahr.cancel_cause() ].label(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'cancel_note',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.hold_cancel_note'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.cancel_note(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'request_lib',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.request_lib'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (Number(my.ahr.request_lib())>=0) {
                    return data.hash.aou[ my.ahr.request_lib() ].name();
                } else {
                    return my.ahr.request_lib().name();
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'request_lib_shortname',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.request_lib_shortname'),
            'flex' : 0,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (Number(my.ahr.request_lib())>=0) {
                    return data.hash.aou[ my.ahr.request_lib() ].shortname();
                } else {
                    return my.ahr.request_lib().shortname();
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'request_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.request_time'),
            'flex' : 0,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.ahr.request_time(), '%{localized}' ); }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.ahr
                    ? my.ahr.request_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'shelf_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.holds.shelf_time'),
            'flex' : 0,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.ahr.shelf_time(), '%{localized}' ); }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.ahr
                    ? my.ahr.shelf_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'shelf_expire_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.holds.shelf_expire_time'),
            'flex' : 0,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.ahr.shelf_expire_time(), '%{localized}' ); }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.ahr
                    ? my.ahr.shelf_expire_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'available_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.available_time'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) {
                if (my.ahr.current_shelf_lib() == my.ahr.pickup_lib()) {
                    return util.date.formatted_date( my.ahr.shelf_time(), '%{localized}' );
                }
                return "";
            }
            ,'sort_value' : function(my) {
                if (my.ahr.current_shelf_lib() == my.ahr.pickup_lib()) {
                    return util.date.db_date2Date( my.ahr.shelf_time() ).getTime();
                } else {
                    return util.date.db_date2Date( null ).getTime();
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'capture_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.capture_time'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.capture_time() ? util.date.formatted_date( my.ahr.capture_time(), '%{localized}' ) : ""; }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.ahr
                    ? my.ahr.capture_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'ahr_status',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_status_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'editable' : false, 'render' : function(my) {
                switch (Number(my.status)) {
                    case 1:
                        return document.getElementById('circStrings').getString('staff.circ.utils.hold_status.1');
                        break;
                    case 2:
                        return document.getElementById('circStrings').getString('staff.circ.utils.hold_status.2');
                        break;
                    case 3:
                        return document.getElementById('circStrings').getString('staff.circ.utils.hold_status.3');
                        break;
                    case 4:
                        return document.getElementById('circStrings').getString('staff.circ.utils.hold_status.4');
                        break;
                    case 5:
                        return document.getElementById('circStrings').getString('staff.circ.utils.hold_status.5');
                        break;
                    case 6:
                        return document.getElementById('circStrings').getString('staff.circ.utils.hold_status.6');
                        break;
                    case 7:
                        return document.getElementById('circStrings').getString('staff.circ.utils.hold_status.7');
                        break;
                    case 8:
                        return document.getElementById('circStrings').getString('staff.circ.utils.hold_status.8');
                        break;
                    default:
                        return my.status;
                        break;
                };
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'hold_type',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_hold_type_label'),
            'flex' : 0,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.hold_type(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'ahr_mint_condition',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.ahr_mint_condition'),
            'flex' : 0,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (get_bool( my.ahr.mint_condition() )) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.ahr_mint_condition.true');
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.ahr_mint_condition.false');
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'frozen',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.active'),
            'flex' : 0,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (!get_bool( my.ahr.frozen() )) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.yes');
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.no');
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'thaw_date',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.thaw_date'),
            'flex' : 0,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.ahr.thaw_date() == null) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.thaw_date.none');
                } else {
                    return util.date.formatted_date( my.ahr.thaw_date(), '%{localized}' );
                }
            }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.ahr
                    ? my.ahr.thaw_date()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'pickup_lib',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.pickup_lib'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (Number(my.ahr.pickup_lib())>=0) {
                    return data.hash.aou[ my.ahr.pickup_lib() ].name();
                } else {
                    return my.ahr.pickup_lib().name();
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'pickup_lib_shortname',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_pickup_lib_label'),
            'flex' : 0,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (Number(my.ahr.pickup_lib())>=0) {
                    return data.hash.aou[ my.ahr.pickup_lib() ].shortname();
                } else {
                    return my.ahr.pickup_lib().shortname();
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'current_copy',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_current_copy_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.acp) {
                    return my.acp.barcode();
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.current_copy.none');
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'current_copy_location',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_current_copy_location_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (!my.acp) { return ""; } else { if (Number(my.acp.location())>=0) return data.lookup("acpl", my.acp.location() ).name(); else return my.acp.location().name(); }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'email_notify',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_email_notify_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (get_bool(my.ahr.email_notify())) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.yes');
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.no');
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'expire_date',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_expire_date_label'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.expire_time() ? util.date.formatted_date( my.ahr.expire_time(), '%{localized}' ) : ''; }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.ahr
                    ? my.ahr.expire_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'fulfillment_time',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_fulfillment_time_label'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.ahr.fulfillment_time(), '%{localized}' ); }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.ahr
                    ? my.ahr.fulfillment_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'holdable_formats',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_holdable_formats_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.holdable_formats(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'holdable_part',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_holdable_part_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.part.label(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'issuance_label',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_issuance_label_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.issuance.label(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'ahr_id',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_id_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.id(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'phone_notify',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_phone_notify_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.phone_notify(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'sms_notify',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_sms_notify_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.sms_notify(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'sms_carrier',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_sms_carrier_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return data.hash.csc[ my.ahr.sms_carrier() ].name(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'prev_check_time',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_prev_check_time_label'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.ahr.prev_check_time(), '%{localized}' ); }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.ahr
                    ? my.ahr.prev_check_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'requestor',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_requestor_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.requestor(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'selection_depth',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_selection_depth_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.selection_depth(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'top_of_queue',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_top_of_queue_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return get_bool( my.ahr.cut_in_line() ) ? document.getElementById('commonStrings').getString('common.yes') : document.getElementById('commonStrings').getString('common.no') ; }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'target',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_target_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.target(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'usr',
            'label' : document.getElementById('commonStrings').getString('staff.ahr_usr_label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.usr(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'title',
            'label' : document.getElementById('commonStrings').getString('staff.mvr_label_title'),
            'flex' : 1,
            'sort_type' : 'title',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.mvr) {
                    return my.mvr.title();
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.title.none');
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'author',
            'label' : document.getElementById('commonStrings').getString('staff.mvr_label_author'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.mvr) {
                    return my.mvr.author();
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.author.none');
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'edition',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.edition'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.mvr.edition(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'isbn',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.isbn'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.mvr.isbn(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'pubdate',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.pubdate'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.mvr.pubdate(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'publisher',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.publisher'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.mvr.publisher(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'tcn',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.tcn'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.mvr.tcn(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'notify_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.notify_time'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return util.date.formatted_date( my.ahr.notify_time(), '%{localized}' ); }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.ahr
                    ? my.ahr.notify_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'notify_count',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.notify_count'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.notify_count(); }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_source',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.transit_source'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (my.ahr.transit()) {
                    return data.hash.aou[ my.ahr.transit().source() ].shortname();
                } else {
                    return "";
                }
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_source_send_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.transit_source_send_time'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.transit() ?  util.date.formatted_date( my.ahr.transit().source_send_time(), '%{localized}' ) : ""; }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.ahr
                    ? my.ahr.transit().source_send_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_dest_lib',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.transit_dest'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.transit() ?  data.hash.aou[ my.ahr.transit().dest() ].shortname() : ""; }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'transit_dest_recv_time',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.transit_dest_recv_time'),
            'flex' : 1,
            'sort_type' : 'date',
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahr.transit() ?  util.date.formatted_date( my.ahr.transit().dest_recv_time(), '%{localized}' ) : ""; }
            ,'sort_value' : function(my) {
                return util.date.db_date2Date(
                    my.ahr
                    ? my.ahr.transit().dest_recv_time()
                    : null
                ).getTime();
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'patron_barcode',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.offline.patron_barcode'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.patron_barcode ? my.patron_barcode : ""; }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'patron_family_name',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.patron_family_name'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.patron_family_name ? my.patron_family_name : ""; }
        },
        {
            "persist": "hidden width ordinal",
            "id": "patron_alias",
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.patron_alias'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.patron_alias ? my.patron_alias : ""; }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'patron_first_given_name',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.patron_first_given_name'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.patron_first_given_name ? my.patron_first_given_name : ""; }
        },
        {
            'id' : 'callnumber',
            'fm_class' : 'acp',
            'label' : document.getElementById('commonStrings').getString('staff.acp_label_call_number'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my,scratch_data) {
                var acn_id;
                if (my.acn) {
                    if (typeof my.acn == 'object') {
                        acn_id = my.acn.id();
                    } else {
                        acn_id = my.acn;
                    }
                } else if (my.acp) {
                    if (typeof my.acp.call_number() == 'object' && my.acp.call_number() != null) {
                        acn_id = my.acp.call_number().id();
                    } else {
                        acn_id = my.acp.call_number();
                    }
                }
                if (!acn_id && acn_id != 0) {
                    return '';
                } else if (acn_id == -1) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.not_cataloged');
                } else if (acn_id == -2) {
                    return document.getElementById('circStrings').getString('staff.circ.utils.retrieving');
                } else {
                    if (!my.acn) {
                        if (typeof scratch_data == 'undefined' || scratch_data == null) {
                            scratch_data = {};
                        }
                        if (typeof scratch_data['acn_map'] == 'undefined') {
                            scratch_data['acn_map'] = {};
                        }
                        if (typeof scratch_data['acn_map'][ acn_id ] == 'undefined') {
                            var x = network.simple_request("FM_ACN_RETRIEVE.authoritative",[ acn_id ]);
                            if (x.ilsevent) {
                                return document.getElementById('circStrings').getString('staff.circ.utils.not_cataloged');
                            } else {
                                my.acn = x;
                                scratch_data['acn_map'][ acn_id ] = my.acn;
                            }
                        } else {
                            my.acn = scratch_data['acn_map'][ acn_id ];
                        }
                    }
                    return my.acn.label();
                }
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'prefix',
            'fm_class' : 'acn',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.prefix'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (typeof my.acn == 'undefined') return '';
                return (typeof my.acn.prefix() == 'object')
                    ? my.acn.prefix().label()
                    : data.lookup("acnp", my.acn.prefix() ).label();
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'suffix',
            'fm_class' : 'acn',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.suffix'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                if (typeof my.acn == 'undefined') return '';
                return (typeof my.acn.suffix() == 'object')
                    ? my.acn.suffix().label()
                    : data.lookup("acns", my.acn.suffix() ).label();
            },
            'persist' : 'hidden width ordinal'
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'total_holds',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.total_holds'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.total_holds; }
        },
                {
            'persist' : 'hidden width ordinal',
            'id' : 'queue_position',
            'sort_type' : 'number',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.queue_position'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.queue_position; }
        },
                {
            'persist' : 'hidden width ordinal',
            'id' : 'potential_copies',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.potential_copies'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.potential_copies; }
        },
                {
            'persist' : 'hidden width ordinal',
            'id' : 'estimated_wait',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.estimated_wait'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.estimated_wait; }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'hold_note',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.hold_note'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) { return my.ahrn_count; }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'hold_note_text',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.hold_note_text'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 'render' : function(my) {
                var s = '';
                var notes = my.ahr.notes();
                for (var i = 0; i < notes.length; i++) {
                    s += notes[i].title() + ':' + notes[i].body() + '; \n';
                }
                return s;
            }
        },
        {
            'persist' : 'hidden width ordinal',
            'id' : 'staff_hold',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.staff_hold'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'editable' : false, 
            'render' : function(my) {
                if (my.ahr.usr() != my.ahr.requestor()){
                    return document.getElementById('circStrings').getString('staff.circ.utils.yes');
                } else {
                    return document.getElementById('circStrings').getString('staff.circ.utils.no');
                }
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
};

circ.util.checkin_via_barcode = function(session,params,backdate,auto_print,async) {
    try {
        JSAN.use('util.error'); var error = new util.error();
        JSAN.use('util.network'); var network = new util.network();
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
        JSAN.use('util.date'); JSAN.use('util.functional');

        if (backdate && (backdate == util.date.formatted_date(new Date(),'%Y-%m-%d')) ) backdate = null;

        //var params = { 'barcode' : barcode };
        if (backdate) params.backdate = util.date.formatted_date(backdate,'%{iso8601}');

        if (typeof params.disable_textbox == 'function') {
            try { params.disable_textbox(); }
            catch(E) { error.sdump('D_ERROR','params.disable_textbox() = ' + E); };
        }

        function checkin_callback(req) {
            JSAN.use('util.error'); var error = new util.error();
            try {
                var check = req.getResultObject();
                var r = circ.util.checkin_via_barcode2(session,params,backdate,auto_print,check);
                try {
                    error.work_log(
                        document.getElementById('circStrings').getFormattedString(
                            'staff.circ.work_log_checkin_attempt.' + r.what_happened + '.message',
                            [
                                ses('staff_usrname'),
                                r.payload.patron ? r.payload.patron.family_name() : '',
                                r.payload.patron ? r.payload.patron.card().barcode() : '',
                                r.payload.copy ? r.payload.copy.barcode() : '',
                                r.route_to ? r.route_to : ''
                            ]
                        ), {
                            'au_id' : r.payload.patron ? r.payload.patron.id() : '',
                            'au_family_name' : r.payload.patron ? r.payload.patron.family_name() : '',
                            'au_barcode' : r.payload.patron ? r.payload.patron.card().barcode() : '',
                            'acp_barcode' : r.payload.copy ? r.payload.copy.barcode() : ''
                        }
                    );
                } catch(E) {
                    error.sdump('D_ERROR','Error with work_logging in server/circ/checkout.js, _checkout:' + E);
                }

                if (typeof params.checkin_result == 'function') {
                    try { params.checkin_result(r); } catch(E) { error.sdump('D_ERROR','params.checkin_result() = ' + E); };
                }
                if (typeof async == 'function') async(check);
                return check;
            } catch(E) {
                error.standard_unexpected_error_alert(document.getElementById('circStrings').getFormattedString('staff.circ.checkin.error', ['1']), E);
                if (typeof params.enable_textbox == 'function') {
                    try { params.enable_textbox(); }
                    catch(E) { error.sdump('D_ERROR','params.disable_textbox() = ' + E); };
                }
                return null;
            }
        }

        var suppress_popups = data.hash.aous['ui.circ.suppress_checkin_popups'];

        var check = network.request(
            api.CHECKIN_VIA_BARCODE.app,
            api.CHECKIN_VIA_BARCODE.method,
            [ session, util.functional.filter_object( params, function(i,o) { return typeof o != 'function'; } ) ],
            async ? checkin_callback : null,
            {
                'title' : document.getElementById('circStrings').getString('staff.circ.utils.checkin.override'),
                'auto_override_these_events' : suppress_popups ? [
                    null /* custom event */,
                    1203 /* COPY_BAD_STATUS */,
                    1213 /* PATRON_BARRED */,
                    1217 /* PATRON_INACTIVE */,
                    1224 /* PATRON_ACCOUNT_EXPIRED */,
                    1234 /* ITEM_DEPOSIT_PAID */,
                    7009 /* CIRC_CLAIMS_RETURNED */,
                    7010 /* COPY_ALERT_MESSAGE */,
                    7011 /* COPY_STATUS_LOST */,
                    7012 /* COPY_STATUS_MISSING */,
                    7013 /* PATRON_EXCEEDS_FINES */
                ] : [],
                'overridable_events' : [
                    null /* custom event */,
                    1203 /* COPY_BAD_STATUS */,
                    1213 /* PATRON_BARRED */,
                    1217 /* PATRON_INACTIVE */,
                    1224 /* PATRON_ACCOUNT_EXPIRED */,
                    1234 /* ITEM_DEPOSIT_PAID */,
                    7009 /* CIRC_CLAIMS_RETURNED */,
                    7010 /* COPY_ALERT_MESSAGE */,
                    7011 /* COPY_STATUS_LOST */,
                    7012 /* COPY_STATUS_MISSING */,
                    7013 /* PATRON_EXCEEDS_FINES */,
                    11103 /* TRANSIT_CHECKIN_INTERVAL_BLOCK */ 
                ],
                'text' : {
                    '1203' : function(r) {
                        return typeof r.payload.status() == 'object' ? r.payload.status().name() : data.hash.ccs[ r.payload.status() ].name();
                    },
                    '1234' : function(r) {
                        return document.getElementById('circStrings').getString('staff.circ.utils.checkin.override.item_deposit_paid.warning');
                    },
                    '7010' : function(r) {
                        return r.payload;
                    }
                }
            }
        );
        if (! async ) {
            return checkin_callback( { 'getResultObject' : function() { return check; } } );
        }


    } catch(E) {
        JSAN.use('util.error'); var error = new util.error();
        error.standard_unexpected_error_alert(document.getElementById('circStrings').getFormattedString('staff.circ.checkin.error', ['2']), E);
        if (typeof params.enable_textbox == 'function') {
            try { params.enable_textbox(); } catch(E) { error.sdump('D_ERROR','params.disable_textbox() = ' + E); };
        }
        return null;
    }
};

circ.util.checkin_via_barcode2 = function(session,params,backdate,auto_print,check) {
    try {
        JSAN.use('util.error'); var error = new util.error();
        JSAN.use('util.network'); var network = new util.network();
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
        JSAN.use('util.date');
        JSAN.use('util.sound'); var sound = new util.sound();

        dump('check = ' + error.pretty_print( js2JSON( check ) ) + '\n' );

        check.message = check.textcode;

        if (check.payload && check.payload.copy) { check.copy = check.payload.copy; }
        if (check.payload && check.payload.volume) { check.volume = check.payload.volume; }
        if (check.payload && check.payload.record) { check.record = check.payload.record; }
        if (check.payload && check.payload.circ) { check.circ = check.payload.circ; }
        if (check.payload && check.payload.patron) { check.patron = check.payload.patron; }

        if (!check.route_to) { check.route_to = '   '; }

        var no_change_label = document.getElementById('no_change_label');

        if (no_change_label) {
            no_change_label.setAttribute('value','');
            no_change_label.setAttribute('hidden','true');
            no_change_label.setAttribute('onclick','');
            removeCSSClass(no_change_label,'click_link');
            no_change_label.setAttribute('unique_row_counter','');
        }

        var msg = '';
        var print_list = [];
        var print_data = { 
            'error' : '',
            'error_msg' : '',
            'cancelled' : '',
            'route_to' : '',
            'route_to_msg' : '',
            'route_to_org_fullname' : '',
            'destination_shelf' : '',
            'destination_shelf_msg' : '',
            'courier_code' : '',
            'street1' : '',
            'street2' : '',
            'city_state_zip' : '',
            'city' : '',
            'state' : '',
            'county' : '',
            'country' : '',
            'post_code' : '',
            'item_barcode' : '',
            'item_barcode_msg' : '',
            'item_title' : '',
            'item_title_msg' : '',
            'item_author' : '',
            'item_author_msg' : '',
            'hold_for_msg' : '',
            'hold_for_alias' : '',
            'hold_for_family_name' : '',
            'hold_for_first_given_name' : '',
            'hold_for_second_given_name' : '',
            'user_barcode' : '',
            'user_barcode_msg' : '',
            'notify_by_phone' : '',
            'notify_by_phone_msg' : '',
            'notify_by_email' : '',
            'notify_by_email_msg' : '',
            'notify_by_text' : '',
            'notify_by_text_msg' : '',
            'request_date' : '',
            'request_date_msg' : '',
            'shelf_expire_time' : '',
            'slip_date' : '',
            'slip_date_msg' : '',
            'user' : '',
            'user_stat_cat_entries' : ''
        };

        if (check.payload && check.payload.cancelled_hold_transit) {
            print_data.cancelled = document.getElementById('circStrings').getString('staff.circ.utils.transit_hold_cancelled');
            msg += print_data.cancelled;
            msg += '\n\n';
        }

        var suppress_popups = data.hash.aous['ui.circ.suppress_checkin_popups'];

        /* SUCCESS  /  NO_CHANGE  /  ITEM_NOT_CATALOGED */
        if (check.ilsevent == 0 || check.ilsevent == 3 || check.ilsevent == 1202) {
            try {
                var acpl = data.lookup('acpl', check.copy.location()); 
                check.route_to = acpl.name();
                check.checkin_alert = isTrue(acpl.checkin_alert()) && !suppress_popups;
            } catch(E) {
                print_data.error_msg = document.getElementById('commonStrings').getString('common.error');
                print_data.error_msg += '\nFIXME: ' + E + '\n';
                msg += print_data.error_msg;
            }
            if (check.ilsevent == 3 /* NO_CHANGE */) {
                //msg = 'This item is already checked in.\n';
                check.what_happened = 'no_change';
                sound.special('checkin.no_change');
                if (no_change_label) {
                    var m = no_change_label.getAttribute('value');
                    var text = document.getElementById('circStrings').getFormattedString('staff.circ.utils.item_checked_in', [params.barcode]);
                    no_change_label.setAttribute('value', m + text + '  ');
                    no_change_label.setAttribute('hidden','false');
                    no_change_label.setAttribute('onclick','');
                    removeCSSClass(no_change_label,'click_link');
                    no_change_label.setAttribute('unique_row_counter','');
                    if (typeof params.info_blurb == 'function') {
                        params.info_blurb( text );
                    }
                }
            }
            if (check.ilsevent == 1202 /* ITEM_NOT_CATALOGED */ && check.copy.status() != 11) {
                check.what_happened = 'error';
                sound.special('checkin.error');
                var copy_status = (data.hash.ccs[ check.copy.status() ] ? data.hash.ccs[ check.copy.status() ].name() : check.copy.status().name() );
                var err_msg = document.getElementById('commonStrings').getString('common.error');
                err_msg += '\nFIXME --';
                err_msg += document.getElementById('circStrings').getFormattedString('staff.circ.utils.item_not_cataloged', [copy_status]);
                err_msg += '\n';
                msg += err_msg;
                print_data.error_msg += err_msg;
            }
            switch(Number(check.copy.status())) {
                case 0: /* AVAILABLE */
                case 7: /* RESHELVING */
                    check.what_happened = 'success';
                    sound.special('checkin.success');
                    if (msg || check.checkin_alert) {
                        print_data.route_to_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.msg', [check.route_to]);
                        print_data.route_to = check.route_to;
                        msg += print_data.route_to_msg;
                        msg += '\n';
                    }
                break;
                case 8: /* ON HOLDS SHELF */
                    check.what_happened = 'hold_shelf';
                    sound.special('checkin.hold_shelf');
                    check.route_to = document.getElementById('circStrings').getString('staff.circ.route_to.hold_shelf');
                    if (check.payload.hold) {
                        if (check.payload.hold.pickup_lib() != data.list.au[0].ws_ou()) {
                            check.what_happened = 'error';
                            sound.special('checkin.error');
                            var err_msg = document.getElementById('commonStrings').getString('common.error');
                            err_msg += '\nFIXME: ';
                            err_msg += document.getElementById('circStrings').getString('staff.circ.utils.route_item_error');
                            err_msg += '\n';
                            msg += err_msg;
                            print_data.error_msg += err_msg;
                        } else {
                            print_data.route_to_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.msg', [check.route_to]);
                            print_data.route_to = check.route_to;
                            var behind_the_desk_support = String( data.hash.aous['circ.holds.behind_desk_pickup_supported'] ) == 'true';
                            if (behind_the_desk_support) {
                               var usr_settings = network.simple_request('FM_AUS_RETRIEVE',[ses(),check.payload.hold.usr()]); 
                                if (typeof usr_settings['circ.holds_behind_desk'] != 'undefined') {
                                    if (usr_settings['circ.holds_behind_desk']) {
                                        print_data.prefer_behind_holds_desk = true;
                                        check.route_to = document.getElementById('circStrings').getString('staff.circ.route_to.private_hold_shelf');
                                        print_data.route_to_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.msg', [check.route_to]);
                                        print_data.route_to = check.route_to;
                                    } else {
                                        check.route_to = document.getElementById('circStrings').getString('staff.circ.route_to.public_hold_shelf');
                                        print_data.route_to_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.msg', [check.route_to]);
                                        print_data.route_to = check.route_to;
                                    }
                                } else {
                                    check.route_to = document.getElementById('circStrings').getString('staff.circ.route_to.public_hold_shelf');
                                    print_data.route_to_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.msg', [check.route_to]);
                                    print_data.route_to = check.route_to;
                                }
                            }
                            print_data.destination_shelf_msg = print_data.route_to_msg;
                            print_data.destination_shelf = print_data.route_to;
                            msg += print_data.route_to_msg;
                            msg += '\n';
                        }
                    } else {
                        check.what_happened = 'error';
                        sound.special('checkin.error');
                        var err_msg = document.getElementById('commonStrings').getString('common.error');
                        err_msg += '\nFIXME: ';
                        err_msg += document.getElementById('circStrings').getString('staff.circ.utils.route_item_status_error');
                        err_msg += '\n';
                        msg += err_msg;
                        print_data.error_msg += err_msg;
                    }
                    JSAN.use('util.date');
                    if (check.payload.hold) {
                        JSAN.use('patron.util');
                        msg += '\n';
                        print_data.item_barcode_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.barcode', [check.payload.copy.barcode()]);
                        print_data.item_barcode = check.payload.copy.barcode();
                        msg += print_data.item_barcode_msg;
                        msg += '\n';
                        var payload_title  = (check.payload.record ? check.payload.record.title() : check.payload.copy.dummy_title() );
                        print_data.item_title_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.title', [payload_title]);
                        print_data.item_title = payload_title;
                        msg += print_data.item_title_msg;
                        msg += '\n';
                        var au_obj = patron.util.retrieve_fleshed_au_via_id( session, check.payload.hold.usr() );
                        print_data.user = au_obj;
                        print_data.user_stat_cat_entries = [];
                        var entries = au_obj.stat_cat_entries();
                        for (var i = 0; i < entries.length; i++) {
                            var stat_cat = data.hash.my_actsc[ entries[i].stat_cat() ];
                            if (!stat_cat) {
                                stat_cat = data.lookup('actsc', entries[i].stat_cat());
                            }
                            print_data.user_stat_cat_entries.push( { 
                                'id' : entries[i].id(),
                                'stat_cat' : {
                                    'id' : stat_cat.id(),
                                    'name' : stat_cat.name(),
                                    'opac_visible' : stat_cat.opac_visible(),
                                    'owner' : stat_cat.owner(),
                                    'usr_summary' : stat_cat.usr_summary()
                                },
                                'stat_cat_entry' : entries[i].stat_cat_entry(),
                                'target_usr' : entries[i].target_usr() 
                            } );
                        }
                        msg += '\n';
                        if (au_obj.alias()) {
                            print_data.hold_for_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.patron_alias',  [au_obj.alias()]);
                            print_data.hold_for_alias = au_obj.alias();
                            msg += print_data.hold_for_msg;
                        } else {
                            print_data.hold_for_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.patron',  [au_obj.family_name() ? au_obj.family_name() : '', au_obj.first_given_name() ? au_obj.first_given_name() : '', au_obj.second_given_name() ? au_obj.second_given_name() : '']);
                            msg += print_data.hold_for_msg;
                            print_data.hold_for_family_name = au_obj.family_name() ? au_obj.family_name() : '';
                            print_data.hold_for_first_given_name = au_obj.first_given_name() ? au_obj.first_given_name() : '';
                            print_data.hold_for_second_given_name = au_obj.second_given_name() ? au_obj.second_given_name() : '';
                        }
                        msg += '\n';
                        print_data.user_barcode_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.barcode', [au_obj.card().barcode()]);
                        print_data.user_barcode = au_obj.card().barcode();
                        msg += print_data.user_barcode_msg;
                        msg += '\n';
                        if (check.payload.hold.phone_notify()) {
                            print_data.notify_by_phone_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.phone_notify', [check.payload.hold.phone_notify()]);
                            print_data.notify_by_phone = check.payload.hold.phone_notify();
                            msg += print_data.notify_by_phone_msg;
                            msg += '\n';
                        }
                        if (check.payload.hold.sms_notify()) {
                            print_data.notify_by_text_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.sms_notify', [check.payload.hold.sms_notify()]);
                            print_data.notify_by_text = check.payload.hold.sms_notify();
                            msg += print_data.notify_by_text_msg;
                            msg += '\n';
                        }
                        if (get_bool(check.payload.hold.email_notify())) {
                            var payload_email = au_obj.email() ? au_obj.email() : '';
                            print_data.notify_by_email_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.email_notify', [payload_email]);
                            print_data.notify_by_email = payload_email;
                            msg += print_data.notify_by_email_msg;
                            msg += '\n';
                        }
                        msg += '\n';
                        var notes = check.payload.hold.notes();
                        print_data.notes_raw = notes;
                        for (var i = 0; i < notes.length; i++) {
                            if ( get_bool( notes[i].slip() ) ) {
                                var temp_msg;
                                if ( get_bool( notes[i].staff() ) ) {
                                    temp_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.notes.staff_note', [ notes[i].title(), notes[i].body() ]);
                                } else {
                                    temp_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.notes.patron_note', [ notes[i].title(), notes[i].body() ]);
                                }
                                msg += temp_msg + '\n';
                                print_list.push(
                                    {
                                        'formatted_note' : temp_msg,
                                        'note_title' : notes[i].title(),
                                        'note_body' : notes[i].body(),
                                        'note_public' : notes[i].pub(),
                                        'note_by_staff' : notes[i].staff()
                                    }
                                );
                            }
                        }
                        msg += '\n';
                        msg += '\n';
                        print_data.request_date = util.date.formatted_date(check.payload.hold.request_time(),'%F');
                        print_data.request_date_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.request_date', [print_data.request_date]);
                        print_data.shelf_expire_time = check.payload.hold.shelf_expire_time();
                        msg += print_data.request_date_msg;
                        msg += '\n';
                    }
                    var rv = 0;
                    if (suppress_popups) {
                        rv = auto_print ? 0 : -1; auto_print = true; // skip dialog and PRINT or DO NOT PRINT based on Auto-Print checkbox
                    }
                    var x = data.hash.aous['circ.staff_client.do_not_auto_attempt_print'];
                    var no_print_prompting = x ? ( x.indexOf( "Hold Slip" ) > -1) : false;
                    if (no_print_prompting) {
                        rv = -1; auto_print = true; // DO NOT PRINT and skip dialog
                    }
                    print_data.slip_date = util.date.formatted_date(new Date(),'%F');
                    print_data.slip_date_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.slip_date', [print_data.slip_date]);
                    msg += print_data.slip_date_msg;
                    msg += '\n';
                    print_data.payload = check.payload;

                    if (!auto_print) {
                        rv = error.yns_alert_formatted(
                            msg,
                            document.getElementById('circStrings').getString('staff.circ.utils.hold_slip'),
                            document.getElementById('circStrings').getString('staff.circ.utils.hold_slip.print.yes'),
                            document.getElementById('circStrings').getString('staff.circ.utils.hold_slip.print.no'),
                            null,
                            document.getElementById('circStrings').getString('staff.circ.confirm.msg'),
                            '/xul/server/skin/media/images/turtle.gif'
                        );
                    } else {
                        if (suppress_popups && !no_print_prompting) {
                            // FIXME: Add SFX and/or GFX
                            sound.circ_bad();
                        }
                    }
                    if (rv == 0) {
                        try {
                            JSAN.use('util.print'); var print = new util.print();
                            var old_template = String( data.hash.aous['ui.circ.old_harcoded_slip_template'] ) == 'true';
                            if (old_template) {
                                msg = msg.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g,'<br/>');
                                print.simple( msg , { 'no_prompt' : true, 'content_type' : 'text/html' } );
                            } else {
                                var template = 'hold_slip';
                                var parms = {
                                    'patron' : print_data.user,
                                    'lib' : data.hash.aou[ check.payload.hold.pickup_lib() ],
                                    'staff' : data.list.au[0],
                                    'header' : data.print_list_templates[ template ].header,
                                    'line_item' : data.print_list_templates[ template ].line_item,
                                    'footer' : data.print_list_templates[ template ].footer,
                                    'type' : data.print_list_templates[ template ].type,
                                    'list' : print_list,
                                    'data' : print_data,
                                    'context' : data.print_list_templates[ template ].context,
                                };
                                if ($('printer_prompt')) {
                                    if (! $('printer_prompt').checked) { parms.no_prompt = true; }
                                }
                                print.tree_list( parms );
                            }
                        } catch(E) {
                            var err_msg = document.getElementById('commonStrings').getString('common.error');
                            err_msg += '\nFIXME: ' + E + '\n';
                            dump(err_msg);
                            alert(err_msg);
                        }
                    }
                    msg = '';
                    if (no_change_label) {
                        var m = no_change_label.getAttribute('value');
                        var text = document.getElementById('circStrings').getFormattedString('staff.circ.utils.capture', [params.barcode]);
                        m += text + '  ';
                        no_change_label.setAttribute('value', m);
                        no_change_label.setAttribute('hidden','false');
                        no_change_label.setAttribute('onclick','');
                        removeCSSClass(no_change_label,'click_link');
                        no_change_label.setAttribute('unique_row_counter','');
                        if (typeof params.info_blurb == 'function') {
                            params.info_blurb( text );
                        }
                    }
                break;
                case 6: /* IN TRANSIT */
                    check.what_happened = 'error';
                    sound.special('checkin.error');
                    check.route_to = 'TRANSIT SHELF??';
                    print_data.route_to;
                    var err_msg = document.getElementById('commonStrings').getString('common.error');
                    err_msg += "\nFIXME -- I didn't think we could get here.\n";
                    print_data.error_msg += err_msg;
                    msg += err_msg;
                break;
                case 11: /* CATALOGING */
                    check.what_happened = 'cataloging';
                    sound.special('checkin.cataloging');
                    check.route_to = 'CATALOGING';
                    print_data.route_to;
                    var x = document.getElementById('do_not_alert_on_precat');
                    var do_not_alert_on_precats = x ? ( x.getAttribute('checked') == 'true' ) : false;
                    if ( !suppress_popups && !do_not_alert_on_precats ) {
                        print_data.route_to_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.msg', [check.route_to]);
                        msg += print_data.route_to_msg;
                    } else {
                        if (suppress_popups && !do_not_alert_on_precats) {
                            // FIXME: add SFX and/or GFX
                            sound.circ_bad();
                        }
                    }
                    if (no_change_label) {
                        var m = no_change_label.getAttribute('value');
                        var needs_cat = document.getElementById('circStrings').getFormattedString('staff.circ.utils.needs_cataloging', [params.barcode]);
                        no_change_label.setAttribute('value', m + needs_cat + '  ');
                        no_change_label.setAttribute('hidden','false');
                        no_change_label.setAttribute('onclick','');
                        removeCSSClass(no_change_label,'click_link');
                        no_change_label.setAttribute('unique_row_counter','');
                        if (typeof params.info_blurb == 'function') {
                            params.info_blurb( needs_cat );
                        }
                    }
                break;
                case 15: // ON_RESERVATION_SHELF
                    check.route_to = 'RESERVATION SHELF';
                    check.what_happened = "reservation_shelf";
                    sound.special('checkin.reservation_shelf');
                    if (check.payload.reservation) {
                        if (check.payload.reservation.pickup_lib() != data.list.au[0].ws_ou()) {
                            msg += document.getElementById('commonStrings').getString('common.error');
                            msg += '\nFIXME: ';
                            msg += document.getElementById('circStrings').getString('staff.circ.utils.route_item_error');
                            msg += '\n';
                        } else {
                            msg += document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.msg', [check.route_to]);
                            msg += '.\n';
                        }
                    } else {
                        msg += document.getElementById('commonStrings').getString('common.error');
                        msg += '\nFIXME: ';
                        msg += document.getElementById('circStrings').getString('staff.circ.utils.reservation_status_error');
                        msg += '\n';
                    }
                    JSAN.use('util.date');
                    if (check.payload.reservation) {
                        JSAN.use('patron.util');
                        msg += '\n';
                        msg += document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.reservation.barcode', [check.payload.copy.barcode()]);
                        msg += '\n';
                        var payload_title  = (check.payload.record ? check.payload.record.title() : check.payload.copy.dummy_title() );
                        msg += document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.reservation.title', [payload_title]);
                        msg += '\n';
                        var au_obj =
                            typeof(check.payload.reservation.usr().card) == "function" ?
                                check.payload.reservation.usr() :
                                patron.util.retrieve_fleshed_au_via_id(session, check.payload.reservation.usr());
                        msg += '\n';
                        if (au_obj.alias()) {
                            msg += document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.reservation.patron_alias',  [au_obj.alias()]);
                        } else {
                            msg += document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.reservation.patron',  [au_obj.family_name() || "", au_obj.first_given_name() || "", au_obj.second_given_name() || ""]);
                        }
                        msg += '\n';
                        msg += document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.reservation.barcode', [au_obj.card().barcode()]);
                        msg += '\n';
                        msg += document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.reservation.request_date', [util.date.formatted_date(check.payload.reservation.request_time(),'%F %H:%M')]);
                        msg += '\n';

                        msg += document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.reservation.start_date', [util.date.formatted_date(check.payload.reservation.start_time(),'%F %H:%M')]);
                        msg += '\n';
                    }
                    var rv = 0;
                    msg += document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.reservation.slip_date', [util.date.formatted_date(new Date(),'%F')]);
                    msg += '\n';
                    if (!auto_print) {
                        rv = error.yns_alert_formatted(
                            msg,
                            document.getElementById('circStrings').getString('staff.circ.utils.reservation_slip'),
                            document.getElementById('circStrings').getString('staff.circ.utils.reservation_slip.print.yes'),
                            document.getElementById('circStrings').getString('staff.circ.utils.reservation_slip.print.no'),
                            null,
                            document.getElementById('circStrings').getString('staff.circ.confirm.msg'),
                            '/xul/server/skin/media/images/turtle.gif'
                        );
                    }
                    if (rv == 0) {
                        try {
                            JSAN.use('util.print'); var print = new util.print();
                            msg = msg.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g,'<br/>');
                            print.simple( msg , { 'no_prompt' : true, 'content_type' : 'text/html' } );
                        } catch(E) {
                            var err_msg = document.getElementById('commonStrings').getString('common.error');
                            err_msg += '\nFIXME: ' + E + '\n';
                            dump(err_msg);
                            alert(err_msg);
                        }
                    }
                    msg = '';
                    if (no_change_label) {
                        var m = no_change_label.getAttribute('value');
                        var text = document.getElementById('circStrings').getFormattedString('staff.circ.utils.reservation_capture', [params.barcode]);
                        m += text + '  ';
                        no_change_label.setAttribute('value', m);
                        no_change_label.setAttribute('hidden','false');
                        no_change_label.setAttribute('onclick','');
                        removeCSSClass(no_change_label,'click_link');
                        no_change_label.setAttribute('unique_row_counter','');
                        if (typeof params.info_blurb == 'function') {
                            params.info_blurb( text );
                        }
                    }
                break;
                default:
                    check.what_happened = 'error';
                    sound.special('checkin.error');
                    msg += document.getElementById('commonStrings').getString('common.error');
                    var copy_status = data.hash.ccs[check.copy.status()] ? data.hash.ccs[check.copy.status()].name() : check.copy.status().name();
                    msg += '\n';
                    var error_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.copy_status.error', [copy_status]);
                    print_data.error_msg += error_msg;
                    msg += error_msg;
                    msg += '\n';
                    print_data.route_to_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.msg', [check.route_to]);
                    msg += print_data.route_to_msg;
                break;
            }
            if (msg) {
                error.yns_alert(
                    msg,
                    document.getElementById('circStrings').getString('staff.circ.alert'),
                    null,
                    document.getElementById('circStrings').getString('staff.circ.utils.msg.ok'),
                    null,
                    document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                );
            }
        } else /* ROUTE_ITEM */ if (check.ilsevent == 7000) {

            check.what_happened = 'transit';
            sound.special('checkin.transit');
            var lib = data.hash.aou[ check.org ];
            check.route_to = lib.shortname();
            print_data.route_to = check.route_to;
            print_data.route_to_org = lib;
            print_data.route_to_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.destination', [check.route_to]);
            print_data.route_to_org_fullname = lib.name();
            var aous_req = network.simple_request('FM_AOUS_SPECIFIC_RETRIEVE',[ lib.id(), 'lib.courier_code' ]);
            if (aous_req) {
                print_data.courier_code = aous_req.value || '';
            }
            msg += print_data.route_to_msg;
            msg += '\n\n';
            msg += lib.name();
            msg += '\n';
            try {
                if (lib.holds_address() ) {
                    var a = network.simple_request('FM_AOA_RETRIEVE',[ lib.holds_address() ]);
                    if (typeof a.ilsevent != 'undefined') throw(a);
                    if (a.street1()) { msg += a.street1() + '\n'; print_data.street1 = a.street1(); }
                    if (a.street2()) { msg += a.street2() + '\n'; print_data.street2 = a.street2(); }
                    print_data.city_state_zip = (a.city() ? a.city() + ', ' : '') + (a.state() ? a.state() + ' ' : '') + (a.post_code() ? a.post_code() : '');
                    print_data.city = a.city();
                    print_data.state = a.state();
                    print_data.county = a.county();
                    print_data.country = a.country();
                    print_data.post_code = a.post_code();
                    msg += print_data.city_state_zip + '\n';
                } else {
                    print_data.street1 = document.getElementById('circStrings').getString('staff.circ.utils.route_to.no_address');
                    print_data.no_address = true;
                    msg += print_data.street1;
                    msg += '\n';
                }
            } catch(E) {
                var err_msg = document.getElementById('circStrings').getString('staff.circ.utils.route_to.no_address.error');
                print_data.error_msg += err_msg + '\n';
                msg += err_msg + '\n';
                error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.utils.route_to.no_address.error'), E);
            }
            msg += '\n';
            print_data.item_barcode_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.barcode', [check.payload.copy.barcode()]);
            print_data.item_barcode = check.payload.copy.barcode();
            msg += print_data.item_barcode_msg;
            msg += '\n';
            var payload_title  = (check.payload.record ? check.payload.record.title() : check.payload.copy.dummy_title() );
            print_data.item_title_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.title', [payload_title]);
            print_data.item_title = payload_title;
            msg += print_data.item_title_msg;
            msg += '\n';
            var payload_author = (check.payload.record ? check.payload.record.author() :check.payload.copy.dummy_author());
            print_data.item_author_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.author', [payload_author]);
            print_data.item_author = payload_author;
            msg += print_data.item_author_msg;
            msg += '\n';
            JSAN.use('util.date');
            if (check.payload.hold) {
                check.what_happened = 'transit_for_hold';
                sound.special('checkin.transit_for_hold');
                JSAN.use('patron.util');
                var au_obj = patron.util.retrieve_fleshed_au_via_id( session, check.payload.hold.usr() );
                print_data.user = au_obj;
                print_data.user_stat_cat_entries = [];
                var entries = au_obj.stat_cat_entries();
                for (var i = 0; i < entries.length; i++) {
                    var stat_cat = data.hash.my_actsc[ entries[i].stat_cat() ];
                    if (!stat_cat) {
                        stat_cat = data.lookup('actsc', entries[i].stat_cat());
                    }
                    print_data.user_stat_cat_entries.push( { 
                        'id' : entries[i].id(),
                        'stat_cat' : {
                            'id' : stat_cat.id(),
                            'name' : stat_cat.name(),
                            'opac_visible' : stat_cat.opac_visible(),
                            'owner' : stat_cat.owner(),
                            'usr_summary' : stat_cat.usr_summary()
                        },
                        'stat_cat_entry' : entries[i].stat_cat_entry(),
                        'target_usr' : entries[i].target_usr() 
                    } );
                }
                msg += '\n';
                if (au_obj.alias()) {
                    print_data.hold_for_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.patron_alias',  [au_obj.alias()]);
                    print_data.hold_for_alias = au_obj.alias();
                    msg += print_data.hold_for_msg;
                } else {
                    print_data.hold_for_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.patron',  [au_obj.family_name() ? au_obj.family_name() : '', au_obj.first_given_name() ? au_obj.first_given_name() : '', au_obj.second_given_name() ? au_obj.second_given_name() : '']);
                    msg += print_data.hold_for_msg;
                    print_data.hold_for_family_name = au_obj.family_name() ? au_obj.family_name() : '';
                    print_data.hold_for_first_given_name = au_obj.first_given_name() ? au_obj.first_given_name() : '';
                    print_data.hold_for_second_given_name = au_obj.second_given_name() ? au_obj.second_given_name() : '';
                }
                msg += '\n';
                print_data.user_barcode_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.barcode', [au_obj.card().barcode()]);
                print_data.user_barcode = au_obj.card().barcode();
                msg += print_data.user_barcode_msg;
                msg += '\n';
                if (check.payload.hold.phone_notify()) {
                    print_data.notify_by_phone_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.phone_notify', [check.payload.hold.phone_notify()]);
                    print_data.notify_by_phone = check.payload.hold.phone_notify();
                    msg += print_data.notify_by_phone_msg;
                    msg += '\n';
                }
                if (check.payload.hold.sms_notify()) {
                    print_data.notify_by_text_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.sms_notify', [check.payload.hold.sms_notify()]);
                    print_data.notify_by_text = check.payload.hold.sms_notify();
                    msg += print_data.notify_by_text_msg;
                    msg += '\n';
                }
                if (get_bool(check.payload.hold.email_notify())) {
                    var payload_email = au_obj.email() ? au_obj.email() : '';
                    print_data.notify_by_email_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.email_notify', [payload_email]);
                    print_data.notify_by_email = payload_email;
                    msg += print_data.notify_by_email_msg;
                    msg += '\n';
                }
                msg += '\n';
                var notes = check.payload.hold.notes();
                print_data.notes_raw = notes;
                for (var i = 0; i < notes.length; i++) {
                    if ( get_bool( notes[i].slip() ) ) {
                        var temp_msg;
                        if ( get_bool( notes[i].staff() ) ) {
                            temp_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.notes.staff_note', [ notes[i].title(), notes[i].body() ]);
                        } else {
                            temp_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.notes.patron_note', [ notes[i].title(), notes[i].body() ]);
                        }
                        msg += temp_msg + '\n';
                        print_list.push(
                            {
                                'formatted_note' : temp_msg,
                                'note_title' : notes[i].title(),
                                'note_body' : notes[i].body(),
                                'note_public' : notes[i].pub(),
                                'note_by_staff' : notes[i].staff()
                            }
                        );
                    }
                }
                msg += '\n';
                msg += '\n';
                print_data.request_date = util.date.formatted_date(check.payload.hold.request_time(),'%F');
                print_data.request_date_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.request_date', [print_data.request_date]);
                msg += print_data.request_date_msg;
                msg += '\n';
                var destination_shelf = document.getElementById('circStrings').getString('staff.circ.route_to.hold_shelf');
                print_data.destination_shelf_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.msg', [destination_shelf]);
                print_data.destination_shelf = destination_shelf;
                var behind_the_desk_support = String( data.hash.aous['circ.holds.behind_desk_pickup_supported'] ) == 'true';
                if (behind_the_desk_support) {
                   var usr_settings = network.simple_request('FM_AUS_RETRIEVE',[ses(),check.payload.hold.usr()]); 
                    if (typeof usr_settings['circ.holds_behind_desk'] != 'undefined') {
                        if (usr_settings['circ.holds_behind_desk']) {
                            print_data.prefer_behind_holds_desk = true;
                            destination_shelf = document.getElementById('circStrings').getString('staff.circ.route_to.private_hold_shelf');
                            print_data.destination_shelf_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.msg', [destination_shelf]);
                            print_data.destination_shelf = destination_shelf;
                        } else {
                            destination_shelf = document.getElementById('circStrings').getString('staff.circ.route_to.public_hold_shelf');
                            print_data.destination_shelf_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.msg', [destination_shelf]);
                            print_data.destination_shelf = destination_shelf;
                        }
                    } else {
                        destination_shelf = document.getElementById('circStrings').getString('staff.circ.route_to.public_hold_shelf');
                        print_data.destination_shelf_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.route_to.msg', [destination_shelf]);
                        print_data.destination_shelf = destination_shelf;
                    }
                }
            }
            var rv = 0;
            if (suppress_popups) {
                rv = auto_print ? 0 : -1; auto_print = true; // skip dialog and PRINT or DO NOT PRINT based on Auto-Print checkbox
            }
            var x = data.hash.aous['circ.staff_client.do_not_auto_attempt_print'];
            var no_print_prompting = x ? (x.indexOf( check.payload.hold ? "Hold/Transit Slip" : "Transit Slip" ) > -1) : false;
            if (no_print_prompting) {
                rv = -1; auto_print = true; // DO NOT PRINT and skip dialog
            }
            print_data.slip_date = util.date.formatted_date(new Date(),'%F');
            print_data.slip_date_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.hold.slip_date', [print_data.slip_date]);
            msg += print_data.slip_date_msg;
            print_data.payload = check.payload;

            if (!auto_print) {
                rv = error.yns_alert_formatted(
                    msg,
                    document.getElementById('circStrings').getString('staff.circ.utils.transit_slip'),
                    document.getElementById('circStrings').getString('staff.circ.utils.transit_slip.print.yes'),
                    document.getElementById('circStrings').getString('staff.circ.utils.transit_slip.print.no'),
                    null,
                    document.getElementById('circStrings').getString('staff.circ.confirm.msg'),
                    '/xul/server/skin/media/images/turtle.gif'
                );
            } else {
                if (suppress_popups && !no_print_prompting) {
                    // FIXME: add SFX and/or GFX
                    sound.circ_bad();
                }
            }
            if (rv == 0) {
                try {
                    JSAN.use('util.print'); var print = new util.print();
                    var old_template = String( data.hash.aous['ui.circ.old_harcoded_slip_template'] ) == 'true';
                    if (old_template) {
                        msg = msg.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g,'<br/>');
                        print.simple( msg , { 'no_prompt' : true, 'content_type' : 'text/html' } );
                    } else {
                        var template = check.payload.hold ? 'hold_transit_slip' : 'transit_slip';
                        var parms = {
                            'patron' : print_data.user,
                            'lib' : data.hash.aou[ data.list.au[0].ws_ou() ],
                            'staff' : data.list.au[0],
                            'header' : data.print_list_templates[ template ].header,
                            'line_item' : data.print_list_templates[ template ].line_item,
                            'footer' : data.print_list_templates[ template ].footer,
                            'type' : data.print_list_templates[ template ].type,
                            'list' : print_list,
                            'data' : print_data,
                            'context' : data.print_list_templates[ template ].context,
                        };
                        if ($('printer_prompt')) {
                            if (! $('printer_prompt').checked) { parms.no_prompt = true; }
                        }
                        print.tree_list( parms );
                    }
                } catch(E) {
                    var err_msg = document.getElementById('commonStrings').getString('common.error');
                    err_msg += '\nFIXME: ' + E + '\n';
                    dump(err_msg);
                    alert(err_msg);
                }
            }
            if (no_change_label) {
                var m = no_change_label.getAttribute('value');
                var trans_msg = document.getElementById('circStrings').getFormattedString('staff.circ.utils.payload.in_transit', [params.barcode]);
                no_change_label.setAttribute('value', m + trans_msg + '  ');
                no_change_label.setAttribute('hidden','false');
                no_change_label.setAttribute('onclick','');
                removeCSSClass(no_change_label,'click_link');
                no_change_label.setAttribute('unique_row_counter','');
                if (typeof params.info_blurb == 'function') {
                    params.info_blurb( trans_msg );
                }
            }

        } else /* ASSET_COPY_NOT_FOUND */ if (check.ilsevent == 1502) {

            check.what_happened = 'not_found';
            sound.special('checkin.not_found');
            check.route_to = 'CATALOGING';
            var mis_scan_msg = document.getElementById('circStrings').getFormattedString('staff.circ.copy_status.status.copy_not_found', [params.barcode]);
            if (!suppress_popups) {
                error.yns_alert(
                    mis_scan_msg,
                    document.getElementById('circStrings').getString('staff.circ.alert'),
                    null,
                    document.getElementById('circStrings').getString('staff.circ.utils.msg.ok'),
                    null,
                    document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                );
            } else {
                // FIXME: add SFX and/or GFX
                sound.circ_bad();
            }
            if (no_change_label) {
                var m = no_change_label.getAttribute('value');
                no_change_label.setAttribute('value',m + mis_scan_msg + '  ');
                no_change_label.setAttribute('hidden','false');
                no_change_label.setAttribute('onclick','');
                removeCSSClass(no_change_label,'click_link');
                no_change_label.setAttribute('unique_row_counter','');
                if (typeof params.info_blurb == 'function') {
                    params.info_blurb( mis_scan_msg );
                }
            }

        } else /* HOLD_CAPTURE_DELAYED */ if (check.ilsevent == 7019) {

            check.what_happened = 'hold_capture_delayed';
            sound.special('checkin.hold_capture_delayed');
            var rv = 0;
            msg += document.getElementById('circStrings').getString('staff.circ.utils.hold_capture_delayed.description');
            if (!suppress_popups) {
                rv = error.yns_alert_formatted(
                    msg,
                    document.getElementById('circStrings').getString('staff.circ.utils.hold_capture_delayed.titlebar'),
                    document.getElementById('circStrings').getString('staff.circ.utils.hold_capture_delayed.prompt_for_nocapture'),
                    document.getElementById('circStrings').getString('staff.circ.utils.hold_capture_delayed.prompt_for_capture'),
                    null,
                    document.getElementById('circStrings').getString('staff.circ.confirm.msg'),
                    '/xul/server/skin/media/images/stop_sign.png'
                );
            } else {
                // FIXME: add SFX and/or GFX
                sound.circ_bad();
            }
            params.capture = rv == 0 ? 'nocapture' : 'capture';

            return circ.util.checkin_via_barcode(session,params,backdate,auto_print,false);

        } else /* NETWORK TIMEOUT */ if (check.ilsevent == -1) {
            check.what_happened = 'error';
            sound.special('checkin.error');
            error.standard_network_error_alert(document.getElementById('circStrings').getString('staff.circ.checkin.suggest_offline'));
        } else {

            if (check.ilsevent == null) { return null; /* handled */ }
            switch (Number(check.ilsevent)) {
                case 1203 /* COPY_BAD_STATUS */ :
                case 1213 /* PATRON_BARRED */ :
                case 1217 /* PATRON_INACTIVE */ :
                case 1224 /* PATRON_ACCOUNT_EXPIRED */ :
                case 1234 /* ITEM_DEPOSIT_PAID */ :
                case 7009 /* CIRC_CLAIMS_RETURNED */ :
                case 7010 /* COPY_ALERT_MESSAGE */ :
                case 7011 /* COPY_STATUS_LOST */ :
                case 7012 /* COPY_STATUS_MISSING */ :
                case 7013 /* PATRON_EXCEEDS_FINES */ :
                    return null; /* handled */
                break;
            }

            throw(check);

        }

        return check;
    } catch(E) {
        JSAN.use('util.error'); var error = new util.error();
        error.standard_unexpected_error_alert(document.getElementById('circStrings').getFormattedString('staff.circ.checkin.error', ['3']), E);
        return null;
    }
};

circ.util.renew_via_barcode = function ( params, async ) {
    try {
        var obj = {};
        JSAN.use('util.network'); obj.network = new util.network();
        JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.stash_retrieve();

        function renew_callback(req) {
            try {
                JSAN.use('util.error'); var error = new util.error();
                var renew = req.getResultObject();
                if (typeof renew.ilsevent != 'undefined') renew = [ renew ];
                for (var j = 0; j < renew.length; j++) {
                    switch(renew[j].ilsevent == null ? null : Number(renew[j].ilsevent)) {
                        case 0 /* SUCCESS */ : break;
                        case null /* custom event */ : break;
                        case 5000 /* PERM_FAILURE */: break;
                        case 1212 /* PATRON_EXCEEDS_OVERDUE_COUNT */ : break;
                        case 1213 /* PATRON_BARRED */ : break;
                        case 1215 /* CIRC_EXCEEDS_COPY_RANGE */ : break;
                        case 1224 /* PATRON_ACCOUNT_EXPIRED */ : break;
                        case 1232 /* ITEM_DEPOSIT_REQUIRED */ : break;
                        case 1233 /* ITEM_RENTAL_FEE_REQUIRED */ : break;
                        case 1234 /* ITEM_DEPOSIT_PAID */ : break;
                        case 1500 /* ACTION_CIRCULATION_NOT_FOUND */ : break;
                        case 1502 /* ASSET_COPY_NOT_FOUND */ : 
                            var mis_scan_msg = document.getElementById('circStrings').getFormattedString('staff.circ.copy_status.status.copy_not_found', [params.barcode]);
                            error.yns_alert(
                                mis_scan_msg,
                                document.getElementById('circStrings').getString('staff.circ.alert'),
                                null,
                                document.getElementById('circStrings').getString('staff.circ.utils.msg.ok'),
                                null,
                                document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                            );
                            if (no_change_label) {
                                var m = no_change_label.getAttribute('value');
                                no_change_label.setAttribute('value',m + mis_scan_msg + '  ');
                                no_change_label.setAttribute('hidden','false');
                                no_change_label.setAttribute('onclick','');
                                removeCSSClass(no_change_label,'click_link');
                                no_change_label.setAttribute('unique_row_counter','');
                                if (typeof params.info_blurb == 'function') {
                                    params.info_blurb( mis_scan_msg );
                                }
                            }
                        break;
                        case 7002 /* PATRON_EXCEEDS_CHECKOUT_COUNT */ : break;
                        case 7003 /* COPY_CIRC_NOT_ALLOWED */ : break;
                        case 7004 /* COPY_NOT_AVAILABLE */ : break;
                        case 7006 /* COPY_IS_REFERENCE */ : break;
                        case 7007 /* COPY_NEEDED_FOR_HOLD */ : break;
                        case 7008 /* MAX_RENEWALS_REACHED */ : break;
                        case 7009 /* CIRC_CLAIMS_RETURNED */ : break;
                        case 7010 /* COPY_ALERT_MESSAGE */ : break;
                        case 7013 /* PATRON_EXCEEDS_FINES */ : break;
                        default:
                            throw(renew);
                        break;
                    }
                }
                try {
                    var ibarcode = renew[0].payload.copy ? renew[0].payload.copy.barcode() : params.barcode;
                    var p_id = renew[0].payload.patron ? renew[0].payload.patron.id() : renew[0].payload.circ.usr();
                    var pname; var pbarcode; 
                    if (renew[0].patron) {
                        pname = renew[0].payload.patron.family_name();
                        pbarcode = typeof renew[0].payload.patron.card() == 'object' ? renew[0].payload.patron.card().barcode() : null;
                    } else {
                        if (circ.util.renew_via_barcode.last_usr_id == p_id) {
                            pname = circ.util.renew_via_barcode.last_pname;
                            pbarcode = circ.util.renew_via_barcode.last_pbarcode;
                        } else {
                            JSAN.use('patron.util'); var p = patron.util.retrieve_fleshed_au_via_id(ses(),p_id);
                            pname = p.family_name();
                            pbarcode = typeof p.card() == 'object' ? p.card().barcode() : null;
                            if (pname) {
                                circ.util.renew_via_barcode.last_usr_id = p_id;
                                circ.util.renew_via_barcode.last_pname = pname;
                                circ.util.renew_via_barcode.last_pbarcode = pbarcode;
                            }
                        } 
                    }
                    error.work_log(
                        document.getElementById('circStrings').getFormattedString(
                            'staff.circ.work_log_renew.message',
                            [
                                ses('staff_usrname'),
                                pname ? pname : '???',
                                pbarcode ? pbarcode : '???',
                                ibarcode ? ibarcode : '???'
                            ]
                        ), {
                            'au_id' : p_id,
                            'au_family_name' : pname,
                            'au_barcode' : pbarcode,
                            'acp_barcode' : ibarcode
                        }
                    );
                } catch(E) {
                    error.sdump('D_ERROR','Error with work_logging in server/circ/util.js, renew_via_barcode():' + E);
                }
                if (typeof async == 'function') async(renew);
                return renew;
            } catch(E) {
                JSAN.use('util.error'); var error = new util.error();
                error.standard_unexpected_error_alert(document.getElementById('circStrings').getFormattedString('staff.circ.checkin.renew_failed.error', [params.barcode]), E);
                return null;
            }
        }

        var renew = obj.network.simple_request(
            'CHECKOUT_RENEW',
            [ ses(), params ],
            async ? renew_callback : null,
            {
                'title' : document.getElementById('circStrings').getString('staff.circ.checkin.renew_failed.override'),
                'overridable_events' : [
                    null /* custom event */,
                    1212 /* PATRON_EXCEEDS_OVERDUE_COUNT */,
                    1213 /* PATRON_BARRED */,
                    1215 /* CIRC_EXCEEDS_COPY_RANGE */,
                    1232 /* ITEM_DEPOSIT_REQUIRED */,
                    1233 /* ITEM_RENTAL_FEE_REQUIRED */,
                    1234 /* ITEM_DEPOSIT_PAID */,
                    7002 /* PATRON_EXCEEDS_CHECKOUT_COUNT */,
                    7003 /* COPY_CIRC_NOT_ALLOWED */,
                    7004 /* COPY_NOT_AVAILABLE */,
                    7006 /* COPY_IS_REFERENCE */,
                    7007 /* COPY_NEEDED_FOR_HOLD */,
                    7008 /* MAX_RENEWALS_REACHED */,
                    7009 /* CIRC_CLAIMS_RETURNED */,
                    7010 /* COPY_ALERT_MESSAGE */,
                    7013 /* PATRON_EXCEEDS_FINES */,
                ],
                'text' : {
                    '1212' : function(r) { return document.getElementById('circStrings').getFormattedString('staff.circ.renew.barcode', [params.barcode]); },
                    '1213' : function(r) { return document.getElementById('circStrings').getFormattedString('staff.circ.renew.barcode', [params.barcode]); },
                    '1215' : function(r) { return document.getElementById('circStrings').getFormattedString('staff.circ.renew.barcode', [params.barcode]); },
                    '1232' : function(r) {
                        return document.getElementById('circStrings').getFormattedString('staff.circ.renew.override.item_deposit_required.warning.barcode', [params.barcode]);
                    },
                    '1233' : function(r) {
                        return document.getElementById('circStrings').getFormattedString('staff.circ.renew.override.item_rental_fee_required.warning.barcode', [params.barcode]);
                    },
                    '1234' : function(r) {
                        return document.getElementById('circStrings').getFormattedString('staff.circ.utils.checkin.override.item_deposit_paid.warning');
                    },
                    '7002' : function(r) { return document.getElementById('circStrings').getFormattedString('staff.circ.renew.barcode', [params.barcode]); },
                    '7003' : function(r) { return document.getElementById('circStrings').getFormattedString('staff.circ.renew.barcode', [params.barcode]); },
                    '7004' : function(r) {
                        return document.getElementById('circStrings').getFormattedString('staff.circ.renew.barcode.status', [params.barcode, typeof r.payload.status() == 'object' ? r.payload.status().name() : obj.data.hash.ccs[ r.payload.status() ].name()]);
                    },
                    '7006' : function(r) { return document.getElementById('circStrings').getFormattedString('staff.circ.renew.barcode', [params.barcode]); },
                    '7007' : function(r) { return document.getElementById('circStrings').getFormattedString('staff.circ.renew.barcode', [params.barcode]); },
                    '7008' : function(r) { return document.getElementById('circStrings').getFormattedString('staff.circ.renew.barcode', [params.barcode]); },
                    '7009' : function(r) { return document.getElementById('circStrings').getFormattedString('staff.circ.renew.barcode', [params.barcode]); },
                    '7010' : function(r) {
                        return document.getElementById('circStrings').getFormattedString('staff.circ.renew.barcode.msg', [params.barcode, r.payload]);
                    },
                    '7013' : function(r) { return document.getElementById('circStrings').getFormattedString('staff.circ.renew.barcode', [params.barcode]); }
                }
            }
        );
        if (! async ) {
            return renew_callback( { 'getResultObject' : function() { return renew; } } );
        }

    } catch(E) {
        JSAN.use('util.error'); var error = new util.error();
        error.standard_unexpected_error_alert(document.getElementById('circStrings').getFormattedString('staff.circ.checkin.renew_failed.error', [params.barcode]), E);
        return null;
    }
};

circ.util.batch_hold_update = function ( hold_ids, field_changes, params ) {
    try {
        JSAN.use('util.sound'); var sound = new util.sound();
        var change_list = []; var idx = -1; var bad_holds = [];
        dojo.forEach(
            hold_ids,
            function(el) {
                change_list.push( function(id,fc){ var clone = JSON2js(js2JSON(fc)); clone.id = id; return clone; }(el,field_changes) ); // Is there a better way to do this?
            }
        );
        if (params.progressmeter) { params.progressmeter.value = 0; params.progressmeter.hidden = false; }
        fieldmapper.standardRequest(
            [ api.FM_AHR_UPDATE_BATCH.app, api.FM_AHR_UPDATE_BATCH.method ],
            {   async: true,
                params: [ses(), null, change_list],
                onresponse: function(r) {
                    idx++; 
                    if (params.progressmeter) { params.progressmeter.value = Number( params.progressmeter.value ) + 100/hold_ids.length; }
                    var result = r.recv().content();
                    if (result != hold_ids[ idx ]) {
                        bad_holds.push( { 'hold_id' : hold_ids[ idx ], 'result' : result } );
                    }
                },
                oncomplete: function() {
                    if (bad_holds.length > 0) {
                        sound.circ_bad();
                        alert( $('circStrings').getFormattedString('staff.circ.hold_update.hold_ids.failed',[ bad_holds.length ]) );
                    } else {
                        sound.circ_good();
                    }
                    if (typeof params.oncomplete == 'function') {
                        params.oncomplete( bad_holds );
                    }
                    if (params.progressmeter) { params.progressmeter.value = 0; params.progressmeter.hidden = true; }
                },
                onerror: function(r) {
                    alert('Error in circ/util.js, batch_hold_update(), onerror: ' + r);
                }
            }
        );
    } catch(E) {
        alert('Error in circ.util.js, circ.util.batch_hold_update(): ' + E);
    }
};

circ.util.find_acq_po = function(session, copy_id) {
    dojo.require("openils.Util");
    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.lineitem.retrieve.by_copy_id.authoritative"], {
            "params": [session, copy_id, {"clear_marc": true}],
            "onresponse": function(r) {
                if (r = openils.Util.readResponse(r)) {
                    if (r.purchase_order()) {
                        var url = urls.XUL_BROWSER + "?url=" +
                            window.escape(
                                xulG.url_prefix('EG_ACQ_PO_VIEW/')
                                    + r.purchase_order() + "/" + r.id()
                            );
                        window.xulG.new_tab(
                            url, {"browser": true}, {
                                "no_xulG": false,
                                "show_print_button": false,
                                "show_nav_buttons": true
                            }
                        );
                    } else {
                        /* unlikely: got an LI with no PO */
                        alert(dojo.byId("circStrings").getFormattedString(
                            "staff.circ.utils.find_acq_po.no_po", [r.id()]
                        ));
                    }
                }
            }
        }
    );
};

dump('exiting circ/util.js\n');
