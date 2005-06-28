sdump('D_TRACE',"Loading error.js\n");

var sdump_levels = {
	'D_TRACE' :  true,
	'D_AUTH' : false,
	'D_UTIL' : false,
	'D_EXPLODE' : false,
	'D_PRINT' : false,
	'D_SES' : true,
	'D_SPAWN' : true,
	'D_TAB' : false,
	'D_OPAC' : true,
	'D_STRING' : true
};

function sdump(level,msg) {
	try {
		if (sdump_levels[level])
			debug(msg);
	} catch(E) {}
}

function arg_dump(args,dump_these) {
	var s = '*>*>*> Called function ';
	try {
		if (!dump_these)
			dump_these = {};
		s += args.callee.toString().match(/\w+/g)[1] + ' : ';
		for (var i = 0; i < args.length; i++)
			s += typeof(args[i]) + ' ';
		s += '\n';
		for (var i = 0; i < args.length; i++)
			if (dump_these[i]) {
				s += '\targ #' + i + ' = ';
				try {
					s += js2JSON( args[i] );
				} catch(E) {
					s += args[i];
				}
				s += '\n';
			}
		return s;
	} catch(E) {
		return s + '\nDEBUG ME: ' + js2JSON(E) + '\n';
	}
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

