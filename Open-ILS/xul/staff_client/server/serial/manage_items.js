dump('entering manage_items.js\n');

function $(id) { return document.getElementById(id); }

if (typeof serial == 'undefined') serial = {};
serial.manage_items = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});

    this.current_sunit_id = -1; //default to **AUTO**
    this.mode = 'receive';

}

serial.manage_items.prototype = {

	'list_sitem_map' : {},
    'sdist_map' : {},
    'ssub_map' : {},
    'row_map' : {},

    'retrieve_ssubs_and_sdists' : function () {
		var obj = this;

        try {
            obj.lib = $('serial_item_lib_menu').value;
            var sdist_retrieve_params = {"+ssub":{"record_entry" : obj.docid}};
            if (obj.mode == 'receive') {
                sdist_retrieve_params["+ssub"].owning_lib = obj.lib;
            } else {
                sdist_retrieve_params.holding_lib = obj.lib;
            }
            var robj = obj.network.request(
                'open-ils.pcrud',
                'open-ils.pcrud.id_list.sdist',
                [ ses(), sdist_retrieve_params, {"join":"ssub"} ]
            );
            if (robj != null) {
                if (typeof robj.ilsevent != 'undefined') throw(robj);
                obj.sdist_ids = robj.length ? robj : [robj];
                // now get actual sdist and ssub objects
                robj = obj.network.simple_request(
                    'FM_SDIST_FLESHED_BATCH_RETRIEVE.authoritative',
                    [ obj.sdist_ids ]
                );
                if (robj != null) {
                    if (typeof robj.ilsevent != 'undefined') throw(robj);
                    robj = robj.length ? robj : [robj];
                    for (var i = 0; i < robj.length; i++) {
                        obj.sdist_map[robj[i].id()] = robj[i];
                    }
                }
                robj = obj.network.request(
                    'open-ils.pcrud',
                    'open-ils.pcrud.id_list.ssub',
                    [ ses(), {"+sdist" : {"id" : obj.sdist_ids}}, {"join":"sdist"} ]
                );
                var ssub_ids = robj.length ? robj : [robj];
                robj = obj.network.simple_request(
                    'FM_SSUB_FLESHED_BATCH_RETRIEVE.authoritative',
                    [ ssub_ids ]
                );
                if (robj != null) {
                    if (typeof robj.ilsevent != 'undefined') throw(robj);
                    robj = robj.length ? robj : [robj];
                    for (var i = 0; i < robj.length; i++) {
                        obj.ssub_map[robj[i].id()] = robj[i];
                    }
                }
            } else {
                obj.sdist_ids = [];
            }

        } catch(E) {
            obj.error.standard_unexpected_error_alert('retrieve_ssubs_and_sdists failed!',E);
        }
    },

    'build_menus' : function () {
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
            for (var i = 0; i < list_data[0].length; i++) { // make sure all entries are enabled
                    list_data[0][i][2] = false;
            }
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
                    //if (document.getElementById('serial_item_refresh_button')) document.getElementById('serial_item_refresh_button').focus();
                    obj.save_settings();
                    // get latest sdist id list based on library drowdown
                    obj.retrieve_ssubs_and_sdists();
                    obj.refresh_list('main');
                    obj.refresh_list('workarea');
                },
                false
            );

        } else {
            throw(document.getElementById('catStrings').getString('staff.cat.copy_browser.missing_library') + '\n');
        }
        file = new util.file('serial_items_prefs.'+obj.data.server_unadorned);
        util.widgets.load_attributes(file);
        ml.value = ml.getAttribute('value');
        if (! ml.value) {
            ml.value = org.id();
            ml.setAttribute('value',ml.value);
        }
        
        // deal with mode radio selectedIndex, as load_attributes is setting a "read-only" value
        if ($('mode_receive').getAttribute('selected')) {
            $('serial_manage_items_mode').selectedIndex = 0;
        } else if ($('mode_advanced_receive').getAttribute('selected')) {
            $('serial_manage_items_mode').selectedIndex = 1;
        } else {
            $('serial_manage_items_mode').selectedIndex = 2;
        }

        // setup recent sunits list
        var recent_sunits_file = new util.file('serial_items_recent_sunits_'+obj.docid+'.'+obj.data.server_unadorned);
        util.widgets.load_attributes(recent_sunits_file);
        var recent_sunits_popup = $('serial_items_recent_sunits');
        obj.sunit_entries = JSON2js(recent_sunits_popup.getAttribute('sunit_json'));
        for (i = 0; i < obj.sunit_entries.length; i++) {
            var sunit_info = obj.sunit_entries[i];
            var new_menu_item = recent_sunits_popup.appendItem(sunit_info.label);
            new_menu_item.setAttribute('id', 'serial_items_recent_sunits_entry_'+sunit_info.id);
            new_menu_item.setAttribute('sunit_id', sunit_info.id);
            new_menu_item.setAttribute('command', 'cmd_set_sunit');
        }
    },

	'init' : function( params ) {
		var obj = this;

		obj.docid = params['docid'];

        obj.build_menus();
        obj.set_sunit($('serial_items_current_sunit').getAttribute('sunit_id'), $('serial_items_current_sunit').getAttribute('sunit_label'), $('serial_items_current_sunit').getAttribute('sdist_id'), $('serial_items_current_sunit').getAttribute('sstr_id'));
        //obj.retrieve_ssubs_and_sdists();
		obj.init_lists();

        var mode_radio_group = $('serial_manage_items_mode');
        obj.set_mode(mode_radio_group.selectedItem.id.substr(5));
        mode_radio_group.addEventListener(
            'command',
            function(ev) {
                obj.save_settings();
                var mode = ev.target.id.substr(5); //strip out 'mode_'
                obj.set_mode(mode);
                obj.refresh_list('main');
                obj.refresh_list('workarea');
            },
            false
        );
        $('serial_manage_items_show_all').addEventListener(
            'command',
            function(ev) {
                obj.save_settings();
                obj.set_mode();
                obj.refresh_list('main');
                obj.refresh_list('workarea');
            },
            false
        );

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
                                spawn_sitem_editor( {'sitems' : [new_item], 'do_edit' : 1 } );

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

                                spawn_sitem_editor( { 'sitem_ids' : list, 'do_edit' : 1 } );

                                obj.refresh_rows(list);

                            } catch(E) {
                                obj.error.standard_unexpected_error_alert(document.getElementById('catStrings').getString('staff.cat.copy_browser.edit_items.error'),E);
                            }
                        }
                    ],
                    'cmd_reset_items' : [
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

                                var robj = obj.network.request(
                                            'open-ils.serial',
                                            'open-ils.serial.reset_items',
                                            [ ses(), list ]
                                        );
                                if (typeof robj.ilsevent != 'undefined') throw(robj);

                                alert('Successfully reset '+robj.num_items+' item(s)');

                                obj.refresh_list('main');
                                obj.refresh_list('workarea');
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('staff.serial.manage_items.reset_items.error',E);
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
                                        [ ses(), list ],
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
                    'cmd_set_sunit' : [
                        ['command'],
                        function(evt) {
                            try {
                                var target = evt.explicitOriginalTarget;
                                obj.process_unit_selection(target);
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('cmd_set_sunit failed!',E);
                            }
                        }
                    ],
                    'cmd_set_other_sunit' : [
                        ['command'],
                        function() {
                            obj.set_other_sunit();
                            if (obj.mode == 'bind') {
                                obj.refresh_list('main');
                                obj.refresh_list('workarea');
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
                                var donor_unit_ids = {};
                                var list = util.functional.map_list(
                                        obj.retrieve_ids,
                                        function (o) {
                                            var item = obj.list_sitem_map[o.sitem_id];
                                            if (item.unit()) {
                                                donor_unit_ids[item.unit().id()] = 1;
                                            }
                                            item.unit(obj.current_sunit_id);
                                            return item;
                                        }
                                    );

                                var mode = obj.mode;
                                if (mode == 'advanced_receive') mode = 'receive';

                                var method; var success_label;
                                if (mode == 'receive') {
                                    method = 'open-ils.serial.receive_items';
                                    success_label = 'received';
                                } else { // bind mode
                                    method = 'open-ils.serial.bind_items';
                                    success_label = 'bound';
                                } 

                                // deal with barcodes and call numbers for *NEW* units
                                var barcodes = {};
                                var call_numbers = {};
                                var call_numbers_by_siss_and_sdist = {};

                                if (obj.current_sunit_id < 0) { // **AUTO** or **NEW** units
                                    var new_unit_barcode = '';
                                    var new_unit_call_number = '';
                                    for (var i = 0; i < list.length; i++) {
                                        var item = list[i];
                                        if (new_unit_barcode) {
                                            barcodes[item.id()] = new_unit_barcode;
                                            call_numbers[item.id()] = new_unit_call_number;
                                            continue;
                                        }
                                        var prompt_text;
                                        if (obj.current_sunit_id == -1) {
                                            prompt_text = 'for '+item.issuance().label()+ ' from Distribution: '+obj.sdist_map[item.stream().distribution()].label()+'/'+item.stream().id()+':';
                                        } else { // must be -2
                                            prompt_text = 'for the new unit:';
                                        }

                                        // first barcodes
                                        var barcode = window.prompt('Please enter a barcode ' + prompt_text,
                                            '@@AUTO',
                                            'Unit Barcode Prompt');
                                        barcode = String( barcode ).replace(/\s/g,'');
                                        /* Casting a possibly null input value to a String turns it into "null" */
                                        if (!barcode || barcode == 'null') {
                                            alert('Invalid barcode entered, defaulting to system-generated.');
                                            barcode = '@@AUTO';
                                        } else {
                                            // disable alarm sound temporarily
                                            var sound_setting = obj.data.no_sound;
                                            if (!sound_setting) { // undefined or false
                                                obj.data.no_sound = true; obj.data.stash('no_sound');
                                            }
                                            var test = obj.network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[ barcode ]);
                                            if (typeof test.ilsevent == 'undefined') {
                                                alert('Another copy has barcode "' + barcode + '", defaulting to system-generated.');
                                                barcode = '@@AUTO';
                                            }
                                            if (!sound_setting) {
                                                obj.data.no_sound = sound_setting; obj.data.stash('no_sound');
                                            }
                                        }
                                        barcodes[item.id()] = barcode;

                                        // now call numbers
                                        if (typeof call_numbers_by_siss_and_sdist[item.issuance().id() + '@' + item.stream().distribution()] == 'undefined') {
                                            var default_cn = 'DEFAULT';
                                            // if they defined a *_call_number, honor it as the default
                                            var preset_cn = obj.sdist_map[item.stream().distribution()][mode + '_call_number']();
                                            if (preset_cn) {
                                                default_cn = preset_cn.label();
                                            } else {
                                                // for now, let's default to the last created call number if there is one
                                                var acn_list = obj.network.request(
                                                        'open-ils.pcrud',
                                                        'open-ils.pcrud.search.acn',
                                                        [ ses(), {"record" : obj.docid, "owning_lib" : obj.sdist_map[item.stream().distribution()].holding_lib().id(), "deleted" : 'f' }, {"order_by" : {"acn" : "create_date DESC"}, "limit" : "1" } ]
                                                );

                                                if (acn_list) {
                                                    default_cn = acn_list.label();
                                                }
                                            }
                                            var call_number = window.prompt('Please enter/adjust a call number ' + prompt_text,
                                                default_cn, //TODO: real default by setting
                                                'Unit Call Number Prompt');
                                            call_number = String( call_number ).replace(/^\s+/,'').replace(/\s$/,'');
                                            /* Casting a possibly null input value to a String turns it into "null" */
                                            if (!call_number || call_number == 'null') {
                                                alert('Invalid call number entered, setting to "DEFAULT".');
                                                call_number = 'DEFAULT'; //TODO: real default by setting
                                            }
                                            call_numbers[item.id()] = call_number;
                                            call_numbers_by_siss_and_sdist[item.issuance().id() + '@' + item.stream().distribution()] = call_number;
                                        } else {
                                            // we have already seen this same issuance and distribution combo, so use the same call number
                                            call_numbers[item.id()] = call_numbers_by_siss_and_sdist[item.issuance().id() + '@' + item.stream().distribution()];
                                        }

                                        if (obj.current_sunit_id == -2) {
                                            new_unit_barcode = barcode;
                                            new_unit_call_number = call_number;
                                        }
                                    }
                                }

                                var robj = obj.network.request(
                                            'open-ils.serial',
                                            method,
                                            [ ses(), list, barcodes, call_numbers, donor_unit_ids ]
                                        );
                                if (typeof robj.ilsevent != 'undefined') throw(robj); //TODO: catch for override

                                alert('Successfully '+success_label+' '+robj.num_items+' item(s)');

                                if (obj.current_sunit_id == -2) {
                                    obj.current_sunit_id = robj.new_unit_id;
                                }

                                obj.rebuild_current_sunit(obj.sdist_map[list[0].stream().distribution()].label(), list[0].stream().distribution(), list[0].stream().id());
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
                    'cmd_view_sitem_notes' : [
                        ['command'],
                        function() {
                            try {
                                obj.view_notes('sitem');
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('cmd_view_sitem_notes failed!',E);
                            }
                        }
                    ],
                    'cmd_view_sdist_notes' : [
                        ['command'],
                        function() {
                            try {
                                obj.view_notes('sdist');
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('cmd_view_sdist_notes failed!',E);
                            }
                        }
                    ],
                    'cmd_view_ssub_notes' : [
                        ['command'],
                        function() {
                            try {
                                obj.view_notes('ssub');
                            } catch(E) {
                                obj.error.standard_unexpected_error_alert('cmd_view_ssub_notes failed!',E);
                            }
                        }
                    ],
                    'cmd_items_print' : [ ['command'], function() { obj.items_print(obj.selected_list); } ],
					'cmd_items_export' : [ ['command'], function() { obj.items_export(obj.selected_list); } ],
					'cmd_refresh_list' : [ ['command'], function() { obj.retrieve_ssubs_and_sdists(); obj.refresh_list('main'); obj.refresh_list('workarea'); } ]
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

	'rebuild_current_sunit' : function(sdist_label, sdist_id, sstr_id) {
		var obj = this;
        if (!obj.current_sunit_id) return; // current sunit is NONE
		try {
            var robj = obj.network.request(
                'open-ils.pcrud',
                'open-ils.pcrud.retrieve.sunit',
                [ ses(),  obj.current_sunit_id]
            );
            if (!robj) return; // current sunit is NEW or AUTO

            var label = '[' + sdist_label + '/' + sstr_id + ' #' + obj.current_sunit_id + '] ' + robj.summary_contents();
            obj.set_sunit(obj.current_sunit_id, label, sdist_id, sstr_id);
            obj.save_sunit(obj.current_sunit_id, label, sdist_id, sstr_id);
		} catch(E) {
			obj.error.standard_unexpected_error_alert('serial items set_sunit',E);
		}
	},

	'set_sunit' : function(sunit_id, label, sdist_id, sstr_id) {
		var obj = this;
		try {
            obj.current_sunit_id = sunit_id;
            obj.current_sunit_sdist_id = sdist_id;
            obj.current_sunit_sstr_id = sstr_id;
            if (sunit_id < 0  || sunit_id === '') {
                $('serial_workarea_sunit_desc').firstChild.nodeValue = '**' + label + '**';
            } else {
                $('serial_workarea_sunit_desc').firstChild.nodeValue = label;
                obj.add_sunit_to_menu(sunit_id, label, sdist_id, sstr_id);
            }
		} catch(E) {
			obj.error.standard_unexpected_error_alert('serial items set_sunit',E);
		}
	},

	'save_sunit' : function(sunit_id, label, sdist_id, sstr_id) {
		var obj = this;
		try {
            $('serial_items_current_sunit').setAttribute('sunit_id', sunit_id);
            $('serial_items_current_sunit').setAttribute('sunit_label', label);
            if (sunit_id > 0) {
                $('serial_items_current_sunit').setAttribute('sdist_id', sdist_id);
                $('serial_items_current_sunit').setAttribute('sstr_id', sstr_id);
            }
            var recent_sunits_file = new util.file('serial_items_recent_sunits_'+obj.docid+'.'+obj.data.server_unadorned);
            util.widgets.save_attributes(recent_sunits_file, { 'serial_items_recent_sunits' : [ 'sunit_json' ], 'serial_items_current_sunit' : [ 'sunit_id', 'sunit_label', 'sdist_id', 'sstr_id' ] });
		} catch(E) {
			obj.error.standard_unexpected_error_alert('serial items save_sunit',E);
		}
	},

	'set_other_sunit' : function() {
		var obj = this;
		try {
            JSAN.use('util.window'); var win = new util.window();
            var select_unit_window = win.open(
                xulG.url_prefix('XUL_SERIAL_SELECT_UNIT'),
                '_blank',
                'chrome,resizable,modal,centerscreen',
                {'sdist_ids' : obj.sdist_ids}
            );
            if (!select_unit_window.sunit_selection) {
                return;
            }

            var selection = select_unit_window.sunit_selection;
            var sunit_id = selection.sunit;
            var sdist_id = selection.sdist;
            var sstr_id = selection.sstr;
            var label = selection.label;

            obj.set_sunit(sunit_id, label, sdist_id, sstr_id);
            obj.save_sunit(sunit_id, label, sdist_id, sstr_id);
		} catch(E) {
			obj.error.standard_unexpected_error_alert('serial items set_other_sunit',E);
		}
	},

	'add_sunit_to_menu' : function(sunit_id, label, sdist_id, sstr_id) {
		var obj = this;
		try {
            if (sunit_id > 0) {
                // check if it is already in sunit_entries, remove it
                for (i = 0; i < obj.sunit_entries.length; i++) {
                    if (obj.sunit_entries[i].id == sunit_id) {
                        obj.sunit_entries.splice(i,1);
                        var menu_item = $('serial_items_recent_sunits_entry_'+sunit_id);
                        menu_item.parentNode.removeChild(menu_item);
                        i--;
                    }
                }
                // add to front of array
                obj.sunit_entries.unshift({"id" : sunit_id, "label" : label, "sdist_id" : sdist_id, "sstr_id" : sstr_id});
                var recent_sunits_popup = $('serial_items_recent_sunits');
                var new_menu_item = recent_sunits_popup.insertItemAt(0,label);
                new_menu_item.setAttribute('id', 'serial_items_recent_sunits_entry_'+sunit_id);
                new_menu_item.setAttribute('sunit_id', sunit_id);
                new_menu_item.setAttribute('sdist_id', sdist_id);
                new_menu_item.setAttribute('sstr_id', sstr_id);
                new_menu_item.setAttribute('command', 'cmd_set_sunit');

                // pop off from sunit_entries if it already has 10 sunits
                if (obj.sunit_entries.length > 10) {
                    var sunit_info = obj.sunit_entries.pop();
                    var menu_item = $('serial_items_recent_sunits_entry_'+sunit_info.id);
                    menu_item.parentNode.removeChild(menu_item);
                }

                recent_sunits_popup.setAttribute('sunit_json', js2JSON(obj.sunit_entries));
            }
		} catch(E) {
			obj.error.standard_unexpected_error_alert('serial items add_sunit_to_menu',E);
		}
	},

	'set_mode' : function(mode) {
		var obj = this;

        if (!mode) {
            mode = obj.mode;
        } else {
            obj.mode = mode;
        }

        obj.retrieve_ssubs_and_sdists();

        if (mode == 'receive' || mode == 'advanced_receive') {
            $('serial_workarea_mode_label').value = 'Recently Received';
            if ($('serial_manage_items_show_all').checked) {
                obj.lists.main.sitem_retrieve_params = {};
            } else {
                obj.lists.main.sitem_retrieve_params = {'date_received' : null };
            }
            obj.lists.main.sitem_extra_params ={'order_by' : {'sitem' : 'date_expected ASC, stream ASC'}};

            obj.lists.workarea.sitem_retrieve_params = {'date_received' : {"!=" : null}};
            obj.lists.workarea.sitem_extra_params ={'order_by' : {'sitem' : 'date_received DESC'}, 'limit' : 30};
            if (mode == 'receive') {
                $('serial_manage_items_context').value = $('serialStrings').getString('staff.serial.manage_items.subscriber.label') + ':';
                $('cmd_set_other_sunit').setAttribute('disabled','true');
                $('serial_items_recent_sunits').disabled = true;
                obj.process_unit_selection($('serial_items_auto_per_item_menuitem'));
                //obj.set_sunit(obj.current_sunit_id, label, sdist_id, sstr_id);
            } else {
                $('serial_manage_items_context').value = $('serialStrings').getString('staff.serial.manage_items.holder.label') + ':';
                $('cmd_set_other_sunit').setAttribute('disabled','false');
                $('serial_items_recent_sunits').disabled = false;
            }    
        } else { // bind mode
            $('serial_workarea_mode_label').value = 'Bound Items in Current Working Unit';
            $('serial_manage_items_context').value = $('serialStrings').getString('staff.serial.manage_items.holder.label') + ':';
            if ($('serial_manage_items_show_all').checked) {
                obj.lists.main.sitem_retrieve_params = {};
            } else {
                obj.lists.main.sitem_retrieve_params = {'date_received' : {'!=' : null}}; // unit set dynamically in 'retrieve'
            }
            obj.lists.main.sitem_extra_params ={'order_by' : {'sitem' : 'date_expected ASC, stream ASC'}};

            obj.lists.workarea.sitem_retrieve_params = {}; // unit set dynamically in 'retrieve'
            obj.lists.workarea.sitem_extra_params ={'order_by' : {'sitem' : 'date_received DESC'}};

            $('cmd_set_other_sunit').setAttribute('disabled','false');
            $('serial_items_recent_sunits').disabled = false;
            // default to **NEW UNIT**
            // For now, keep the unit static.  TODO: Eventually, keep track of and store the last used unit value for both receive and bind separately
            // obj.set_sunit(-2, 'New Unit', '', '');
        }
    },

	'save_settings' : function() {
		var obj = this;

        JSAN.use('util.file'); var file = new util.file('serial_items_prefs.'+obj.data.server_unadorned);
        util.widgets.save_attributes(file, { 'serial_item_lib_menu' : [ 'value' ], 'mode_receive' : [ 'selected' ], 'mode_advanced_receive' : [ 'selected' ], 'mode_bind' : [ 'selected' ], 'serial_manage_items_show_all' : [ 'checked' ] });
    },

	'init_lists' : function() {
		var obj = this;

		JSAN.use('circ.util');
        var columns = item_columns({});

        function retrieve_row(params) {
			try { 
				var row = params.row;
                obj.network.simple_request(
                    'FM_SITEM_FLESHED_BATCH_RETRIEVE.authoritative',
                    [[row.my.sitem_id]],
                    //[ ses(), row.my.sitem_id, {"flesh":2,"flesh_fields":{"sitem":["creator","editor","issuance","stream","unit","notes"], "sunit":["call_number"], "sstr":["distribution"]}}],
                    function(req) {
                        try {
                            var robj = req.getResultObject();
                            if (typeof robj.ilsevent != 'undefined') throw(robj);
                            if (typeof robj.ilsevent == 'null') throw('null result');
                            var sitem = robj[0];
                            obj.list_sitem_map[sitem.id()] = sitem;
                            row.my.sitem = sitem;
                            row.my.parent_obj = obj;
                            //params.treeitem_node.setAttribute( 'retrieve_id', js2JSON({'copy_id':copy_id,'circ_id':row.my.circ.id(),'barcode':row.my.acp.barcode(),'doc_id': ( row.my.record ? row.my.record.id() : null ) }) );
                            params.treeitem_node.setAttribute( 'retrieve_id', js2JSON({'sitem_id':sitem.id()}) );
                            dump('dumping... ' + js2JSON(obj.list_sitem_map[sitem.id()]));
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

        obj.lists.workarea = new util.list('workarea_tree');
		obj.lists.workarea.init(
			{
				'columns' : columns,
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
    },

	'refresh_list' : function(list_name) {
        var obj = this;

        //TODO Optimize this?
        obj.retrieve(list_name);
    },

    // accepts a list of ids or a list of objects
    'refresh_rows' : function(list) {
        var obj = this;

        var id_list;

        if (typeof list[0] == 'object') {
            id_list = util.functional.map_list(
                list,
                function(o) {
                    return o.id()
                }
            );
        } else {
            id_list = list;
        }

        for (var i = 0; i < id_list.length; i++) {
            obj.lists[obj.selected_list].refresh_row(obj.row_map[id_list[i]]);
        }
    },

	'retrieve' : function(list_name) {
		var obj = this;
        var list = obj.lists[list_name];
        
		list.clear();

        if (!obj.sdist_ids.length) { // no sdists to retrieve items for
            return;
        }

        var rparams = list.sitem_retrieve_params;
        var robj;
        rparams['+sstr'] = { "distribution" : obj.sdist_ids };

        if (obj.mode == 'bind') {
            if (list_name == 'workarea') {
                rparams['unit'] = obj.current_sunit_id;
            } else if (!$('serial_manage_items_show_all').checked){
                rparams['unit'] = {"<>" : obj.current_sunit_id};
            }
        }

        var other_params = list.sitem_extra_params;
        other_params.join = 'sstr';

        robj = obj.network.simple_request(
            'FM_SITEM_ID_LIST',
            [ ses(), rparams, other_params ]
        );
        if (!robj) {
            robj = [];
        } else if (typeof robj.ilsevent!='undefined') {
            obj.error.standard_unexpected_error_alert('Failed to retrieve serial item ID list',E);
        } else if (!robj.length) {
            robj = [robj];
        }

        for (i = 0; i < robj.length; i++) {
            var nparams = list.append( { 'row' : { 'my' : { 'sitem_id' : robj[i] } }, 'to_bottom' : true, 'no_auto_select' : true } );
            obj.row_map[robj[i]] = nparams;
        }
	},

	'on_select' : function(list) {

		dump('manage_items.on_select list = ' + js2JSON(list) + '\n');

		var obj = this;

		/*obj.controller.view.cmd_items_claimed_returned.setAttribute('disabled','false');
		obj.controller.view.sel_mark_items_missing.setAttribute('disabled','false');*/

		obj.retrieve_ids = list;
	},

    'process_unit_selection' : function(menuitem) {
        var obj = this;

        var label = menuitem.label;
        var sunit_id = menuitem.getAttribute('sunit_id');
        var sdist_id = menuitem.getAttribute('sdist_id');
        var sstr_id = menuitem.getAttribute('sstr_id');
        obj.set_sunit(sunit_id, label, sdist_id, sstr_id);
        obj.save_sunit(sunit_id, label, sdist_id, sstr_id);
        if (obj.mode == 'bind') {
            obj.refresh_list('main');
            obj.refresh_list('workarea');
        }
    },

    'view_notes' : function(type) {
        var obj = this;

        if (!obj.retrieve_ids || obj.retrieve_ids.length == 0) return;

        var object_id_fn;
        var function_type;
        var object_type;
        var constructor;

        switch(type) {
            case 'sitem':
                object_id_fn = function(item) { return item.id() };
                title_fn = function(item) { return fieldmapper.IDL.fmclasses.sitem.field_map.id.label + ' ' + item.id() };
                function_type = 'SIN';
                object_type = 'item';
                constructor = sin;
                break;
            case 'sdist':
                object_id_fn = function(item) { return item.stream().distribution() };
                title_fn = function(item) {
                    var sdist_id = object_id_fn(item);
                    return obj.sdist_map[sdist_id].label()
                        + ' -- ' + obj.sdist_map[sdist_id].holding_lib().shortname()
                        + ' (' + fieldmapper.IDL.fmclasses.sdist.field_map.id.label + ' ' + sdist_id + ')'
                };
                function_type = 'SDISTN';
                object_type = 'distribution';
                constructor = sdistn;
                break;
            case 'ssub':
                object_id_fn = function(item) { return item.issuance().subscription().id() };
                title_fn = function(item) {
                    var ssub_id = object_id_fn(item);
                    return obj.ssub_map[ssub_id].owning_lib().shortname()
                        + ' (' + fieldmapper.IDL.fmclasses.ssub.field_map.id.label + ' ' + ssub_id + ')'
                };
                function_type = 'SSUBN';
                object_type = 'subscription';
                constructor = ssubn;
                break;
            default:
                return;
        }

        var seen_ids = {};
        for (var i = 0; i < obj.retrieve_ids.length; i++) {
            var item = obj.list_sitem_map[obj.retrieve_ids[i].sitem_id];
            var obj_id = object_id_fn(item);
            if (seen_ids[obj_id]) continue;
            JSAN.use('util.window'); var win = new util.window();
            win.open(
                urls.XUL_SERIAL_NOTES,
                '','chrome,resizable,modal',
                { 'object_id' : obj_id, 'function_type' : function_type, 'object_type' : object_type, 'constructor' : constructor, 'title' : $('serialStrings').getString('staff.serial.'+type+'_editor.notes') + ' -- ' + title_fn(item) }
            );
            seen_ids[obj_id] = 1;
        }
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
            'render' : function(my) { return my.parent_obj.sdist_map[my.sitem.stream().distribution()].label(); }
        },
        {
            'id' : 'distribution_ou',
            'label' : $('serialStrings').getString('staff.serial.manage_items.holder.label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'persist' : 'hidden width ordinal',
            'render' : function(my) { return my.parent_obj.sdist_map[my.sitem.stream().distribution()].holding_lib().shortname(); }
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
            'label' : $('serialStrings').getString('staff.serial.manage_items.notes_column.label'),
            'flex' : 1,
            'primary' : false,
            'hidden' : false,
            'render' : function(my) { return my.sitem.notes().length + ' / ' + my.parent_obj.sdist_map[my.sitem.stream().distribution()].notes().length + ' / ' + my.parent_obj.ssub_map[my.sitem.issuance().subscription().id()].notes().length; },
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

spawn_sitem_editor = function(params) {
    try {
        if (!params.sitem_ids && !params.sitems) return;
        if (params.sitem_ids && params.sitem_ids.length == 0) return;
        if (params.sitems && params.sitems.length == 0) return;
        if (params.sitem_ids) params.sitem_ids = js2JSON(params.sitem_ids); // legacy
        if (!params.caller_handles_update) params.handle_update = 1; // legacy

        var obj = {};
        JSAN.use('util.network'); obj.network = new util.network();
        JSAN.use('util.error'); obj.error = new util.error();

        var title = '';
        if (params.sitem_ids && params.sitem_ids.length > 1 && params.do_edit == 1)
            title = 'Batch Edit Items';
        else /* if(params.sitems && params.sitems.length > 1 && params.do_edit == 1)
            title = 'Batch View Items';
        else if(params.sitem_ids && params.sitem_ids.length == 1) */
            title = 'Edit Item';/*
        else
            title = 'View Item';*/

        JSAN.use('util.window'); var win = new util.window();
        params.in_modal = true;
        var my_xulG = win.open(
            (urls.XUL_SERIAL_ITEM_EDITOR),
            title,
            'chrome,modal,resizable',
            params
        );
        if (my_xulG.sitems && params.do_edit) {
            return my_xulG.sitems;
        } else {
            return [];
        }
    } catch(E) {
        JSAN.use('util.error'); var error = new util.error();
        error.standard_unexpected_error_alert('error in spawn_sitem_editor',E);
    }
}

dump('exiting manage_items.js\n');
