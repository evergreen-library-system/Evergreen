sdump('D_TRACE',"Loading error.js\n");

var sdump_levels = {
	'D_TRACE' :  true,
	'D_AUTH' : false,
	'D_UTIL' : false,
	'D_EXPLODE' : false,
	'D_PRINT' : false,
	'D_SES' : true
};

function sdump(level,msg) {
	try {
		if (sdump_levels[level])
			debug(msg);
	} catch(E) {}
}

function handle_error(E) {
	var s = '';
	if (instanceOf(E,ex)) {
		s += E.err_msg();
		//s += '\n\n=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=\n\n';
		//s += 'This error was anticipated.\n\n';
		//s += js2JSON(E).substr(0,200) + '...\n\n';
		if (snd_bad) snd_bad();
	} else {
		s += '\n\n=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=\n\n';
		s += 'This is a bug that we will fix later.\n\n';
		s += js2JSON(E).substr(0,200) + '\n\n';
		if (snd_really_bad) snd_really_bad();
	}
	s_alert(s);
}

