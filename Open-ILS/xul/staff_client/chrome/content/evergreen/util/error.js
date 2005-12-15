dump('entering util/error.js\n');

if (typeof util == 'undefined') util = {};
util.error = function () {

	try {
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		this.consoleService = Components.classes['@mozilla.org/consoleservice;1']
			.getService(Components.interfaces.nsIConsoleService);
	} catch(E) {
		this.consoleDump = false;
		dump('util.error constructor: ' + E + '\n');
	}

	this.sdump_last_time = new Date();

	this.OpenILS = {};

	return this;
};

util.error.prototype = {

	'printDebug' : true,
	'consoleDump' : true,
	'debugDump' : true,
	'arg_dump_full' : false,

	'debug' : function(e){
		dump('-----------------------------------------\n' 
			+ e + '\n-----------------------------------------\n' );
	},

	'sdump_levels' : {

		'D_NONE' : false, 'D_ALL' : true, 'D_ERROR' : true, 'D_DEBUG' : true, 'D_TRACE' :  false,
		'D_TRACE_ENTER' :  false, 'D_TRACE_EXIT' :  false, 'D_TIMEOUT' :  false, 'D_FILTER' : false,
		'D_CONSTRUCTOR' : false, 'D_FIREFOX' : false, 'D_LEGACY' : false,

		'D_CLAM' : false, 'D_PAGED_TREE' : false, 'D_GRID_LIST' : false, 'D_HTML_TABLE' : false,
		'D_TAB' : false,

		'D_AUTH' : true, 'D_OPAC' : true, 'D_CAT' : false,

		'D_PATRON_SEARCH' : false, 'D_PATRON_SEARCH_FORM' : false, 'D_PATRON_SEARCH_RESULTS' : false,

		'D_PATRON_DISPLAY' : false, 'D_PATRON_DISPLAY_STATUS' : false, 'D_PATRON_DISPLAY_CONTACT' : false,

		'D_PATRON_ITEMS' : false, 'D_PATRON_CHECKOUT_ITEMS' : false, 'D_PATRON_HOLDS' : false,
		'D_PATRON_BILLS' : false, 'D_PATRON_EDIT' : false,

		'D_CHECKIN' : false, 'D_CHECKIN_ITEMS' : false,

		'D_HOLD_CAPTURE' : false, 'D_HOLD_CAPTURE_ITEMS' : false,

		'D_PATRON_UTILS' : false, 'D_CIRC_UTILS' : false,

		'D_FILE' : true, 'D_EXPLODE' : false, 'D_FM_UTILS' : false, 'D_PRINT' : false, 'D_SES' : true,
		'D_SES_FUNC' : false, 'D_SES_RESULT' : true, 'D_SPAWN' : false, 'D_STRING' : false,
		'D_UTIL' : false, 'D_WIN' : true, 'D_WIDGETS' : false
	},

	'filter_console_init' : function (p) {
		this.sdump('D_FILTER',this.arg_dump(arguments,{0:true}));

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
			this.consoleService.registerListener(filterConsoleListener);	
		} catch(E) {
			alert(E);
		}

		this.sdump('D_TRACE_EXIT',this.arg_dump(arguments));
	},

	'sdump' : function (level,msg) {
		try {
			var now = new Date();
			var message = now.valueOf() + '\tdelta = ' + (now.valueOf() - this.sdump_last_time.valueOf()) + '\t' + level + '\n' + msg;
			if (this.sdump_levels['D_NONE']) return null;
			if (this.sdump_levels[level]||this.sdump_levels['D_ALL']) {
				this.sdump_last_time = now;
				if (this.debugDump)
					this.debug(message);
				if (this.consoleDump) {
					netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
					this.consoleService.logStringMessage(message);
				}
			}
		} catch(E) {
			dump('Calling sdump but ' + E + '\n');
		}
	},

	'arg_dump' : function (args,dump_these) {
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
							//s += js2JSON( arg );
							s += arg;
						} catch(E) {
							s += arg;
						}
					}
	
					s += '\n';
					if (this.arg_dump_full)
						s += 'Definition: ' + args.callee.toString() + '\n';
	
				}
			return s;
		} catch(E) {
			return s + '\nDEBUG ME: ' + js2JSON(E) + '\n';
		}
	},

	'handle_error' : function (E,annoy) {
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
			try {
				s += js2JSON(E).substr(0,1024) + '\n\n';
			} catch(E2) {
				try {
					s += E.substr(0,1024) + '\n\n';
				} catch(E3) {
					s += E + '\n\n';
				}
			}
			if (snd_really_bad) snd_really_bad();
		}
		sdump('D_ERROR',s);
		if (annoy)
			this.s_alert(s);
		else
			alert(s);
	},

	's_alert' : function (s) { alert(s); },

	'get_ilsevent' : function(status) {
		JSAN.use('OpenILS.data'); 
		this.OpenILS.data = new OpenILS.data(); this.OpenILS.data.init({'via':'stash'});
		return this.OpenILS.data.entities['ilsevent.'+status];
	},

	'yns_alert' : function (s,title,b1,b2,b3,c) {

		/*
			s 	= Message to display
			title 	= Text in Title Bar
			b1	= Text for button 1
			b2	= Text for button 2
			b3	= Text for button 3
			c	= Text for confirmation checkbox.  null for no confirm
		*/

		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");

		// get a reference to the prompt service component.
		var promptService = Components.classes["@mozilla.org/embedcomp/prompt-service;1"]
			.getService(Components.interfaces.nsIPromptService);

		// set the buttons that will appear on the dialog. It should be
		// a set of constants multiplied by button position constants. In this case,
		// three buttons appear, Save, Cancel and a custom button.
		//var flags=promptService.BUTTON_TITLE_OK * promptService.BUTTON_POS_0 +
		//	promptService.BUTTON_TITLE_CANCEL * promptService.BUTTON_POS_1 +
		//	promptService.BUTTON_TITLE_IS_STRING * promptService.BUTTON_POS_2;
		var flags = promptService.BUTTON_TITLE_IS_STRING * promptService.BUTTON_POS_0 +
			promptService.BUTTON_TITLE_IS_STRING * promptService.BUTTON_POS_1 +
			promptService.BUTTON_TITLE_IS_STRING * promptService.BUTTON_POS_2; 

		// display the dialog box. The flags set above are passed
		// as the fourth argument. The next three arguments are custom labels used for
		// the buttons, which are used if BUTTON_TITLE_IS_STRING is assigned to a
		// particular button. The last two arguments are for an optional check box.
		var check = {};
		var rv = promptService.confirmEx(window,title, s, flags, b1, b2, b3, c, check);
		if (c && !check.value) {
			return this.yns_alert(s,title,b1,b2,b3,c);
		}
		return rv;
	},
}

dump('exiting util/error.js\n');
