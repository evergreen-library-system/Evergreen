dump('entering serial/manage_dists.js\n');
// vim:et:sw=4:ts=4:

if (typeof serial == 'undefined') serial = {};
serial.manage_dists = function (params) {
    try {
        JSAN.use('util.error'); this.error = new util.error();
    } catch(E) {
        dump('serial/manage_dists: ' + E + '\n');
    }
};

serial.manage_dists.prototype = {

    'map_tree' : {},
    'map_sdist' : {},
    'map_sstr' : {},
    'sel_list' : [],
    'funcs' : [],
    'editor_indexes' : { 'sdist' : 1, 'sstr' : 2, 'sbsum' : 3, 'sssum' : 4, 'sisum' : 5 },

    'ids_from_sel_list' : function(type) {
        var obj = this;
        JSAN.use('util.functional');

        var list = util.functional.map_list(
            util.functional.filter_list(
                obj.sel_list,
                function (o) {
                    return o.split(/_/)[0] == type;
                }
            ),
            function (o) {
                return o.split(/_/)[1];
            }
        );

        return list;
    },

    'editor_init' : function(type, mode, params) {
        var obj = this;
        try {
            $('serial_manage_dists_editor_deck').selectedIndex = obj.editor_indexes[type];
            var editor_type = type + '_editor';
            if (typeof obj[editor_type] == 'undefined') {
                JSAN.use('serial.' + editor_type);
                obj[editor_type] = new serial[editor_type](); 
            }

            params.do_edit = true;
            params.handle_update = true;
            if (mode == 'add') {
                params.trigger_refresh = true;
                params.refresh_command = function () {obj.refresh_list();};
            }
            obj[editor_type].init(params);
        } catch(E) {
            obj.error.standard_unexpected_error_alert('editor_init() error',E);
        }
    },

    'do_delete' : function(type, method, overridable_events) {
        var obj = this;
        try {
            JSAN.use('util.functional');

            var list = util.functional.filter_list(
                obj.sel_list,
                function (o) {
                    return o.split(/_/)[0] == type;
                }
            );

            list = util.functional.map_list(
                list,
                function (o) {
                    return JSON2js( js2JSON( obj['map_' + type][ type + '_' + o.split(/_/)[1] ] ) );
                }
            );

            //TODO: proper messages
            var delete_msg;
            if (list.length != 1) {
                delete_msg = document.getElementById('serialStrings').getFormattedString('staff.serial.manage_dists.delete_' + type + '.confirm.plural', [list.length]);
            } else {
                delete_msg = document.getElementById('serialStrings').getString('staff.serial.manage_dists.delete_' + type + '.confirm');
            }
            var r = obj.error.yns_alert(
                    delete_msg,
                    document.getElementById('serialStrings').getString('staff.serial.manage_dists.delete_' + type + '.title'),
                    document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_items.delete'),
                    document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_items.cancel'),
                    null,
                    document.getElementById('commonStrings').getString('common.confirm')
            );

            if (r == 0) {
                for (var i = 0; i < list.length; i++) {
                    list[i].isdeleted('1');
                }
                var robj = obj.network.request(
                    'open-ils.serial', 
                    method, 
                    [ ses(), list, true ],
                    null,
                    {
                        'title' : document.getElementById('serialStrings').getString('staff.serial.manage_dists.delete_' + type + '.override'),
                        'overridable_events' : overridable_events
                    }
                );
                if (robj == null) throw(robj);
                if (typeof robj.ilsevent != 'undefined') {
                    if (robj.ilsevent != 0) {
                        var overridable = false;
                        for (i = 0; i < overridable_events.length; i++) {
                            if (overridable_events[i] == robj.ilsevent) {
                                overridable = true;
                                break;
                            }
                        }
                        if (!overridable) throw(robj);
                    }
                }
                obj.refresh_list();
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert(document.getElementById('serialStrings').getString('staff.serial.manage_dists.delete.error'),E);
            obj.refresh_list();
        }
    },

    'init' : function( params ) {

        try {
            var obj = this;

            obj.docid = params.docid;

            JSAN.use('util.network'); obj.network = new util.network();
            JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
            JSAN.use('util.controller'); obj.controller = new util.controller();
            obj.controller.init(
                {
                    control_map : {
                        'save_columns' : [ [ 'command' ], function() { obj.list.save_columns(); } ],
                        'sel_clip' : [
                            ['command'],
                            function() { obj.list.clipboard(); }
                        ],
                        'cmd_broken' : [
                            ['command'],
                            function() { 
                                alert(document.getElementById('commonStrings').getString('common.unimplemented'));
                            }
                        ],
                        'cmd_show_my_libs' : [
                            ['command'],
                            function() { 
                                obj.show_my_libs(); 
                            }
                        ],
                        'cmd_clear' : [
                            ['command'],
                            function() {
                                obj.map_tree = {};
                                obj.list.clear();
                            }
                        ],
                        'cmd_add_sstr' : [
                            ['command'],
                            function() {
                                try {
                                    var list = obj.ids_from_sel_list('sdist');
                                    if (list.length == 0) list = obj.ids_from_sel_list('sstr-group');
                                    if (list.length == 0) return;

                                    /*TODO: permission check?
                                    //populate 'list' with owning_libs of subs, TODO
                                    var edit = 0;
                                    try {
                                        edit = obj.network.request(
                                            api.PERM_MULTI_ORG_CHECK.app,
                                            api.PERM_MULTI_ORG_CHECK.method,
                                            [ 
                                                ses(), 
                                                obj.data.list.au[0].id(), 
                                                list,
                                                [ 'CREATE_COPY' ]
                                            ]
                                        ).length == 0 ? 1 : 0;
                                    } catch(E) {
                                        obj.error.sdump('D_ERROR','batch permission check: ' + E);
                                    }

                                    if (edit==0) return; // no read-only view for this interface */
                                    var new_sstr = new sstr();
                                    new_sstr.distribution(list[0]);//TODO: add multiple at once support?
                                    new_sstr.isnew(1);
                                    var params = {};
                                    params.sstrs = [new_sstr];
                                    obj.editor_init('sstr', 'add', params);
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert($('serialStrings').getString('staff.serial.manage_dists.add.error'),E);
                                }
                            }
                        ],
                        'cmd_delete_sstr' : [
                            ['command'],
                            function() {
                                var overridable_events = [ //TODO: proper overrides
                                ];
                                obj.do_delete('sstr', 'open-ils.serial.stream.batch.update', overridable_events);
                            }
                        ],
                        'cmd_mark_library' : [
                            ['command'],
                            function() {
                                try {
                                    var list = obj.ids_from_sel_list('aou');
                                    if (list.length == 1) {
                                        obj.data.marked_library = { 'lib' : list[0], 'docid' : obj.docid };
                                        obj.data.stash('marked_library');
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.mark_library.alert'));
                                    } else {
                                        obj.error.yns_alert(
                                                document.getElementById('catStrings').getString('staff.cat.copy_browser.mark_library.prompt'),
                                                document.getElementById('catStrings').getString('staff.cat.copy_browser.mark_library.title'),
                                                document.getElementById('commonStrings').getString('common.ok'),
                                                null,
                                                null,
                                                document.getElementById('commonStrings').getString('common.confirm')
                                                );
                                    }
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert('manage_dists.js -> mark library',E);
                                }
                            }
                        ],

                        'cmd_mark_distribution' : [
                            ['command'],
                            function() {
                                try {
                                    var list = obj.ids_from_sel_list('sdist');
                                    if (list.length == 1) {
                                        obj.data.marked_distribution = list[0];
                                        obj.data.stash('marked_distribution');
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.mark_volume.alert'));
                                    } else {
                                        obj.error.yns_alert(
                                                document.getElementById('catStrings').getString('staff.cat.copy_browser.mark_volume.prompt'),
                                                document.getElementById('catStrings').getString('staff.cat.copy_browser.mark_volume.title'),
                                                document.getElementById('commonStrings').getString('common.ok'),
                                                null,
                                                null,
                                                document.getElementById('commonStrings').getString('common.confirm')
                                                );
                                    }
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert('manage_dists.js -> mark distribution',E);
                                }
                            }
                        ],
                        'cmd_transfer_distribution' : [
                            ['command'],
                            function() {
                                try {
                                    obj.data.stash_retrieve();
                                    if (!obj.data.marked_library) {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer_volume.alert'));
                                        return;
                                    }
                                    
                                    var list = obj.ids_from_sel_list('sdist');

                                    JSAN.use('util.functional');

                                    var sdist_list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return obj.map_sdist[ 'sdist_' + o ].start_date();
                                        }
                                    ).join(document.getElementById('commonStrings').getString('common.grouping_string'));

                                    var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: auto">';
                                    xml += '<description>';
                                    xml += document.getElementById('catStrings').getFormattedString('staff.cat.copy_browser.transfer.prompt', [sdist_list, obj.data.hash.aou[ obj.data.marked_library.lib ].shortname()]);
                                    xml += '</description>';
                                    xml += '<hbox><button label="' + document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.submit.label') + '" name="fancy_submit"/>';
                                    xml += '<button label="' 
                                        + document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.cancel.label') 
                                        + '" accesskey="' 
                                        + document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.cancel.accesskey') 
                                        + '" name="fancy_cancel"/></hbox>';
                                    xml += '<iframe style="overflow: scroll" flex="1" src="' + urls.XUL_BIB_BRIEF + '?docid=' + obj.data.marked_library.docid + '" oils_force_external="true"/>';
                                    xml += '</vbox>';
                                    JSAN.use('OpenILS.data');
                                    var data = new OpenILS.data(); data.init({'via':'stash'});
                                    //data.temp_transfer = xml; data.stash('temp_transfer');
                                    JSAN.use('util.window'); var win = new util.window();
                                    var fancy_prompt_data = win.open(
                                        urls.XUL_FANCY_PROMPT,
                                        //+ '?xml_in_stash=temp_transfer'
                                        //+ '&title=' + window.escape('Volume Transfer'),
                                        'fancy_prompt', 'chrome,resizable,modal,width=500,height=300',
                                        {
                                            'xml' : xml,
                                            'title' : document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.title')
                                        }
                                    );

                                    if (fancy_prompt_data.fancy_status == 'incomplete') {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.incomplete'));
                                        return;
                                    }

                                    var robj = obj.network.simple_request(
                                        'FM_ACN_TRANSFER', 
                                        [ ses(), { 'docid' : obj.data.marked_library.docid, 'lib' : obj.data.marked_library.lib, 'distributions' : list } ],
                                        null,
                                        {
                                            'title' : document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.override.failure'),
                                            'overridable_events' : [
                                                1208, // TITLE_LAST_COPY
                                                1219, // COPY_REMOTE_CIRC_LIB
                                            ],
                                        }
                                    );

                                    if (typeof robj.ilsevent != 'undefined') {
                                        if (robj.ilsevent == 1221) { // ORG_CANNOT_HAVE_VOLS
                                            alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.ineligible_destination'));
                                        } else {
                                            throw(robj);
                                        }
                                    } else {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.success'));
                                    }

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.unexpected_error'),E);
                                }
                                obj.refresh_list();
                            }
                        ],

                        'cmd_transfer_sstrs' : [
                            ['command'],
                            function() {
                                try {
                                    obj.data.stash_retrieve();
                                    if (!obj.data.marked_distribution) {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer_items.missing_volume'));
                                        return;
                                    }
                                    
                                    JSAN.use('util.functional');

                                    var list = obj.ids_from_sel_list('sstr');
                                    var distribution = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ obj.data.marked_distribution ]);

                                    JSAN.use('cat.util'); cat.util.transfer_copies( { 
                                        'distribution_ids' : list, 
                                        'docid' : distribution.record(),
                                        'distribution_label' : distribution.start_date(),
                                        'owning_lib' : distribution.owning_lib(),
                                    } );

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer_items.unexpected_error'),E);
                                }
                                obj.refresh_list();
                            }
                        ],
                        'cmd_refresh_list' : [
                            ['command'],
                            function() {
                                obj.refresh_list();
                            }
                        ],
/*dbw2                      'sel_distribution_details' : [
                            ['command'],
                            function() {
                                JSAN.use('util.functional');

                                var list = util.functional.filter_list(
                                    obj.sel_list,
                                    function (o) {
                                        return o.split(/_/)[0] == 'sstr';
                                    }
                                );

                                list = util.functional.map_list(
                                    list,
                                    function (o) {
                                        return o.split(/_/)[1];
                                    }
                                );
    
                                JSAN.use('circ.util');
                                for (var i = 0; i < list.length; i++) {
                                    circ.util.show_copy_details( list[i] );
                                }
                            }
                        ],
                        'cmd_edit_sstrs' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');

                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'sstr';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return o.split(/_/)[1];
                                        }
                                    );

                                    JSAN.use('cat.util'); cat.util.spawn_copy_editor( { 'copy_ids' : list, 'edit' : 1 } );
                                    obj.refresh_list();

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.edit_items.error'),E);
                                }
                            }
                        ], dbw2*/

/*dbw2                      'cmd_print_spine_labels' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');
                                    
                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'sstr';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return obj.map_sstr[ o ];
                                        }
                                    );

                                    obj.data.temp_barcodes_for_labels = util.functional.map_list( list, function(o){return o.barcode();}) ; 
                                    obj.data.stash('temp_barcodes_for_labels');
                                    xulG.new_tab(
                                        xulG.url_prefix('XUL_SPINE_LABEL'),
                                        { 'tab_name' : document.getElementById('catStrings').getString('staff.cat.copy_browser.print_spine.tab') },
                                        {}
                                    );
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.print_spine.error'),E);
                                }
                            }
                        ]
                        dbw2*/
                    }
                }
            );

            obj.list_init(params);

            obj.org_ids = obj.network.simple_request('FM_SDIST_AOU_IDS_RETRIEVE_VIA_RECORD_ID.authoritative',[ obj.docid ]);
            if (typeof obj.org_ids.ilsevent != 'undefined') throw(obj.org_ids);
            JSAN.use('util.functional'); 
            obj.org_ids = util.functional.map_list( obj.org_ids, function (o) { return Number(o); });

            var org = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
            //obj.show_libs( org );

            //obj.show_my_libs();

            JSAN.use('util.file'); JSAN.use('util.widgets');

            var file; var list_data; var ml; 

            file = new util.file('offline_ou_list'); 
            if (file._file.exists()) {
                list_data = file.get_object(); file.close();
                for (var i = 0; i < list_data[0].length; i++) { // make sure all entries are enabled
                    list_data[0][i][2] = false;
                }
                ml = util.widgets.make_menulist( list_data[0], list_data[1] );
                ml.setAttribute('id','sdist_lib_menu'); document.getElementById('serial_dist_lib_menu').appendChild(ml);
                //TODO: class this menu properly
                for (var i = 0; i < obj.org_ids.length; i++) {
                    ml.getElementsByAttribute('value',obj.org_ids[i])[0].setAttribute('class','has_distributions');
                }
                ml.firstChild.addEventListener(
                    'popupshown',
                    function(ev) {
                        document.getElementById('legend').setAttribute('hidden','false');
                    },
                    false
                );
                ml.firstChild.addEventListener(
                    'popuphidden',
                    function(ev) {
                        document.getElementById('legend').setAttribute('hidden','true');
                    },
                    false
                );
                ml.addEventListener(
                    'command',
                    function(ev) {
                        if (document.getElementById('refresh_button')) document.getElementById('refresh_button').focus(); 
                        JSAN.use('util.file'); var file = new util.file('manage_dists_prefs.'+obj.data.server_unadorned);
                        util.widgets.save_attributes(file, { 'sdist_lib_menu' : [ 'value' ], 'show_sdists' : [ 'checked' ], 'show_sdist_groups' : [ 'checked' ] });
                        obj.refresh_list();
                    },
                    false
                );
            } else {
                throw(document.getElementById('catStrings').getString('staff.cat.copy_browser.missing_library') + '\n');
            }

            file = new util.file('manage_dists_prefs.'+obj.data.server_unadorned);
            util.widgets.load_attributes(file);
            obj.default_lib = ml.getAttribute('value');
            ml.value = obj.default_lib;
            if (! obj.default_lib) {
                obj.default_lib = org.id();
                ml.setAttribute('value',obj.default_lib);
                ml.value = obj.default_lib;
            }

            document.getElementById('show_sdists').addEventListener(
                'command',
                function(ev) {
                    JSAN.use('util.file'); var file = new util.file('manage_dists_prefs.'+obj.data.server_unadorned);
                    util.widgets.save_attributes(file, { 'sdist_lib_menu' : [ 'value' ], 'show_sdists' : [ 'checked' ], 'show_sdist_groups' : [ 'checked' ] });
                },
                false
            );

            document.getElementById('show_sdist_groups').addEventListener(
                'command',
                function(ev) {
                    JSAN.use('util.file'); var file = new util.file('manage_dists_prefs.'+obj.data.server_unadorned);
                    util.widgets.save_attributes(file, { 'sdist_lib_menu' : [ 'value' ], 'show_sdists' : [ 'checked' ], 'show_sdist_groups' : [ 'checked' ] });
                },
                false
            );

            obj.show_my_libs( obj.default_lib );

            JSAN.use('util.exec'); var exec = new util.exec(20); exec.timer(obj.funcs,100);

            obj.toggle_actions(); // disable menus initially

        } catch(E) {
            this.error.standard_unexpected_error_alert('serial/manage_dists.init: ',E);
        }
    },

    'show_my_libs' : function(org) {
        var obj = this;
        try {
            if (!org) {
                org = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
            } else {
                if (typeof org != 'object') org = obj.data.hash.aou[ org ];
            }
            obj.show_libs( org, false );
        } catch(E) {
            alert(E);
        }
    },

    'show_libs' : function(start_aou,show_open) {
        var obj = this;
        try {
            if (!start_aou) throw('show_libs: Need a start_aou');
            JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});
            JSAN.use('util.functional'); 

            var parents = [];
            var temp_aou = start_aou;
            while ( temp_aou.parent_ou() ) {
                temp_aou = obj.data.hash.aou[ temp_aou.parent_ou() ];
                parents.push( temp_aou );
            }
            parents.reverse();

            for (var i = 0; i < parents.length; i++) {
                obj.funcs.push(
                    function(o,p) {
                        return function() { 
                            obj.append_org(o,p,{'container':'true','open':'true'}); 
                        };
                    }(parents[i], obj.data.hash.aou[ parents[i].parent_ou() ])
                );
            }

            obj.funcs.push(
                function(o,p) {
                    return function() { obj.append_org(o,p); };
                }(start_aou,obj.data.hash.aou[ start_aou.parent_ou() ])
            );

            obj.funcs.push(
                function() {
                    if (start_aou.children()) {
                        var x = obj.map_tree[ 'aou_' + start_aou.id() ];
                        x.setAttribute('container','true');
                        if (show_open) x.setAttribute('open','true');
                        for (var i = 0; i < start_aou.children().length; i++) {
                            obj.funcs.push(
                                function(o,p) {
                                    return function() { obj.append_org(o,p); };
                                }( start_aou.children()[i], start_aou )
                            );
                        }
                    }
                }
            );

        } catch(E) {
            alert(E);
        }
    },

    'on_select' : function(list,twisty) {
        var obj = this;
        var sel_lists = {};

        for (var i = 0; i < list.length; i++) {
            var row_type = list[i].split('_')[0];
            var id = list[i].split('_')[1];

            if (!sel_lists[row_type]) sel_lists[row_type] = [];
            sel_lists[row_type].push(id);

            switch(row_type) {
                case 'aou' : obj.on_click_aou(id,twisty); break;
                case 'sdist' : obj.on_select_sdist(id,twisty); break;
                default: break;
            }
        }

        if (!obj.focused_node_retrieve_id) return;

        var row_type = obj.focused_node_retrieve_id.split('_')[0];
        var id = obj.focused_node_retrieve_id.split('_')[1];

        if (sel_lists[row_type]) { // the type focused is in the selection (usually the case)
            switch(row_type) {
                case 'aou' : obj.on_click_aou(id,twisty); break;
                default: if (obj['on_click_' + row_type]) obj['on_click_' + row_type](sel_lists[row_type],twisty);
            }
        }
    },

    'on_select_sdist' : function(sdist_id,twisty) {
        var obj = this;
        try {
            var sdist_tree = obj.map_sdist[ 'sdist_' + sdist_id ];
            obj.funcs.push( function() { 
                document.getElementById('cmd_refresh_list').setAttribute('disabled','true'); 
                document.getElementById('sdist_lib_menu').setAttribute('disabled','true'); 
            } );
            if (sdist_tree.basic_summary()) {
                obj.funcs.push(
                    function(c,a) {
                        return function() {
                            obj.append_member(c,a,[],'sbsum', false);
                        }
                    }( sdist_tree.basic_summary(), sdist_tree )
                );
            }
            if (sdist_tree.supplement_summary()) {
                obj.funcs.push(
                    function(c,a) {
                        return function() {
                            obj.append_member(c,a,[],'sssum', false);
                        }
                    }( sdist_tree.supplement_summary(), sdist_tree )
                );
            }
            if (sdist_tree.index_summary()) {
                obj.funcs.push(
                    function(c,a) {
                        return function() {
                            obj.append_member(c,a,[],'sisum', false);
                        }
                    }( sdist_tree.index_summary(), sdist_tree )
                );
            }
            if (sdist_tree.streams()) {
                for (var i = 0; i < sdist_tree.streams().length; i++) {
                    obj.funcs.push(
                        function(c,a) {
                            return function() {
                                obj.append_member(c,a,[],'sstr', true);
                            }
                        }( sdist_tree.streams()[i], sdist_tree )
                    )
                }
            }
            /* TODO: template editing would be convenient here, but a little too confusing
            // add template nodes
            var same_templates;
            var has_bind_template;
            if (sdist_tree.receive_unit_template()) {
                if (sdist_tree.bind_unit_template()) {
                    has_bind_template = true;                    
                    if (sdist_tree.receive_unit_template().id() == sdist_tree.bind_unit_template().id()) {
                        same_templates = true;
                        obj.funcs.push(
                            function(c,a) {
                                return function() {
                                    obj.append_member(c,a,[],'act', false, 'Receive/Bind Unit Template');
                                }
                            }( sdist_tree.receive_unit_template(), sdist_tree )
                        )
                    }
                }

                if (!same_templates) {
                    obj.funcs.push(
                        function(c,a) {
                            return function() {
                                obj.append_member(c,a,[],'act', false, 'Receive Unit Template');
                            }
                        }( sdist_tree.receive_unit_template(), sdist_tree )
                    )
                }
            }
            if (has_bind_template && !same_templates) {
                obj.funcs.push(
                    function(c,a) {
                        return function() {
                            obj.append_member(c,a,[],'act', false, 'Bind Unit Template');
                        }
                    }( sdist_tree.bind_unit_template(), sdist_tree )
                )
            }
            */
            obj.funcs.push( function() { 
                document.getElementById('cmd_refresh_list').setAttribute('disabled','false'); 
                document.getElementById('sdist_lib_menu').setAttribute('disabled','false'); 
            } );
        } catch(E) {
            alert(E);
        }
    },

    'on_click_sdist' : function(sdist_ids,twisty) {
        var obj = this;
        try {
            // draw sdist editor
            if (typeof twisty == 'undefined') {
                var params = {};
                params.sdist_ids = sdist_ids;
                params.xul_id_prefix = 'sdist2';
                obj.editor_init('sdist', 'edit', params);
            }
        } catch(E) {
            alert(E);
        }
    },

    'on_click_sstr' : function(sstr_ids,twisty) {
        var obj = this;
        try {
            // draw sstr editor
            if (typeof twisty == 'undefined') {
                var params = {};
                params.sstr_ids = sstr_ids;
                obj.editor_init('sstr', 'edit', params);
            }
        } catch(E) {
            alert(E);
        }
    },

    'on_click_sbsum' : function(sbsum_ids,twisty) {
        var obj = this;
        try {
            // draw sbsum editor
            if (typeof twisty == 'undefined') {
                var params = {};
                params.sbsum_ids = sbsum_ids;
                obj.editor_init('sbsum', 'edit', params);
            }
        } catch(E) {
            alert(E);
        }
    },

    'on_click_sssum' : function(sssum_ids,twisty) {
        var obj = this;
        try {
            // draw sssum editor
            if (typeof twisty == 'undefined') {
                var params = {};
                params.sssum_ids = sssum_ids;
                obj.editor_init('sssum', 'edit', params);
            }
        } catch(E) {
            alert(E);
        }
    },

    'on_click_sisum' : function(sisum_ids,twisty) {
        var obj = this;
        try {
            // draw sisum editor
            if (typeof twisty == 'undefined') {
                var params = {};
                params.sisum_ids = sisum_ids;
                obj.editor_init('sisum', 'edit', params);
            }
        } catch(E) {
            alert(E);
        }
    },

    'on_click_aou' : function(org_id,twisty) {
        var obj = this;
        var org = obj.data.hash.aou[ org_id ];
        var default_aou = obj.data.hash.aou[obj.default_lib];
        obj.funcs.push( function() { 
            document.getElementById('cmd_refresh_list').setAttribute('disabled','true'); 
            document.getElementById('sdist_lib_menu').setAttribute('disabled','true'); 
        } );
        if (org.children()) {
            for (var i = 0; i < org.children().length; i++) {
                var child = org.children()[i];
                if (orgIsMine(default_aou,child)) {
                    obj.funcs.push(
                        function(o,p) {
                            return function() {
                                obj.append_org(o,p)
                            }
                        }(child,org)
                    );
                }
            }
        } 
        if (obj.map_sdist[ 'aou_' + org_id ]) {
            for (var i = 0; i < obj.map_sdist[ 'aou_' + org_id ].length; i++) {
                obj.funcs.push(
                    function(o,a) {
                        return function() {
                            obj.append_sdist(o,a);
                        }
                    }( org, obj.map_sdist[ 'aou_' + org_id ][i] )
                );
            }
        }
        obj.funcs.push( function() { 
            document.getElementById('cmd_refresh_list').setAttribute('disabled','false'); 
            document.getElementById('sdist_lib_menu').setAttribute('disabled','false'); 
        } );

        // remove current editor
        if (typeof twisty == 'undefined') {
            document.getElementById('serial_manage_dists_editor_deck').selectedIndex = 0;
        }
    },

    'append_org' : function (org,parent_org,params) {
        var obj = this;
        try {
            if (obj.map_tree[ 'aou_' + org.id() ]) {
                var x = obj.map_tree[ 'aou_' + org.id() ];
                if (params) {
                    for (var i in params) {
                        x.setAttribute(i,params[i]);
                    }
                }
                return x;
            }

            var data = {
                'row' : {
                    'my' : {
                        'aou' : org,
                    }
                },
                'skip_all_columns_except' : [0,1,2],
                'retrieve_id' : 'aou_' + org.id(),
                'to_bottom' : true,
                'no_auto_select' : true,
            };
        
            var sdist_tree_list;
            if ( obj.org_ids.indexOf( Number( org.id() ) ) == -1 ) {
                if ( get_bool( obj.data.hash.aout[ org.ou_type() ].can_have_vols() ) ) {
                    data.row.my.distribution_count = '0';
                } else {
                    data.row.my.distribution_count = '';
                }
            } else {
                var d_count = 0;
                sdist_tree_list = obj.network.simple_request(
                    'FM_SDIST_TREE_LIST_RETRIEVE_VIA_RECORD_ID_AND_ORG_IDS.authoritative',
                    [ ses(), obj.docid, [ org.id() ] ]
                );
                for (var i = 0; i < sdist_tree_list.length; i++) {
                    d_count++;
                    obj.map_sdist[ 'sdist_' + sdist_tree_list[i].id() ] = function(r){return r;}(sdist_tree_list[i]);
                    var streams = sdist_tree_list[i].streams();
                    for (var j = 0; j < streams.length; j++) {
                        obj.map_sstr[ 'sstr_' + streams[j].id() ] = function(r){return r;}(streams[j]);
                    }
                }
                data.row.my.distribution_count = d_count;
            }
            if (parent_org) {
                data.node = obj.map_tree[ 'aou_' + parent_org.id() ];
            }
            var nparams = obj.list.append(data);
            var node = nparams.treeitem_node;
            if (params) {
                for (var i in params) {
                    node.setAttribute(i,params[i]);
                }
            }
            obj.map_tree[ 'aou_' + org.id() ] = node;

            if (org.children()) {
                node.setAttribute('container','true');
            }

            if (parent_org) {
                if ( obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ].parent_ou() == parent_org.id() ) {
                    data.node.setAttribute('open','true');
                    obj.funcs.push( function() { obj.on_click_aou( org.id() ); } );
                }
            } else {
                obj.map_tree[ 'aou_' + org.id() ].setAttribute('open','true');
                obj.funcs.push( function() { obj.on_click_aou( org.id() ); } );
            }

            if (sdist_tree_list) {
                obj.map_sdist[ 'aou_' + org.id() ] = sdist_tree_list;
                node.setAttribute('container','true');
            }

            if (document.getElementById('show_sdists').checked) {
                obj.funcs.push( function() { obj.on_click_aou( org.id() ); } );
                node.setAttribute('open','true');
            }

        } catch(E) {
            dump(E+'\n');
            alert(E);
        }
    },

    'append_sdist' : function( org, sdist_tree, params ) {
        var obj = this;
        try {
            if (obj.map_tree[ 'sdist_' + sdist_tree.id() ]) {
                var x = obj.map_tree[ 'sdist_' + sdist_tree.id() ];
                if (params) {
                    for (var i in params) {
                        x.setAttribute(i,params[i]);
                    }
                }
                return x;
            }

            var parent_node = obj.map_tree[ 'aou_' + org.id() ];
            var data = {
                'row' : {
                    'my' : {
                        'aou' : org,
                        'sdist' : sdist_tree,
                        'distribution_count' : ''
                    }
                },
                'skip_all_columns_except' : [0,1,2],
                'retrieve_id' : 'sdist_' + sdist_tree.id(),
                'node' : parent_node,
                'to_bottom' : true,
                'no_auto_select' : true,
            };
            var nparams = obj.list.append(data);
            var node = nparams.treeitem_node;
            obj.map_tree[ 'sdist_' + sdist_tree.id() ] =  node;
            if (params) {
                for (var i in params) {
                    node.setAttribute(i,params[i]);
                }
            }
            node.setAttribute('container','true');
            if (document.getElementById('show_sdist_groups').checked) {
                node.setAttribute('open','true');
                obj.funcs.push( function() { obj.on_select_sdist( sdist_tree.id(), true ); } );
            }
            var sstr_group_node_data = {
                'row' : {
                    'my' : {
                        'label' : $('serialStrings').getString('serial.manage_dists.streams'),
                    }
                },
                'retrieve_id' : 'sstr-group_' + sdist_tree.id(),
                'node' : node,
                'to_bottom' : true,
                'no_auto_select' : true,
            };
            nparams = obj.list.append(sstr_group_node_data);
            obj.map_tree[ 'sdist_sstr_group_' + sdist_tree.id() ] =  nparams.treeitem_node;
        } catch(E) {
            dump(E+'\n');
            alert(E);
        }
    },

    'append_member' : function( item, sdist_tree, attributes, type, group, label ) {
        var obj = this;
        try {
            if (obj.map_tree[ type + '_' + sdist_tree.id() + '_' + item.id() ]) {
                var x = obj.map_tree[ type + '_' + item.id() ];
                if (attributes) {
                    for (var i in attributes) {
                        x.setAttribute(i,attributes[i]);
                    }
                }
                return x;
            }

            var parent_node;
            if (group) {
                parent_node = obj.map_tree[ 'sdist_' + type + '_group_' + sdist_tree.id() ];
            } else {
                parent_node = obj.map_tree[ 'sdist_' + sdist_tree.id() ];
            }
            var data = {
                'row' : {
                    'my' : {
                        'aou' : obj.data.hash.aou[ sdist_tree.holding_lib() ],
                        'sdist' : sdist_tree,
                        'distribution_count' : ''
                    }
                },
                'retrieve_id' : type + '_' + item.id(),
                'node' : parent_node,
                'to_bottom' : true,
                'no_auto_select' : true,
            };
            data['row']['my'][type] = item; // TODO: future optimization: get only the IDs of these leaves, then fetch the full row in 'retrieve_row'
            var nparams = obj.list.append(data);
            var node = nparams.treeitem_node;
            obj.map_tree[ type + '_' + sdist_tree.id() + '_' + item.id() ] =  node;
            if (label) {
                data['row']['my']['label'] = label;
            }
            if (attributes) {
                for (var i in attributes) {
                    node.setAttribute(i,attributes[i]);
                }
            }

        } catch(E) {
            dump(E+'\n');
            alert(E);
        }
    },

    'list_init' : function( params ) {

        try {
            var obj = this;
            
            JSAN.use('circ.util');
            var columns = [
                {
                    'id' : 'tree_location',
                    'label' : 'Location',
                    'flex' : 1, 'primary' : true, 'hidden' : false, 
                    'render' : function(my) { 
                        if (my.label) { return my.label; }
                        if (my.sstr) { return $('serialStrings').getFormattedString('serial.manage_dists.stream_num', [my.sstr.id()]); }
                        if (my.sbsum) { return $('serialStrings').getString('serial.manage_dists.sbsum'); }
                        if (my.sssum) { return $('serialStrings').getString('serial.manage_dists.sssum'); }
                        if (my.sisum) { return $('serialStrings').getString('serial.manage_dists.sisum'); }
                        if (my.sdist) { return my.sdist.label(); }
                        if (my.aou) { return $('serialStrings').getFormattedString('serial.manage_dists.library_label', [my.aou.shortname(), my.aou.name()]); }
                        return "???";
                    },
                },
                {
                    'id' : 'distribution_count',
                    'label' : $('serialStrings').getString('serial.manage_dists.distributions'),
                    'flex' : 0, 'primary' : false, 'hidden' : false, 
                    'render' : function(my) { return my.distribution_count; },
                }
            ];
            JSAN.use('util.list'); obj.list = new util.list('sdists_tree');
            obj.list.init(
                {
                    'no_auto_select' : true,
                    'columns' : columns,
                    'retrieve_row' : function(params) {

                        var row = params.row;
                        obj.funcs.push(
                            function() {

                                if (typeof params.on_retrieve == 'function') {
                                    params.on_retrieve(row);
                                }

                            }
                        );

                        return row;
                    },
                    'on_click' : function(ev) {
                        var row = {}; var col = {}; var nobj = {};
                        obj.list.node.treeBoxObject.getCellAt(ev.clientX,ev.clientY,row,col,nobj); 
                        if ((row.value == -1)||(nobj.value != 'twisty')) { return; } // on_click runs for twistys only

                        var node = obj.list.node.contentView.getItemAtIndex(row.value);
                        var list = [ node.getAttribute('retrieve_id') ];
                        if (typeof obj.on_select == 'function') {
                            obj.on_select(list,true);
                        }
                        if (typeof window.xulG == 'object' && typeof window.xulG.on_select == 'function') {
                            window.xulG.on_select(list);
                        }
                    },
                    'on_select' : function(ev) {
                        JSAN.use('util.functional');
                        
                        // get the actual node clicked to determine which editor to use
                        if (obj.list.node.view.selection.currentIndex > -1) {
                            var node = obj.list.node.contentView.getItemAtIndex(obj.list.node.view.selection.currentIndex);
                            obj.focused_node_retrieve_id = node.getAttribute('retrieve_id');
                        }

                        var sel = obj.list.retrieve_selection();
                        obj.controller.view.sel_clip.disabled = sel.length < 1;
                        obj.sel_list = util.functional.map_list(
                            sel,
                            function(o) { return o.getAttribute('retrieve_id'); }
                        );
                        obj.toggle_actions();
                        if (typeof obj.on_select == 'function') {
                            obj.on_select(obj.sel_list);
                        }
                        if (typeof window.xulG == 'object' && typeof window.xulG.on_select == 'function') {
                            window.xulG.on_select(obj.sel_list);
                        }
                    },
                }
            );

            obj.controller.render();

        } catch(E) {
            this.error.sdump('D_ERROR','serial/manage_dists.list_init: ' + E + '\n');
            alert(E);
        }
    },

    'toggle_actions' : function() {
        var obj = this;
        try {
            var found_aou = false; var found_sdist = false; var found_sstr = false; var found_sbsum = false; var found_sssum = false; var found_sisum = false; var found_sstr_group = false;
            for (var i = 0; i < obj.sel_list.length; i++) {
                var type = obj.sel_list[i].split(/_/)[0];
                switch(type) {
                    case 'aou' : 
                        found_aou = true; 
                    break;
                    case 'sdist' : found_sdist = true; break;
                    case 'sstr' : found_sstr = true; break;
                    case 'sbsum' : found_sbsum = true; break;
                    case 'sssum' : found_sssum = true; break;
                    case 'sisum' : found_sisum = true; break;
                    case 'sstr-group' : found_sstr_group = true; break;
                }
            }
            obj.controller.view.cmd_add_sstr.setAttribute('disabled','true');
            obj.controller.view.cmd_delete_sstr.setAttribute('disabled','true');
            obj.controller.view.cmd_mark_library.setAttribute('disabled','true');
            //obj.controller.view.cmd_delete_sdist.setAttribute('disabled','true');
            if (found_aou) {
                obj.controller.view.cmd_mark_library.setAttribute('disabled','false');
            }
            if (found_sdist) {
                //obj.controller.view.cmd_delete_sdist.setAttribute('disabled','false');
                obj.controller.view.cmd_add_sstr.setAttribute('disabled','false');
            }
            if (found_sstr_group) {
                obj.controller.view.cmd_add_sstr.setAttribute('disabled','false');
            }
            if (found_sstr) {
                obj.controller.view.cmd_delete_sstr.setAttribute('disabled','false');
                obj.controller.view.cmd_transfer_sstrs.setAttribute('disabled','false');
            }
            if (found_sbsum) {
            }
            if (found_sssum) {
            }
            if (found_sisum) {
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.actions.error'),E);
        }
    },

    'refresh_list' : function() { 
        try {
            var obj = this;
            obj.list.clear();
            obj.map_tree = {};
            obj.map_sdist = {};
            obj.map_sstr = {};
            obj.org_ids = obj.network.simple_request('FM_SDIST_AOU_IDS_RETRIEVE_VIA_RECORD_ID.authoritative',[ obj.docid ]);
            if (typeof obj.org_ids.ilsevent != 'undefined') throw(obj.org_ids);
            JSAN.use('util.functional'); 
            obj.org_ids = util.functional.map_list( obj.org_ids, function (o) { return Number(o); });
            /*
            var org = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
            obj.show_libs( org );
            */
            obj.default_lib = document.getElementById('sdist_lib_menu').value;
            obj.show_my_libs( obj.default_lib );
        } catch(E) {
            this.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.refresh_list.error'),E);
        }
    },
};

dump('exiting serial/manage_dists.js\n');
