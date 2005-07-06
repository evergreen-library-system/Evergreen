sdump('D_TRACE',"Loading error.js\n");

var consoleService = Components.classes['@mozilla.org/consoleservice;1']
	.getService(Components.interfaces.nsIConsoleService);

var consoleDump = true;

var sdump_levels = {
	'D_ERROR' : true,
	'D_TRACE' :  true,

	'D_CLAM' : false,
	'D_PAGED_TREE' : true,
	'D_TAB' : false,

	'D_AUTH' : false,

	'D_OPAC' : true,

	'D_PATRON_SEARCH' : true,
	'D_PATRON_SEARCH_FORM' : true,
	'D_PATRON_SEARCH_RESULTS' : true,

	'D_EXPLODE' : false,
	'D_PRINT' : false,
	'D_SES' : false,
	'D_SPAWN' : true,
	'D_STRING' : false,
	'D_UTIL' : false,
	'D_WIN' : false

};

function sdump(level,msg) {
	try {
		if (sdump_levels[level]) {
			debug(level + ': ' + msg);
			if (consoleDump)
				consoleService.logStringMessage(level + ': ' + msg);
		}
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

				var arg = args[i];
				//dump('dump_these[i] = ' + dump_these[i] + '  arg = ' + arg + '\n');

				if (typeof(dump_these[i])=='string') {

					if (dump_these[i].slice(0,1) == '.') {
						var cmd = 'arg' + dump_these[i];
						var result;
						try {
							result = eval( cmd );
						} catch(E) {
							result = cmd + ' ==> ' + E;
						}
						s += '\targ #' + i + ': ' + cmd + ' = ' + result;
					} else {
						var result;
						try {
							result = eval( dump_these[i] );
						} catch(E) {
							result = dump_these[i] + ' ==> ' + E;
						}
						s += '\targ #' + i + ': ' + result;
					}

				} else {
					s += '\targ #' + i + ' = ';
					try {
						s += js2JSON( arg );
					} catch(E) {
						s += arg;
					}
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
	sdump('D_ERROR',s);
	s_alert(s);
}

