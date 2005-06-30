function OpenILS_init(params) { 
	sdump( 'D_TRACE', arg_dump( arguments, { '0':'js2JSON( map_object( arg, function (i,o) { if (i=="d") return [i,o.toString()]; else return [i,o]; }))' }));

	try {

		switch(params.app) {
			case 'Auth' : auth_init(params); break;
			case 'AppShell' : app_shell_init(params); break;
			case 'ClamShell' : clam_shell_init(params); break;
			case 'Opac' : opac_init(params); break;
		}

		register_document(params.d);

	} catch(E) {}

}

function OpenILS_exit(params) {
	sdump( 'D_TRACE', arg_dump( arguments, { '0':'js2JSON( map_object( arg, function (i,o) { if (i=="d") return [i,o.toString()]; else return [i,o]; }))' }));

	try {
	
		switch(params.app) {
			case 'Auth' : auth_exit(params); break;
			case 'AppShell' : app_shell_exit(params); break;
			case 'ClamShell' : clam_shell_exit(params); break;
			case 'Opac' : opac_exit(params); break;
		}

		unregister_document(params.d);

	} catch(E) {}

	sdump('D_TRACE','Exiting OpenILS_exit\n');
}
