sdump('D_TRACE','Loading patron_display.js\n');

function patron_display_init(p) {
	sdump('D_PATRON_DISPLAY',"TESTING: patron_display.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_TRACE_ENTER',arg_dump(arguments));

	p.w.set_patron = function (au) {
		return p.w._patron = au;
	}
	p.w.display_patron = function (au) {
		if (au) p.w.set_patron(au);
		if (p.w.status_w)
			p.w.status_w.display_patron(au);
		if (p.w.contact_w)
			p.w.contact_w.display_patron(au);
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
	p.w.refresh = function() {
		p.w.retrieve_patron_via_id( p.w._patron.id() );
	}

	if (p.patron) {
		if (typeof(p.patron) == 'object') {
			p.w._patron = p.patron;
			p.w.display_patron();
		} else
			p.w.retrieve_patron_via_barcode( p.patron );
	}

	p.w.clamshell = spawn_clamshell( 
		p.w.document, 'new_iframe', p.clamshell, {
			'horizontal' : true,
			'onload' : patron_display_init_after_clamshell(p) 
		}
	);


	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return;
}

function patron_display_init_after_clamshell(p) {
	sdump('D_PATRON_DISPLAY',arg_dump(arguments));
	return function (clamshell_w) {
		p.w.inner_clamshell = spawn_clamshell_vertical( 
			clamshell_w.document, 
			'new_iframe', 
			clamshell_w.first_deck, {
				'vertical' : true,
				'onload' : patron_display_init_after_inner_clamshell(p)
			}
		);

		return;
	};

}

function patron_display_init_after_inner_clamshell(p) {
	sdump('D_PATRON_DISPLAY',arg_dump(arguments));
	return function (clamshell_w) {
		sdump('D_PATRON_DISPLAY',arg_dump(arguments));
		p.w.status_w = spawn_patron_display_status(
			clamshell_w.document, 
			'new_iframe', 
			clamshell_w.first_deck, {
				'patron' : p.w._patron
			}
		);
		p.w.contact_w = spawn_patron_display_contact(
			clamshell_w.document, 
			'new_iframe', 
			clamshell_w.second_deck, {
				'patron' : p.w._patron
			}
		);
		return;
	};
}

