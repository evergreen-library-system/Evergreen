function OpenILS_init(screen) { 
	sdump('D_TRACE','Entering OpenILS_init with ' + screen + '\n');

	switch(screen) {
		case 'Auth' : auth_init(); break;
		case 'AppShell' : app_shell_init(); break;
	}

	sdump('D_TRACE','Exiting OpenILS_init\n');
}

