dump('entering circ.copy_status.js\n');

if (typeof circ == 'undefined') circ = {};
circ.copy_status = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('util.date');
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

circ.copy_status.prototype = {
	'selection_list' : [],

	'init' : function( params ) {

		var obj = this;

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'barcode' : { 'hidden' : false },
				'title' : { 'hidden' : false },
				'location' : { 'hidden' : false },
				'call_number' : { 'hidden' : false },
				'status' : { 'hidden' : false },
				'alert_message' : { 'hidden' : false },
				'due_date' : { 'hidden' : false },
			},
			{
				'except_these' : [
					'checkin_time', 'checkin_time_full', 'route_to', 'message', 'uses', 'xact_finish',
				],
			}
		);

		JSAN.use('util.list'); obj.list = new util.list('copy_status_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_columns' : circ.util.std_map_row_to_columns(),
				'on_select' : function(ev) {
					try {
						JSAN.use('util.functional');
						var sel = obj.list.retrieve_selection();
						obj.selection_list = util.functional.map_list(
							sel,
							function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
						);
						obj.error.sdump('D_TRACE','circ/copy_status: selection list = ' + js2JSON(obj.selection_list) );
						if (obj.selection_list.length == 0) {
							obj.controller.view.sel_checkin.setAttribute('disabled','true');
							obj.controller.view.cmd_replace_barcode.setAttribute('disabled','true');
							obj.controller.view.sel_edit.setAttribute('disabled','true');
							obj.controller.view.sel_opac.setAttribute('disabled','true');
							obj.controller.view.sel_bucket.setAttribute('disabled','true');
							obj.controller.view.sel_copy_details.setAttribute('disabled','true');
							obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','true');
							obj.controller.view.sel_mark_items_missing.setAttribute('disabled','true');
							obj.controller.view.sel_patron.setAttribute('disabled','true');
							obj.controller.view.sel_spine.setAttribute('disabled','true');
							obj.controller.view.sel_transit_abort.setAttribute('disabled','true');
							obj.controller.view.sel_clip.setAttribute('disabled','true');
							obj.controller.view.sel_renew.setAttribute('disabled','true');
						} else {
							obj.controller.view.sel_checkin.setAttribute('disabled','false');
							obj.controller.view.cmd_replace_barcode.setAttribute('disabled','false');
							obj.controller.view.sel_edit.setAttribute('disabled','false');
							obj.controller.view.sel_opac.setAttribute('disabled','false');
							obj.controller.view.sel_patron.setAttribute('disabled','false');
							obj.controller.view.sel_bucket.setAttribute('disabled','false');
							obj.controller.view.sel_copy_details.setAttribute('disabled','false');
							obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','false');
							obj.controller.view.sel_mark_items_missing.setAttribute('disabled','false');
							obj.controller.view.sel_spine.setAttribute('disabled','false');
							obj.controller.view.sel_transit_abort.setAttribute('disabled','false');
							obj.controller.view.sel_clip.setAttribute('disabled','false');
							obj.controller.view.sel_renew.setAttribute('disabled','false');
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
					'save_columns' : [ [ 'command' ], function() { obj.list.save_columns(); } ],
					'sel_clip' : [
						['command'],
						function() { obj.list.clipboard(); }
					],
					'sel_checkin' : [
						['command'],
						function() {
							try {
								var funcs = [];
								JSAN.use('circ.util');
								for (var i = 0; i < obj.selection_list.length; i++) {
									var barcode = obj.selection_list[i].barcode;
									var checkin = circ.util.checkin_via_barcode( ses(), { 'barcode' : barcode } );
									funcs.push( function(a) { return function() { obj.copy_status( a ); }; }(barcode) );
								}
								alert('Action complete.');
								for (var i = 0; i < funcs.length; i++) { funcs[i](); }
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Checkin did not likely happen.',E);
							}
						}
					],
					'cmd_replace_barcode' : [
						['command'],
						function() {
							try {
								var funcs = [];
								JSAN.use('cat.util');
								for (var i = 0; i < obj.selection_list.length; i++) {
									try { 
										var barcode = obj.selection_list[i].barcode;
										var new_bc = cat.util.replace_barcode( barcode );
										funcs.push( function(a) { return function() { obj.copy_status( a ); }; }(new_bc) );
									} catch(E) {
										obj.error.standard_unexpected_error_alert('Barcode ' + barcode + ' was not likely replaced.',E);
									}
								}
								alert('Action complete.');
								for (var i = 0; i < funcs.length; i++) { funcs[i](); }
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Barcode replacements did not likely happen.',E);
							}
						}
					],
					'sel_edit' : [
						['command'],
						function() {
							try {
								var funcs = [];
								obj.spawn_copy_editor();
								for (var i = 0; i < obj.selection_list.length; i++) {
										var barcode = obj.selection_list[i].barcode;
										funcs.push( function(a) { return function() { obj.copy_status( a ); }; }(barcode) );
								}
								for (var i = 0; i < funcs.length; i++) { funcs[i](); }
							} catch(E) {
								obj.error.standard_unexpected_error_alert('with copy editor',E);
							}
						}
					],
					'sel_spine' : [
						['command'],
						function() {
							JSAN.use('cat.util');
							cat.util.spawn_spine_editor(obj.selection_list);
						}
					],
					'sel_opac' : [
						['command'],
						function() {
							JSAN.use('cat.util');
							cat.util.show_in_opac(obj.selection_list);
						}
					],
					'sel_transit_abort' : [
						['command'],
						function() {
							var funcs = [];
							JSAN.use('circ.util');
							circ.util.abort_transits(obj.selection_list);
							for (var i = 0; i < obj.selection_list.length; i++) {
								var barcode = obj.selection_list[i].barcode;
								funcs.push( function(a) { return function() { obj.copy_status( a ); }; }(barcode) );
							}
							alert('Action complete.');
							for (var i = 0; i < funcs.length; i++) { funcs[i](); }
						}
					],
					'sel_patron' : [
						['command'],
						function() {
							JSAN.use('circ.util');
							circ.util.show_last_few_circs(obj.selection_list);
						}
					],
					'sel_copy_details' : [
						['command'],
						function() {
							JSAN.use('circ.util');
							for (var i = 0; i < obj.selection_list.length; i++) {
								circ.util.show_copy_details( obj.selection_list[i].copy_id );
							}
						}
					],
					'sel_renew' : [
						['command'],
						function() {
							var funcs = [];
							JSAN.use('circ.util');
							for (var i = 0; i < obj.selection_list.length; i++) {
								var test = obj.selection_list[i].renewable;
								var barcode = obj.selection_list[i].barcode;
								if (test == 't') {
									circ.util.renew_via_barcode( barcode );
									funcs.push( function(a) { return function() { obj.copy_status( a ); }; }(barcode) );
								} else {
									alert('Item with barcode ' + barcode + ' is not circulating.');
								}
							}
							alert('Action complete.');
							for (var i = 0; i < funcs.length; i++) { funcs[i](); }
						}
					],

					'sel_mark_items_damaged' : [
						['command'],
						function() {
							var funcs = [];
							JSAN.use('cat.util'); JSAN.use('util.functional');
							cat.util.mark_item_damaged( util.functional.map_list( obj.selection_list, function(o) { return o.copy_id; } ) );
							for (var i = 0; i < obj.selection_list.length; i++) {
								var barcode = obj.selection_list[i].barcode;
								funcs.push( function(a) { return function() { obj.copy_status( a ); }; }(barcode) );
							}
							for (var i = 0; i < funcs.length; i++) { funcs[i](); }
						}
					],
					'sel_mark_items_missing' : [
						['command'],
						function() {
							var funcs = [];
							JSAN.use('cat.util'); JSAN.use('util.functional');
							cat.util.mark_item_missing( util.functional.map_list( obj.selection_list, function(o) { return o.copy_id; } ) );
							for (var i = 0; i < obj.selection_list.length; i++) {
								var barcode = obj.selection_list[i].barcode;
								funcs.push( function(a) { return function() { obj.copy_status( a ); }; }(barcode) );
							}
							for (var i = 0; i < funcs.length; i++) { funcs[i](); }
						}
					],
					'sel_bucket' : [
						['command'],
						function() {
							JSAN.use('cat.util');
							cat.util.add_copies_to_bucket(obj.selection_list);
						}
					],
					'copy_status_barcode_entry_textbox' : [
						['keypress'],
						function(ev) {
							if (ev.keyCode && ev.keyCode == 13) {
								obj.copy_status();
							}
						}
					],
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_copy_status_submit_barcode' : [
						['command'],
						function() {
							obj.copy_status();
						}
					],
					'cmd_copy_status_print' : [
						['command'],
						function() {
							try {
								obj.list.on_all_fleshed =
									function() {
										try {
											dump( js2JSON( obj.list.dump_with_keys() ) + '\n' );
											obj.data.stash_retrieve();
											var lib = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
											lib.children(null);
											var p = { 
												'lib' : lib,
												'staff' : obj.data.list.au[0],
												'header' : obj.data.print_list_templates.item_status.header,
												'line_item' : obj.data.print_list_templates.item_status.line_item,
												'footer' : obj.data.print_list_templates.item_status.footer,
												'type' : obj.data.print_list_templates.item_status.type,
												'list' : obj.list.dump_with_keys(),
											};
											JSAN.use('util.print'); var print = new util.print();
											print.tree_list( p );
											setTimeout(function(){ obj.list.on_all_fleshed = null; },0);
										} catch(E) {
											obj.error.standard_unexpected_error_alert('print',E); 
										}
									}
								obj.list.full_retrieve();
							} catch(E) {
								obj.error.standard_unexpected_error_alert('print',E); 
							}
						}
					],
					'cmd_copy_status_reprint' : [
						['command'],
						function() {
						}
					],
					'cmd_copy_status_done' : [
						['command'],
						function() {
						}
					],
				}
			}
		);
		this.controller.render();
		this.controller.view.copy_status_barcode_entry_textbox.focus();

	},

	'copy_status' : function(barcode) {
		var obj = this;
		try {
			try { document.getElementById('last_scanned').setAttribute('value',''); } catch(E) {}
			if (!barcode) barcode = obj.controller.view.copy_status_barcode_entry_textbox.value;
			if (!barcode) return;
			JSAN.use('circ.util');
			var copy = obj.network.simple_request( 'FM_ACP_RETRIEVE_VIA_BARCODE', [ barcode ]);
			if (copy == null) {
				throw('Something weird happened.  null result');
			} else if (copy.ilsevent) {
				switch(copy.ilsevent) {
					case -1: 
						obj.error.standard_network_error_alert(); 
						obj.controller.view.copy_status_barcode_entry_textbox.select();
						obj.controller.view.copy_status_barcode_entry_textbox.focus();
					break;
					case 1502 /* ASSET_COPY_NOT_FOUND */ :
						try { document.getElementById('last_scanned').setAttribute('value',barcode + ' was either mis-scanned or is not cataloged.'); } catch(E) {}
						obj.error.yns_alert(barcode + ' was either mis-scanned or is not cataloged.','Not Cataloged','OK',null,null,'Check here to confirm this message');
						obj.controller.view.copy_status_barcode_entry_textbox.select();
						obj.controller.view.copy_status_barcode_entry_textbox.focus();
					break;
					default: 
						throw(copy); 
					break;
				}
			} else {
				obj.network.simple_request('FM_ACP_DETAILS', [ ses(), copy.id() ], function(req) {
					try {
						var details = req.getResultObject();
						var msg = copy.barcode() + ' -- ';
						if (copy.call_number() == -1) msg += 'Item is a Pre-Cat.  ';
						if (details.hold) msg += 'Item is captured for a Hold.  ';
						if (details.transit) msg += 'Item is in Transit.  ';
						if (details.circ && ! details.circ.checkin_time()) msg += 'Item is circulating.  ';
						try { document.getElementById('last_scanned').setAttribute('value',msg); } catch(E) {}
					} catch(E) {
						alert(E);
					}
				} );
				var my_mvr = obj.network.simple_request('MODS_SLIM_RECORD_RETRIEVE_VIA_COPY', [ copy.id() ]);
				if (document.getElementById('trim_list')) {
					var x = document.getElementById('trim_list');
					if (x.checked) { obj.list.trim_list = 20; } else { obj.list.trim_list = null; }
				}
				obj.list.append(
					{
						'retrieve_id' : js2JSON( { 'renewable' : copy.circulations() ? 't' : 'f', 'copy_id' : copy.id(), 'barcode' : barcode, 'doc_id' : (typeof my_mvr.ilsevent == 'undefined' ? my_mvr.doc_id() : null ) } ),
						'row' : {
							'my' : {
								'mvr' : my_mvr,
								'acp' : copy,
							}
						},
						'to_top' : true,
					}
				);
				obj.controller.view.copy_status_barcode_entry_textbox.value = '';
				obj.controller.view.copy_status_barcode_entry_textbox.focus();
			}
		} catch(E) {
			obj.error.standard_unexpected_error_alert('',E);
			obj.controller.view.copy_status_barcode_entry_textbox.select();
			obj.controller.view.copy_status_barcode_entry_textbox.focus();
		}

	},
	
	'spawn_copy_editor' : function() {

		/* FIXME -  a lot of redundant calls here */

		var obj = this;

		JSAN.use('util.widgets'); JSAN.use('util.functional');

		var list = obj.selection_list;

		list = util.functional.map_list(
			list,
			function (o) {
				return o.copy_id;
			}
		);

		var copies = util.functional.map_list(
			list,
			function (acp_id) {
				return obj.network.simple_request('FM_ACP_RETRIEVE',[acp_id]);
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
					util.functional.map_list(
						copies,
						function (o) {
							return o.call_number() == -1 ? o.circ_lib() : obj.network.simple_request('FM_ACN_RETRIEVE',[o.call_number()]).owning_lib();
						}
					),
					copies.length == 1 ? [ 'UPDATE_COPY' ] : [ 'UPDATE_COPY', 'UPDATE_BATCH_COPY' ]
				]
			).length == 0 ? 1 : 0;
		} catch(E) {
			obj.error.sdump('D_ERROR','batch permission check: ' + E);
		}

		JSAN.use('cat.util'); cat.util.spawn_copy_editor(list,edit);

	},

}

dump('exiting circ.copy_status.js\n');
