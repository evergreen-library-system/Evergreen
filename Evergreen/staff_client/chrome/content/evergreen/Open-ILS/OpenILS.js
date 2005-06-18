function OpenILS_init(screen) { 
	sdump('D_TRACE','Entering OpenILS_init with ' + screen + '\n');

	switch(screen) {
		case 'auth' : auth_init(); break;
	}

	sdump('D_TRACE','Exiting OpenILS_init\n');
}

