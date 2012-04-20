dump('entering cat.copy_browser.js\n');
// vim:noet:sw=4:ts=4:

if (typeof cat == 'undefined') cat = {};
cat.copy_browser = function (params) {
    try {
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        JSAN.use('util.error'); this.error = new util.error();
    } catch(E) {
        dump('cat.copy_browser: ' + E + '\n');
    }
}

cat.copy_browser.prototype = {

    'map_tree' : {},
    'map_acn' : {},
    'map_acp' : {},
    'sel_list' : [],
    'funcs' : [],

    'init' : function( params ) {

        try {
            netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
            var obj = this;

            obj.docid = params.docid;

            JSAN.use('util.network'); obj.network = new util.network();
            JSAN.use('OpenILS.data'); obj.data = new OpenILS.data(); obj.data.init({'via':'stash'});

            obj.controller_init(params);

            obj.list_init(params);

            obj.source_init();

            obj.controller.render();

            obj.default_depth = obj.depth_menu_init();
            obj.default_lib = obj.data.hash.aou[ obj.library_menu_init() ];

            document.getElementById('show_acns').addEventListener(
                'command',
                function(ev) {
                    JSAN.use('util.file');
                    var file = new util.file(
                        'copy_browser_prefs.'+obj.data.server_unadorned);
                    util.widgets.save_attributes(file, {
                        'lib_menu' : [ 'value' ],
                        'depth_menu' : [ 'value' ],
                        'show_acns' : [ 'checked' ],
                        'show_acps' : [ 'checked' ],
                        'hide_aous' : [ 'checked' ] });
                },
                false
            );

            document.getElementById('show_acps').addEventListener(
                'command',
                function(ev) {
                    JSAN.use('util.file');
                    var file = new util.file(
                        'copy_browser_prefs.'+obj.data.server_unadorned);
                    util.widgets.save_attributes(file, {
                        'lib_menu' : [ 'value' ],
                        'depth_menu' : [ 'value' ],
                        'show_acns' : [ 'checked' ],
                        'show_acps' : [ 'checked' ],
                        'hide_aous' : [ 'checked' ] });
                },
                false
            );

            document.getElementById('hide_aous').addEventListener(
                'command',
                function(ev) {
                    JSAN.use('util.file');
                    var file = new util.file(
                        'copy_browser_prefs.'+obj.data.server_unadorned);
                    util.widgets.save_attributes(file, {
                        'lib_menu' : [ 'value' ],
                        'depth_menu' : [ 'value' ],
                        'show_acns' : [ 'checked' ],
                        'show_acps' : [ 'checked' ],
                        'hide_aous' : [ 'checked' ] });
                },
                false
            );

            obj.show_my_libs( obj.default_lib.id() );

            JSAN.use('util.exec'); var exec = new util.exec(20); exec.timer(obj.funcs,100);

            obj.show_consortial_count();

        } catch(E) {
            this.error.standard_unexpected_error_alert('cat.copy_browser.init: ',E);
        }
    },

    'controller_init' : function(params) {
        var obj = this;
        try {
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
                        'cmd_show_all_libs' : [
                            ['command'],
                            function() {
                                obj.show_all_libs();
                            }
                        ],
                        'cmd_show_libs_with_copies' : [
                            ['command'],
                            function() {
                                obj.show_libs_with_copies();
                            }
                        ],
                        'cmd_clear' : [
                            ['command'],
                            function() {
                                obj.map_tree = {};
                                obj.list.clear();
                            }
                        ],
                        'cmd_request_items' : [
                            ['command'],
                            function() {
                                JSAN.use('cat.util'); JSAN.use('util.functional');

                                var list = util.functional.filter_list( obj.sel_list, function (o) { return o.split(/_/)[0] == 'acp'; });

                                list = util.functional.map_list( list, function (o) { return o.split(/_/)[1]; });

                                cat.util.request_items( list );
                            }
                        ],
                        'sel_mark_items_damaged' : [
                            ['command'],
                            function() {
                                JSAN.use('cat.util'); JSAN.use('util.functional');

                                var list = util.functional.filter_list( obj.sel_list, function (o) { return o.split(/_/)[0] == 'acp'; });

                                list = util.functional.map_list( list, function (o) { return o.split(/_/)[1]; });

                                cat.util.mark_item_damaged( list );

                                obj.refresh_list();
                            }
                        ],
                        'sel_mark_items_missing' : [
                            ['command'],
                            function() {
                                JSAN.use('cat.util'); JSAN.use('util.functional');

                                var list = util.functional.filter_list( obj.sel_list, function (o) { return o.split(/_/)[0] == 'acp'; });

                                list = util.functional.map_list( list, function (o) { return o.split(/_/)[1]; });

                                cat.util.mark_item_missing( list );

                                obj.refresh_list();
                            }
                        ],
                        'sel_patron' : [
                            ['command'],
                            function() {
                                JSAN.use('util.functional');

                                var list = util.functional.filter_list(
                                    obj.sel_list,
                                    function (o) {
                                        return o.split(/_/)[0] == 'acp';
                                    }
                                );

                                list = util.functional.map_list(
                                    list,
                                    function (o) {
                                        return { 'copy_id' : o.split(/_/)[1] };
                                    }
                                );
                                
                                JSAN.use('circ.util');
                                circ.util.show_last_few_circs(list);
                            }
                        ],
                        'sel_copy_details' : [
                            ['command'],
                            function() {
                                JSAN.use('util.functional');

                                var list = util.functional.filter_list(
                                    obj.sel_list,
                                    function (o) {
                                        return o.split(/_/)[0] == 'acp';
                                    }
                                );

                                JSAN.use('circ.util');
                                circ.util.item_details_new(
                                    util.functional.map_list(
                                        list, function (o) {
                                            return obj.map_acp[o].barcode();
                                        }
                                    )
                                );
                            }
                        ],
                        'cmd_create_brt' : [
                            ['command'],
                            function() {
                                JSAN.use("cat.util");
                                JSAN.use("util.functional");

                                /* Filter selected rows that aren"t copies. */
                                var list = util.functional.filter_list(
                                    obj.sel_list,
                                    function (o) {
                                        return o.split(/_/)[0] == "acp";
                                    }
                                );
                                var results = cat.util.make_bookable(
                                    util.functional.map_list(
                                        list, function (o) {
                                            return obj.map_acp[o].id();
                                        }
                                    )
                                );
                                if (results && results["brsrc"]) {
                                    cat.util.edit_new_brsrc(results["brsrc"]);
                                }
                            }
                        ],
                        'cmd_book_item_now' : [
                            ['command'],
                            function() {
                                JSAN.use("cat.util");
                                JSAN.use("util.functional");

                                /* Filter selected rows that aren"t copies. */
                                var list = util.functional.filter_list(
                                    obj.sel_list,
                                    function (o) {
                                        return o.split(/_/)[0] == "acp";
                                    }
                                );
                                var results = cat.util.make_bookable(
                                    util.functional.map_list(
                                        list, function (o) {
                                            return obj.map_acp[o].id();
                                        }
                                    )
                                );
                                if (results) {
                                    cat.util.edit_new_bresv(results);
                                }
                            }
                        ],
                        'cmd_add_items' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');
                                    var list = util.functional.map_list(
                                        util.functional.filter_list(
                                            obj.sel_list,
                                            function (o) {
                                                return o.split(/_/)[0] == 'acn';
                                            }
                                        ),
                                        function (o) {
                                            return o.split(/_/)[1];
                                        }
                                    );
                                    if (list.length == 0) return;

                                    var copy_shortcut = {};
                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            var call_number = obj.map_acn['acn_'+o];
                                            var ou_id = call_number.owning_lib();
                                            var volume_id = o;
                                            var label = call_number.label();
                                            var acnc_id = typeof call_number.label_class() == 'object'
                                                ? call_number.label_class().id()
                                                : call_number.label_class();
                                            var acnp_id = typeof call_number.prefix() == 'object'
                                                ? call_number.prefix().id()
                                                : call_number.prefix();
                                            var acns_id = typeof call_number.suffix() == 'object'
                                                ? call_number.suffix().id()
                                                : call_number.suffix();
                                            if (!copy_shortcut[ou_id]) copy_shortcut[ou_id] = {};
                                            var callnumber_composite_key = acnc_id + ':' + acnp_id + ':' + label + ':' + acns_id;
                                            copy_shortcut[ou_id][ callnumber_composite_key ] = volume_id;

                                            return ou_id;
                                        }
                                    );
                                    /* quick fix */  /* what was this fixing? */
                                    list = []; for (var i in copy_shortcut) { list.push( i ); }

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

                                    if (edit==0) return; // no read-only view for this interface

                                    if (!obj.can_have_copies) {
                                        alert(document.getElementById('catStrings').getFormattedString('staff.cat.copy_browser.can_have_copies.false', obj.source));
                                        return;
                                    }

                                    var title = document.getElementById('catStrings').getString('staff.cat.copy_browser.add_item.title');

                                    var url;
                                    var unified_interface = String( obj.data.hash.aous['ui.unified_volume_copy_editor'] ) == 'true';
                                    if (unified_interface) {
                                        var horizontal_interface = String( obj.data.hash.aous['ui.cat.volume_copy_editor.horizontal'] ) == 'true';
                                        url = xulG.url_prefix( horizontal_interface ? urls.XUL_VOLUME_COPY_CREATOR_HORIZONTAL : urls.XUL_VOLUME_COPY_CREATOR );
                                    } else {
                                        url = xulG.url_prefix( urls.XUL_VOLUME_COPY_CREATOR_ORIGINAL );
                                    }

                                    var w = xulG.new_tab(
                                        url,
                                        { 'tab_name' : title },
                                        {
                                            'doc_id' : obj.docid, 
                                            'ou_ids' : list, 
                                            'copy_shortcut' : copy_shortcut,
                                            'onrefresh' : function() { obj.refresh_list(); }
                                        }
                                    );
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.add_item.error'),E);
                                }
                            }
                        ],
                        'cmd_add_items_to_buckets' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');

                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'acp';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return o.split(/_/)[1];
                                        }
                                    );
                                
                                    JSAN.use('cat.util');
                                    cat.util.add_copies_to_bucket( list );

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.add_items_bucket.error'),E);
                                }
                            }
                        ],
                        'cmd_edit_items' : [
                            ['command'],
                            function() {
                                try {
                                    var unified_interface = String( obj.data.hash.aous['ui.unified_volume_copy_editor'] ) == 'true';
                                    if (!unified_interface) {
                                        obj.controller.control_map['old_cmd_edit_items'][1]();
                                        return;
                                    }

                                    JSAN.use('util.functional');

                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'acp';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            var cloned_copy_obj = JSON2js( js2JSON( obj.map_acp[ o ] ) );
                                            cloned_copy_obj.call_number( obj.map_acn[ 'acn_' + cloned_copy_obj.call_number() ] );
                                            return cloned_copy_obj;
                                        }
                                    );

                                    if (list.length > 0) {
                                        xulG.volume_item_creator( {'existing_copies':list, 'onrefresh' : function() { obj.refresh_list(); } } );
                                    }

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.edit_items.error'),E);
                                    obj.refresh_list();
                                }
                            }
                        ],
                        'cmd_replace_barcode' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');

                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'acp';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            var cloned_copy_obj = JSON2js( js2JSON( obj.map_acp[ o ] ) );
                                            cloned_copy_obj.call_number( obj.map_acn[ 'acn_' + cloned_copy_obj.call_number() ] );
                                            return cloned_copy_obj;
                                        }
                                    );

                                    xulG.volume_item_creator( {'existing_copies':list, 'onrefresh' : function() { obj.refresh_list(); } } );

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.edit_items.error'),E);
                                    obj.refresh_list();
                                }
                            }
                        ],

                        'old_cmd_edit_items' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');

                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'acp';
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
                        ],
                        'cmd_delete_items' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');

                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'acp';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return JSON2js( js2JSON( obj.map_acp[ 'acp_' + o.split(/_/)[1] ] ) );
                                        }
                                    );

                                    var delete_msg;
                                    if (list.length != 1) {
                                        delete_msg = document.getElementById('catStrings').getFormattedString('staff.cat.copy_browser.delete_items.confirm.plural', [list.length]);
                                    } else {
                                        delete_msg = document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_items.confirm');
                                    }
                                    var r = obj.error.yns_alert(
                                            delete_msg,
                                            document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_items.title'),
                                            document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_items.delete'),
                                            document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_items.cancel'),
                                            null,
                                            document.getElementById('commonStrings').getString('common.confirm')
                                    );

                                    if (r == 0) {
                                        var acn_hash = {}; var acn_list = [];
                                        for (var i = 0; i < list.length; i++) {
                                            list[i].isdeleted('1');
                                            var acn_id = list[i].call_number();
                                            if ( ! acn_hash[ acn_id ] ) {
                                                acn_hash[ acn_id ] = obj.map_acn[ 'acn_' + acn_id ];
                                                acn_hash[ acn_id ].copies( [] );
                                            }
                                            var temp = acn_hash[ acn_id ].copies();
                                            temp.push( list[i] );
                                            acn_hash[ acn_id ].copies( temp );
                                        }
                                        for (var i in acn_hash) acn_list.push( acn_hash[i] );
                                        var robj = obj.network.simple_request(
                                            'FM_ACN_TREE_UPDATE', 
                                            [ ses(), acn_list, true ],
                                            null,
                                            {
                                                'title' : document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_items.override'),
                                                'overridable_events' : [
                                                    1208 /* TITLE_LAST_COPY */,
                                                    1227 /* COPY_DELETE_WARNING */,
                                                ]
                                            }
                                        );
                                        if (robj == null) throw(robj);
                                        if (typeof robj.ilsevent != 'undefined') {
                                            if (
                                                (robj.ilsevent != 0)
                                                && (robj.ilsevent != 1227 /* COPY_DELETE_WARNING */)
                                                && (robj.ilsevent != 1208 /* TITLE_LAST_COPY */)
                                                && (robj.ilsevent != 5000 /* PERM_DENIED */)
                                            ) {
                                                throw(robj);
                                            }
                                        }
                                        obj.refresh_list();
                                    }

                                    
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_items.error'),E);
                                    obj.refresh_list();
                                }
                            }
                        ],
                        'cmd_print_spine_labels' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');
                                    
                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'acp';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return obj.map_acp[ o ];
                                        }
                                    );

                                    xulG.new_tab(
                                        xulG.url_prefix( urls.XUL_SPINE_LABEL ),
                                        { 'tab_name' : document.getElementById('catStrings').getString('staff.cat.copy_browser.print_spine.tab') },
                                        {
                                            'barcodes' : util.functional.map_list( list, function(o){return o.barcode();})
                                        }
                                    );
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.print_spine.error'),E);
                                }
                            }
                        ],
                        'cmd_add_volumes' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');
                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'aou';
                                        }
                                    );
                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return o.split(/_/)[1];
                                        }
                                    );        
                                    var edit = 0;
                                    try {
                                        edit = obj.network.request(
                                            api.PERM_MULTI_ORG_CHECK.app,
                                            api.PERM_MULTI_ORG_CHECK.method,
                                            [ 
                                                ses(), 
                                                obj.data.list.au[0].id(), 
                                                list,
                                                [ 'CREATE_VOLUME', 'CREATE_COPY' ]
                                            ]
                                        ).length == 0 ? 1 : 0;
                                    } catch(E) {
                                        obj.error.sdump('D_ERROR','batch permission check: ' + E);
                                    }

                                    if (edit==0) {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.add_volume.permission_error'));
                                        return; // no read-only view for this interface
                                    }

                                    if (!obj.can_have_copies) {
                                        alert(document.getElementById('catStrings').getFormattedString('staff.cat.copy_browser.can_have_copies.false', obj.source));
                                        return;
                                    }

                                    var title = document.getElementById('catStrings').getString('staff.cat.copy_browser.add_volume.title');

                                    var url;
                                    var unified_interface = String( obj.data.hash.aous['ui.unified_volume_copy_editor'] ) == 'true';
                                    if (unified_interface) {
                                        var horizontal_interface = String( obj.data.hash.aous['ui.cat.volume_copy_editor.horizontal'] ) == 'true';
                                        url = xulG.url_prefix( horizontal_interface ? urls.XUL_VOLUME_COPY_CREATOR_HORIZONTAL : urls.XUL_VOLUME_COPY_CREATOR );
                                    } else {
                                        url = xulG.url_prefix( urls.XUL_VOLUME_COPY_CREATOR_ORIGINAL );
                                    }

                                    var w = xulG.new_tab(
                                        url,
                                        { 'tab_name' : title },
                                        { 'doc_id' : obj.docid, 'ou_ids' : list, 'onrefresh' : function() { obj.refresh_list(); } }
                                    );

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.add_volume.error'),E);
                                }
                            }
                        ],
                        'cmd_edit_volumes' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');
                                    var volumes = util.functional.map_list(
                                        util.functional.filter_list(
                                            obj.sel_list,
                                            function (o) {
                                                return o.split(/_/)[0] == 'acn';
                                            }
                                        ),
                                        function (o) {
                                            return o.split(/_/)[1];
                                        }
                                    );
                                    volumes = util.functional.map_list(
                                        volumes,
                                        function (o) {
                                            var my_acn = obj.map_acn['acn_' + o];
                                            return function(r){return r;}(my_acn);
                                        }
                                    );

                                    JSAN.use('cat.util'); 
                                    if ( cat.util.batch_edit_volumes( volumes ) ) {
                                        obj.refresh_list();
                                    }

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.edit_volume.exception'),E);
                                }
                            }
                        ],
                        'cmd_delete_volumes' : [
                            ['command'],
                            function() {
                                try {
                                    JSAN.use('util.functional');

                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'acn';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return JSON2js( js2JSON( obj.map_acn[ 'acn_' + o.split(/_/)[1] ] ) );
                                        }
                                    );

                                    var del_prompt;
                                    if (list.length == 1) {
                                        del_prompt = document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.prompt');
                                    } else {
                                        del_prompt = document.getElementById('catStrings').getFormattedString('staff.cat.copy_browser.delete_volume.prompt.plural', [list.length]);
                                    }

                                    var r = obj.error.yns_alert(
                                            del_prompt,
                                            document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.title'),
                                            document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.delete'),
                                            document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.cancel'),
                                            null,
                                            document.getElementById('commonStrings').getString('common.confirm')
                                    );

                                    if (r == 0) { // delete vols
                                        for (var i = 0; i < list.length; i++) {
                                            list[i].isdeleted('1');
                                        }
                                        var params = {};
                                        loop: while(true) {
                                            var robj = obj.network.simple_request(
                                                'FM_ACN_TREE_UPDATE', 
                                                [ ses(), list, true, params ],
                                                null,
                                                {
                                                    'title' : document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.override'),
                                                    'overridable_events' : [
                                                        1208 /* TITLE_LAST_COPY */,
                                                        1227 /* COPY_DELETE_WARNING */
                                                    ]
                                                }
                                            );
                                            if (robj == null) throw(robj);
                                            if (typeof robj.ilsevent != 'undefined') {
                                                if (robj.ilsevent == 1206 /* VOLUME_NOT_EMPTY */) {
                                                    var r2 = obj.error.yns_alert(
                                                        document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.copies_remain'),
                                                        document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.title'),
                                                        document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.copies_remain.confirm'),
                                                        document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.copies_remain.cancel'),
                                                        null,
                                                        document.getElementById('commonStrings').getString('common.confirm')
                                                    );
                                                    if (r2 == 0) { // delete vols and copies
                                                        params.force_delete_copies = true;
                                                        continue loop;
                                                    }
                                                } else {
                                                    if (typeof robj.ilsevent != 'undefined') {
                                                        if (
                                                            (robj.ilsevent != 0)
                                                            && (robj.ilsevent != 1227 /* COPY_DELETE_WARNING */)
                                                            && (robj.ilsevent != 1208 /* TITLE_LAST_COPY */)
                                                            && (robj.ilsevent != 5000 /* PERM_DENIED */)
                                                        ) {
                                                            throw(robj);
                                                        }
                                                    }
                                                }
                                            }
                                            break loop;
                                        }
                                        obj.refresh_list();
                                    }
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_volume.exception'),E);
                                    obj.refresh_list();
                                }

                            }
                        ],
                        'cmd_mark_library' : [
                            ['command'],
                            function() {
                                try {
                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'aou';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return o.split(/_/)[1];
                                        }
                                    );

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
                                    obj.error.standard_unexpected_error_alert('copy browser -> mark library',E);
                                }
                            }
                        ],

                        'cmd_mark_volume' : [
                            ['command'],
                            function() {
                                try {
                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'acn';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return o.split(/_/)[1];
                                        }
                                    );

                                    if (list.length == 1) {
                                        obj.data.marked_volume = list[0];
                                        obj.data.stash('marked_volume');
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
                                    obj.error.standard_unexpected_error_alert('copy browser -> mark volume',E);
                                }
                            }
                        ],
                        'cmd_refresh_list' : [
                            ['command'],
                            function() {
                                obj.refresh_list();
                            }
                        ],
                        'cmd_transfer_volume' : [
                            ['command'],
                            function() {
                                try {
                                    obj.data.stash_retrieve();
                                    if (!obj.data.marked_library) {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer_volume.alert'));
                                        return;
                                    }
                                    
                                    JSAN.use('util.functional');

                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'acn';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return o.split(/_/)[1];
                                        }
                                    );

                                    netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserWrite');

                                    var acn_list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return obj.map_acn[ 'acn_' + o ].label();
                                        }
                                    ).join(document.getElementById('commonStrings').getString('common.grouping_string'));

                                    var xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" style="overflow: auto">';
                                    xml += '<description>';
                                    xml += document.getElementById('catStrings').getFormattedString('staff.cat.copy_browser.transfer.prompt', [acn_list, obj.data.hash.aou[ obj.data.marked_library.lib ].shortname()]);
                                    xml += '</description>';
                                    xml += '<hbox><button label="' + document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.submit.label') + '" name="fancy_submit"/>';
                                    xml += '<button label="' 
                                        + document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.cancel.label') 
                                        + '" accesskey="' 
                                        + document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.cancel.accesskey') 
                                        + '" name="fancy_cancel"/></hbox>';
                                    xml += '<iframe style="overflow: scroll" flex="1" src="' + urls.XUL_BIB_BRIEF + '?docid=' + obj.data.marked_library.docid + '"/>';
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
                                        [ ses(), { 'docid' : obj.data.marked_library.docid, 'lib' : obj.data.marked_library.lib, 'volumes' : list } ],
                                        null,
                                        {
                                            'title' : document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer.override.failure'),
                                            'overridable_events' : [
                                                1208 /* TITLE_LAST_COPY */,
                                                1219 /* COPY_REMOTE_CIRC_LIB */,
                                            ],
                                        }
                                    );

                                    if (typeof robj.ilsevent != 'undefined') {
                                        if (robj.ilsevent == 1221 /* ORG_CANNOT_HAVE_VOLS */) {
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

                        'cmd_transfer_items' : [
                            ['command'],
                            function() {
                                try {
                                    obj.data.stash_retrieve();
                                    if (!obj.data.marked_volume) {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer_items.missing_volume'));
                                        return;
                                    }
                                    
                                    JSAN.use('util.functional');

                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'acp';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return o.split(/_/)[1];
                                        }
                                    );

                                    var volume = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ obj.data.marked_volume ]);

                                    JSAN.use('cat.util'); cat.util.transfer_copies( { 
                                        'copy_ids' : list, 
                                        'docid' : volume.record(),
                                        'volume_label' : volume.label(),
                                        'owning_lib' : volume.owning_lib(),
                                    } );

                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.transfer_items.unexpected_error'),E);
                                }
                                obj.refresh_list();
                            }
                        ],

                        'cmd_link_as_multi_bib' : [
                            ['command'],
                            function() {
                                try {
                                    obj.data.stash_retrieve();
                                    if (!obj.data.marked_multi_home_record) {
                                        alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.link_as_multi_bib.missing_bib'));
                                        return;
                                    }

                                    JSAN.use('util.functional');

                                    var list = util.functional.filter_list(
                                        obj.sel_list,
                                        function (o) {
                                            return o.split(/_/)[0] == 'acp';
                                        }
                                    );

                                    list = util.functional.map_list(
                                        list,
                                        function (o) {
                                            return obj.map_acp[ o ].barcode();
                                        }
                                    );

                                    xulG.new_tab(
                                        window.xulG.url_prefix(urls.MANAGE_MULTI_HOME_ITEMS),
                                        {},
                                        { 'docid' : obj.data.marked_multi_home_record, 'barcodes' : list }
                                    );

                                } catch(E) {
                                    alert('Error in copy_browser.js, cmd_link_as_multi_bib: ' + E);
                                }
                                obj.refresh_list();
                            }
                        ],

                        'cmd_print_tree' : [
                            ['command'],
                            function() {
                                try {
                                    var p = {
                                        'template' : 'holdings_maintenance',
                                        'mvr_id' : obj.docid,
                                        'print_data' : {}
                                    };
                                    bib_brief_overlay(p);
                                    p.data = p.print_data;
                                    obj.list.print(p);
                                } catch(E) {
                                    alert('Error in copy_browser.js, cmd_print_tree: ' + E);
                                }
                            }
                        ]
                    }
                }
            );

        } catch(E) {
            this.error.standard_unexpected_error_alert('cat.copy_browser.controller_init(): ',E);
        }
    },

    'depth_menu_init' : function(params) {
        var obj = this;
        try {
            var list = [];
            var max_depth = 0;
            for (var i = 0; i < obj.data.list.aout.length; i++) {
                var type = obj.data.list.aout[i];
                var depth = type.depth();
                if ( depth > max_depth) { max_depth = depth; }
                if (typeof list[depth] == 'undefined') {
                    list[depth] = [
                        type.opac_label(),
                        type.depth(),
                        false,
                        ( type.depth() * 2)
                    ];
                } else {
                    list[depth][0] += ' / ' + type.opac_label();
                }
            }
            ml = util.widgets.make_menulist( list, max_depth );
            ml.setAttribute('id','depth_menu'); document.getElementById('x_depth_menu').appendChild(ml);
            ml.addEventListener(
                'command',
                function(ev) {
                    obj.default_depth = ev.target.value;
                    if (document.getElementById('refresh_button')) document.getElementById('refresh_button').focus(); 
                    JSAN.use('util.file'); var file = new util.file('copy_browser_prefs.'+obj.data.server_unadorned);
                    util.widgets.save_attributes(file, { 
                        'lib_menu' : [ 'value' ],
                        'depth_menu' : [ 'value' ],
                        'show_acns' : [ 'checked' ],
                        'show_acps' : [ 'checked' ],
                        'hide_aous' : [ 'checked' ]
                    });
                },
                false
            );

            file = new util.file('copy_browser_prefs.'+obj.data.server_unadorned);
            util.widgets.load_attributes(file);
            ml.value = ml.getAttribute('value');
            if (! ml.value) {
                ml.value = max_depth;
                ml.setAttribute('value',ml.value);
            }

            return ml.value;
        } catch(E) {
            alert('Error in copy_browser.js, depth_menu_init(): ' + E);
        }
    },

    'library_menu_init' : function(params) {
        var obj = this;
        try {

            obj.org_ids = obj.network.simple_request('FM_AOU_IDS_RETRIEVE_VIA_RECORD_ID.authoritative',[ obj.docid ]);
            if (typeof obj.org_ids.ilsevent != 'undefined') throw(obj.org_ids);
            JSAN.use('util.functional'); 
            obj.org_ids = util.functional.map_list( obj.org_ids, function (o) { return Number(o); });

            var org = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];

            JSAN.use('util.file'); JSAN.use('util.widgets');

            var file; var list_data; var ml; 

            file = new util.file('offline_ou_list'); 
            if (file._file.exists()) {
                list_data = file.get_object(); file.close();
                for (var i = 0; i < list_data[0].length; i++) { // make sure all entries are enabled
                    list_data[0][i][2] = false;
                }
                ml = util.widgets.make_menulist( list_data[0], list_data[1] );
                ml.setAttribute('id','lib_menu'); document.getElementById('x_lib_menu').appendChild(ml);
                for (var i = 0; i < obj.org_ids.length; i++) {
                    ml.getElementsByAttribute('value',obj.org_ids[i])[0].setAttribute('class','has_copies');
                }
                ml.firstChild.addEventListener(
                    'popupshowing',
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
                        obj.default_lib = obj.data.hash.aou[ ev.target.value ];
                        if (document.getElementById('refresh_button')) document.getElementById('refresh_button').focus(); 
                        JSAN.use('util.file'); var file = new util.file('copy_browser_prefs.'+obj.data.server_unadorned);
                        util.widgets.save_attributes(file, { 
                            'lib_menu' : [ 'value' ],
                            'depth_menu' : [ 'value' ],
                            'show_acns' : [ 'checked' ],
                            'show_acps' : [ 'checked' ],
                            'hide_aous' : [ 'checked' ]
                        });
                        obj.refresh_list();
                    },
                    false
                );
            } else {
                throw(document.getElementById('catStrings').getString('staff.cat.copy_browser.missing_library') + '\n');
            }

            file = new util.file('copy_browser_prefs.'+obj.data.server_unadorned);
            util.widgets.load_attributes(file);
            ml.value = ml.getAttribute('value');
            if (! ml.value) {
                ml.value = org.id();
                ml.setAttribute('value',ml.value);
            }

            return ml.value;

        } catch(E) {
            this.error.standard_unexpected_error_alert('cat.copy_browser.library_menu_init(): ',E);
        }
    },

    'show_consortial_count' : function() {
        var obj = this;
        try {
            obj.network.simple_request('FM_ACP_COUNT.authoritative',[ obj.data.tree.aou.id(), obj.docid ],function(req){ 
                try {
                    var robj = req.getResultObject();
                    var x = document.getElementById('consortial_total');
                    if (x) x.setAttribute('value',robj[0].count);
                    x = document.getElementById('consortial_available');
                    if (x) x.setAttribute('value',robj[0].available);
                } catch(E) {
                    obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.consortial_copy_count.error'),E);
                }
            });
        } catch(E) {
            this.error.standard_unexpected_error_alert('cat.copy_browser.show_consortial_count: ',E);
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
/*        
            var p_org = obj.data.hash.aou[ org.parent_ou() ];
            if (p_org) {
                obj.funcs.push( function() { 
                    document.getElementById('cmd_refresh_list').setAttribute('disabled','true'); 
                    document.getElementById('cmd_show_libs_with_copies').setAttribute('disabled','true'); 
                    document.getElementById('lib_menu').setAttribute('disabled','true'); 
                } );
                for (var i = 0; i < p_org.children().length; i++) {
                    obj.funcs.push(
                        function(o) {
                            return function() {
                                obj.show_libs( o, false );
                            }
                        }( p_org.children()[i] )
                    );
                }
                obj.funcs.push( function() { 
                    document.getElementById('cmd_refresh_list').setAttribute('disabled','false'); 
                    document.getElementById('cmd_show_libs_with_copies').setAttribute('disabled','false'); 
                    document.getElementById('lib_menu').setAttribute('disabled','false'); 
                } );
            }
*/
        } catch(E) {
            alert(E);
        }
    },

    'show_all_libs' : function() {
        var obj = this;
        try {
            obj.show_my_libs();

            obj.show_libs( obj.data.tree.aou );

            obj.funcs.push( function() { 
                document.getElementById('cmd_refresh_list').setAttribute('disabled','true'); 
                document.getElementById('cmd_show_libs_with_copies').setAttribute('disabled','true'); 
                document.getElementById('lib_menu').setAttribute('disabled','true'); 
            } );

            for (var i = 0; i < obj.data.tree.aou.children().length; i++) {
                var child = obj.data.tree.aou.children()[i];
                if (obj.data.hash.aout[child.ou_type()].depth() <= obj.default_depth
                && orgIsMine(obj.default_lib,child,obj.default_depth)) {
                    obj.funcs.push(
                        function(o) {
                            return function() {
                                obj.show_libs( o );
                            }
                        }( child )
                    );
                }
            }
            obj.funcs.push( function() { 
                document.getElementById('cmd_refresh_list').setAttribute('disabled','false'); 
                document.getElementById('cmd_show_libs_with_copies').setAttribute('disabled','false'); 
                document.getElementById('lib_menu').setAttribute('disabled','false'); 
            } );

        } catch(E) {
            alert(E);
        }
    },

    'show_libs_with_copies' : function() {
        var obj = this;
        try {
            JSAN.use('util.functional');

            var orgs = util.functional.map_list(
                obj.org_ids,
                function(id) { return obj.data.hash.aou[id]; }
            ).sort(
                function( a, b ) {
                    if (a.shortname() < b.shortname()) return -1;
                    if (a.shortname() > b.shortname()) return 1;
                    return 0;
                }
            );
            obj.funcs.push( function() { 
                document.getElementById('cmd_refresh_list').setAttribute('disabled','true'); 
                document.getElementById('cmd_show_libs_with_copies').setAttribute('disabled','true'); 
                document.getElementById('lib_menu').setAttribute('disabled','true'); 
            } );

            for (var i = 0; i < orgs.length; i++) {
                obj.funcs.push(
                    function(o) {
                        return function() {
                            obj.show_libs(o,false);
                        }
                    }( orgs[i] )
                );
            }
            obj.funcs.push( function() { 
                document.getElementById('cmd_refresh_list').setAttribute('disabled','false'); 
                document.getElementById('cmd_show_libs_with_copies').setAttribute('disabled','false'); 
                document.getElementById('lib_menu').setAttribute('disabled','false'); 
            } );

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
                            var child = start_aou.children()[i];
                            if (obj.data.hash.aout[child.ou_type()].depth() <= obj.default_depth
                            && orgIsMine(obj.default_lib,child,obj.default_depth)) {
                                obj.funcs.push(
                                    function(o,p) {
                                        return function() { obj.append_org(o,p); };
                                    }( child, start_aou )
                                );
                            }
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
        for (var i = 0; i < list.length; i++) {
            var node = obj.map_tree[ list[i] ];
            //if (node.lastChild.nodeName == 'treechildren') { continue; } else { alert(node.lastChild.nodeName); }
            var row_type = list[i].split('_')[0];
            var id = list[i].split('_')[1];
            switch(row_type) {
                case 'aou' : obj.on_select_org(id,twisty); break;
                case 'acn' : obj.on_select_acn(id,twisty); break;
                default: break;
            }
        }
    },

    'on_select_acn' : function(acn_id,twisty) {
        var obj = this;
        try {
            var acn_tree = obj.map_acp[ 'acn_' + acn_id ];
            obj.funcs.push( function() { 
                document.getElementById('cmd_refresh_list').setAttribute('disabled','true'); 
                document.getElementById('cmd_show_libs_with_copies').setAttribute('disabled','true'); 
                document.getElementById('lib_menu').setAttribute('disabled','true'); 
            } );
            if (acn_tree.copies()) {
                for (var i = 0; i < acn_tree.copies().length; i++) {
                    obj.funcs.push(
                        function(c,a) {
                            return function() {
                                obj.append_acp(c,a);
                            }
                        }( acn_tree.copies()[i], acn_tree )
                    )
                }
            }
            obj.funcs.push( function() { 
                document.getElementById('cmd_refresh_list').setAttribute('disabled','false'); 
                document.getElementById('cmd_show_libs_with_copies').setAttribute('disabled','false'); 
                document.getElementById('lib_menu').setAttribute('disabled','false'); 
            } );
        } catch(E) {
            alert(E);
        }
    },

    'on_select_org' : function(org_id,twisty) {
        var obj = this;
        try {
            var org = obj.data.hash.aou[ org_id ];
            obj.funcs.push( function() { 
                document.getElementById('cmd_refresh_list').setAttribute('disabled','true'); 
                document.getElementById('cmd_show_libs_with_copies').setAttribute('disabled','true'); 
                document.getElementById('lib_menu').setAttribute('disabled','true'); 
            } );
            if (org.children()) {
                for (var i = 0; i < org.children().length; i++) {
                    var child = org.children()[i];
                    if (obj.data.hash.aout[child.ou_type()].depth() <= obj.default_depth
                    && orgIsMine(obj.default_lib,child,obj.default_depth)) {
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
            if (obj.map_acn[ 'aou_' + org_id ]) {
                for (var i = 0; i < obj.map_acn[ 'aou_' + org_id ].length; i++) {
                    obj.funcs.push(
                        function(o,a) {
                            return function() {
                                obj.append_acn(o,a);
                            }
                        }( org, obj.map_acn[ 'aou_' + org_id ][i] )
                    );
                }
            }
            obj.funcs.push( function() { 
                document.getElementById('cmd_refresh_list').setAttribute('disabled','false'); 
                document.getElementById('cmd_show_libs_with_copies').setAttribute('disabled','false'); 
                document.getElementById('lib_menu').setAttribute('disabled','false'); 
            } );
        } catch(E) {
            alert('Error in copy_browser.js, on_select_org(): ' + E);
        }
    },

    'append_org' : function (org,parent_org,params) {
        var obj = this;
        netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
        obj.error.consoleService.logStringMessage('append_org: org = ' + org.shortname() + ' parent_org = ' + (parent_org ? parent_org.shortname() : '') + ' params = ' + js2JSON(params) + '\n');
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
        
            var acn_tree_list;
            if ( obj.org_ids.indexOf( Number( org.id() ) ) == -1 ) {
                if ( get_bool( obj.data.hash.aout[ org.ou_type() ].can_have_vols() ) ) {
                    data.row.my.volume_count = '0';
                    data.row.my.copy_count = '<0>';
                } else {
                    data.row.my.volume_count = '';
                    data.row.my.copy_count = '';
                }
            } else {
                var v_count = 0; var c_count = 0;
                acn_tree_list = obj.network.simple_request(
                    'FM_ACN_TREE_LIST_RETRIEVE_VIA_RECORD_ID_AND_ORG_IDS.authoritative',
                    [ ses(), obj.docid, [ org.id() ] ]
                );
                for (var i = 0; i < acn_tree_list.length; i++) {
                    v_count++;
                    obj.map_acn[ 'acn_' + acn_tree_list[i].id() ] = function(r){return r;}(acn_tree_list[i]);
                    var copies = acn_tree_list[i].copies(); if (copies) c_count += copies.length;
                    for (var j = 0; j < copies.length; j++) {
                        obj.map_acp[ 'acp_' + copies[j].id() ] = function(r){return r;}(copies[j]);
                    }
                }
                data.row.my.volume_count = String(v_count);
                data.row.my.copy_count = '<' + c_count + '>';
            }
            if (document.getElementById('hide_aous').checked) {
                if (org.children().length == 0
                        && data.row.my.volume_count == '0') {
                    if (!params) {
                        params = { 'hidden' : true };
                    } else {
                        params['hidden'] = true;
                    }
                    dump('hiding org.id() = ' + org.id() + '\n');
                }
            }
            if (parent_org) {
                data.node = obj.map_tree[ 'aou_' + parent_org.id() ];
            }
            var nparams = obj.list.append(data);
            obj.list.refresh_ordinals();
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
                }
            } else {
                obj.map_tree[ 'aou_' + org.id() ].setAttribute('open','true');
            }

            if (acn_tree_list) {
                obj.map_acn[ 'aou_' + org.id() ] = acn_tree_list;
                node.setAttribute('container','true');
            }

            if (document.getElementById('show_acns').checked) {
                node.setAttribute('open','true');
                obj.funcs.push( function() { obj.on_select_org( org.id() ); } );
            }

        } catch(E) {
            dump(E+'\n');
            alert(E);
        }
    },

    'append_acn' : function( org, acn_tree, params ) {
        var obj = this;
        try {
            if (obj.map_tree[ 'acn_' + acn_tree.id() ]) {
                var x = obj.map_tree[ 'acn_' + acn_tree.id() ];
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
                        'acn' : acn_tree,
                        'volume_count' : '',
                        'copy_count' : acn_tree.copies() ? acn_tree.copies().length : '0',
                    }
                },
                'skip_all_columns_except' : [0,1,2],
                'retrieve_id' : 'acn_' + acn_tree.id(),
                'node' : parent_node,
                'to_bottom' : true,
                'no_auto_select' : true,
            };
            var nparams = obj.list.append(data);
            obj.list.refresh_ordinals();
            var node = nparams.treeitem_node;
            obj.map_tree[ 'acn_' + acn_tree.id() ] =  node;
            if (params) {
                for (var i in params) {
                    node.setAttribute(i,params[i]);
                }
            }
            if (acn_tree.copies()) {
                obj.map_acp[ 'acn_' + acn_tree.id() ] = acn_tree;
                node.setAttribute('container','true');
            }
            if (document.getElementById('show_acps').checked) {
                node.setAttribute('open','true');
                obj.funcs.push( function() { obj.on_select_acn( acn_tree.id() ); } );
            }

        } catch(E) {
            dump(E+'\n');
            alert(E);
        }
    },

    'append_acp' : function( acp_item, acn_tree, params ) {
        var obj = this;
        try {
            if (obj.map_tree[ 'acp_' + acp_item.id() ]) {
                var x = obj.map_tree[ 'acp_' + acp_item.id() ];
                if (params) {
                    for (var i in params) {
                        x.setAttribute(i,params[i]);
                    }
                }
                return x;
            }

            var parent_node = obj.map_tree[ 'acn_' + acn_tree.id() ];
            var data = {
                'row' : {
                    'my' : {
                        'doc_id' : obj.docid,
                        'aou' : obj.data.hash.aou[ acn_tree.owning_lib() ],
                        'acn' : acn_tree,
                        'acp' : acp_item,
                        'circ' :
                            acp_item.circulations() 
                            ? (
                                acp_item.circulations().length > 0
                                ? acp_item.circulations()[0]
                                : null
                            ) 
                            : null,
                        'volume_count' : '',
                        'copy_count' : '',
                    }
                },
                'retrieve_id' : 'acp_' + acp_item.id(),
                'node' : parent_node,
                'to_bottom' : true,
                'no_auto_select' : true,
            };
            var nparams = obj.list.append(data);
            obj.list.refresh_ordinals();
            var node = nparams.treeitem_node;
            obj.map_tree[ 'acp_' + acp_item.id() ] =  node;
            if (params) {
                for (var i in params) {
                    node.setAttribute(i,params[i]);
                }
            }

        } catch(E) {
            dump(E+'\n');
            alert(E);
        }
    },

    'list_init' : function( params ) {

        try {
            netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
            var obj = this;
            
            JSAN.use('circ.util');
            var columns = [
                {
                    'id' : 'tree_location',
                    'label' : document.getElementById('catStrings').getString('staff.cat.copy_browser.list_init.tree_location'),
                    'flex' : 1, 'primary' : true, 'hidden' : false, 
                    'render' : function(my) { return my.acp ? my.acp.barcode() : my.acn ? my.acn.label() : my.aou ? my.aou.shortname() + " : " + my.aou.name() : "???"; },
                },
                {
                    'id' : 'volume_count',
                    'label' : document.getElementById('catStrings').getString('staff.cat.copy_browser.list_init.volume_count'),
                    'flex' : 0, 'primary' : false, 'hidden' : false, 
                    'render' : function(my) { return my.volume_count; },
                },
                {
                    'id' : 'copy_count',
                    'label' : document.getElementById('catStrings').getString('staff.cat.copy_browser.list_init.copy_count'),
                    'flex' : 0,
                    'primary' : false, 'hidden' : false, 
                    'render' : function(my) { return my.copy_count; },
                },
            ].concat(
                circ.util.columns( 
                    { 
                        'location' : { 'hidden' : false },
                        'circ_lib' : { 'hidden' : false },
                        'owning_lib' : { 'hidden' : false },
                        'call_number' : { 'hidden' : false },
                        'parts' : { 'hidden' : false },
                        'due_date' : { 'hidden' : false },
                        'acp_status' : { 'hidden' : false },
                    },
                    {
                        'just_these' : [
                            'due_date',
                            'owning_lib',
                            'circ_lib',
                            'label_class',
                            'prefix',
                            'call_number',
                            'suffix',
                            'copy_number',
                            'parts',
                            'location',
                            'barcode',
                            'loan_duration',
                            'fine_level',
                            'circulate',
                            'holdable',
                            'opac_visible',
                            'ref',
                            'deposit',
                            'deposit_amount',
                            'price',
                            'circ_as_type',
                            'circ_modifier',
                            'acp_status',
                            'alert_message',
                            'acp_mint_condition',
                            'acp_id'
                        ]
                    }
                )
            );
            JSAN.use('util.list'); obj.list = new util.list('copy_tree');
            obj.list.init(
                {
                    'no_auto_select' : true,
                    'columns' : columns,
                    'retrieve_row' : function(params) {

                        var row = params.row;

                    /*    
                        if (!row.my.mvr) obj.funcs.push(
                            function() {

                                row.my.mvr = obj.network.request(
                                    api.MODS_SLIM_RECORD_RETRIEVE_VIA_COPY.app,
                                    api.MODS_SLIM_RECORD_RETRIEVE_VIA_COPY.method,
                                    [ row.my.circ.target_copy() ]
                                );

                            }
                        );
                        if (!row.my.acp) {
                            obj.funcs.push(    
                                function() {

                                    row.my.acp = obj.network.request(
                                        api.FM_ACP_RETRIEVE.app,
                                        api.FM_ACP_RETRIEVE.method,
                                        [ row.my.circ.target_copy() ]
                                    );

                                    params.treeitem_node.setAttribute( 'retrieve_id',row.my.acp.barcode() );

                                }
                            );
                        } else {
                            params.treeitem_node.setAttribute( 'retrieve_id',row.my.acp.barcode() );
                        }
                    */
                        obj.funcs.push(
                            function() {

                                if (typeof params.on_retrieve == 'function') {
                                    params.on_retrieve(row);
                                }
                                obj.list.refresh_ordinals();

                            }
                        );

                        return row;
                    },
                    'on_click' : function(ev) {
                        netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect UniversalBrowserRead');
                        var row = {}; var col = {}; var nobj = {};
                        obj.list.node.treeBoxObject.getCellAt(ev.clientX,ev.clientY,row,col,nobj); 
                        if ((row.value == -1)||(nobj.value != 'twisty')) { return; }
                        var node = obj.list.node.contentView.getItemAtIndex(row.value);
                        var list = [ node.getAttribute('retrieve_id') ];
                        if (typeof obj.on_select == 'function') {
                            obj.on_select(list,true);
                        }
                        if (typeof window.xulG == 'object' && typeof window.xulG.on_select == 'function') {
                            window.xulG.on_select(list);
                        }
                        obj.list.refresh_ordinals();
                    },
                    'on_dblclick' : function(ev) {
                        JSAN.use('util.functional');
                        JSAN.use('util.widgets');
                        var sel = obj.list.retrieve_selection();
                        obj.controller.view.sel_clip.disabled = sel.length < 1;
                        obj.sel_list = util.functional.map_list(
                            sel,
                            function(o) { return o.getAttribute('retrieve_id'); }
                        );
                        obj.toggle_actions();
                        util.widgets.dispatch('command','cmd_edit_items');
                        obj.list.refresh_ordinals();
                    },
                    'on_select' : function(ev) {
                        JSAN.use('util.functional');
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
                        obj.list.refresh_ordinals();
                    },
                }
            );

            $('list_actions').appendChild( obj.list.render_list_actions() );
            obj.list.set_list_actions();

        } catch(E) {
            this.error.sdump('D_ERROR','cat.copy_browser.list_init: ' + E + '\n');
            alert(E);
        }
    },

    // Sets can_have_copies and source member variables.
    'source_init' : function() {
        var obj = this;
        try {
            JSAN.use('cat.util');
            var cbsObj = cat.util.get_cbs_for_bre_id(obj.docid);
            if(cbsObj) {
                obj.can_have_copies = (cbsObj.can_have_copies() == get_db_true());
                obj.source = cbsObj.source();
            } else {
                obj.can_have_copies = true;
            }
        } catch(E) {
            obj.error.sdump('D_ERROR','can have copies check: ' + E);
            alert(E);
        }
    },

    'toggle_actions' : function() {
        var obj = this;
        try {
            var found_aou = false; var found_acn = false; var found_acp = false;
            var found_aou_with_can_have_vols = false;
            var sel_copy_libs = {};
            for (var i = 0; i < obj.sel_list.length; i++) {
                var type = obj.sel_list[i].split(/_/)[0];
                switch(type) {
                    case 'aou' : 
                        found_aou = true; 
                        var org = obj.data.hash.aou[ obj.sel_list[i].split(/_/)[1] ];
                        if ( get_bool( obj.data.hash.aout[ org.ou_type() ].can_have_vols() ) ) found_aou_with_can_have_vols = true;
                    break;
                    case 'acn' : found_acn = true; break;
                    case 'acp' :
                        found_acp = true;
                        sel_copy_libs[
                            obj.map_acn[
                                "acn_" +
                                obj.map_acp[obj.sel_list[i]].call_number()
                            ].owning_lib()
                        ] = true;
                        break;
                }
            }
            obj.controller.view.cmd_add_items.setAttribute('disabled','true');
            obj.controller.view.cmd_add_items_to_buckets.setAttribute('disabled','true');
            obj.controller.view.cmd_edit_items.setAttribute('disabled','true');
            obj.controller.view.cmd_replace_barcode.setAttribute('disabled','true');
            obj.controller.view.cmd_delete_items.setAttribute('disabled','true');
            obj.controller.view.cmd_print_spine_labels.setAttribute('disabled','true');
            obj.controller.view.cmd_add_volumes.setAttribute('disabled','true');
            obj.controller.view.cmd_mark_library.setAttribute('disabled','true');
            obj.controller.view.cmd_edit_volumes.setAttribute('disabled','true');
            obj.controller.view.cmd_delete_volumes.setAttribute('disabled','true');
            obj.controller.view.cmd_mark_volume.setAttribute('disabled','true');
            obj.controller.view.cmd_transfer_volume.setAttribute('disabled','true');
            obj.controller.view.cmd_transfer_items.setAttribute('disabled','true');
            obj.controller.view.sel_copy_details.setAttribute('disabled','true');
            obj.controller.view.cmd_create_brt.setAttribute('disabled','true');
            obj.controller.view.cmd_book_item_now.setAttribute('disabled','true');
            obj.controller.view.sel_patron.setAttribute('disabled','true');
            obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','true');
            obj.controller.view.sel_mark_items_missing.setAttribute('disabled','true');
            if (found_aou && found_aou_with_can_have_vols) {
                obj.controller.view.cmd_add_volumes.setAttribute('disabled','false');
                obj.controller.view.cmd_mark_library.setAttribute('disabled','false');
            }
            if (found_acn) {
                obj.controller.view.cmd_edit_volumes.setAttribute('disabled','false');
                obj.controller.view.cmd_delete_volumes.setAttribute('disabled','false');
                obj.controller.view.cmd_mark_volume.setAttribute('disabled','false');
                obj.controller.view.cmd_add_items.setAttribute('disabled','false');
                obj.controller.view.cmd_transfer_volume.setAttribute('disabled','false');
            }
            if (found_acp) {
                obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','false');
                obj.controller.view.sel_mark_items_missing.setAttribute('disabled','false');
                obj.controller.view.cmd_add_items_to_buckets.setAttribute('disabled','false');
                obj.controller.view.cmd_edit_items.setAttribute('disabled','false');
                obj.controller.view.cmd_replace_barcode.setAttribute('disabled','false');
                obj.controller.view.cmd_delete_items.setAttribute('disabled','false');
                obj.controller.view.cmd_print_spine_labels.setAttribute('disabled','false');
                obj.controller.view.cmd_transfer_items.setAttribute('disabled','false');
                obj.controller.view.sel_copy_details.setAttribute('disabled','false');
                obj.controller.view.cmd_create_brt.setAttribute('disabled','false');
                obj.controller.view.sel_patron.setAttribute('disabled','false');

                var L = 0; for (var k in sel_copy_libs) L++;
                if (L < 2) {
                    obj.controller.view.cmd_book_item_now.setAttribute('disabled','false');
                }
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
            obj.map_acn = {};
            obj.map_acp = {};
            obj.org_ids = obj.network.simple_request('FM_AOU_IDS_RETRIEVE_VIA_RECORD_ID.authoritative',[ obj.docid ]);
            if (typeof obj.org_ids.ilsevent != 'undefined') throw(obj.org_ids);
            JSAN.use('util.functional'); 
            obj.org_ids = util.functional.map_list( obj.org_ids, function (o) { return Number(o); });
            obj.show_my_libs( obj.default_lib.id() );
            // FIXME - we get a null from the copy_count call if we call it too quickly here
            setTimeout(
                function() {
                    obj.show_consortial_count();
                    if (typeof xulG.reload_opac == 'function') {
                        xulG.reload_opac();
                    }
                }, 2000
            );
        } catch(E) {
            this.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.refresh_list.error'),E);
        }
    },
}

dump('exiting cat.copy_browser.js\n');
