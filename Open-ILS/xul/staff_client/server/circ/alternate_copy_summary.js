var error; 
var network;

function my_init() {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); error = new util.error();
        error.sdump('D_TRACE','my_init() for alternate_copy_summary.xul');

        JSAN.use('util.network'); network = new util.network();

        setTimeout( function() { load_item(); }, 1000 ); // timeout so xulG gets a chance to get pushed in

    } catch(E) {
        try { error.standard_unexpected_error_alert('main/test.xul',E); } catch(F) { alert(E); }
    }
}

function set(name,value) { 
    var nodes = document.getElementsByAttribute('name',name); 
    for (var i = 0; i < nodes.length; i++) {
        if (value) { nodes[i].setAttribute('value',value); nodes[i].value = value; }; 
    }
}

function load_item() {
    if (! xulG.barcode) return;
    var details = network.simple_request('FM_ACP_DETAILS_VIA_BARCODE.authoritative', [ ses(), xulG.barcode ]);
    // Should get back .mvr, .copy, .volume, .transit, .circ, .hold

    if (details.mvr) {
        set('title', details.mvr.title());
        set('author', details.mvr.author());
        set('doc_id', details.mvr.doc_id());
        set('doc_type', details.mvr.doc_type());
        set('pubdate', details.mvr.pubdate());
        set('isbn', details.mvr.isbn());
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
    }

    if (details.copy) {
        set("stat_cat_entries", details.copy.stat_cat_entries()); 
        set("age_protect", details.copy.age_protect()); 
        set("alert_message", details.copy.alert_message()); 
        set("barcode", details.copy.barcode()); 
        set("call_number", details.copy.call_number()); 
        set("circ_as_type", details.copy.circ_as_type()); 
        set("circ_lib" , details.copy.circ_lib()); 
        set("circ_modifier", details.copy.circ_modifier()); 
        set("circulate", details.copy.circulate()); 
        set("copy_number", details.copy.copy_number()); 
        set("create_date", details.copy.create_date()); 
        set("creator", details.copy.creator()); 
        set("deleted", details.copy.deleted()); 
        set("deposit", details.copy.deposit()); 
        set("deposit_amount", details.copy.deposit_amount()); 
        set("dummy_author", details.copy.dummy_author()); 
        set("dummy_title", details.copy.dummy_title()); 
        set("edit_date", details.copy.edit_date()); 
        set("editor", details.copy.editor()); 
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
        set("total_circ_count", details.copy.total_circ_count()); 
        set("holds", details.copy.holds()); 
    }

    if (details.volume) {
        set("copies", details.volume.copies()); 
        set("create_date", details.volume.create_date()); 
        set("creator", details.volume.creator()); 
        set("deleted", details.volume.deleted()); 
        set("edit_date", details.volume.edit_date()); 
        set("editor", details.volume.editor()); 
        set("volume_id", details.volume.id()); 
        set("label", details.volume.label()); 
        set("owning_lib" , details.volume.owning_lib()); 
        set("record", details.volume.record()); 
        set("notes", details.volume.notes()); 
        set("uri_maps", details.volume.uri_maps()); 
        set("uris", details.volume.uris()); 
    }

    if (details.transit) {
        set("copy_status", details.transit.copy_status()); 
        set("dest", details.transit.dest()); 
        set("dest_recv_time", details.transit.dest_recv_time()); 
        set("transit_id", details.transit.id()); 
        set("persistant_transfer", details.transit.persistant_transfer()); 
        set("prev_hop", details.transit.prev_hop()); 
        set("source", details.transit.source()); 
        set("source_send_time", details.transit.source_send_time()); 
        set("target_copy", details.transit.target_copy()); 
        set("hold_transit_copy", details.transit.hold_transit_copy()); 
    }

    if (details.circ) {
        set("checkin_lib", details.circ.checkin_lib()); 
        set("checkin_workstation", details.circ.checkin_workstation().name()); 
        set("checkin_staff", details.circ.checkin_staff()); 
        set("checkin_time", details.circ.checkin_time()); 
        set("circ_lib" , details.circ.circ_lib()); 
        set("circ_staff", details.circ.circ_staff()); 
        set("desk_renewal", details.circ.desk_renewal()); 
        set("due_date", details.circ.due_date()); 
        set("duration", details.circ.duration()); 
        set("duration_rule", details.circ.duration_rule()); 
        set("fine_interval", details.circ.fine_interval()); 
        set("circ_id", details.circ.id()); 
        set("max_fine", details.circ.max_fine()); 
        set("max_fine_rule", details.circ.max_fine_rule()); 
        set("opac_renewal", details.circ.opac_renewal()); 
        set("phone_renewal", details.circ.phone_renewal()); 
        set("recuring_fine", details.circ.recuring_fine()); 
        set("recuring_fine_rule", details.circ.recuring_fine_rule()); 
        set("renewal_remaining", details.circ.renewal_remaining()); 
        set("stop_fines", details.circ.stop_fines()); 
        set("stop_fines_time", details.circ.stop_fines_time()); 
        set("target_copy", details.circ.target_copy()); 
        set("usr", details.circ.usr()); 
        set("xact_finish", details.circ.xact_finish()); 
        set("xact_start", details.circ.xact_start()); 
        set("create_time", details.circ.create_time()); 
        set("workstation", details.circ.workstation()); 
        set("billings", details.circ.billings()); 
        set("payments", details.circ.payments()); 
        set("billable_transaction", details.circ.billable_transaction()); 
        set("circ_type", details.circ.circ_type()); 
        set("billing_total", details.circ.billing_total()); 
        set("payment_total", details.circ.payment_total()); 
    }

    if (details.hold) {
        set("status", details.hold.status()); 
        set("transit", details.hold.transit()); 
        set("capture_time", details.hold.capture_time()); 
        set("current_copy", details.hold.current_copy()); 
        set("email_notify", details.hold.email_notify()); 
        set("expire_time", details.hold.expire_time()); 
        set("fulfillment_lib", details.hold.fulfillment_lib()); 
        set("fulfillment_staff", details.hold.fulfillment_staff()); 
        set("fulfillment_time", details.hold.fulfillment_time()); 
        set("hold_type", details.hold.hold_type()); 
        set("holdable_formats", details.hold.holdable_formats()); 
        set("hold_id", details.hold.id()); 
        set("phone_notify", details.hold.phone_notify()); 
        set("pickup_lib", details.hold.pickup_lib()); 
        set("prev_check_time", details.hold.prev_check_time()); 
        set("request_lib", details.hold.request_lib()); 
        set("request_time", details.hold.request_time()); 
        set("requestor", details.hold.requestor()); 
        set("selection_depth", details.hold.selection_depth()); 
        set("selection_ou", details.hold.selection_ou()); 
        set("target", details.hold.target()); 
        set("usr", details.hold.usr()); 
        set("cancel_time", details.hold.cancel_time()); 
        set("notify_time", details.hold.notify_time()); 
        set("notify_count", details.hold.notify_count()); 
        set("notifications", details.hold.notifications()); 
        set("bib_rec", details.hold.bib_rec()); 
        set("eligible_copies", details.hold.eligible_copies()); 
        set("frozen", details.hold.frozen()); 
        set("thaw_date", details.hold.thaw_date()); 
        set("shelf_time", details.hold.shelf_time()); 
        set("cancel_cause", details.hold.cancel_cause()); 
        set("cancel_note", details.hold.cancel_note()); 
        set("notes", details.hold.notes()); 
    } 
}
