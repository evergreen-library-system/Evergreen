dump('entering cat.record_buckets.js\n');

function $(id) { return document.getElementById(id); }

if (typeof cat == 'undefined') cat = {};
cat.record_buckets = function (params) {

    JSAN.use('util.error'); this.error = new util.error();
    JSAN.use('util.network'); this.network = new util.network();
    JSAN.use('util.date');
    JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
    var x = document.getElementById("record_buckets_tabbox");
    if (x) {
        x.addEventListener(
            'select',
            function(ev) {
                if (ev.target.tagName == 'tabpanels') {
                    for (var i = 0; i < ev.target.childNodes.length; i++) {
                        var p = ev.target.childNodes[i].firstChild;
                        p.hidden = x.selectedIndex != i;
                    }
                }
            },
            false
        );
        x.selectedIndex = 2;
        for (var i = 0; i < x.lastChild.childNodes.length; i++) {
            var p = x.lastChild.childNodes[i].firstChild;
            p.hidden = x.selectedIndex != i;
        }
    }
};

cat.record_buckets.pick_file = function (defaultFileName) {
    var nsIFilePicker = Components.interfaces.nsIFilePicker;
    var fp = Components.classes["@mozilla.org/filepicker;1"].createInstance( nsIFilePicker );

    fp.init( window, $("catStrings").getString('staff.cat.record_buckets.save_file_as'), nsIFilePicker.modeSave );
    if (defaultFileName)
        fp.defaultString = defaultFileName;

    fp.appendFilters( nsIFilePicker.filterAll );

    var result = fp.show(); 
    if ( (result == nsIFilePicker.returnOK || result == nsIFilePicker.returnReplace) && fp.file ) {
        return fp.file;
    } else {
        return null;
    }
};

cat.record_buckets.export_records = function(obj, output_type) {
    try {
        obj.list2.select_all();
        obj.data.stash_retrieve();
        JSAN.use('util.functional');

        var record_ids = util.functional.map_list(
            obj.list2.dump_retrieve_ids(),
            function (o) { return JSON2js(o).docid }
        );

        var persist = Components.classes["@mozilla.org/embedding/browser/nsWebBrowserPersist;1"]
            .createInstance(Components.interfaces.nsIWebBrowserPersist);

        var proto_uri = 'https://' + window.location.hostname + '/exporter?format=' + output_type + '&ses=' + ses();

        dump('Record Export URI is ' + proto_uri + '&id=' + record_ids.join('&id=') + '\n');

        var uri = Components.classes["@mozilla.org/network/io-service;1"]
            .getService(Components.interfaces.nsIIOService)
            .newURI( proto_uri + '&id=' + record_ids.join('&id='), null, null );

        var file = cat.record_buckets.pick_file('bucket.' + output_type);
                                
        if (file) {
            persist.saveURI(uri,null,null,null,null,file);
        } else {
            alert( $("catStrings").getString('staff.cat.record_buckets.export_records.alert') );
        }

    } catch(E) {
        obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.record_buckets.export_records.std_unexpected_error'), E);
    }
};


cat.record_buckets.prototype = {
    'selection_list0' : [],
    'selection_list1' : [],
    'selection_list2' : [],
    'bucket_id_name_map' : {},

    'render_pending_records' : function() {
        var obj = this;
        obj.list1.clear();
        for (var i = 0; i < obj.record_ids.length; i++) {
            var item = obj.prep_record_for_list( obj.record_ids[i] );
            if (item) obj.list1.append( item );
        }
    },

    'init' : function( params ) {

        var obj = this;

        obj.record_ids = params['record_ids'] || [];

        JSAN.use('circ.util');
        var columns = circ.util.columns( 
            { 
                'title' : { 'hidden' : false },
                'author' : { 'hidden' : false },
                'edition' : { 'hidden' : false },
                'publisher' : { 'hidden' : false },
                'pubdate' : { 'hidden' : false },
                'isbn' : { 'hidden' : false },
                'tcn' : { 'hidden' : false }
            } 
        );

        JSAN.use('util.list'); 

        function retrieve_row(params) {
            var row = params.row;
            try {
                obj.network.simple_request( 'MODS_SLIM_RECORD_RETRIEVE.authoritative', [ row.my.docid ],
                    function(req) {
                        try {
                            var record = req.getResultObject();
                            if (typeof req.ilsevent != 'undefined') throw(req);
                            row.my.mvr = record;
                            if (typeof params.on_retrieve == 'function') { params.on_retrieve(row); }

                        } catch(E) {
                            obj.error.standard_unexpected_error_alert(
                              $("catStrings").getFormattedString('staff.cat.record_buckets.retrieve_row.std_unexpected_error', [row.my.docid]), E);
                        }
                    }
                );
            } catch(E) {
                obj.error.sdump('D_ERROR','retrieve_row: ' + E );
            }
            return row;
        }

        obj.list0 = new util.list('record_query_list');
        obj.list0.init(
            {
                'columns' : columns,
                'retrieve_row' : retrieve_row,
                'on_select' : function(ev) {
                    try {
                        JSAN.use('util.functional');
                        var sel = obj.list0.retrieve_selection();
                        obj.controller.view.sel_clip1.setAttribute('disabled', sel.length < 1 ? "true" : "false");
                        obj.selection_list0 = util.functional.map_list(
                            sel,
                            function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
                        );
                        obj.error.sdump('D_TRACE','circ/record_buckets: selection list 0 = ' + js2JSON(obj.selection_list1) );
                        if (obj.selection_list0.length == 0) {
                            obj.controller.view.cmd_add_sel_query_to_pending.setAttribute('disabled','true');
                        } else {
                            obj.controller.view.cmd_add_sel_query_to_pending.setAttribute('disabled','false');
                        }
                    } catch(E) {
                        alert('FIXME: ' + E);
                    }
                }

            }
        );

        obj.list1 = new util.list('pending_records_list');
        obj.list1.init(
            {
                'columns' : columns,
                'retrieve_row' : retrieve_row,
                'on_select' : function(ev) {
                    try {
                        JSAN.use('util.functional');
                        var sel = obj.list1.retrieve_selection();
                        obj.controller.view.sel_clip1.setAttribute('disabled', sel.length < 1 ? "true" : "false");
                        obj.selection_list1 = util.functional.map_list(
                            sel,
                            function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
                        );
                        obj.error.sdump('D_TRACE','circ/record_buckets: selection list 1 = ' + js2JSON(obj.selection_list1) );
                        if (obj.selection_list1.length == 0) {
                            obj.controller.view.cmd_add_sel_pending_to_record_bucket.setAttribute('disabled','true');
                        } else {
                            obj.controller.view.cmd_add_sel_pending_to_record_bucket.setAttribute('disabled','false');
                        }
                    } catch(E) {
                        alert('FIXME: ' + E);
                    }
                }

            }
        );

        obj.render_pending_records();
    
        obj.list2 = new util.list('records_in_bucket_list');
        obj.list2.init(
            {
                'columns' : columns,
                'retrieve_row' : retrieve_row,
                'on_select' : function(ev) {
                    try {
                        JSAN.use('util.functional');
                        var sel = obj.list2.retrieve_selection();
                        obj.controller.view.sel_clip2.setAttribute('disabled', sel.length < 1 ? "true" : "false");
                        obj.selection_list2 = util.functional.map_list(
                            sel,
                            function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
                        );
                        obj.error.sdump('D_TRACE','circ/record_buckets: selection list 2 = ' + js2JSON(obj.selection_list2) );
                        if (obj.selection_list2.length == 0) {
                            obj.controller.view.cmd_record_buckets_delete_item.setAttribute('disabled','true');
                            obj.controller.view.cmd_record_buckets_to_pending_buckets.setAttribute('disabled','true');
                        } else {
                            obj.controller.view.cmd_record_buckets_delete_item.setAttribute('disabled','false');
                            obj.controller.view.cmd_record_buckets_to_pending_buckets.setAttribute('disabled','false');
                        }
                    } catch(E) {
                        alert('FIXME: ' + E);
                    }
                }
            }
        );
        
        JSAN.use('util.controller'); obj.controller = new util.controller();
        obj.controller.init(
            {
                'control_map' : {
                    'save_columns2' : [
                        ['command'],
                        function() { obj.list2.save_columns(); }
                    ],
                    'save_columns1' : [
                        ['command'],
                        function() { obj.list1.save_columns(); }
                    ],
                    'save_columns0' : [
                        ['command'],
                        function() { obj.list0.save_columns(); }
                    ],
                    'sel_clip2' : [
                        ['command'],
                        function() { obj.list2.clipboard(); }
                    ],
                    'sel_clip1' : [
                        ['command'],
                        function() { obj.list1.clipboard(); }
                    ],
                    'sel_clip0' : [
                        ['command'],
                        function() { obj.list0.clipboard(); }
                    ],
                    'record_query_input' : [
                        ['render'],
                        function(ev) {
                            ev.addEventListener('keypress',function(ev){
                                if (ev.target.tagName != 'textbox') return;
                                if (ev.keyCode == 13 /* enter */ || ev.keyCode == 77 /* enter on a mac */) setTimeout( function() { obj.submit(); }, 0);
                            },false);
                        }
                    ],
                    'cmd_submit_query' : [
                        ['command'],
                        function() { obj.submit(); }
                    ],
                    'record_buckets_menulist_placeholder' : [
                        ['render'],
                        function(e) {
                            return function() {
                                JSAN.use('util.widgets'); JSAN.use('util.functional');
                                var buckets = obj.network.simple_request(
                                    'BUCKET_RETRIEVE_VIA_USER',
                                    [ ses(), obj.data.list.au[0].id() ]
                                );
                                if (typeof buckets.ilsevent != 'undefined') {
                                    obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.record_buckets.buckets.std_unexpected_error'), buckets);
                                    return;
                                }
                                var items = [
                                    [$("catStrings").getString('staff.cat.record_buckets.menulist_placeholder.item1'),''],
                                    [$("catStrings").getString('staff.cat.record_buckets.menulist_placeholder.item2'),-1]
                                ].concat(
                                    util.functional.map_list(
                                        util.functional.filter_list(
                                            buckets.biblio,
                                            function(o) {
                                                return (o.btype() == 'staff_client' || o.btype() == 'vandelay_queue');
                                            }
                                        ),
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
                                        bucket_id = window.prompt($("catStrings").getString('staff.cat.record_buckets.change_bucket.bucket_id'));
                                        ev.target.value = bucket_id;
                                        ev.target.setAttribute('value',bucket_id);
                                    }
                                    if (!bucket_id) return;
                                    var x = document.getElementById('info_box');
                                    if (x) x.setAttribute('hidden','true');
                                    x = document.getElementById('bucket_item_count');
                                    if (x) x.setAttribute('label','');
                                    obj.controller.view.cmd_record_buckets_delete_bucket.setAttribute('disabled','true');
                                    obj.controller.view.cmd_record_buckets_refresh.setAttribute('disabled','true');
                                    obj.controller.view.record_buckets_export_records.disabled = true;
                                    obj.controller.view.cmd_merge_records.setAttribute('disabled','true');
                                    obj.controller.view.cmd_delete_records.setAttribute('disabled','true');
                                    obj.controller.view.cmd_sel_opac.setAttribute('disabled','true');
                                    obj.controller.view.cmd_transfer_title_holds.setAttribute('disabled','true');
                                    obj.controller.view.cmd_marc_batch_edit.setAttribute('disabled','true');
                                    obj.controller.view.record_buckets_list_actions.disabled = true;
                                    var bucket = obj.network.simple_request(
                                        'BUCKET_FLESH',
                                        [ ses(), 'biblio', bucket_id ]
                                    );
                                    if (typeof bucket.ilsevent != 'undefined') {
                                        if (bucket.ilsevent == 1506 /* CONTAINER_NOT_FOUND */) {
                                            alert(catStrings.getFormattedString('staff.cat.record_buckets.menulist.change_bucket.undefined',[bucket_id]));
                                        } else {
                                            obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.record_buckets.change_bucket.error'),bucket);
                                        }
                                        return;
                                    }
                                    try {
                                        obj.controller.view.cmd_record_buckets_delete_bucket.setAttribute('disabled','false');
                                        obj.controller.view.cmd_record_buckets_refresh.setAttribute('disabled','false');
                                        obj.controller.view.record_buckets_export_records.disabled = false;
                                        obj.controller.view.cmd_merge_records.setAttribute('disabled','false');
                                        obj.controller.view.cmd_delete_records.setAttribute('disabled','false');
                                        obj.controller.view.cmd_sel_opac.setAttribute('disabled','false');
                                        obj.controller.view.cmd_transfer_title_holds.setAttribute('disabled','false');
                                        obj.controller.view.cmd_marc_batch_edit.setAttribute('disabled','false');
                                        obj.controller.view.record_buckets_list_actions.disabled = false;

                                        var x = document.getElementById('info_box');
                                        x.setAttribute('hidden','false');
                                        x = document.getElementById('bucket_number');
                                        x.setAttribute('value',bucket.id());
                                        x = document.getElementById('bucket_name');
                                        x.setAttribute('value',bucket.name());
                                        x = document.getElementById('bucket_owner');
                                        var s = bucket.owner(); JSAN.use('patron.util');
                                        if (s && typeof s != "object") s = patron.util.retrieve_fleshed_au_via_id(ses(),s); 
                                        x.setAttribute('value',s.family_name() + ' (' + s.card().barcode() + ") @ " + obj.data.hash.aou[ s.home_ou() ].shortname());
                                    } catch(E) {
                                        alert(E);
                                    }
                                    var items = bucket.items() || [];
                                    obj.list2.clear();
                                    var x = document.getElementById('bucket_item_count');
                                    if (x && catStrings) x.setAttribute('value',catStrings.getFormattedString('cat.total_bucket_items_in_bucket',[items.length]));
                                    for (var i = 0; i < items.length; i++) {
                                        var item = obj.prep_record_for_list( 
                                            items[i].target_biblio_record_entry(),
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
                            };
                        },
                    ],

                    'cmd_record_buckets_refresh' : [
                        ['command'],
                        function() {
                            JSAN.use('util.widgets'); util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
                        }
                    ],

                    'cmd_add_all_query_to_pending' : [
                        ['command'],
                        function() {
                            obj.list0.select_all();
                            for (var i = 0; i < obj.selection_list0.length; i++) {
                                var docid = obj.selection_list0[i].docid;
                                try {
                                    var item = obj.prep_record_for_list( docid );
                                    if (!item) continue;
                                    obj.list1.append( item );
                                    obj.record_ids.push( docid );
                                } catch(E) {
                                    alert( js2JSON(E) );
                                }
                            }
                        }
                    ],

                    'cmd_add_sel_query_to_pending' : [
                        ['command'],
                        function() {
                            for (var i = 0; i < obj.selection_list0.length; i++) {
                                var docid = obj.selection_list0[i].docid;
                                try {
                                    var item = obj.prep_record_for_list( docid );
                                    if (!item) continue;
                                    obj.list1.append( item );
                                    obj.record_ids.push( docid );
                                } catch(E) {
                                    alert( js2JSON(E) );
                                }
                            }
                        }
                    ],


                    'cmd_add_all_pending_to_record_bucket' : [
                        ['command'],
                        function() {
                            var bucket_id = obj.controller.view.bucket_menulist.value;
                            if (!bucket_id) return;
                            for (var i = 0; i < obj.record_ids.length; i++) {
                                var bucket_item = new cbrebi();
                                bucket_item.isnew('1');
                                bucket_item.bucket(bucket_id);
                                bucket_item.target_biblio_record_entry( obj.record_ids[i] );
                                try {
                                    var robj = obj.network.simple_request('BUCKET_ITEM_CREATE',
                                        [ ses(), 'biblio', bucket_item ]);

                                    if (typeof robj == 'object') throw robj;

                                    var item = obj.prep_record_for_list( obj.record_ids[i], robj );
                                    if (!item) continue;

                                    obj.list2.append( item );
                                } catch(E) {
                                    alert( js2JSON(E) );
                                }
                            }
                        }
                    ],
                    'cmd_add_sel_pending_to_record_bucket' : [
                        ['command'],
                        function() {                                                        
                            var bucket_id = obj.controller.view.bucket_menulist.value;
                            if (!bucket_id) return;
                            for (var i = 0; i < obj.selection_list1.length; i++) {
                                var docid = obj.selection_list1[i].docid;
                                var bucket_item = new cbrebi();
                                bucket_item.isnew('1');
                                bucket_item.bucket(bucket_id);
                                bucket_item.target_biblio_record_entry( docid );
                                try {
                                    var robj = obj.network.simple_request('BUCKET_ITEM_CREATE',
                                        [ ses(), 'biblio', bucket_item ]);

                                    if (typeof robj == 'object') throw robj;

                                    var item = obj.prep_record_for_list( docid, robj );
                                    if (!item) continue;

                                    obj.list2.append( item );
                                } catch(E) {
                                    alert( js2JSON(E) );
                                }
                            }

                        }
                    ],
                    'cmd_record_buckets_to_pending_buckets' : [
                        ['command'],
                        function() {                                                        
                            for (var i = 0; i < obj.selection_list2.length; i++) {
                                var docid = obj.selection_list2[i].docid;
                                var item = obj.prep_record_for_list( docid );
                                if (item) {
                                    obj.list1.append( item );
                                    obj.record_ids.push( docid );
                                }
                            }
                        }
                    ],

                    'cmd_record_buckets_delete_item' : [
                        ['command'],
                        function() {
                            for (var i = 0; i < obj.selection_list2.length; i++) {
                                try {
                                    var bucket_item_id = obj.selection_list2[i].bucket_item_id;
                                    var robj = obj.network.simple_request('BUCKET_ITEM_DELETE',
                                        [ ses(), 'biblio', bucket_item_id ]);
                                    if (typeof robj == 'object') throw robj;
                                } catch(E) {
                                    alert(js2JSON(E));
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
                    'cmd_record_buckets_delete_bucket' : [
                        ['command'],
                        function() {
                            try {
                                var bucket = obj.controller.view.bucket_menulist.value;
                                var name = obj.bucket_id_name_map[ bucket ];
                                var conf = window.confirm($("catStrings").getFormattedString('staff.cat.record_buckets.delete_bucket_named', [name]));
                                if (!conf) return;
                                obj.list2.clear();
                                var robj = obj.network.simple_request('BUCKET_DELETE',[ses(),'biblio',bucket]);
                                if (typeof robj == 'object') throw robj;
                                var x = document.getElementById('info_box');
                                x.setAttribute('hidden','true');
                                obj.controller.view.cmd_record_buckets_delete_bucket.setAttribute('disabled','true');
                                obj.controller.view.cmd_record_buckets_refresh.setAttribute('disabled','true');
                                obj.controller.view.record_buckets_export_records.disabled = true;
                                obj.controller.view.cmd_merge_records.setAttribute('disabled','true');
                                obj.controller.view.cmd_delete_records.setAttribute('disabled','true');
                                obj.controller.view.cmd_sel_opac.setAttribute('disabled','true');
                                obj.controller.view.cmd_transfer_title_holds.setAttribute('disabled','true');
                                obj.controller.view.cmd_marc_batch_edit.setAttribute('disabled','true');
                                obj.controller.view.record_buckets_list_actions.disabled = true;
                                obj.controller.render('record_buckets_menulist_placeholder');
                                setTimeout(
                                    function() {
                                        JSAN.use('util.widgets'); 
                                        util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
                                    }, 0
                                );

                            } catch(E) {
                                alert('FIXME: ' + E);
                            }
                        }
                    ],
                    'cmd_record_buckets_new_bucket' : [
                        ['command'],
                        function() {
                            try {
                                var name = prompt(
                                    $("catStrings").getString('staff.cat.record_buckets.new_bucket.bucket_prompt'),
                                    '',
                                    $("catStrings").getString('staff.cat.record_buckets.new_bucket.bucket_prompt_title')
                                );

                                if (name) {
                                    var bucket = new cbreb();
                                    bucket.btype('staff_client');
                                    bucket.owner( obj.data.list.au[0].id() );
                                    bucket.name( name );

                                    var robj = obj.network.simple_request('BUCKET_CREATE',[ses(),'biblio',bucket]);

                                    if (typeof robj == 'object') {
                                        if (robj.ilsevent == 1710 /* CONTAINER_EXISTS */) {
                                            alert($("catStrings").getString('staff.cat.record_buckets.new_bucket.same_name_alert'));
                                            return;
                                        }
                                        throw robj;
                                    }

                                    obj.controller.render('record_buckets_menulist_placeholder');
                                    obj.controller.view.bucket_menulist.value = robj;
                                    setTimeout(
                                        function() {
                                            JSAN.use('util.widgets'); 
                                            util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
                                        }, 0
                                    );
                                }
                            } catch(E) {
                                alert( js2JSON(E) );
                            }
                        }
                    ],
                    
                    'cmd_record_query_csv_to_clipboard' : [ ['command'], function() { obj.list0.dump_csv_to_clipboard(); } ], 
                    'cmd_pending_buckets_csv_to_clipboard' : [ ['command'], function() { obj.list1.dump_csv_to_clipboard(); } ], 
                    'cmd_record_buckets_csv_to_clipboard' : [ ['command'], function() { obj.list2.dump_csv_to_clipboard(); } ],
                    'cmd_record_query_csv_to_printer' : [ ['command'], function() { obj.list0.dump_csv_to_printer(); } ],
                    'cmd_pending_buckets_csv_to_printer' : [ ['command'], function() { obj.list1.dump_csv_to_printer(); } ],
                    'cmd_record_buckets_csv_to_printer' : [ ['command'], function() { obj.list2.dump_csv_to_printer(); } ], 
                    'cmd_record_query_csv_to_file' : [ ['command'], function() { obj.list0.dump_csv_to_file( { 'defaultFileName' : 'pending_records.txt' } ); } ],
                    'cmd_pending_buckets_csv_to_file' : [ ['command'], function() { obj.list1.dump_csv_to_file( { 'defaultFileName' : 'pending_records.txt' } ); } ],
                    'cmd_record_buckets_csv_to_file' : [ ['command'], function() { obj.list2.dump_csv_to_file( { 'defaultFileName' : 'bucket_records.txt' } ); } ], 

                    'cmd_export_records_usmarc' : [
                        ['command'],
                        function () { return cat.record_buckets.export_records(obj, 'usmarc') }
                    ],

                    'cmd_export_records_unimarc' : [
                        ['command'],
                        function () { return cat.record_buckets.export_records(obj, 'unimarc') }
                    ],

                    'cmd_export_records_xml' : [
                        ['command'],
                        function () { return cat.record_buckets.export_records(obj, 'xml') }
                    ],

                    'cmd_export_records_bre' : [
                        ['command'],
                        function () { return cat.record_buckets.export_records(obj, 'bre') }
                    ],

                    'cmd_merge_records' : [
                        ['command'],
                        function() {
                            try {
                                obj.list2.select_all();
                                obj.data.stash_retrieve();
                                JSAN.use('util.functional');

                                var record_ids = util.functional.map_list(
                                    obj.list2.dump_retrieve_ids(),
                                    function (o) {
                                        return JSON2js(o).docid; // docid
                                    }
                                );

                                xulG.new_tab(
                                    'oils://remote/xul/server/cat/bibs_abreast.xul',{
                                        'tab_name' : $("catStrings").getString('staff.cat.record_buckets.merge_records.fancy_prompt_title')
                                    },{
                                        'merge' : true,
                                        'on_merge' : function() {
                                            obj.render_pending_records(); // FIXME -- need a generic refresh for lists
                                            setTimeout(
                                                function() {
                                                    JSAN.use('util.widgets'); 
                                                    util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
                                                }, 0
                                            );
                                        },
                                        'record_ids':record_ids
                                    }
                                );

                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.record_buckets.merge_records.catch.std_unex_error'),E);
                            }

                        }
                    ],
                    
                    'cmd_delete_records' : [
                        ['command'],
                        function() {
                            try {
                                obj.list2.select_all();
                                obj.data.stash_retrieve();
                                JSAN.use('util.functional');

                                var record_ids = util.functional.map_list(
                                    obj.list2.dump_retrieve_ids(),
                                    function (o) {
                                        return JSON2js(o).docid; // docid
                                    }
                                );

                                var top_xml = '<vbox xmlns="http://www.mozilla.org/keymaster/gatekeeper/there.is.only.xul" flex="1" >';
                                top_xml += '<description>' + $("catStrings").getString('staff.cat.record_buckets.delete_records.xml1') + '</description>';
                                top_xml += '<hbox>';
                                top_xml += '<button id="lead" disabled="false" label="'
                                        + $("catStrings").getString('staff.cat.record_buckets.delete_records.button.label')
                                        + '" name="fancy_submit"/>';
                                top_xml += '<button label="'
                                        + $("catStrings").getString('staff.cat.record_buckets.delete_records.cancel_button.label') +'" accesskey="'
                                        + $("catStrings").getString('staff.cat.record_buckets.delete_records.cancel_button.accesskey') +'" name="fancy_cancel"/></hbox></vbox>';

                                var xml = '<form xmlns="http://www.w3.org/1999/xhtml">';
                                xml += '<table><tr valign="top">';
                                for (var i = 0; i < record_ids.length; i++) {
                                    xml += '<td>' + $("catStrings").getFormattedString('staff.cat.record_buckets.delete_records.xml2', [record_ids[i]]) + '</td>';
                                }
                                xml += '</tr><tr valign="top">';
                                for (var i = 0; i < record_ids.length; i++) {
                                    xml += '<td nowrap="nowrap"><iframe src="' + urls.XUL_BIB_BRIEF; 
                                    xml += '?docid=' + record_ids[i] + '" oils_force_external="true"/></td>';
                                }
                                xml += '</tr><tr valign="top">';
                                for (var i = 0; i < record_ids.length; i++) {
                                    xml += '<td nowrap="nowrap"><iframe style="min-height: 1000px; min-width: 300px;" flex="1" src="' + urls.XUL_MARC_VIEW + '?docid=' + record_ids[i] + ' " oils_force_external="true"/></td>';
                                }
                                xml += '</tr></table></form>';
                                //obj.data.temp_merge_top = top_xml; obj.data.stash('temp_merge_top');
                                //obj.data.temp_merge_mid = xml; obj.data.stash('temp_merge_mid');
                                JSAN.use('util.window'); var win = new util.window();
                                var fancy_prompt_data = win.open(
                                    urls.XUL_FANCY_PROMPT,
                                    //+ '?xml_in_stash=temp_merge_mid'
                                    //+ '&top_xml_in_stash=temp_merge_top'
                                    //+ '&title=' + window.escape('Record Purging'),
                                    'fancy_prompt', 'chrome,resizable,modal,width=700,height=500',
                                    {
                                        'top_xml' : top_xml, 'xml' : xml, 'title' : $("catStrings").getString('staff.cat.record_buckets.delete_records.fancy_prompt_title')
                                    }
                                );
                                //obj.data.stash_retrieve();
                                if (typeof fancy_prompt_data.fancy_status == 'undefined' || fancy_prompt_data.fancy_status != 'complete') {
                                    alert($("catStrings").getString('staff.cat.record_buckets.delete_records.fancy_prompt.alert'));
                                    return;
                                }
                                var s = '';
                                for (var i = 0; i < record_ids.length; i++) {
                                    var robj = obj.network.simple_request('FM_BRE_DELETE',[ses(),record_ids[i]]);
                                    if (typeof robj.ilsevent != 'undefined') {
                                        if (!s) s = $("catStrings").getString('staff.cat.record_buckets.delete_records.s1');
                                        s += $("catStrings").getFormattedString('staff.cat.record_buckets.delete_records.s2', [record_ids[i], robj.textcode, robj.desc]);
                                    }
                                }
                                if (s) { alert(s); }

                                obj.render_pending_records(); // FIXME -- need a generic refresh for lists
                                setTimeout(
                                    function() {
                                        JSAN.use('util.widgets'); 
                                        util.widgets.dispatch('change_bucket',obj.controller.view.bucket_menulist);
                                    }, 0
                                );
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.record_buckets.delete_records.catch.std_unex_err',E));
                            }

                        }
                    ],

                    'cmd_broken' : [
                        ['command'],
                        function() { alert($("catStrings").getString('staff.cat.record_buckets.cmd_broken.alert')); }
                    ],
                    'cmd_sel_opac' : [
                        ['command'],
                        function() {
                            try {
                                obj.list2.select_all();
                                JSAN.use('util.functional');
                                var docids = util.functional.map_list(
                                    obj.list2.dump_retrieve_ids(),
                                    function (o) {
                                        return JSON2js(o).docid; // docid
                                    }
                                );
                                var seen = {};
                                for (var i = 0; i < docids.length; i++) {
                                    var doc_id = docids[i];
                                    if (seen[doc_id]) continue; seen[doc_id] = true;
                                    var opac_url = xulG.url_prefix('opac_rdetail') + doc_id;
                                    var content_params = { 
                                        'session' : ses(),
                                        'authtime' : ses('authtime'),
                                        'opac_url' : opac_url
                                    };
                                    xulG.new_tab(
                                        xulG.url_prefix('XUL_OPAC_WRAPPER'), 
                                        {'tab_name':$("catStrings").getString('staff.cat.record_buckets.cmd_sel_opac.tab_name')}, 
                                        content_params
                                    );
                                }
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert($("catStrings").getString('staff.cat.record_buckets.cmd_sel_opac.catch.std_unex_err'),E);
                            }
                        }
                    ],
                    'cmd_marc_batch_edit' : [
                        ['command'],
                        function() {
                            try {
                                var bucket_id = obj.controller.view.bucket_menulist.value;
                                if (!bucket_id) return;
                                obj.list2.select_all();
                                xulG.new_tab(
                                    urls.MARC_BATCH_EDIT + '?containerid='+bucket_id+'&recordSource=b', 
                                    {
                                        'tab_name' : $('offlineStrings').getString('menu.cmd_marc_batch_edit.tab')
                                    },
                                    {}
                                );
                            } catch(E) {
                                alert('Error in record_buckets.js, cmd_marc_batch_edit: ' + E);
                            }
                        }
                    ],
                    'cmd_transfer_title_holds' : [
                        ['command'],
                        function() {
                            try {
                                obj.list2.select_all();
                                JSAN.use('util.functional');
                                var docids = util.functional.map_list(
                                    obj.list2.dump_retrieve_ids(),
                                    function (o) {
                                        return JSON2js(o).docid; // docid
                                    }
                                );
                                JSAN.use('cat.util');
                                cat.util.transfer_title_holds(docids);
                            } catch(E) {
                                alert('Error in record_buckets.js, cmd_transfer_title_holds: ' + E);
                            }
                        }
                    ],

                    'record_buckets_export_records' : [ ['render'], function(){} ],
                    'record_buckets_list_actions' : [ ['render'], function(){} ]
                }
            }
        );
        this.controller.render();

        if (typeof xulG == 'undefined') {
            obj.controller.view.cmd_sel_opac.disabled = true;
            obj.controller.view.cmd_sel_opac.setAttribute('disabled',true);
        }
    },

    'submit' : function() {
        try {
            var obj = this;
            var x = document.getElementById('record_query_input'); 
            if (x.value == '') {
                setTimeout( function() { obj.controller.view.record_query_input.focus(); obj.controller.view.record_query_input.select(); }, 0 );
                return;
            }
            obj.list0.clear();
            var y = document.getElementById('query_status');
            x.disabled = true;
            if (y) y.value = $("catStrings").getString('staff.cat.record_buckets.submit.query_status');
            obj.network.simple_request(
                'FM_BRE_ID_SEARCH_VIA_MULTICLASS_QUERY',
                [ { 'limit' : 100 }, x.value, 1 ],
                function(req) {
                    try {
                        var resp = req.getResultObject();
                        if (y) y.value = catStrings.getFormattedString('cat.results_returned',[resp.count]);
                        x.disabled = false;
                        if (resp.count > 0) {
                            JSAN.use('util.exec'); var exec = new util.exec();
                            var funcs = [];
                            for (var i = 0; i < resp.ids.length; i++) {
                                funcs.push(
                                    function(b){
                                        return function() {
                                            obj.list0.append(obj.prep_record_for_list(b));
                                        };
                                    }(resp.ids[i][0])
                                );
                            }
                            funcs.push(
                                function() {
                                    obj.controller.view.record_query_input.focus();
                                    obj.controller.view.record_query_input.select();
                                }
                            );
                            exec.chain( funcs ); 
                        } else {
                            setTimeout( function() { obj.controller.view.record_query_input.focus(); obj.controller.view.record_query_input.select(); }, 0 );
                        }
                    } catch(E) {
                        obj.error.standard_unexpected_error_alert('submit_query_callback',E);
                    }
                }
            );
        } catch(E) {
            this.error.standard_unexpected_error_alert('submit_query',E);
        }
    },

    'prep_record_for_list' : function(docid,bucket_item_id) {
        var obj = this;
        try {
            var item = {
                'retrieve_id' : js2JSON( { 'docid' : docid, 'bucket_item_id' : bucket_item_id } ),
                'row' : {
                    'my' : {
                        'docid' : docid,
                        'bucket_item_id' : bucket_item_id
                    }
                }
            };
            return item;
        } catch(E) {
            obj.error.standard_unexpected_error_alert($("catStrings").getFormattedString('staff.cat.record_buckets.prep_record_for_list.std_unex_err', [docid]),E);
            return null;
        }
    }
    
};

dump('exiting cat.record_buckets.js\n');
