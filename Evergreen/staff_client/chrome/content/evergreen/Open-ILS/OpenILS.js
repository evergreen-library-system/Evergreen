function OpenILS_init(params) { 
	sdump( 'D_TRACE', arg_dump( arguments, { '0':'js2JSON( map_object( arg,function(i,o){try{return [i,o.toString()];}catch(E){return [i,o];}}))' }));

	try {

		switch(params.app) {
			case 'Auth' : auth_init(params); break;
			case 'AppShell' : app_shell_init(params); register_AppShell(params.w); break;
			case 'ClamShell' : clam_shell_init(params); break;
			case 'PagedTree' : paged_tree_init(params); break;
			case 'Opac' : opac_init(params); break;
			case 'PatronSearch' : patron_search_init(params); break;
			case 'PatronSearchForm' : patron_search_form_init(params); break;
			case 'PatronSearchResults' : patron_search_results_init(params); break;
			case 'PatronDisplay' : patron_display_init(params); break;
			case 'PatronDisplayStatus' : patron_display_status_init(params); break;
			case 'PatronDisplayContact' : patron_display_contact_init(params); break;
			case 'CircTree' : circ_tree_init(params); break;
		}

	} catch(E) { sdump('D_ERROR',js2JSON(E)+'\n'); }

	try {

		//register_document(params.w.document);
		register_window(params.w);

	} catch(E) { sdump('D_ERROR',js2JSON(E)+'\n'); }

}

function OpenILS_exit(params) {
	sdump( 'D_TRACE', arg_dump( arguments, { '0':'js2JSON( map_object( arg,function(i,o){try{return [i,o.toString()];}catch(E){return [i,o];}}))' }));
	params.w.document.firstChild.setAttribute('style','background-color: red;');
	return;

	try {
	
		switch(params.app) {
			case 'Auth' : auth_exit(params); break;
			case 'AppShell' : app_shell_exit(params); unregister_AppShell(params.w); break;
			case 'ClamShell' : clam_shell_exit(params); break;
			case 'PagedTree' : paged_tree_exit(params); break;
			case 'Opac' : opac_exit(params); break;
			case 'PatronSearch' : patron_search_exit(params); break;
			case 'PatronSearchForm' : patron_search_form_exit(params); break;
			case 'PatronSearchResults' : patron_search_results_exit(params); break;
			case 'PatronDisplay' : patron_display_exit(params); break;
			case 'PatronDisplayStatus' : patron_display_status_exit(params); break;
			case 'PatronDisplayContact' : patron_display_contact_exit(params); break;
			case 'CircTree' : circ_tree_exit(params); break;
		}

	} catch(E) { sdump('D_ERROR',js2JSON(E)+'\n'); }

	try {

		// buggy for now
		//unregister_document(params.w.document);
		unregister_window(params.w);

	} catch(E) { sdump('D_ERROR',js2JSON(E)+'\n'); }

	sdump('D_TRACE','Exiting OpenILS_exit\n');
}
