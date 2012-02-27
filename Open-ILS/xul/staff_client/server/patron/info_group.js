function $(id) { return document.getElementById(id); }

function my_init() {
    try {
        if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
        JSAN.errorLevel = "die"; // none, warn, or die
        JSAN.addRepository('/xul/server/');

        JSAN.use('util.error'); g.error = new util.error();
        JSAN.use('util.network'); g.network = new util.network();
        JSAN.use('util.date'); JSAN.use('util.money'); JSAN.use('patron.util'); JSAN.use('util.functional');
        JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.stash_retrieve();

        g.error.sdump('D_TRACE','my_init() for patron_info_group.xul');

        g.patron_id = xul_param('patron_id');

        tree_init();

        g.patron = patron.util.retrieve_au_via_id(ses(),g.patron_id);
        if ((g.patron == null) || (typeof g.patron.ilsevent != 'undefined') ) throw(p);

        refresh();

    } catch(E) {
        var err_msg = $("commonStrings").getFormattedString('common.exception', ['patron/info_group.xul', E]);
        try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); }
        alert(err_msg);
    }
}

function retrieve_money_summaries() {
    try {
        JSAN.use('util.money');
        var robj = g.network.simple_request( 'BLOB_BALANCE_OWED_VIA_USERGROUP', [ ses(), g.patron.usrgroup() ]);
        if (typeof robj.ilsevent != 'undefined') { throw(robj); }

        var sum = 0; /* in cents */
        g.group_owed = {};

        for (var i = 0; i < robj.length; i++) {
            sum += util.money.dollars_float_to_cents_integer( robj[i].balance_owed );
            g.group_owed[ robj[i].usr ] = robj[i].balance_owed;
        }

        $('total_owed').setAttribute(
            'value',
            $('patronStrings').getFormattedString( 'staff.patron.info_group.total_owed.label', [ util.money.cents_as_dollars(sum) ] )
        );

    } catch(E) {
        alert('Error in info_group.js, retrieve_money_summaries(): ' + E);
    }
}

function tree_init() {
    try {
        var obscure_dob = String( g.data.hash.aous['circ.obscure_dob'] ) == 'true';

        JSAN.use('util.list'); g.list = new util.list('patron_list');

        var columns = g.list.fm_columns( 'au', {
            '*' : { 'hidden' : true },
            'au_active' : { 'hidden' : 'false' },
            'au_barred' : { 'hidden' : 'false' },
            'au_family_name' : { 'hidden' : 'false' },
            'au_first_given_name' : { 'hidden' : 'false' },
            'au_second_given_name' : { 'hidden' : 'false' },
            'au_dob' : { 'hidden' : obscure_dob },
            'au_master_account' : { 'hidden' : 'false' }
        }).concat([
            {
                'id' : 'gl_balance_owed', 'flex' : 1, 'sort_type' : 'money',
                'label' : $("patronStrings").getString('staff.patron.summary.group_list.column.balance_owed.label'),
                'render' : function(my) { return my.balance_owed; } 
            },
            {
                'id' : 'gl_circ_count_out', 'flex' : 1, 'sort_type' : 'number',
                'label' : $("patronStrings").getString('staff.patron.info_group.column.circs_out.label'),
                'render' : function(my) { return my.circ_counts.out; }
            },
            {
                'id' : 'gl_circ_count_overdue', 'flex' : 1, 'sort_type' : 'number',
                'label' : $("patronStrings").getString('staff.patron.info_group.column.circs_overdue.label'),
                'render' : function(my) { return my.circ_counts.overdue; }
            },
            {
                'id' : 'gl_circ_count_claims_returned', 'flex' : 1, 'sort_type' : 'number', 'hidden' : true,
                'label' : $("patronStrings").getString('staff.patron.info_group.column.circs_claimed_returned.label'),
                'render' : function(my) { return my.circ_counts.claims_returned; }
            },
            {
                'id' : 'gl_circ_count_long_overdue', 'flex' : 1, 'sort_type' : 'number', 'hidden' : true,
                'label' : $("patronStrings").getString('staff.patron.info_group.column.circs_long_overdue.label'),
                'render' : function(my) { return my.circ_counts.long_overdue; }
            },
            {
                'id' : 'gl_circ_count_lost', 'flex' : 1, 'sort_type' : 'number', 'hidden' : true,
                'label' : $("patronStrings").getString('staff.patron.info_group.column.circs_lost.label'),
                'render' : function(my) { return my.circ_counts.lost; }
            }
        ]);
        g.list.init(
            {
                'columns' : columns,
                'retrieve_row' : function(params) {
                    var id = params.retrieve_id;
                    var row = params.row;
                    if (typeof row.my == 'undefined') row.my = {};

                    function process_and_return() {
                        if (typeof params.on_retrieve == 'function') {
                            params.on_retrieve(row);
                        }
                        return row;
                    }

                    patron.util.retrieve_fleshed_au_via_id( ses(), id, null, function(req) {
                        row.my.au = req.getResultObject();
                        process_and_return();
                    });
                    g.network.simple_request(
                        'FM_CIRC_COUNT_RETRIEVE_VIA_USER.authoritative',
                        [ ses(), id ],
                        function(req) {
                            try {
                                var robj = req.getResultObject();
                                // robj.out / robj.overdue / robj.claims_returned / robj.long_overdue / robj.lost
                                row.my.circ_counts = robj;
                                g.flesh_count++;
                                if (g.flesh_count >= g.row_count) {
                                    $('total_out').setAttribute(
                                        'value',
                                        $('patronStrings').getFormattedString(
                                            'staff.patron.info_group.total_out.label', 
                                            [ g.total_out ]
                                        )
                                    );
                                    $('total_overdue').setAttribute(
                                        'value',
                                        $('patronStrings').getFormattedString(
                                            'staff.patron.info_group.total_overdue.label', 
                                            [ g.total_overdue ]
                                        )
                                    );
                                }
                                process_and_return();
                            } catch(E) {
                                alert('Error in info_group.js, circ count retrieve(): ' + E);
                            }
                        }
                    );

                    process_and_return();
                },
                'on_select' : function(ev) {
                    JSAN.use('util.functional');
                    var sel = g.list.retrieve_selection();
                    g.sel_list = util.functional.map_list(
                        sel,
                        function(o) { return o.getAttribute('retrieve_id'); }
                    );
                    if (g.sel_list.length > 0) {
                        $('retrieve_p').disabled = false;
                        $('retrieve_p').setAttribute('disabled','false');
                        if (g.sel_list.length > 1) {
                            $('merge_p').disabled = false;
                            $('merge_p').setAttribute('disabled','false');
                        }
                        $('clone').disabled = false;
                        $('clone').setAttribute('disabled','false');
                        $('remove').disabled = false;
                        $('remove').setAttribute('disabled','false');
                        $('move').disabled = false;
                        $('move').setAttribute('disabled','false');
                    } else {
                        $('retrieve_p').disabled = true;
                        $('retrieve_p').setAttribute('disabled','true');
                        $('merge_p').disabled = true;
                        $('merge_p').setAttribute('disabled','true');
                        $('clone').disabled = true;
                        $('clone').setAttribute('disabled','true');
                        $('remove').disabled = true;
                        $('remove').setAttribute('disabled','true');
                        $('move').disabled = true;
                        $('move').setAttribute('disabled','true');
                    }
                }
            }
        );
        $('list_actions').appendChild( g.list.render_list_actions() );
        g.list.set_list_actions();
        $('retrieve_p').disabled = true;
        $('retrieve_p').setAttribute('disabled','true');
        $('merge_p').disabled = true;
        $('merge_p').setAttribute('disabled','true');
        $('clone').disabled = true;
        $('clone').setAttribute('disabled','true');
        $('remove').disabled = true;
        $('remove').setAttribute('disabled','true');
        $('move').disabled = true;
        $('move').setAttribute('disabled','true');
        setTimeout( function() { $('patron_list').focus(); }, 0 );
    } catch(E) {
        alert('Error in info_group.js, tree_init(): ' + E);
    }
}

function refresh() {
    try {
        retrieve_money_summaries();
        retrieve_group_members();
    } catch(E) {
        alert('Error in info_group.js, refresh(): ' + E);
    }
}

function retrieve_group_members() {
    try {
        JSAN.use('util.functional'); JSAN.use('patron.util');
        g.group_members = [];
        var robj = g.network.simple_request(
            'FM_AU_LIST_RETRIEVE_VIA_GROUP.authoritative',
            [ ses(), g.patron.usrgroup() ]
        );
        if ((robj == null) || (typeof robj.ilsevent != 'undefined') ) throw(robj);
        var ids = util.functional.filter_list( robj, function(o) { return o != g.patron_id; });
        g.row_count = ids.length + 1;
        g.flesh_count = 0;
        g.total_out = 0;
        g.total_overdue = 0;

        g.list.clear();

        var funcs = [];

            function gen_func(r) {
                return function() {
                    g.list.append( {
                        'retrieve_id' : r, 
                        'row' : {
                            'my' : {
                                'balance_owed' : g.group_owed[r]
                            }
                         }
                    } );
                }
            }

        funcs.push( gen_func(g.patron_id) );
        for (var i = 0; i < ids.length; i++) {
            funcs.push( gen_func(ids[i]) );
        }
        JSAN.use('util.exec'); var exec = new util.exec(4);
        exec.on_error = function(E) { alert('Error in info_group.js, retrieve_group_members chain exec: ' + E); }
        exec.chain( funcs );

    } catch(E) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.info_group.retrieve_group_members.failure'),E);
    }
}

function retrieve_patron() {
    try {
        if (! g.sel_list ) return;
        if (typeof window.xulG == 'object' && typeof window.xulG.new_patron_tab == 'function') {
            for (var i = 0; i < g.sel_list.length; i++) {    
                try {
                    window.xulG.new_patron_tab(
                        { 'tab_name' : $("patronStrings").getString('staff.patron.info_group.retrieve_patron.tab_name') }, 
                        { 
                            'id' : g.sel_list[i],
                            'url_prefix' : xulG.url_prefix,
                            'new_tab' : xulG.new_tab,
                            'set_tab' : xulG.set_tab
                        }
                    );
                } catch(E) {
                    g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.info_group.retrieve_patron.failed_retrieving_patron'),E);
                }
            }
        }
    } catch(E) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.info_group.retrieve_patron.failed_retrieving_patrons'),E);
    }
}

function merge_patrons() {
    try {
        if (! g.sel_list ) return;
        JSAN.use('patron.util'); 
        var result = patron.util.merge(g.sel_list);
        if (result) {
            if (result != g.patron_id && g.sel_list.indexOf( g.patron_id ) != -1) {
                xulG.set_patron_tab(
                    { 'tab_name' : $("patronStrings").getString('staff.patron.info_group.retrieve_patron.tab_name') }, 
                    {
                        'id' : result
                    } 
                );
            } else {
                refresh();
            }
        }
    } catch(E) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.info_group.merge_patrons.failed_merging_patrons'),E);
    }
}

function clone_patron() {
    if (! g.sel_list ) return;
    try {
        for (var i = 0; i < g.sel_list.length; i++) {    
            var loc = xulG.url_prefix('XUL_REMOTE_BROWSER'); 
                //+ '?url=' + window.escape( urls.XUL_PATRON_EDIT + '?ses=' 
                //+ window.escape( ses() ) + '&clone=' + g.sel_list[i] );
            if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') xulG.new_tab(
                loc, 
                {}, 
                { 
                    'url' : urls.XUL_PATRON_EDIT, // + '?ses=' + window.escape(ses()) + '&clone=' + g.sel_list[i],
                    'show_print_button' : true , 
                    'tab_name' : $("patronStrings").getString('staff.patron.info_group.clone_patron.register_clone.tab_name'),
                    'passthru_content_params' : {
                        'ses' : ses(),
                        'clone' : g.sel_list[i],
                        'spawn_search' : spawn_search,
                        'spawn_editor' : spawn_editor,
                        'on_save' : function(p) { patron.util.work_log_patron_edit(p); refresh(); },
                        'url_prefix' : xulG.url_prefix,
                        'new_tab' : xulG.new_tab,
                    },
                    'url_prefix' : xulG.url_prefix,
                    'new_tab' : xulG.new_tab,
                    'lock_tab' : xulG.lock_tab,
                    'unlock_tab' : xulG.unlock_tab
                }
            );
        }
    } catch(E) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.info_group.clone_patron.error_spawning_editors'),E);
    }
}

function spawn_editor(p) {
    var url = urls.XUL_PATRON_EDIT;
    var passthru = {
        'spawn_search' : spawn_search,
        'spawn_editor' : spawn_editor,
        'on_save' : function(p) { patron.util.work_log_patron_edit(p); refresh(); },
        'url_prefix' : xulG.url_prefix,
        'new_tab' : xulG.new_tab,
    };
    for (var i in p) {
        passthru[i] = p[i];
    }
    var loc = xulG.url_prefix('XUL_REMOTE_BROWSER'); // + '?url=' + window.escape( url );
    if (typeof window.xulG == 'object' && typeof window.xulG.new_tab == 'function') xulG.new_tab(
        loc, 
        {}, 
        { 
            'url' : url,
            'show_print_button' : true , 
            'tab_name' : $("patronStrings").getString('staff.patron.info_group.spawn_editor.editing_patron'),
            'passthru_content_params' : passthru,
            'url_prefix' : xulG.url_prefix,
            'new_tab' : xulG.new_tab,
            'lock_tab' : xulG.lock_tab,
            'unlock_tab' : xulG.unlock_tab
        }
    );

}

function spawn_search(s) {
    try {
        g.error.sdump('D_TRACE', 'Editor would like to search for: ' + js2JSON(s) ); 
        if (typeof window.xulG == 'object' && typeof window.xulG.new_patron_tab == 'function') 
            xulG.new_patron_tab( {}, {'doit':1,'query':s} );
    } catch(E) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.info_group.spawn_search'),E);
    }
}

function remove_patron() {
    if (! g.sel_list ) return;
    var msg = '';
    for (var i = 0 ; i < g.sel_list.length; i++)
        if (g.sel_list[i] == g.patron_id)
            msg = $("patronStrings").getString('staff.patron.info_group.remove_patron.warning_message');
            
    var c = window.confirm($("patronStrings").getFormattedString('staff.patron.info_group.remove_patron.warning_message_confirm', [msg]));
    if (c) {
        for (var i = 0; i < g.sel_list.length; i++) {    
            var robj = g.network.simple_request('FM_AU_NEW_USERGROUP', [ ses(), g.sel_list[i], get_db_true() ]);
            if (typeof robj.ilsevent != 'undefined') {
                g.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.info_group.remove_patron.error_removing_patron', [g.sel_list[i]]), robj);
            }
        }
        alert($("patronStrings").getString('staff.patron.info_group.remove_patron.patrons_removed_from_group')); 
        /* FIXME - xulrunner bug if this alert comes after refresh? */
        /* that's okay, because now that we're on a distributed database, we want human delay to mitigate race conditions */
        refresh();
    } else {
        alert($("patronStrings").getString('staff.patron.info_group.remove_patron.patrons_not_removed_from_group'));
    }
}

function link_patron(direction) {
    try {
        if (! g.sel_list ) { g.sel_list = []; g.sel_list[0] = g.patron_id; }
        if (direction == null) throw($("patronStrings").getString('staff.patron.info_group.link_patron.null_not_allowed'));
        var first_msg; var second_msg;
        switch(direction) {
            case true:
                first_msg = "-->";
                break;
            case false:
                first_msg = "<--";
                break;
            default:
                throw($("patronStrings").getString('staff.patron.info_group.link_patron.invalid_parameter'));
                break;
        }
        var barcode = window.prompt($("patronStrings").getString('staff.patron.info_group.link_patron.scan_patron_barcode'),'',first_msg);
        if (!barcode) return;
        JSAN.use('patron.util');
        var patron_b = patron.util.retrieve_fleshed_au_via_barcode(ses(),barcode);
        if (typeof patron_b.ilsevent != 'undefined') throw(patron_b);

        if (g.sel_list.length == 0) g.sel_list[0] = g.patron_id;
        for (var i = 0; i < g.sel_list.length; i++) {    

            var patron_a = patron.util.retrieve_fleshed_au_via_id(ses(),g.sel_list[i],null);
            if (typeof patron_a.ilsevent != 'undefined') throw(patron_a);
            switch(direction) {
                case true:
                    second_msg = $("patronStrings").getFormattedString('staff.patron.info_group.link_patron.move_patron_to_new_usergroup',[patron_a.card().barcode(), patron_b.card().barcode()]);
                    break;
                case false:
                    second_msg = $("patronStrings").getFormattedString('staff.patron.info_group.link_patron.move_patron_to_new_usergroup',[patron_b.card().barcode(), patron_a.card().barcode()]);
                    break;
            }

            var horizontal_interface = String( g.data.hash.aous['ui.circ.patron_summary.horizontal'] ) == 'true';
            var top_xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: auto"><description>' + second_msg + '</description>';
            top_xml += '<hbox><spacer flex="1"/><button label="'+$("patronStrings").getString('staff.patron.info_group.link_patron.move.label')+'"';
            top_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.info_group.link_patron.move.accesskey')+'" name="fancy_submit"/>';
            top_xml += '<button label="'+$("patronStrings").getString('staff.patron.info_group.link_patron.done.label')+'"';
            top_xml += ' accesskey="'+$("patronStrings").getString('staff.patron.info_group.link_patron.done.accesskey')+'" name="fancy_cancel"/></hbox></vbox>';
            var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: vertical">';
            if (horizontal_interface) {
                xml += '<vbox flex="1">';
            } else {
                xml += '<hbox flex="1">';
            }
            /************/
            xml += '<vbox flex="1">';
            xml += '<hbox><spacer flex="1"/>';
            if (direction) {
                xml += '<image src="/xul/server/skin/media/images/patron_right_arrow.png"/>';
            } else {
                xml += '<image src="/xul/server/skin/media/images/patron_left_arrow.png"/>';
            }
            xml += '</hbox>';
            xml += '<iframe style="min-height: 100px" flex="1" src="' + xulG.url_prefix('XUL_PATRON_SUMMARY');
            xml += '?show_name=1&amp;id=' + g.sel_list[i] + '" oils_force_external="true"/>';
            xml += '</vbox>';
            xml += '<vbox flex="1">';
            xml += '<hbox>';
            if (direction) {
                xml += '<image src="/xul/server/skin/media/images/patron_right_arrow.png"/>';
            } else {
                xml += '<image src="/xul/server/skin/media/images/patron_left_arrow.png"/>';
            }
            xml += '<spacer flex="1"/></hbox>';
            xml += '<iframe style="min-height: 100px" flex="1" src="' + xulG.url_prefix('XUL_PATRON_SUMMARY');
            xml += '?show_name=1&amp;id=' + patron_b.id() + '" oils_force_external="true"/>';
            xml += '</vbox>';
            /************/
            if (horizontal_interface) {
                xml += '</vbox>';
            } else {
                xml += '</hbox>';
            }
            xml += '</vbox>';
            
            var bot_xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: auto"><hbox>';
            bot_xml += '</hbox></vbox>';

            //g.data.temp_top = top_xml; g.data.stash('temp_top');
            //g.data.temp_mid = xml; g.data.stash('temp_mid');
            //g.data.temp_bot = bot_xml; g.data.stash('temp_bot');
            JSAN.use('util.window'); var win = new util.window();
            var fancy_prompt_data = win.open(
                urls.XUL_FANCY_PROMPT,
                //+ '?xml_in_stash=temp_mid'
                //+ '&top_xml_in_stash=temp_top'
                //+ '&bottom_xml_in_stash=temp_bot'
                //+ '&title=' + window.escape('Move Patron into a Usergroup'),
                'fancy_prompt', 'chrome,resizable,modal,width=700,height=500',
                { 'xml' : xml, 'top_xml' : top_xml, 'bottom_xml' : bot_xml, 'title' : $("patronStrings").getString('staff.patron.info_group.link_patron.move_patron_to_usergroup')}
            );
            if (fancy_prompt_data.fancy_status == 'incomplete') { continue; }
            else {
                var patron_c;
                switch(direction) {
                    case true:
                        patron_a.usrgroup( patron_b.usrgroup() );
                        patron_a.ischanged( '1' );
                        patron_c = patron_a;
                    break;
                    case false:
                        patron_b.usrgroup( patron_a.usrgroup() );
                        patron_b.ischanged( '1' );
                        patron_c = patron_b;
                    break;
                }
                var robj = g.network.simple_request('FM_AU_UPDATE',[ ses(), patron_c ]);
                if (typeof robj.ilsevent != 'undefined') g.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.info_group.link_patron.error_linking_patron', [g.sel_list[i]]), robj);
            }
        }
        alert($("patronStrings").getString('staff.patron.info_group.link_patron.usergroups_updated'));
        refresh();
    } catch(E) {
        g.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.info_group.link_patron.error_linking_patrons'),E);
        refresh();
    }
}


