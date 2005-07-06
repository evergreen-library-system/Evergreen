sdump('D_TRACE','Loading patron_search.js\n');

var test_variable = false;

function patron_search_init(p) {
	sdump('D_PATRON_SEARCH',"TESTING: patron_search.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_TRACE_ENTER',arg_dump(arguments));

	var clamshell = spawn_clamshell( 
		p.w.document, 'new_iframe', p.clamshell, { 
			'onload' : patron_search_init_after_clamshell(p) 
		}
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
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return function (clamshell_w) {
		sdump('D_PATRON_SEARCH',arg_dump(arguments));
		sdump('D_TRACE_ENTER',arg_dump(arguments));
		p.w.search_form = spawn_patron_search_form(
			clamshell_w.document, 
			'new_iframe', 
			clamshell_w.first_deck, {
				'onload' : patron_init_after_patron_search_form(p)
			}
		);

		p.w.result_tree = spawn_patron_search_results(
			clamshell_w.document, 
			'new_iframe', 
			clamshell_w.second_deck, {
				'onload' : patron_init_after_patron_search_results(p)
			}
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
					p.w.result_tree.add_patrons(
						p.w.crazy_search( form_w.crazy_search_hash )
					);
				}
			}
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
				alert('Selected: ' + 
					js2JSON(results_w.selection_id) + '\n');
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
		sdump('D_TRACE_EXIT',arg_dump(arguments));
		return;
	};
}
