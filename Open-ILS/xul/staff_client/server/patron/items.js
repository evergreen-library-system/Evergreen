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

		obj.session = params['session'];
		obj.patron_id = params['patron_id'];

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'title' : { 'hidden' : false, 'flex' : '3' },
				'due_date' : { 'hidden' : false },
				'renewal_remaining' : { 'hidden' : false },
			} 
		);

		JSAN.use('util.list'); obj.list = new util.list('items_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
				'retrieve_row' : function(params) {

					var row = params.row;

					var funcs = [
						
						function() {

							row.my.mvr = obj.network.request(
								api.MODS_SLIM_RECORD_RETRIEVE_VIA_COPY.app,
								api.MODS_SLIM_RECORD_RETRIEVE_VIA_COPY.method,
								[ row.my.circ.target_copy() ]
							);

						},
						
						function() {

							row.my.acp = obj.network.request(
								api.FM_ACP_RETRIEVE.app,
								api.FM_ACP_RETRIEVE.method,
								[ row.my.circ.target_copy() ]
							);

							params.row_node.setAttribute( 'retrieve_id',row.my.acp.barcode() );

						},

						function() {

							if (typeof params.on_retrieve == 'function') {
								params.on_retrieve(row);
							}

						},
					];

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
						function(o) { return o.getAttribute('retrieve_id'); }
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
									'patron' : patron.util.retrieve_au_via_id(obj.session,obj.patron_id), 
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
							for (var i = 0; i < obj.retrieve_ids.length; i++) {
								var barcode = obj.retrieve_ids[i];
								dump('Renew barcode = ' + barcode);
								var renew = obj.network.simple_request(
									'CHECKOUT_RENEW', 
									[ obj.session, { barcode: barcode, patron: obj.patron_id } ]
								);
								dump('  result = ' + js2JSON(renew) + '\n');
							}
							if (window.xulG && typeof window.xulG.display_refresh == 'function') {
								window.xulG.display_refresh();
							}

						}
					],
					'cmd_items_edit' : [
						['command'],
						function() {
						}
					],
					'cmd_items_mark_lost' : [
						['command'],
						function() {
							for (var i = 0; i < obj.retrieve_ids.length; i++) {
								var barcode = obj.retrieve_ids[i];
								dump('Mark barcode lost = ' + barcode);
								var lost = obj.network.simple_request(
									'MARK_ITEM_LOST', 
									[ obj.session, { barcode: barcode } ]
								);
								dump('  result = ' + js2JSON(lost) + '\n');
							}
							if (window.xulG && typeof window.xulG.display_refresh == 'function') {
								window.xulG.display_refresh();
							}
						}
					],
					'cmd_items_claimed_returned' : [
						['command'],
						function() {
							for (var i = 0; i < obj.retrieve_ids.length; i++) {
								var barcode = obj.retrieve_ids[i];
								var backdate = window.prompt('This will be replaced with our generic valdiating popup calendar/date widget','2004-12-12','Claims Returned Date');
								dump('Mark barcode lost = ' + barcode);
								var lost = obj.network.simple_request(
									'MARK_ITEM_CLAIM_RETURNED', 
									[ obj.session, { barcode: barcode, backdate: backdate } ]
								);
								dump('  result = ' + js2JSON(lost) + '\n');
							}
							if (window.xulG && typeof window.xulG.display_refresh == 'function') {
								window.xulG.display_refresh();
							}
						}
					],
					'cmd_items_checkin' : [
						['command'],
						function() {
							JSAN.use('circ.util');
							for (var i = 0; i < obj.retrieve_ids.length; i++) {
								var barcode = obj.retrieve_ids[i];
								dump('Check in barcode = ' + barcode);
								var checkin = circ.util.checkin_via_barcode(
									obj.session, barcode
								);
								dump('  result = ' + js2JSON(checkin) + '\n');
							}
							if (window.xulG && typeof window.xulG.display_refresh == 'function') {
								window.xulG.display_refresh();
							}
						}
					],
					'cmd_show_catalog' : [
						['command'],
						function() {
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

	'retrieve' : function() {
		var obj = this;
		if (window.xulG && window.xulG.checkouts) {
			obj.checkouts = window.xulG.checkouts;
		} else {
			obj.checkouts = obj.network.request(
				api.FM_CIRC_RETRIEVE_VIA_USER.app,
				api.FM_CIRC_RETRIEVE_VIA_USER.method,
				[ obj.session, obj.patron_id ]
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

		JSAN.use('util.exec'); var exec = new util.exec();
		var rows = [];
		for (var i in obj.checkouts) {
			rows.push( gen_list_append(obj.checkouts[i]) );
		}
		exec.chain( rows );
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
