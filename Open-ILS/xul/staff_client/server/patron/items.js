dump('entering patron.items.js\n');

if (typeof patron == 'undefined') patron = {};
patron.items = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	this.OpenILS = {}; JSAN.use('OpenILS.data'); this.OpenILS.data = new OpenILS.data(); this.OpenILS.data.init({'via':'stash'});
}

patron.items.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.patron_id = params['patron_id'];

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'title' : { 'hidden' : false, 'flex' : '3' },
				'due_date' : { 'hidden' : false },
				'renewal_remaining' : { 'hidden' : false },
				'stop_fines' : { 'hidden' : false },
			} 
		);

		JSAN.use('util.list'); obj.list = new util.list('items_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
				'retrieve_row' : function(params) {

					var row = params.row;

					var funcs = [];
					
					if (!row.my.mvr) funcs.push(
						function() {

							row.my.mvr = obj.network.request(
								api.MODS_SLIM_RECORD_RETRIEVE_VIA_COPY.app,
								api.MODS_SLIM_RECORD_RETRIEVE_VIA_COPY.method,
								[ row.my.circ.target_copy() ]
							);

						}
					);
					if (!row.my.acp) {
						funcs.push(	
							function() {

								row.my.acp = obj.network.request(
									api.FM_ACP_RETRIEVE.app,
									api.FM_ACP_RETRIEVE.method,
									[ row.my.circ.target_copy() ]
								);

								params.row_node.setAttribute( 'retrieve_id', js2JSON({'circ_id':row.my.circ.id(),'barcode':row.my.acp.barcode(),'doc_id': (typeof row.my.mvr.ilsevent == 'undefined' ? row.my.mvr.doc_id() : null )}) );

							}
						);
					} else {
						params.row_node.setAttribute( 'retrieve_id', js2JSON({'circ_id':row.my.circ.id(),'barcode':row.my.acp.barcode(),'doc_id': ( typeof row.my.mvr.ilsevent == 'undefined' ? row.my.mvr.doc_id() : null) }) );
					}

					funcs.push(
						function() {

							if (typeof params.on_retrieve == 'function') {
								params.on_retrieve(row);
							}

						}
					);

					JSAN.use('util.exec'); var exec = new util.exec();
					exec.on_error = function(E) {
						//var err = 'items chain: ' + js2JSON(E);
						//obj.error.sdump('D_ERROR',err);
						return true; /* keep going */
					}
					exec.chain( funcs );

					return row;
				},
				'on_select' : function(ev) {
					JSAN.use('util.functional');
					var sel = obj.list.retrieve_selection();
					var list = util.functional.map_list(
						sel,
						function(o) { return JSON2js( o.getAttribute('retrieve_id') ); }
					);
					if (typeof obj.on_select == 'function') {
						obj.on_select(list);
					}
					if (typeof window.xulG == 'object' && typeof window.xulG.on_select == 'function') {
						obj.error.sdump('D_PATRON','patron.items: Calling external .on_select()\n');
						window.xulG.on_select(list);
					} else {
						obj.error.sdump('D_PATRON','patron.items: No external .on_select()\n');
					}
				},
			}
		);
		
		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
					],
					'cmd_items_print' : [
						['command'],
						function() {
							dump(js2JSON(obj.list.dump()) + '\n');
							try {
								JSAN.use('patron.util');
								var params = { 
									'patron' : patron.util.retrieve_au_via_id(ses(),obj.patron_id), 
									'lib' : obj.OpenILS.data.hash.aou[ obj.OpenILS.data.list.au[0].ws_ou() ],
									'staff' : obj.OpenILS.data.list.au[0],
									'header' : obj.OpenILS.data.print_list_templates.checkout.header,
									'line_item' : obj.OpenILS.data.print_list_templates.checkout.line_item,
									'footer' : obj.OpenILS.data.print_list_templates.checkout.footer,
									'type' : obj.OpenILS.data.print_list_templates.checkout.type,
									'list' : obj.list.dump(),
								};
								JSAN.use('util.print'); var print = new util.print();
								print.tree_list( params );
							} catch(E) {
								this.error.sdump('D_ERROR','preview: ' + E);
								alert('preview: ' + E);
							}


						}
					],
					'cmd_items_renew' : [
						['command'],
						function() {
							try {
							for (var i = 0; i < obj.retrieve_ids.length; i++) {
								var barcode = obj.retrieve_ids[i].barcode;
								dump('Renew barcode = ' + barcode);
								var renew = obj.network.simple_request(
									'CHECKOUT_RENEW', 
									[ ses(), { barcode: barcode, patron: obj.patron_id } ],
									null,
									{
										'title' : 'Override Checkin Failure?',
										'overridable_events' : [ 
											1203 /* COPY_BAD_STATUS */, 
											7010 /* COPY_ALERT_MESSAGE */, 
											7011 /* COPY_STATUS_LOST */, 
											7012 /* COPY_STATUS_MISSING */, 
											7004 /* COPY_NOT_AVAILABLE */, 
											7006 /* COPY_IS_REFERENCE */, 
											7010 /* COPY_ALERT_MESSAGE */,
										],
										'text' : {
											'1203' : function(r) {
												return obj.OpenILS.data.hash.ccs[ r.payload.status() ].name();
											},
											'7010' : function(r) {
												return r.payload;
											},
											'7004' : function(r) {
												return obj.OpenILS.data.hash.ccs[ r.payload ].name();
											},
											'7010' : function(r) {
												return r.payload;
											},
										}
									}
								);
								if (typeof renew.ilsevent != 'undefined') throw(renew);
							}
							obj.retrieve();
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Renew probably did not happen.',E);
							}
						}
					],
					'cmd_items_edit' : [
						['command'],
						function() {
							try {
								function check_date(value) {
									JSAN.use('util.date');
									try {
										if (! util.date.check('YYYY-MM-DD',value) ) { 
											throw('Invalid Date'); 
										}
										if (util.date.check_past('YYYY-MM-DD',value) ) { 
											throw('Due date needs to be after today.'); 
										}
										if ( util.date.formatted_date(new Date(),'%F') == value) { 
											throw('Due date needs to be after today.'); 
										}
										return true;
									} catch(E) {
										alert(E);
										return false;
									}
								}

								JSAN.use('util.functional');
								var title = 'Edit Due Date' + (obj.retrieve_ids.length > 1 ? 's' : '');
								var value = 'YYYY-MM-DD';
								var text = 'Enter a new due date for these copies: ' + 
									util.functional.map_list(obj.retrieve_ids,function(o){return o.barcode;}).join(', ');
								var due_date; var invalid = true;
								while(invalid) {
									due_date = window.prompt(text,value,title);
									if (due_date) {
										invalid = ! check_date(due_date);
									} else {
										invalid = false;
									}
								}
								if (due_date) {
									var circs = util.functional.map_list(obj.retrieve_ids,function(o){return o.copy_id;});
									for (var i = 0; i < circs.length; i++) {
										var robj = obj.network.simple_request('FM_CIRC_EDIT_DUE_DATE',[ses(),circs[i],due_date]);
										if (typeof robj.ilsevent != 'undefined') { if (robj.ilsevent != 0) throw(robj); }
									}
									obj.retrieve();
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('The due dates were not likely modified.',E);
							}
						}
					],
					'cmd_items_mark_lost' : [
						['command'],
						function() {
							try {
							for (var i = 0; i < obj.retrieve_ids.length; i++) {
								var barcode = obj.retrieve_ids[i].barcode;
								dump('Mark barcode lost = ' + barcode);
								var robj = obj.network.simple_request( 'MARK_ITEM_LOST', [ ses(), { barcode: barcode } ]);
								if (typeof robj.ilsevent != 'undefined') { if (robj.ilsevent != 0) throw(robj); }
							}
							obj.retrieve();
							} catch(E) {
								obj.error.standard_unexpected_error_alert('The items were not likely marked lost.',E);
							}
						}
					],
					'cmd_items_claimed_returned' : [
						['command'],
						function() {
							try {
							function check_date(value) {
								JSAN.use('util.date');
								try {
									if (! util.date.check('YYYY-MM-DD',value) ) { 
										throw('Invalid Date'); 
									}
									if ( util.date.formatted_date(new Date(),'%F') == value) { 
										return true;
									}
									if (! util.date.check_past('YYYY-MM-DD',value) ) { 
										throw('Claims Returned Date cannot be in the future.'); 
									}
									return true;
								} catch(E) {
									alert(E);
									return false;
								}
							}

							JSAN.use('util.functional');
							var title = 'Claimed Returned';
							var value = 'YYYY-MM-DD';
							var text = 'Enter a claimed returned date for these copies: ' + 
								util.functional.map_list(obj.retrieve_ids,function(o){return o.barcode;}).join(', ');
							var backdate; var invalid = true;
							while(invalid) {
								backdate = window.prompt(text,value,title);
								if (backdate) {
									invalid = ! check_date(backdate);
								} else {
									invalid = false;
								}
							}
							alert('backdate = ' + backdate);
							if (backdate) {
								var barcodes = util.functional.map_list(obj.retrieve_ids,function(o){return o.barcode;});
								for (var i = 0; i < barcodes.length; i++) {
									var robj = obj.network.simple_request(
										'MARK_ITEM_CLAIM_RETURNED', 
										[ ses(), { barcode: barcodes[i], backdate: backdate } ]
									);
									if (typeof robj.ilsevent != 'undefined') { if (robj.ilsevent != 0) throw(robj); }
								}
								obj.retrieve();
							}
						} catch(E) {
							obj.error.standard_unexpected_error_alert('The items were not likely marked Claimed Returned.',E);
						}
						}
					],
					'cmd_items_checkin' : [
						['command'],
						function() {
							try {
								JSAN.use('circ.util');
								for (var i = 0; i < obj.retrieve_ids.length; i++) {
									var barcode = obj.retrieve_ids[i].barcode;
									dump('Check in barcode = ' + barcode);
									var robj = circ.util.checkin_via_barcode(
										ses(), barcode
									);
									if (typeof robj.ilsevent != 'undefined') { if (robj.ilsevent != 0) throw(robj); }
								}
								obj.retrieve();
							} catch(E) {
								obj.error.standard_unexpected_error_alert('Checkin probably did not happen.',E);
							}
						}
					],
					'cmd_show_catalog' : [
						['command'],
						function() {
							try {
								for (var i = 0; i < obj.retrieve_ids.length; i++) {
									var doc_id = obj.retrieve_ids[i].doc_id;
									if (!doc_id) {
										alert(obj.retrieve_ids[i].barcode + ' is not cataloged');
										continue;
									}
									var opac_url = xulG.url_prefix( urls.opac_rdetail ) + '?r=' + doc_id;
									var content_params = { 
										'session' : ses(),
										'authtime' : ses('authtime'),
										'opac_url' : opac_url,
									};
									xulG.new_tab(
										xulG.url_prefix(urls.XUL_OPAC_WRAPPER), 
										{'tab_name':'Retrieving title...'}, 
										content_params
									);
								}
							} catch(E) {
								obj.error.standard_unexpected_error_alert('',E);
							}
						}
					],
				}
			}
		);

		obj.retrieve();

		obj.controller.view.cmd_items_claimed_returned.setAttribute('disabled','true');
		obj.controller.view.cmd_items_renew.setAttribute('disabled','true');
		obj.controller.view.cmd_items_checkin.setAttribute('disabled','true');
		obj.controller.view.cmd_items_edit.setAttribute('disabled','true');
		obj.controller.view.cmd_items_mark_lost.setAttribute('disabled','true');
		obj.controller.view.cmd_show_catalog.setAttribute('disabled','true');
	},

	'retrieve' : function(dont_show_me_the_list_change) {
		alert('pause');
		var obj = this;
		if (window.xulG && window.xulG.checkouts) {
			obj.checkouts = window.xulG.checkouts;
		} else {
			obj.checkouts = obj.network.request(
				api.FM_CIRC_RETRIEVE_VIA_USER.app,
				api.FM_CIRC_RETRIEVE_VIA_USER.method,
				[ ses(), obj.patron_id ]
			);
				
		}

		function gen_list_append(checkout) {
			return function() {
				obj.list.append(
					{
						'row' : {
							'my' : {
								'circ' : checkout,
							}
						},
					}
				);
			};
		}

		obj.list.clear();

		JSAN.use('util.exec'); var exec = new util.exec();
		var rows = [];
		for (var i in obj.checkouts) {
			rows.push( gen_list_append(obj.checkouts[i]) );
		}
		exec.chain( rows );
		if (!dont_show_me_the_list_change) {
			if (window.xulG && typeof window.xulG.on_list_change == 'function') {
				try { window.xulG.on_list_change(obj.checkouts); } catch(E) { this.error.sdump('D_ERROR',E); }
			}
		}
	},

	'on_select' : function(list) {

		dump('patron.items.on_select list = ' + js2JSON(list) + '\n');

		var obj = this;

		obj.controller.view.cmd_items_claimed_returned.setAttribute('disabled','false');
		obj.controller.view.cmd_items_renew.setAttribute('disabled','false');
		obj.controller.view.cmd_items_checkin.setAttribute('disabled','false');
		obj.controller.view.cmd_items_edit.setAttribute('disabled','false');
		obj.controller.view.cmd_items_mark_lost.setAttribute('disabled','false');
		obj.controller.view.cmd_show_catalog.setAttribute('disabled','false');

		obj.retrieve_ids = list;
	}
}

dump('exiting patron.items.js\n');
