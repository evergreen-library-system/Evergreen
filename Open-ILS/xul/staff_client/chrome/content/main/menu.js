dump('entering main/menu.js\n');
// vim:noet:sw=4:ts=4:

var offlineStrings;

if (typeof main == 'undefined') main = {};
main.menu = function () {

    netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
    offlineStrings = document.getElementById('offlineStrings');
    JSAN.use('util.error'); this.error = new util.error();
    JSAN.use('util.window'); this.window = new util.window();
    JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});

    this.w = window;
    var x = document.getElementById('network_progress');
    x.setAttribute('count','0');
    x.addEventListener(
        'click',
        function() {
            if ( window.confirm(offlineStrings.getString('menu.reset_network_stats')) ) {
                var y = document.getElementById('network_progress_rows');
                while(y.firstChild) { y.removeChild( y.lastChild ); }
                x.setAttribute('mode','determined');
                x.setAttribute('count','0');
            }
        },
        false
    );
}

main.menu.prototype = {

    'id_incr' : 0,

    'toolbar' : 'none',
    'toolbar_size' : 'large',
    'toolbar_mode' : 'both',
    'toolbar_labelpos' : 'side',

    'url_prefix' : function(url,secure) {
        // if host unspecified URL with leading /, prefix the remote hostname
        if (url.match(/^\//)) url = urls.remote + url;
        // if it starts with http:// and we want secure, convert to https://
        if (secure && url.match(/^http:\/\//)) {
            url = url.replace(/^http:\/\//, 'https://');
        }
        // if it doesn't start with a known protocol, add http(s)://
        if (! url.match(/^(http|https|chrome):\/\//) && ! url.match(/^data:/) ) {
            url = secure
                ? 'https://' + url
                : 'http://' + url;
        }
        dump('url_prefix = ' + url + '\n');
        return url;
    },

    'init' : function( params ) {

        var obj = this;

        urls.remote = params['server'];

        xulG.get_barcode = this.get_barcode;
        xulG.get_barcode_and_settings = this.get_barcode_and_settings;

        // Pull in local customizations
        var r = new XMLHttpRequest();
        r.open("GET", obj.url_prefix('/xul/server/skin/custom.js'), false);
        r.send(null);
        if (r.status == 200) {
            dump('Evaluating /xul/server/skin/custom.js\n');
            eval( r.responseText );
        }

        this.button_bar_init();

        var cl_first = xulG.pref.getBoolPref('oils.copy_editor.copy_location_name_first');
        var menuitems = document.getElementsByAttribute('command','cmd_copy_editor_copy_location_first_toggle');
        for(var i = 0; i < menuitems.length; i++)
            menuitems[i].setAttribute('checked', cl_first ? 'true' : 'false');

        xulG.pref.addObserver('', this, false);
        window.addEventListener("unload", function(e) { this.stop_observing(); }, false);

        var network_meter = String( obj.data.hash.aous['ui.network.progress_meter'] ) == 'true';
        if (! network_meter) {
            var x = document.getElementById('network_progress');
            if (x) x.setAttribute('hidden','true');
            var y = document.getElementById('page_progress');
            if (y) y.setAttribute('hidden','true');
        }

        var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"].
                    getService(Components.interfaces.nsIWindowMediator);
        var mainwin = wm.getMostRecentWindow('eg_main');
        mainwin.get_menu_perms(document);
        var hotkeysets = mainwin.load_hotkey_sets();

        var popupmenu = document.getElementById('main.menu.admin.client.hotkeys.current.popup');
        
        for(var i = 0; i < hotkeysets.length; i++) {
            var keysetname = hotkeysets[i];
            var menuitem = document.createElement('menuitem');
            if(offlineStrings.testString('hotkey.' + keysetname))
                menuitem.setAttribute('label',offlineStrings.getString('hotkey.' + keysetname));
            else
                menuitem.setAttribute('label',keysetname);
            menuitem.setAttribute('value',keysetname);
            menuitem.setAttribute('type','radio');
            menuitem.setAttribute('name','menu_hotkey_current');
            menuitem.setAttribute('command','cmd_hotkeys_set');
            popupmenu.appendChild(menuitem);
        }

        JSAN.use('util.network');
        var network = new util.network();
        network.set_user_status();

        this.set_menu_hotkeys();

        function open_conify_page(path, labelKey, event) {

            // tab label
            labelKey = labelKey || 'menu.cmd_open_conify.tab';
            label = offlineStrings.getString(labelKey);

            // URL
            var loc = urls.XUL_BROWSER + '?url=' + window.escape( obj.url_prefix(urls.CONIFY) + '/' + path + '.html');

            obj.command_tab(
                event,
                loc, 
                {'tab_name' : label, 'browser' : false }, 
                {'no_xulG' : false, 'show_print_button' : false, show_nav_buttons:true} 
            );
        }

        function open_admin_page(path, labelKey, addSes, event) {

            // tab label
            labelKey = labelKey || 'menu.cmd_open_conify.tab';
            label = offlineStrings.getString(labelKey);

            // URL
            var loc = urls.XUL_BROWSER + '?url=' + window.escape( obj.url_prefix(urls.XUL_LOCAL_ADMIN_BASE) + '/' + path);
            if(addSes) loc += window.escape('?ses=' + ses());

            obj.command_tab( 
                event,
                loc, 
                {'tab_name' : label, 'browser' : false }, 
                {'no_xulG' : false, 'show_print_button' : true, 'show_nav_buttons' : true } 
            );
        }


        function open_eg_web_page(path, labelKey, event) {
            
            // tab label
            labelKey = labelKey || 'menu.cmd_open_conify.tab';
            var label = offlineStrings.getString(labelKey);

            // URL
            var loc = urls.XUL_BROWSER + '?url=' + window.escape(obj.url_prefix(urls.EG_WEB_BASE) + '/' + path);

            obj.command_tab(
                event,
                loc, 
                {tab_name : label, browser : false }, 
                {no_xulG : false, show_print_button : true, show_nav_buttons : true }
            );
        }

        var cmd_map = {
            'cmd_broken' : [
                ['oncommand'],
                function() { alert(offlineStrings.getString('common.unimplemented')); }
            ],

            /* File Menu */
            'cmd_close_window' : [ 
                ['oncommand'], 
                function() {
                    JSAN.use('util.widgets');
                    util.widgets.dispatch('close',window);
                }
            ],
            'cmd_new_window' : [
                ['oncommand'],
                function() {
                    var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"].
                        getService(Components.interfaces.nsIWindowMediator);
                    wm.getMostRecentWindow('eg_main').new_tabs(Array('new'));
                }
            ],
            'cmd_new_tab' : [
                ['oncommand'],
                function() {
                    if (obj.new_tab(null,{'focus':true},null) == false)
                    {
                        if(window.confirm(offlineStrings.getString('menu.new_tab.max_tab_dialog')))
                        {
                            var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"].
                                getService(Components.interfaces.nsIWindowMediator);
                            wm.getMostRecentWindow('eg_main').new_tabs(Array('tab'));
                        }
                    }
                }
            ],
            'cmd_portal' : [
                ['oncommand'],
                function() {
                    obj.set_tab();
                }
            ],
            'cmd_close_tab' : [
                ['oncommand'],
                function(event) {
                    var myEvent = event;
                    var closeAll = false;
                    if(event && event.sourceEvent) myEvent = event.sourceEvent;
                    // Note: The last event is not supposed to be myEvent in this if.
                    if(myEvent && myEvent.explicitOriginalTarget.nodeName.match(/toolbarbutton/) && myEvent.explicitOriginalTarget.command == event.originalTarget.id) {
                        var value = xulG.pref.getIntPref('ui.key.accelKey');
                        switch(value) {
                            case 17:
                                closeAll = myEvent.ctrlKey;
                                break;
                            case 18:
                                closeAll = myEvent.altKey;
                                break;
                            case 224:
                                closeAll = myEvent.metaKey;
                                break;
                        }
                    }
                    if(closeAll) {
                        obj.close_all_tabs();
                    } else {
                        obj.close_tab();
                    }
                }
            ],
            'cmd_close_all_tabs' : [
                ['oncommand'],
                function() { obj.close_all_tabs(); }
            ],

            /* Edit Menu */
            'cmd_edit_copy_buckets' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_COPY_BUCKETS),{'tab_name':offlineStrings.getString('menu.cmd_edit_copy_buckets.tab')},{});
                }
            ],
            'cmd_edit_volume_buckets' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_VOLUME_BUCKETS),{'tab_name':offlineStrings.getString('menu.cmd_edit_volume_buckets.tab')},{});
                }
            ],
            'cmd_edit_record_buckets' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_RECORD_BUCKETS),{'tab_name':offlineStrings.getString('menu.cmd_edit_record_buckets.tab')},{});
                }
            ],
            'cmd_edit_user_buckets' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_USER_BUCKETS),{'tab_name':offlineStrings.getString('menu.cmd_edit_user_buckets.tab')},{});
                }
            ],


            'cmd_replace_barcode' : [
                ['oncommand'],
                function() {
                    try {
                        JSAN.use('util.network');
                        var network = new util.network();

                        var old_bc = window.prompt(offlineStrings.getString('menu.cmd_replace_barcode.prompt'),'',offlineStrings.getString('menu.cmd_replace_barcode.label'));
                        if (!old_bc) return;
    
                        var copy;
                        try {
                            copy = network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[ old_bc ]);
                            if (typeof copy.ilsevent != 'undefined') throw(copy); 
                            if (!copy) throw(copy);
                        } catch(E) {
                            alert(offlineStrings.getFormattedString('menu.cmd_replace_barcode.retrieval.error', [old_bc]) + '\n');
                            return;
                        }
    
                        // Why did I want to do this twice?  Because this copy is more fleshed?
                        try {
                            copy = network.simple_request('FM_ACP_RETRIEVE',[ copy.id() ]);
                            if (typeof copy.ilsevent != 'undefined') throw(copy);
                            if (!copy) throw(copy);
                        } catch(E) {
                            try { alert(offlineStrings.getFormattedString('menu.cmd_replace_barcode.retrieval.error', [old_bc]) + '\n' + (typeof E.ilsevent == 'undefined' ? '' : E.textcode + ' : ' + E.desc)); } catch(F) { alert(E + '\n' + F); }
                            return;
                        }
    
                        var new_bc = window.prompt(offlineStrings.getString('menu.cmd_replace_barcode.replacement.prompt'),'',offlineStrings.getString('menu.cmd_replace_barcode.replacement.label'));
                        new_bc = String( new_bc ).replace(/\s/g,'');
                        /* Casting a possibly null input value to a String turns it into "null" */
                        if (!new_bc || new_bc == 'null') {
                            alert(offlineStrings.getString('menu.cmd_replace_barcode.blank.error'));
                            return;
                        }
    
                        var test = network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[ new_bc ]);
                        if (typeof test.ilsevent == 'undefined') {
                            alert(offlineStrings.getFormattedString('menu.cmd_replace_barcode.duplicate.error', [new_bc]));
                            return;
                        } else {
                            if (test.ilsevent != 1502 /* ASSET_COPY_NOT_FOUND */) {
                                obj.error.standard_unexpected_error_alert(offlineStrings.getFormattedString('menu.cmd_replace_barcode.testing.error', [new_bc]),test);
                                return;
                            }    
                        }

                        copy.barcode(new_bc); copy.ischanged('1');
                        var r = network.simple_request('FM_ACP_FLESHED_BATCH_UPDATE', [ ses(), [ copy ] ]);
                        if (typeof r.ilsevent != 'undefined') { 
                            if (r.ilsevent != 0) {
                                if (r.ilsevent == 5000 /* PERM_FAILURE */) {
                                    alert(offlineStrings.getString('menu.cmd_replace_barcode.permission.error'));
                                } else {
                                    obj.error.standard_unexpected_error_alert(offlineStrings.getString('menu.cmd_replace_barcode.renaming.error'),r);
                                }
                            }
                        }
                    } catch(E) {
                        obj.error.standard_unexpected_error_alert(offlineStrings.getString('menu.cmd_replace_barcode.renaming.failure'),copy);
                    }
                }
            ],

            /* Search Menu */
            'cmd_patron_search' : [
                ['oncommand'],
                function(event) {
                    obj.set_patron_tab({},{},event);
                }
            ],
            'cmd_search_usr_id' : [
                ['oncommand'],
                function(event) {
                    var usr_id = prompt(
                        offlineStrings.getString('menu.cmd_search_usr_id.tab'),
                        '',
                        offlineStrings.getString('menu.cmd_search_usr_id.prompt')
                    );
                    if (usr_id != '' && ! isNaN(usr_id)) {
                        obj.set_patron_tab(
                            {},
                            { 'id' : usr_id },
                            event
                        );
                    }
                }
            ],
            'cmd_search_opac' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    var content_params = { 'session' : ses(), 'authtime' : ses('authtime') };
                    obj.command_tab(event,obj.url_prefix(urls.XUL_OPAC_WRAPPER), {'tab_name':offlineStrings.getString('menu.cmd_search_opac.tab')}, content_params);
                }
            ],
            'cmd_search_tcn' : [
                ['oncommand'],
                function(event) {
                    var tcn = prompt(offlineStrings.getString('menu.cmd_search_tcn.tab'),'',offlineStrings.getString('menu.cmd_search_tcn.prompt'));

                    function spawn_tcn(r,event) {
                        for (var i = 0; i < r.count; i++) {
                            var id = r.ids[i];
                            var opac_url = obj.url_prefix( urls.opac_rdetail ) + id;
                            obj.data.stash_retrieve();
                            var content_params = { 
                                'session' : ses(), 
                                'authtime' : ses('authtime'),
                                'opac_url' : opac_url,
                            };
                            if (i == 0) {
                                obj.command_tab(
                                    event,
                                    obj.url_prefix(urls.XUL_OPAC_WRAPPER), 
                                    {'tab_name':tcn}, 
                                    content_params
                                );
                            } else {
                                obj.new_tab(
                                    obj.url_prefix(urls.XUL_OPAC_WRAPPER), 
                                    {'tab_name':tcn}, 
                                    content_params
                                );
                            }
                        }
                    }

                    if (tcn) {
                        JSAN.use('util.network');
                        var network = new util.network();
                        var robj = network.simple_request('FM_BRE_ID_SEARCH_VIA_TCN',[tcn]);
                        if (robj.count != robj.ids.length) throw('FIXME -- FM_BRE_ID_SEARCH_VIA_TCN = ' + js2JSON(robj));
                        if (robj.count == 0) {
                            var robj2 = network.simple_request('FM_BRE_ID_SEARCH_VIA_TCN',[tcn,1]);
                            if (robj2.count == 0) {
                                alert(offlineStrings.getFormattedString('menu.cmd_search_tcn.not_found.error', [tcn]));
                            } else {
                                if ( window.confirm(offlineStrings.getFormattedString('menu.cmd_search_tcn.deleted.error', [tcn])) ) {
                                    spawn_tcn(robj2,event);
                                }
                            }
                        } else {
                            spawn_tcn(robj,event);
                        }
                    }
                }
            ],
            'cmd_search_bib_id' : [
                ['oncommand'],
                function(event) {
                    var bib_id = prompt(offlineStrings.getString('menu.cmd_search_bib_id.tab'),'',offlineStrings.getString('menu.cmd_search_bib_id.prompt'));
                    if (!bib_id) return;

                    var opac_url = obj.url_prefix( urls.opac_rdetail ) + bib_id;
                    var content_params = { 
                        'session' : ses(), 
                        'authtime' : ses('authtime'),
                        'opac_url' : opac_url,
                    };
                    obj.command_tab(
                        event,
                        obj.url_prefix(urls.XUL_OPAC_WRAPPER), 
                        {'tab_name':'#' + bib_id}, 
                        content_params
                    );
                }
            ],
            'cmd_copy_status' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_COPY_STATUS),{},{});
                }
            ],

            /* Circulation Menu */
            'cmd_patron_register' : [
                ['oncommand'],
                function(event) {

                    function log_registration(p) {
                        try {
                            obj.error.work_log(
                                document.getElementById('offlineStrings').getFormattedString(
                                    'staff.circ.work_log_patron_registration.message',
                                    [
                                        ses('staff_usrname'),
                                        p.family_name(),
                                        p.card().barcode()
                                    ]
                                ), {
                                    'au_id' : p.id(),
                                    'au_family_name' : p.family_name(),
                                    'au_barcode' : p.card().barcode()
                                }
                            );
                        } catch(E) {
                            obj.error.sdump('D_ERROR','Error with work_logging in menu.js, cmd_patron_register:' + E);
                        }
                    }

                    function spawn_editor(p) {
                        var url = urls.XUL_PATRON_EDIT;
                        var param_count = 0;
                        for (var i in p) {
                            if (param_count++ == 0) url += '?'; else url += '&';
                            url += i + '=' + window.escape(p[i]);
                        }
                        var loc = obj.url_prefix( urls.XUL_BROWSER ) + '?url=' + window.escape( obj.url_prefix(url) );
                        obj.new_tab(
                            loc, 
                            {}, 
                            { 
                                'show_print_button' : true , 
                                'tab_name' : offline.getString('menu.cmd_patron_register.related.tab'),
                                'passthru_content_params' : {
                                    'spawn_search' : function(s) { obj.spawn_search(s); },
                                    'spawn_editor' : spawn_editor,
                                    'on_save' : function(p) { log_registration(p); }
                                }
                            }
                        );
                    }

                    obj.data.stash_retrieve();
                    var loc = obj.url_prefix( urls.XUL_BROWSER ) 
                        + '?url=' + window.escape( obj.url_prefix(urls.XUL_PATRON_EDIT) );
                    obj.command_tab(
                        event,
                        loc, 
                        {}, 
                        { 
                            'show_print_button' : true , 
                            'tab_name' : offlineStrings.getString('menu.cmd_patron_register.tab'),
                            'passthru_content_params' : {
                                'ses' : ses(),
                                'spawn_search' : function(s) { obj.spawn_search(s); },
                                'spawn_editor' : spawn_editor,
                                'on_save' : function(p) { log_registration(p); }
                            }
                        }
                    );
                }
            ],
            'cmd_staged_patrons' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_STAGED_PATRONS),{'tab_name':offlineStrings.getString('menu.circulation.staged_patrons.tab')},{});
                }
            ],
            'cmd_circ_checkin' : [
                ['oncommand'],
                function(event) { 
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_CHECKIN),{},{});
                }
            ],
            'cmd_circ_renew' : [
                ['oncommand'],
                function(event) { 
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_RENEW),{},{});
                }
            ],
            'cmd_circ_checkout' : [
                ['oncommand'],
                function(event) { 
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_PATRON_BARCODE_ENTRY),{},{});
                }
            ],
            'cmd_circ_hold_capture' : [
                ['oncommand'],
                function(event) { 
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_CHECKIN)+'?hold_capture=1',{},{});
                }
            ],
            'cmd_browse_holds_shelf' : [
                ['oncommand'],
                function(event) { 
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_HOLDS_BROWSER)+'?shelf=1',{ 'tab_name' : offlineStrings.getString('menu.cmd_browse_holds_shelf.tab') },{});
                }
            ],
            'cmd_circ_hold_pull_list' : [
                ['oncommand'],
                function(event) { 
                    obj.data.stash_retrieve();
                    var loc = urls.XUL_BROWSER + '?url=' + window.escape(
                        obj.url_prefix(urls.XUL_HOLD_PULL_LIST)
                    );
                    obj.command_tab(event, loc, {'tab_name' : offlineStrings.getString('menu.cmd_browse_hold_pull_list.tab')} );
                }
            ],

            'cmd_in_house_use' : [
                ['oncommand'],
                function(event) { 
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_IN_HOUSE_USE),{},{});
                }
            ],

            'cmd_scan_item_as_missing_pieces' : [
                ['oncommand'],
                function() { 
                    xulG.window.open(obj.url_prefix(urls.XUL_SCAN_ITEM_AS_MISSING_PIECES),'scan_missing_pieces','chrome'); 
                }
            ],

            'cmd_standalone' : [
                ['oncommand'],
                function() { 
                    //obj.set_tab(obj.url_prefix(urls.XUL_STANDALONE),{},{});
                    window.open(urls.XUL_STANDALONE,'Offline','chrome,resizable');
                }
            ],

            'cmd_local_admin' : [
                ['oncommand'],
                function(event) { 
                    //obj.set_tab(obj.url_prefix(urls.XUL_LOCAL_ADMIN)+'?ses='+window.escape(ses())+'&session='+window.escape(ses()),{},{});
                    var loc = urls.XUL_BROWSER + '?url=' + window.escape(
                        obj.url_prefix( urls.XUL_LOCAL_ADMIN+'?ses='+window.escape(ses())+'&session='+window.escape(ses()) )
                    );
                    obj.command_tab(
                        event,
                        loc, 
                        {'tab_name' : offlineStrings.getString('menu.cmd_local_admin.tab'), 'browser' : false }, 
                        { 'no_xulG' : false, 'show_nav_buttons' : true, 'show_print_button' : true } 
                    );

                }
            ],

            'cmd_toggle_meters' : [
                ['oncommand'],
                function() {
                    var x = document.getElementById('network_progress');
                    if (x) x.hidden = ! x.hidden;
                    var y = document.getElementById('page_progress');
                    if (y) y.hidden = ! y.hidden;
                }
            ],

            'cmd_local_admin_reports' : [
                ['oncommand'],
                function(event) { 
                    var loc = urls.XUL_BROWSER + '?url=' + window.escape( obj.url_prefix(urls.XUL_REPORTS) + '?ses=' + ses());
                    obj.command_tab(
                        event,
                        loc, 
                        {'tab_name' : offlineStrings.getString('menu.cmd_local_admin_reports.tab'), 'browser' : false }, 
                        {'no_xulG' : false, 'show_print_button' : false, show_nav_buttons : true } 
                    );
                }
            ],
            'cmd_open_vandelay' : [
                ['oncommand'],
                function(event) { open_eg_web_page('vandelay/vandelay', null, event); }
            ],
            'cmd_local_admin_transit_list' : [
                ['oncommand'],
                function(event) { open_admin_page('transit_list.xul', 'menu.cmd_local_admin_transit_list.tab', false, event); }
            ],
            'cmd_local_admin_age_overdue_circulations_to_lost' : [
                ['oncommand'],
                function(event) { open_admin_page('circ_age_to_lost.xul', 'menu.cmd_local_admin_age_overdue_circulations_to_lost.tab', true, event); }
            ],
            'cmd_local_admin_cash_reports' : [
                ['oncommand'],
                function(event) { open_admin_page('cash_reports.xhtml', 'menu.cmd_local_admin_cash_reports.tab', true, event); }
            ],
            'cmd_local_admin_fonts_and_sounds' : [
                ['oncommand'],
                function(event) { open_admin_page('font_settings.xul', 'menu.cmd_local_admin_fonts_and_sounds.tab', false, event); }
            ],
            'cmd_local_admin_printer' : [
                ['oncommand'],
                function(event) { open_admin_page('printer_settings.html', 'menu.cmd_local_admin_printer.tab', true, event); }
            ],
            'cmd_local_admin_do_not_auto_attempt_print_setting' : [
                ['oncommand'],
                function(event) { 
                    obj.command_tab(event,obj.url_prefix(urls.XUL_DO_NOT_AUTO_ATTEMPT_PRINT_SETTING),{'tab_name':offlineStrings.getString('menu.cmd_local_admin_do_not_auto_attempt_print_setting.tab')},{});
                }
            ],
            'cmd_local_admin_closed_dates' : [
                ['oncommand'],
                function(event) { open_admin_page('closed_dates.xhtml', 'menu.cmd_local_admin_closed_dates.tab', true, event); }
            ],
            'cmd_local_admin_copy_locations' : [
                ['oncommand'],
                function(event) { open_admin_page('copy_locations.xhtml', 'menu.cmd_local_admin_copy_locations.tab', true, event); }
            ],
            'cmd_local_admin_lib_settings' : [
                ['oncommand'],
                function(event) { open_admin_page('org_unit_settings.xhtml', 'menu.cmd_local_admin_lib_settings.tab', true, event); }
            ],
            'cmd_local_admin_non_cat_types' : [
                ['oncommand'],
                function(event) { open_admin_page('non_cat_types.xhtml', 'menu.cmd_local_admin_non_cat_types.tab', true, event); }
            ],
            'cmd_local_admin_stat_cats' : [
                ['oncommand'],
                function(event) { open_admin_page('stat_cat_editor.xhtml', 'menu.cmd_local_admin_stat_cats.tab', true, event); }
            ],
            'cmd_local_admin_standing_penalty' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/standing_penalty', null, event); }
            ],
            'cmd_local_admin_grp_penalty_threshold' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/permission/grp_penalty_threshold', null, event); }
            ],
            'cmd_local_admin_circ_limit_set' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/circ_limit_set', null, event); }
            ],
            'cmd_server_admin_config_rule_circ_duration' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/rule_circ_duration', null, event); }
            ],
            'cmd_server_admin_config_hard_due_date' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/hard_due_date', null, event); }
            ],
            'cmd_server_admin_config_rule_recurring_fine' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/rule_recurring_fine', null, event); }
            ],
            'cmd_server_admin_config_rule_max_fine' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/rule_max_fine', null, event); }
            ],
            'cmd_server_admin_config_rule_age_hold_protect' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/rule_age_hold_protect', null, event); }
            ],
            'cmd_server_admin_config_circ_weights' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/circ_matrix_weights', null, event); }
            ],
            'cmd_server_admin_config_hold_weights' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/hold_matrix_weights', null, event); }
            ],
            'cmd_server_admin_config_weight_assoc' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/weight_assoc', null, event); }
            ],
            'cmd_server_admin_config_actor_sip_fields' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/actor_sip_fields', null, event); }
            ],
            'cmd_server_admin_config_asset_sip_fields' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/asset_sip_fields', null, event); }
            ],
            'cmd_server_admin_circ_limit_group' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/circ_limit_group', null, event); }
            ],
            'cmd_server_admin_config_usr_activity_type' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/usr_activity_type', null, event); }
            ],
            'cmd_server_admin_actor_org_unit_custom_tree' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/actor/org_unit_custom_tree', null, event); }
            ],
            'cmd_local_admin_external_text_editor' : [
                ['oncommand'],
                function() {
                    var prefs = Components.classes['@mozilla.org/preferences-service;1'].getService(Components.interfaces['nsIPrefBranch']);
                    var key = 'oils.text_editor.external.cmd';
                    var has_key = prefs.prefHasUserValue(key);
                    var value = has_key ? prefs.getCharPref(key) : 'C:\\Windows\\notepad.exe %letter.txt%';
                    var cmd = window.prompt(
                        document.getElementById('offlineStrings').getString('text_editor.prompt_for_external_cmd'),
                        value
                    );
                    if (!cmd) { return; }
                    prefs.setCharPref(key,cmd);
                }
            ],
            'cmd_local_admin_idl_field_doc' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/idl_field_doc', null, event); }
            ],
            'cmd_local_admin_action_trigger' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/action_trigger/event_definition', null, event); }
            ],
            'cmd_local_admin_survey' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/action/survey', null, event); }
            ],
            'cmd_local_admin_barcode_completion' : [
                ['oncommand'],
                function() { open_eg_web_page('conify/global/config/barcode_completion', 
                    'menu.local_admin.barcode_completion.tab'); }
            ],
            'cmd_local_admin_circ_matrix_matchpoint' : [
                ['oncommand'],
                function() { open_eg_web_page('conify/global/config/circ_matrix_matchpoint', 
                    'menu.local_admin.circ_matrix_matchpoint.tab'); }
            ],
            'cmd_local_admin_hold_matrix_matchpoint' : [
                ['oncommand'],
                function() { open_eg_web_page('conify/global/config/hold_matrix_matchpoint', 
                    'menu.local_admin.hold_matrix_matchpoint.tab'); }
            ],
            'cmd_local_admin_copy_location_order' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/asset/copy_location_order', null, event); }
            ],
            'cmd_local_admin_work_log' : [
                ['oncommand'],
                function(event) { 
                    obj.command_tab(
                        event,
                        urls.XUL_WORK_LOG,
                        { 'tab_name' : offlineStrings.getString('menu.local_admin.work_log.tab') },
                        {}
                    );
                }
            ],
            "cmd_local_admin_copy_template": [
                ["oncommand"],
                function() {
                    open_eg_web_page("conify/global/asset/copy_template");
                }
            ],
            'cmd_local_admin_patrons_due_refunds' : [
                ['oncommand'],
                function(event) {
                    obj.command_tab(
                        event,
                        obj.url_prefix(urls.XUL_PATRONS_DUE_REFUNDS),
                        { 'tab_name' : offlineStrings.getString('menu.local_admin.patrons_due_refunds.tab') },
                        {}
                    );
                }
            ],
            'cmd_server_admin_org_type' : [
                ['oncommand'],
                function(event) { open_conify_page('actor/org_unit_type', null, event); }
            ],
            'cmd_server_admin_org_unit' : [
                ['oncommand'],
                function(event) { open_conify_page('actor/org_unit', null, event); }
            ],
            'cmd_server_admin_grp_tree' : [
                ['oncommand'],
                function(event) { open_conify_page('permission/grp_tree', null, event); }
            ],
            'cmd_server_admin_perm_list' : [
                ['oncommand'],
                function(event) { open_conify_page('permission/perm_list', null, event); }
            ],
            'cmd_server_admin_copy_status' : [
                ['oncommand'],
                function(event) { open_conify_page('config/copy_status', null, event); }
            ],
            'cmd_server_admin_marc_code' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/record_attr_definition', null, event); }
            ],
            'cmd_server_admin_coded_value_map' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/coded_value_map', null, event); }
            ],
            'cmd_server_admin_metabib_field' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/metabib_field', null, event); }
            ],
            'cmd_server_admin_acn_prefix' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/acn_prefix', null, event); }
            ],
            'cmd_server_admin_acn_suffix' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/acn_suffix', null, event); }
            ],
            'cmd_server_admin_billing_type' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/billing_type', null, event); }
            ],
            'cmd_server_admin_acq_invoice_item_type' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/invoice_item_type', null, event); }
            ],
            'cmd_server_admin_acq_invoice_payment_method' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/invoice_payment_method', null, event); }
            ],
            'cmd_server_admin_acq_lineitem_alert' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/lineitem_alert', null, event); }
            ],
            'cmd_server_admin_acq_lineitem_marc_attr_def' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/lineitem_marc_attr_def', null, event); }
            ],
            'cmd_server_admin_acq_fund_tag' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/fund_tag', null, event); }
            ],
            'cmd_server_admin_acq_cancel_reason' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/cancel_reason', null, event); }
            ],
            'cmd_server_admin_acq_claim_type' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/claim_type', null, event); }
            ],
            'cmd_server_admin_acq_claim_event_type' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/claim_event_type', null, event); }
            ],
            'cmd_server_admin_acq_claim_policy' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/claim_policy', null, event); }
            ],
            'cmd_server_admin_acq_claim_policy_action' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/claim_policy_action', null, event); }
            ],
            'cmd_server_admin_acq_fund' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/fund/list', null, event); }
            ],
            'cmd_server_admin_acq_funding_source' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/funding_source/list', null, event); }
            ],
            'cmd_server_admin_acq_provider' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/provider', null, event); }
            ],
            'cmd_server_admin_acq_edi_account' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/edi_account', null, event); }
            ],
            'cmd_server_admin_acq_edi_message' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/po/edi_messages', null, event); }
            ],
            'cmd_server_admin_acq_currency_type' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/currency_type/list', null, event); }
            ],
            'cmd_server_admin_acq_exchange_rate' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/exchange_rate', null, event); }
            ],
            'cmd_server_admin_acq_distrib_formula' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/acq/distribution_formula', null, event); }
            ],
            'cmd_server_admin_sms_carrier' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/sms_carrier', null, event); }
            ],
            'cmd_server_admin_z39_source' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/z3950_source', null, event); }
            ],
            'cmd_server_admin_circ_mod' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/circ_modifier', null, event); }
            ],
            'cmd_server_admin_global_flag' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/global_flag', null, event); }
            ],
            'cmd_server_admin_org_unit_setting_type' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/org_unit_setting_type', null, event); }
            ],
            'cmd_server_admin_import_match_set' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/vandelay/match_set', null, event); }
            ],
            'cmd_server_admin_usr_setting_type' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/config/usr_setting_type', null, event); }
            ],
            'cmd_server_admin_authority_control_set': [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/cat/authority/control_set', null, event); }
            ],
            'cmd_server_admin_authority_browse_axis': [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/cat/authority/browse_axis', null, event); }
            ],
            'cmd_server_admin_authority_thesaurus': [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/cat/authority/thesaurus', null, event); }
            ],
            'cmd_server_admin_booking_resource': [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/booking/resource', null, event); }
            ],
            'cmd_server_admin_booking_resource_type': [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/booking/resource_type', null, event); }
            ],
            'cmd_server_admin_booking_resource_attr': [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/booking/resource_attr', null, event); }
            ],
            'cmd_server_admin_booking_resource_attr_value': [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/booking/resource_attr_value', null, event); }
            ],
            'cmd_server_admin_booking_resource_attr_map': [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/booking/resource_attr_map', null, event); }
            ],
            'cmd_local_admin_address_alert' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/actor/address_alert', null, event); }
            ],
            'cmd_local_admin_copy_location_group' : [
                ['oncommand'],
                function(event) { open_eg_web_page('conify/global/asset/copy_location_group', null, event); }
            ],
            'cmd_acq_create_invoice' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/invoice/view?create=1', 'menu.cmd_acq_create_invoice.tab', event); }
            ],
            'cmd_acq_view_my_pl' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/search/unified?ca=pl', 'menu.cmd_acq_unified_search.tab', event); }
            ],
            'cmd_acq_view_local_po' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/search/unified?ca=po', 'menu.cmd_acq_unified_search.tab', event); }
            ],
            'cmd_acq_create_po' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/po/create', 'menu.cmd_acq_po.tab', event); }
            ],
            'cmd_acq_view_local_inv' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/search/unified?ca=inv', 'menu.cmd_acq_unified_search.tab', event); }
            ],
            'cmd_acq_user_requests' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/picklist/user_request', 'menu.cmd_acq_user_requests.tab', event); }
            ],
            'cmd_acq_upload' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/picklist/upload', 'menu.cmd_acq_upload.tab', event); }
            ],
            'cmd_acq_bib_search' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/picklist/bib_search', 'menu.cmd_acq_bib_search.tab', event); }
            ],
            'cmd_acq_unified_search' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/search/unified', 'menu.cmd_acq_unified_search.tab', event); }
            ],
            'cmd_acq_from_bib' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/picklist/from_bib', 'menu.cmd_acq_from_bib.tab', event); }
            ],
            'cmd_acq_new_brief_record' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/picklist/brief_record', 'menu.cmd_acq_new_brief_record.tab', event); }
            ],
            'cmd_acq_claim_eligible' : [
                ['oncommand'],
                function(event) { open_eg_web_page('acq/financial/claim_eligible', 'menu.cmd_acq_claim_eligible.tab', event); }
            ],
            'cmd_booking_reservation' : [
                ['oncommand'],
                function(event) {
                    open_eg_web_page(
                        "/eg/booking/reservation",
                        "menu.cmd_booking_reservation.tab",
                        event
                    );
                }
            ],
            'cmd_booking_pull_list' : [
                ['oncommand'],
                function(event) {
                    open_eg_web_page(
                        "/eg/booking/pull_list",
                        "menu.cmd_booking_pull_list.tab",
                        event
                    );
                }
            ],
            'cmd_booking_capture' : [
                ['oncommand'],
                function(event) {
                    open_eg_web_page(
                        "/eg/booking/capture",
                        "menu.cmd_booking_capture.tab",
                        event
                    );
                }
            ],
            'cmd_booking_reservation_pickup' : [
                ['oncommand'],
                function(event) {
                    open_eg_web_page(
                        "/eg/booking/pickup",
                        "menu.cmd_booking_reservation_pickup.tab",
                        event
                    );
                }
            ],
            'cmd_booking_reservation_return' : [
                ['oncommand'],
                function(event) {
                    open_eg_web_page(
                        "/eg/booking/return",
                        "menu.cmd_booking_reservation_return.tab",
                        event
                    );
                }
            ],
            'cmd_reprint' : [
                ['oncommand'],
                function() {
                    try {
                        JSAN.use('util.print'); var print = new util.print();
                        print.reprint_last();
                    } catch(E) {
                        alert(E);
                    }
                }
            ],

            'cmd_retrieve_last_patron' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    if (!obj.data.last_patron) {
                        alert(offlineStrings.getString('menu.cmd_retrieve_last_patron.session.error'));
                        return;
                    }
                    var horizontal_interface = String( obj.data.hash.aous['ui.circ.patron_summary.horizontal'] ) == 'true';
                    var url = obj.url_prefix( horizontal_interface ? urls.XUL_PATRON_HORIZ_DISPLAY : urls.XUL_PATRON_DISPLAY );
                    obj.command_tab( event, url, {}, { 'id' : obj.data.last_patron } );
                }
            ],
            
            'cmd_retrieve_last_record' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    if (!obj.data.last_record) {
                        alert(offlineStrings.getString('menu.cmd_retrieve_last_record.session.error'));
                        return;
                    }
                    var opac_url = obj.url_prefix( urls.opac_rdetail ) + obj.data.last_record;
                    var content_params = {
                        'session' : ses(),
                        'authtime' : ses('authtime'),
                        'opac_url' : opac_url,
                    };
                    obj.command_tab(
                        event,
                        obj.url_prefix(urls.XUL_OPAC_WRAPPER),
                        {'tab_name' : offlineStrings.getString('menu.cmd_retrieve_last_record.status')},
                        content_params
                    );
                }
            ],

            'cmd_verify_credentials' : [
                ['oncommand'],
                function(event) {
                    obj.command_tab(
                        event,
                        obj.url_prefix(urls.XUL_VERIFY_CREDENTIALS),
                        { 'tab_name' : offlineStrings.getString('menu.cmd_verify_credentials.tabname') },
                        {}
                    );
                }
            ],

            /* Cataloging Menu */
            'cmd_z39_50_import' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_Z3950_IMPORT),{},{});
                }
            ],
            'cmd_create_marc' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_MARC_NEW),{},{});
                }
            ],

            'cmd_authority_manage' : [
                ['oncommand'],
                function(event) {
                    open_eg_web_page(
                        urls.AUTHORITY_MANAGE,
                        "menu.cmd_authority_manage.tab",
                        event
                    );
                }
            ],

            'cmd_marc_batch_edit' : [
                ['oncommand'],
                function(event) {
                    obj.command_tab(
                        event,
                        obj.url_prefix(urls.MARC_BATCH_EDIT),{
                            'tab_name' : offlineStrings.getString('menu.cmd_marc_batch_edit.tab')
                        },
                        {}
                    );
                }
            ],

            /* Admin menu */
            'cmd_change_session' : [
                ['oncommand'],
                function() {
                    try {
                        obj.data.stash_retrieve();
                        JSAN.use('util.network'); var network = new util.network();
                        var temp_au = js2JSON( obj.data.list.au[0] );
                        var temp_ses = js2JSON( obj.data.session );
                        if (obj.data.list.au.length > 1) {
                            obj.data.list.au = [ obj.data.list.au[1] ];
                            obj.data.stash('list');
                            network.reset_titlebars( obj.data );
                            network.simple_request('AUTH_DELETE', [ obj.data.session.key ] );
                            obj.data.session = obj.data.previous_session;
                            obj.data.menu_perms = obj.data.previous_menu_perms;
                            obj.data.stash('session');
                            obj.data.stash('menu_perms');
                            try {
                                netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
                                var ios = Components.classes["@mozilla.org/network/io-service;1"].getService(Components.interfaces.nsIIOService);
                                var cookieUri = ios.newURI("http://" + obj.data.server_unadorned, null, null);
                                var cookieUriSSL = ios.newURI("https://" + obj.data.server_unadorned, null, null);
                                var cookieSvc = Components.classes["@mozilla.org/cookieService;1"].getService(Components.interfaces.nsICookieService);

                                cookieSvc.setCookieString(cookieUri, null, "ses="+obj.data.session.key, null);
                                cookieSvc.setCookieString(cookieUriSSL, null, "ses="+obj.data.session.key, null);

                        } catch(E) {
                            alert(offlineStrings.getFormattedString(main.session_cookie.error, [E]));
                        }

                        } else {
                            if (network.get_new_session(offlineStrings.getString('menu.cmd_chg_session.label'),{'url_prefix':obj.url_prefix})) {
                                obj.data.stash_retrieve();
                                obj.data.list.au[1] = JSON2js( temp_au );
                                obj.data.stash('list');
                                obj.data.previous_session = JSON2js( temp_ses );
                                obj.data.previous_menu_perms = obj.data.menu_perms;
                                obj.data.menu_perms = false;
                                obj.data.stash('previous_session');
                                obj.data.stash('previous_menu_perms');
                                obj.data.stash('menu_perms');
                            }
                        }
                        network.set_user_status();
                    } catch(E) {
                        obj.error.standard_unexpected_error_alert('cmd_change_session',E);
                    }
                }
            ],
            'cmd_manage_offline_xacts' : [
                ['oncommand'],
                function(event) {
                    obj.command_tab(event,obj.url_prefix(urls.XUL_OFFLINE_MANAGE_XACTS), {'tab_name' : offlineStrings.getString('menu.cmd_manage_offline_xacts.tab')}, {});
                }
            ],
            'cmd_download_patrons' : [
                ['oncommand'],
                function() {
                    try {
                        netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
                        var x = new XMLHttpRequest();
                        var url = 'http://' + XML_HTTP_SERVER + '/standalone/list.txt';
                        x.open("GET",url,false);
                        x.send(null);
                        if (x.status == 200) {
                            JSAN.use('util.file'); var file = new util.file('offline_patron_list');
                            file.write_content('truncate',x.responseText);
                            file.close();
                            file = new util.file('offline_patron_list.date');
                            file.write_content('truncate',new Date());
                            file.close();
                            alert(offlineStrings.getString('menu.cmd_download_patrons.complete.status'));
                        } else {
                            alert(offlineStrings.getFormattedString('menu.cmd_download_patrons.error', [x.status, x.statusText]));
                        }
                    } catch(E) {
                        obj.error.standard_unexpected_error_alert('cmd_download_patrons',E);
                    }
                }
            ],
            'cmd_adv_user_edit' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_PATRON_BARCODE_ENTRY), {}, { 'perm_editor' : true });
                }
            ],
            'cmd_print_list_template_edit' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_PRINT_LIST_TEMPLATE_EDITOR), {}, {});
                }
            ],
            'cmd_stat_cat_edit' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_STAT_CAT_EDIT) + '?ses='+window.escape(ses()), {'tab_name' : offlineStrings.getString('menu.cmd_stat_cat_edit.tab')},{});
                }
            ],
            'cmd_non_cat_type_edit' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_NON_CAT_LABEL_EDIT) + '?ses='+window.escape(ses()), {'tab_name' : offlineStrings.getString('menu.cmd_non_cat_type_edit.tab')},{});
                }
            ],
            'cmd_copy_location_edit' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.XUL_COPY_LOCATION_EDIT) + '?ses='+window.escape(ses()),{'tab_name' : offlineStrings.getString('menu.cmd_copy_location_edit.tab')},{});
                }
            ],
            'cmd_test' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    var content_params = { 'session' : ses(), 'authtime' : ses('authtime') };
                    obj.command_tab(event,obj.url_prefix(urls.XUL_OPAC_WRAPPER), {}, content_params);
                }
            ],
            'cmd_test_html' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.TEST_HTML) + '?ses='+window.escape(ses()),{ 'browser' : true },{});
                }
            ],
            'cmd_test_xul' : [
                ['oncommand'],
                function(event) {
                    obj.data.stash_retrieve();
                    obj.command_tab(event,obj.url_prefix(urls.TEST_XUL) + '?ses='+window.escape(ses()),{ 'browser' : false },{});
                }
            ],
            'cmd_console' : [
                ['oncommand'],
                function(event) {
                    obj.command_tab(event,obj.url_prefix(urls.XUL_DEBUG_CONSOLE),{'tab_name' : offlineStrings.getString('menu.cmd_console.tab')},{});
                }
            ],
            'cmd_shell' : [
                ['oncommand'],
                function(event) {
                    obj.command_tab(event,obj.url_prefix(urls.XUL_DEBUG_SHELL),{'tab_name' : offlineStrings.getString('menu.cmd_shell.tab')},{});
                }
            ],
            'cmd_xuleditor' : [
                ['oncommand'],
                function(event) {
                    obj.command_tab(event,obj.url_prefix(urls.XUL_DEBUG_XULEDITOR),{'tab_name' : offlineStrings.getString('menu.cmd_xuleditor.tab')},{});
                }
            ],
            'cmd_fieldmapper' : [
                ['oncommand'],
                function(event) {
                    obj.command_tab(event,obj.url_prefix(urls.XUL_DEBUG_FIELDMAPPER),{'tab_name' : offlineStrings.getString('menu.cmd_fieldmapper.tab')},{});
                }
            ],
            'cmd_survey_wizard' : [
                ['oncommand'],
                function() {
                    obj.data.stash_retrieve();
                    xulG.window.open(obj.url_prefix(urls.XUL_SURVEY_WIZARD),'survey_wizard','chrome'); 
                }
            ],
            'cmd_public_opac' : [
                ['oncommand'],
                function(event) {
                    var loc = urls.XUL_BROWSER + '?url=' + window.escape(
                        obj.url_prefix(urls.remote)
                    );
                    obj.command_tab(
                        event,
                        loc, 
                        {'tab_name' : offlineStrings.getString('menu.cmd_public_opac.tab'), 'browser' : false}, 
                        { 'no_xulG' : true, 'show_nav_buttons' : true, 'show_print_button' : true } 
                    );
                }
            ],
            'cmd_clear_cache' : [
                ['oncommand'],
                function clear_the_cache() {
                    try {
                        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
                        var cacheClass         = Components.classes["@mozilla.org/network/cache-service;1"];
                        var cacheService    = cacheClass.getService(Components.interfaces.nsICacheService);
                        cacheService.evictEntries(Components.interfaces.nsICache.STORE_ON_DISK);
                        cacheService.evictEntries(Components.interfaces.nsICache.STORE_IN_MEMORY);
                    } catch(E) {
                        dump(E+'\n');alert(E);
                    }
                }
            ],
            'cmd_restore_all_tabs' : [
                ['oncommand'],
                function() {
                    var tabs = obj.controller.view.tabs;
                    for (var i = 0; i < tabs.childNodes.length; i++) {
                        tabs.childNodes[i].hidden = false;
                    }
                }
            ],
            'cmd_extension_manager' : [
                ['oncommand'],
                function(event) {
                    obj.command_tab(event,'chrome://mozapps/content/extensions/extensions.xul?type=extensions',{'tab_name' : offlineStrings.getString('menu.cmd_extension_manager.tab')},{});
                }
            ],
            'cmd_theme_manager' : [
                ['oncommand'],
                function(event) {
                    obj.command_tab(event,'chrome://mozapps/content/extensions/extensions.xul?type=themes',{'tab_name' : offlineStrings.getString('menu.cmd_theme_manager.tab')},{});
                }
            ],
            'cmd_about_config' : [
                ['oncommand'],
                function(event) {
                    obj.command_tab(event,'chrome://global/content/config.xul',{'tab_name' : 'about:config'},{});
                }
            ],
            'cmd_shutdown' : [
                ['oncommand'],
                function() {
                    var confirm_string = offlineStrings.getString('menu.cmd_shutdown.prompt');
                    obj.data.stash_retrieve();
                    if (typeof obj.data.unsaved_data != 'undefined') {
                        if (obj.data.unsaved_data > 0) {
                            confirm_string = offlineStrings.getString('menu.shutdown.unsaved_data_warning');
                        }
                    }
                    if (window.confirm(confirm_string)) {
                        obj.data.unsaved_data = 0; // just in case the program doesn't close somehow
                        obj.data.stash('unsaved_data');
                        dump('forcing data.unsaved_data == ' + obj.data.unsaved_data + '\n');
                        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
                        var windowManager = Components.classes["@mozilla.org/appshell/window-mediator;1"].getService();
                        var windowManagerInterface = windowManager.QueryInterface(Components.interfaces.nsIWindowMediator);
                        var enumerator = windowManagerInterface.getEnumerator(null);
                        var w; // close all other windows
                        while ( w = enumerator.getNext() ) {
                            if (w != window) {
                                if (w.xulG) { w.close(); } // FIXME: kludge so we don't close Firefox windows as an extension.  We should define a @windowtype for all the staff client windows and have the enumerator just pull those
                            }
                        }
                        window.close();
                    }
                }
            ],
            'cmd_hotkeys_toggle' : [
                ['oncommand'],
                function() {
                    // Easy enough, toggle disabled on the keyset
                    var keyset = document.getElementById("menu_frame_keys");
                    var disabled = (keyset.getAttribute("disabled") == "true") ? "false" : "true";
                    if(disabled == "true")
                        keyset.setAttribute("disabled", "true");
                    else
                        keyset.removeAttribute("disabled");
                    // Then find every menuitem/toolbarbutton for this command for a graphical hint
                    var controls = document.getElementsByAttribute("command","cmd_hotkeys_toggle");
                    for(var i = 0; i < controls.length; i++)
                        controls[i].setAttribute("checked",disabled);
                }
            ],
            'cmd_hotkeys_set' : [
                ['oncommand'],
                function(event) {
                    obj.set_menu_hotkeys(event.explicitOriginalTarget.getAttribute('value'));
                }
            ],
            'cmd_hotkeys_setworkstation' : [
                ['oncommand'],
                function() {
                    xulG.pref.setCharPref('open-ils.menu.hotkeyset', obj.data.current_hotkeyset);
                }
            ],
            'cmd_hotkeys_clearworkstation' : [
                ['oncommand'],
                function() {
                    if(xulG.pref.prefHasUserValue('open-ils.menu.hotkeyset'))
                        xulG.pref.clearUserPref('open-ils.menu.hotkeyset');
                }
            ],
            'cmd_toolbar_set' : [
                ['oncommand'],
                function(event) {
                    var newToolbar = event.explicitOriginalTarget.getAttribute('value');
                    obj.render_toolbar(newToolbar);
                    obj.toolbar = newToolbar;
                }
            ],
            'cmd_toolbar_mode_set' : [
                ['oncommand'],
                function(event) {
                    var newMode = event.explicitOriginalTarget.getAttribute('value');
                    var toolbox = document.getElementById('main_toolbox');
                    var toolbars = toolbox.getElementsByTagName('toolbar');
                    for(var i = 0; i < toolbars.length; i++)
                        toolbars[i].setAttribute("mode",newMode);
                    obj.toolbar_mode = newMode;
                }
            ],
            'cmd_toolbar_size_set' : [
                ['oncommand'],
                function(event) {
                    var newSize = event.explicitOriginalTarget.getAttribute('value');
                    var toolbox = document.getElementById('main_toolbox');
                    var toolbars = toolbox.getElementsByTagName('toolbar');
                    for(var i = 0; i < toolbars.length; i++)
                        toolbars[i].setAttribute("iconsize",newSize);
                    obj.toolbar_size = newSize;
                }
            ],
            'cmd_toolbar_label_position_set' : [
                ['oncommand'],
                function(event) {
                    var altPosition = (event.explicitOriginalTarget.getAttribute('value') == "under");
                    var toolbox = document.getElementById('main_toolbox');
                    var toolbars = toolbox.getElementsByTagName('toolbar');
                    for(var i = 0; i < toolbars.length; i++) {
                        if(altPosition)
                            addCSSClass(toolbars[i], 'labelbelow');
                        else
                            removeCSSClass(toolbars[i], 'labelbelow');
                    }
                    obj.toolbar_labelpos = (altPosition ? "under" : "side");
                }
            ],
            'cmd_toolbar_configure' : [
                ['oncommand'],
                function(event) {
                    var url = obj.url_prefix( urls.XUL_TOOLBAR_CONFIG ); 
                    obj.command_tab(event,url,{},{});
                }
            ],
            'cmd_toolbar_setworkstation' : [
                ['oncommand'],
                function() {
                xulG.pref.setCharPref('open-ils.menu.toolbar', obj.toolbar);
                xulG.pref.setCharPref('open-ils.menu.toolbar.iconsize', obj.toolbar_size);
                xulG.pref.setCharPref('open-ils.menu.toolbar.mode', obj.toolbar_mode);
                xulG.pref.setBoolPref('open-ils.menu.toolbar.labelbelow', (obj.toolbar_labelpos == "under"));
                }
            ],
            'cmd_toolbar_clearworkstation' : [
                ['oncommand'],
                function() {
                    if(xulG.pref.prefHasUserValue('open-ils.menu.toolbar'))
                        xulG.pref.clearUserPref('open-ils.menu.toolbar');
                    if(xulG.pref.prefHasUserValue('open-ils.menu.toolbar.iconsize'))
                        xulG.pref.clearUserPref('open-ils.menu.toolbar.iconsize');
                    if(xulG.pref.prefHasUserValue('open-ils.menu.toolbar.mode'))
                        xulG.pref.clearUserPref('open-ils.menu.toolbar.mode');
                    if(xulG.pref.prefHasUserValue('open-ils.menu.toolbar.labelbelow'))
                        xulG.pref.clearUserPref('open-ils.menu.toolbar.labelbelow');
                }
            ],
            'cmd_debug_venkman' : [
                ['oncommand'],
                function() {
                    try{
                        xulG.window.win.start_debugger();
                    } catch(E) {
                        alert(E);
                    }
                }
            ],
            'cmd_debug_inspector' : [
                ['oncommand'],
                function() {
                    try{
                        xulG.window.win.start_inspector();
                    } catch(E) {
                        alert(E);
                    }
                }
            ],
            'cmd_debug_chrome_list' : [
                ['oncommand'],
                function() {
                    try{
                        xulG.window.win.start_chrome_list();
                    } catch(E) {
                        alert(E);
                    }
                }
            ],
            'cmd_debug_chrome_shell' : [
                ['oncommand'],
                function() {
                    try{
                        xulG.window.win.start_js_shell();
                    } catch(E) {
                        alert(E)
                    }
                }
            ],
            'cmd_copy_editor_copy_location_first_toggle' : [
                ['oncommand'],
                function() {
                    var curvalue = xulG.pref.getBoolPref('oils.copy_editor.copy_location_name_first');
                    xulG.pref.setBoolPref('oils.copy_editor.copy_location_name_first', !curvalue);
                }
            ],
        };

        JSAN.use('util.controller');
        var cmd;
        obj.controller = new util.controller();
        obj.controller.init( { 'window_knows_me_by' : 'g.menu.controller', 'control_map' : cmd_map } );

        obj.controller.view.tabbox = window.document.getElementById('main_tabbox');
        // Despite what the docs say:
        // The "tabs" element need not be the first child
        // The "panels" element need not be the second/last
        // Nor need they be the only ones there.
        // Thus, use the IDs for robustness.
        obj.controller.view.tabs = window.document.getElementById('main_tabs');
        obj.controller.view.panels = window.document.getElementById('main_panels');
        obj.controller.view.tabscroller = window.document.getElementById('main_tabs_scrollbox');

        obj.sort_menu(document.getElementById('main.menu.admin'), true);

        if(params['firstURL']) {
            obj.new_tab(params['firstURL'],{'focus':true},null);
        }
        else {
            obj.new_tab(null,{'focus':true},null);
        }
    },

    'button_bar_init' : function() {
        try {

            var obj = this;

            JSAN.use('util.widgets');

            // populate the menu of available toolbars
            var x = document.getElementById('main.menu.admin.client.toolbars.current.popup');
            if (x) {
                util.widgets.remove_children(x);

                function create_menuitem(label,value,checked) {
                    var menuitem = document.createElement('menuitem');
                        menuitem.setAttribute('name','current_toolbar');
                        menuitem.setAttribute('type','radio');
                        menuitem.setAttribute('label',label);
                        menuitem.setAttribute('value',value);
                        menuitem.setAttribute('command','cmd_toolbar_set');
                        if (checked) menuitem.setAttribute('checked','true');
                    return menuitem;
                }

                x.appendChild(
                    create_menuitem(
                        offlineStrings.getString('staff.main.button_bar.none'),
                        'none',
                        true
                    )
                );

                for (var i = 0; i < this.data.list.atb.length; i++) {
                    var def = this.data.list.atb[i];
                    x.appendChild(
                        create_menuitem(
                            def.label(),
                            def.id()
                        )
                    );
                }
            }

            // Try workstation pref for button bar
            var button_bar = xulG.pref.getCharPref('open-ils.menu.toolbar');

            if (!button_bar) { // No workstation pref? Try org unit pref.
                if (obj.data.hash.aous['ui.general.button_bar']) {
                    button_bar = String( obj.data.hash.aous['ui.general.button_bar'] );
                }
            }

            if (button_bar) {
                this.render_toolbar(button_bar);
                this.toolbar = button_bar;
            }

            // Check for alternate Size pref
            var toolbar_size = xulG.pref.getCharPref('open-ils.menu.toolbar.iconsize');
            if(toolbar_size) this.toolbar_size = toolbar_size;
            // Check for alternate Mode pref
            var toolbar_mode = xulG.pref.getCharPref('open-ils.menu.toolbar.mode');
            if(toolbar_mode) this.toolbar_mode = toolbar_mode;
            // Check for alternate Label Position pref
            var toolbar_labelpos = xulG.pref.getBoolPref('open-ils.menu.toolbar.labelbelow');
            if(toolbar_labelpos) this.toolbar_labelpos = toolbar_labelpos;

            if(button_bar || toolbar_size || toolbar_mode || toolbar_labelpos) {
                var toolbar = document.getElementById('toolbar_main');
                if(toolbar_mode) toolbar.setAttribute('mode', toolbar_mode);
                if(toolbar_size) toolbar.setAttribute('iconsize', toolbar_size);
                if(toolbar_labelpos) addCSSClass(toolbar, 'labelbelow');
            }

            if(button_bar) {
                var x = document.getElementById('main.menu.admin.client.toolbars.current.popup');
                if (x) {
                    var selectitems = x.getElementsByAttribute('value',button_bar);
                    if(selectitems.length > 0) selectitems[0].setAttribute('checked','true');
                }
            }

            if(toolbar_size) {
                var x = document.getElementById('main.menu.admin.client.toolbars.size.popup');
                if (x) {
                    var selectitems = x.getElementsByAttribute('value',toolbar_size);
                    if(selectitems.length > 0) selectitems[0].setAttribute('checked','true');
                }
            }

            if(toolbar_mode) {
                var x = document.getElementById('main.menu.admin.client.toolbars.mode.popup');
                if (x) {
                    var selectitems = x.getElementsByAttribute('value',toolbar_mode);
                    if(selectitems.length > 0) selectitems[0].setAttribute('checked','true');
                }
            }

            if(toolbar_labelpos) {
                var x = document.getElementById('main.menu.admin.client.toolbars.label_position.popup');
                if (x) {
                    var selectitems = x.getElementsByAttribute('value',"under");
                    if(selectitems.length > 0) selectitems[0].setAttribute('checked','true');
                }
            }

            // stash the available toolbar buttons for later use in the toolbar editing interface
            if (typeof this.data.toolbar_buttons == 'undefined') {
                this.data.toolbar_buttons = {};
                var nl = $('palette').childNodes;
                for (var i = 0; i < nl.length; i++) {
                    var id = nl[i].getAttribute('templateid');
                    var label = nl[i].getAttribute('label');
                    if (id && label) {
                        this.data.toolbar_buttons[ id ] = label;
                    }
                }
                this.data.stash('toolbar_buttons');
            }

        } catch(E) {
            alert('Error in menu.js, button_bar_init(): ' + E);
        }
    },

    'spawn_search' : function(s) {
        var obj = this;
        obj.error.sdump('D_TRACE', offlineStrings.getFormattedString('menu.spawn_search.msg', [js2JSON(s)]) ); 
        obj.new_patron_tab( {}, { 'doit' : 1, 'query' : js2JSON(s) } );
    },

    'close_all_tabs' : function() {
        var obj = this;
        try {
            var count = obj.controller.view.tabs.childNodes.length;
            for (var i = 1; i < count; i++) obj.close_tab();
            setTimeout( function(){ obj.controller.view.tabs.firstChild.focus(); }, 0);
        } catch(E) {
            obj.error.standard_unexpected_error_alert(offlineStrings.getString('menu.close_all_tabs.error'),E);
        }
    },

    'close_tab' : function (specific_idx) {
        var idx = specific_idx || this.controller.view.tabs.selectedIndex;
        var panel = this.controller.view.panels.childNodes[ idx ];

        var tab = this.controller.view.tabs.getItemAtIndex( idx );
        var id = tab.getAttribute('id');
        if (typeof this.tab_semaphores[id] != 'undefined') {
            if (this.tab_semaphores[id] > 0) {
                var confirmation = window.confirm(offlineStrings.getString('menu.close_tab.unsaved_data_warning'));
                if (!confirmation) { return; }
                oils_unsaved_data_P( this.tab_semaphores[id] );
            }
            delete this.tab_semaphores[id];
        }

        this.controller.view.tabs.removeItemAt(idx);
        this.controller.view.panels.removeChild(panel);
        if(this.controller.view.tabs.childNodes.length > idx) {
            this.controller.view.tabbox.selectedIndex = idx;
        }
        else {
            this.controller.view.tabbox.selectedIndex = idx - 1;
        }
        this.controller.view.tabscroller.ensureElementIsVisible(this.controller.view.tabs.selectedItem);
        this.update_all_tab_names();
        // Make sure we keep at least one tab open.
        if(this.controller.view.tabs.childNodes.length == 1) {
            this.new_tab(); 
        }
    },
    
    'update_all_tab_names' : function() {
        var doAccessKeys = !xulG.pref.getBoolPref('open-ils.disable_accesskeys_on_tabs');
        for(var i = 1; i < this.controller.view.tabs.childNodes.length; ++i) {
            var tab = this.controller.view.tabs.childNodes[i];
            tab.curindex = i;
            tab.label = i + ' ' + tab.origlabel;
            if(doAccessKeys && offlineStrings.testString('menu.tab' + i + '.accesskey')) {
                tab.accessKey = offlineStrings.getString('menu.tab' + i + '.accesskey');
            }
        }
    },

    'command_tab' : function(event,url,params,content_params) {
        var newTab = false;
        var myEvent = event;
        if(event && event.sourceEvent) myEvent = event.sourceEvent;
        // Note: The last event is not supposed to be myEvent in this if.
        if(myEvent && myEvent.explicitOriginalTarget.nodeName.match(/toolbarbutton/) && myEvent.explicitOriginalTarget.command == event.originalTarget.id) {
            var value = xulG.pref.getIntPref('ui.key.accelKey');
            switch(value) {
                case 17:
                    newTab = myEvent.ctrlKey;
                    break;
                case 18:
                    newTab = myEvent.altKey;
                    break;
                case 224:
                    newTab = myEvent.metaKey;
                    break;
            }
            try {
                if(xulG.pref.getBoolPref('open-ils.toolbar.defaultnewtab')) {
                    newTab = !newTab;
                }
            }
            catch (e) {
            }
        }
        if(newTab) {
            this.new_tab(url,params,content_params);
        }
        else {
            this.set_tab(url,params,content_params);
        }
    },

    'new_tab' : function(url,params,content_params) {
        var obj = this;
        var max_tabs = 0;
        try {
            var max_tabs = xulG.pref.getIntPref('open-ils.window_max_tabs') || max_tabs;
        }
        catch (e) {}
        if(max_tabs > 0 && this.controller.view.tabs.childNodes.length > max_tabs) return false;
        var tab = this.w.document.createElement('tab');
        var panel = this.w.document.createElement('tabpanel');
        var tabscroller = this.controller.view.tabscroller;
        this.controller.view.tabs.appendChild(tab);
        this.controller.view.panels.appendChild(panel);
        tab.curindex = this.controller.view.tabs.childNodes.length - 1;
        if(!xulG.pref.getBoolPref('open-ils.disable_accesskeys_on_tabs')) {
            if(offlineStrings.testString('menu.tab' + tab.curindex + '.accesskey')) {
                tab.accessKey = offlineStrings.getString('menu.tab' + tab.curindex + '.accesskey');
            }
        }
        var tabs = this.controller.view.tabs;
        tab.addEventListener(
            'command',
            function() {
                try {
                    tabscroller.ensureElementIsVisible(tab);
                    netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
                    if (panel
                        && panel.firstChild 
                        && ( panel.firstChild.nodeName == 'iframe' || panel.firstChild.nodeName == 'browser' )
                        && panel.firstChild.contentWindow 
                    ) {
                        var cw = panel.firstChild.contentWindow;
                        var help_params = {
                            'protocol' : cw.location.protocol,
                            'hostname' : cw.location.hostname,
                            'port' : cw.location.port,
                            'pathname' : cw.location.pathname,
                            'src' : ''
                        };
                        obj.set_help_context(help_params);
                        if (typeof cw.default_focus == 'function') {
                            cw.default_focus();
                        }
                    }
                } catch(E) {
                    obj.error.sdump('D_ERROR','init_tab_focus_handler: ' + js2JSON(E));
                }
            }
            ,
            false
        );
        if (!content_params) content_params = {};
        if (!params) params = {};
        if (!params.tab_name) params.tab_name = offlineStrings.getString('menu.new_tab.tab');
        if (!params.nofocus) params.focus = true; /* make focus the default */
        try {
            if (params.focus) {
                this.controller.view.tabs.selectedItem = tab;
                tabscroller.ensureElementIsVisible(tab);
            }
            params.index = tab.curindex;
            this.set_tab(url,params,content_params);
            return true;
        } catch(E) {
            this.error.sdump('D_ERROR',E);
            return false;
        }
    },

    'set_menu_access' : function(perms) {
        if(perms === false) return;
        var commands = document.getElementById('universal_cmds').getElementsByTagName('command');
        var commandperms;
commands:
        for (var i = 0; i < commands.length; i++) { 
            if (commands[i].hasAttribute('perm')) {
                commandperms = commands[i].getAttribute('perm').split(' ');
                for (var j = 0; j < commandperms.length; j++) {
                    if (perms[commandperms[j]]) {
                        commands[i].setAttribute('disabled','false');
                        continue commands;
                    }
                }
                commands[i].setAttribute('disabled','true');
            }           
        }

    },

    'set_menu_hotkeys' : function(hotkeyset) {
        this.data.stash_retrieve();

        var wm = Components.classes["@mozilla.org/appshell/window-mediator;1"].
                    getService(Components.interfaces.nsIWindowMediator);
        var mainwin = wm.getMostRecentWindow('eg_main');
        JSAN.use('util.network');
        var network = new util.network();

        if(hotkeyset) { // Explicit request
            // Store
            this.data.current_hotkeyset = hotkeyset;
            this.data.stash('current_hotkeyset');
            // Then iterate over windows
            var windowManager = Components.classes["@mozilla.org/appshell/window-mediator;1"].getService();
            var windowManagerInterface = windowManager.QueryInterface(Components.interfaces.nsIWindowMediator);
            var enumerator = windowManagerInterface.getEnumerator('eg_menu');

            var w;
            while ( w = enumerator.getNext() ) {
                if ( w != window )
                    w.g.menu.set_menu_hotkeys();
            }
        }
        else { // Non-explicit request?
            if(this.data.current_hotkeyset) // Previous hotkeyset?
                hotkeyset = this.data.current_hotkeyset; // Use it
            else { // No previous? We need to decide on one!
                // Load the list so we know if what we are being asked to load is valid.
                var hotkeysets = mainwin.load_hotkey_sets();
                if(!hotkeysets) return; // No sets = nothing to load. Which is probably an error, but meh.
                hotkeysets.has = function(test) {
                    for(i = 0; i < this.length; i++) {
                        if(this[i] == test) return true;
                    }
                    return false;
                }; 
                // Try workstation (pref)
                hotkeyset = xulG.pref.getCharPref('open-ils.menu.hotkeyset');

                // Nothing or nothing valid?
                if(!hotkeyset || !hotkeysets.has(hotkeyset)) {
                    hotkeyset = this.data.hash.aous['ui.general.hotkeyset'];
                }
                // STILL nothing? Try Default.
                if(!hotkeyset || !hotkeysets.has(hotkeyset)) {
                    if(hotkeysets.has('Default'))
                        hotkeyset = 'Default';
                    else
                        return false;
                }
                // And save whatever we are using.
                this.data.current_hotkeyset = hotkeyset;
                this.data.stash('current_hotkeyset');
            }
        }
        // Clear out all the old hotkeys
        var keyset = document.getElementById('menu_frame_keys');
        var main_menu = document.getElementById('main_menubar');
        if(keyset.hasChildNodes()) {
            var menuitems = main_menu.getElementsByAttribute('key','*');
            while(menuitems.length > 0) {
                var menuitem = menuitems[0];
                menuitem.removeAttribute('key');
                // Trick/force mozilla to re-evaluate the menuitem
                // If you want to take this trick for use *anywhere* in *any* project, regardless of licensing, please do
                // Because it was a PITA to figure out
                menuitem.style.display = 'none'; // Hide the item to force menu to clear spot
                menuitem.setAttribute('acceltext', ''); // Set acceltext to blank string outright
                menuitem.removeAttribute('acceltext'); // Remove acceltext to clear out hotkey hint text
                menuitem.parentNode.openPopupAtScreen(0,0,false); // Tell menupopup to redraw itself
                menuitem.parentNode.hidePopup(); // And then make it go away right away.
                menuitem.style.removeProperty('display'); // Restore normal css display
            }
            while(keyset.hasChildNodes()) keyset.removeChild(keyset.childNodes[0]);
        }
        keyset_lines = mainwin.get_hotkey_array(hotkeyset);
        // Next, fill the keyset
        for(var line = 0; line < keyset_lines.length; line++) {
            // Create and populate our <key>
            var key_node = document.createElement('key');
            key_node.setAttribute('id',keyset_lines[line][0] + "_key");
            key_node.setAttribute('command',keyset_lines[line][0]);
            key_node.setAttribute('modifiers',keyset_lines[line][1]);
            // If keycode starts with VK_ we assume it is a key code.
            // Key codes go in the keycode attribute
            // Regular keys (like "i") go in the key attribute
            if(keyset_lines[line][2].match(/^VK_/))
                key_node.setAttribute('keycode',keyset_lines[line][2]);
            else
                key_node.setAttribute('key',keyset_lines[line][2]);
            // If a fourth option was specified, set keytext to it.
            if(keyset_lines[line][3])
                key_node.setAttribute('keytext',keyset_lines[line][3]);
            // Add the new node to the DOM
            keyset.appendChild(key_node);
            // And populate all the menu items that should now display it
            var menuitems = main_menu.getElementsByAttribute('command',keyset_lines[line][0]);
            for(var i = 0; i < menuitems.length; i++) {
                menuitems[i].setAttribute('key', keyset_lines[line][0] + "_key");
                // Trick/force mozilla to re-evaluate the menuitem
                menuitems[i].style.display = 'none'; // Hide the item to force menu to clear spot
                menuitems[i].parentNode.openPopupAtScreen(0,0,false); // Tell menupopup to redraw itself
                menuitems[i].parentNode.hidePopup(); // And then make it go away right away
                menuitems[i].style.removeProperty('display'); // Restore normal css display
            }
        }
        // Force reload of keyset cache?
        keyset.parentNode.insertBefore(keyset, keyset.nextSibling);
        // If no keys, disable ability to toggle hotkeys (because why bother?)
        var x = document.getElementById('cmd_hotkeys_toggle');
        if(x) {
            if(keyset.hasChildNodes())
                x.removeAttribute('disabled');
            else
                x.setAttribute('disabled', 'true');
        }
        // Select the hotkey set in the menu
        // This ensures that first window load OR remote window update shows properly
        var hotkeylist = document.getElementById('main.menu.admin.client.hotkeys.current.popup');
        var selectitems = hotkeylist.getElementsByAttribute('value',hotkeyset);
        if(selectitems.length > 0) selectitems[0].setAttribute('checked','true');
    },

    'page_meter' : {
        'node' : document.getElementById('page_progress'),
        'on' : function() {
            document.getElementById('page_progress').setAttribute('mode','undetermined');
        },
        'off' : function() {
            document.getElementById('page_progress').setAttribute('mode','determined');
        },
        'tooltip' : function(text) {
            if (text || text == '') {
                document.getElementById('page_progress').setAttribute('tooltiptext',text);
            }
            return document.getElementById('page_progress').getAttribute('tooltiptext');
        }
    },

    'network_meter' : {
        'inc' : function(app,method) {
            try {
                var m = document.getElementById('network_progress');
                var count = 1 + Number( m.getAttribute('count') );
                m.setAttribute('mode','undetermined');
                m.setAttribute('count', count);
                var rows = document.getElementById('network_progress_rows');
                var row = document.getElementById('network_progress_tip_'+app+'_'+method);
                if (!row) {
                    row = document.createElement('row'); row.setAttribute('id','network_progress_tip_'+app+'_'+method);
                    var a = document.createElement('label'); a.setAttribute('value','App:');
                    var b = document.createElement('label'); b.setAttribute('value',app);
                    var c = document.createElement('label'); c.setAttribute('value','Method:');
                    var d = document.createElement('label'); d.setAttribute('value',method);
                    var e = document.createElement('label'); e.setAttribute('value','Total:');
                    var f = document.createElement('label'); f.setAttribute('value','0'); 
                    f.setAttribute('id','network_progress_tip_total_'+app+'_'+method);
                    var g = document.createElement('label'); g.setAttribute('value','Outstanding:');
                    var h = document.createElement('label'); h.setAttribute('value','0');
                    h.setAttribute('id','network_progress_tip_out_'+app+'_'+method);
                    row.appendChild(a); row.appendChild(b); row.appendChild(c);
                    row.appendChild(d); row.appendChild(e); row.appendChild(f);
                    row.appendChild(g); row.appendChild(h); rows.appendChild(row);
                }
                var total = document.getElementById('network_progress_tip_total_'+app+'_'+method);
                if (total) {
                    total.setAttribute('value', 1 + Number( total.getAttribute('value') ));
                }
                var out = document.getElementById('network_progress_tip_out_'+app+'_'+method);
                if (out) {
                    out.setAttribute('value', 1 + Number( out.getAttribute('value') ));
                }
            } catch(E) {
                dump('network_meter.inc(): ' + E + '\n');
            }
        },
        'dec' : function(app,method) {
            try {
                var m = document.getElementById('network_progress');
                var count = -1 + Number( m.getAttribute('count') );
                if (count < 0) count = 0;
                if (count == 0) m.setAttribute('mode','determined');
                m.setAttribute('count', count);
                var out = document.getElementById('network_progress_tip_out_'+app+'_'+method);
                if (out) {
                    out.setAttribute('value', -1 + Number( out.getAttribute('value') ));
                }
            } catch(E) {
                dump('network_meter.dec(): ' + E + '\n');
            }
        }
    },
    'set_patron_tab' : function(params,content_params,event) {
        var obj = this;
        var horizontal_interface = String( obj.data.hash.aous['ui.circ.patron_summary.horizontal'] ) == 'true';
        var url = obj.url_prefix( horizontal_interface ? urls.XUL_PATRON_HORIZ_DISPLAY : urls.XUL_PATRON_DISPLAY );
        obj.command_tab(event,url,params ? params : {},content_params ? content_params : {});
    },
    'new_patron_tab' : function(params,content_params) {
        var obj = this;
        var horizontal_interface = String( obj.data.hash.aous['ui.circ.patron_summary.horizontal'] ) == 'true';
        var url = obj.url_prefix( horizontal_interface ? urls.XUL_PATRON_HORIZ_DISPLAY : urls.XUL_PATRON_DISPLAY );
        obj.new_tab(url,params ? params : {},content_params ? content_params : {});
    },
    'volume_item_creator' : function(params) {
        var obj = this;
        var url;
        var unified_interface = String( obj.data.hash.aous['ui.unified_volume_copy_editor'] ) == 'true';
        if (unified_interface) {
            var horizontal_interface = String( obj.data.hash.aous['ui.cat.volume_copy_editor.horizontal'] ) == 'true';
            url = obj.url_prefix( horizontal_interface ? urls.XUL_VOLUME_COPY_CREATOR_HORIZONTAL : urls.XUL_VOLUME_COPY_CREATOR );
        } else {
            url = obj.url_prefix( urls.XUL_VOLUME_COPY_CREATOR_ORIGINAL );
        }
        var w = obj.new_tab(
            url,
            { 'tab_name' : document.getElementById('offlineStrings').getString('staff.cat.create_or_rebarcode_items') },
            params
        );
    },
    'holdings_maintenance_tab' : function(docid,params,content_params) {
        var obj = this;
        if (!content_params) {
            content_params = {};
        }
        if (docid) {
            content_params['docid'] = docid;
        }
        var url = obj.url_prefix( urls.XUL_COPY_VOLUME_BROWSE );
        obj.new_tab(url,params || {}, content_params);
    },
    'get_new_session' : function(params) {
        var obj = this;
        if (!params) { params = {}; }
        JSAN.use('util.network'); var net = new util.network();
        var result = net.get_new_session(null,{'url_prefix':obj.url_prefix},!params.operator_change);
        if (typeof params.callback == 'function') {
            return params.callback( result, ses(), ses('authtime') );
        }
        return result;
    },
    'set_help_context' : function(params) {
        var obj = this;
        if (!params) { params = {}; }
        if (params.protocol == 'chrome:') { return; } /* not supported */
        var help_btn = document.getElementById('help_btn');
        if (help_btn) {
            dump('set_help_context: ' + js2JSON(params) + '\n');
            if (params.protocol) { help_btn.setAttribute('protocol', params.protocol); }
            if (params.hostname) { help_btn.setAttribute('hostname', params.hostname);  }
            if (params.port) { help_btn.setAttribute('port', params.port);  }
            if (params.pathname) { help_btn.setAttribute('pathname', params.pathname); }
            if (params.src) { help_btn.setAttribute('src', params.src); }
        }
    },

    'tab_semaphores' : {},

    'set_tab' : function(url,params,content_params) {
        var obj = this;
        if (!url) url = '/xul/server/';
        if (!url.match(/:\/\//) && !url.match(/^data:/)) url = urls.remote + url;
        if (!params) params = {};
        if (!content_params) content_params = {};
        var idx = this.controller.view.tabs.selectedIndex;
        if (params && typeof params.index != 'undefined') idx = params.index;
        var tab = this.controller.view.tabs.childNodes[ idx ];

        var id = tab.getAttribute('id');
        if (id) {
            if (typeof obj.tab_semaphores[id] != 'undefined') {
                if (obj.tab_semaphores[id] > 0) {
                    var confirmation = window.confirm(offlineStrings.getString('menu.replace_tab.unsaved_data_warning'));
                    if (!confirmation) { return; }
                    oils_unsaved_data_P( obj.tab_semaphores[id] );
                }
                delete obj.tab_semaphores[id];
            }
        }
        var unique_id = idx + ':' + new Date();
        tab.setAttribute('id',unique_id);
        if (params.focus) tab.focus();
        var panel = this.controller.view.panels.childNodes[ idx ];
        while ( panel.lastChild ) panel.removeChild( panel.lastChild );

        content_params.is_tab_locked = function() {
            dump('is_tab_locked\n');
            var id = tab.getAttribute('id');
            if (typeof obj.tab_semaphores[id] == 'undefined') {
                return false;
            }
            return obj.tab_semaphores[id] > 0;
        }
        content_params.lock_tab = function() { 
            dump('lock_tab\n');
            var id = tab.getAttribute('id');
            if (typeof obj.tab_semaphores[id] == 'undefined') {
                obj.tab_semaphores[id] = 0;
            }
            obj.tab_semaphores[id]++; 
            oils_unsaved_data_V();
            return obj.tab_semaphores[id]; 
        };
        content_params.unlock_tab = function() { 
            dump('unlock_tab\n');
            var id = tab.getAttribute('id');
            if (typeof obj.tab_semaphores[id] == 'undefined') {
                obj.tab_semaphores[id] = 0;
            }
            obj.tab_semaphores[id]--;
            if (obj.tab_semaphores[id] < 0) { obj.tab_semaphores[id] = 0; } 
            oils_unsaved_data_P();
            return obj.tab_semaphores[id]; 
        };
        content_params.inspect_tab = function() {
            var id = tab.getAttribute('id');
            return 'id = ' + id + ' semaphore = ' + obj.tab_semaphores[id];
        }
        content_params.new_tab = function(a,b,c) { return obj.new_tab(a,b,c); };
        content_params.set_tab = function(a,b,c) { return obj.set_tab(a,b,c); };
        content_params.open_external = function(a) { return obj.open_external(a); };
        content_params.close_tab = function() { return obj.close_tab(); };
        content_params.new_patron_tab = function(a,b) { return obj.new_patron_tab(a,b); };
        content_params.set_patron_tab = function(a,b) { return obj.set_patron_tab(a,b); };
        content_params.volume_item_creator = function(a) { return obj.volume_item_creator(a); };
        content_params.get_new_session = function(a) { return obj.get_new_session(a); };
        content_params.holdings_maintenance_tab = function(a,b,c) { return obj.holdings_maintenance_tab(a,b,c); };
        content_params.set_tab_name = function(name) { tab.label = tab.curindex + ' ' + name; tab.origlabel = name; };
        content_params.set_help_context = function(params) { return obj.set_help_context(params); };
        content_params.open_chrome_window = function(a,b,c) { return xulG.window.open(a,b,c); };
        content_params.url_prefix = function(url,secure) { return obj.url_prefix(url,secure); };
        content_params.network_meter = obj.network_meter;
        content_params.page_meter = obj.page_meter;
        content_params.get_barcode = obj.get_barcode;
        content_params.get_barcode_and_settings = obj.get_barcode_and_settings;
        content_params.render_toolbar_layout = function(layout) { return obj.render_toolbar_layout(layout); };
        content_params.set_statusbar = function(slot,text,tooltiptext,click_handler) {
            var e = document.getElementById('statusbarpanel'+slot);
            if (e) {
                var p = e.parentNode;
                var sbp = document.createElement('statusbarpanel');
                sbp.setAttribute('id','statusbarpanel'+slot);
                p.replaceChild(sbp,e); // destroy and replace the statusbarpanel as a poor man's way of clearing event handlers

                sbp.setAttribute('label',text);
                if (tooltiptext) {
                    sbp.setAttribute('tooltiptext',tooltiptext);
                }
                if (click_handler) {
                    sbp.addEventListener(
                        'click',
                        click_handler,
                        false
                    );
                }
            }
        };
        content_params.chrome_xulG = xulG;
        content_params._data = xulG._data;
        if (params && params.tab_name) content_params.set_tab_name( params.tab_name );
        
        var frame;
        try {
            if (typeof params.browser == 'undefined') params.browser = false;
            if (params.browser) {
                obj.id_incr++;
                frame = this.w.document.createElement('browser');
                frame.setAttribute('flex','1');
                frame.setAttribute('type','content');
                frame.setAttribute('autoscroll','false');
                frame.setAttribute('id','frame_'+obj.id_incr);
                panel.appendChild(frame);
                try {
                    dump('creating browser with src = ' + url + '\n');
                    JSAN.use('util.browser');
                    var b = new util.browser();
                    b.init(
                        {
                            'url' : url,
                            'push_xulG' : true,
                            'alt_print' : false,
                            'browser_id' : 'frame_'+obj.id_incr,
                            'passthru_content_params' : content_params,
                        }
                    );
                } catch(E) {
                    alert(E);
                }
            } else {
                frame = this.w.document.createElement('iframe');
                frame.setAttribute('flex','1');
                panel.appendChild(frame);
                dump('creating iframe with src = ' + url + '\n');
                frame.setAttribute('src',url);
                try {
                    netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
                    var cw = frame.contentWindow;
                    if (typeof cw.wrappedJSObject != 'undefined') cw = cw.wrappedJSObject;
                    cw.IAMXUL = true;
                    cw.xulG = content_params;
                    cw.addEventListener(
                        'load',
                        function() {
                            try {
                                if (typeof cw.help_context_set_locally == 'undefined') {
                                    var help_params = {
                                        'protocol' : cw.location.protocol,
                                        'hostname' : cw.location.hostname,
                                        'port' : cw.location.port,
                                        'pathname' : cw.location.pathname,
                                        'src' : ''
                                    };
                                    obj.set_help_context(help_params);
                                } else if (typeof cw.default_focus == 'function') {
                                    cw.default_focus();
                                }
                            } catch(E) {
                                obj.error.sdump('D_ERROR', 'main.menu, set_tab, onload: ' + E);
                            }
                            try {
                                if (typeof params.on_tab_load == 'function') {
                                    params.on_tab_load(cw);
                                }
                            } catch(E) {
                                obj.error.sdump('D_ERROR', 'main.menu, set_tab, onload #2: ' + E);
                            }
                        },
                        false
                    );
                } catch(E) {
                    this.error.sdump('D_ERROR', 'main.menu: ' + E);
                }
            }
        } catch(E) {
            this.error.sdump('D_ERROR', 'main.menu:2: ' + E);
            alert(offlineStrings.getString('menu.set_tab.error'));
        }

        return frame;
    },

    'open_external' : function(url) {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        // first construct an nsIURI object using the ioservice
        var ioservice = Components.classes["@mozilla.org/network/io-service;1"]
                            .getService(Components.interfaces.nsIIOService);

        var uriToOpen = ioservice.newURI(url, null, null);

        var extps = Components.classes["@mozilla.org/uriloader/external-protocol-service;1"]
                            .getService(Components.interfaces.nsIExternalProtocolService);

        // now, open it!
        extps.loadURI(uriToOpen, null);
    },

    'get_barcode' : function(window, context, barcode) {
        JSAN.use('util.network');
        JSAN.use('util.sound');

        // Depending on where we were called from data can be found in multiple ways
        var data;
        if(this.data) data = this.data;
        else if(xulG.data) data = xulG.data;        
        else {
            JSAN.use('util.data');
            data = new util.data();
        }
        data.stash_retrieve();

        var network = new util.network();
        var sound = new util.sound();

        // Should return an array. Or an error.
        var r = network.simple_request('GET_BARCODES', [ ses(), data.list.au[0].ws_ou(), context, barcode ]);

        if(!r) // Nothing?
            return false;

        // Top-level error, likely means bad session or no STAFF_LOGIN permission.
        if(typeof r.ilsevent != 'undefined') {
            // Hand it off to the caller.
            return r;
        }

        // No results? Return false
        if(r.length == 0) return false;

        // One result?
        if(r.length == 1) {
            // Return it. If it is an error the caller should deal with it.
            return r[0];
        }

        // At this point we have more than one result.
        // Check to see what we got.
        var result_filter = {};
        var valid_r = [];
        var unique_count = 0;
        var found_errors = false;
        var errors = '';
        var len = r.length;

        // Check each result.
        for(var i = 0; i < len; ++i) {
            // If it is an error
            if(typeof r[i].ilsevent != 'undefined') {
                // Make note that we found errors
                found_errors = true;
                // Grab the error into a string
                errors += js2JSON(r[i]);
            }
            else {
                // Otherwise, record the type/id combo for later
                var type = r[i].type;
                var id = r[i].id;
                var barcode = r[i].barcode;
                if(!result_filter[type]) result_filter[type] = {};
                if(!result_filter[type][id]) {
                    unique_count++;
                    result_filter[type][id] = [];
                }
                result_filter[type][id].push(barcode);
                valid_r.push(r[i]);
            }
        }

        // Only errors? Return the first one.
        if(unique_count == 0 && found_errors == true) {
            return r[0];
        }

        // No errors, one (unique) result? Return it.
        if(unique_count == 1 && found_errors == false) return valid_r[0];

        // For possible debugging, dump the errors.
        if(found_errors) dump(errors);

        // Still here? Must need to have the user pick.
        if(!xulG.url_prefix) xulG.url_prefix = url_prefix; // Make util.window happy
        JSAN.use('util.window');
        var win = new util.window();
        var url = url_prefix(urls.XUL_FANCY_PROMPT);
        var title = offlineStrings.getString('barcode_choice.title');
        var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" xmlns:html="http://www.w3.org/1999/xhtml" flex="1">';
        xml += '<groupbox flex="1" style="overflow: auto; border: solid thin;"><caption label="' + title + '"/>';
        xml += '<description style="-moz-user-select: text; -moz-user-focus: normal; font-size: large">' + offlineStrings.getString('barcode_choice.prompt') + '</description>';
        if(found_errors) // Let the user know that one or more possible answers errored out.
            xml += '<description style="-moz-user=select: text; -moz-user-focus: normal; font-size: large">' + offlineStrings.getString('barcode_choice.errors_found') + '</description>';
        xml += '</groupbox><groupbox><caption label="' + offlineStrings.getString('barcode_choice.choice_label') + '"/><vbox>';

        len = valid_r.length;
        // Look at all the non-error answers we got
        for(var i = 0; i < len; ++i) {
            // If we still have a filtered answer, display a button.
            if(result_filter[valid_r[i].type][valid_r[i].id]) {
                var result_data = false;
                var barcodes = result_filter[valid_r[i].type][valid_r[i].id];
                var barcodes_assembled = barcodes.shift();
                var button_label = '';
                while(barcodes.length > 0) // Join any secondary barcodes found together
                    barcodes_assembled = offlineStrings.getFormattedString('barcode_choice.join_barcodes', [barcodes_assembled, barcodes.shift()]);
                switch(r[i].type) {
                    case 'actor':
                        result_data = network.simple_request('BLOB_AU_PARTS_RETRIEVE',
                            [ ses() , valid_r[i].id, ['family_name', 'first_given_name', 'second_given_name', 'home_ou' ] ]);
                        button_label = offlineStrings.getFormattedString('barcode_choice.actor',
                            [barcodes_assembled, result_data[0], result_data[1] + (result_data[2] ? ' ' + result_data[2] : ''), data.hash.aou[ result_data[3] ].name(), data.hash.aou[ result_data[3] ].shortname()]);
                        break;
                    case 'booking':
                        result_data = network.simple_request('FM_ACP_DETAILS_VIA_BARCODE', [ ses(), valid_r[i].barcode ]);
                        // Note: This falls through intentionally.
                    case 'asset':
                    case 'serial':
                        if(!result_data) // If we fell through this should be set already.
                            result_data = network.simple_request('FM_ACP_DETAILS', [ ses(), valid_r[i].id ]);
                        button_label = offlineStrings.getFormattedString('barcode_choice.asset',
                            [barcodes_assembled, result_data.mvr.title(), data.hash.aou[ result_data.copy.circ_lib() ].name(), data.hash.aou[ result_data.copy.circ_lib() ].shortname()]);
                        break;
                }
                r[i].data = result_data;

                // This ensures we only show each unique id once
                delete result_filter[valid_r[i].type][valid_r[i].id];

                // If we have more than one context this should label each entry with where it came from
                // Likely most useful for distinguishing assets from bookings
                if(context != valid_r[i].type && offlineStrings.testString('barcode_choice.' + valid_r[i].type + '_label'))
                    button_label = offlineStrings.getFormattedString('barcode_choice.' + valid_r[i].type + '_label', [button_label]);

                xml += '<button label="' + button_label + '" name="fancy_submit" value="' + i + '"/>';
            }
        }
        xml += '<button label="' + offlineStrings.getString('barcode_choice.none') + '" name="fancy_cancel"/>';
        xml += '</vbox></groupbox></vbox>';
        var fancy_prompt_data = win.open( url, 'fancy_prompt', 'chrome,resizable,modal,width=500,height=500', { 'xml' : xml, 'title' : title, 'sound' : 'bad' } );
        if(fancy_prompt_data.fancy_status == 'complete')
            return valid_r[fancy_prompt_data.fancy_submit];
        else
            // user_false is used to indicate the user said "None of the above" to avoid fall-through erroring later.
            return "user_false";
    },

    'get_barcode_and_settings' : function(window, barcode, settings_only) {
        JSAN.use('util.network');
        if(!settings_only) {
            // We need to double-check the barcode for completion and such.
            var new_barcode = xulG.get_barcode(window, 'actor', barcode);
            if(new_barcode == "user_false") return;
            // No error means we have a (hopefully valid) completed barcode to use.
            // Otherwise, fall through to other methods of checking
            if(typeof new_barcode.ilsevent == 'undefined')
                barcode = new_barcode.barcode;
            else
                return false;
        }
        var network = new util.network();
        // We have a barcode! Time to load settings.
        // First, we need the user ID
        var user = network.simple_request('FM_AU_RETRIEVE_VIA_BARCODE', [ ses(), barcode ]);
        if(user.ilsevent != undefined || user.textcode != undefined)
            return false;
        var settings = {};
        for(var i = 0; i < user.settings().length; i++) {
            settings[user.settings()[i].name()] = JSON2js(user.settings()[i].value());
        }
        if(!settings['opac.default_phone'] && user.day_phone()) settings['opac.default_phone'] = user.day_phone();
        if(!settings['opac.hold_notify'] && settings['opac.hold_notify'] !== '') settings['opac.hold_notify'] = 'email:phone';
        return {"barcode": barcode, "settings" : settings};
    },

    'sort_menu' : function(menu, recurse) {
        var curgroup = new Array();
        var curstart = 1;
        var curordinal = 0;
        for (var itemid = 0; itemid < menu.firstChild.children.length; itemid++) {
            var item = menu.firstChild.children[itemid];
            curordinal++;
            if (item.getAttribute('forceFirst')) {
                item.setAttribute('ordinal', curstart);
                curstart++;
                continue;
            }
            if (item.nodeName == 'menuseparator') {
                this.sort_menu_items(curgroup, curstart);
                item.setAttribute('ordinal', curordinal);
                curstart = curordinal + 1;
                curgroup = new Array();
                continue;
            }
            if (item.nodeName == 'menu' && recurse) {
                this.sort_menu(item, recurse);
            }
            curgroup.push(item);
        }
        this.sort_menu_items(curgroup, curstart);
    },

    'sort_menu_items' : function(itemgroup, start) {
        var curpos = start;
        var sorted = itemgroup.sort(function(a,b) {
            var labelA = a.getAttribute('label').toUpperCase();
            var labelB = b.getAttribute('label').toUpperCase();
            return labelA.localeCompare(labelB);
        });
        for(var item = 0; item < sorted.length; item++) {
            sorted[item].setAttribute('ordinal', curpos++);
        }
    },

    'observe' : function(subject, topic, data) {
        if (topic != "nsPref:changed") {
            return;
        }

        switch(data) {
            case 'oils.copy_editor.copy_location_name_first':
                var cl_first = xulG.pref.getBoolPref('oils.copy_editor.copy_location_name_first');
                var menuitems = document.getElementsByAttribute('command','cmd_copy_editor_copy_location_first_toggle');
                for(var i = 0; i < menuitems.length; i++)
                    menuitems[i].setAttribute('checked', cl_first ? 'true' : 'false');
            break;
        }
    },

    'stop_observing' : function() {
        xulG.pref.removeObserver('oils.copy_editor.*', this);
    },

    'render_toolbar' : function(button_bar) {
        try {

            this.last_sanctioned_toolbar = button_bar;

            var toolbar = document.getElementById('toolbar_main');

            if (button_bar == 'none' || typeof button_bar == 'undefined') {
                toolbar.setAttribute('hidden','true');
                return;
            }

            // find the layout
            var layout;
            JSAN.use('util.widgets'); JSAN.use('util.functional');
            var def = this.data.hash.atb[ button_bar ];
            if (!def) def = util.functional.find_list( this.data.list.atb, function(e) { return e.label == button_bar; } );
            if (!def) {
                dump('Could not find layout for specified toolbar. Defaulting to a stock toolbar.\n');
                layout = ["circ_checkout","circ_checkin","toolbarseparator","search_opac","copy_status","toolbarseparator","patron_search","patron_register","toolbarspacer","hotkeys_toggle"];
            } else {
                layout = JSON2js(def.layout());
            }

            this.render_toolbar_layout(layout);

        } catch(E) {
            alert('Error in menu.js, render_toolbar('+button_bar+'): ' + E);
        }
    },

    'render_toolbar_layout' : function(layout) {
        try {

            if (!layout) {
                this.data.stash_retrieve();
                this.render_toolbar( this.last_sanctioned_toolbar );
                return;
            }

            var toolbar = document.getElementById('toolbar_main');

            // destroy existing toolbar
            util.widgets.remove_children(toolbar);

            // create new one
            for (var i = 0; i < layout.length; i++) {
                var e = layout[i];
                if (e.match('toolbarseparator')) {
                        toolbar.appendChild( document.createElement('toolbarseparator') );
                } else if (e.match('toolbarspacer')) {
                    var spacer = document.createElement('toolbarspacer');
                    spacer.setAttribute('flex','1');
                    toolbar.appendChild( spacer );
                } else {
                    var templates = $('palette').getElementsByAttribute('templateid',e);
                    var template = templates.length > 0 ? templates[0] : null;
                    if (template) {
                        var clone = template.cloneNode(true);
                        toolbar.appendChild( clone );
                    } else {
                        var label = document.createElement('label');
                        label.setAttribute('value',e);
                        toolbar.appendChild( label );
                    }
                }
            }
            toolbar.setAttribute('hidden','false');

        } catch(E) {
            alert('Error in menu.js, render_toolbar_layout('+layout+'): ' + E);
        }
    }
}

dump('exiting main/menu.js\n');
