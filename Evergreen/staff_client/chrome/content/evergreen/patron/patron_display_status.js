sdump('D_TRACE','Loading patron_display_status.js\n');

function patron_display_status_init(p) {
	sdump('D_PATRON_DISPLAY_STATUS',"TESTING: patron_display_status.js: " + mw.G['main_test_variable'] + '\n');

	if (p.app_shell) p.w.app_shell = p.app_shell;

	p.w.patron_name_label = get_widget( p.w.document, p.patron_name_label );
	if (p.show_name) {
		sdump('D_PATRON_DISPLAY_STATUS','Showing name label\n');
		p.w.patron_name_label.hidden = false;
	} else {
		sdump('D_PATRON_DISPLAY_STATUS','Hiding name label\n');
		p.w.patron_name_label.hidden = true;
	}

	p.w.patron_retrieve_button = get_widget( p.w.document, p.patron_retrieve_button );
	p.w.patron_retrieve_button.disabled = true;
	if (p.show_retrieve_button) {
		sdump('D_PATRON_DISPLAY_STATUS','Showing retrieve button\n');
		p.w.patron_retrieve_button.hidden = false;
		p.w.patron_retrieve_button.addEventListener(
			'command',
			function (ev) {
				spawn_patron_display(
					p.w.app_shell,'new_tab','main_tabbox', 
					{ 
						'patron' : p.w._patron
					}
				);
			},
			false
		);
	} else {
		sdump('D_PATRON_DISPLAY_STATUS','Hiding retrieve button\n');
		p.w.patron_retrieve_button.hidden = true;
	}

	p.w.set_patron = function (au) {
		p.w.patron_retrieve_button.disabled = false;
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

	setTimeout(
		function() {
			sdump('D_TIMEOUT','******** timeout occurred in patron_display_status.js\n');
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


