dump('entering admin.transit_list.js\n');

if (typeof admin == 'undefined') admin = {};
admin.transit_list = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('util.date');
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

admin.transit_list.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.list_init();
		obj.controller_init();
		obj.kick_off();

	},

	'kick_off' : function() {
		var obj = this;
		try {
			obj.network.simple_request('FM_ATC_RETRIEVE_VIA_AOU',[ ses(), obj.data.list.au[ 0 ].ws_ou() ], 
				function(req) {
					try {
						var robj = req.getResultObject();
						if (typeof robj.ilsevent != 'undefined') throw(robj);

						JSAN.use('util.exec'); 
						var exec = new util.exec(2);
						var exec2 = new util.exec(2);

						function gen_list_append(id,which_list) {
							return function() {
								switch(which_list) {
									case 0: obj.list.append( { 'row' : { 'my' : { 'transit_id' : id } } } ); break;
									case 1: obj.list2.append( { 'row' : { 'my' : { 'transit_id' : id } } } ); break;
								}
							};
						}

						var rows = []; var rows2 = [];

						for (var i = 0; i < robj.from.length; i++) {
							//get_transit(robj.from[i], 0);
							rows.push( gen_list_append(robj.from[i],0) );
						}

						for (var i = 0; i < robj.to.length; i++) {
							//get_transit(robj.to[i], 1);
							rows2.push( gen_list_append(robj.to[i],1) );
						}
				
						exec.chain( rows );
						exec2.chain( rows2 );

					} catch(E) {
						try { obj.error.standard_unexpected_error_alert('retrieving transits',E); } catch(F) { alert(E); }
					}
				}
			);
		} catch(E) {
			try { obj.error.standard_unexpected_error_alert('pre-retrieving transits',E); } catch(F) { alert(E); }
		}
	},

	'list_init' : function() {

		var obj = this;

		obj.selection_list = [];
		obj.selection_list2 = [];

		JSAN.use('circ.util'); 
		var columns = circ.util.transit_columns(
			{
				'transit_source' : { 'hidden' : false },
				'transit_source_send_time' : { 'hidden' : false },
				'transit_dest_lib' : { 'hidden' : false },
				'transit_item_barcode' : { 'hidden' : false },
				'transit_item_title' : { 'hidden' : false },
			},
			{
				'just_these' : [
					'transit_id',
					'transit_source',
					'transit_source_send_time',
					'transit_dest_lib',
					'transit_item_barcode',
					'transit_item_title',
					'transit_item_author',
					'transit_item_callnumber',
					'transit_target_copy',
				]
			}
		).concat( 
			circ.util.hold_columns(
				{
					'request_time' : { 'hidden' : false },
				},
				{
					'just_these' : [
						'request_timestamp',
						'request_time',
						'capture_timestamp',
						'capture_time',
						'hold_type',
						'expire_time',
						'patron_name',
					],
				}
			) 
		);

		JSAN.use('util.list'); 
		obj.list = new util.list('transit_from');
		obj.list.init( 
			{ 
				'columns' : columns, 
				'map_row_to_column' : circ.util.std_map_row_to_column(), 
				'retrieve_row' : function(params) {
					var row = params.row;
					try {
						obj.get_transit_and_hold_and_run_func(
							row.my.transit_id,
							function(transit,hold) { return obj.get_rest_of_row_given_transit_and_hold(params,transit,hold); }
						);
					} catch(E) {
						try { obj.error.standard_unexpected_error_alert('retrieving row',E); } catch(F) { alert(E); }
					}
				},
				'on_select' : function(ev) {
					try {
						JSAN.use('util.functional');
						var sel = obj.list.retrieve_selection();
						obj.selection_list = util.functional.map_list(
							sel,
							function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
						);
						obj.error.sdump('D_TRACE','admin.transit_list: selection list = ' + js2JSON(obj.selection_list) );
						if (obj.selection_list.length == 0) {
							obj.controller.view.sel_edit.setAttribute('disabled','true');
							obj.controller.view.sel_opac.setAttribute('disabled','true');
							obj.controller.view.sel_bucket.setAttribute('disabled','true');
							obj.controller.view.sel_copy_details.setAttribute('disabled','true');
							obj.controller.view.sel_patron.setAttribute('disabled','true');
							obj.controller.view.sel_transit_abort.setAttribute('disabled','true');
							obj.controller.view.sel_clip.setAttribute('disabled','true');
						} else {
							obj.controller.view.sel_edit.setAttribute('disabled','false');
							obj.controller.view.sel_opac.setAttribute('disabled','false');
							obj.controller.view.sel_patron.setAttribute('disabled','false');
							obj.controller.view.sel_bucket.setAttribute('disabled','false');
							obj.controller.view.sel_copy_details.setAttribute('disabled','false');
							obj.controller.view.sel_transit_abort.setAttribute('disabled','false');
							obj.controller.view.sel_clip.setAttribute('disabled','false');
						}
					} catch(E) {
						alert('FIXME: ' + E);
					}
				},
			}
		);
		obj.list2 = new util.list('transit_to');
		obj.list2.init( 
			{ 
				'columns' : columns, 
				'map_row_to_column' : circ.util.std_map_row_to_column(), 
				'retrieve_row' : function(params) {
					var row = params.row;
					try {
						obj.get_transit_and_hold_and_run_func(
							row.my.transit_id,
							function(transit,hold) { return obj.get_rest_of_row_given_transit_and_hold(params,transit,hold); }
						);
					} catch(E) {
						try { obj.error.standard_unexpected_error_alert('retrieving row',E); } catch(F) { alert(E); }
					}
				},
				'on_select' : function(ev) {
					try {
						JSAN.use('util.functional');
						var sel = obj.list2.retrieve_selection();
						obj.selection_list2 = util.functional.map_list(
							sel,
							function(o) { return JSON2js(o.getAttribute('retrieve_id')); }
						);
						obj.error.sdump('D_TRACE','admin.transit_list: selection list2 = ' + js2JSON(obj.selection_list2) );
						if (obj.selection_list2.length == 0) {
							obj.controller.view.sel_edit2.setAttribute('disabled','true');
							obj.controller.view.sel_opac2.setAttribute('disabled','true');
							obj.controller.view.sel_bucket2.setAttribute('disabled','true');
							obj.controller.view.sel_copy_details2.setAttribute('disabled','true');
							obj.controller.view.sel_patron2.setAttribute('disabled','true');
							obj.controller.view.sel_transit_abort2.setAttribute('disabled','true');
							obj.controller.view.sel_clip2.setAttribute('disabled','true');
						} else {
							obj.controller.view.sel_edit2.setAttribute('disabled','false');
							obj.controller.view.sel_opac2.setAttribute('disabled','false');
							obj.controller.view.sel_patron2.setAttribute('disabled','false');
							obj.controller.view.sel_bucket2.setAttribute('disabled','false');
							obj.controller.view.sel_copy_details2.setAttribute('disabled','false');
							obj.controller.view.sel_transit_abort2.setAttribute('disabled','false');
							obj.controller.view.sel_clip2.setAttribute('disabled','false');
						}
					} catch(E) {
						alert('FIXME: ' + E);
					}
				},
			}
		);

	},

	'get_transit_and_hold_and_run_func' : function (transit_id,do_this) {
		var obj = this;
		obj.network.simple_request('FM_ATC_RETRIEVE', [ ses(), transit_id ],
			function(req2) {
				try {
					var r_atc = req2.getResultObject();
					if (typeof r_atc.ilsevent != 'undefined') throw(r_atc);

					if (instanceOf(r_atc,atc)) {
						do_this(r_atc,null);
					} else if (instanceOf(r_atc,ahtc)) {
						obj.network.simple_request('FM_AHR_RETRIEVE', [ ses(), r_atc.hold() ],
							function(req3) {
								try {
									var r_ahr = req3.getResultObject();
									if (typeof r_ahr.ilsevent != 'undefined') throw(r_ahr);
									if (instanceOf(r_ahr[0],ahr)) {
										do_this(r_atc,r_ahr[0]);
									} else {
										throw(r_ahr);
									}
								} catch(E) {
									try { obj.error.standard_unexpected_error_alert('retrieving hold id = ' + r_atc.hold() + ' for transit id = ' + transit_id,E); } catch(F) { alert(E); }
								}
							}
						);
					} else {
						throw(r_atc);
					}

				} catch(E) {
					try { obj.error.standard_unexpected_error_alert('retrieving transit id = ' + transit_id,E); } catch(F) { alert(E); }
				}
			}
		);
	},

	'get_rest_of_row_given_transit_and_hold' : function(params,transit,hold) {
		var obj = this;
		var row = params.row;

		row.my.atc = transit;
		if (hold) row.my.ahr = hold;

		obj.network.simple_request(
			'FM_ACP_RETRIEVE',
			[ row.my.atc.target_copy() ],
			function(req) {
				try { 
					var r_acp = req.getResultObject();
					if (typeof r_acp.ilsevent != 'undefined') throw(r_acp);
					row.my.acp = r_acp;

					obj.network.simple_request(
						'FM_ACN_RETRIEVE',
						[ r_acp.call_number() ],
						function(req2) {
							try {
								var r_acn = req2.getResultObject();
								if (typeof r_acn.ilsevent != 'undefined') throw(r_acn);
								row.my.acn = r_acn;

								if (row.my.acn.record() > 0) {
									obj.network.simple_request(
										'MODS_SLIM_RECORD_RETRIEVE',
										[ r_acn.record() ],
										function(req3) {
											try {
												var r_mvr = req3.getResultObject();
												if (typeof r_mvr.ilsevent != 'undefined') throw(r_mvr);
												row.my.mvr = r_mvr;

												params.row_node.setAttribute(
													'retrieve_id', js2JSON( { 
														'copy_id' : row.my.acp ? row.my.acp.id() : null, 
														'doc_id' : row.my.mvr ? row.my.mvr.doc_id() : null,  
														'barcode' : row.my.acp ? row.my.acp.barcode() : null, 
														'acp_id' : row.my.acp ? row.my.acp.id() : null, 
														'acn_id' : row.my.acn ? row.my.acn.id() : null,  
														'atc_id' : row.my.atc ? row.my.atc.id() : null,  
														'ahr_id' : row.my.ahr ? row.my.ahr.id() : null,  
													} )
												);
												if (typeof params.on_retrieve == 'function') {
													params.on_retrieve(row);
												}
											} catch(E) {
												try { obj.error.standard_unexpected_error_alert('retrieving mvr',E); } catch(F) { alert(E); }
											}
										}
									);
								} else {
									params.row_node.setAttribute(
										'retrieve_id', js2JSON( { 
											'copy_id' : row.my.acp ? row.my.acp.id() : null, 
											'doc_id' : row.my.mvr ? row.my.mvr.doc_id() : null,  
											'barcode' : row.my.acp ? row.my.acp.barcode() : null, 
											'acp_id' : row.my.acp ? row.my.acp.id() : null, 
											'acn_id' : row.my.acn ? row.my.acn.id() : null,  
											'atc_id' : row.my.atc ? row.my.atc.id() : null,  
											'ahr_id' : row.my.ahr ? row.my.ahr.id() : null,  
										} )
									);
									if (typeof params.on_retrieve == 'function') {
										params.on_retrieve(row);
									}
								}
					
							} catch(E) {
								try { obj.error.standard_unexpected_error_alert('retrieving acn',E); } catch(F) { alert(E); }
							}
						}
					);


				} catch(E) {
					try { obj.error.standard_unexpected_error_alert('retrieving acp',E); } catch(F) { alert(E); }
				}
			}
		);
	},

	'controller_init' : function() {
		var obj = this;

		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'save_columns' : [ [ 'command' ], function() { obj.list.save_columns(); } ],
					'save_columns2' : [ [ 'command' ], function() { obj.list2.save_columns(); } ],
					'sel_clip' : [ ['command'], function() { obj.list.clipboard(); } ],
					'sel_clip2' : [ ['command'], function() { obj.list2.clipboard(); } ],
					'sel_edit' : [ ['command'], function() { try { obj.spawn_copy_editor(0); } catch(E) { alert(E); } } ],
					'sel_edit2' : [ ['command'], function() { try { obj.spawn_copy_editor(1); } catch(E) { alert(E); } } ],
					'sel_opac' : [ ['command'], function() { JSAN.use('cat.util'); cat.util.show_in_opac(obj.selection_list); } ],
					'sel_opac2' : [ ['command'], function() { JSAN.use('cat.util'); cat.util.show_in_opac(obj.selection_list2); } ],
					'sel_transit_abort' : [ ['command'], function() { JSAN.use('circ.util'); circ.util.abort_transits(obj.selection_list); } ],
					'sel_transit_abort2' : [ ['command'], function() { JSAN.use('circ.util'); circ.util.abort_transits(obj.selection_list2); } ],
					'sel_patron' : [ ['command'], function() { JSAN.use('circ.util'); circ.util.show_last_few_circs(obj.selection_list); } ],
					'sel_patron2' : [ ['command'], function() { JSAN.use('circ.util'); circ.util.show_last_few_circs(obj.selection_list2); } ],
					'sel_copy_details' : [ ['command'], function() { JSAN.use('circ.util'); for (var i = 0; i < obj.selection_list.length; i++) { circ.util.show_copy_details( obj.selection_list[i].copy_id ); } } ],
					'sel_copy_details2' : [ ['command'], function() { JSAN.use('circ.util'); for (var i = 0; i < obj.selection_list2.length; i++) { circ.util.show_copy_details( obj.selection_list2[i].copy_id ); } } ],
					'sel_bucket' : [ ['command'], function() { JSAN.use('cat.util'); cat.util.add_copies_to_bucket(obj.selection_list); } ],
					'sel_bucket2' : [ ['command'], function() { JSAN.use('cat.util'); cat.util.add_copies_to_bucket(obj.selection_list2); } ],
					'cmd_print_list' : [ ['command'], function() { obj.print_list(0); } ],
					'cmd_print_list2' : [ ['command'], function() { obj.print_list(1); } ],
				}
			}
		);
		this.controller.render();

	},

	'print_list' : function(which_list) {
		var obj = this;
		try {

			var list = which_list == 0 ? obj.list : obj.list2;

			if (list.on_all_fleshed != null) {
				var r = window.confirm('This list is busy retrieving/rendering rows for a pending action.  Would you like to abort the pending action and proceed?');
				if (!r) return;
			}
			list.on_all_fleshed =
				function() {
					try {
						dump( js2JSON( list.dump_with_keys() ) + '\n' );
						obj.data.stash_retrieve();
						var lib = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
						lib.children(null);
						var p = { 
							'lib' : lib,
							'staff' : obj.data.list.au[0],
							'header' : obj.data.print_list_templates.transit_list.header,
							'line_item' : obj.data.print_list_templates.transit_list.line_item,
							'footer' : obj.data.print_list_templates.transit_list.footer,
							'type' : obj.data.print_list_templates.transit_list.type,
							'list' : list.dump_with_keys(),
						};
						JSAN.use('util.print'); var print = new util.print();
						print.tree_list( p );
						setTimeout(function(){ list.on_all_fleshed = null; },0);
					} catch(E) {
						obj.error.standard_unexpected_error_alert('print',E); 
					}
				}
			list.full_retrieve();
		} catch(E) {
			obj.error.standard_unexpected_error_alert('print',E); 
		}
	},
	
	'spawn_copy_editor' : function(which_list) {

		/* FIXME -  a lot of redundant calls here */

		var obj = this;

		JSAN.use('util.widgets'); JSAN.use('util.functional');

		var list = which_list == 0 ? obj.selection_list : obj.selection_list2;

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

dump('exiting admin.transit_list.js\n');
