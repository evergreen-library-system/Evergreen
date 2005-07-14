sdump('D_TRACE','Loading patron_search.js\n');

var test_variable = false;

function patron_search_init(p) {
	sdump('D_PATRON_SEARCH',"TESTING: patron_search.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_TRACE_ENTER',arg_dump(arguments));

	setTimeout(
		function () {
			sdump('D_TIMEOUT','******** timeout occurred in patron_search.js\n');
			p.w.clamshell = spawn_clamshell( 
				p.w.document, 'new_iframe', p.clamshell, { 
					'onload' : patron_search_init_after_clamshell(p) 
				}
			);
		}, 0
	);

	p.w.crazy_search = function (crazy_search_hash) {
		sdump('D_TRACE_ENTER',arg_dump(arguments));
		sdump('D_TRACE_EXIT',arg_dump(arguments));
		return patron_search( p.w, crazy_search_hash );
	};
	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return;
}

function patron_search(search_win, crazy_search_hash) {
	sdump('D_PATRON_SEARCH',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var result = [];
	try {
		result = user_request(
			'open-ils.actor',
			'open-ils.actor.patron.search.advanced',
			[ G.auth_ses[0], crazy_search_hash ]
		)[0];
		sdump('D_PATRON_SEARCH','result.length = ' + result.length + '\n');
	} catch(E) {
		handle_error(E);
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return result;
}

function patron_search_init_after_clamshell(p) {
	sdump('D_PATRON_SEARCH',arg_dump(arguments));
	return function (clamshell_w) {
		sdump('D_PATRON_SEARCH',arg_dump(arguments));
		sdump('D_TRACE_ENTER',arg_dump(arguments));
		setTimeout(
			function () {
				sdump('D_TIMEOUT','******** timeout occurred (1) after clamshell in patron_search.js\n');
				p.w.search_form = spawn_patron_search_form(
					clamshell_w.document, 
					'new_iframe', 
					clamshell_w.first_deck, {
						'onload' : patron_init_after_patron_search_form(p)
					}
				);
			}, 0
		);
		setTimeout(
			function () {
				sdump('D_TIMEOUT','******** timeout occurred (2) after clamshell in patron_search.js\n');
				p.w.result_tree = spawn_patron_search_results(
					clamshell_w.document, 
					'new_iframe', 
					clamshell_w.second_deck, {
						'onload' : patron_init_after_patron_search_results(p)
					}
				);
			}, 0
		);
		sdump('D_TRACE_EXIT',arg_dump(arguments));
		return;
	};
}

function patron_init_after_patron_search_form(p) {
	sdump('D_PATRON_SEARCH',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return function(form_w) {
		sdump('D_PATRON_SEARCH',arg_dump(arguments));
		sdump('D_TRACE_ENTER',arg_dump(arguments));
		form_w.register_search_callback(
			function (ev) {
				sdump('D_PATRON_SEARCH','Submitted: ' + 
					js2JSON(form_w.crazy_search_hash) + '\n');
				if (p.w.crazy_search) {
					p.w.result_tree.clear_patrons();
					p.w.result_tree.add_patrons(
						p.w.crazy_search( form_w.crazy_search_hash )
					);
				}
			}
		);
		setTimeout(
			function () {
				sdump('D_TIMEOUT','******** timeout occurred after patron_search_form in patron_search.js\n');
				form_w.status_w = spawn_patron_display_status( 
					form_w.document, 
					'new_iframe', 
					form_w.selection_canvas, 
					{ 'show_name' : true, 'show_retrieve_button' : true, 'app_shell' : p.w.app_shell } 
				);
			}, 1
		);
		sdump('D_TRACE_EXIT',arg_dump(arguments));
		return;
	};
}

function patron_init_after_patron_search_results(p) {
	sdump('D_PATRON_SEARCH',arg_dump(arguments));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return function(results_w) {
		sdump('D_PATRON_SEARCH',arg_dump(arguments));
		sdump('D_TRACE_ENTER',arg_dump(arguments));
		results_w.register_patron_select_callback(
			function (ev) {
				sdump('D_PATRON_SEARCH','Firing patron_select_callback\n');
				var patrons = get_list_from_tree_selection( results_w.tree_win.tree );
				p.w.search_form.status_w.display_patron(
					retrieve_patron_by_id( patrons[ patrons.length - 1 ].getAttribute('record_id') )
				);
			}
		);
		results_w.register_flesh_patron_function(
			function (treeitem) {
				sdump('D_PATRON_SEARCH',arg_dump(arguments));
				user_async_request(
					'open-ils.actor',
					'open-ils.actor.user.fleshed.retrieve',
					[ G.auth_ses[0], treeitem.getAttribute('record_id') ],
					function (request) {
						sdump('D_PATRON_SEARCH','In flesh_patron_function: ' + arg_dump(arguments));
						try {
							var patron = request.getResultObject();
							sdump('D_PATRON_SEARCH','patron = ' + js2JSON( patron ) + '\n');
							results_w.map_patron_to_cols( patron, treeitem );
						} catch(E) {
							sdump('D_ERROR',js2JSON(E) + '\n');
						}
					}
				);
			}
		);
		results_w.register_context_builder(
			function (ev) {
				empty_widget(results_w.tree_win.popup);
				var patrons = get_list_from_tree_selection( results_w.tree_win.tree );
				var menuitem = results_w.tree_win.document.createElement('menuitem');
				results_w.tree_win.popup.appendChild( menuitem );
				menuitem.setAttribute('label','Open in tab');
				menuitem.addEventListener(
					'command',
					function (ev) {
						for (var i = 0; i < patrons.length; i++) {
							spawn_patron_display(
								p.w.app_shell,'new_tab','main_tabbox', 
								{ 
									'patron' : retrieve_patron_by_id( 
										patrons[i].getAttribute('record_id') 
									)
								}
							);
						}
					},
					false
				);
			}
		);
		sdump('D_TRACE_EXIT',arg_dump(arguments));
		return;
	};
}
