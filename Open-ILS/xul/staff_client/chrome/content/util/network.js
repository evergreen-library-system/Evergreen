dump('entering util/network.js\n');
// vim:noet:sw=4:ts=4:

var offlineStrings;

if (typeof util == 'undefined') util = {};
util.network = function () {

    try {

        JSAN.use('util.error'); this.error = new util.error();
        JSAN.use('util.sound'); this.sound = new util.sound();

        offlineStrings = document.getElementById('offlineStrings');

    } catch(E) {
        alert('error in util.network constructor: ' + E);
        throw(E);
    }

    return this;
};

util.network.prototype = {

    'link_id' : 0,

    'network_timeout' : 55, /* seconds */

    'NETWORK_FAILURE' : null,

    'simple_request' : function(method_id,params,f,override_params) {
        //var obj = this;
        //var sparams = js2JSON(params);
        //obj.error.sdump('D_SES','simple_request '+ method_id +' '+obj.error.pretty_print(sparams.slice(1,sparams.length-1))+
        //    '\noverride_params = ' + override_params + '\n');
        if (typeof api[method_id] == 'undefined') {
            throw( offlineStrings.getFormattedString('network.method_not_found.error', [method_id]) );
        }
        var secure = true; if (typeof api[method_id].secure != 'undefined') secure = api[method_id].secure;
        return this.request(api[method_id].app,api[method_id].method,params,f,override_params,{ 'secure' : secure, 'method_id' : method_id });
    },

    'get_result' : function (req) {
        var obj = this;
        var result;
        var fake_ilsevent_for_network_errors = { 'ilsevent' : -1, 'textcode' : offlineStrings.getString('network.server_or_method.error') }; 
        try {
            if (req.cancelled) {
                result = fake_ilsevent_for_network_errors;
            } else {
                result = req.getResultObject();   
                if(result && req._reported_events) {
                    if(typeof result.ilsevent != 'undefined') {
                        result._reported_events = req._reported_events;
                    } else {
                        result[0]._reported_events = req._reported_events;
                    }
                } 
            }
        } catch(E) {
            try {
                if (instanceOf(E, NetworkFailure)) {
                    obj.NETWORK_FAILURE = E;
                } else {
                    try { obj.NETWORK_FAILURE = js2JSON(E); } catch(F) { dump(F + '\n'); obj.NETWORK_FAILURE = E; };
                }
            } catch(I) { 
                obj.NETWORK_FAILURE = offlineStrings.getString('network.unknown_status');
            }
            result = fake_ilsevent_for_network_errors;
        }
        return result;
    },

    'request' : function (app,name,params,f,override_params,_params) {

        var obj = this;
        
        //var sparams = js2JSON(params);
        //obj.error.sdump('D_SES','request '+ app + ' ' + name +' '+obj.error.pretty_print(sparams.slice(1,sparams.length-1))+
        //    '\noverride_params = ' + override_params + '\n_params = ' + _params + '\n');

        try {

            if (typeof _params == 'undefined') {
                // If we're not using simple_request to get here, let's assume secure by default
                _params = { 'secure' : true };
            }

            var request =  this._request(app,name,params,f,override_params,_params);
            if (request) {
                return this.get_result(request);
            } else {
                return null;
            }
    
        } catch(E) {
            alert('1: ' + E); 
        }
    },

    '_request' : function (app,name,params,f,override_params,_params) {
        var obj = this;
        try {
            var sparams = js2JSON(params);
            obj.error.sdump('D_SES','_request '+app+' '+name+' '+obj.error.pretty_print(sparams.slice(1,sparams.length-1))+
                '\noverride_params = ' + override_params + '\n_params = ' + _params +
                '\nResult #' + (++obj.link_id) + ( f ? ' asynced' : ' synced' ) +
                '\nlocation.href = ' + location.href );

            if (document.getElementById('network_progress')) {
                if (g && g.menu && g.menu.network_meter && typeof g.menu.network_meter.inc == 'function') g.menu.network_meter.inc(app,name);
            } else if (typeof xulG != 'undefined') {
                if (xulG && xulG.network_meter && typeof xulG.network_meter.inc == 'function') xulG.network_meter.inc(app,name);
            }

            var request = new RemoteRequest( app, name );
            if (_params && _params.secure) {
                request.setSecure(true);
            } else {
                request.setSecure(false);
            }
            for(var index in params) {
                request.addParam(params[index]);
            }

            var start_timer = (new Date).getTime();    
            if (f)  {
                request.setCompleteCallback(
                    function(req) {
                        try {
                            var duration = ( (new Date).getTime() - start_timer )/1000;
                            if ( obj.get_result(req) == null && duration > obj.network_timeout ) req.cancelled = true;

                            if (document.getElementById('network_progress')) {
                                if (g && g.menu && g.menu.network_meter && typeof g.menu.network_meter.dec == 'function') g.menu.network_meter.dec(app,name);
                            } else if (typeof xulG != 'undefined') {
                                if (xulG && xulG.network_meter && typeof xulG.network_meter.dec == 'function') xulG.network_meter.dec(app,name);
                            }

                            var json_string = js2JSON(obj.get_result(req));
                            obj.error.sdump('D_SES_RESULT','asynced result #' 
                                + obj.link_id + '\n\n' 
                                + (json_string.length > 80 ? obj.error.pretty_print(json_string) : json_string) 
                                + '\n\nOriginal Request:\n\n' 
                                + 'request '+app+' '+name+' '+ sparams.slice(1,sparams.length-1));
                            obj.play_sounds( request );
                            req = obj.rerequest_on_session_timeout(app,name,params,req,override_params,_params);
                            req = obj.rerequest_on_perm_failure(app,name,params,req,override_params,_params);
                            if (override_params) {
                                req = obj.rerequest_on_override(app,name,params,req,override_params,_params);
                            }
                            req = obj.check_for_offline(app,name,params,req,override_params,_params);
                            f(req);
                            obj.NETWORK_FAILURE = null;
                        } catch(E) {
                            try {
                                E.ilsevent = -2;
                                E.textcode = offlineStrings.getString('network.server_or_method.error');
                            } catch(F) {}
                            f( { 'getResultObject' : function() { return E; } } );
                        }
                    }
                );
                try {
                    request.send(false);
                } catch(E) {
                    throw(E);
                }
                return null;
            } else {
                try {
                    request.send(true);
                    var duration = ( (new Date).getTime() - start_timer )/1000;
                    if ( obj.get_result(request) == null && duration > obj.network_timeout ) request.cancelled = true;

                    if (document.getElementById('network_progress')) {
                        if (g && g.menu && g.menu.network_meter && typeof g.menu.network_meter.dec == 'function') g.menu.network_meter.dec(app,name);
                    } else if (typeof xulG != 'undefined') {
                        if (xulG && xulG.network_meter && typeof xulG.network_meter.dec == 'function') xulG.network_meter.dec(app,name);
                    }

                } catch(E) {
                    throw(E);
                }
                var result = obj.get_result(request);
                var json_string = js2JSON(result);
                this.error.sdump('D_SES_RESULT','synced result #' 
                    + obj.link_id + '\n\n' + ( json_string.length > 80 ? obj.error.pretty_print(json_string) : json_string ) 
                    + '\n\nOriginal Request:\n\n' 
                    + 'request '+app+' '+name+' '+ sparams.slice(1,sparams.length-1));
                obj.play_sounds( request );
                request = obj.rerequest_on_session_timeout(app,name,params,request,override_params,_params);
                request = obj.rerequest_on_perm_failure(app,name,params,request,override_params,_params);
                if (override_params) {
                    request = obj.rerequest_on_override(app,name,params,request,override_params,_params);
                }
                request = obj.check_for_offline(app,name,params,request,override_params,_params);
                obj.NETWORK_FAILURE = null;
                return request;
            }

        } catch(E) {
            alert('2: ' + E);
            if (instanceOf(E,perm_ex)) {
                alert('in util.network, _request : permission exception: ' + js2JSON(E));
            }
            throw(E);
        }
    },

    'check_for_offline' : function (app,name,params,req,override_params,_params) {
        try {
            var obj = this;
            var result = obj.get_result(req);
            if (result == null) return req;
            if (typeof result.ilsevent == 'undefined') return req;
            if (result.ilsevent != -1) return req;

            JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
            var proceed = true;

            while(proceed) {

                proceed = false;

                var r;

                if (data.proceed_offline) {

                    r = 1;

                } else {

                    var network_failure_string;
                    var network_failure_status_string;
                    var msg;

                    try { network_failure_string = String( obj.NETWORK_FAILURE ); } catch(E) { network_failure_string = E; }
                    try { network_failure_status_string = typeof obj.NETWORK_FAILURE == 'object' && typeof obj.NETWORK_FAILURE != 'null' && typeof obj.NETWORK_FAILURE.status == 'function' ? obj.NETWORK_FAILURE.status() : ''; } catch(E) { network_failure_status_string = ''; obj.error.sdump('D_ERROR', 'setting network_failure_status_string: ' + E); }
                    
                    try { msg = offlineStrings.getFormattedString('network.server.failure.exception', [data.server_unadorned]) + '\n' +
                                offlineStrings.getFormattedString('network.server.method', [name]) + '\n' + 
                                offlineStrings.getFormattedString('network.server.params', [js2JSON(params)]) + '\n' + 
                                offlineStrings.getString('network.server.thrown_label') + '\n' + network_failure_string + '\n' + 
                                offlineStrings.getString('network.server.status_label') + '\n' + network_failure_status_string;
                    } catch(E) { msg = E; }

                    try { obj.error.sdump('D_SES_ERROR',msg); } catch(E) { alert('3: ' + E); }

                    r = obj.error.yns_alert(
                        msg,
                        offlineStrings.getString('network.network_failure'),
                        offlineStrings.getString('network.retry_network'),
                        offlineStrings.getString('network.ignore_errors'),
                        null,
                        offlineStrings.getString('common.confirm')
                    );
                    if (r == 1) {
                        data.proceed_offline = true; data.stash('proceed_offline');
                        dump('Remembering proceed_offline for 200000 ms.\n');
                        setTimeout(
                            function() {
                                data.proceed_offline = false; data.stash('proceed_offline');
                                dump('Setting proceed_offline back to false.\n');
                            }, 200000
                        );
                    }
                }

                dump( r == 0 ? 'Retry Network\n' : 'Ignore Errors\n' );

                switch(r) {
                    case 0: 
                        req = obj._request(app,name,params,null,override_params,_params);
                        if (obj.get_result(req)) proceed = true; /* daily WTF, why am I even doing this? :) */
                        return req;
                    break;

                    case 1: 
                        return req;
                    break;
                }
            }
        } catch(E) {
            alert('4: ' + E);
            throw(E);
        }
    },

    'reset_titlebars' : function(data) {
        var obj = this;
        data.stash_retrieve();
        try {
            JSAN.use('util.window'); var win =  new util.window();
            var windowManager = Components.classes["@mozilla.org/appshell/window-mediator;1"].getService();
            var windowManagerInterface = windowManager.QueryInterface(Components.interfaces.nsIWindowMediator);
            var enumerator = windowManagerInterface.getEnumerator(null);

            var w; // set title on all appshell windows
            while ( w = enumerator.getNext() ) {
                if (w.document.title.match(/^\d/)) {
                    w.document.title = 
                        win.appshell_name_increment() 
                        + ': ' + data.list.au[0].usrname() 
                        + '@' + data.ws_name;
                        + '.' + data.server_unadorned 
                }
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert(offlineStrings.getString('network.window_title.error'),E);
        }
    },

    'set_user_status' : function() {
        data.stash_retrieve();
        try {
            var windowManager = Components.classes["@mozilla.org/appshell/window-mediator;1"].getService();
            var windowManagerInterface = windowManager.QueryInterface(Components.interfaces.nsIWindowMediator);
            var permlist = windowManagerInterface.getMostRecentWindow('eg_main').get_menu_perms(null);
            var offlinestrings;
            var enumerator = windowManagerInterface.getEnumerator('eg_menu');

            var w;
            var x;
            while ( w = enumerator.getNext() ) {
                x = w.document.getElementById('oc_menuitem');

                if(!offlinestrings) offlinestrings = w.document.getElementById('offlineStrings');
                if(permlist) w.g.menu.set_menu_access(permlist);
                if(data.list.au.length > 1) {
                    addCSSClass(w.document.getElementById('main_tabbox'),'operator_change');
                    x.setAttribute('label', offlineStrings.getFormattedString('menu.cmd_chg_session.operator.label', [data.list.au[1].usrname()]) );
                }
                else {
                    removeCSSClass(w.document.getElementById('main_tabbox'),'operator_change');
                    x.setAttribute('label', x.getAttribute('label_orig'));
                }
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert(offlineStrings.getString('network.window_title.error'),E);
        }
    },

    'get_new_session' : function(name,xulG,text) {
        var obj = this;
        try {

        var url = urls.XUL_AUTH_SIMPLE;
        if (typeof xulG != 'undefined' && typeof xulG.url_prefix == 'function') url = xulG.url_prefix( url );
        JSAN.use('util.window'); var win = new util.window();
        var my_xulG = win.open(
            url,
            //+ '?login_type=staff'
            //+ '&desc_brief=' + window.escape( text ? 'Session Expired' : 'Operator Change' )
            //+ '&desc_full=' + window.escape( text ? 'Please enter the credentials for a new login session.' : 'Please enter the credentials for the new login session.  Note that the previous session is still active.'),
            //'simple_auth' + (new Date()).toString(),
            offlineStrings.getString('network.new_session.authorize'),
            'chrome,resizable,modal,width=700,height=500',
            {
                'login_type' : 'staff',
                'desc_brief' : text ? offlineStrings.getString('network.new_session.expired') : offlineStrings.getString('network.new_session.operator_change'),
                'desc_full' : text ? offlineStrings.getString('network.new_session.expired.prompt') : offlineStrings.getString('network.new_session.operator_change.prompt')
                //'simple_auth' : (new Date()).toString(),
            }
        );
        JSAN.use('OpenILS.data');
        var data = new OpenILS.data(); data.init({'via':'stash'});
        if (typeof data.temporary_session != 'undefined' && data.temporary_session != '') {
            data.session.key = data.temporary_session.key; 
            data.session.authtime = data.temporary_session.authtime; 
            data.stash('session');
            try {
                var ios = Components.classes["@mozilla.org/network/io-service;1"].getService(Components.interfaces.nsIIOService);
                var cookieUriSSL = ios.newURI("https://" + data.server_unadorned, null, null);
                var cookieSvc = Components.classes["@mozilla.org/cookieService;1"].getService(Components.interfaces.nsICookieService);

                cookieSvc.setCookieString(cookieUriSSL, null, "ses="+data.session.key + "; secure;", null);

            } catch(E) {
                alert(offineStrings.getFormattedString('main.session_cookie.error', [E]));
            }
            if (! data.list.au ) data.list.au = [];
            data.list.au[0] = JSON2js( data.temporary_session.usr );
            data.stash('list');
            obj.reset_titlebars(data);
            return true;
        } else {
            obj.error.sdump('D_TRACE','No new session key after simple_auth in util/network\n');
        }
        return false;

        } catch(E) {
            obj.error.standard_unexpected_error_alert('util.network.get_new_session',E);
        }
    },

    'rerequest_on_session_timeout' : function(app,name,params,req,override_params,_params) {
        try {
            var obj = this;
            var robj = obj.get_result(req);
            if (robj != null && robj.ilsevent && robj.ilsevent == 1001 /* NO_SESSION */) {

                if (obj.get_new_session(name,undefined,true)) {
                    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
                    params[0] = data.session.key;
                    req = obj._request(app,name,params,null,override_params,_params);
                }
            }
        } catch(E) {
            this.error.standard_unexpected_error_alert('rerequest_on_session_timeout',E);
        }
        return req;
    },
    
    'rerequest_on_perm_failure' : function(app,name,params,req,override_params,_params) {
        try {
            var obj = this;
            var robj = obj.get_result(req);
            if (robj != null && robj.ilsevent && robj.ilsevent == 5000) {
                if (location.href.match(/^chrome/)) {
                    //alert('Permission denied.');
                } else {
                    JSAN.use('util.window'); var win = new util.window();
                    var my_xulG = win.open(
                        urls.XUL_AUTH_SIMPLE,
                        //+ '?login_type=temp'
                        //+ '&desc_brief=' + window.escape('Permission Denied: ' + robj.ilsperm)
                        //+ '&desc_full=' + window.escape('Another staff member with the above permission may authorize this specific action.  Please notify your library administrator if you need this permission.  If you feel you have received this exception in error, inform your friendly Evergreen developers of the above permission and this debug information: ' + name),
                        //'simple_auth' + (new Date()).toString(),
                        offlineStrings.getFormattedString('network.permission.authorize'),
                        'chrome,resizable,modal,width=700,height=500',
                        {
                            'login_type' : 'temp',
                            'desc_brief' : offlineStrings.getFormattedString('network.permission.description.brief', [robj.ilsperm]),
                            'desc_full' : offlineStrings.getFormattedString('network.permission.description.full', [name])
                            //'simple_auth' : (new Date()).toString(),
                        }
                    );
                    JSAN.use('OpenILS.data');
                    //var data = new OpenILS.data(); data.init({'via':'stash'});
                    if (typeof my_xulG.temporary_session != 'undefined' && my_xulG.temporary_session != '') {
                        params[0] = my_xulG.temporary_session.key;
                        req = obj._request(app,name,params,null,override_params,_params);
                    }
                }
            }
        } catch(E) {
            this.error.sdump('D_ERROR',E);
        }
        return req;
    },

    'rerequest_on_override' : function (app,name,params,req,override_params,_params) {
        var obj = this;
        try {
            if (!override_params.text) override_params.text = {};
            if (!override_params.auto_override_these_events) override_params.auto_override_these_events = [];
            if (!override_params.report_override_on_events) override_params.report_override_on_events = [];
            function override(r) {
                try {
                    // test to see if we can suppress this dialog and auto-override
                    var auto_override = false;
                    if (override_params.auto_override_these_events.length > 0) {
                        auto_override = true;
                        for (var i = 0; i < r.length; i++) {
                            if ( 
                                (typeof r[i].ilsevent != 'undefined') && 
                                (
                                    (override_params.auto_override_these_events.indexOf( r[i].ilsevent == null ? null : Number(r[i].ilsevent) ) != -1) ||
                                    (override_params.auto_override_these_events.indexOf( r[i].textcode ) != -1) 
                                )
                            ) {
                                // so far so good
                            } else {
                                // showstopper
                                auto_override = false;
                            }
                        }
                    }
                    if (auto_override) {
                        obj.sound.bad();
                        req = obj._request(app,name + '.override',params);
                        return req;
                    }

                    var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul">' + 
                        '<groupbox><caption label="' + offlineStrings.getString('network.override.exceptions') + '"/>' + 
                        '<grid><columns><column/><column flex="1"/></columns><rows>';
                    for (var i = 0; i < r.length; i++) {
                        var t1 = String(r[i].ilsevent).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
                        var t2 = String(r[i].textcode).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
                        var t3 = String((override_params.text[r[i].ilsevent] ? override_params.text[r[i].ilsevent](r[i]) : '')).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
                        var t4 = String(r[i].desc).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
                        xml += '<row>' + 
                            '<description class="oils_event" tooltiptext="' + t1 + '">' + t2 + '</description>' + 
                            '<description>' + t3 + '</description>' + 
                            '</row><row>' + '<description>' + t4 + '</description>' + '</row>';
                    }
                    xml += '</rows></grid></groupbox><groupbox><caption label="' + offlineStrings.getString('network.override.override') +'"/><hbox>' + 
                        '<description>' + offlineStrings.getString('network.override.force.prompt') + '</description>' + 
                        '<button accesskey="' + offlineStrings.getString('common.no.accesskey') + '" label="' + offlineStrings.getString('common.no') + '" name="fancy_cancel"/>' + 
                        '<button id="override" accesskey="' + offlineStrings.getString('common.yes.accesskey') + '" label="' + offlineStrings.getString('common.yes') + '" name="fancy_submit" value="override"/></hbox></groupbox></vbox>';
                    //JSAN.use('OpenILS.data');
                    //var data = new OpenILS.data(); data.init({'via':'stash'});
                    //data.temp_override_xml = xml; data.stash('temp_override_xml');
                    JSAN.use('util.window'); var win = new util.window();
                    var fancy_prompt_data = win.open(
                        urls.XUL_FANCY_PROMPT,
                        //+ '?xml_in_stash=temp_override_xml'
                        //+ '&title=' + window.escape(override_params.title),
                        'fancy_prompt', 'chrome,resizable,modal,width=700,height=500',
                        { 'xml' : xml, 'title' : override_params.title, 'sound' : 'bad', 'sound_object' : obj.sound }
                    );
                    if (fancy_prompt_data.fancy_status == 'complete') {
                        req = obj._request(app,name + '.override',params);
                        if (req && override_params.report_override_on_events.length > 0 && typeof result == 'object') {
                            var reported_events = [];
                            for (var i = 0; i < r.length; i++) {
                                if (typeof r[i].ilsevent != 'undefined') {
                                    if (override_params.report_override_on_events.indexOf( r[i].ilsevent == null ? null : Number(r[i].ilsevent) ) != -1) {
                                        reported_events.push(Number(r[i].ilsevent));
                                    }
                                    if (override_params.report_override_on_events.indexOf( r[i].textcode ) != -1) {
                                        reported_events.push(r[i].textcode);
                                    }
                                }
                            }
                            req._reported_events = reported_events;
                        }
                    }
                    return req;
                } catch(E) {
                    alert('in util.network, rerequest_on_override, override:' + E);
                }
            }

            var result = obj.get_result(req);
            if (!result) return req;

            if ( 
                (typeof result.ilsevent != 'undefined') && 
                (
                    (override_params.overridable_events.indexOf( result.ilsevent == null || result.ilsevent == '' ? null : Number(result.ilsevent) ) != -1) ||
                    (override_params.overridable_events.indexOf( result.textcode ) != -1)
                )
            ) {
                req = override([result]);
            } else {
                var found_good = false; var found_bad = false;
                for (var i = 0; i < result.length; i++) {
                    if ( 
                        (typeof result[i].ilsevent != 'undefined') && 
                        (
                            (override_params.overridable_events.indexOf( result[i].ilsevent == null || result[i].ilsevent == '' ? null : Number(result[i].ilsevent) ) != -1) ||
                            (override_params.overridable_events.indexOf( result[i].textcode ) != -1) 
                        )
                    ) {
                        found_good = true;
                    } else {
                        found_bad = true;
                    }
                }
                if (found_good && (!found_bad)) req = override(result);
            }

            return req;
        } catch(E) {
            throw(E);
        }
    },

    'ping' : function() {
        try {
            JSAN.use('util.file'); JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
            var file = new util.file('ping.bat');
            var path = file._file.path;
            file.write_content('truncate+exec',
                '#!/bin/sh\n' +
                'ping -n 15 ' + data.server_unadorned + ' > "' + path + '.txt"\n' + /* windows */
                'ping -c 15 ' + data.server_unadorned + ' >> "' + path + '.txt"\n'  /* unix */
            );
            file.close();
            file = new util.file('ping.bat');

            var process = Components.classes["@mozilla.org/process/util;1"].createInstance(Components.interfaces.nsIProcess);
            process.init(file._file);

            var args = [];

            dump('process.run = ' + process.run(true, args, args.length) + '\n');

            file.close();

            var file = new util.file('ping.bat.txt');
            var output = file.get_content();
            file.close();

            return output;
        } catch(E) {
            alert(E);
        }
    },

    'play_sounds' : function(req) {
        var obj = this;
        try {
            var result = req.getResultObject();
            if (result == null) { return; }
            if (typeof result.textcode != 'undefined') {
                obj.sound.event( result );
            } else {
                if (typeof result.length != 'undefined') {
                    for (var i = 0; i < result.length; i++) {
                        if (typeof result[i].textcode != 'undefined') {
                            obj.sound.event( result[i] );
                        }
                    }
                }
            }
        } catch(E) {
            dump('Error in network.js, play_sounds() : ' + E + '\n');
        }
    }
}

/*
function sample_callback(request) {
    var result = request.getResultObject();
}
*/

dump('exiting util/network.js\n');
