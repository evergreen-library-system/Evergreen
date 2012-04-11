    if(window.arguments && typeof window.arguments[0] == 'object' && typeof xulG == 'undefined') {
        xulG = window.arguments[0];
    }

    function $(id) { return document.getElementById(id); }

    function oils_unsaved_data_V() {
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
        data.stash_retrieve();
        if (typeof data.unsaved_data == 'undefined') { data.unsaved_data = 0; }
        data.unsaved_data++;
        window.oils_lock++;
        data.stash('unsaved_data');
        dump('\n=-=-=-=-=\n');
        dump('oils_unsaved_data_V for ' + location.href + '\n');
        dump('incrementing window.oils_lock\n');
        dump('incrementing data.unsaved_data\n');
        dump('\twindow.oils_lock == ' + window.oils_lock + '\n');
        dump('\tdata.unsaved_data == ' + data.unsaved_data + '\n');
    }

    function oils_unsaved_data_P(count) {
        dump('\n=-=-=-=-=\n');
        dump('oils_unsaved_data_P for ' + location.href + '\n');
        if (!count) { count = 1; }
        dump('decrementing window.oils_lock by ' + count + '\n');
        window.oils_lock -= count;
        if (window.oils_lock < 0) { window.oils_lock = 0; }
        JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
        data.stash_retrieve();
        if (typeof data.unsaved_data == 'undefined') { data.unsaved_data = 0; }
        dump('decrementing data.unsaved_data by ' + count + '\n');
        data.unsaved_data -= count;
        if (data.unsaved_data < 0) { data.unsaved_data = 0; }
        data.stash('unsaved_data');
        dump('\twindow.oils_lock == ' + window.oils_lock + '\n');
        dump('\tdata.unsaved_data == ' + data.unsaved_data + '\n');
    }

    function oils_lock_page(params) {
        dump('\n=-=-=-=-=\n');
        dump('oils_lock_page for ' + location.href + '\n');
        if (!params) { params = {}; }
        if (window.oils_lock > 0) {
            if (!params.allow_multiple_locks) {
                return window.oils_lock;
            }
        }
        if (typeof xulG != 'undefined') {
            if (typeof xulG.unlock_tab == 'function') {
                dump('\twith xulG.lock_tab\n');
                xulG.lock_tab();
                window.oils_lock++; // different window scope than the chrome of xulG.lock_tab
            } else {
                dump('\twithout xulG.lock_tab\n');
                oils_unsaved_data_V();
            }
        } else {
            dump('\twithout xulG.lock_tab\n');
            oils_unsaved_data_V();
        }
        return window.oils_lock;
    }

    function oils_unlock_page(params) {
        dump('\n=-=-=-=-=\n');
        dump('oils_unlock_page for ' + location.href + '\n');
        if (typeof xulG != 'undefined') {
            if (typeof xulG.unlock_tab == 'function') {
                dump('\twith xulG.unlock_tab\n');
                xulG.unlock_tab();
                window.oils_lock--; // different window scope than the chrome of xulG.unlock_tab
                if (window.oils_lock < 0) { window.oils_lock = 0; }
            } else {
                dump('\twithout xulG.unlock_tab\n');
                oils_unsaved_data_P();
            }
        } else {
            dump('\twithout xulG.unlock_tab\n');
            oils_unsaved_data_P();
        }
        return window.oils_lock;
    }

    window.oils_lock = 0;
    dump('\n=-=-=-=-=\n');
    dump('init window.oils_lock == ' + window.oils_lock + ' for ' + location.href + '\n');
    window.addEventListener(
        'close',
        function(ev) {
            try {
                dump('\n=-=-=-=-=\n');
                dump('oils_lock_page/oils_unlock_page onclose handler for ' + location.href + '\n');
                if (window.oils_lock > 0) {
                    var confirmation = window.confirm($('offlineStrings').getString('menu.close_window.unsaved_data_warning'));
                    if (!confirmation) {
                        ev.preventDefault();
                        return false;
                    }
                }

                if (typeof xulG != 'undefined') {
                    if (typeof xulG.unlock_tab == 'function') {
                        xulG.unlock_tab();
                    } else {
                        oils_unsaved_data_P( window.oils_lock );
                    }
                } else {
                    oils_unsaved_data_P( window.oils_lock );
                }
                window.oils_lock = 0;
                dump('forcing window.oils_lock == ' + window.oils_lock + '\n');

                // Dispatching the window close event doesn't always close the window, even though the event does happen
                setTimeout(
                    function() {
                        try {
                            window.close();
                        } catch(E) {
                            dump('Error inside global_util.js, onclose handler, setTimeout window.close KLUDGE: ' + E + '\n');
                        }
                    }, 0
                );

                return true;
            } catch(E) {
                dump('Error inside global_util.js, onclose handler: ' + E + '\n');
                return true;
            }
        },
        false
    );

    function ses(a,params) {
        try {
            if (!params) params = {};
            var data;
            if (params.data) {
                data = params.data; data.stash_retrieve();
            } else {
                // This has been breaking in certain contexts, with an internal instantiation of util.error failing because of util.error being an object instead of the constructor function it should be
                JSAN.use('OpenILS.data'); data = new OpenILS.data(); data.stash_retrieve();
            }

            switch(a) {
                case 'staff' : return data.list.au[0]; break;
                case 'staff_id' : return data.list.au[0].id(); break;
                case 'staff_usrname' : return data.list.au[0].usrname(); break;
                case 'ws_name':
                    return data.ws_name;
                break;
                case 'ws_id' :
                    return data.list.au[0].wsid();
                break;
                case 'ws_ou' :
                    return data.list.au[0].ws_ou();
                break;
                case 'ws_ou_shortname' :
                    return data.hash.aou[ data.list.au[0].ws_ou() ].shortname();
                break;
                case 'authtime' :
                    return data.session.authtime;
                break;
                case 'key':
                default:
                    return data.session.key;
                break;
            }
        } catch(E) {
            alert(location.href + '\nError in global_utils.js, ses(): ' + E);
            throw(E);
        }
    }

    function font_helper() {
        try {
            JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
            removeCSSClass(document.documentElement,'ALL_FONTS_LARGER');
            removeCSSClass(document.documentElement,'ALL_FONTS_SMALLER');
            removeCSSClass(document.documentElement,'ALL_FONTS_XX_SMALL');
            removeCSSClass(document.documentElement,'ALL_FONTS_X_SMALL');
            removeCSSClass(document.documentElement,'ALL_FONTS_SMALL');
            removeCSSClass(document.documentElement,'ALL_FONTS_MEDIUM');
            removeCSSClass(document.documentElement,'ALL_FONTS_LARGE');
            removeCSSClass(document.documentElement,'ALL_FONTS_X_LARGE');
            removeCSSClass(document.documentElement,'ALL_FONTS_XX_LARGE');
            addCSSClass(document.documentElement,data.global_font_adjust);
        } catch(E) {
            var Strings = $('offlineStrings') || $('commonStrings');
            alert(Strings.getFormattedString('openils.global_util.font_size.error', [E]));
        }
    }

    function oils_persist(e,cancelable) {
        try {
            if (!e) { return; }
            if (typeof cancelable == 'undefined') { cancelable = false; } 
            var evt = document.createEvent("Events");
            evt.initEvent( 'oils_persist', false, cancelable ); // event name, bubbles, cancelable
            e.dispatchEvent(evt);
        } catch(E) {
            alert('Error with oils_persist():' + E);
        }
    }

    function oils_persist_hostname() {
        if(location.protocol == 'oils:') {
            JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
            return data.server_unadorned;
        } else {
            return location.hostname;
        }
    }

    function persist_helper(base_key_suffix) {
        try {
            if (base_key_suffix) {
                base_key_suffix = base_key_suffix.replace(/[^A-Za-z]/g,'_') + '_';
            } else {
                base_key_suffix = '';
            }

            function gen_event_handler(etype,node) {
                return function(ev) {
                    try {
                        oils_persist(ev.target);
                    } catch(E) {
                        alert('Error in persist_helper, firing virtual event oils_persist after ' + etype + ' event on ' + node.nodeName + '.id = ' + node.id + ': ' + E);
                    }
                };
            };

            function gen_oils_persist_handler(bk,node) {
                return function(ev) {
                    try {
                        var target;
                        if (ev.target.nodeName == 'command') {
                            target = node;
                            if (ev.explicitOriginalTarget != node) return;
                        } else {
                            target = ev.target;
                            if (target == window) {
                                target = window.document.documentElement;
                            }
                        }
                        var filename = location.pathname.split('/')[ location.pathname.split('/').length - 1 ];
                        var base_key = 'oils_persist_' + String(oils_persist_hostname() + '_' + filename + '_' + target.getAttribute('id')).replace('/','_','g') + '_' + base_key_suffix;
                        var attribute_list = target.getAttribute('oils_persist').split(' ');
                        dump('on_oils_persist: <<< ' + target.nodeName + '.id = ' + target.id + '\t' + bk + '\n');
                        for (var j = 0; j < attribute_list.length; j++) {
                            var key = base_key + attribute_list[j];
                            var value;
                            try {
                                value = encodeURI(target.getAttribute( attribute_list[j] ));
                            } catch(E) {
                                dump('Error in persist_helper with encodeURI: ' + E + '\n');
                                value = target.getAttribute( attribute_list[j] );
                            }
                            if ( attribute_list[j] == 'checked' && ['checkbox','toolbarbutton'].indexOf( target.nodeName ) > -1 ) {
                                value = target.checked;
                                dump('\t' + value + ' <== .' + attribute_list[j] + '\n');
                            } else if ( attribute_list[j] == 'value' && ['menulist'].indexOf( target.nodeName ) > -1 ) {
                                value = target.value;
                                dump('\t' + value + ' <== .' + attribute_list[j] + '\n');
                            } else if ( attribute_list[j] == 'value' && ['textbox'].indexOf( target.nodeName ) > -1 ) {
                                value = target.value;
                                dump('\t' + value + ' <== .' + attribute_list[j] + '\n');
                            } else if ( attribute_list[j] == 'sizemode' && ['window'].indexOf( target.nodeName ) > -1 ) {
                                value = window.windowState;
                                dump('\t' + value + ' <== window.windowState, @' + attribute_list[j] + '\n');
                            } else if ( attribute_list[j] == 'height' && ['window'].indexOf( target.nodeName ) > -1 ) {
                                value = window.outerHeight;
                                dump('\t' + value + ' <== window.outerHeight, @' + attribute_list[j] + '\n');
                            } else if ( attribute_list[j] == 'width' && ['window'].indexOf( target.nodeName ) > -1 ) {
                                value = window.outerWidth;
                                dump('\t' + value + ' <== window.outerWidth, @' + attribute_list[j] + '\n');
                            } else {
                                dump('\t' + value + ' <== @' + attribute_list[j] + '\n');
                            }
                            prefs.setCharPref( key, value );
                            // TODO: Need to add logic for splitter repositioning, grippy state, etc.
                            // NOTE: oils_persist_peers and oils_persist="width" on those peers can help with the elements adjacent to a splitter
                        }
                        if (target.hasAttribute('oils_persist_peers') && ! ev.cancelable) { // We abuse the .cancelable field on the oils_persist event to prevent looping
                            var peer_list = target.getAttribute('oils_persist_peers').split(' ');
                            for (var j = 0; j < peer_list.length; j++) {
                                dump('on_oils_persist: dispatching oils_persist to peer ' + peer_list[j] + '\n');
                                oils_persist( document.getElementById( peer_list[j] ), true );
                            } 
                        }
                    } catch(E) {
                        alert('Error in persist_helper() event listener for ' + bk + ': ' + E);
                    }
                };
            }

            var prefs = Components.classes['@mozilla.org/preferences-service;1'].getService(Components.interfaces['nsIPrefBranch']);
            var nodes = document.getElementsByAttribute('oils_persist','*');
            for (var i = 0; i < nodes.length; i++) {
                var filename = location.pathname.split('/')[ location.pathname.split('/').length - 1 ];
                var base_key = 'oils_persist_' + String(oils_persist_hostname() + '_' + filename + '_' + nodes[i].getAttribute('id')).replace('/','_','g') + '_' + base_key_suffix;
                var attribute_list = nodes[i].getAttribute('oils_persist').split(' ');
                dump('persist_helper: >>> ' + nodes[i].nodeName + '.id = ' + nodes[i].id + '\t' + base_key + '\n');
                for (var j = 0; j < attribute_list.length; j++) {
                    var key = base_key + attribute_list[j];
                    var has_key = prefs.prefHasUserValue(key);
                    var value;
                    try {
                        value = has_key ? decodeURI(prefs.getCharPref(key)) : null;
                    } catch(E) {
                        dump('Error in persist_helper with decodeURI: ' + E + '\n');
                        value = has_key ? prefs.getCharPref(key) : null;
                    }
                    if (value == 'true') { value = true; }
                    if (value == 'false') { value = false; }
                    if (has_key) {
                        if ( attribute_list[j] == 'checked' && ['checkbox','toolbarbutton'].indexOf( nodes[i].nodeName ) > -1 ) {
                            nodes[i].checked = value; 
                            dump('\t' + value + ' ==> .' + attribute_list[j] + '\n');
                            if (!value) {
                                nodes[i].removeAttribute('checked');
                                dump('\tremoving @checked\n');
                            }
                        } else if ( attribute_list[j] == 'value' && ['textbox'].indexOf( nodes[i].nodeName ) > -1 ) {
                            nodes[i].value = value;
                            dump('\t' + value + ' ==> .' + attribute_list[j] + '\n');
                        } else if ( attribute_list[j] == 'value' && ['menulist'].indexOf( nodes[i].nodeName ) > -1 ) {
                            nodes[i].value = value;
                            dump('\t' + value + ' ==> .' + attribute_list[j] + '\n');       
                        } else if ( attribute_list[j] == 'sizemode' && ['window'].indexOf( nodes[i].nodeName ) > -1 ) {
                            switch(value) {
                                case window.STATE_MAXIMIZED:
                                    window.maximize();
                                    break;
                                case window.STATE_MINIMIZED:
                                    window.minimize();
                                    break;
                            };
                            dump('\t' + value + ' ==> window.windowState, @' + attribute_list[j] + '\n');
                        } else if ( attribute_list[j] == 'height' && ['window'].indexOf( nodes[i].nodeName ) > -1 ) {
                            window.outerHeight = value;
                            dump('\t' + value + ' ==> window.outerHeight, @' + attribute_list[j] + '\n');
                        } else if ( attribute_list[j] == 'width' && ['window'].indexOf( nodes[i].nodeName ) > -1 ) {
                            window.outerWidth = value;
                            dump('\t' + value + ' ==> window.outerWidth, @' + attribute_list[j] + '\n');
                        } else {
                            nodes[i].setAttribute( attribute_list[j], value);
                            dump('\t' + value + ' ==> @' + attribute_list[j] + '\n');
                        }
                    }
                }
                var cmd = nodes[i].getAttribute('command');
                var cmd_el = document.getElementById(cmd);
                if (nodes[i].disabled == false && nodes[i].hidden == false) {
                    var no_poke = nodes[i].getAttribute('oils_persist_no_poke');
                    if (no_poke && no_poke == 'true') {
                        // Timing issue for some checkboxes; don't poke them with an event
                        dump('\tnot poking\n');
                    } else {
                        if (cmd_el) {
                            dump('\tpoking @command\n');
                            var evt = document.createEvent("Events");
                            evt.initEvent( 'command', true, true );
                            cmd_el.dispatchEvent(evt);
                        } else {
                            dump('\tpoking\n');
                            var evt = document.createEvent("Events");
                            evt.initEvent( 'command', true, true );
                            nodes[i].dispatchEvent(evt);
                        }
                    }
                }
                if (cmd_el) {
                    cmd_el.addEventListener(
                        'command',
                        gen_event_handler('command',cmd_el),
                        false
                    );
                    cmd_el.addEventListener(
                        'oils_persist',
                        gen_oils_persist_handler( base_key, nodes[i] ),
                        false
                    );
                } else {
                    var node = nodes[i];
                    var event_types = [];
                    if (node.hasAttribute('oils_persist_events')) {
                        var event_type_list = node.getAttribute('oils_persist_events').split(' ');
                        for (var j = 0; j < event_type_list.length; j++) {
                            event_types.push( event_type_list[j] );
                        }
                    } else {
                        if (node.nodeName == 'textbox') { 
                            event_types.push('change');
                        } else if (node.nodeName == 'menulist') { 
                            event_types.push('select');  
                        } else if (node.nodeName == 'window') {
                            event_types.push('resize'); 
                            node = window; // xul window is an element of window.document
                        } else {
                            event_types.push('command'); 
                        }
                    }
                    for (var j = 0; j < event_types.length; j++) {
                        node.addEventListener(
                            event_types[j],
                            gen_event_handler(event_types[j],node),
                            false
                        );
                    }
                    node.addEventListener(
                        'oils_persist',
                        gen_oils_persist_handler( base_key, node ),
                        false
                    );
                }
            }
        } catch(E) {
            alert('Error in persist_helper(): ' + E);
        }
    }

    function getKeys(o) {
        var keys = [];
        for (var k in o) keys.push(k);
        return keys;
    }

    function get_contentWindow(frame) {
        try {
            if (frame && frame.contentWindow) {
                try {
                    if (typeof frame.contentWindow.wrappedJSObject != 'undefined') {
                                     return frame.contentWindow.wrappedJSObject;
                          }
                } catch(E) {
                    var Strings = $('offlineStrings') || $('commonStrings');
                    alert(Strings.getFormattedString('openils.global_util.content_window_jsobject.error', [frame, E]));
                }
                return frame.contentWindow;
            } else {
                return null;
            }
        } catch(E) {
            var Strings = $('offlineStrings') || $('commonStrings');
            alert(Strings.getFormattedString('openils.global_util.content_window.error', [frame, E]));
        }
    }

    function xul_param(param_name,_params) {
        /* By default, this function looks for a CGI-style query param identified by param_name.  If one isn't found, it then looks in xulG.  If one still isn't found, and _params.stash_name is true, it looks in the global xpcom stash for the field identified by stash_name.  If _params.concat is true, then it looks in all these places and concatenates the results.  There are also options for converting JSON to javascript objects, and clearing the xpcom stash_name field after retrieval.  Also added, ability to search a specific spot in the xpcom stash that implements a stack to hold xulG's for modal windows */
        try {
            //dump('xul_param('+param_name+','+js2JSON(_params)+')\n');
            var value = undefined; if (!_params) _params = {};
            if (typeof _params.no_cgi == 'undefined') {
                var cgi = new CGI();
                if (cgi.param(param_name)) {
                    var x = cgi.param(param_name);
                    //dump('\tfound via location.href = ' + x + '\n');
                    if (typeof _params.JSON2js_if_cgi != 'undefined') {
                        x = JSON2js( x );
                        //dump('\tJSON2js = ' + x + '\n');
                    }
                    if (typeof _params.concat == 'undefined') {
                        //alert(param_name + ' x = ' + x);
                        return x; // value
                    } else {
                        if (value) {
                            if (value.constructor != Array) value = [ value ];
                            value = value.concat(x);
                        } else {
                            value = x;
                        }
                    }
                }
            }
            if (typeof _params.no_xulG == 'undefined') {
                if (typeof xulG == 'object' && typeof xulG[ param_name ] != 'undefined') {
                    var x = xulG[ param_name ];
                    //dump('\tfound via xulG = ' + x + '\n');
                    if (typeof _params.JSON2js_if_xulG != 'undefined') {
                        x = JSON2js( x );
                        //dump('\tJSON2js = ' + x + '\n');
                    }
                    if (typeof _params.concat == 'undefined') {
                        //alert(param_name + ' x = ' + x);
                        return x; // value
                    } else {
                        if (value) {
                            if (value.constructor != Array) value = [ value ];
                            value = value.concat(x);
                        } else {
                            value = x;
                        }
                    }
                }
            }
            if (typeof _params.no_xpcom == 'undefined') {
                /* the field names used for temp variables in the global stash tend to be more unique than xuLG or CGI param names, to avoid collisions */
                if (typeof _params.stash_name != 'undefined') { 
                    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
                    if (typeof data[ _params.stash_name ] != 'undefined') {
                        var x = data[ _params.stash_name ];
                        //dump('\tfound via xpcom = ' + x + '\n');
                        if (typeof _params.JSON2js_if_xpcom != 'undefined') {
                            x = JSON2js( x );
                            //dump('\tJSON2js = ' + x + '\n');
                        }
                        if (_params.clear_xpcom) { 
                            data[ _params.stash_name ] = undefined; data.stash( _params.stash_name ); 
                        }
                        if (typeof _params.concat == 'undefined') {
                            //alert(param_name + ' x = ' + x);
                            return x; // value
                        } else {
                            if (value) {
                                if (value.constructor != Array) value = [ value ];
                                value = value.concat(x);
                            } else {
                                value = x;
                            }
                        }
                    }
                }
            }
            //alert(param_name + ' value = ' + value);
            return value;
        } catch(E) {
            dump('xul_param error: ' + E + '\n');
        }
    }

    function get_bool(a) {
        // Normal javascript interpretation except 'f' == false, per postgres, and 'F' == false, and '0' == false (newer JSON is returning '0' instead of 0 in cases)
        // So false includes 'f', '', '0', 0, null, and undefined
        if (a == 'f') return false;
        if (a == 'F') return false;
        if (a == '0') return false;
        if (a) return true; else return false;
    }

    function get_localized_bool(a) {
        var Strings = $('offlineStrings') || $('commonStrings');
        return get_bool(a) ? Strings.getString('common.yes') : Strings.getString('common.no');
    }

    function get_db_true() {
        return 't';
    }

    function get_db_false() {
        return 'f';
    }

    function copy_to_clipboard(ev) {
        try {
            var text;
            if (typeof ev == 'object') {
                if (typeof ev.target != 'undefined') {
                    if (typeof ev.target.textContent != 'undefined') if (ev.target.textContent) text = ev.target.textContent;
                    if (typeof ev.target.value != 'undefined') if (ev.target.value) text = ev.target.value;
                }
            } else if (typeof ev == 'string') {
                text = ev;
            }
            const gClipboardHelper = Components.classes["@mozilla.org/widget/clipboardhelper;1"]
                .getService(Components.interfaces.nsIClipboardHelper);
            gClipboardHelper.copyString(text);
            var Strings = $('offlineStrings') || $('commonStrings');
            alert(Strings.getFormattedString('openils.global_util.clipboard', [text]));
        } catch(E) {
            var Strings = $('offlineStrings') || $('commonStrings');
            alert(Strings.getFormattedString('openils.global_util.clipboard.error', [E]));    
        }
    }

    function clear_the_cache() {
        try {
            var cacheClass         = Components.classes["@mozilla.org/network/cache-service;1"];
            var cacheService    = cacheClass.getService(Components.interfaces.nsICacheService);
            cacheService.evictEntries(Components.interfaces.nsICache.STORE_ON_DISK);
            cacheService.evictEntries(Components.interfaces.nsICache.STORE_IN_MEMORY);
        } catch(E) {
            var Strings = $('offlineStrings') || $('commonStrings');
            alert(Strings.getFormattedString('openils.global_util.clear_cache.error', [E]));
        }
    }

    function toOpenWindowByType(inType, uri) {
        var winopts = "chrome,extrachrome,menubar,resizable,scrollbars,status,toolbar";
        window.open(uri, "_blank", winopts);
    }

    function url_prefix(url) {
        var base_url = url.match(/^[^?/|]+/);
        if(base_url) {
            base_url = base_url[0];
            if(urls[base_url])
                url = url.replace(/^[^?/|]+\|/, urls[base_url]);
        }
        if (url.match(/^\//)) url = urls.remote + url;
        if (! url.match(/^(http|https|chrome|oils):\/\//) && ! url.match(/^data:/) ) url = 'http://' + url;
        dump('url_prefix = ' + url + '\n');
        return url;
    }

    function widget_prompt(node,args) {
        // args is an object that may contain the following keys: title, desc, ok_label, ok_accesskey, cancel_label, cancel_accesskey, access, method
        // access may contain 'property' or 'attribute' or 'method' for retrieving the value from the node
        // if 'method', then the method key will reference a function that returns the value
        try {
            if (!node) { return false; }
            if (!args) { args = {}; }
            args[ 'widget' ] = node;

            var url = location.protocol == 'chrome'
                ? 'chrome://open_ils_staff_client/content/util/widget_prompt.xul'
                : '/xul/server/util/widget_prompt.xul';

            JSAN.use('util.window'); var win = new util.window();
            var my_xulG = win.open(
                url,
                args.title || 'widget_prompt',
                'chrome,modal',
                args
            );

            if (my_xulG.status == 'incomplete') {
                return false;
            } else {
                return my_xulG.value;
            }
        } catch(E) {
            alert('Error in global_utils.js, widget_prompt(): ' + E);
        }
    }
