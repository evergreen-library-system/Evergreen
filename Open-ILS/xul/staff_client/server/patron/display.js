dump('entering patron/display.js\n');
dojo.require("openils.User");
dojo.require("openils.XUL");

function $(id) { return document.getElementById(id); }

if (typeof patron == 'undefined') patron = {};
patron.display = function (params) {

    JSAN.use('util.error'); this.error = new util.error();
    JSAN.use('util.window'); this.window = new util.window();
    JSAN.use('util.network'); this.network = new util.network();
    JSAN.use('util.widgets'); 
    this.w = window;
}

patron.display.prototype = {

    'retrieve_ids' : [],
    'stop_checkouts' : false,
    'check_stop_checkouts' : function() { return this.stop_checkouts; },

    'init' : function( params ) {

        var obj = this;

        obj.barcode = params['barcode'];
        obj.id = params['id'];

        JSAN.use('OpenILS.data'); this.OpenILS = {}; 
        obj.OpenILS.data = new OpenILS.data(); obj.OpenILS.data.init({'via':'stash'});
        
        //var horizontal_interface = String( obj.OpenILS.data.hash.aous['ui.circ.patron_summary.horizontal'] ) == 'true';
        //document.getElementById('ui.circ.patron_summary.horizontal').setAttribute('orient', horizontal_interface ? 'vertical' : 'horizontal');
        //document.getElementById('pdms1').setAttribute('orient', horizontal_interface ? 'vertical' : 'horizontal');
        
        JSAN.use('util.deck'); 
        obj.right_deck = new util.deck('patron_right_deck');
        obj.left_deck = new util.deck('patron_left_deck');

        JSAN.use('util.controller'); obj.controller = new util.controller();
        obj.controller.init(
            {
                control_map : {
                    'cmd_broken' : [
                        ['command'],
                        function() { alert($("commonStrings").getString('common.unimplemented')); }
                    ],
                    'cmd_patron_retrieve' : [
                        ['command'],
                        function(ev) {
                            if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') {
                                for (var i = 0; i < obj.retrieve_ids.length; i++) {    
                                    try {
                                        window.xulG.new_patron_tab(
                                            {}, { 'id' : obj.retrieve_ids[i] }
                                        );
                                    } catch(E) {
                                        alert(E);
                                    }
                                }
                            }
                        }
                    ],
                    'cmd_patron_merge' : [
                        ['command'],
                        function(ev) {
                            JSAN.use('patron.util');
                            if (patron.util.merge( obj.retrieve_ids )) {
                                obj.controller.view.cmd_patron_retrieve.setAttribute('disabled','true');
                                obj.controller.view.cmd_patron_merge.setAttribute('disabled','true');
                                var sobj = obj.search_result.g.search_result;
                                if ( sobj.query ) { sobj.search( sobj.query ); }
                            }
                        }
                    ],
                    'cmd_patron_toggle_summary' : [
                        ['command'],
                        function(ev) {
                            document.getElementById('splitter_grippy').doCommand();
                        }
                    ],
                    'cmd_patron_delete' : [
                        ['command'],
                        function(ev) {
                            try {
                                if (get_bool( obj.patron.super_user() )) {
                                    alert($("patronStrings").getString('staff.patron.display.cmd_patron_delete.deny_deletion_of_super_user'));
                                    return;
                                }
                                if (obj.patron.id() == obj.OpenILS.data.list.au[0].id()) {
                                    alert($("patronStrings").getString('staff.patron.display.cmd_patron_delete.deny_deletion_of_self'));
                                    return;
                                }
                                var rv = obj.error.yns_alert_original(
                                    $("patronStrings").getString('staff.patron.display.cmd_patron_delete.dialog.message'),
                                    $("patronStrings").getString('staff.patron.display.cmd_patron_delete.dialog.title'),
                                    $("patronStrings").getString('staff.patron.display.cmd_patron_delete.dialog.okay'),
                                    $("patronStrings").getString('staff.patron.display.cmd_patron_delete.dialog.cancel'),
                                    null,
                                    $("patronStrings").getString('staff.patron.display.cmd_patron_delete.dialog.confirmation')
                                );
                                //alert('rv = ' + rv + ' (' + typeof rv + ')');
                                if (rv == 0) {
                                    var params = [ ses(), obj.patron.id() ];
                                    var staff_check = obj.network.simple_request('PERM_RETRIEVE_WORK_OU',[ ses(), 'STAFF_LOGIN', obj.patron.id() ]);
                                    if (staff_check.length > 0) {
                                        var dest_barcode = window.prompt(
                                            $("patronStrings").getString('staff.patron.display.cmd_patron_delete.dest_user.prompt'),
                                            $("patronStrings").getString('staff.patron.display.cmd_patron_delete.dest_user.default_value'),
                                            $("patronStrings").getString('staff.patron.display.cmd_patron_delete.dest_user.title')
                                        );
                                        if (!dest_barcode) return;
                                        JSAN.use('patron.util');
                                        var dest_usr = patron.util.retrieve_fleshed_au_via_barcode( ses(), dest_barcode );
                                        if (typeof dest_usr.ilsevent != 'undefined') {
                                            alert( $("patronStrings").getString('staff.patron.display.cmd_patron_delete.dest_user.failure') );
                                            return;
                                        }
                                        if (dest_usr.id() == obj.patron.id()) {
                                            alert( $("patronStrings").getString('staff.patron.display.cmd_patron_delete.dest_user.self_reference_failure') );
                                            return;
                                        }
                                        params.push( dest_usr.id() );
                                    }
                                    var robj = obj.network.simple_request(
                                        'FM_AU_DELETE',
                                        params,
                                        null,
                                        {
                                            'title' : document.getElementById('patronStrings').getString('staff.patron.display.cmd_patron_delete.override_prompt'),
                                            'overridable_events' : [
                                                2004 /* ACTOR_USER_DELETE_OPEN_XACTS */
                                            ]
                                        }
                                    );
                                    if (typeof robj.ilsevent != 'undefined') {
                                        switch(Number(robj.ilsevent)) {
                                            /* already informed via override prompt */
                                            case 2004 /* ACTOR_USER_DELETE_OPEN_XACTS */ :
                                                return;
                                            break;
                                        }
                                    }
                                    obj.refresh_all();
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('Error in server/patron/display.js -> cmd_patron_delete: ',E);
                            }
                        }
                    ],
                    'cmd_search_form' : [
                        ['command'],
                        function(ev) {
                            obj.controller.view.cmd_search_form.setAttribute('disabled','true');
                            obj.left_deck.node.selectedIndex = 0;
                            obj.controller.view.patron_name.setAttribute('value', $("patronStrings").getString('staff.patron.display.cmd_search_form.no_patron'));
                            obj.controller.view.patron_name.setAttribute('tooltiptext', '');
                            obj.controller.view.patron_name.setAttribute('onclick', '');
                            removeCSSClass(document.documentElement,'PATRON_HAS_BILLS');
                            removeCSSClass(document.documentElement,'PATRON_HAS_OVERDUES');
                            removeCSSClass(document.documentElement,'PATRON_HAS_NOTES');
                            removeCSSClass(document.documentElement,'PATRON_EXCEEDS_CHECKOUT_COUNT');
                            removeCSSClass(document.documentElement,'PATRON_EXCEEDS_OVERDUE_COUNT');
                            removeCSSClass(document.documentElement,'PATRON_EXCEEDS_FINES');
                            removeCSSClass(document.documentElement,'NO_PENALTIES');
                            removeCSSClass(document.documentElement,'ONE_PENALTY');
                            removeCSSClass(document.documentElement,'MULTIPLE_PENALTIES');
                            removeCSSClass(document.documentElement,'PATRON_HAS_ALERT');
                            removeCSSClass(document.documentElement,'PATRON_BARRED');
                            removeCSSClass(document.documentElement,'PATRON_INACTIVE');
                            removeCSSClass(document.documentElement,'PATRON_EXPIRED');
                            removeCSSClass(document.documentElement,'PATRON_HAS_INVALID_DOB');
                            removeCSSClass(document.documentElement,'PATRON_JUVENILE');
                            removeCSSClass(document.documentElement,'PATRON_HAS_INVALID_ADDRESS');
                            removeCSSClass(document.documentElement,'PATRON_AGE_GE_65');
                            removeCSSClass(document.documentElement,'PATRON_AGE_LT_65');
                            removeCSSClass(document.documentElement,'PATRON_AGE_GE_24');
                            removeCSSClass(document.documentElement,'PATRON_AGE_LT_24');
                            removeCSSClass(document.documentElement,'PATRON_AGE_GE_21');
                            removeCSSClass(document.documentElement,'PATRON_AGE_LT_21');
                            removeCSSClass(document.documentElement,'PATRON_AGE_GE_18');
                            removeCSSClass(document.documentElement,'PATRON_AGE_LT_18');
                            removeCSSClass(document.documentElement,'PATRON_AGE_GE_13');
                            removeCSSClass(document.documentElement,'PATRON_AGE_LT_13');
                            removeCSSClass(document.documentElement,'PATRON_NET_ACCESS_1');
                            removeCSSClass(document.documentElement,'PATRON_NET_ACCESS_2');
                            removeCSSClass(document.documentElement,'PATRON_NET_ACCESS_3');
                        }
                    ],
                    'cmd_patron_refresh' : [
                        ['command'],
                        function(ev) {
                            try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_refresh" ) ); } catch(E) {};
                            obj.refresh_all();
                        }
                    ],
                    'cmd_patron_checkout' : [
                        ['command'],
                        function(ev) {
                            obj.reset_nav_styling('cmd_patron_checkout');
                            obj.spawn_checkout_interface();
                        }
                    ],
                    'cmd_patron_items' : [
                        ['command'],
                        function(ev) {
                            try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_items" ) ); } catch(E) {};
                            obj.reset_nav_styling('cmd_patron_items');
                            var frame = obj.right_deck.set_iframe(
                                urls.XUL_PATRON_ITEMS,
                                //+ '?patron_id=' + window.escape( obj.patron.id() ),
                                {},
                                {
                                    'patron_id' : obj.patron.id(),
                                    'on_list_change' : function(b) {
                                        obj.summary_window.g.summary.controller.render('patron_checkouts');
                                        obj.summary_window.g.summary.controller.render('patron_standing_penalties');
                                        obj.summary_window.g.summary.controller.render('patron_bill');
                                        if (obj.bill_window) {
                                            obj.bill_window.refresh(true);
                                        }
                                    },
                                    'url_prefix' : function(url,secure) { return xulG.url_prefix(url,secure); },
                                    'get_new_session' : function(a) { return xulG.get_new_session(a); },
                                    'new_tab' : function(a,b,c) { return xulG.new_tab(a,b,c); },
                                    'new_patron_tab' : function(a,b) { return xulG.new_patron_tab(a,b); }
                                }
                            );
                            obj.items_window = get_contentWindow(frame);
                        }
                    ],
                    'cmd_patron_edit' : [
                        ['command'],
                        function(ev) {
                                try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_edit" ) ); } catch(E) {};
                                obj.reset_nav_styling('cmd_patron_edit');

                                function spawn_search(s) {
                                    obj.error.sdump('D_TRACE', 'Editor would like to search for: ' + js2JSON(s)); 
                                    obj.OpenILS.data.stash_retrieve();
                                    xulG.new_patron_tab( {}, { 'doit' : 1, 'query' : js2JSON(s) } );
                                }

                                function spawn_editor(p) {
                                    var url = urls.XUL_PATRON_EDIT;
                                    //var param_count = 0;
                                    //for (var i in p) {
                                    //    if (param_count++ == 0) url += '?'; else url += '&';
                                    //    url += i + '=' + window.escape(p[i]);
                                    //}
                                    var loc = xulG.url_prefix('XUL_REMOTE_BROWSER'); // + '?url=' + window.escape( url );
                                    xulG.new_tab(
                                        loc, 
                                        {}, 
                                        { 
                                            'url' : url,
                                            'show_print_button' : true , 
                                            'tab_name' : $("patronStrings").getString('staff.patron.display.spawn_editor.editing_related_patron'),
                                            'passthru_content_params' : {
                                                'spawn_search' : spawn_search,
                                                'spawn_editor' : spawn_editor,
                                                'url_prefix' : function(url,secure) { return xulG.url_prefix(url,secure); },
                                                'get_new_session' : function(a) { return xulG.get_new_session(a); },
                                                'new_tab' : function(a,b,c) { return xulG.new_tab(a,b,c); },
                                                'new_patron_tab' : function(a,b) { return xulG.new_patron_tab(a,b); },
                                                'params' : p,
                                                'on_save' : function(p_obj) {
                                                    JSAN.use('patron.util');
                                                    patron.util.work_log_patron_edit(p_obj);
                                                }
                                            },
                                            'lock_tab' : function() { return xulG.lock_tab(); },
                                            'unlock_tab' : function() { return xulG.unlock_tab(); }
                                        }
                                    );
                                }

                            obj.right_deck.set_iframe(
                                urls.XUL_REMOTE_BROWSER + '?patron_edit=1',
                                //+ '?url=' + window.escape( 
                                //    urls.XUL_PATRON_EDIT
                                //    + '?ses=' + window.escape( ses() )
                                //    + '&usr=' + window.escape( obj.patron.id() )
                                //),
                                {}, {
                                    'url' : urls.XUL_PATRON_EDIT,
                                    'show_print_button' : true,
                                    'passthru_content_params' : {
                                        'params' : {
                                            'ses' : ses(),
                                            'usr' : obj.patron.id()
                                        },
                                        'on_save' : function(p) {
                                            try {
                                                JSAN.use('patron.util'); 
                                                patron.util.work_log_patron_edit(p);
                                                if (obj.barcode) obj.barcode = p.card().barcode();
                                                //obj.summary_window.g.summary.retrieve();
                                                obj.refresh_all();
                                            } catch(E) {
                                                alert(E);
                                            }
                                        },
                                        'spawn_search' : spawn_search,
                                        'spawn_editor' : spawn_editor,
                                        'url_prefix' : function(url,secure) { return xulG.url_prefix(url,secure); },
                                        'get_new_session' : function(a) { return xulG.get_new_session(a); },
                                        'new_tab' : function(a,b,c) { return xulG.new_tab(a,b,c); },
                                        'new_patron_tab' : function(a,b) { return xulG.new_patron_tab(a,b); }
                                    },
                                    'lock_tab' : function() { return xulG.lock_tab(); },
                                    'unlock_tab' : function() { return xulG.unlock_tab(); }
                                }
                            );
                        }
                    ],
                    'cmd_patron_other' : [
                        ['command'],
                        function(ev) {
                            try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_other" ) ); } catch(E) {};
                            obj.reset_nav_styling('cmd_patron_other');
                            try { document.getElementById('PatronNavBar_other').firstChild.showPopup(); } catch(E) {};
                        }
                    ],
                    'cmd_patron_info_notes' : [
                        ['command'],
                        function(ev) {
                            obj.right_deck.set_iframe(
                                urls.XUL_PATRON_INFO_NOTES,
                                {},
                                {
                                    'patron_id' : obj.patron.id(),
                                    'url_prefix' : function(url,secure) { return xulG.url_prefix(url,secure); },
                                    'get_new_session' : function(a) { return xulG.get_new_session(a); },
                                    'new_tab' : function(a,b,c) { return xulG.new_tab(a,b,c); },
                                    'new_patron_tab' : function(a,b) { return xulG.new_patron_tab(a,b); }
                                }
                            );
                        }
                    ],
                    'cmd_patron_info_triggered_events' : [
                        ['command'],
                        function(ev) {
                            obj.right_deck.set_iframe(
                                xulG.url_prefix(urls.XUL_REMOTE_BROWSER),
                                {},
                                {
                                    'url': urls.EG_TRIGGER_EVENTS + "?patron_id=" + obj.patron.id(),
                                    'show_print_button': false,
                                    'show_nav_buttons': false
                                }
                            );
                        }
                    ],
                    'cmd_patron_info_stats' : [
                        ['command'],
                        function(ev) {
                            obj.right_deck.set_iframe(
                                urls.XUL_PATRON_INFO_STAT_CATS,
                                {},
                                {
                                    'patron_id' : obj.patron.id(),
                                    'url_prefix' : function(url,secure) { return xulG.url_prefix(url,secure); },
                                    'get_new_session' : function(a) { return xulG.get_new_session(a); },
                                    'new_tab' : function(a,b,c) { return xulG.new_tab(a,b,c); },
                                    'new_patron_tab' : function(a,b) { return xulG.new_patron_tab(a,b); }
                                }
                            );
                        }
                    ],
                    'cmd_patron_info_surveys' : [
                        ['command'],
                        function(ev) {
                            obj.right_deck.set_iframe(
                                urls.XUL_PATRON_INFO_SURVEYS,
                                {},
                                {
                                    'patron_id' : obj.patron.id(),
                                    'url_prefix' : function(url,secure) { return xulG.url_prefix(url,secure); },
                                    'get_new_session' : function(a) { return xulG.get_new_session(a); },
                                    'new_tab' : function(a,b,c) { return xulG.new_tab(a,b,c); },
                                    'new_patron_tab' : function(a,b) { return xulG.new_patron_tab(a,b); }
                                }
                            );
                        }
                    ],
                    'cmd_patron_info_acq_requests' : [
                        ['command'],
                        function(ev) {
                            obj.right_deck.set_iframe(
                                urls.EG_ACQ_USER_REQUESTS + '?usr=' + obj.patron.id(),
                                {},
                                {
                                    'get_barcode' : function(a,b,c) { return xulG.get_barcode(a,b,c); },
                                    'get_barcode_and_settings' : function(a,b,c) { return xulG.get_barcode_and_settings(a,b,c); }
                                }
                            );
                        }
                    ],

                    'cmd_patron_info_groups' : [
                        ['command'],
                        function(ev) {
                            obj.spawn_group_interface();
                        }
                    ],
                    'cmd_patron_alert' : [
                        ['command'],
                        function(ev) {
                            if (obj.msg_url) {
                                obj.right_deck.set_iframe('data:text/html,'+obj.msg_url,{},{});
                            } else {
                                obj.right_deck.set_iframe('data:text/html,<h1>' + $("patronStrings").getString('staff.patron.display.no_alerts_or_messages') + '</h1>',{},{});
                            }
                        }
                    ],
                    'cmd_patron_reservation' : [
                        ['command'],
                        function(ev) {
                            openils.XUL.newTabEasy(
                                "BOOKING_RESERVATION",
                                $("offlineStrings").getString(
                                    "menu.cmd_booking_reservation.tab"
                                ), {
                                    "bresv_interface_opts": {
                                        "patron_barcode":
                                            obj.patron.card().barcode()
                                    }
                                },
                                true
                            );
                        }
                    ],
                    'cmd_patron_reservation_pickup' : [
                        ['command'],
                        function(ev) {
                            openils.XUL.newTabEasy(
                                "BOOKING_PICKUP",
                                $("offlineStrings").getString(
                                    "menu.cmd_booking_reservation_pickup.tab"
                                ), {
                                    "bresv_interface_opts": {
                                        "patron_barcode":
                                            obj.patron.card().barcode()
                                    }
                                },
                                true
                            );
                        }
                    ],
                    'cmd_patron_reservation_return' : [
                        ['command'],
                        function(ev) {
                            openils.XUL.newTabEasy(
                                "BOOKING_RETURN",
                                $("offlineStrings").getString(
                                    "menu.cmd_booking_reservation_return.tab"
                                ), {
                                    "bresv_interface_opts": {
                                        "patron_barcode":
                                            obj.patron.card().barcode()
                                    }
                                },
                                true
                            );
                        }
                    ],
                    'cmd_patron_exit' : [
                        ['command'],
                        function(ev) {
                            xulG.set_tab(urls.XUL_PATRON_BARCODE_ENTRY,{},{});
                        }
                    ],
                    'cmd_patron_holds' : [
                        ['command'],
                        function(ev) {
                            try {
                                try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_holds" ) ); } catch(E) {};
                                obj.reset_nav_styling('cmd_patron_holds');
                                obj.right_deck.set_iframe(
                                    urls.XUL_PATRON_HOLDS,    
                                    //+ '?patron_id=' + window.escape( obj.patron.id() ),
                                    {},
                                    {
                                        'display_window' : window,
                                        'patron_id' : obj.patron.id(),
                                        'patron_barcode' : obj.patron.card().barcode(),
                                        'on_list_change' : function(h) {
                                            try {
                                                obj.summary_window.g.summary.controller.render('patron_holds');
                                            } catch(E) {
                                                alert(E);
                                            }
                                        },
                                        'url_prefix' : function(url,secure) { return xulG.url_prefix(url,secure); },
                                        'get_new_session' : function(a) { return xulG.get_new_session(a); },
                                        'new_tab' : function(a,b,c) { return xulG.new_tab(a,b,c); },
                                        'new_patron_tab' : function(a,b) { return xulG.new_patron_tab(a,b); },
                                        'get_barcode' : function(a,b,c) { return xulG.get_barcode(a,b,c); },
                                        'get_barcode_and_settings' : function(a,b,c) { return xulG.get_barcode_and_settings(a,b,c); }
                                    }
                                );
                            } catch(E) {
                                alert(E);
                            }
                        }
                    ],
                    'cmd_patron_bills' : [
                        ['command'],
                        function(ev) {
                            try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_bills" ) ); } catch(E) {};
                            obj.reset_nav_styling('cmd_patron_bills');
                            var f = obj.right_deck.set_iframe(
                                urls.XUL_PATRON_BILLS,
                                //+ '?patron_id=' + window.escape( obj.patron.id() ),
                                {},
                                {
                                    'display_window' : window,
                                    'patron_id' : obj.patron.id(),
                                    'url_prefix' : function(url,secure) { return xulG.url_prefix(url,secure); },
                                    'get_new_session' : function(a) { return xulG.get_new_session(a); },
                                    'new_tab' : function(a,b,c) { return xulG.new_tab(a,b,c); },
                                    'on_money_change' : function(b) {
                                        obj.summary_window.g.summary.controller.render('patron_standing_penalties');
                                        obj.summary_window.g.summary.controller.render('patron_bill');
                                        obj.summary_window.refresh();
                                    }
                                }
                            );
                            obj.bill_window = get_contentWindow(f);
                        }
                    ],
                    'patron_name' : [
                        ['render'],
                        function(e) {
                            return function() { 
                                JSAN.use('patron.util'); 
                                e.setAttribute('value',
                                    patron.util.format_name( obj.patron )
                                );
                                patron.util.set_penalty_css(obj.patron);
                                var tooltiptext = $("patronStrings").getFormattedString(
                                    'staff.patron.display.db_data',
                                    [
                                        obj.patron.id(),
                                        obj.patron.create_date(),
                                        obj.patron.last_update_time()
                                            ? obj.patron.last_update_time()
                                            : ''
                                    ]
                                );
                                e.setAttribute('tooltiptext',tooltiptext);
                                e.setAttribute('onclick','try { copy_to_clipboard(event); } catch(E) { alert(E); }');
                            };
                        }
                    ],
                    'PatronNavBar' : [
                        ['render'],
                        function(e) {
                            return function() {}
                        }
                    ],
                    'cmd_verify_credentials' : [
                        ['command'],
                        function() {
                            var vframe = obj.right_deck.reset_iframe(
                                urls.XUL_VERIFY_CREDENTIALS,
                                {},
                                {
                                    'barcode' : obj.patron.card().barcode(),
                                    'usrname' : obj.patron.usrname()
                                }
                            );
                        } 
                    ],
                    'cmd_perm_editor' : [
                        ['command'],
                        function() {
                             var frame = obj.right_deck.reset_iframe( urls.XUL_USER_PERM_EDITOR + '?ses=' + window.escape(ses()) + '&usr=' + obj.patron.id(), {}, {});
                        }
                    ],
                    'cmd_standing_penalties' : [
                        ['command'],
                        function() {
                            function penalty_interface() {
                                try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_messages" ) ); } catch(E) {};
                                obj.reset_nav_styling('cmd_standing_penalties');
                                return obj.right_deck.set_iframe(
                                    urls.XUL_STANDING_PENALTIES,
                                    {},
                                    {
                                        'patron' : obj.patron,
                                        'refresh' : function() { 
                                            obj.refresh_all(); 
                                        }
                                    }
                                );
                            }
                            penalty_interface();
                        } 
                    ]
                }
            }
        );

        var x = document.getElementById("PatronNavBar_checkout");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_refresh");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_items");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_holds");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_other");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_edit");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_bills");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);
        var x = document.getElementById("PatronNavBar_messages");
        x.addEventListener( 'focus', function(xx) { return function() { try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible(xx); } catch(E) {}; } }(x), false);

        if (obj.barcode || obj.id) {
            if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
                try { window.xulG.set_tab_name($("patronStrings").getString('staff.patron.display.init.retrieving_patron')); } catch(E) { alert(E); }
            }

            obj.controller.view.PatronNavBar.selectedIndex = 1;
            JSAN.use('util.widgets'); 
            util.widgets.enable_accesskeys_in_node_and_children(
                obj.controller.view.PatronNavBar.lastChild
            );
            util.widgets.disable_accesskeys_in_node_and_children(
                obj.controller.view.PatronNavBar.firstChild
            );
            obj.controller.view.cmd_patron_refresh.setAttribute('disabled','true');
            obj.controller.view.cmd_patron_checkout.setAttribute('disabled','true');
            obj.controller.view.cmd_patron_items.setAttribute('disabled','true');
            obj.controller.view.cmd_patron_holds.setAttribute('disabled','true');
            obj.controller.view.cmd_patron_bills.setAttribute('disabled','true');
            obj.controller.view.cmd_patron_edit.setAttribute('disabled','true');
            obj.controller.view.patron_name.setAttribute('value', $("patronStrings").getString('staff.patron.display.init.retrieving'));
            document.documentElement.setAttribute('class','');
            var frame = obj.left_deck.set_iframe(
                urls.XUL_PATRON_SUMMARY,
                {},
                {
                    'display_window' : window,
                    'barcode' : obj.barcode,
                    'id' : obj.id,
                    'refresh' : function() { obj.refresh_all(); },
                    'on_finished' : obj.gen_patron_summary_finish_func(params),
                    'stop_sign_page' : obj.gen_patron_stop_sign_page_func(),
                    'spawn_group_interface' : function() { obj.spawn_group_interface(); },
                    'new_patron_tab' : function(a,b) { return xulG.new_patron_tab(a,b); },
                    'new_tab' : function(a,b,c) { return xulG.new_tab(a,b,c); },
                    'set_tab' : function(a,b,c) { return xulG.set_tab(a,b,c); },
                    'on_error' : function(E) {
                        try {
                            var error;
                            if (typeof E.ilsevent != 'undefined') {
                                error = E.textcode;
                            } else {
                                error = js2JSON(E).substr(0,100);
                            }
                            xulG.set_tab(urls.XUL_PATRON_BARCODE_ENTRY + '?error=' + window.escape(error),{},{});
                        } catch(F) {
                            alert(F);
                        }
                    }
                }
            );
            obj.summary_window = get_contentWindow(frame);

        } else {
            obj.render_search_form(params);
        }
    },

    'reset_nav_styling' : function(btn,dont_hide_summary) {
        try {
            if (!dont_hide_summary) { dont_hide_summary = false; }
            if (this.skip_hide_summary) {
                this.skip_hide_summary = false;
                dont_hide_summary = true;
            }
            this.controller.view.cmd_patron_checkout.setAttribute('style','');
            this.controller.view.cmd_patron_items.setAttribute('style','');
            this.controller.view.cmd_patron_edit.setAttribute('style','');
            this.controller.view.cmd_patron_other.setAttribute('style','');
            this.controller.view.cmd_patron_holds.setAttribute('style','');
            this.controller.view.cmd_patron_bills.setAttribute('style','');
            this.controller.view.cmd_standing_penalties.setAttribute('style','');
            this.controller.view[ btn ].setAttribute('style','background: blue; color: white;');
            var auto_hide_patron_sidebar = String( this.OpenILS.data.hash.aous['circ.auto_hide_patron_summary'] ) == 'true';
            var x = document.getElementById('splitter_grippy'); 
            if (x && auto_hide_patron_sidebar && ! dont_hide_summary) {
                if (! this.summary_hidden_once_already ) {
                    var first_deck = x.parentNode.previousSibling;
                    if (! first_deck.collapsed) x.doCommand();
                    this.summary_hidden_once_already = true;
                }
            }
        } catch(E) {
            alert(E);
        }
    },

    'render_search_form' : function(params) {
        var obj = this;
            if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
                try { window.xulG.set_tab_name($("patronStrings").getString('staff.patron.display.render_search_form.patron_search')); } catch(E) { alert(E); }
            }

            obj.controller.view.PatronNavBar.selectedIndex = 0;
            obj.controller.view.cmd_patron_retrieve.setAttribute('disabled','true');
            obj.controller.view.cmd_patron_merge.setAttribute('disabled','true');
            obj.controller.view.cmd_search_form.setAttribute('disabled','true');

            var horizontal_interface = String( obj.OpenILS.data.hash.aous['ui.circ.patron_summary.horizontal'] ) == 'true';
            var loc = horizontal_interface ? urls.XUL_PATRON_HORIZONTAL_SEARCH_FORM : urls.XUL_PATRON_SEARCH_FORM; 
            var my_xulG = {
                'clear_left_deck' : function() {
                    setTimeout( function() {
                        obj.left_deck.clear_all_except(loc);
                        obj.render_search_form(params);
                    }, 0);
                },
                'on_submit' : function(query,search_limit,search_sort) {
                    obj.controller.view.cmd_patron_retrieve.setAttribute('disabled','true');
                    obj.controller.view.cmd_patron_merge.setAttribute('disabled','true');
                    var list_frame = obj.right_deck.reset_iframe(
                        urls.XUL_PATRON_SEARCH_RESULT, // + '?' + query,
                        {},
                        {
                            'query' : query,
                            'search_limit' : search_limit,
                            'search_sort' : search_sort,
                            'on_dblclick' : function(list) {
                                JSAN.use('util.widgets');
                                util.widgets.dispatch('command','cmd_patron_retrieve')
                            },
                            'on_select' : function(list) {
                                if (!list) return;
                                if (list.length < 1) return;
                                obj.controller.view.cmd_patron_retrieve.setAttribute('disabled','false');
                                if (list.length > 1) obj.controller.view.cmd_patron_merge.setAttribute('disabled','false');
                                obj.controller.view.cmd_search_form.setAttribute('disabled','false');
                                obj.retrieve_ids = list;
                                obj.controller.view.patron_name.setAttribute('value',$("patronStrings").getString('staff.patron.display.init.retrieving'));
                                document.documentElement.setAttribute('class','');
                                setTimeout(
                                    function() {
                                        var frame = obj.left_deck.set_iframe(
                                            urls.XUL_PATRON_SUMMARY + '?id=' + window.escape(list[0]),
                                            {},
                                            {
                                                //'id' : list[0],
                                                'spawn_group_interface' : function() { obj.spawn_group_interface(); },
                                                'new_patron_tab' : function(a,b) { return xulG.new_patron_tab(a,b); },
                                                'new_tab' : function(a,b,c) { return xulG.new_tab(a,b,c); },
                                                'set_tab' : function(a,b,c) { return xulG.set_tab(a,b,c); },
                                                'on_finished' : function(patron) {
                                                    obj.patron = patron;
                                                    obj.controller.render();
                                                }
                                            }
                                        );
                                        obj.summary_window = get_contentWindow(frame);
                                        obj.patron = obj.summary_window.g.summary.patron;
                                        obj.controller.render('patron_name');
                                    }, 0
                                );
                            }
                        }
                    );
                    obj.search_result = get_contentWindow(list_frame);
                }
            };

            if (params['query']) {
                my_xulG.query = JSON2js(params['query']);
                if (params.doit) my_xulG.doit = 1;
            }

            var form_frame = obj.left_deck.set_iframe(
                loc,
                {},
                my_xulG
            );
            obj.search_window = get_contentWindow(form_frame);
            obj._already_defaulted_once = true;
    },

    '_already_defaulted_once' : false,

    'refresh_deck' : function(url) {
        var obj = this;
        for (var i = 0; i < obj.right_deck.node.childNodes.length; i++) {
            try {
                var f = obj.right_deck.node.childNodes[i];
                var w = get_contentWindow(f);
                if (url) {
                    if (w.location.href == url) w.refresh(true);
                } else {
                    if (typeof w.refresh == 'function') {
                        w.refresh(true);
                    }
                }

            } catch(E) {
                obj.error.sdump('D_ERROR','refresh_deck: ' + E + '\n');
            }
        }
    },
    
    'refresh_all' : function() {
        var obj = this;
        obj.controller.view.patron_name.setAttribute('value', $("patronStrings").getString('staff.patron.display.init.retrieving'));
        document.documentElement.setAttribute('class','');
        obj.network.simple_request(
            'RECALCULATE_STANDING_PENALTIES',
            [ ses(), obj.patron.id() ]
        );
        try { obj.summary_window.refresh(); } catch(E) { obj.error.sdump('D_ERROR', E + '\n'); }
        try { obj.refresh_deck(); } catch(E) { obj.error.sdump('D_ERROR', E + '\n'); }
    },

    'spawn_checkout_interface' : function() {
        var obj = this;
        try {
            try { document.getElementById("PatronNavBarScrollbox").ensureElementIsVisible( document.getElementById("PatronNavBar_checkout" ) ); } catch(E) {};
            obj.reset_nav_styling('cmd_patron_checkout',true);
            var frame = obj.right_deck.set_iframe(
                urls.XUL_CHECKOUT,
                {},
                { 
                    'set_tab' : function(a,b,c) { return xulG.set_tab(a,b,c); },
                    'patron_id' : obj.patron.id(),
                    'patron' : obj.patron,
                    'check_stop_checkouts' : function() { return obj.check_stop_checkouts(); },
                    'on_list_change_old' : function(checkout) {
                        var x = obj.summary_window.g.summary.controller.view.patron_checkouts;
                        var n = Number(x.getAttribute('value'));
                        x.setAttribute('value',n+1);
                    },
                    'on_list_change' : function(checkout,is_renewal) {
                        // Downside here: an extra network call, open-ils.actor.user.checked_out.count.authoritative
                        obj.summary_window.g.summary.controller.render('patron_checkouts');
                        obj.summary_window.g.summary.controller.render('patron_standing_penalties');

                        /* this stops noncats from getting pushed into Items Out */
                        if (!checkout.circ.id()) return;

                        if (obj.items_window) {
                            if (is_renewal) {
                                var original_circ_id = obj.items_window.g.items.list_circ_map_by_copy[ checkout.circ.target_copy() ];
                                obj.items_window.g.items.list_circ_map[ original_circ_id ].row.my.circ = checkout.circ;
                                obj.items_window.g.items.list_circ_map[ checkout.circ.id() ] =
                                    obj.items_window.g.items.list_circ_map[ original_circ_id ];
                                obj.items_window.g.items.refresh( checkout.circ.id() );
                            } else {
                                var nparams = obj.items_window.g.items.list.append(
                                    {
                                        'row' : {
                                            'my' : {
                                                'circ_id' : checkout.circ.id()
                                            }
                                        },
                                        'to_bottom' : true
                                    }
                                )
                                obj.items_window.g.items.list_circ_map[ checkout.circ.id() ] = nparams;
                                obj.items_window.g.items.list_circ_map_by_copy[ checkout.circ.target_copy() ] = checkout.circ.id();
                            }
                        }
                    },
                    'get_barcode' : xulG.get_barcode,
                    'get_barcode_and_settings' : xulG.get_barcode_and_settings,
                    'url_prefix' : xulG.url_prefix
                }
            );
            obj.checkout_window = get_contentWindow(frame);
        } catch(E) {
            alert('Error in spawn_checkout_interface(): ' + E);
        }
    },

    'gen_patron_summary_finish_func' : function(display_params) {
        var obj = this;

        return function(patron,params) {
            try {
                obj.patron = patron; obj.controller.render();

                obj.controller.view.cmd_patron_refresh.setAttribute('disabled','false');
                obj.controller.view.cmd_patron_checkout.setAttribute('disabled','false');
                obj.controller.view.cmd_patron_items.setAttribute('disabled','false');
                obj.controller.view.cmd_patron_holds.setAttribute('disabled','false');
                obj.controller.view.cmd_patron_bills.setAttribute('disabled','false');
                obj.controller.view.cmd_patron_edit.setAttribute('disabled','false');

                if (typeof window.xulG == 'object' && typeof window.xulG.set_tab_name == 'function') {
                    try { 
                        window.xulG.set_tab_name(
                            $("patronStrings").getString('staff.patron.display.tab_name')
                                + ' ' + patron.family_name() + ', ' + patron.first_given_name() + ' ' 
                                + (patron.second_given_name() ? patron.second_given_name() : '' ) 
                        ); 
                    } catch(E) { 
                        obj.error.sdump('D_ERROR',E);
                    }
                }

                if (!obj._already_defaulted_once) {
                    obj._already_defaulted_once = true;
                    if (display_params['show']) {
                        setTimeout(
                            function() {
                                switch(display_params['show']) {
                                    case 'bills' : util.widgets.dispatch('command','cmd_patron_bills'); break;
                                }
                            },
                            0
                        );
                    } else {
                        obj.spawn_checkout_interface();
                    }
                }

                if (obj.stop_checkouts && obj.checkout_window) {
                    setTimeout( function() {
                        try {
                            obj.checkout_window.g.checkout.check_disable();
                        } catch(E) { }
                    }, 1000);
                }
                            
            } catch(E) {
                alert('Error in patron_summary_finish_func(): ' + E);
            }
        };
    },

    'gen_patron_stop_sign_page_func' : function() {
        var obj = this;
        // FIXME - replace this generated "stop sign" page with a dedicated XUL file or template
        return function(patron,params) {
            try {
                obj._already_defaulted_once = true;
                var msg = ''; obj.stop_checkouts = false;
                if (patron.alert_message())
                    msg += $("patronStrings").getFormattedString('staff.patron.display.init.network_request.alert_message', [patron.alert_message()]);
                //alert('obj.barcode = ' + obj.barcode);
                if (obj.barcode) {
                    if (patron.cards()) for (var i = 0; i < patron.cards().length; i++) {
                        //alert('card #'+i+' == ' + js2JSON(patron.cards()[i]));
                        if ( (patron.cards()[i].barcode()==obj.barcode) && ( ! get_bool(patron.cards()[i].active()) ) ) {
                            msg += $("patronStrings").getString('staff.patron.display.init.network_request.inactive_card');
                            obj.stop_checkouts = true;
                        }
                    }
                }
                if (get_bool(patron.barred())) {
                    msg += $("patronStrings").getString('staff.patron.display.init.network_request.account_barred');
                    obj.stop_checkouts = true;
                }
                if (!get_bool(patron.active())) {
                    msg += $("patronStrings").getString('staff.patron.display.init.network_request.account_inactive');
                    obj.stop_checkouts = true;
                }
                if (patron.expire_date()) {
                    var now = new Date();
                    now = now.getTime()/1000;

                    var expire_parts = patron.expire_date().substr(0,10).split('-');
                    expire_parts[1] = expire_parts[1] - 1;

                    var expire = new Date();
                    expire.setFullYear(expire_parts[0], expire_parts[1], expire_parts[2]);
                    expire = expire.getTime()/1000

                    if (expire < now) {
                        msg += $("patronStrings").getString('staff.patron.display.init.network_request.account_expired');
                    obj.stop_checkouts = true;
                    }
                }
                var penalties = patron.standing_penalties();
                if (!penalties) { penalties = []; }
                var dl_flag_opened = false;
                for (var i = 0; i < penalties.length; i++) {
                    if (get_bool(penalties[i].standing_penalty().staff_alert())) {
                        if (!dl_flag_opened) {
                            msg += '<dl>';
                            dl_flag_opened = true;
                        }
                        msg += '<dt>';
                        msg += obj.OpenILS.data.hash.aou[ penalties[i].org_unit() ].shortname() + ' : ' + penalties[i].standing_penalty().label() + '<br/>';
                        msg += '</dt><dd>';
                        msg += (penalties[i].note())?penalties[i].note():'';
                        msg += '</dd>';
                    }
                }
                if (dl_flag_opened) { msg += '</dl>'; }
                var holds = params.holds_summary;
                if (holds.ready && holds.ready > 0) {
                    msg += $("patronStrings").getFormattedString('staff.patron.display.init.holds_ready', [holds.ready]);
                }
                if (msg) {
                    if (msg != obj.old_msg) {
                        //obj.error.yns_alert(msg,'Alert Message','OK',null,null,'Check here to confirm this message.');
                        document.documentElement.firstChild.focus();
                        var data_url = window.escape("<img src='" + xulG.url_prefix('/xul/server/skin/media/images/stop_sign.png') + "'/>" + '<h1>'
                            + $("patronStrings").getString('staff.patron.display.init.network_request.window_title') + '</h1><blockquote><p>' + msg + '</p>\r\n\r\n<pre>'
                            + $("patronStrings").getString('staff.patron.display.init.network_request.window_message') + '</pre></blockquote>');
                        obj.right_deck.set_iframe('data:text/html,'+data_url,{},{});
                        obj.old_msg = msg;
                        obj.msg_url = data_url;
                    } else {
                        obj.error.sdump('D_TRACE',$("patronStrings").getFormattedString('staff.patron.display.init.network_request.dump_error_message', [msg]));
                    }
                }
            } catch(E) {
                alert('Error in patron_stop_sign_page_func(): ' + E);
            }
        };
    },

    'spawn_group_interface' : function() {
        var obj = this;
        try {
            obj.right_deck.set_iframe(
                urls.XUL_PATRON_INFO_GROUP,
                {},
                {
                    'patron_id' : obj.patron.id(),
                    'url_prefix' : function(url,secure) { return xulG.url_prefix(url,secure); },
                    'get_new_session' : function(a) { return xulG.get_new_session(a); },
                    'new_tab' : function(a,b,c) { return xulG.new_tab(a,b,c); },
                    'new_patron_tab' : function(a,b) { return xulG.new_patron_tab(a,b); }
                }
            );
        } catch(E) {
            alert('Error in display.js, spawn_group_interface(): ' + E);
        }
    }

}

dump('exiting patron/display.js\n');
