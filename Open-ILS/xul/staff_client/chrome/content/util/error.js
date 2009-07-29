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

	JSAN.use('util.sound'); this.sound = new util.sound();

	return this;
};

util.error.prototype = {

	'printDebug' : true,
	'consoleDump' : false,
	'debugDump' : true,
	'fileDump' : false,
	'alertDump' : false,
	'arg_dump_full' : false,

	'debug' : function(e){
		dump('-----------------------------------------\n' 
			+ e + '\n-----------------------------------------\n' );
	},

	'sdump_levels' : {

		'D_NONE' : false, 
		'D_ALL' : false, 
		'D_ERROR' : { 'dump' : true, 'console' : true }, 
		'D_DEBUG' : { 'dump' : true, 'console' : true }, 
		'D_TRACE' :  { 'dump' : true }, 
		'D_ALERT' : { 'alert' : true, 'dump' : true },
		'D_WARN' : false, 
		'D_COLUMN_RENDER_ERROR' : false, 
		'D_XULRUNNER' : false, 
		'D_DECK' : { 'dump' : true },
		'D_TRACE_ENTER' :  false, 
		'D_TRACE_EXIT' :  false, 
		'D_TIMEOUT' :  false, 
		'D_FILTER' : false,
		'D_CONSTRUCTOR' : false, 
		'D_FIREFOX' : false, 
		'D_LEGACY' : false, 
		'D_DATA_STASH' : { 'alert' : false }, 
		'D_DATA_RETRIEVE' : false,

		'D_CLAM' : false, 
		'D_PAGED_TREE' : false, 
		'D_GRID_LIST' : false, 
		'D_HTML_TABLE' : false,
		'D_TAB' : false, 
		'D_LIST' : false, 
		'D_LIST_DUMP_WITH_KEYS_ON_CLEAR' : false, 
		'D_LIST_DUMP_ON_CLEAR' : false,

		'D_AUTH' : { 'dump' : true }, 
		'D_OPAC' : { 'dump' : true }, 
		'D_CAT' : false, 
		'D_BROWSER' : { 'dump' : true },

		'D_PATRON_SEARCH' : false, 
		'D_PATRON_SEARCH_FORM' : false, 
		'D_PATRON_SEARCH_RESULTS' : false,

		'D_PATRON_DISPLAY' : false, 
		'D_PATRON_DISPLAY_STATUS' : false, 
		'D_PATRON_DISPLAY_CONTACT' : false,

		'D_PATRON_ITEMS' : false, 
		'D_PATRON_CHECKOUT_ITEMS' : false, 
		'D_PATRON_HOLDS' : false,
		'D_PATRON_BILLS' : false, 
		'D_PATRON_EDIT' : false,

		'D_CHECKIN' : false, 
		'D_CHECKIN_ITEMS' : false,

		'D_HOLD_CAPTURE' : false, 
		'D_HOLD_CAPTURE_ITEMS' : false,

		'D_PATRON_UTILS' : false, 
		'D_CIRC_UTILS' : false,

		'D_FILE' : false, 
		'D_EXPLODE' : false, 
		'D_FM_UTILS' : false, 
		'D_PRINT' : { 'dump' : true }, 
		'D_OBSERVERS' : { 'dump' : true, 'console' : false, 'alert' : false },
		'D_CACHE' : { 'dump' : true, 'console' : false, 'alert' : false },
		'D_SES' : { 'dump' : true, 'console' : false },
		'D_SES_FUNC' : false, 
		'D_SES_RESULT' : { 'dump' : true }, 
		'D_SES_ERROR' : { 'dump' : true, 'console' : true }, 
		'D_SPAWN' : false, 
		'D_STRING' : false,
		'D_UTIL' : false, 
		'D_WIN' : { 'dump' : true }, 
		'D_WIDGETS' : false
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
				if (this.debugDump || ( this.sdump_levels[level] && this.sdump_levels[level].debug ) ) this.debug(message);
				if (this.alertDump || ( this.sdump_levels[level] && this.sdump_levels[level].alert ) ) alert(message);
				if (this.consoleDump || ( this.sdump_levels[level] && this.sdump_levels[level].console ) ) {
					netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
					this.consoleService.logStringMessage(message);
				}
				if (this.fileDump || ( this.sdump_levels[level] && this.sdump_levels[level].file ) ) {
					if (level!='D_FILE') {
						netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
						JSAN.use('util.file'); var master_log = new util.file('log');
						master_log.write_content('append',message); master_log.close();
						var specific_log = new util.file('log_'+level);
						specific_log.write_content('append',message); specific_log.close();
					}
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

	'standard_network_error_alert' : function(msg) {
		var obj = this;
		if (!msg) msg = '';
		var alert_msg = 'We experienced a network/server communication failure.  Please check your internet connection and try this action again.  Repeated failures may require attention from your local IT staff or your friendly Evergreen developers.\n\n' + msg;
		obj.yns_alert(
			alert_msg,	
			'Communication Failure',
			'Ok', null, null, 'Check here to confirm this message'
		);
	},

	'standard_unexpected_error_alert' : function(msg,E) {
		var obj = this;
		if (E != null && typeof E.ilsevent != 'undefined') {
			if (E.ilsevent == 0 /* SUCCESS */ ) {
				msg = "The action involved likely succeeded, however, this part of the software needs to be updated to better understand success messages from the server, so please let us know about it.";
			}
			if (E.ilsevent == -1 /* Network/Server Problem */ ) {
				return obj.standard_network_error_alert(msg);
			}
			if (E.ilsevent == 5000 /* PERM_FAILURE */ ) {
				msg = "The action involved likely failed due to insufficient permissions.  However, this part of the software needs to be updated to better understand permission messages from the server, so please let us know about it.";
			}
		}
		if (!msg) msg = '';
		var alert_msg = 'FIXME:  If you encounter this alert, please inform your IT/ILS helpdesk staff or your friendly Evergreen developers.\n\n' + (new Date()) + '\n\n' + msg + '\n\n' + (typeof E.ilsevent != 'undefined' ? E.textcode + '\n' + (E.desc ? E.desc + '\n' : '') : '') + ( typeof E.status != 'undefined' ? 'Status: ' + E.status + '\n': '' ) + ( typeof E == 'string' ? E + '\n' : '' );
		obj.sdump('D_ERROR',msg + ' : ' + js2JSON(E));
		var r = obj.yns_alert(
			alert_msg,	
			'Unhandled Error',
			'Ok', 'Debug Output to send to Helpdesk', null, 'Check here to confirm this message',
			'/xul/server/skin/media/images/skull.png'
		);
		if (r == 1) {
			JSAN.use('util.window'); var win = new util.window();
			win.open(
				'data:text/plain,' + window.escape( 'Please open a helpdesk ticket and include the following text: \n\n' + (new Date()) + '\n\n' + msg + '\n\n' + obj.pretty_print(js2JSON(E)) ),
				'error_alert',
				'chrome,resizable,width=700,height=500'
			);
		}
		if (r==2) {
			alert('Not Yet Implemented');
		}
	},

	'yns_alert' : function (s,title,b1,b2,b3,c,image) {

		try {

			if (location.href.match(/^chrome/)) return this.yns_alert_original(s,title,b1,b2,b3,c);

		/* The original purpose of yns_alert was to prevent errors from being scanned through accidentally with a barcode scanner.  
		However, this can be done in a less annoying manner by rolling our own dialog and not having any of the options in focus */

		/*
			s 	= Message to display
			title 	= Text in Title Bar
			b1	= Text for button 1
			b2	= Text for button 2
			b3	= Text for button 3
			c	= Text for confirmation checkbox.  null for no confirm
		*/

		dump('yns_alert:\n\ts = ' + s + '\n\ttitle = ' + title + '\n\tb1 = ' + b1 + '\n\tb2 = ' + b2 + '\n\tb3 = ' + b3 + '\n\tc = ' + c + '\n');
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect UniversalBrowserWrite");

		this.sound.bad();


		//FIXME - is that good enough of an escape job?
		s = s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

		var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" xmlns:html="http://www.w3.org/1999/xhtml" flex="1">' 
			+ '<groupbox flex="1" style="overflow: auto; border: solid thin red;"><caption label="' + (title) + '"/>';

		if (image) xml += '<hbox><image src="' + image + '"/><spacer flex="1"/></hbox>';
		xml += '<description style="font-size: large">' + (s)
			+ '</description></groupbox><groupbox><caption label="Options"/><hbox>';
		var b1_key = b1 ? b1[0] : '';
		var b2_key = b2 ? b2[0] : '';
		var b3_key = b3 ? b3[0] : ''; /* FIXME - need to check for collisions */
		if (b1) xml += '<button id="b1" accesskey="' + b1_key + '" label="' + (b1) + '" name="fancy_submit" value="b1"/>'
		if (b2) xml += '<button id="b2" accesskey="' + b2_key + '" label="' + (b2) + '" name="fancy_submit" value="b2"/>'
		if (b3) xml += '<button id="b3" accesskey="' + b3_key + '" label="' + (b3) + '" name="fancy_submit" value="b3"/>'
		xml += '</hbox></groupbox></vbox>';
		JSAN.use('OpenILS.data');
		//var data = new OpenILS.data(); data.init({'via':'stash'});
		//data.temp_yns_xml = xml; data.stash('temp_yns_xml');
		var url = urls.XUL_FANCY_PROMPT; // + '?xml_in_stash=temp_yns_xml' + '&title=' + window.escape(title);
		if (typeof xulG != 'undefined') if (typeof xulG.url_prefix == 'function') url = xulG.url_prefix( url );
		JSAN.use('util.window'); var win = new util.window();
		var fancy_prompt_data = win.open(
			url, 'fancy_prompt', 'chrome,resizable,modal,width=700,height=500', { 'xml' : xml, 'title' : title }
		);
		if (fancy_prompt_data.fancy_status == 'complete') {
			switch(fancy_prompt_data.fancy_submit) {
				case 'b1' : return 0; break;
				case 'b2' : return 1; break;
				case 'b3' : return 2; break;
			}
		} else {
			//return this.yns_alert(s,title,b1,b2,b3,c,image);
			return null;
		}

		} catch(E) {

			dump('yns_alert failed: ' + E + '\ns = ' + s + '\ntitle = ' + title + '\nb1 = ' + b1 + '\nb2 = ' + b2 + '\nb3 = ' + b3 + '\nc = ' + c + '\nimage = ' + image + '\n');

			this.yns_alert_original(s + '\n\nAlso, yns_alert failed: ' + E,title,b1,b2,b3,c);

		}
	},

	'yns_alert_formatted' : function (s,title,b1,b2,b3,c,image) {

		try {

			if (location.href.match(/^chrome/)) return this.yns_alert_original(s,title,b1,b2,b3,c);

		/* The original purpose of yns_alert was to prevent errors from being scanned through accidentally with a barcode scanner.  
		However, this can be done in a less annoying manner by rolling our own dialog and not having any of the options in focus */

		/*
			s 	= Message to display
			title 	= Text in Title Bar
			b1	= Text for button 1
			b2	= Text for button 2
			b3	= Text for button 3
			c	= Text for confirmation checkbox.  null for no confirm
		*/

		dump('yns_alert:\n\ts = ' + s + '\n\ttitle = ' + title + '\n\tb1 = ' + b1 + '\n\tb2 = ' + b2 + '\n\tb3 = ' + b3 + '\n\tc = ' + c + '\n');
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect UniversalBrowserWrite");

		this.sound.bad();


		//FIXME - is that good enough of an escape job?
		s = s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

		var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" xmlns:html="http://www.w3.org/1999/xhtml" flex="1">' 
			+ '<groupbox flex="1" style="overflow: auto; border: solid thin red;"><caption label="' + (title) + '"/>';

		if (image) xml += '<hbox><image src="' + image + '"/><spacer flex="1"/></hbox>';
		xml += '<description style="font-size: large"><html:pre style="font-size: large">' + (s)
			+ '</html:pre></description></groupbox><groupbox><caption label="Options"/><hbox>';
		var b1_key = b1 ? b1[0] : '';
		var b2_key = b2 ? b2[0] : '';
		var b3_key = b3 ? b3[0] : ''; /* FIXME - need to check for collisions */
		if (b1) xml += '<button id="b1" accesskey="' + b1_key + '" label="' + (b1) + '" name="fancy_submit" value="b1"/>'
		if (b2) xml += '<button id="b2" accesskey="' + b2_key + '" label="' + (b2) + '" name="fancy_submit" value="b2"/>'
		if (b3) xml += '<button id="b3" accesskey="' + b3_key + '" label="' + (b3) + '" name="fancy_submit" value="b3"/>'
		xml += '</hbox></groupbox></vbox>';
		JSAN.use('OpenILS.data');
		//var data = new OpenILS.data(); data.init({'via':'stash'});
		//data.temp_yns_xml = xml; data.stash('temp_yns_xml');
		var url = urls.XUL_FANCY_PROMPT; // + '?xml_in_stash=temp_yns_xml' + '&title=' + window.escape(title);
		if (typeof xulG != 'undefined') if (typeof xulG.url_prefix == 'function') url = xulG.url_prefix( url );
		JSAN.use('util.window'); var win = new util.window();
		var fancy_prompt_data = win.open(
			url, 'fancy_prompt', 'chrome,resizable,modal,width=700,height=500', { 'xml' : xml, 'title' : title }
		);
		if (fancy_prompt_data.fancy_status == 'complete') {
			switch(fancy_prompt_data.fancy_submit) {
				case 'b1' : return 0; break;
				case 'b2' : return 1; break;
				case 'b3' : return 2; break;
			}
		} else {
			//return this.yns_alert(s,title,b1,b2,b3,c,image);
			return null;
		}

		} catch(E) {

			alert('yns_alert_formatted failed: ' + E + '\ns = ' + s + '\ntitle = ' + title + '\nb1 = ' + b1 + '\nb2 = ' + b2 + '\nb3 = ' + b3 + '\nc = ' + c + '\nimage = ' + image + '\n');

		}

	},

	'yns_alert_original' : function (s,title,b1,b2,b3,c) {

		/*
			s 	= Message to display
			title 	= Text in Title Bar
			b1	= Text for button 1
			b2	= Text for button 2
			b3	= Text for button 3
			c	= Text for confirmation checkbox.  null for no confirm
		*/

		dump('yns_alert_original:\n\ts = ' + s + '\n\ttitle = ' + title + '\n\tb1 = ' + b1 + '\n\tb2 = ' + b2 + '\n\tb3 = ' + b3 + '\n\tc = ' + c + '\n');
		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");

		this.sound.bad();

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
		
		// promptService.confirmEx does not offer scrollbars for long
		// content, so trim error lines to avoid spilling offscreen
		//
		// There's probably a better way of doing this.

		var maxlines = 30;
		var ss = '';
		var linefeeds = 0;
		for (var i=0, chr; linefeeds < maxlines && i < s.length; i++) {  
			if ((chr = this.getWholeChar(s, i)) === false) {continue;}
			if (chr == '\u000A') { // \n
				linefeeds++;
			}	
			ss = ss + chr;
		}
		
		var rv = promptService.confirmEx(window,title, ss, flags, b1, b2, b3, c, check);
		if (c && !check.value) {
			return this.yns_alert_original(ss,title,b1,b2,b3,c);
		}
		return rv;
	},

	'print_tabs' : function(t) {
		var r = '';
		for (var j = 0; j < t; j++ ) { r = r + "\t"; }
		return r;
	},

	'pretty_print' : function(s) {
		var r = ''; var t = 0;
		for (var i in s) {
			if (s[i] == '{') {
				r = r + "\n" + this.print_tabs(t) + s[i]; t++;
				r = r + "\n" + this.print_tabs(t);
			} else if (s[i] == '[') {
				r = r + "\n" + this.print_tabs(t) + s[i]; t++;
				r = r + "\n" + this.print_tabs(t);
			} else if (s[i] == '}') {
				t--; r = r + "\n" + this.print_tabs(t) + s[i];
				r = r + "\n" + this.print_tabs(t);
			} else if (s[i] == ']') {
				t--; r = r + "\n" + this.print_tabs(t) + s[i];
				r = r + "\n" + this.print_tabs(t);
			} else if (s[i] == ',') {
				r = r + s[i];
				r = r + "\n" + this.print_tabs(t);
			} else {
				r = r + s[i];
			}
		}
		return r;
	},

	// Copied from https://developer.mozilla.org/en/Core_JavaScript_1.5_Reference/Global_Objects/String/charCodeAt
	'getWholeChar' : function(str, i) {  
		var code = str.charCodeAt(i);  
		if (0xD800 <= code && code <= 0xDBFF) { // High surrogate(could change last hex to 0xDB7F to treat high private surrogates as single characters)  
			if (str.length <= (i+1))  {  
				throw 'High surrogate without following low surrogate';  
			}  
			var next = str.charCodeAt(i+1);  
			if (0xDC00 > next || next > 0xDFFF) {  
				throw 'High surrogate without following low surrogate';  
			}  
			return str[i]+str[i+1];  
		}  
		else if (0xDC00 <= code && code <= 0xDFFF) { // Low surrogate  
			if (i === 0) {  
				throw 'Low surrogate without preceding high surrogate';  
			}  
			var prev = str.charCodeAt(i-1);  
			if (0xD800 > prev || prev > 0xDBFF) { //(could change last hex to 0xDB7F to treat high private surrogates as single characters)  
				throw 'Low surrogate without preceding high surrogate';  
			}  
			return false; // We can pass over low surrogates now as the second component in a pair which we have already processed  
		}  
		return str[i];  
	}  
}

dump('exiting util/error.js\n');
