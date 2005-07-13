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
			p.w.status_w.display_patron();
		if (p.w.contact_w)
			p.w.contact_w.display_patron();
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

	sdump('D_TRACE','******** SETTING TIMEOUT\n');
	setTimeout( 
		function() {
			sdump('D_TRACE','******** TIMEOUT OCCURRED\n');
			p.w.clamshell = spawn_clamshell( 
				p.w.document, 'new_iframe', p.clamshell, {
					'horizontal' : true,
					'onload' : patron_display_init_after_clamshell(p) 
				}
			);
		}
		,0
	);
	sdump('D_TRACE','******** AFTER SETTING TIMEOUT\n');

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return;
}

function patron_display_init_after_clamshell(p) {
	sdump('D_PATRON_DISPLAY',arg_dump(arguments));
	return function (clamshell_w) {
		setTimeout(
			function() {
				p.w.inner_clamshell = spawn_clamshell_vertical( 
					clamshell_w.document, 
					'new_iframe', 
					clamshell_w.first_deck, {
						'vertical' : true,
						'onload' : patron_display_init_after_inner_clamshell(p)
					}
				);
			}, 0
		);
		setTimeout(
			function() {
				p.w.item_tree = spawn_circ_tree( 
					clamshell_w.document, 
					'new_iframe', 
					clamshell_w.second_deck, {
						'paged_tree_onload' : patron_display_init_after_item_tree_paged_tree(p),
						'onload' : patron_display_init_after_item_tree(p)
					}
				);
			}, 0
		);
		return;
	};

}

function patron_display_init_after_item_tree_paged_tree(p) {
	sdump('D_PATRON_DISPLAY',arg_dump(arguments));
	return function (tree_win) {
		if (p.w._patron) {
			if (!p.w._patron.checkouts()) patron_get_checkouts( p.w._patron );
			for (var i = 0; i < p.w._patron.checkouts().length; i++) {
				p.w.item_tree.add_circs( [ i ] );
			}
		}
	};
};

function patron_display_init_after_inner_clamshell(p) {
	sdump('D_PATRON_DISPLAY',arg_dump(arguments));
	return function (clamshell_w) {
		sdump('D_PATRON_DISPLAY',arg_dump(arguments));
		setTimeout(
			function() {
				p.w.status_w = spawn_patron_display_status(
					clamshell_w.document, 
					'new_iframe', 
					clamshell_w.first_deck, {
						'patron' : p.w._patron
					}
				);
			}, 0
		);
		setTimeout(
			function() {
				p.w.contact_w = spawn_patron_display_contact(
					clamshell_w.document, 
					'new_iframe', 
					clamshell_w.second_deck, {
						'patron' : p.w._patron
					}
				);
			}, 0
		);
		return;
	};
}

function patron_display_init_after_item_tree(p) {
	sdump('D_PATRON_DISPLAY',arg_dump(arguments));
	return function (item_tree_w) {
		sdump('D_PATRON_DISPLAY',arg_dump(arguments));
		item_tree_w.register_circ_select_callback(
			function (ev) {
				sdump('D_PATRON_DISPLAY','Firing circ_select_callback\n');
				var circs = get_list_from_tree_selection( item_tree_w.tree_win.tree );
				/* grab cover art for selected item? */
			}
		);
		item_tree_w.register_flesh_circ_function(
			function (treeitem) {
				sdump('D_PATRON_DISPLAY',arg_dump(arguments));
				/* A little kludgy if the patron's checkouts change while the list is being navigated, but since
				there is no network traffic, it may be worth clearing and rebuilding the tree when updating */
				var record_id = treeitem.getAttribute('record_id'); 
				item_tree_w.map_circ_to_cols( p.w._patron.checkouts()[ record_id ], treeitem );
			}
		);
		item_tree_w.register_context_builder(
			function (ev) {
				/* add check-in and renew options */
				empty_widget(item_tree_w.tree_win.popup);
				var circs = get_list_from_tree_selection( item_tree_w.tree_win.tree );
				var menuitem = item_tree_w.tree_win.document.createElement('menuitem');
				item_tree_w.tree_win.popup.appendChild( menuitem );
				menuitem.setAttribute('label','Open in OPAC');
				menuitem.addEventListener(
					'command',
					function (ev) {
						for (var i = 0; i < circs.length; i++) {
							spawn_circ_display(
								p.w.app_shell,'new_tab','main_tabbox', 
								{ 
									'circ' : retrieve_circ_by_id( 
										circs[i].getAttribute('record_id') 
									)
								}
							);
						}
					},
					false
				);
			}
		);
	};
}
