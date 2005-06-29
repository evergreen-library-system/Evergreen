function OpenILS_init(params) { 
	sdump('D_TRACE','Entering OpenILS_init with ' + screen + '\n');

	try {

		switch(params.app) {
			case 'Auth' : auth_init(params); break;
			case 'AppShell' : app_shell_init(params); break;
			case 'ClamShell' : clam_shell_init(params); break;
			case 'Opac' : opac_init(params); break;
		}

		register_document(params.d);

	} catch(E) {}

	sdump('D_TRACE','Exiting OpenILS_init\n');
}

function OpenILS_exit(params) {
	sdump('D_TRACE','Entering OpenILS_exit with ' + screen + '\n');

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
