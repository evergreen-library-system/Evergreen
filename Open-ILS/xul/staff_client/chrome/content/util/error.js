dump('entering util/error.js\n');

if (typeof util == 'undefined') util = {};
util.error = function () {

    try {

        try {
            this.consoleService = Components.classes['@mozilla.org/consoleservice;1']
                .getService(Components.interfaces.nsIConsoleService);
        } catch(E) {
            this.consoleDump = false;
            dump('util.error constructor: ' + E + '\n');
        }

        this.sdump_last_time = new Date();

        this.OpenILS = {};

        // Only use sounds if the context window has already created a sound object
        if (typeof xulG != 'undefined' && xulG._sound) {
            this.sound = xulG._sound;
        }

    } catch(E) {
        alert('Error in util.error constructor: ' + E);
    }

    return this;
};

util.error.prototype = {

    'allowPrintDebug' : true,
    'allowConsoleDump' : true,
    'allowDebugDump' : true,
    'allowFileDump' : true,
    'allowAlertDump' : true,

    'forcePrintDebug' : false,
    'forceConsoleDump' : false,
    'forceDebugDump' : false,
    'forceFileDump' : false,
    'forceAlertDump' : false,

    'arg_dump_full' : false,

    'debug' : function(e){
        dump('-----------------------------------------\n' 
            + e + '\n-----------------------------------------\n' );
    },

    'obj_dump' : function(s,dobj) {
        var o = 'typeof ' + dobj + ' = ' + typeof dobj + '\n';
        for (var i in dobj) {
            o += i + '\t' + typeof dobj[i] + '\n';
        }
        this.sdump(s,o);
    },

    'sdump_levels' : {

        'D_NONE' : false, 
        'D_ALL' : false,

        'D_ERROR' : { 'debug' : true, 'console' : true }, 
        'D_DEBUG' : { 'debug' : true, 'console' : true }, 
        'D_TRACE' :  { 'debug' : false }, 
        'D_ALERT' : { 'alert' : true, 'debug' : true },
        'D_WARN' : { 'debug' : true }, 
        'D_COLUMN_RENDER_ERROR' : { 'debug' : false }, 
        'D_XULRUNNER' : { 'debug' : false }, 
        'D_DECK' : { 'debug' : false },
        'D_TRACE_ENTER' :  false, 
        'D_TRACE_EXIT' :  false, 
        'D_TIMEOUT' :  false, 
        'D_FILTER' : { 'debug' : false },
        'D_CONSTRUCTOR' : { 'debug' : false }, 
        'D_FIREFOX' : { 'debug' : false }, 
        'D_LEGACY' : { 'debug' : false }, 
        'D_DATA_STASH' : { 'alert' : false }, 
        'D_DATA_RETRIEVE' : { 'debug' : false },

        'D_CLAM' : { 'debug' : false }, 
        'D_PAGED_TREE' : { 'debug' : false }, 
        'D_GRID_LIST' : { 'debug' : false }, 
        'D_HTML_TABLE' : { 'debug' : false },
        'D_TAB' : { 'debug' : false }, 
        'D_LIST' : { 'debug' : false }, 
        'D_LIST_DUMP_WITH_KEYS_ON_CLEAR' : { 'debug' : false }, 
        'D_LIST_DUMP_ON_CLEAR' : { 'debug' : false },

        'D_AUTH' : { 'debug' : false }, 
        'D_OPAC' : { 'debug' : false }, 
        'D_CAT' : { 'debug' : false }, 
        'D_BROWSER' : { 'debug' : false },

        'D_PATRON_SEARCH' : { 'debug' : false }, 
        'D_PATRON_SEARCH_FORM' : { 'debug' : false }, 
        'D_PATRON_SEARCH_RESULTS' : { 'debug' : false },

        'D_PATRON_DISPLAY' : { 'debug' : false }, 
        'D_PATRON_DISPLAY_STATUS' : { 'debug' : false }, 
        'D_PATRON_DISPLAY_CONTACT' : { 'debug' : false },

        'D_PATRON_ITEMS' : { 'debug' : false }, 
        'D_PATRON_CHECKOUT_ITEMS' : { 'debug' : false }, 
        'D_PATRON_HOLDS' : { 'debug' : false },
        'D_PATRON_BILLS' : { 'debug' : false }, 
        'D_PATRON_EDIT' : { 'debug' : false },

        'D_CHECKIN' : { 'debug' : false }, 
        'D_CHECKIN_ITEMS' : { 'debug' : false },

        'D_HOLD_CAPTURE' : { 'debug' : false }, 
        'D_HOLD_CAPTURE_ITEMS' : { 'debug' : false },

        'D_PATRON_UTILS' : { 'debug' : false }, 
        'D_CIRC_UTILS' : { 'debug' : false },

        'D_FILE' : { 'debug' : false }, 
        'D_EXPLODE' : { 'debug' : false }, 
        'D_FM_UTILS' : { 'debug' : false }, 
        'D_PRINT' : { 'debug' : false }, 
        'D_OBSERVERS' : { 'debug' : false, 'console' : false, 'alert' : false },
        'D_CACHE' : { 'debug' : false, 'console' : false, 'alert' : false },
        'D_SES' : { 'debug' : false, 'console' : true },
        'D_SES_FUNC' : { 'debug' : false }, 
        'D_SES_RESULT' : { 'debug' : false }, 
        'D_SES_ERROR' : { 'debug' : true, 'console' : true }, 
        'D_SPAWN' : { 'debug' : false }, 
        'D_STRING' : { 'debug' : false },
        'D_UTIL' : { 'debug' : false }, 
        'D_WIN' : { 'debug' : false }, 
        'D_WIDGETS' : { 'debug' : false }
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
                if (this.forceDebugDump || ( this.allowDebugDump && this.sdump_levels[level] && this.sdump_levels[level].debug ) ) this.debug(message);
                if (this.forceAlertDump || ( this.allowAlertDump && this.sdump_levels[level] && this.sdump_levels[level].alert ) ) alert(message);
                if (this.forceConsoleDump || ( this.allowConsoleDump && this.sdump_levels[level] && this.sdump_levels[level].console ) ) {
                    if (level=='D_ERROR') {
                        Components.utils.reportError(message);
                    } else {
                        this.consoleService.logStringMessage(message);
                    }
                }
                if (this.forceFileDump || ( this.allowFileDump && this.sdump_levels[level] && this.sdump_levels[level].file ) ) {
                    if (level!='D_FILE') {
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
            s     = Message to display
            title     = Text in Title Bar
            b1    = Text for button 1
            b2    = Text for button 2
            b3    = Text for button 3
            c    = Text for confirmation checkbox.  null for no confirm
        */

        dump('yns_alert:\n\ts = ' + s + '\n\ttitle = ' + title + '\n\tb1 = ' + b1 + '\n\tb2 = ' + b2 + '\n\tb3 = ' + b3 + '\n\tc = ' + c + '\n');

        //FIXME - is that good enough of an escape job?
        s = s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

        var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" xmlns:html="http://www.w3.org/1999/xhtml" flex="1">' 
            + '<groupbox flex="1" style="overflow: auto; border: solid thin red;"><caption label="' + (title) + '"/>';

        if (image) xml += '<hbox><image src="' + image + '"/><spacer flex="1"/></hbox>';
        xml += '<description id="msg" style="-moz-user-select: text; -moz-user-focus: normal; font-size: large">' + (s)
            + '</description></groupbox><groupbox><caption label="Options"/><hbox>';
        var b1_key = b1 ? b1[0] : '';
        var b2_key = b2 ? b2[0] : '';
        var b3_key = b3 ? b3[0] : ''; /* FIXME - need to check for collisions */
        if (b1) xml += '<button id="b1" accesskey="' + b1_key + '" label="' + (b1) + '" name="fancy_submit" value="b1"/>';
        if (b2) xml += '<button id="b2" accesskey="' + b2_key + '" label="' + (b2) + '" name="fancy_submit" value="b2"/>';
        if (b3) xml += '<button id="b3" accesskey="' + b3_key + '" label="' + (b3) + '" name="fancy_submit" value="b3"/>';
        var copy_button_label = 'Copy Message'; /* default in case the I18N infrastructure is failing, yns_alert often gets used for errors */
        var x= document.getElementById('offlineStrings');
        if (x) {
            if (typeof x.getString == 'function') {
                if (x.getString('common.error.copy_msg')) { copy_button_label = x.getString('common.error.copy_msg'); }
            }
        }
        xml += '<spacer flex="1"/><button label="' + copy_button_label + '" oncommand="try { copy_to_clipboard( document.getElementById(' + "'msg'" + ').textContent ); } catch(E) { alert(E); }" />';
        xml += '</hbox></groupbox></vbox>';
        JSAN.use('OpenILS.data');
        //var data = new OpenILS.data(); data.init({'via':'stash'});
        //data.temp_yns_xml = xml; data.stash('temp_yns_xml');
        var url = urls.XUL_FANCY_PROMPT; // + '?xml_in_stash=temp_yns_xml' + '&title=' + window.escape(title);
        if (typeof xulG != 'undefined') if (typeof xulG.url_prefix == 'function') url = xulG.url_prefix( url );
        JSAN.use('util.window'); var win = new util.window();
        var fancy_prompt_data = win.open(
            url, 'fancy_prompt', 'chrome,resizable,modal,width=700,height=500', { 'xml' : xml, 'title' : title, 'sound' : 'bad' }
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
            s     = Message to display
            title     = Text in Title Bar
            b1    = Text for button 1
            b2    = Text for button 2
            b3    = Text for button 3
            c    = Text for confirmation checkbox.  null for no confirm
        */

        dump('yns_alert_formatted:\n\ts = ' + s + '\n\ttitle = ' + title + '\n\tb1 = ' + b1 + '\n\tb2 = ' + b2 + '\n\tb3 = ' + b3 + '\n\tc = ' + c + '\n');

        //FIXME - is that good enough of an escape job?
        s = s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

        var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" xmlns:html="http://www.w3.org/1999/xhtml" flex="1">' 
            + '<groupbox flex="1" style="overflow: auto; border: solid thin red;"><caption label="' + (title) + '"/>';

        if (image) xml += '<hbox><image src="' + image + '"/><spacer flex="1"/></hbox>';
        xml += '<description style="-moz-user-select: text; -moz-user-focus: normal; font-size: large"><html:pre id="msg" style="font-size: large">' + (s)
            + '</html:pre></description></groupbox><groupbox><caption label="Options"/><hbox>';
        var b1_key = b1 ? b1[0] : '';
        var b2_key = b2 ? b2[0] : '';
        var b3_key = b3 ? b3[0] : ''; /* FIXME - need to check for collisions */
        if (b1) xml += '<button id="b1" accesskey="' + b1_key + '" label="' + (b1) + '" name="fancy_submit" value="b1"/>';
        if (b2) xml += '<button id="b2" accesskey="' + b2_key + '" label="' + (b2) + '" name="fancy_submit" value="b2"/>';
        if (b3) xml += '<button id="b3" accesskey="' + b3_key + '" label="' + (b3) + '" name="fancy_submit" value="b3"/>';
        var copy_button_label = 'Copy Message'; /* default in case the I18N infrastructure is failing, yns_alert often gets used for errors */
        var x= document.getElementById('offlineStrings');
        if (x) {
            if (typeof x.getString == 'function') {
                if (x.getString('common.error.copy_msg')) { copy_button_label = x.getString('common.error.copy_msg'); }
            }
        }
        xml += '<spacer flex="1"/><button label="' + copy_button_label + '" oncommand="try { copy_to_clipboard( document.getElementById(' + "'msg'" + ').textContent ); } catch(E) { alert(E); }" />';
        xml += '</hbox></groupbox></vbox>';
        JSAN.use('OpenILS.data');
        //var data = new OpenILS.data(); data.init({'via':'stash'});
        //data.temp_yns_xml = xml; data.stash('temp_yns_xml');
        var url = urls.XUL_FANCY_PROMPT; // + '?xml_in_stash=temp_yns_xml' + '&title=' + window.escape(title);
        if (typeof xulG != 'undefined') if (typeof xulG.url_prefix == 'function') url = xulG.url_prefix( url );
        JSAN.use('util.window'); var win = new util.window();
        var fancy_prompt_data = win.open(
            url, 'fancy_prompt', 'chrome,resizable,modal,width=700,height=500', { 'xml' : xml, 'title' : title, 'sound' : 'bad' }
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
            s     = Message to display
            title     = Text in Title Bar
            b1    = Text for button 1
            b2    = Text for button 2
            b3    = Text for button 3
            c    = Text for confirmation checkbox.  null for no confirm
        */

        dump('yns_alert_original:\n\ts = ' + s + '\n\ttitle = ' + title + '\n\tb1 = ' + b1 + '\n\tb2 = ' + b2 + '\n\tb3 = ' + b3 + '\n\tc = ' + c + '\n');

        if (this.sound) { this.sound.bad(); }

        // get a reference to the prompt service component.
        var promptService = Components.classes["@mozilla.org/embedcomp/prompt-service;1"]
            .getService(Components.interfaces.nsIPromptService);

        // set the buttons that will appear on the dialog. It should be
        // a set of constants multiplied by button position constants. In this case,
        // three buttons appear, Save, Cancel and a custom button.
        //var flags=promptService.BUTTON_TITLE_OK * promptService.BUTTON_POS_0 +
        //    promptService.BUTTON_TITLE_CANCEL * promptService.BUTTON_POS_1 +
        //    promptService.BUTTON_TITLE_IS_STRING * promptService.BUTTON_POS_2;
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
    },

    'work_log' : function(msg,row_data) {
        try {
            JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
            var max_entries = data.hash.aous['ui.admin.work_log.max_entries'] || 20;
            if (! data.work_log) data.work_log = [];
            if (! row_data) row_data = {};
            row_data.message = msg;
            row_data.when = new Date();
            var ds = { 
                retrieve_id: js2JSON( { 'au_id' : row_data.au_id, 'au_barcode' : row_data.au_barcode, 'au_family_name' : row_data.au_family_name, 'acp_id' : row_data.acp_id, 'acp_barcode' : row_data.acp_barcode } ), 
                row: { my: row_data },
                to_top: true
            };
            data.work_log.push( ds );
            if (data.work_log.length > max_entries) data.work_log.shift();
            data.stash('work_log');
            if (row_data.au_id) {
               this.patron_log(msg,row_data); 
            }
        } catch(E) {
            try { this.standard_unexpected_error_alert('error in error.js, work_log(): ',E); } catch(F) { alert(E); }
        }
    },

    'patron_log' : function(msg,row_data) {
        try {
            JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
            var max_entries = data.hash.aous['ui.admin.patron_log.max_entries'] || 10;
            if (! data.patron_log) data.patron_log = [];
            if (! row_data) row_data = {};
            row_data.message = msg;
            row_data.when = new Date();
            var ds = { 
                retrieve_id: js2JSON( { 'au_id' : row_data.au_id, 'au_barcode' : row_data.au_barcode, 'au_family_name' : row_data.au_family_name, 'acp_id' : row_data.acp_id, 'acp_barcode' : row_data.acp_barcode } ), 
                row: { my: row_data },
                to_top: true
            };
            if (data.patron_log.length > 0) {
                var temp = [];
                for (var i = 0; i < data.patron_log.length; i++) {
                    if (data.patron_log[ i ].row.my.au_id != row_data.au_id) temp.push( data.patron_log[i] );
                } 
                data.patron_log = temp;
            }
            data.patron_log.push( ds );
            if (data.patron_log.length > max_entries) data.patron_log.shift();
            data.stash('patron_log');
        } catch(E) {
            try { this.standard_unexpected_error_alert('error in error.js, patron_log(): ',E); } catch(F) { alert(E); }
        }
    } 
}

dump('exiting util/error.js\n');
