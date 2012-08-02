dump('entering auth/controller.js\n');
// vim:sw=4:ts=4:noet:

if (typeof auth == 'undefined') auth = {};
auth.controller = function (params) {
    JSAN.use('util.error'); this.error = new util.error();
    this.w = params.window;

    return this;
};

auth.controller.prototype = {

    'init' : function () {

        var obj = this;  // so the 'this' in event handlers don't confuse us
        var w = obj.w;

        JSAN.use('OpenILS.data');
        obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

        // MVC
        JSAN.use('util.controller'); obj.controller = new util.controller();
        obj.controller.init(
            {
                'control_map' : {
                    'cmd_login' : [
                        ['command'],
                        function() {
                            obj.login();
                        }
                    ],
                    'cmd_standalone' : [
                        ['command'],
                        function() {
                            obj.standalone();
                        }
                    ],
                    'cmd_standalone_import' : [
                        ['command'],
                        function() {
                            obj.standalone_import();
                        }
                    ],
                    'cmd_standalone_export' : [
                        ['command'],
                        function() {
                            obj.standalone_export();
                        }
                    ],
                    'cmd_clear_cache' : [
                        ['command'],
                        function() {
                            obj.debug('clear_cache');
                        }
                    ],
                    'cmd_js_console' : [
                        ['command'],
                        function() {
                            obj.debug('js_console');
                        }
                    ],
                    'cmd_debugger' : [
                        ['command'],
                        function() {
                            start_debugger();
                        }
                    ],
                    'cmd_inspector' : [
                        ['command'],
                        function() {
                            start_inspector();
                        }
                    ],
                    'cmd_chrome_list' : [
                        ['command'],
                        function() {
                            start_chrome_list();
                        }
                    ],
                    'cmd_js_shell' : [
                        ['command'],
                        function() {
                            start_js_shell();
                        }
                    ],
                    'cmd_override' : [
                        ['command'],
                        function() {
                            obj.override();
                        }
                    ],
                    'cmd_logoff' : [
                        ['command'],
                        function() {
                            obj.logoff()
                        }
                    ],
                    'cmd_close_window' : [
                        ['command'],
                        function() {
                            obj.close()
                        }
                    ],
                    'cmd_test_server' : [
                        ['command'],
                        function() {
                            obj.test_server( obj.controller.view.server_prompt.value );
                        }
                    ],
                    'ssl_exception' : [
                        ['render'],
                        function(e) {
                            return function() {
                                try {
                                    obj.controller.view.cmd_ssl_exception.setAttribute('hidden','true');
                                    var x = new XMLHttpRequest();
                                    x.open("GET",'chrome://pippki/content/exceptionDialog.xul',false);
                                    x.send(null);
                                    obj.controller.view.cmd_ssl_exception.setAttribute('hidden','false');
                                } catch(E) {
                                    obj.controller.view.cmd_ssl_exception.setAttribute('hidden','true');
                                }
                            };
                        }
                    ],
                    'cmd_ssl_exception' : [
                        ['command'],
                        function() {
                            window.openDialog(
                                'chrome://pippki/content/exceptionDialog.xul',
                                '', 
                                'chrome,centerscreen,modal', 
                                { 
                                    'location' : 'https://' + obj.controller.view.server_prompt.value.match(/^[^\/]*/), 
                                    'prefetchCert' : true 
                                } 
                            );
                            obj.test_server( obj.controller.view.server_prompt.value );
                        }
                    ],
                    'server_prompt' : [
                        ['keypress'],
                        handle_keypress
                    ],
                    'server_menu' : [
                        ['render'],
                        function(e) {
                            return function() {
                                var list = [];
                                for (var s in obj.data.ws_info) {
                                    list.push(s);
                                }
                                list.sort();
                                for (var i = 0; i < list.length; i++) {
                                    var mi = document.createElement('menuitem');
                                    mi.setAttribute('label',list[i]);
                                    mi.setAttribute('value',list[i]);
                                    e.appendChild(mi);
                                }
                            };
                        }
                    ],
                    'name_prompt' : [
                        ['keypress'],
                        handle_keypress
                    ],
                    'password_prompt' : [
                        ['keypress'],
                        handle_keypress
                    ],
                    'submit_button' : [
                        ['render'],
                        function(e) { return function() {} }
                    ],
                    'apply_locale_btn' : [
                        ['render'],
                        function(e) { return function() {} }
                    ],
                    'progress_bar' : [
                        ['render'],
                        function(e) { return function() {} }
                    ],
                    'status' : [
                        ['render'],
                        function(e) { return function() {
                        } }
                    ],
                    'ws_deck' : [
                        ['render'],
                        function(e) { return function() {
                            try {
                                JSAN.use('util.widgets'); util.widgets.remove_children(e);
                                var x = document.createElement('description');
                                e.appendChild(x);
                                if (obj.data.ws_info 
                                    && obj.data.ws_info[ obj.controller.view.server_prompt.value ]) {
                                    var ws = obj.data.ws_info[ obj.controller.view.server_prompt.value ];
                                    x.appendChild(
                                        document.createTextNode(
                                            ws.name /*+ ' @  ' + ws.lib_shortname*/
                                        )
                                    );
                                    JSAN.use('util.file'); var file = new util.file('last_ws_server');
                                    file.set_object(obj.controller.view.server_prompt.value);
                                    file.close();
                                } else {
                                    x.appendChild(
                                        document.createTextNode(
                                            document.getElementById('authStrings').getString('staff.auth.controller.not_configured')
                                        )
                                    );
                                }
                            } catch(E) {
                                alert(E);
                            }
                        } }
                    ],
                    'menu_spot' : [
                        ['render'],
                        function(e) { return function() {
                        } }
                    ],

                }
            }
        );
        obj.controller.view.name_prompt.focus();

        function handle_keypress(ev) {
            try {
                if (ev.keyCode && ev.keyCode == 13) {
                    switch(this) {
                        case obj.controller.view.server_prompt:
                            ev.preventDefault();
                            obj.controller.view.name_prompt.focus(); obj.controller.view.name_prompt.select();
                        break;
                        case obj.controller.view.name_prompt:
                            ev.preventDefault();
                            obj.controller.view.password_prompt.focus(); obj.controller.view.password_prompt.select();
                        break;
                        case obj.controller.view.password_prompt:
                            ev.preventDefault();
                            obj.controller.view.submit_button.focus(); 
                            obj.login();
                        break;
                        default: break;
                    }
                }
            } catch(E) {
                alert(E);
            }
        }

        obj.controller.view.server_prompt.addEventListener(
            'change',
            function (ev) { 
                obj.test_server(ev.target.value);
                obj.controller.render('ws_deck'); 
            },
            false
        );
        obj.controller.view.server_prompt.addEventListener(
            'command',
            function (ev) {
                obj.controller.view.name_prompt.focus();
                obj.controller.view.name_prompt.select();
                obj.test_server(ev.target.value);
                obj.controller.render('ws_deck'); 
            },
            false
        );

        // This talks to our ILS
        JSAN.use('auth.session');
        obj.session = new auth.session(obj.controller.view);

        obj.controller.render();
        obj.controller.render('ws_deck'); 

        if (typeof this.on_init == 'function') {
            this.error.sdump('D_AUTH','auth.controller.on_init()\n');
            this.on_init();
        }
    },

    'test_server' : function(url) {
        var obj = this;
        if (!url) {
            JSAN.use('util.file'); var file = new util.file('last_ws_server');
            if (file._file.exists()) {
                url = file.get_object(); file.close();
                obj.controller.view.server_prompt.value = url;
            }
        }
        url = url.match(/^[^\/]*/).toString(); // Only test the pre-slash URL
        obj.controller.view.submit_button.disabled = true;
        obj.controller.view.server_prompt.disabled = true;
        var s = document.getElementById('status');
        s.setAttribute('value', document.getElementById('authStrings').getString('staff.auth.controller.testing_hostname'));
        s.setAttribute('style','color: orange;');
        document.getElementById('version').value = '';
        if (!url) {
            s.setAttribute('value', document.getElementById('authStrings').getString('staff.auth.controller.prompt_hostname'));
            s.setAttribute('style','color: red;');
            obj.controller.view.server_prompt.disabled = false;
            obj.controller.view.server_prompt.focus();
            return;
        }
        try {
            if ( ! url.match(/^https:\/\//) ) url = 'https://' + url;
            var x = new XMLHttpRequest();
            dump('server url = ' + url + '\n');
            x.open("GET",url,true);
            x.onreadystatechange = function() {
                try {
                    if (x.readyState != 4) return;
                    s.setAttribute('value', document.getElementById('authStrings').getFormattedString('staff.auth.controller.status', [x.status, x.statusText]));
                    if (x.status == 200) {
                        s.setAttribute('style','color: green;');
                    } else {
                        if(x.status == 0) {
                            s.setAttribute('value', document.getElementById('authStrings').getString('staff.auth.controller.error_hostname'));
                            obj.controller.view.server_prompt.disabled = false;
                            obj.controller.view.server_prompt.focus();
                        }
                        s.setAttribute('style','color: red;');
                    }
                    if(x.status > 0)
                        obj.test_version(url);
                } catch(E) {
                    obj.controller.view.server_prompt.disabled = false;
                    obj.controller.view.server_prompt.focus();
                    s.setAttribute('value', document.getElementById('authStrings').getString('staff.auth.controller.error_hostname'));
                    s.setAttribute('style','color: red;');
                    obj.error.sdump('D_ERROR',E);
                }
            }
            x.send(null);
        } catch(E) {
            s.setAttribute('value', document.getElementById('authStrings').getString('staff.auth.controller.error_hostname'));
            s.setAttribute('style','color: brown;');
            obj.error.sdump('D_ERROR',E);
            obj.controller.view.server_prompt.disabled = false;
            obj.controller.view.server_prompt.focus();
        }
    },

    'test_version' : function(url) {
        var obj = this;
        var s = document.getElementById('version');
        s.setAttribute('value', document.getElementById('authStrings').getString('staff.auth.controller.testing_version'));
        s.setAttribute('style','color: orange;');
        try {
            var x = new XMLHttpRequest();
            var url2 = url + '/xul/server/';
            dump('version url = ' + url2 + '\n');
            x.open("GET",url2,true);
            x.onreadystatechange = function() {
                try {
                    if (x.readyState != 4) return;
                    s.setAttribute('value', document.getElementById('authStrings').getFormattedString('staff.auth.controller.status', [x.status, x.statusText]));
                    if (x.status == 200) {
                        s.setAttribute('style','color: green;');
                        obj.controller.view.submit_button.disabled = false;
                    } else {
                        s.setAttribute('style','color: red;');
                        obj.test_upgrade_instructions(url);
                    }
                    obj.controller.view.server_prompt.disabled = false;
                } catch(E) {
                    s.setAttribute('value', document.getElementById('authStrings').getString('staff.auth.controller.error_version'));
                    s.setAttribute('style','color: red;');
                    obj.error.sdump('D_ERROR',E);
                    obj.controller.view.server_prompt.disabled = false;
                }
            }
            x.send(null);
        } catch(E) {
            s.setAttribute('value', document.getElementById('authStrings').getString('staff.auth.controller.error_version'));
            s.setAttribute('style','color: brown;');
            obj.error.sdump('D_ERROR',E);
            obj.controller.view.server_prompt.disabled = false;
        }
    },

    'test_upgrade_instructions' : function(url) {
        var obj = this;
        try {
            var x = new XMLHttpRequest();
            var url2 = url + '/xul/versions.html';
            dump('upgrade url = ' + url2 + '\n');
            x.open("GET",url2,true);
            x.onreadystatechange = function() {
                try {
                    if (x.readyState != 4) return;
                    if (x.status == 200) {
                        window.open('data:text/html,'+window.escape(x.responseText),'upgrade','chrome,resizable,modal,centered');
                    } else {
                        if(typeof(G.upgradeCheck) == "function")
                        {
                            if (confirm("This server does not support your version of the staff client, an upgrade may be required. If you wish to check for an upgrade please press Ok. Otherwise please press cancel."))
                                G.upgradeCheck();
                        } else {
                            alert(document.getElementById('authStrings').getString('staff.auth.controller.version_mismatch'));
                        }
                    }
                    obj.controller.view.server_prompt.disabled = false;
                } catch(E) {
                    obj.error.sdump('D_ERROR',E);
                    obj.controller.view.server_prompt.disabled = false;
                }
            }
            x.send(null);
        } catch(E) {
            obj.error.sdump('D_ERROR',E);
            obj.controller.view.server_prompt.disabled = false;
        }
    },

    'login' : function() { 

        var obj = this;

        this.error.sdump('D_AUTH',
            document.getElementById('authStrings').getFormattedString(
                'staff.auth.controller.error_login', [
                    this.controller.view.name_prompt.value,
                    this.controller.view.password_prompt.value,
                    this.controller.view.server_prompt.value
                ]
            )
        ); 
        this.controller.view.server_prompt.disabled = true;
        this.controller.view.name_prompt.disabled = true;
        this.controller.view.password_prompt.disabled = true;
        this.controller.view.submit_button.disabled = true;
        this.controller.view.apply_locale_btn.disabled = true;
        XML_HTTP_SERVER = this.controller.view.server_prompt.value.match(/^[^\/]*/).toString();

        try {

            if (typeof this.on_login == 'function') {
                this.error.sdump('D_AUTH','auth.controller.session.on_init = ' +
                    'auth.controller.on_login\n');
                this.session.on_init = this.on_login;
                this.session.on_error = function() { obj.logoff(); };
            }
            
            this.session.init();

        } catch(E) {
            var error = '!! ' + E + '\n';
            this.error.sdump('D_ERROR',error); 
            alert(error);
            this.logoff();
            if (E == 'open-ils.auth.authenticate.init returned false\n') {
                this.controller.view.server_prompt.focus();
                this.controller.view.server_prompt.select();
            }

            if (typeof this.on_login_error == 'function') {
                this.error.sdump('D_AUTH','auth.controller.on_login_error()\n');
                this.on_login_error(E);
            }
        }
        // Once we are done with it, clear the password
        this.controller.view.password_prompt.value = '';

    },

    'standalone' : function() {
        var obj = this;
        try {
            if (typeof this.on_standalone == 'function') {
                obj.on_standalone();
            }
        } catch(E) {
            var error = '!! ' + E + '\n';
            obj.error.sdump('D_ERROR',error); 
            alert(error);
        }
    },

    'standalone_import' : function() {
        var obj = this;
        try {
            if (typeof this.on_standalone_import == 'function') {
                obj.on_standalone_import();
            }
        } catch(E) {
            var error = '!! ' + E + '\n';
            obj.error.sdump('D_ERROR',error); 
            alert(error);
        }
    },

    'standalone_export' : function() {
        var obj = this;
        try {
            if (typeof this.on_standalone_export == 'function') {
                obj.on_standalone_export();
            }
        } catch(E) {
            var error = '!! ' + E + '\n';
            obj.error.sdump('D_ERROR',error); 
            alert(error);
        }
    },

    'debug' : function(action) {
        var obj = this;
        try {
            if (typeof this.on_debug == 'function') {
                obj.on_debug(action);
            }
        } catch(E) {
            var error = '!! ' + E + '\n';
            obj.error.sdump('D_ERROR',error);
            alert(error);
        }
    },

    'logoff' : function() { 

        this.data.stash_retrieve();
        if (typeof this.data.unsaved_data != 'undefined') {
            if (this.data.unsaved_data > 0) {
                var confirmation = window.confirm( document.getElementById('offlineStrings').getString('menu.logoff.unsaved_data_warning') );
                if (!confirmation) { return; }
                this.data.unsaved_data = 0;
                this.data.stash('unsaved_data');
            }
        }
    
        this.error.sdump('D_AUTH','logoff' + this.w + '\n'); 
        this.controller.view.progress_bar.value = 0; 
        this.controller.view.progress_bar.setAttribute('real','0.0');
        this.controller.view.submit_button.disabled = false;
        this.controller.view.apply_locale_btn.disabled = false;
        this.controller.view.password_prompt.disabled = false;
        this.controller.view.password_prompt.value = '';
        this.controller.view.name_prompt.disabled = false;
        this.controller.view.name_prompt.focus(); 
        this.controller.view.name_prompt.select();
        this.controller.view.server_prompt.disabled = false;

        var windowManager = Components.classes["@mozilla.org/appshell/window-mediator;1"].getService();
        var windowManagerInterface = windowManager.QueryInterface(Components.interfaces.nsIWindowMediator);
        var enumerator = windowManagerInterface.getEnumerator(null);

        var w; // close all other windows
        while ( w = enumerator.getNext() ) {
            if (w != window) {
                if (w.xulG) { w.close(); } // FIXME: kludge so we don't close Firefox windows as an extension.  We should define a @windowtype for all the staff client windows and have the enumerator just pull those
            }
        }

        this.controller.render('ws_deck');

        this.session.close();
        this.data.menu_perms = false;
        this.data.current_hotkeyset = undefined;
        this.data.enable_debug = this.data.debug_client;
        this.data.session = undefined;
        this.data.stash('menu_perms');
        this.data.stash('current_hotkeyset');
        this.data.stash('enable_debug');
        this.data.stash('session');

        /* FIXME - need some locking or object destruction for the async tests */
        /* this.test_server( this.controller.view.server_prompt.value ); */

        if (typeof this.on_logoff == 'function') {
            this.error.sdump('D_AUTH','auth.controller.on_logoff()\n');
            this.on_logoff();
        }
        
    },
    'close' : function() { 
    
        this.error.sdump('D_AUTH','close' + this.w + '\n');

        var confirm_string = document.getElementById('authStrings').getString('staff.auth.controller.confirm_close');

        this.data.stash_retrieve();
        if (typeof this.data.unsaved_data != 'undefined') {
            if (this.data.unsaved_data > 0) {
                confirm_string = document.getElementById('offlineStrings').getString('menu.shutdown.unsaved_data_warning');
            }
        }
 
        if (window.confirm(confirm_string)) {
            this.data.unsaved_data = 0;
            this.data.stash('unsaved_data');
            this.logoff();
            this.w.close(); /* Probably won't go any further */

            if (typeof this.on_close == 'function') {
                this.error.sdump('D_AUTH','auth.controller.on_close()\n');
                this.on_close();
            }
        }
        
    }
}

dump('exiting auth/controller.js\n');
