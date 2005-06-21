function OpenILS_init(screen,params) { 
	sdump('D_TRACE','Entering OpenILS_init with ' + screen + '\n');

	switch(screen) {
		case 'Auth' : auth_init(params); break;
		case 'AppShell' : app_shell_init(params); break;
	}

	sdump('D_TRACE','Exiting OpenILS_init\n');
}

