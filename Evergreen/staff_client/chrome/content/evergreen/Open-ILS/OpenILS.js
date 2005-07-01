function OpenILS_init(params) { 
	sdump( 'D_TRACE', arg_dump( arguments, { '0':'js2JSON( map_object( arg, function (i,o) { if (i=="d"||i=="w") return [i,o.toString()]; else return [i,o]; }))' }));

	try {

		switch(params.app) {
			case 'Auth' : auth_init(params); break;
			case 'AppShell' : app_shell_init(params); break;
			case 'ClamShell' : clam_shell_init(params); break;
			case 'Opac' : opac_init(params); break;
			case 'PatronSearch' : patron_search_init(params); break;
			case 'PatronSearchForm' : patron_search_form_init(params); break;
		}

	} catch(E) { dump(js2JSON(E)+'\n'); }

	try {

		register_document(params.w.document);
		register_window(params.w);

	} catch(E) { dump(js2JSON(E)+'\n'); }

}

function OpenILS_exit(params) {
	sdump( 'D_TRACE', arg_dump( arguments, { '0':'js2JSON( map_object( arg, function (i,o) { if (i=="d"||i=="w") return [i,o.toString()]; else return [i,o]; }))' }));

	try {
	
		switch(params.app) {
			case 'Auth' : auth_exit(params); break;
			case 'AppShell' : app_shell_exit(params); break;
			case 'ClamShell' : clam_shell_exit(params); break;
			case 'Opac' : opac_exit(params); break;
			case 'PatronSearch' : patron_search_exit(params); break;
			case 'PatronSearchForm' : patron_search_form_exit(params); break;
		}

	} catch(E) { dump(js2JSON(E)+'\n'); }

	try {

		// buggy for now
		//unregister_document(params.w.document);
		//unregister_window(params.w);

	} catch(E) { dump(js2JSON(E)+'\n'); }

	sdump('D_TRACE','Exiting OpenILS_exit\n');
}
