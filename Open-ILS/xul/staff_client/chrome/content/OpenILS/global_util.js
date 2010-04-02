    function $(id) { return document.getElementById(id); }

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

    function persist_helper() {
        try {
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
                        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
                        var target;
                        if (ev.target.nodeName == 'command') {
                            target = node;
                            if (ev.explicitOriginalTarget != node) return;
                        } else {
                            target = ev.target;
                        }
                        var filename = location.pathname.split('/')[ location.pathname.split('/').length - 1 ];
                        var base_key = 'oils_persist_' + String(location.hostname + '_' + filename + '_' + target.getAttribute('id')).replace('/','_','g') + '_';
                        var attribute_list = target.getAttribute('oils_persist').split(' ');
                        dump('on_oils_persist: <<< ' + target.nodeName + '.id = ' + target.id + '\t' + bk + '\n');
                        for (var j = 0; j < attribute_list.length; j++) {
                            var key = base_key + attribute_list[j];
                            var value = target.getAttribute( attribute_list[j] );
                            if ( attribute_list[j] == 'checked' && ['checkbox','toolbarbutton'].indexOf( target.nodeName ) > -1 ) {
                                value = target.checked;
                                dump('\t' + value + ' <== .' + attribute_list[j] + '\n');
                            } else if ( attribute_list[j] == 'value' && ['textbox'].indexOf( target.nodeName ) > -1 ) {
                                value = target.value;
                                dump('\t' + value + ' <== .' + attribute_list[j] + '\n');
                            } else {
                                dump('\t' + value + ' <== @' + attribute_list[j] + '\n');
                            }
                            prefs.setCharPref( key, value );
                            // TODO: Need to add logic for window resizing, splitter repositioning, grippy state, etc.
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

            netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
            var prefs = Components.classes['@mozilla.org/preferences-service;1'].getService(Components.interfaces['nsIPrefBranch']);
            var nodes = document.getElementsByAttribute('oils_persist','*');
            for (var i = 0; i < nodes.length; i++) {
                var filename = location.pathname.split('/')[ location.pathname.split('/').length - 1 ];
                var base_key = 'oils_persist_' + String(location.hostname + '_' + filename + '_' + nodes[i].getAttribute('id')).replace('/','_','g') + '_';
                var attribute_list = nodes[i].getAttribute('oils_persist').split(' ');
                dump('persist_helper: >>> ' + nodes[i].nodeName + '.id = ' + nodes[i].id + '\t' + base_key + '\n');
                for (var j = 0; j < attribute_list.length; j++) {
                    var key = base_key + attribute_list[j];
                    var has_key = prefs.prefHasUserValue(key);
                    var value = has_key ? prefs.getCharPref(key) : null;
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
                    var event_types = [];
                    if (nodes[i].hasAttribute('oils_persist_events')) {
                        var event_type_list = nodes[i].getAttribute('oils_persist_events').split(' ');
                        for (var j = 0; j < event_type_list.length; j++) {
                            event_types.push( event_type_list[j] );
                        }
                    } else {
                        if (nodes[i].nodeName == 'textbox') { 
                            event_types.push('change'); 
                        } else {
                            event_types.push('command'); 
                        }
                    }
                    for (var j = 0; j < event_types.length; j++) {
                        nodes[i].addEventListener(
                            event_types[j],
                            gen_event_handler(event_types[j],nodes[i]),
                            false
                        );
                    }
                    nodes[i].addEventListener(
                        'oils_persist',
                        gen_oils_persist_handler( base_key, nodes[i] ),
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
            netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
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

    function update_modal_xulG(v) {
        try {
            JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
            var key = location.pathname + location.search + location.hash;
            if (typeof data.modal_xulG_stack != 'undefined' && typeof data.modal_xulG_stack[key] != 'undefined') {
                data.modal_xulG_stack[key][ data.modal_xulG_stack[key].length - 1 ] = v;
                data.stash('modal_xulG_stack');
            }
        } catch(E) {
            alert('FIXME: update_modal_xulG => ' + E);
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
                if (typeof _params.modal_xulG != 'undefined') {
                    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
                    var key = location.pathname + location.search + location.hash;
                    //dump('xul_param, considering modal key = ' + key + '\n');
                    if (typeof data.modal_xulG_stack != 'undefined' && typeof data.modal_xulG_stack[key] != 'undefined') {
                        xulG = data.modal_xulG_stack[key][ data.modal_xulG_stack[key].length - 1 ];
                    }
                }
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
            netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
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
            netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
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
        if (url.match(/^\//)) url = urls.remote + url;
        if (! url.match(/^(http|chrome):\/\//) && ! url.match(/^data:/) ) url = 'http://' + url;
        dump('url_prefix = ' + url + '\n');
        return url;
    }

