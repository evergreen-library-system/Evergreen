var error; 
var network;
var data;

function my_init() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); error = new util.error();
        error.sdump('D_TRACE','my_init() for alternate_copy_summary.xul');

        JSAN.use('util.network'); network = new util.network();
        JSAN.use('OpenILS.data'); data = new OpenILS.data(); data.stash_retrieve();
        JSAN.use('util.date');

        // timeout so xulG gets a chance to get pushed in
        setTimeout(
            function () { xulG.from_item_details_new = false; load_item(); },
            1000
        );

    } catch(E) {
        try { error.standard_unexpected_error_alert('main/test.xul',E); } catch(F) { alert(E); }
    }
}

function set(name,value) { 
    var nodes = document.getElementsByAttribute('name',name); 
    for (var i = 0; i < nodes.length; i++) {
        nodes[i].setAttribute('value',value); nodes[i].value = value; 
    }
}

function set_tooltip(name,value) { 
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

        if (typeof bib_brief_overlay == 'function') bib_brief_overlay( { 'mvr' : details.mvr, 'acp' : details.copy } );
/*
        set('title', '');
        set('author', '');
        set('doc_id', '');
        set('doc_type', '');
        set('pubdate', '');
        set('isbn', '');
        set('publisher', '');
        set('tcn', '');
        set('subject', '');
        set('types_of_resource', '');
        set('call_numbers', '');
        set('edition', '');
        set('online_loc', '');
        set('synopsis', '');
        set('physical_description', '');
        set('toc', '');
        set('copy_count', '');
        set('series', '');
        set('serials', '');

        if (details.mvr) {
            set('title',details.mvr.title()); 
            set('author',details.mvr.author());
            set('doc_id', details.mvr.doc_id());
            set('doc_type', details.mvr.doc_type());
            set('pubdate', details.mvr.pubdate());
            set('isbn',details.mvr.isbn());
            set('publisher', details.mvr.publisher());
            set('tcn', details.mvr.tcn());
            set('subject', details.mvr.subject());
            set('types_of_resource', details.mvr.types_of_resource());
            set('call_numbers', details.mvr.call_numbers());
            set('edition', details.mvr.edition());
            set('online_loc', details.mvr.online_loc());
            set('synopsis', details.mvr.synopsis());
            set('physical_description', details.mvr.physical_description());
            set('toc', details.mvr.toc());
            set('copy_count', details.mvr.copy_count());
            set('series', details.mvr.series());
            set('serials', details.mvr.serials());
        } else {
            set('title',details.copy.dummy_title());
            set('author',details.copy.dummy_author()); 
            set('isbn',details.copy.dummy_isbn());
        }
*/
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
        set("copy_number", '');
        set("copy_create_date", '');
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
        set("renewal_type", '');
        set("opac_visible", '');
        set("price", '');
        set("ref", '');
        set("status", '');
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
            set("call_number", details.copy.call_number()); 
            set("circ_as_type", details.copy.circ_as_type()); 
            set("copy_circ_lib" , typeof details.copy.circ_lib() == 'object' ? details.copy.circ_lib().shortname() : data.hash.aou[ details.copy.circ_lib() ].shortname()); 
            set_tooltip("copy_circ_lib" , typeof details.copy.circ_lib() == 'object' ? details.copy.circ_lib().name() : data.hash.aou[ details.copy.circ_lib() ].name()); 
            set("circ_modifier", details.copy.circ_modifier()); 
            set("circulate", details.copy.circulate()); 
            set("copy_number", details.copy.copy_number()); 
            set("copy_create_date", util.date.formatted_date( details.copy.create_date(), '%{localized}' )); 
            set("status_changed_time", util.date.formatted_date( details.copy.status_changed_time(), '%{localized}' )); 
            set("copy_creator", details.copy.creator()); 
            set("deleted", details.copy.deleted()); 
            set("deposit", details.copy.deposit()); 
            set("deposit_amount", details.copy.deposit_amount()); 
            set("dummy_author", details.copy.dummy_author()); 
            set("dummy_title", details.copy.dummy_title()); 
            set("copy_edit_date", util.date.formatted_date( details.copy.edit_date(), '%{localized}' )); 
            set("copy_editor", details.copy.editor()); 
            set("fine_level", details.copy.fine_level()); 
            set("holdable", details.copy.holdable()); 
            set("copy_id", details.copy.id()); 
            set("loan_duration", details.copy.loan_duration()); 
            set("location", details.copy.location()); 
            set("opac_visible", details.copy.opac_visible()); 
            set("price", details.copy.price()); 
            set("ref", details.copy.ref()); 
            set("status", details.copy.status()); 
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

        set("copy_status", '');
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
            set("copy_status", details.transit.copy_status()); 
            set("dest", details.transit.dest()); 
            set("dest_recv_time", util.date.formatted_date( details.transit.dest_recv_time(), '%{localized}' )); 
            set("transit_id", details.transit.id()); 
            set("persistant_transfer", details.transit.persistant_transfer()); 
            set("prev_hop", details.transit.prev_hop()); 
            set("source", details.transit.source()); 
            set("source_send_time", util.date.formatted_date( details.transit.source_send_time(), '%{localized}' )); 
            set("target_copy", details.transit.target_copy()); 
            set("hold_transit_copy", details.transit.hold_transit_copy()); 
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
        set("usr", '');
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

        if (details.circ) {
            try { set("checkin_lib", typeof details.circ.checkin_lib() == 'object' ? details.circ.checkin_lib().shortname() : data.hash.aou[ details.circ.checkin_lib() ].shortname() );  } catch(E) {};
            try { set_tooltip("checkin_lib", typeof details.circ.checkin_lib() == 'object' ? details.circ.checkin_lib().name() : data.hash.aou[ details.circ.checkin_lib() ].name() );  } catch(E) {};
            if (details.circ.checkin_workstation()) {
                set("checkin_workstation", details.circ.checkin_workstation().name()); 
            }
            set("checkin_staff", details.circ.checkin_staff()); 
            set("checkin_time", util.date.formatted_date( details.circ.checkin_time(), '%{localized}' )); 
            set("checkin_scan_time", util.date.formatted_date( details.circ.checkin_scan_time(), '%{localized}' )); 
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
            set("usr", details.circ.usr()); 
            set("xact_finish", util.date.formatted_date( details.circ.xact_finish(), '%{localized}' )); 
            set("xact_start", util.date.formatted_date( details.circ.xact_start(), '%{localized}' )); 
            set("create_time", util.date.formatted_date( details.circ.create_time(), '%{localized}' )); 
            set("workstation", details.circ.workstation()); 
            if (get_bool(details.circ.opac_renewal())||get_bool(details.circ.phone_renewal())||get_bool(details.circ.desk_renewal())) {
                set("renewal_workstation", (typeof details.circ.workstation() == 'object' && details.circ.workstation() != null) ? details.circ.workstation().name() : details.circ.workstation() ); 
                network.simple_request('FM_CIRC_CHAIN', [ses(), details.circ.id() ], function(req) { // Tiny race condition between details.circ and circs[circs.length-1] here, but meh :)
                    try {
                        var circs = req.getResultObject();
                        set("checkout_workstation", (typeof circs[0].workstation() == 'object' && circs[0].workstation() != null) ? circs[0].workstation().name() : circs[0].workstation() );
                    } catch(E) {
                        alert('Error in alternate_copy_summary.js, FM_CIRC_CHAIN: ' + E);
                    }
                } );
            } else {
                set("checkout_workstation", (typeof details.circ.workstation() == 'object' && details.circ.workstation() != null) ? details.circ.workstation().name() : details.circ.workstation() );
            }
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

        set("status", '');
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
        set("usr", '');
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
            set("status", details.hold.status()); 
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
            set("usr", details.hold.usr()); 
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
