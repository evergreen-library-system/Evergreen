dump('entering patron.items.js\n');

if (typeof patron == 'undefined') patron = {};
patron.items = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

patron.items.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.patron_id = params['patron_id'];

		obj.init_lists();

		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'cmd_broken' : [ ['command'], function() { alert('Not Yet Implemented'); } ],
					'cmd_items_print' : [ ['command'], function() { obj.items_print(1); } ],
					'cmd_items_print2' : [ ['command'], function() { obj.items_print(2); } ],
					'cmd_items_renew' : [ ['command'], function() { obj.items_renew(1); } ],
					'cmd_items_renew2' : [ ['command'], function() { obj.items_renew(2); } ],
					'cmd_items_edit' : [ ['command'], function() { obj.items_edit(1); } ],
					'cmd_items_edit2' : [ ['command'], function() { obj.items_edit(2); } ],
					'cmd_items_mark_lost' : [ ['command'], function() { obj.items_mark_lost(1); } ],
					'cmd_items_mark_lost2' : [ ['command'], function() { obj.items_mark_lost(2); } ],
					'cmd_items_claimed_returned' : [ ['command'], function() { obj.items_claimed_returned(1); } ],
					'cmd_items_claimed_returned2' : [ ['command'], function() { obj.items_claimed_returned(2); } ],
					'cmd_items_checkin' : [ ['command'], function() { obj.items_checkin(1); } ],
					'cmd_items_checkin2' : [ ['command'], function() { obj.items_checkin(2); } ],
					'cmd_show_catalog' : [ ['command'], function() { obj.show_catalog(1); } ],
					'cmd_show_catalog2' : [ ['command'], function() { obj.show_catalog(2); } ],
					'cmd_add_billing' : [ ['command'], function() { obj.add_billing(1); } ],
					'cmd_add_billing2' : [ ['command'], function() { obj.add_billing(2); } ],
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
		obj.controller.view.cmd_items_claimed_returned2.setAttribute('disabled','true');
		obj.controller.view.cmd_items_renew2.setAttribute('disabled','true');
		obj.controller.view.cmd_items_checkin2.setAttribute('disabled','true');
		obj.controller.view.cmd_items_edit2.setAttribute('disabled','true');
		obj.controller.view.cmd_items_mark_lost2.setAttribute('disabled','true');
		obj.controller.view.cmd_show_catalog2.setAttribute('disabled','true');
	},


	'items_print' : function(which) {
		var obj = this;
		try {
			var list = (which==2 ? obj.list2 : obj.list);
			dump(js2JSON( list.dump() ) + '\n');
			function flesh_callback() {
				try {
					JSAN.use('patron.util');
					var params = { 
						'patron' : patron.util.retrieve_au_via_id(ses(),obj.patron_id), 
						'lib' : obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ],
						'staff' : obj.data.list.au[0],
						'header' : obj.data.print_list_templates.checkout.header,
						'line_item' : obj.data.print_list_templates.checkout.line_item,
						'footer' : obj.data.print_list_templates.checkout.footer,
						'type' : obj.data.print_list_templates.checkout.type,
						'list' : list.dump(),
					};
					JSAN.use('util.print'); var print = new util.print();
					print.tree_list( params );
					setTimeout(function(){list.on_all_fleshed = null;},0);
				} catch(E) {
					obj.error.standard_unexpected_error_alert('printing 2',E);
				}
			}
			list.on_all_fleshed = flesh_callback;
			list.full_retrieve();
		} catch(E) {
			obj.error.standard_unexpected_error_alert('printing 1',E);
		}
	},

	'items_renew' : function(which) {
		var obj = this;
		try{
			var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
			JSAN.use('util.functional');
			var msg = 'Are you sure you would like to renew item' + ( retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( retrieve_ids, function(o){return o.barcode;}).join(', ') + '?';
			var r = obj.error.yns_alert(msg,'Renewing Items','Yes','No',null,'Check here to confirm this message');
			if (r != 0) { return; }
			for (var i = 0; i < retrieve_ids.length; i++) {
				try {
					var barcode = retrieve_ids[i].barcode;
					alert('Renew barcode = ' + barcode);
					var renew = obj.network.simple_request(
						'CHECKOUT_RENEW', 
						[ ses(), { barcode: barcode, patron: obj.patron_id } ],
						null,
						{
							'title' : 'Override Renew Failure?',
							'overridable_events' : [ 
								1212 /* PATRON_EXCEEDS_OVERDUE_COUNT */,
								7002 /* PATRON_EXCEEDS_CHECKOUT_COUNT */,
								7003 /* COPY_CIRC_NOT_ALLOWED */,
								7004 /* COPY_NOT_AVAILABLE */,
								7006 /* COPY_IS_REFERENCE */,
								7007 /* COPY_NEEDED_FOR_HOLD */,
								7008 /* MAX_RENEWALS_REACHED */, 
								7010 /* COPY_ALERT_MESSAGE */,
								7013 /* PATRON_EXCEEDS_FINES */,
							],
							'text' : {
								'7010' : function(r) {
									return r.payload;
								},
								'7004' : function(r) {
									//return obj.data.hash.ccs[ r.payload ].name();
									return r.payload.status().name();
									//return r.payload.name();
								},
							}
						}
					);
					if (typeof renew.ilsevent != 'undefined') renew = [ renew ];
					for (var j = 0; j < renew.length; j++) { 
						switch(renew[j].ilsevent) {
							case 0 /* SUCCESS */ : break;
							case 5000 /* PERM_FAILURE */: break;
							case 7008 /* MAX_RENEWALS_REACHED */ : break;
							default:
								throw(renew);
							break;
						}
					}
				} catch(E) {
					obj.error.standard_unexpected_error_alert('Renew probably did not happen for barcode ' + barcode,E);
				}
			}
			obj.retrieve();
		} catch(E) {
			obj.error.standard_unexpected_error_alert('Renew probably did not happen.',E);
			obj.retrieve();
		}
	},

	'items_edit' : function(which) {
			var obj = this;
			try {
				var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
				function check_date(value) {
					JSAN.use('util.date');
					try {
						if (! util.date.check('YYYY-MM-DD',value) ) { 
							throw('Invalid Date'); 
						}
						if (util.date.check_past('YYYY-MM-DD',value) ) { 
							throw('Due date needs to be after today.'); 
						}
						/*
						if ( util.date.formatted_date(new Date(),'%F') == value) { 
							throw('Due date needs to be after today.'); 
						}
						*/
						return true;
					} catch(E) {
						alert(E);
						return false;
					}
				}

				JSAN.use('util.functional');
				var title = 'Edit Due Date' + (retrieve_ids.length > 1 ? 's' : '');
				var value = 'YYYY-MM-DD';
				var text = 'Enter a new due date for these copies: ' + 
					util.functional.map_list(retrieve_ids,function(o){return o.barcode;}).join(', ');
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
					var circs = util.functional.map_list(retrieve_ids,function(o){return o.circ_id;});
					for (var i = 0; i < circs.length; i++) {
						var robj = obj.network.simple_request('FM_CIRC_EDIT_DUE_DATE',[ses(),circs[i],due_date]);
						if (typeof robj.ilsevent != 'undefined') { if (robj.ilsevent != 0) throw(robj); }
					}
					obj.retrieve();
				}
			} catch(E) {
				obj.error.standard_unexpected_error_alert('The due dates were not likely modified.',E);
				obj.retrieve();
			}
	},

	'items_mark_lost' : function(which) {
		var obj = this;
		try {
			var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
			for (var i = 0; i < retrieve_ids.length; i++) {
				var barcode = retrieve_ids[i].barcode;
				dump('Mark barcode lost = ' + barcode);
				var robj = obj.network.simple_request( 'MARK_ITEM_LOST', [ ses(), { barcode: barcode } ]);
				if (typeof robj.ilsevent != 'undefined') { if (robj.ilsevent != 0) throw(robj); }
			}
			obj.retrieve();
		} catch(E) {
			obj.error.standard_unexpected_error_alert('The items were not likely marked lost.',E);
			obj.retrieve();
		}
	},

	'items_claimed_returned' : function(which) {
		var obj = this;
		try {
			var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
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
				util.functional.map_list(retrieve_ids,function(o){return o.barcode;}).join(', ');
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
				var barcodes = util.functional.map_list(retrieve_ids,function(o){return o.barcode;});
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
			obj.retrieve();
		}
	},

	'items_checkin' : function(which) {
		var obj = this;
		try {
			var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
			JSAN.use('util.functional');
			var msg = 'Are you sure you would like to check in item' + ( retrieve_ids.length > 1 ? 's ' : ' ') + util.functional.map_list( retrieve_ids, function(o){return o.barcode;}).join(', ') + '?';
			var r = obj.error.yns_alert(msg,'Check In Items','Yes','No',null,'Check here to confirm this message');
			if (r != 0) { return; }
			JSAN.use('circ.util');
			for (var i = 0; i < retrieve_ids.length; i++) {
				var barcode = retrieve_ids[i].barcode;
				dump('Check in barcode = ' + barcode);
				var robj = circ.util.checkin_via_barcode(
					ses(), barcode
				);
				/* circ.util.checkin_via_barcode handles errors currently */
			}
			obj.retrieve();
		} catch(E) {
			obj.error.standard_unexpected_error_alert('Checkin probably did not happen.',E);
			obj.retrieve();
		}
	},

	'show_catalog' : function(which) {
		var obj = this;
		try {
			var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
			for (var i = 0; i < retrieve_ids.length; i++) {
				var doc_id = retrieve_ids[i].doc_id;
				if (!doc_id) {
					alert(retrieve_ids[i].barcode + ' is not cataloged');
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
	},

	'add_billing' : function(which) {
		var obj = this;
		try {
			var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
			JSAN.use('util.window');
			var win = new util.window();
			for (var i = 0; i < retrieve_ids.length; i++) {
				var circ_id = retrieve_ids[i].circ_id;
				var w = win.open(
					urls.XUL_PATRON_BILL_WIZARD
						+ '?patron_id=' + window.escape(obj.patron_id)
						+ '&xact_id=' + window.escape( circ_id ),
					'billwizard',
					'chrome,resizable,modal'
				);
			}
			obj.retrieve();
		} catch(E) {
			obj.error.standard_unexpected_error_alert('',E);
		}
	},

	'init_lists' : function() {
		var obj = this;

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'barcode' : { 'hidden' : false },
				'title' : { 'hidden' : false, 'flex' : '3' },
				'due_date' : { 'hidden' : false },
				'renewal_remaining' : { 'hidden' : false },
				'stop_fines' : { 'hidden' : false },
			} 
		);
		var columns2 = circ.util.columns( 
			{ 
				'barcode' : { 'hidden' : false },
				'title' : { 'hidden' : false, 'flex' : '3' },
				'checkin_time' : { 'hidden' : false },
				'stop_fines' : { 'hidden' : false },
			} 
		);

		function retrieve_row(params) {
			var row = params.row;

			var funcs = [];


			funcs.push(
				function() {
					row.my.circ = obj.network.simple_request('FM_CIRC_RETRIEVE_VIA_ID',[ ses(), row.my.circ_id ]);
				}
			);
			
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

		}

		JSAN.use('util.list'); obj.list = new util.list('items_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
				'retrieve_row' : retrieve_row,
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
		
		obj.list2 = new util.list('items_list2');
		obj.list2.init(
			{
				'columns' : columns2,
				'map_row_to_column' : circ.util.std_map_row_to_column(),
				'retrieve_row' : retrieve_row,
				'on_select' : function(ev) {
					JSAN.use('util.functional');
					var sel = obj.list2.retrieve_selection();
					var list = util.functional.map_list(
						sel,
						function(o) { return JSON2js( o.getAttribute('retrieve_id') ); }
					);
					if (typeof obj.on_select2 == 'function') {
						obj.on_select2(list);
					}
				},
			}
		);
	},

	'retrieve' : function(dont_show_me_the_list_change) {
		var obj = this;
		if (window.xulG && window.xulG.checkouts) {
			obj.checkouts = window.xulG.checkouts;
		} else {
			obj.checkouts = [];
			obj.checkouts2 = [];
			var robj = obj.network.simple_request(
				'FM_CIRC_RETRIEVE_VIA_USER',
				[ ses(), obj.patron_id ]
			);
			if (typeof robj.ilsevent!='undefined') {
				obj.error.standard_unexpected_error_alert('Error retrieving circulations.',E);
			} else {
				obj.checkouts = obj.checkouts.concat( robj.overdue );
				obj.checkouts = obj.checkouts.concat( robj.out );
				obj.checkouts2 = obj.checkouts2.concat( robj.lost );
				obj.checkouts2 = obj.checkouts2.concat( robj.claims_returned );
				obj.checkouts2 = obj.checkouts2.concat( robj.long_overdue );
			}
			var robj = obj.network.simple_request(
				'FM_CIRC_IN_WITH_FINES_VIA_USER',
				[ ses(), obj.patron_id ]
			);
			if (typeof robj.ilsevent!='undefined') {
				obj.error.standard_unexpected_error_alert('Error retrieving circulations.',E);
			} else {
				obj.checkouts2 = obj.checkouts2.concat( robj.lost );
				obj.checkouts2 = obj.checkouts2.concat( robj.claims_returned );
				obj.checkouts2 = obj.checkouts2.concat( robj.long_overdue );
			}
		}

		function gen_list_append(circ_id,which_list) {
			return function() {
				try {
					switch(which_list) {
						case 1:
							obj.list2.append( { 'row' : { 'my' : { 'circ_id' : circ_id } }, } );
						break;
						default:
							obj.list.append( { 'row' : { 'my' : { 'circ_id' : circ_id } }, } );
						break;
					}
				} catch(E) {
					alert(E);
				}
			};
		}

		obj.list.clear(); obj.list2.clear();

		JSAN.use('util.exec'); var exec = new util.exec();
		var rows = [];
		for (var i in obj.checkouts) {
			rows.push( gen_list_append(obj.checkouts[i],0) );
		}
		for (var i in obj.checkouts2) {
			rows.push( gen_list_append(obj.checkouts2[i],1) );
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
	},

	'on_select2' : function(list) {
	
		dump('patron.items.on_select2 list = ' + js2JSON(list) + '\n');

		var obj = this;

		obj.controller.view.cmd_items_claimed_returned2.setAttribute('disabled','false');
		obj.controller.view.cmd_items_renew2.setAttribute('disabled','false');
		obj.controller.view.cmd_items_checkin2.setAttribute('disabled','false');
		obj.controller.view.cmd_items_edit2.setAttribute('disabled','false');
		obj.controller.view.cmd_items_mark_lost2.setAttribute('disabled','false');
		obj.controller.view.cmd_show_catalog2.setAttribute('disabled','false');

		this.retrieve_ids2 = list;
	},

}

dump('exiting patron.items.js\n');
