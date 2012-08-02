var error; 
var network;
var data;
var transit_list;
var hold_list;

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); error = new util.error();
        error.sdump('D_TRACE','my_init() for alternate_copy_summary.xul');

        JSAN.use('util.network'); network = new util.network();
        JSAN.use('OpenILS.data'); data = new OpenILS.data(); data.stash_retrieve();
        JSAN.use('util.date');
        JSAN.use('cat.util');

        var x = document.getElementById('patron_name');
        if (x) {
            x.addEventListener(
                'command',
                function(ev) {
                    var usr = ev.target.getAttribute('data');
                    if (usr) { window.xulG.new_patron_tab( {}, { 'id' : usr } ); }
                },
                false
            );
        }
        var y = document.getElementById('prev_patron_name');
        if (y) {
            y.addEventListener(
                'command',
                function(ev) {
                    var usr = ev.target.getAttribute('data');
                    if (usr) { window.xulG.new_patron_tab( {}, { 'id' : usr } ); }
                },
                false
            );
        }

        JSAN.use('circ.util'); 
        JSAN.use('util.list'); 

        var columns = circ.util.transit_columns({});
        transit_list = new util.list('transit');
        transit_list.init( { 'columns' : columns });

        hold_list = new util.list('hold');
        hold_list.init( { 'columns' : columns });

        // timeout so xulG gets a chance to get pushed in
        setTimeout(
            function () { xulG.from_item_details_new = false; load_item(); },
            1000
        );

    } catch(E) {
        try { error.standard_unexpected_error_alert('main/test.xul',E); } catch(F) { alert(E); }
    }
}

function set(name,value,data) { 
    if (typeof value == 'undefined' || typeof value == 'null') { return; }
    var nodes = document.getElementsByAttribute('name',name); 
    for (var i = 0; i < nodes.length; i++) {
        if (nodes[i].nodeName == 'button') {
            nodes[i].setAttribute('label',value);
            if (data) {
                nodes[i].setAttribute('data',data); 
            } else {
                nodes[i].setAttribute('data',''); 
            }
        } else {
            nodes[i].setAttribute('value',value);
        }
        nodes[i].value = value; 
    }
}

function set_tooltip(name,value) { 
    if (typeof value == 'undefined' || typeof value == 'null') { return; }
    var nodes = document.getElementsByAttribute('name',name); 
    for (var i = 0; i < nodes.length; i++) {
        nodes[i].setAttribute('tooltiptext',value);
    }
}

function renewal_composite_kludge(circ) {
    // Only a corrupt database could give us a situation where more
    // than one of these were true at a time, right?
    if (circ.desk_renewal() == "t")
        return document.getElementById('circStrings').getString(
            'staff.circ.copy_details.desk_renewal'
        );
    else if (circ.opac_renewal() == "t")
        return document.getElementById('circStrings').getString(
            'staff.circ.copy_details.opac_renewal'
        );
    else if (circ.phone_renewal() == "t")
        return document.getElementById('circStrings').getString(
            'staff.circ.copy_details.phone_renewal'
        );
    else return "";
}

function load_item() {
    try {
        if (! xulG.barcode) return;

        if (xulG.fetched_copy_details && xulG.fetched_copy_details[xulG.barcode]) {
            var details = xulG.fetched_copy_details[xulG.barcode];
            // We don't want to use these details more than once (i.e., we
            // don't want cached data after things have potentially changed).
            delete xulG.fetched_copy_details[xulG.barcode];
        } else {
            var details = network.simple_request('FM_ACP_DETAILS_VIA_BARCODE.authoritative', [ ses(), xulG.barcode ]);
            // Should get back .mvr, .copy, .volume, .transit, .circ, .hold
        }

        if (typeof dynamic_grid_replacement == 'function') {
            dynamic_grid_replacement('alternate_copy_summary');
        }
        if (typeof bib_brief_overlay == 'function') {
            bib_brief_overlay({
                'mvr' : details.mvr,
                'acp' : details.copy
            });
        }

        set("stat_cat_entries", '');
        set("age_protect", '');
        set("alert_message", '');
        set("barcode", '');
        set("call_number", '');
        set("circ_as_type", '');
        set("copy_circ_lib" , '');
        set_tooltip("copy_circ_lib" , '');
        set("circ_modifier", '');
        set("circulate", '');
        set("floating", '');
        set("copy_number", '');
        set("copy_create_date", '');
        set("copy_active_date", '');
        set("status_changed_time", '');
        set("copy_creator", '');
        set("deleted", '');
        set("deposit", '');
        set("deposit_amount", '');
        set("dummy_author", '');
        set("dummy_title", '');
        set("copy_edit_date", '');
        set("copy_editor", '');
        set("fine_level", '');
        set("holdable", '');
        set("copy_id", '');
        set("loan_duration", '');
        set("location", '');
        set_tooltip("location", '');
        set("renewal_type", '');
        set("opac_visible", '');
        set("price", '');
        set("ref", '');
        set("copy_status", '');
        set_tooltip("copy_status", '');
        set("notes", '');
        set("stat_cat_entry_copy_maps", '');
        set("circulations", '');
        set("total_circ_count", '');
        set_tooltip("total_circ_count", '');
        set("total_circ_count_prev_year", '');
        set("total_circ_count_curr_year", '');
        set("holds", '');

        if (details.copy) {
            set("stat_cat_entries", details.copy.stat_cat_entries()); 
            set("age_protect", details.copy.age_protect()); 
            set("alert_message", details.copy.alert_message()); 
            set("barcode", details.copy.barcode()); 
            if (typeof details.copy.call_number() == 'object') {
                set("call_number", details.copy.call_number().label()); 
            } else {
                network.simple_request('FM_ACN_RETRIEVE.authoritative',[details.copy.call_number()], function(req) {
                    var acn_obj = req.getResultObject();
                    set("call_number", acn_obj.label());
                });
            }
            set("circ_as_type", details.copy.circ_as_type() != null && details.copy.circ_as_type() == 'object'
                ? details.copy.circ_as_type()
                : ( typeof data.hash.citm[ details.copy.circ_as_type() ] != 'undefined'
                    ? data.hash.citm[ details.copy.circ_as_type() ].value
                    : ''
                )
            ); 
            set("copy_circ_lib" , typeof details.copy.circ_lib() == 'object' ? details.copy.circ_lib().shortname() : data.hash.aou[ details.copy.circ_lib() ].shortname()); 
            set_tooltip("copy_circ_lib" , typeof details.copy.circ_lib() == 'object' ? details.copy.circ_lib().name() : data.hash.aou[ details.copy.circ_lib() ].name()); 
            var cm = details.copy.circ_modifier();
            if (typeof data.hash.ccm[cm] != 'undefined') {
                set("circ_modifier", document.getElementById('commonStrings').getFormattedString('staff.circ_modifier.display',[cm,data.hash.ccm[cm].name(),data.hash.ccm[cm].description()])); 
            } else {
                set("circ_modifier","");
            }
            set("circulate", get_localized_bool( details.copy.circulate() )); 
            set("floating", get_localized_bool( details.copy.floating() )); 
            set("copy_number", details.copy.copy_number()); 
            set("copy_create_date", util.date.formatted_date( details.copy.create_date(), '%{localized}' )); 
            set("copy_active_date", util.date.formatted_date( details.copy.active_date(), '%{localized}' ));
            set("status_changed_time", util.date.formatted_date( details.copy.status_changed_time(), '%{localized}' )); 
            set("copy_creator", details.copy.creator()); 
            set("deleted", details.copy.deleted()); 
            set("deposit", details.copy.deposit()); 
            set("deposit_amount", details.copy.deposit_amount()); 
            set("dummy_author", details.copy.dummy_author()); 
            set("dummy_title", details.copy.dummy_title()); 
            set("copy_edit_date", util.date.formatted_date( details.copy.edit_date(), '%{localized}' )); 
            set("copy_editor", details.copy.editor()); 
            set("fine_level", cat.util.render_fine_level( details.copy.fine_level() )); 
            set("holdable", get_localized_bool( details.copy.holdable() )); 
            set("copy_id", details.copy.id()); 
            set("loan_duration", cat.util.render_loan_duration( details.copy.loan_duration() )); 
            var copy_location = typeof details.copy.location() == 'object' ? details.copy.location() : data.lookup('acpl',details.copy.location());
                set("location", copy_location.name());
                set_tooltip("location", document.getElementById('circStrings').getFormattedString( 
                    'staff.circ.copy_details.location_tooltip',
                    [
                        get_localized_bool( copy_location.circulate() ), 
                        get_localized_bool( copy_location.holdable() ), 
                        get_localized_bool( copy_location.hold_verify() ), 
                        get_localized_bool( copy_location.opac_visible() )
                    ]
                ));
            set("opac_visible", get_localized_bool( details.copy.opac_visible() )); 
            set("price", details.copy.price()); 
            set("ref", get_localized_bool( details.copy.ref() )); 
            var copy_status = typeof details.copy.status() == 'object' ? details.copy.status() : data.hash.ccs[ details.copy.status() ];
                set("copy_status", copy_status.name() );
                set_tooltip("copy_status", document.getElementById('circStrings').getFormattedString(
                    'staff.circ.copy_details.copy_status_tooltip',
                    [
                        get_localized_bool( copy_status.opac_visible() ), 
                        get_localized_bool( copy_status.holdable() ) 
                    ]
                ));
            set("notes", details.copy.notes()); 
            set("stat_cat_entry_copy_maps", details.copy.stat_cat_entry_copy_maps()); 
            set("circulations", details.copy.circulations()); 
            set("holds", details.copy.holds()); 

            network.simple_request('FM_CIRC_IMPROVED_COUNT_VIA_COPY', [ses(), { 'copy' : details.copy.id() } ], function(req) {
                var r = req.getResultObject();
                var total = 0; var tooltip = ''; var year = {};
                for (var i = 0; i < r.length; i++) {
                    total += Number( r[i].count() );
                    if (typeof year[ r[i].year() ] == 'undefined') year[ r[i].year() ] = 0;
                    year[ r[i].year() ] += Number( r[i].count() ); // Add original circs and renewals together
                }
                set( 'total_circ_count', total );
                var curr_year = (new Date()).getFullYear();
                var prev_year = curr_year - 1;
                set( 'total_circ_count_curr_year', year[ curr_year ] || 0 );
                set( 'total_circ_count_prev_year', year[ prev_year ] || 0 );
                var keys = []; for (var i in year) { keys.push( i ); }; keys.sort();
                for (var i = 0; i < keys.length; i++) {
                    tooltip += document.getElementById('circStrings').getFormattedString( 
                        'staff.circ.copy_details.circ_count_by_year', [ 
                            keys[i] == -1 ? document.getElementById('circStrings').getString('staff.circ.copy_details.circ_count_by_year.legacy_label') : keys[i], 
                            year[keys[i]]
                        ] 
                    ) + '\n';
                }
                set_tooltip( 'total_circ_count', tooltip );
            } );
        }

        set("copies", '');
        set("volume_create_date", '');
        set("volume_creator", '');
        set("deleted", '');
        set("volume_edit_date", '');
        set("volume_editor", '');
        set("volume_id", '');
        set("label", '');
        set("owning_lib" , '');
        set_tooltip("owning_lib" , '');
        set("record", '');
        set("notes", '');
        set("uri_maps", '');
        set("uris", '');

        if (details.volume) {
            set("copies", details.volume.copies()); 
            set("volume_create_date", util.date.formatted_date( details.volume.create_date(), '%{localized}' )); 
            set("volume_creator", details.volume.creator()); 
            set("deleted", details.volume.deleted()); 
            set("volume_edit_date", util.date.formatted_date( details.volume.edit_date(), '%{localized}' )); 
            set("volume_editor", details.volume.editor()); 
            set("volume_id", details.volume.id()); 
            set("label", details.volume.label()); 
            set("owning_lib" , typeof details.volume.owning_lib() == 'object' ? details.volume.owning_lib().shortname() : data.hash.aou[ details.volume.owning_lib() ].shortname()); 
            set_tooltip("owning_lib" , typeof details.volume.owning_lib() == 'object' ? details.volume.owning_lib().name() : data.hash.aou[ details.volume.owning_lib() ].name()); 
            set("record", details.volume.record()); 
            set("notes", details.volume.notes()); 
            set("uri_maps", details.volume.uri_maps()); 
            set("uris", details.volume.uris()); 
        }

        set("transit_copy_status", '');
        set_tooltip("transit_copy_status", '');
        set("dest", '');
        set("dest_recv_time", '');
        set("transit_id", '');
        set("persistant_transfer", '');
        set("prev_hop", '');
        set("source", '');
        set("source_send_time", '');
        set("target_copy", '');
        set("hold_transit_copy", '');

        if (details.transit) {

            transit_list.clear();
            transit_list.append( { 'row' : { 'my' : { 'atc' : details.transit, } } });

            var transit_copy_status = typeof details.transit.copy_status() == 'object' ? details.transit.copy_status() : data.hash.ccs[ details.transit.copy_status() ];
                set("transit_copy_status", transit_copy_status.name() );
                set_tooltip("transit_copy_status", document.getElementById('circStrings').getFormattedString(
                    'staff.circ.copy_details.copy_status_tooltip',
                    [
                        get_localized_bool( transit_copy_status.opac_visible() ), 
                        get_localized_bool( transit_copy_status.holdable() ) 
                    ]
                ));
            set("dest", details.transit.dest()); 
            set("dest_recv_time", util.date.formatted_date( details.transit.dest_recv_time(), '%{localized}' )); 
            set("transit_id", details.transit.id()); 
            set("persistant_transfer", details.transit.persistant_transfer()); 
            set("prev_hop", details.transit.prev_hop()); 
            set("source", details.transit.source()); 
            set("source_send_time", util.date.formatted_date( details.transit.source_send_time(), '%{localized}' )); 
            set("target_copy", details.transit.target_copy()); 
            set("hold_transit_copy", details.transit.hold_transit_copy()); 
        } else {
            $('transit_caption').setAttribute('label', $('circStrings').getString('staff.circ.copy_details.not_transit'));
        }

        set("checkin_lib", '');
        set_tooltip("checkin_lib", '');
        set("checkin_workstation",""); 
        set("checkin_staff", '');
        set("checkin_time", '');
        set("checkin_scan_time", '');
        set("circ_circ_lib" , '');
        set_tooltip("circ_circ_lib" , '');
        set("circ_staff", '');
        set("desk_renewal", '');
        set("due_date", '');
        set("duration", '');
        set("duration_rule", '');
        set("fine_interval", '');
        set("circ_id", '');
        set("max_fine", '');
        set("max_fine_rule", '');
        set("opac_renewal", '');
        set("phone_renewal", '');
        set("recurring_fine", '');
        set("recurring_fine_rule", '');
        set("renewal_remaining", '');
        set("stop_fines", '');
        set("stop_fines_time", '');
        set("target_copy", '');
        set("circ_usr", '');
        set("xact_finish", '');
        set("xact_start", '');
        set("create_time", '');
        set("workstation", '');
        set("renewal_workstation", '');
        set("checkout_workstation", '');
        set("billings", '');
        set("payments", '');
        set("billable_transaction", '');
        set("circ_type", '');
        set("billing_total", '');
        set("payment_total", '');
        set("patron_name", '');
        set("prev_patron_name", '');
        set("prev_num_circs", '');
        set("prev_num_renewals", '');
        set("prev_xact_start", '');
        set("prev_checkout_workstation", '');
        set("prev_renewal_time", '');
        set("prev_stop_fines", '');
        set("prev_stop_fines_time", '');
        set("prev_renewal_workstation", '');
        set("prev_checkin_workstation", '');
        set("prev_last_checkin_time", '');
        set("prev_last_checkin_scan_time", '');

        if (details.circ) {
            try { set("checkin_lib", typeof details.circ.checkin_lib() == 'object' ? details.circ.checkin_lib().shortname() : data.hash.aou[ details.circ.checkin_lib() ].shortname() );  } catch(E) {};
            try { set_tooltip("checkin_lib", typeof details.circ.checkin_lib() == 'object' ? details.circ.checkin_lib().name() : data.hash.aou[ details.circ.checkin_lib() ].name() );  } catch(E) {};
            if (details.circ.checkin_workstation()) {
                set("checkin_workstation", details.circ.checkin_workstation().name()); 
            }
            set("checkin_staff", details.circ.checkin_staff()); 
            set("checkin_time", util.date.formatted_date( details.circ.checkin_time(), '%{localized}' )); 
            set("last_checkin_time", util.date.formatted_date( details.circ.checkin_time(), '%{localized}' )); 
            set("checkin_scan_time", util.date.formatted_date( details.circ.checkin_scan_time(), '%{localized}' )); 
            set("last_checkin_scan_time", util.date.formatted_date( details.circ.checkin_scan_time(), '%{localized}' )); 
            try { set("circ_circ_lib" , typeof details.circ.circ_lib() == 'object' ? details.circ.circ_lib().shortname() : data.hash.aou[ details.circ.circ_lib() ].shortname() );  } catch(E) {};
            try { set_tooltip("circ_circ_lib" , typeof details.circ.circ_lib() == 'object' ? details.circ.circ_lib().name() : data.hash.aou[ details.circ.circ_lib() ].name() );  } catch(E) {};
            set("circ_staff", details.circ.circ_staff()); 
            set("desk_renewal", details.circ.desk_renewal()); 
            set("due_date", util.date.formatted_date( details.circ.due_date(), '%{localized}' )); 
            set("duration", details.circ.duration()); 
            set("fine_interval", details.circ.fine_interval()); 
            set("circ_id", details.circ.id()); 
            set("max_fine", details.circ.max_fine()); 
            set("opac_renewal", details.circ.opac_renewal()); 
            set("phone_renewal", details.circ.phone_renewal()); 
            set("renewal_type", renewal_composite_kludge(details.circ));
            set("recurring_fine", details.circ.recurring_fine()); 
            set("renewal_remaining", details.circ.renewal_remaining()); 
            set("stop_fines", details.circ.stop_fines()); 
            set("stop_fines_time", util.date.formatted_date( details.circ.stop_fines_time(), '%{localized}' )); 
            set("target_copy", details.circ.target_copy()); 
            set("circ_usr", details.circ.usr()); 
            network.simple_request('FM_AU_FLESHED_RETRIEVE_VIA_ID',[ ses(), details.circ.usr() ], function(preq) {
                var r_au = preq.getResultObject();
                JSAN.use('patron.util');
                set(
                    'patron_name', 
                    patron.util.format_name( r_au ) + ' : ' + r_au.card().barcode(),
                    details.circ.usr()
                );
                set_tooltip('patron_name','circ id ' + details.circ.id());
            });
            set("xact_finish", util.date.formatted_date( details.circ.xact_finish(), '%{localized}' )); 
            set("xact_start", util.date.formatted_date( details.circ.xact_start(), '%{localized}' )); 
            set("create_time", util.date.formatted_date( details.circ.create_time(), '%{localized}' )); 
            set("workstation", details.circ.workstation()); 
            if (get_bool(details.circ.opac_renewal())||get_bool(details.circ.phone_renewal())||get_bool(details.circ.desk_renewal())) {
                set("renewal_workstation", (typeof details.circ.workstation() == 'object' && details.circ.workstation() != null) ? details.circ.workstation().name() : details.circ.workstation() ); 
                network.simple_request('FM_CIRC_CHAIN_SUMMARY', [ses(), details.circ.id() ], function(req) {
                    try {
                        var summary = req.getResultObject();
                        set("num_circs", summary.num_circs());
                        set("num_renewals", Number(summary.num_circs()) - 1);
                        set("xact_start", util.date.formatted_date( summary.start_time(), '%{localized}' )); 
                        set("checkout_workstation", summary.checkout_workstation());
                        set("renewal_time", util.date.formatted_date( summary.last_renewal_time(), '%{localized}' )); 
                        set("stop_fines", summary.last_stop_fines());
                        set("stop_fines_time", util.date.formatted_date( summary.last_stop_fines_time(), '%{localized}' )); 
                        set("renewal_workstation", summary.last_renewal_workstation());
                        set("checkin_workstation", summary.last_checkin_workstation());
                        set("last_checkin_time", util.date.formatted_date( summary.last_checkin_time(), '%{localized}' )); 
                        set("last_checkin_scan_time", util.date.formatted_date( summary.last_checkin_scan_time(), '%{localized}' )); 
                    } catch(E) {
                        alert('Error in alternate_copy_summary.js, FM_CIRC_CHAIN: ' + E);
                    }
                } );
            } else {
                set("checkout_workstation", (typeof details.circ.workstation() == 'object' && details.circ.workstation() != null) ? details.circ.workstation().name() : details.circ.workstation() );
            }
            network.simple_request('FM_CIRC_PREV_CHAIN_SUMMARY', [ses(), details.circ.id() ], function(req) {
                try {
                    var robj = req.getResultObject();
                    if (!robj || typeof robj == 'null') { return; }
                    var summary = robj['summary'];
                    network.simple_request('FM_AU_FLESHED_RETRIEVE_VIA_ID',[ ses(), robj['usr'] ], function(preq) {
                        var r_au = preq.getResultObject();
                        JSAN.use('patron.util');
                        set(
                            'prev_patron_name', 
                            patron.util.format_name( r_au ) + ' : ' + r_au.card().barcode(),
                            robj['usr']
                        );
                        set_tooltip('prev_patron_name','circ chain prior to circ id ' + details.circ.id());
                    });
                    set("prev_num_circs", summary.num_circs());
                    set("prev_num_renewals", Number(summary.num_circs()) - 1);
                    set("prev_xact_start", util.date.formatted_date( summary.start_time(), '%{localized}' )); 
                    set("prev_checkout_workstation", summary.checkout_workstation());
                    set("prev_renewal_time", util.date.formatted_date( summary.last_renewal_time(), '%{localized}' )); 
                    set("prev_stop_fines", summary.last_stop_fines());
                    set("prev_stop_fines_time", util.date.formatted_date( summary.last_stop_fines_time(), '%{localized}' )); 
                    set("prev_renewal_workstation", summary.last_renewal_workstation());
                    set("prev_checkin_workstation", summary.last_checkin_workstation());
                    set("prev_last_checkin_time", util.date.formatted_date( summary.last_checkin_time(), '%{localized}' )); 
                    set("prev_last_checkin_scan_time", util.date.formatted_date( summary.last_checkin_scan_time(), '%{localized}' )); 
                } catch(E) {
                    alert('Error in alternate_copy_summary.js, FM_CIRC_PREV_CHAIN: ' + E);
                }
            });
            set("billings", details.circ.billings()); 
            set("payments", details.circ.payments()); 
            set("billable_transaction", details.circ.billable_transaction()); 
            set("circ_type", details.circ.circ_type()); 
            set("billing_total", details.circ.billing_total()); 
            set("payment_total", details.circ.payment_total()); 
            if (! details.circ.checkin_time() ) {
                set("recurring_fine_rule", document.getElementById('circStrings').getFormattedString(
                    'staff.circ.copy_details.recurring_fine_rule_format',
                    [
                        details.circ.recurring_fine_rule().name(),
                        details.circ.recurring_fine_rule().id(),
                        details.circ.recurring_fine_rule().low(),
                        details.circ.recurring_fine_rule().normal(),
                        details.circ.recurring_fine_rule().high(),
                        details.circ.recurring_fine_rule().recurrence_interval()
                    ]
                )); 
                set_tooltip("recurring_fine_rule", document.getElementById('circStrings').getFormattedString(
                    'staff.circ.copy_details.recurring_fine_rule_tooltip_format',
                    [
                        details.circ.recurring_fine_rule().name(),
                        details.circ.recurring_fine_rule().id(),
                        details.circ.recurring_fine_rule().low(),
                        details.circ.recurring_fine_rule().normal(),
                        details.circ.recurring_fine_rule().high(),
                        details.circ.recurring_fine_rule().recurrence_interval()
                    ]
                )); 
                set("duration_rule", document.getElementById('circStrings').getFormattedString(
                    'staff.circ.copy_details.duration_rule_format',
                    [
                        details.circ.duration_rule().name(),
                        details.circ.duration_rule().id(),
                        details.circ.duration_rule().shrt(),
                        details.circ.duration_rule().normal(),
                        details.circ.duration_rule().extended(),
                        details.circ.duration_rule().max_renewals()
                    ]
                )); 
                set_tooltip("duration_rule", document.getElementById('circStrings').getFormattedString(
                    'staff.circ.copy_details.duration_rule_tooltip_format',
                    [
                        details.circ.duration_rule().name(),
                        details.circ.duration_rule().id(),
                        details.circ.duration_rule().shrt(),
                        details.circ.duration_rule().normal(),
                        details.circ.duration_rule().extended(),
                        details.circ.duration_rule().max_renewals()
                    ]
                )); 
                set("max_fine_rule", document.getElementById('circStrings').getFormattedString(
                    'staff.circ.copy_details.max_fine_rule_format',
                    [
                        details.circ.max_fine_rule().name(),
                        details.circ.max_fine_rule().id(),
                        details.circ.max_fine_rule().amount(),
                        details.circ.max_fine_rule().is_percent()
                    ]
                ));
                set_tooltip("max_fine_rule", document.getElementById('circStrings').getFormattedString(
                    'staff.circ.copy_details.max_fine_rule_tooltip_format',
                    [
                        details.circ.max_fine_rule().name(),
                        details.circ.max_fine_rule().id(),
                        details.circ.max_fine_rule().amount(),
                        details.circ.max_fine_rule().is_percent()
                    ]
                ));
            }
        }

        set("hold_status", '');
        set("transit", '');
        set("capture_time", '');
        set("current_copy", '');
        set("email_notify", '');
        set("expire_time", '');
        set("fulfillment_lib", '');
        set_tooltip("fulfillment_lib", '');
        set("fulfillment_staff", '');
        set("fulfillment_time", '');
        set("hold_type", '');
        set("holdable_formats", '');
        set("hold_id", '');
        set("phone_notify", '');
        set("pickup_lib", '');
        set_tooltip("pickup_lib", '');
        set("prev_check_time", '');
        set("request_lib", '');
        set_tooltip("request_lib", '');
        set("request_time", '');
        set("requestor", '');
        set("selection_depth", '');
        set("selection_ou", '');
        set_tooltip("selection_ou", '');
        set("target", '');
        set("hold_usr", '');
        set("hold_patron_name", '');
        set("cancel_time", '');
        set("notify_time", '');
        set("notify_count", '');
        set("notifications", '');
        set("bib_rec", '');
        set("eligible_copies", '');
        set("frozen", '');
        set("thaw_date", '');
        set("shelf_time", '');
        set("cancel_cause", '');
        set("cancel_note", '');
        set("notes", '');

        if (details.hold) {
            var better_fleshed_hold_blob = network.simple_request('FM_AHR_BLOB_RETRIEVE.authoritative',[ ses(), details.hold.id() ]);
            var status_robj = better_fleshed_hold_blob.status;
            JSAN.use('circ.util');
            var columns = circ.util.hold_columns( 
                { 
                    'request_time' : { 'hidden' : false },
                    'pickup_lib_shortname' : { 'hidden' : false },
                    'hold_type' : { 'hidden' : true },
                    'current_copy' : { 'hidden' : true },
                    'capture_time' : { 'hidden' : true },
                    'email_notify' : { 'hidden' : false },
                    'phone_notify' : { 'hidden' : false },
                } 
            );

            hold_list.clear();
            hold_list.append( { 'row' : { 'my' : { 'ahr' : better_fleshed_hold_blob.hold, 'acp' : details.copy, 'status' : status_robj, } } });

            JSAN.use('patron.util'); 
            var au_obj = patron.util.retrieve_fleshed_au_via_id( ses(), details.hold.usr() );
            $('hold_patron_name').setAttribute('value', $('circStrings').getFormattedString('staff.circ.copy_details.user_details', [au_obj.family_name(), au_obj.first_given_name(), au_obj.card().barcode()]) );
            $('hold_patron_name').onclick = function(e) {
                if (e.ctrlKey) {
                   window.xulG.new_patron_tab( {}, { 'id' : au_obj.id() } );
                   return;
                }
                copy_to_clipboard(au_obj.card().barcode());
            };

            set("hold_status", details.hold.status()); 
            set("transit", details.hold.transit()); 
            set("capture_time", util.date.formatted_date( details.hold.capture_time(), '%{localized}' )); 
            set("current_copy", details.hold.current_copy()); 
            set("email_notify", details.hold.email_notify()); 
            set("expire_time", util.date.formatted_date( details.hold.expire_time(), '%{localized}' )); 
            try { set("fulfillment_lib" , typeof details.hold.fulfillment_lib() == 'object' ? details.hold.fulfillment_lib().shortname() : data.hash.aou[ details.hold.fulfillment_lib() ].shortname() );  } catch(E) {}
            try { set_tooltip("fulfillment_lib" , typeof details.hold.fulfillment_lib() == 'object' ? details.hold.fulfillment_lib().name() : data.hash.aou[ details.hold.fulfillment_lib() ].name() );  } catch(E) {}
            set("fulfillment_staff", details.hold.fulfillment_staff()); 
            set("fulfillment_time", util.date.formatted_date( details.hold.fulfillment_time(), '%{localized}' )); 
            set("hold_type", details.hold.hold_type()); 
            set("holdable_formats", details.hold.holdable_formats()); 
            set("hold_id", details.hold.id()); 
            set("phone_notify", details.hold.phone_notify()); 
            try { set("pickup_lib" , typeof details.hold.pickup_lib() == 'object' ? details.hold.pickup_lib().shortname() : data.hash.aou[ details.hold.pickup_lib() ].shortname() );  } catch(E) {}
            try { set_tooltip("pickup_lib" , typeof details.hold.pickup_lib() == 'object' ? details.hold.pickup_lib().name() : data.hash.aou[ details.hold.pickup_lib() ].name() );  } catch(E) {}
            set("prev_check_time", util.date.formatted_date( details.hold.prev_check_time(), '%{localized}' )); 
            try { set("request_lib" , typeof details.hold.request_lib() == 'object' ? details.hold.request_lib().shortname() : data.hash.aou[ details.hold.request_lib() ].shortname() ); } catch(E) {}
            try { set_tooltip("request_lib" , typeof details.hold.request_lib() == 'object' ? details.hold.request_lib().name() : data.hash.aou[ details.hold.request_lib() ].name() ); } catch(E) {}
            set("request_time", util.date.formatted_date( details.hold.request_time(), '%{localized}' )); 
            set("requestor", details.hold.requestor()); 
            set("selection_depth", details.hold.selection_depth()); 
            set("selection_ou" , typeof details.hold.selection_ou() == 'object' ? details.hold.selection_ou().shortname() : data.hash.aou[ details.hold.selection_ou() ].shortname() ); 
            set_tooltip("selection_ou" , typeof details.hold.selection_ou() == 'object' ? details.hold.selection_ou().name() : data.hash.aou[ details.hold.selection_ou() ].name() ); 
            set("target", details.hold.target()); 
            set("hold_usr", details.hold.usr()); 
            set("cancel_time", util.date.formatted_date( details.hold.cancel_time(), '%{localized}' )); 
            set("notify_time", util.date.formatted_date( details.hold.notify_time(), '%{localized}' )); 
            set("notify_count", details.hold.notify_count()); 
            set("notifications", details.hold.notifications()); 
            set("bib_rec", details.hold.bib_rec()); 
            set("eligible_copies", details.hold.eligible_copies()); 
            set("frozen", details.hold.frozen()); 
            set("thaw_date", util.date.formatted_date( details.hold.thaw_date(), '%{localized}' )); 
            set("shelf_time", util.date.formatted_date( details.hold.shelf_time(), '%{localized}' )); 
            set("cancel_cause", details.hold.cancel_cause()); 
            set("cancel_note", details.hold.cancel_note()); 
            set("notes", details.hold.notes()); 
        } else {
            if (details.copy.status() == 8 /* ON HOLDS SHELF */) {
                $('hold_caption').setAttribute('label', $('circStrings').getString('staff.circ.copy_details.bad_hold_status'));
            } else {
                $('hold_caption').setAttribute('label', $('circStrings').getString('staff.circ.copy_details.no_hold'));
            }
        }

        var x = document.getElementById('cat_deck');
        if (x) {
            JSAN.use('util.deck');
            var d = new util.deck('cat_deck');
            d.reset_iframe( urls.XUL_MARC_VIEW, {}, { 'docid' : details.mvr ? details.mvr.doc_id() : -1 } );
        }

    } catch(E) {
        alert(E);
    }
}
