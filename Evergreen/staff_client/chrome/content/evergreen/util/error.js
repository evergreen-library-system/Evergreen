sdump('D_TRACE',"Loading error.js\n");

var consoleService = Components.classes['@mozilla.org/consoleservice;1']
	.getService(Components.interfaces.nsIConsoleService);

var consoleDump = true;
var debugDump = true;
var arg_dump_full = false;

var sdump_levels = {
	'D_NONE' : false,
	'D_ALL' : false,
	'D_ERROR' : true,
	'D_TRACE' :  false,
	'D_TRACE_ENTER' :  false,
	'D_TRACE_EXIT' :  false,
	'D_TIMEOUT' :  false,
	'D_FILTER' : false,
	'D_CONSTRUCTOR' : false,

	'D_CLAM' : false,
	'D_PAGED_TREE' : false,
	'D_GRID_LIST' : true,
	'D_TAB' : false,

	'D_AUTH' : false,

	'D_OPAC' : true,

	'D_PATRON_SEARCH' : false,
	'D_PATRON_SEARCH_FORM' : false,
	'D_PATRON_SEARCH_RESULTS' : false,

	'D_PATRON_DISPLAY' : false,
	'D_PATRON_DISPLAY_STATUS' : false,
	'D_PATRON_DISPLAY_CONTACT' : false,

	'D_PATRON_ITEMS' : false,
	'D_PATRON_CHECKOUT_ITEMS' : false,
	'D_PATRON_HOLDS' : true,
	'D_PATRON_BILLS' : true,

	'D_CHECKIN' : true,
	'D_CHECKIN_ITEMS' : true,

	'D_CAT' : true,

	'D_PATRON_UTILS' : false,
	'D_CIRC_UTILS' : false,

	'D_EXPLODE' : false,
	'D_FM_UTILS' : false,
	'D_PRINT' : false,
	'D_SES' : true,
	'D_SES_FUNC' : false,
	'D_SPAWN' : true,
	'D_STRING' : false,
	'D_UTIL' : false,
	'D_WIN' : false,
	'D_WIDGETS' : false

};

var sdump_last_time = new Date();

function filter_console_init(p) {
	sdump('D_FILTER',arg_dump(arguments,{0:true}));

	var filterConsoleListener = {
		observe: function( msg ) {
			try {
				p.observe_msg( msg );
			} catch(E) {
				alert(E);
			}
		},
		QueryInterface: function (iid) {
			if (!iid.equals(Components.interfaces.nsIConsoleListener) &&
				!iid.equals(Components.interfaces.nsISupports)) {
					throw Components.results.NS_ERROR_NO_INTERFACE;
			}
		        return this;
		}
	};
	try {
		consoleService.registerListener(filterConsoleListener);	
	} catch(E) {
		alert(E);
	}

	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function sdump(level,msg) {
	try {
		var now = new Date();
		var message = now.valueOf() + '\tdelta = ' + (now.valueOf() - sdump_last_time.valueOf()) + '\n' + level + '\n' + msg;
		if (sdump_levels['D_NONE']) return;
		if (sdump_levels[level]||sdump_levels['D_ALL']) {
			sdump_last_time = now;
			if (debugDump)
				debug(message);
			if (consoleDump)
				consoleService.logStringMessage(message);
		}
	} catch(E) {
		dump('Calling sdump but ' + E + '\n');
	}
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
				if (arg_dump_full)
					s += 'Definition: ' + args.callee.toString() + '\n';

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

