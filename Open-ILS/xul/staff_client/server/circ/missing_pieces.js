var error;

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');
        JSAN.use('util.error'); error = new util.error();
        error.sdump('D_TRACE','my_init() for missing_pieces.xul');

        JSAN.use('util.network');
        var network = new util.network();

        // Why the indirection of missing_pieces.xul instead of calling window.prompt in chrome/content/main/menu.js directly?
        // So we can get free remote upgrades of the logic behind cat.util.mark_item_as_missing_pieces, since I can't call
        // JSAN.use('cat.util'); in menu.js
        var barcode = window.prompt(
            $("circStrings").getString('staff.circ.missing_pieces.scan_item.prompt'),
            '',
            $("circStrings").getString('staff.circ.missing_pieces.scan_item.title')
        );
        if (!barcode) {
            window.close();
            return;
        }

        var copy;
        try {
            copy = network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[ barcode ]);
            if (typeof copy.ilsevent != 'undefined') throw(copy); 
            if (!copy) throw(copy);
        } catch(E) {
            alert($("circStrings").getFormattedString('staff.circ.missing_pieces.scan_item.error_alert', [barcode]) + '\n');
            window.close();
            return;
        }

        JSAN.use('cat.util');
        cat.util.mark_item_as_missing_pieces( [ copy.id() ] );
        window.close();
 
    } catch(E) {
        try { error.standard_unexpected_error_alert('circ/missing_pieces.xul',E); } catch(F) { alert(E); }
        window.close();
    }
}


