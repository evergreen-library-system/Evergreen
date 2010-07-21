dump('entering manage_items.js\n');

function $(id) { return document.getElementById(id); }

if (typeof serial == 'undefined') serial = {};
serial.manage_items = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

serial.manage_items.prototype = {

	'list_sitem_map' : {},

    'set_sdist_ids' : function () {
		var obj = this;

        try {
            var holding_lib = $('serial_item_lib_menu').value;
            robj = obj.network.request(
                'open-ils.pcrud',
                'open-ils.pcrud.id_list.sdist',
                [ ses(), {"holding_lib" : holding_lib, "+ssub":{"record_entry" : obj.docid}}, {"join":"ssub"} ]
            );
            if (robj != null) {
                if (typeof robj.ilsevent != 'undefined') throw(robj);
                obj.sdist_ids = robj.length ? robj : [robj];
            } else {
                obj.sdist_ids = [];
            }
        } catch(E) {
            obj.error.standard_unexpected_error_alert('set_sdist_ids failed!',E);
        }
    },

    'build_lib_menu' : function () {
		var obj = this;

        // draw library drop-down
        obj.org_ids = obj.network.simple_request('FM_SSUB_AOU_IDS_RETRIEVE_VIA_RECORD_ID.authoritative',[ obj.docid ]);
        if (typeof obj.org_ids.ilsevent != 'undefined') throw(obj.org_ids);
        JSAN.use('util.functional');
        obj.org_ids = util.functional.map_list( obj.org_ids, function (o) { return Number(o); });

        var org = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];

        JSAN.use('util.file'); JSAN.use('util.widgets');

        var file; var list_data; var ml;

        file = new util.file('offline_ou_list');
        if (file._file.exists()) {
            list_data = file.get_object(); file.close();
            ml = util.widgets.make_menulist( list_data[0], list_data[1] );
            ml.setAttribute('id','serial_item_lib_menu'); document.getElementById('serial_item_lib_menu_box').appendChild(ml);
            //TODO: class this menu properly
            for (var i = 0; i < obj.org_ids.length; i++) {
                ml.getElementsByAttribute('value',obj.org_ids[i])[0].setAttribute('class','has_distributions');
            }
            /*TODO: add/enable this legend?
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
            );*/
            ml.addEventListener(
                'command',
                function(ev) {
                    if (document.getElementById('serial_item_refresh_button')) document.getElementById('serial_item_refresh_button').focus();
                    JSAN.use('util.file'); var file = new util.file('manage_items_prefs.'+obj.data.server_unadorned);
                    util.widgets.save_attributes(file, { 'serial_item_lib_menu' : [ 'value' ], 'serial_manage_items_mode' : [ 'selectedIndex' ], 'serial_manage_items_show_all' : [ 'checked' ] }); //FIXME: do load_attributes somewhere and check if selectedIndex does what we want here
                    // get latest sdist id list based on library drowdown
                    obj.set_sdist_ids();
                    obj.refresh_list('main');
                    obj.refresh_list('workarea');
                },
                false
            );
        } else {
            throw(document.getElementById('catStrings').getString('staff.cat.copy_browser.missing_library') + '\n');
        }
        file = new util.file('manage_items_prefs.'+obj.data.server_unadorned);
        util.widgets.load_attributes(file);
        ml.value = ml.getAttribute('value');
        if (! ml.value) {
            ml.value = org.id();
            ml.setAttribute('value',ml.value);
        }
    },

	'init' : function( params ) {
		var obj = this;

		obj.docid = params['docid'];

        obj.build_lib_menu();
        obj.set_sdist_ids();
		obj.init_lists();

		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'save_columns' : [ [ 'command' ], function() { obj.lists.main.save_columns(); } ],
					'cmd_broken' : [ ['command'], function() { alert('Not Yet Implemented'); } ],
					'sel_clip' : [ ['command'], function() { obj.lists.main.clipboard(); } ],
                    'cmd_add_item' : [
                        ['command'],
                        function() {
                            try {
                                var new_item = new sitem();
                                new_item.issuance(new siss());
                                new_item.stream(1); //FIXME: hard-coded stream
                                new_item.issuance().subscription(1); //FIXME: hard-coded subscription
                                new_item.isnew(1);
                                new_item.issuance().isnew(1);
                                spawn_item_editor( {'items' : [new_item], 'edit' : 1 } );

                                obj.refresh_list('main');

                            } catch(E) {
                                obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.edit_items.error'),E);
                            }
                        }
                    ],
                    'cmd_edit_items' : [
                        ['command'],
                        function() {
                            try {
                                if (!obj.retrieve_ids || obj.retrieve_ids.length == 0) return;

                                JSAN.use('util.functional');
                                var list = util.functional.map_list(
                                        obj.retrieve_ids,
                                        function (o) {
                                            return o.sitem_id;
                                        }
                                    );

                                spawn_item_editor( { 'item_ids' : list, 'edit' : 1 } );

                                obj.refresh_list(obj.selected_list);

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
                                var list = util.functional.map_list(
                                        obj.retrieve_ids,
                                        function (o) {
                                            return obj.list_sitem_map[o.sitem_id];
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
                                    for (var i = 0; i < list.length; i++) {
                                        list[i].isdeleted('1');
                                    }
                                    var robj = obj.network.request(
                                            'open-ils.serial',
                                            'open-ils.serial.item.fleshed.batch.update',
                                        [ ses(), list, true ],
                                        null,
                                        {
                                            'title' : document.getElementById('catStrings').getString('staff.cat.copy_browser.delete_items.override'),
                                            'overridable_events' : [ // FIXME: replace or delete these events
                                                1208 /* TITLE_LAST_COPY */,
                                                1227 /* COPY_DELETE_WARNING */,
                                            ]
                                        }
                                    );
                                    if (robj == null) throw(robj);
                                    if (typeof robj.ilsevent != 'undefined') {
                                        if ( (robj.ilsevent != 0) && (robj.ilsevent != 1227 /* COPY_DELETE_WARNING */) && (robj.ilsevent != 1208 /* TITLE_LAST_COPY */) ) throw(robj);
                                    }
                                    obj.refresh_list(obj.selected_list);
                                }


                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('staff.serial.manage_items.delete_items.error',E);
                                obj.refresh_list();
                            }
                        }
                    ],
                    'cmd_predict_items' : [
                        ['command'],
                        function() {
                            alert('Subscription selection needed here'); //FIXME: make this prompt, or discard this feature
                        }
                    ],
                    'cmd_receive_items' : [
                        ['command'],
                        function() {
                            try {
                                JSAN.use('util.functional');
                                var list = util.functional.map_list(
                                        obj.retrieve_ids,
                                        function (o) {
                                            var item = obj.list_sitem_map[o.sitem_id];
                                            item.unit('-1'); //FIXME: hard-coded unit (-1 is AUTO)
                                            return item;
                                        }
                                    );

                                var robj = obj.network.request(
                                            'open-ils.serial',
                                            'open-ils.serial.receive_items',
                                            [ ses(), list ]
                                        );
                                if (typeof robj.ilsevent != 'undefined') throw(robj); //TODO: catch for override

                                alert('Successfully received '+robj+' item(s)');
                                obj.refresh_list('main');
                                obj.refresh_list('workarea');
                                
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('cmd_receive_items failed!',E);
                            }
                        }
                    ],
                    'cmd_edit_sunit' : [
                        ['command'],
                        function() {
                            try {
                                /*if (!obj.retrieve_ids || obj.retrieve_ids.length == 0) return;

                                JSAN.use('util.functional');
                                var list = util.functional.map_list(
                                        obj.retrieve_ids,
                                        function (o) {
                                            return o.sitem_id;
                                        }
                                    );
*/
                                spawn_sunit_editor( { 'sunit_ids' : [1], 'edit' : 1 } ); //FIXME: hard-coded sunit

                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('cmd_edit_sunit failed!',E);
                            }
                        }
                    ],

                    'cmd_items_print' : [ ['command'], function() { obj.items_print(obj.selected_list); } ],
					'cmd_items_export' : [ ['command'], function() { obj.items_export(obj.selected_list); } ],
					'cmd_refresh_list' : [ ['command'], function() { obj.refresh_list('main'); obj.refresh_list('workarea'); } ]
				}
			}
		);
        
		obj.retrieve('main'); // retrieve main list
        obj.retrieve('workarea'); // retrieve shelving unit list

		obj.controller.view.sel_clip.setAttribute('disabled','true');

	},

	'items_print' : function(which) {
		var obj = this;
		try {
			var list = obj.lists[which];
/* FIXME: serial items print template?			JSAN.use('patron.util');
			var params = { 
				'patron' : patron.util.retrieve_fleshed_au_via_id(ses(),obj.patron_id), 
				'template' : 'items_out'
			}; */
			list.print( params );
		} catch(E) {
			obj.error.standard_unexpected_error_alert('manage_items printing',E);
		}
	},

	'items_export' : function(which) {
		var obj = this;
		try {
			var list = obj.lists[which];
			list.dump_csv_to_clipboard();
		} catch(E) {
			obj.error.standard_unexpected_error_alert('manage_items export',E);
		}
	},

	'init_lists' : function() {
		var obj = this;

		JSAN.use('circ.util');
        var columns = item_columns({});

        function retrieve_row(params) {
			try { 
				var row = params.row;
                obj.network.simple_request( //FIXME: pcrud fleshing won't work!!
                    'FM_SITEM_RETRIEVE',
                    //[ ses(), row.my.sitem_id, {"flesh":1, "flesh_fields":{"sitem": ["creator","editor","distribution","shelving_unit"]}}],
                    [ ses(), row.my.sitem_id, {"flesh":2,"flesh_fields":{"sitem":["creator","editor","issuance","stream","unit","notes"], "sunit":["call_number"], "sstr":["distribution"]}}], // TODO: we really need note count only, not the actual notes, is there a smart way to do that?
                    function(req) {
                        try {
                            var robj = req.getResultObject();
                            if (typeof robj.ilsevent != 'undefined') throw(robj);
                            if (typeof robj.ilsevent == 'null') throw('null result');
                            obj.list_sitem_map[robj.id()] = robj;
                            row.my.sitem = robj;
                            //params.row_node.setAttribute( 'retrieve_id', js2JSON({'copy_id':copy_id,'circ_id':row.my.circ.id(),'barcode':row.my.acp.barcode(),'doc_id': ( row.my.record ? row.my.record.id() : null ) }) );
                            params.row_node.setAttribute( 'retrieve_id', js2JSON({'sitem_id':robj.id()}) );
                            dump('dumping... ' + js2JSON(obj.list_sitem_map[robj.id()]));
                            if (typeof params.on_retrieve == 'function') {
                                params.on_retrieve(row);
                            }

                        } catch(E) {
                            obj.error.standard_unexpected_error_alert('staff.serial.manage_items.retrieve_row.callback_error', E);
                        }
                    }
                );
				return row;
			} catch(E) {
				obj.error.standard_unexpected_error_alert('staff.serial.manage_items.retrieve_row.error_in_retrieve_row',E);
				return params.row;
			}
		}

		JSAN.use('util.list');

        obj.lists = {};
        obj.lists.main = new util.list('item_tree');
		obj.lists.main.init(
			{
				'columns' : columns,
				'map_row_to_columns' : circ.util.std_map_row_to_columns(),
				'retrieve_row' : retrieve_row,
				'on_select' : function(ev) {
                    obj.selected_list = 'main';
					JSAN.use('util.functional');
					var sel = obj.lists.main.retrieve_selection();
					obj.controller.view.sel_clip.setAttribute('disabled',sel.length < 1);
					var list = util.functional.map_list(
						sel,
						function(o) { return JSON2js( o.getAttribute('retrieve_id') ); }
					);
					if (typeof obj.on_select == 'function') {
						obj.on_select(list);
					}
					if (typeof window.xulG == 'object' && typeof window.xulG.on_select == 'function') {
						obj.error.sdump('D_CAT','manage_items: Calling external .on_select()\n');
						window.xulG.on_select(list);
					}
				}
			}
		);
        obj.lists.main.sitem_retrieve_params = {'date_received' : null };
        obj.lists.main.sitem_extra_params ={'order_by' : {'sitem' : 'date_expected ASC, stream ASC'}};

        obj.lists.workarea = new util.list('workarea_tree');
		obj.lists.workarea.init(
			{
				'columns' : columns,
				'map_row_to_columns' : circ.util.std_map_row_to_columns(),
				'retrieve_row' : retrieve_row,
				'on_select' : function(ev) {
                    obj.selected_list = 'workarea';
					JSAN.use('util.functional');
					var sel = obj.lists.workarea.retrieve_selection();
					obj.controller.view.sel_clip.setAttribute('disabled',sel.length < 1);
					var list = util.functional.map_list(
						sel,
						function(o) { return JSON2js( o.getAttribute('retrieve_id') ); }
					);
					if (typeof obj.on_select == 'function') {
						obj.on_select(list);
					}
					if (typeof window.xulG == 'object' && typeof window.xulG.on_select == 'function') {
						obj.error.sdump('D_CAT','serctrl: Calling external .on_select()\n');
						window.xulG.on_select(list);
					} else {
						obj.error.sdump('D_CAT','serctrl: No external .on_select()\n');
					}
				}
			}
		);
        obj.lists.workarea.sitem_retrieve_params = {'date_received' : {"!=" : null}};
        obj.lists.workarea.sitem_extra_params ={'order_by' : {'sitem' : 'date_received DESC'}, 'limit' : 30};
    },

	'refresh_list' : function(list_name) {
        var obj = this;

        // TODO: make this change on the checkbox command event?
        if (list_name == 'main') {
            if (document.getElementById('serial_manage_items_show_all').checked) {
                delete obj.lists.main.sitem_retrieve_params.date_received;
            } else {
                obj.lists.main.sitem_retrieve_params.date_received = null;
            }
        }
        //TODO Optimize this?
        obj.retrieve(list_name);
    },

	'retrieve' : function(list_name) {
		var obj = this;
        var list = obj.lists[list_name];
        
        if (!obj.sdist_ids.length) { // no sdists to retrieve items for
            return;
        }

        var rparams = list.sitem_retrieve_params;
        var robj;
        rparams['+sstr'] = { "distribution" : obj.sdist_ids };
        var other_params = list.sitem_extra_params;
        other_params.join = 'sstr';

        robj = obj.network.simple_request(
            'FM_SITEM_ID_LIST',
            [ ses(), rparams, other_params ]
        );
        if (typeof robj.ilsevent!='undefined') {
            obj.error.standard_unexpected_error_alert('Failed to retrieve serial item ID list',E);
        }
        if (!robj) {
            robj = [];
        } else if (!robj.length) {
            robj = [robj];
        }

		list.clear();
        for (i = 0; i < robj.length; i++) {
            list.append( { 'row' : { 'my' : { 'sitem_id' : robj[i] } }, 'to_bottom' : true, 'no_auto_select' : true } );
        }
	},

	'on_select' : function(list) {

		dump('manage_items.on_select list = ' + js2JSON(list) + '\n');

		var obj = this;

		/*obj.controller.view.cmd_items_claimed_returned.setAttribute('disabled','false');
		obj.controller.view.sel_mark_items_missing.setAttribute('disabled','false');*/

		obj.retrieve_ids = list;
	}
}

function item_columns(modify,params) {

    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.init({'via':'stash'});
    //JSAN.use('util.network'); var network = new util.network();

    var c = [
        {
            'id' : 'sitem_id',
            'label' : 'Item ID',
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'render' : function(my) { return my.sitem.id(); },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'label',
            'label' : 'Issuance Label',
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'render' : function(my) { return my.sitem.issuance().label(); },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'distribution',
            'label' : 'Distribution',
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'persist' : 'hidden width ordinal',
            'render' : function(my) { return my.sitem.stream().distribution().label(); }
        },
        {
            'id' : 'stream_id',
            'label' : 'Stream ID',
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'persist' : 'hidden width ordinal',
            'render' : function(my) { return my.sitem.stream().id(); }
        },
        {
            'id' : 'date_published',
            'label' : 'Date Published',
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'render' : function(my) { return my.sitem.issuance().date_published().substr(0,10); },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'date_expected',
            'label' : 'Date Expected',
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'render' : function(my) { return my.sitem.date_expected().substr(0,10); },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'date_received',
            'label' : 'Date Received',
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'render' : function(my) { return my.sitem.date_received().substr(0,10); },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'notes',
            'label' : 'Notes',
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'render' : function(my) { return my.sitem.notes().length; },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'call_number',
            'label' : 'Call Number',
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'persist' : 'hidden width ordinal',
            'render' : function(my) { return my.sitem.unit().call_number().label(); }
        },
        {
            'id' : 'unit_id_contents',
            'label' : 'Unit ID / Contents',
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'render' : function(my) { return '[' + my.sitem.unit().id() + '] ' + my.sitem.unit().summary_contents() ; },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'creator',
            'label' : 'Creator',
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'persist' : 'hidden width ordinal',
            'render' : function(my) { return my.sitem.creator().usrname(); }
        },
        {
            'id' : 'create_date',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.create_date'),
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'persist' : 'hidden width ordinal',
            'render' : function(my) { return my.sitem.create_date().substr(0,10); }
        },
        {
            'id' : 'editor',
            'label' : 'Editor',
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'persist' : 'hidden width ordinal',
            'render' : function(my) { return my.sitem.editor().usrname(); }
        },
        {
            'id' : 'edit_date',
            'label' : document.getElementById('circStrings').getString('staff.circ.utils.edit_date'),
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'persist' : 'hidden width ordinal',
            'render' : function(my) { return my.sitem.edit_date().substr(0,10); }
        },
        {
            'id' : 'holding_code',
            'label' : 'Holding Code',
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'render' : function(my) { return my.sitem.issuance().holding_code(); },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'holding_type',
            'label' : 'Holding Type',
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'render' : function(my) { return my.sitem.issuance().holding_type(); },
            'persist' : 'hidden width ordinal'
        },
        {
            'id' : 'holding_link_id',
            'label' : 'Holding Link ID',
            'flex' : 1,
            'primary' : false,
            'hidden' : true,
            'render' : function(my) { return my.sitem.issuance().holding_link_id(); },
            'persist' : 'hidden width ordinal'
        }
    ];
    for (var i = 0; i < c.length; i++) {
        if (modify[ c[i].id ]) {
            for (var j in modify[ c[i].id ]) {
                c[i][j] = modify[ c[i].id ][j];
            }
        }
    }
    if (params) {
        if (params.just_these) {
            JSAN.use('util.functional');
            var new_c = [];
            for (var i = 0; i < params.just_these.length; i++) {
                var x = util.functional.find_list(c,function(d){return(d.id==params.just_these[i]);});
                new_c.push( function(y){ return y; }( x ) );
            }
            c = new_c;
        }
        if (params.except_these) {
            JSAN.use('util.functional');
            var new_c = [];
            for (var i = 0; i < c.length; i++) {
                var x = util.functional.find_list(params.except_these,function(d){return(d==c[i].id);});
                if (!x) new_c.push(c[i]);
            }
            c = new_c;
        }
    }
    //return c.sort( function(a,b) { if (a.label < b.label) return -1; if (a.label > b.label) return 1; return 0; } );
    return c;
};

spawn_item_editor = function(params) {
    try {
        if (!params.item_ids && !params.items) return;
        if (params.item_ids && params.item_ids.length == 0) return;
        if (params.items && params.items.length == 0) return;
        if (params.item_ids) params.item_ids = js2JSON(params.item_ids); // legacy
        if (!params.caller_handles_update) params.handle_update = 1; // legacy

        var obj = {};
        JSAN.use('util.network'); obj.network = new util.network();
        JSAN.use('util.error'); obj.error = new util.error();

        var title = '';
        if (params.item_ids && params.item_ids.length > 1 && params.edit == 1)
            title = 'Batch Edit Items';
        else /* if(params.copies && params.copies.length > 1 && params.edit == 1)
            title = 'Batch View Items';
        else if(params.item_ids && params.item_ids.length == 1) */
            title = 'Edit Item';/*
        else
            title = 'View Item';*/

        JSAN.use('util.window'); var win = new util.window();
        var my_xulG = win.open(
            (urls.XUL_SERIAL_ITEM_EDITOR),
            title,
            'chrome,modal,resizable',
            params
        );
        if (my_xulG.items && params.edit) {
            return my_xulG.items;
        } else {
            return [];
        }
    } catch(E) {
        JSAN.use('util.error'); var error = new util.error();
        error.standard_unexpected_error_alert('error in spawn_item_editor',E);
    }
}

dump('exiting manage_items.js\n');
