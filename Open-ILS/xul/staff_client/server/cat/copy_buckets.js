// vim:noet:sw=4:ts=4:
dump('entering cat.copy_buckets.js\n');

if (typeof cat == 'undefined') cat = {};
cat.copy_buckets = function (params) {

    JSAN.use('util.error'); this.error = new util.error();
    JSAN.use('util.network'); this.network = new util.network();
    JSAN.use('util.date');
    JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

cat.copy_buckets.prototype = {
    'selection_list1' : [],
    'selection_list2' : [],
    'bucket_id_name_map' : {},
    'copy_hash' : {},

    'render_pending_copies' : function() {
        var obj = this;
        obj.list1.clear();
        for (var i = 0; i < obj.copy_ids.length; i++) {
            var item = obj.prep_item_for_list( obj.copy_ids[i] );
            if (item) obj.list1.append( item );
        }
    },

    'init' : function( params ) {

        var obj = this;

        obj.copy_ids = params['copy_ids'] || [];

        JSAN.use('circ.util');
        var columns = circ.util.columns( 
            { 
                'barcode' : { 'hidden' : false },
                'title' : { 'hidden' : false },
                'location' : { 'hidden' : false },
                'call_number' : { 'hidden' : false },
                'status' : { 'hidden' : false },
                'deleted' : { 'hidden' : false },
            } 
        );

        JSAN.use('util.list'); 

        function retrieve_row(params) {
            var row = params.row;
            try {
                function handle_details(blob_req) {
                    try {
                        var blob = blob_req.getResultObject();
                        if (typeof blob.ilsevent != 'undefined') throw(blob);
                        row.my.acp = blob.copy;
                        row.my.mvr = blob.mvr;
                        row.my.acn = blob.volume;
                        row.my.ahr = blob.hold;
                        row.my.circ = blob.circ;
                        params.treeitem_node.setAttribute('retrieve_id', js2JSON( [ blob.copy.id(), blob.copy.barcode(), row.my.bucket_item_id ] ));
                        if (typeof params.on_retrieve == 'function') { params.on_retrieve(row); }

                    } catch(E) {
                        obj.error.standard_unexpected_error_alert($('catStrings').getFormattedString('staff.cat.copy_buckets.retrieve_row.error', [row.my.acp_id]), E);
                    }
                }
                if (obj.copy_hash[ row.my.copy_id ]) {
                    handle_details( { 'getResultObject' : function() { var copy_obj = obj.copy_hash[ row.my.copy_id ]; delete obj.copy_hash[ row.my.copy_id ]; return copy_obj; } } );
                } else {
                    obj.network.simple_request( 'FM_ACP_DETAILS', [ ses(), row.my.copy_id ], handle_details );
                }
            } catch(E) {
                obj.error.sdump('D_ERROR','retrieve_row: ' + E );
            }
            return row;
        }

        obj.list1 = new util.list('pending_copies_list');
        obj.list1.init(
            {
                'columns' : columns,
                'retrieve_row' : retrieve_row,
                'on_select' : function(ev) {
                    try {
                        JSAN.use('util.functional');
                        var sel = obj.list1.retrieve_selection();
                        obj.selection_list1 = util.functional.map_list(
                            sel,
                            function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
                        );
                        obj.error.sdump('D_TRACE','circ/copy_buckets: selection list 1 = ' + js2JSON(obj.selection_list1) );
                        if (obj.selection_list1.length == 0) {
                            obj.controller.view.copy_buckets_sel_add.disabled = true;
                        } else {
                            obj.controller.view.copy_buckets_sel_add.disabled = false;
                        }
                    } catch(E) {
                        alert('FIXME: ' + E);
                    }
                },

            }
        );

        obj.render_pending_copies();
    
        obj.list2 = new util.list('copies_in_bucket_list');
        obj.list2.init(
            {
                'columns' : columns,
                'retrieve_row' : retrieve_row,
                'on_select' : function(ev) {
                    try {
                        JSAN.use('util.functional');
                        var sel = obj.list2.retrieve_selection();
                        obj.selection_list2 = util.functional.map_list(
                            sel,
                            function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
                        );
                        obj.error.sdump('D_TRACE','circ/copy_buckets: selection list 2 = ' + js2JSON(obj.selection_list2) );
                        if (obj.selection_list2.length == 0) {
                            obj.controller.view.copy_buckets_delete_item.disabled = true;
                            obj.controller.view.copy_buckets_delete_item.setAttribute('disabled','true');
                            obj.controller.view.copy_buckets_export.disabled = true;
                            obj.controller.view.copy_buckets_export.setAttribute('disabled','true');
                        } else {
                            obj.controller.view.copy_buckets_delete_item.disabled = false;
                            obj.controller.view.copy_buckets_delete_item.setAttribute('disabled','false');
                            obj.controller.view.copy_buckets_export.disabled = false;
                            obj.controller.view.copy_buckets_export.setAttribute('disabled','false');
                        }
                    } catch(E) {
                        alert('FIXME: ' + E);
                    }
                },
            }
        );
        
        JSAN.use('util.controller'); obj.controller = new util.controller();
        obj.controller.init(
            {
                'control_map' : {
                    'list_actions1' : [
                        ['render'],
                        function(e) {
                            return function() {
                                e.appendChild( obj.list1.render_list_actions() );
                                obj.list1.set_list_actions(
                                    {
                                        'on_complete' : function() { }
                                    }
                                );
                            };
                        }
                    ],
                    'list_actions2' : [
                        ['render'],
                        function(e) {
                            return function() {
                                e.appendChild( obj.list2.render_list_actions() );
                                obj.list2.set_list_actions(
                                    {
                                        'on_complete' : function() { }
                                    }
                                );
                            };
                        }
                    ],
                    'copy_bucket_barcode_entry_textbox' : [
                        ['keypress'],
                        function(ev) {
                            if (ev.keyCode && ev.keyCode == 13) {
                                obj.scan_barcode();
                            }
                        }
                    ],
                    'cmd_copy_bucket_submit_barcode' : [
                        ['command'],
                        function() {
                            obj.scan_barcode();
                        }
                    ],
                    'copy_buckets_menulist_placeholder' : [
                        ['render'],
                        function(e) {
                            return function() {
                                JSAN.use('util.widgets'); JSAN.use('util.functional');
                                var items = [
                                    [$('catStrings').getString('staff.cat.copy_buckets.menulist.render.choose_bucket'),''],
                                    [$('catStrings').getString('staff.cat.copy_buckets.menulist.render.retrieve_bucket'),-1]
                                ].concat(
                                    util.functional.map_list(
                                        obj.network.simple_request(
                                            'BUCKET_RETRIEVE_VIA_USER',
                                            [ ses(), obj.data.list.au[0].id() ]
                                        ).copy,
                                        function(o) {
                                            obj.bucket_id_name_map[ o.id() ] = o.name();
                                            return [ o.name(), o.id() ];
                                        }
                                    ).sort( 
                                        function( a, b ) {
                                            if (a[0] < b[0]) return -1;
                                            if (a[0] > b[0]) return 1;
                                            return 0;
                                        }
                                    )
                                );
                                obj.error.sdump('D_TRACE','items = ' + js2JSON(items));
                                util.widgets.remove_children( e );
                                var ml = util.widgets.make_menulist(
                                    items
                                );
                                e.appendChild( ml );
                                ml.setAttribute('id','bucket_menulist');
                                ml.setAttribute('accesskey','');

                                function change_bucket(ev) {
                                    var bucket_id = ev.target.value;
                                    if (bucket_id < 0 ) {
                                        bucket_id = window.prompt($('catStrings').getString('staff.cat.copy_buckets.menulist.change_bucket.prompt'));
                                        ev.target.value = bucket_id;
                                        ev.target.setAttribute('value',bucket_id);
                                    }
                                    if (!bucket_id) return;
                                    var bucket = obj.network.simple_request(
                                        'BUCKET_FLESH',
                                        [ ses(), 'copy', bucket_id ]
                                    );
                                    if (typeof bucket.ilsevent != 'undefined') {
                                        if (bucket.ilsevent == 1506 /* CONTAINER_NOT_FOUND */) {
                                            alert($('catStrings').getFormattedString('staff.cat.copy_buckets.menulist.change_bucket.undefined', [bucket_id]));
                                        } else {
                                            obj.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_buckets.menulist.change_bucket.error'),bucket);
                                        }
                                        return;
                                    }
                                    try {
                                        var x = document.getElementById('info_box');
                                        x.setAttribute('hidden','false');
                                        x = document.getElementById('bucket_number');
                                        x.setAttribute('value',bucket.id());
                                        x = document.getElementById('bucket_name');
                                        x.setAttribute('value',bucket.name());
                                        x = document.getElementById('bucket_owner');
                                        var s = bucket.owner(); JSAN.use('patron.util');
                                        if (s && typeof s != "object") s = patron.util.retrieve_fleshed_au_via_id(ses(),s); 
                                        x.setAttribute('value',s.card().barcode() + " @ " + obj.data.hash.aou[ s.home_ou() ].shortname());

                                    } catch(E) {
                                        alert(E);
                                    }
                                    var items = bucket.items() || [];
                                    obj.list2.clear();
                                    for (var i = 0; i < items.length; i++) {
                                        var item = obj.prep_item_for_list( 
                                            items[i].target_copy(),
                                            items[i].id()
                                        );
                                        if (item) obj.list2.append( item );
                                    }
                                }

                                ml.addEventListener( 'change_bucket', change_bucket , false);
                                ml.addEventListener( 'command', function() {
                                    JSAN.use('util.widgets'); util.widgets.dispatch('change_bucket',ml);
                                }, false);
                                obj.controller.view.bucket_menulist = ml;
                                JSAN.use('util.widgets'); util.widgets.dispatch('change_bucket',ml);
                                document.getElementById('refresh').addEventListener( 'command', function() {
                                    JSAN.use('util.widgets'); util.widgets.dispatch('change_bucket',ml);
                                }, false);
                            };
                        },
                    ],

                    'copy_buckets_add' : [
                        ['command'],
                        function() {
                            try {
                                var bucket_id = obj.controller.view.bucket_menulist.value;
                                if (!bucket_id) return;
                                for (var i = 0; i < obj.copy_ids.length; i++) {
                                    var bucket_item = new ccbi();
                                    bucket_item.isnew('1');
                                    bucket_item.bucket(bucket_id);
                                    bucket_item.target_copy( obj.copy_ids[i] );
                                    try {
                                        var robj = obj.network.simple_request('BUCKET_ITEM_CREATE',
                                            [ ses(), 'copy', bucket_item ]);

                                        if (typeof robj == 'object') throw robj;

                                        var item = obj.prep_item_for_list( obj.copy_ids[i], robj );
                                        if (!item) continue;

                                        obj.list2.append( item );
                                    } catch(E) {
                                        obj.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_buckets.copy_buckets_add.error'), E);
                                    }
                                }
                            } catch(E) {
                                alert(E);
                            }
                        }
                    ],
                    'copy_buckets_sel_add' : [
                        ['command'],
                        function() {                                                        
                            var bucket_id = obj.controller.view.bucket_menulist.value;
                            if (!bucket_id) return;
                            for (var i = 0; i < obj.selection_list1.length; i++) {
                                var acp_id = obj.selection_list1[i][0];
                                //var barcode = obj.selection_list1[i][1];
                                var bucket_item = new ccbi();
                                bucket_item.isnew('1');
                                bucket_item.bucket(bucket_id);
                                bucket_item.target_copy( acp_id );
                                try {
                                    var robj = obj.network.simple_request('BUCKET_ITEM_CREATE',
                                        [ ses(), 'copy', bucket_item ]);

                                    if (typeof robj == 'object') throw robj;

                                    var item = obj.prep_item_for_list( acp_id, robj );
                                    if (!item) continue;

                                    obj.list2.append( item );
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_buckets.copy_buckets_sel_add.error'), E);
                                }
                            }

                        }
                    ],
                    'copy_buckets_export' : [
                        ['command'],
                        function() {                                                        
                            for (var i = 0; i < obj.selection_list2.length; i++) {
                                var acp_id = obj.selection_list2[i][0];
                                //var barcode = obj.selection_list1[i][1];
                                //var bucket_item_id = obj.selection_list1[i][2];
                                var item = obj.prep_item_for_list( acp_id );
                                if (item) {
                                    obj.list1.append( item );
                                    obj.copy_ids.push( acp_id );
                                }
                            }
                        }
                    ],

                    'copy_buckets_delete_item' : [
                        ['command'],
                        function() {
                            for (var i = 0; i < obj.selection_list2.length; i++) {
                                try {
                                    //var acp_id = obj.selection_list2[i][0];
                                    //var barcode = obj.selection_list2[i][1];
                                    var bucket_item_id = obj.selection_list2[i][2];
                                    var robj = obj.network.simple_request('BUCKET_ITEM_DELETE',
                                        [ ses(), 'copy', bucket_item_id ]);
                                    if (typeof robj == 'object') throw robj;
                                } catch(E) {
                                    obj.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_buckets.copy_buckets_delete_item.error'), E);
                                }
                            }
                            setTimeout(
                                function() {
                                    JSAN.use('util.widgets'); 
                                    util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
                                }, 0
                            );
                        }
                    ],
                    'copy_buckets_delete_bucket' : [
                        ['command'],
                        function() {
                            try {
                                var bucket = obj.controller.view.bucket_menulist.value;
                                var name = obj.bucket_id_name_map[ bucket ];
                                var conf = window.confirm($('catStrings').getFormattedString('staff.cat.copy_buckets.copy_buckets_delete_bucket.confirm', [name]));
                                if (!conf) return;
                                obj.list2.clear();
                                var robj = obj.network.simple_request('BUCKET_DELETE',[ses(),'copy',bucket]);
                                if (typeof robj == 'object') throw robj;
                                obj.controller.render('copy_buckets_menulist_placeholder');
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_buckets.copy_buckets_delete_bucket.error'),E);
                            }
                        }
                    ],
                    'copy_buckets_new_bucket' : [
                        ['command'],
                        function() {
                            try {
                                var name = prompt(
                                    $('catStrings').getString('staff.cat.copy_buckets.copy_buckets_new_bucket.prompt'),
                                    '',
                                    $('catStrings').getString('staff.cat.copy_buckets.copy_buckets_new_bucket.title')
                                );

                                if (name) {
                                    var bucket = new ccb();
                                    bucket.btype('staff_client');
                                    bucket.owner( obj.data.list.au[0].id() );
                                    bucket.name( name );

                                    var robj = obj.network.simple_request('BUCKET_CREATE',[ses(),'copy',bucket]);

                                    if (typeof robj == 'object') {
                                        if (robj.ilsevent == 1710 /* CONTAINER_EXISTS */) {
                                            alert($('catStrings').getString('staff.cat.copy_buckets.copy_buckets_new_bucket.container_exists'));
                                            return;
                                        }
                                        throw robj;
                                    }

                                    obj.controller.render('copy_buckets_menulist_placeholder');
                                    obj.controller.view.bucket_menulist.value = robj;
                                    setTimeout(
                                        function() {
                                            JSAN.use('util.widgets'); 
                                            util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
                                        }, 0
                                    );
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_buckets.copy_buckets_new_bucket.error'),E);
                            }
                        }
                    ],
                    'copy_buckets_batch_copy_edit' : [
                        ['command'],
                        function() {
                            try {

                                obj.list2.select_all();
                            
                                JSAN.use('util.widgets'); JSAN.use('util.functional');

                                var list = util.functional.map_list(
                                    obj.list2.dump_retrieve_ids(),
                                    function (o) {
                                        return JSON2js(o)[0]; // acp_id
                                    }
                                );

                                JSAN.use('cat.util'); cat.util.spawn_copy_editor( { 'copy_ids' : list, 'edit' : 1 } );

                                obj.render_pending_copies(); // FIXME -- need a generic refresh for lists
                                setTimeout(
                                    function() {
                                        util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
                                    }, 0
                                );
                            } catch(E) {
                                alert( js2JSON(E) );
                            }
                        }
                    ],
                    'copy_buckets_batch_copy_delete' : [
                        ['command'],
                        function() {
                            try {
                            
                                obj.list2.select_all();

                                JSAN.use('util.widgets'); JSAN.use('util.functional');

                                var list = util.functional.map_list(
                                    obj.list2.dump_retrieve_ids(),
                                    function (o) {
                                        return JSON2js(o)[0]; // acp_id
                                    }
                                );

                                var copies = util.functional.map_list(
                                    list,
                                    function (acp_id) {
                                        return obj.network.simple_request('FM_ACP_RETRIEVE',[acp_id]);
                                    }
                                );

                                for (var i = 0; i < copies.length; i++) {
                                    copies[i].ischanged(1);
                                    copies[i].isdeleted(1);
                                }

                                var robj = obj.network.simple_request(
                                    'FM_ACP_FLESHED_BATCH_UPDATE',
                                    [ ses(), copies, true],
                                    null, // no callback
                                    {
                                        'title' : document.getElementById('catStrings').getString('staff.cat.copy_buckets.batch.error'),
                                        'overridable_events' : [
                                            1208 /* TITLE_LAST_COPY */,
                                            1227 /* COPY_DELETE_WARNING */
                                        ]
                                    }
                                );
                                if (typeof robj.ilsevent != 'undefined') {
                                    switch(Number(robj.ilsevent)) {
                                        case 1208 /* TITLE_LAST_COPY */ :
                                        case 1227 /* COPY_DELETE_WARNING */ :
                                        case 5000 /* PERM_DENIED */ :
                                            // ignore this
                                        break;
                                        default:
                                            obj.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_buckets.batch.error'), robj);
                                    }
                                }

                                obj.render_pending_copies(); // FIXME -- need a generic refresh for lists
                                setTimeout(
                                    function() {
                                        JSAN.use('util.widgets'); 
                                        util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
                                    }, 0
                                );
                            } catch(E) {
                                alert( js2JSON(E) );
                            }
                        }
                    ],

                    'cmd_request_items' : [
                        ['command'],
                        function() {
                            try {
                                obj.list2.select_all();

                                var copy_ids = util.functional.map_list(
                                    obj.list2.dump_retrieve_ids(),
                                    function (o) {
                                        return JSON2js(o)[0]; // acp_id
                                    }
                                )

                                JSAN.use('cat.util');
                                cat.util.request_items(copy_ids); 

                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_buckets.copy_buckets_transfer_to_volume.error'), E);
                            }
                        }
                    ],

                    'copy_buckets_transfer_to_volume' : [
                        ['command'],
                        function() {
                            try {
                                obj.list2.select_all();

                                obj.data.stash_retrieve();
                                if (!obj.data.marked_volume) {
                                    alert($('catStrings').getString('staff.cat.copy_buckets.copy_buckets_transfer_to_volume.no_volume'));
                                    return;
                                }

                                var copy_ids = util.functional.map_list(
                                    obj.list2.dump_retrieve_ids(),
                                    function (o) {
                                        return JSON2js(o)[0]; // acp_id
                                    }
                                )

                                var volume = obj.network.simple_request('FM_ACN_RETRIEVE.authoritative',[ obj.data.marked_volume ]);

                                var msg = $('catStrings').getFormattedString(
                                    'staff.cat.copy_buckets.copy_buckets_transfer_to_volume.confirm',
                                    [
                                        obj.controller.view.bucket_menulist.getAttribute('label'),
                                        volume.label(),
                                        obj.data.hash.aou[ volume.owning_lib() ].shortname()
                                    ]
                                );

                                JSAN.use('cat.util'); cat.util.transfer_copies( { 
                                    'copy_ids' : copy_ids, 
                                    'message' : msg, 
                                    'docid' : volume.record(),
                                    'volume_label' : volume.label(),
                                    'owning_lib' : volume.owning_lib(),
                                } );

                                obj.render_pending_copies(); // FIXME -- need a generic refresh for lists
                                setTimeout(
                                    function() {
                                        JSAN.use('util.widgets'); 
                                        util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
                                    }, 0
                                );
                                
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_buckets.copy_buckets_transfer_to_volume.error'), E);
                            }
                        }
                    ],
                    'cmd_broken' : [
                        ['command'],
                        function() { alert($('commonStrings').getString('common.unimplemented')); }
                    ],
                    'cmd_copy_buckets_print' : [
                        ['command'],
                        function() {
                            JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
                            obj.list2.on_all_fleshed = function() {
                                try {
                                    dump( js2JSON( obj.list2.dump_with_keys() ) + '\n' );
                                    data.stash_retrieve();
                                    var lib = data.hash.aou[ data.list.au[0].ws_ou() ];
                                    lib.children(null);
                                    var p = { 
                                        'lib' : lib,
                                        'staff' : data.list.au[0],
                                        'header' : data.print_list_templates.item_status.header,
                                        'line_item' : data.print_list_templates.item_status.line_item,
                                        'footer' : data.print_list_templates.item_status.footer,
                                        'type' : data.print_list_templates.item_status.type,
                                        'list' : obj.list2.dump_with_keys(),
                                        'context' : data.print_list_templates.item_status.context,
                                    };
                                    JSAN.use('util.print'); var print = new util.print();
                                    print.tree_list( p );
                                    setTimeout(function(){obj.list2.on_all_fleshed = null;},0);
                                } catch(E) {
                                    alert(E); 
                                }
                            }
                            obj.list2.full_retrieve();
                        }
                    ],
                    'cmd_copy_buckets_export' : [
                        ['command'],
                        function() {
                            obj.list2.dump_csv_to_clipboard();
                        }
                    ],
                    'cmd_copy_buckets_reprint' : [
                        ['command'],
                        function() {
                        }
                    ],
                    'cmd_export_to_copy_status' : [
                        ['command'],
                        function() {
                            try {
                                obj.list2.on_all_fleshed =
                                    function() {
                                        try {
                                            obj.list2.select_all();
                                            JSAN.use('util.functional');
                                            var barcodes = util.functional.map_list(
                                                obj.list2.dump_retrieve_ids(),
                                                function(o) { return JSON2js(o)[1]; }
                                            );
                                            var url = urls.XUL_COPY_STATUS;
                                            xulG.new_tab( url, {}, { 'barcodes' : barcodes });
                                            setTimeout(function(){obj.list2.on_all_fleshed = null;},0);
                                        } catch(E) {
                                            obj.error.standard_unexpected_error_alert('export to copy status',E);
                                        }
                                    }
                                obj.list2.full_retrieve();
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_buckets.cmd_export_to_copy_status.error'), E);
                            }
                        }
                    ],
                }
            }
        );
        this.controller.render();

        if (typeof xulG == 'undefined') {
            obj.controller.view.cmd_export_to_copy_status.disabled = true;
            obj.controller.view.cmd_export_to_copy_status.setAttribute('disabled',true);
        }
    
    },

    'prep_item_for_list' : function(acp_id,bucket_item_id) {
        var obj = this;
        try {
            var item = {
                'retrieve_id' : js2JSON( [ acp_id, null, bucket_item_id ] ),
                'row' : {
                    'my' : {
                        'acn' : -2,
                        'copy_id' : acp_id,
                        'bucket_item_id' : bucket_item_id
                    }
                }
            };
            return item;
        } catch(E) {
            obj.error.standard_unexpected_error_alert($('catStrings').getString('staff.cat.copy_buckets.prep_item_for_list.error'), E);
            return null;
        }

    },

    'scan_barcode' : function() {
        var obj = this;
        try {
            var barcode = obj.controller.view.copy_bucket_barcode_entry_textbox.value;
            var barcode_object = xulG.get_barcode(window, 'asset', barcode);
            // user_false means the user said "None of the above", so abort without further prompts/actions
            if(barcode_object == "user_false") return;
            if(barcode_object && barcode_object.barcode) {
                barcode = barcode_object.barcode;
            }

            var copy_obj = obj.network.simple_request('FM_ACP_DETAILS_VIA_BARCODE',[ses(),barcode]);
            if (copy_obj == null) {
                throw(document.getElementById('circStrings').getString('staff.circ.copy_status.status.null_result'));
            } else if (copy_obj.ilsevent) {
                switch(Number(copy_obj.ilsevent)) {
                    case -1: 
                        obj.error.standard_network_error_alert(); 
                        obj.controller.view.copy_bucket_barcode_entry_textbox.select();
                        obj.controller.view.copy_bucket_barcode_entry_textbox.focus();
                        return;
                    break;
                    case 1502 /* ASSET_COPY_NOT_FOUND */ :
                        obj.error.yns_alert(
                            document.getElementById('circStrings').getFormattedString('staff.circ.copy_status.status.copy_not_found', [barcode]),
                            document.getElementById('circStrings').getString('staff.circ.copy_status.status.not_cataloged'),
                            document.getElementById('circStrings').getString('staff.circ.copy_status.ok'),
                            null,
                            null,
                            document.getElementById('circStrings').getString('staff.circ.confirm.msg')
                        );
                        obj.controller.view.copy_bucket_barcode_entry_textbox.select();
                        obj.controller.view.copy_bucket_barcode_entry_textbox.focus();
                        return;
                    break;
                    default: 
                        throw(details); 
                    break;
                }
            }
            var item = obj.prep_item_for_list( copy_obj.copy.id() );
            if (item) {
                obj.copy_ids.push( copy_obj.copy.id() );
                obj.copy_hash[ copy_obj.copy.id() ] = copy_obj;
                obj.list1.append( item );
            }
            obj.controller.view.copy_bucket_barcode_entry_textbox.value = '';
            obj.controller.view.copy_bucket_barcode_entry_textbox.focus();
        } catch(E) {
            obj.controller.view.copy_bucket_barcode_entry_textbox.select();
            obj.controller.view.copy_bucket_barcode_entry_textbox.focus();
            alert(E);
        }
    }    
}

dump('exiting cat.copy_buckets.js\n');
