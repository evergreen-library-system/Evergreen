sdump('D_TRACE','Loading patron_display_contact.js\n');

function patron_display_contact_init(p) {
	sdump('D_PATRON_DISPLAY_CONTACT',"TESTING: patron_display_contact.js: " + mw.G['main_test_variable'] + '\n');

	if (p.app_shell) p.w.app_shell = p.app_shell;

	p.w.set_patron = function (au) {
		return p.w._patron = au;
	}
	p.w.display_patron = function (au) {
		if (au) p.w.set_patron(au);
		return render_fm(p.w.document, { 'au' : p.w._patron });
	};
	p.w.retrieve_patron_via_barcode = function (barcode) {
		if (!barcode) barcode = patron_get_barcode( p.w._patron );
		p.w.set_patron( retrieve_patron_by_barcode( barcode ) );
		return p.w.display_patron();
	}
	p.w.retrieve_patron_via_id = function (id) {
		p.w.set_patron( retrieve_patron_by_id( id ) );
		return p.w.display_patron();
	}

	consider_Timeout(
		function() {
			sdump('D_TIMEOUT','******** timeout occurred in patron_display_contact.js\n');
			if (p.patron) {
				if (typeof(p.patron) == 'object') {
					p.w.set_patron( p.patron );
					p.w.display_patron();
				} else
					p.w.retrieve_patron_via_barcode( p.patron );
			}
		}, 0
	);

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return;
}


