dump('entering patron.items.js\n');

function $(id) { return document.getElementById(id); }

if (typeof patron == 'undefined') patron = {};
patron.items = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

patron.items.prototype = {

	'list_circ_map' : {},

	'init' : function( params ) {

		var obj = this;

		obj.patron_id = params['patron_id'];

		obj.init_lists();

		JSAN.use('util.controller'); obj.controller = new util.controller();
		obj.controller.init(
			{
				'control_map' : {
					'save_columns' : [ [ 'command' ], function() { obj.list.save_columns(); } ],
					'save_columns2' : [ [ 'command' ], function() { obj.list2.save_columns(); } ],
					'cmd_broken' : [ ['command'], function() { alert('Not Yet Implemented'); } ],
					'sel_clip' : [ ['command'], function() { obj.list.clipboard(); } ],
					'sel_clip2' : [ ['command'], function() { obj.list2.clipboard(); } ],
					'sel_patron' : [ ['command'], function() { JSAN.use('circ.util'); circ.util.show_last_few_circs(obj.retrieve_ids); } ],
					'sel_bucket' : [
						['command'],
						function() {
							JSAN.use('cat.util');
							cat.util.add_copies_to_bucket(util.functional.map_list( obj.retrieve_ids, function(o) { return o.copy_id; } ) );
						}
					],
					'sel_bucket2' : [
						['command'],
						function() {
							JSAN.use('cat.util');
							cat.util.add_copies_to_bucket(util.functional.map_list( obj.retrieve_ids2, function(o) { return o.copy_id; } ) );
						}
					],
					'sel_mark_items_damaged' : [
						['command'],
						function() {
							JSAN.use('cat.util'); JSAN.use('util.functional');
							cat.util.mark_item_damaged( util.functional.map_list( obj.retrieve_ids, function(o) { return o.copy_id; } ) );
						}
					],
					'sel_mark_items_missing' : [
						['command'],
						function() {
							JSAN.use('cat.util'); JSAN.use('util.functional');
							cat.util.mark_item_missing( util.functional.map_list( obj.retrieve_ids, function(o) { return o.copy_id; } ) );
						}
					],
					'sel_mark_items_damaged2' : [
						['command'],
						function() {
							JSAN.use('cat.util'); JSAN.use('util.functional');
							cat.util.mark_item_damaged( util.functional.map_list( obj.retrieve_ids2, function(o) { return o.copy_id; } ) );
						}
					],
					'sel_mark_items_missing2' : [
						['command'],
						function() {
							JSAN.use('cat.util'); JSAN.use('util.functional');
							cat.util.mark_item_missing( util.functional.map_list( obj.retrieve_ids2, function(o) { return o.copy_id; } ) );
						}
					],
					'sel_copy_details' : [ ['command'],
						function() {
							JSAN.use('circ.util');
							for (var i = 0; i < obj.retrieve_ids.length; i++) { circ.util.show_copy_details( obj.retrieve_ids[i].copy_id ); }
						}
					],
					'sel_patron2' : [ ['command'], function() { JSAN.use('circ.util'); circ.util.show_last_few_circs(obj.retrieve_ids2); } ],
					'sel_copy_details2' : [ ['command'],
						function() {
							JSAN.use('circ.util');
							for (var i = 0; i < obj.retrieve_ids2.length; i++) { circ.util.show_copy_details( obj.retrieve_ids2[i].copy_id ); }
						}
					],
					'cmd_items_print' : [ ['command'], function() { obj.items_print(1); } ],
					'cmd_items_print2' : [ ['command'], function() { obj.items_print(2); } ],
					'cmd_items_export' : [ ['command'], function() { obj.items_export(1); } ],
					'cmd_items_export2' : [ ['command'], function() { obj.items_export(2); } ],
					'cmd_items_renew' : [ ['command'], function() { obj.items_renew(1); /* obj.retrieve();*/ } ],
					'cmd_items_renew_all' : [ ['command'], function() { obj.items_renew_all(); } ],
					'cmd_items_renew2' : [ ['command'], function() { obj.items_renew(2); /* obj.retrieve();*/ } ],
					'cmd_items_edit' : [ ['command'], function() { obj.items_edit(1);  /*obj.retrieve();*/ } ],
					'cmd_items_edit2' : [ ['command'], function() { obj.items_edit(2);  /*obj.retrieve();*/ } ],
					'cmd_items_mark_lost' : [ ['command'], function() { obj.items_mark_lost(1);  /*obj.retrieve();*/ } ],
					'cmd_items_mark_lost2' : [ ['command'], function() { obj.items_mark_lost(2);  /*obj.retrieve();*/ } ],
					'cmd_items_claimed_returned' : [ ['command'], function() { obj.items_claimed_returned(1);  /*obj.retrieve();*/ } ],
					'cmd_items_claimed_returned2' : [ ['command'], function() { obj.items_claimed_returned(2);  /*obj.retrieve();*/ } ],
					'cmd_items_checkin' : [ ['command'], function() { obj.items_checkin(1);  /*obj.retrieve();*/ } ],
					'cmd_items_checkin2' : [ ['command'], function() { obj.items_checkin(2);  /*obj.retrieve();*/ } ],
					'cmd_show_catalog' : [ ['command'], function() { obj.show_catalog(1); } ],
					'cmd_show_catalog2' : [ ['command'], function() { obj.show_catalog(2); } ],
					'cmd_add_billing' : [ ['command'], function() { obj.add_billing(1);  /*obj.retrieve();*/ } ],
					'cmd_add_billing2' : [ ['command'], function() { obj.add_billing(2);  /*obj.retrieve();*/ } ],
					'cmd_show_noncats' : [ ['command'], function() { obj.show_noncats(); } ]
				}
			}
		);

		obj.retrieve();

		obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','true');
		obj.controller.view.sel_mark_items_missing.setAttribute('disabled','true');
		obj.controller.view.sel_mark_items_damaged2.setAttribute('disabled','true');
		obj.controller.view.sel_mark_items_missing2.setAttribute('disabled','true');
		obj.controller.view.sel_clip.setAttribute('disabled','true');
		obj.controller.view.sel_clip2.setAttribute('disabled','true');
		obj.controller.view.sel_bucket.setAttribute('disabled','true');
		obj.controller.view.sel_bucket2.setAttribute('disabled','true');
		obj.controller.view.sel_copy_details.setAttribute('disabled','true');
		obj.controller.view.sel_patron.setAttribute('disabled','true');
		obj.controller.view.sel_copy_details2.setAttribute('disabled','true');
		obj.controller.view.sel_patron2.setAttribute('disabled','true');
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

	'show_noncats' : function() {
		var obj = this; var checkout = {};
		try {
			var robj = obj.network.simple_request('FM_ANCC_RETRIEVE_VIA_USER.authoritative',[ ses(), obj.patron_id ]);
			if (typeof robj.ilsevent != 'undefined') throw(robj);

			for (var ii = 0; ii < robj.length; ii++) {
				try {
					var nc_circ = obj.network.simple_request('FM_ANCC_RETRIEVE_VIA_ID',[ ses(), robj[ii] ]);
					if (typeof nc_circ.ilsevent != 'undefined') throw(nc_circ);
					var fake_circ = new aoc();
					fake_circ.circ_lib( nc_circ.circ_lib() );
					fake_circ.circ_staff( nc_circ.staff() );
					fake_circ.usr( nc_circ.patron() );
					fake_circ.xact_start( nc_circ.circ_time() );
					fake_circ.renewal_remaining(0);
					fake_circ.stop_fines('Non-Cataloged');
						
					JSAN.use('util.date');
					var c = nc_circ.circ_time();
					var d = c == "now" ? new Date() : util.date.db_date2Date( c );
					var t = obj.data.hash.cnct[ nc_circ.item_type() ];
					if (!t) {
						var robj2 = obj.network.simple_request('FM_CNCT_RETRIEVE',[ nc_circ.circ_lib() ]);
						if (typeof robj2.ilsevent != 'undefined') throw(robj);
						obj.data.stash_retrieve();
						for (var j = 0; j < robj2.length; j++) {
							if (! obj.data.hash.cnct[ robj2[j].id() ] ) {
								obj.data.hash.cnct[ robj2[j].id() ] = robj2[j];
								obj.data.list.cnct.push( robj2[j] );
							}
						}
						obj.data.stash('hash','list');
						t = obj.data.hash.cnct[ nc_circ.item_type() ];
					}
					var cd = t.circ_duration() || $("patronStrings").getString('staff.patron.items.show_noncats.14_days');
					var i = util.date.interval_to_seconds( cd ) * 1000;
					d.setTime( Date.parse(d) + i );
					fake_circ.due_date( util.date.formatted_date(d,'%F') );
	
					var fake_record = new mvr();
					fake_record.title( obj.data.hash.cnct[ nc_circ.item_type() ].name());
	
					var fake_copy = new acp();
					fake_copy.barcode( '' );
					fake_copy.circ_lib( nc_circ.circ_lib() );

					obj.list.append( { 'row' : { 'my' : { 'circ' : fake_circ, 'mvr' : fake_record, 'acp' : fake_copy } }, 'to_bottom' : true, 'no_auto_select' : true } );

				} catch(F) {
					obj.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.items.show_noncats.err_showing_noncat', [robj[ii].id()]),F);
				}
			}

		} catch(E) {
			obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.items.show_noncats.err_showing_circulations'),E);
		}
	},

	'items_print' : function(which) {
		var obj = this;
		try {
			var list = (which==2 ? obj.list2 : obj.list);
            JSAN.use('patron.util');
            var params = { 
                'patron' : patron.util.retrieve_fleshed_au_via_id(ses(),obj.patron_id), 
                'template' : 'items_out'
            };
            list.print( params );
		} catch(E) {
			obj.error.standard_unexpected_error_alert('printing 1',E);
		}
	},

	'items_export' : function(which) {
		var obj = this;
		try {
			var list = (which==2 ? obj.list2 : obj.list);
			list.dump_csv_to_clipboard();
		} catch(E) {
			obj.error.standard_unexpected_error_alert('export 1',E);
		}
	},

	'items_renew_all' : function() {
		try {
			var obj = this; var list = obj.list;
			if (list.on_all_fleshed != null) {
				var r = window.confirm($("patronStrings").getString('staff.patron.items.items_renew_all.list_is_busy'));
				if (!r) return;
			}
			var r = window.confirm($("patronStrings").getString('staff.patron.items.items_renew_all.renew_items_in_list'));
			if (!r) return;
			function flesh_callback() {
				try {
					obj.list.select_all();
					obj.items_renew(1,true);	
					setTimeout(function(){list.on_all_fleshed = null; /* obj.retrieve();*/ },0);
				} catch(E) {
					obj.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.items.items_renew_all.items_not_renewed', ['2']),E);
				}
			}
			list.on_all_fleshed = flesh_callback;
			list.full_retrieve();
		} catch(E) {
			this.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.items.items_renew_all.items_not_renewed', ['1']),E);
		}
	},

	'items_renew' : function(which,skip_prompt) {
		var obj = this;
		try{
			JSAN.use('circ.util');
			var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
			if (!retrieve_ids || retrieve_ids.length == 0) return;
			JSAN.use('util.functional');
			if (!skip_prompt) {
				var msg = '';
				if(retrieve_ids.length > 1) {
					msg += $("patronStrings").getFormattedString('staff.patron.items.items_renew.renew_item_plural',[util.functional.map_list( retrieve_ids, function(o){return o.barcode;}).join(', ')]);
				} else {
					msg += $("patronStrings").getFormattedString('staff.patron.items.items_renew.renew_item_singular', [util.functional.map_list( retrieve_ids, function(o){return o.barcode;}).join(', ')]);
				}
				var r = window.confirm(msg);
				if (!r) { return; }
			}

			var count = 0;

			function gen_renew(bc,circ_id) {
				var x = document.getElementById('renew_msgs');
				if (x) {
					var l = document.createElement('label');
					l.setAttribute('value', $("patronStrings").getFormattedString('staff.patron.items.items_renew.renewing',[bc]));
					x.appendChild(l);
				}
				var renew = circ.util.renew_via_barcode( barcode, obj.patron_id, 
					function(r) {
                        try {
                            if ( (typeof r[0].ilsevent != 'undefined' && r[0].ilsevent == 0) ) {
                                l.setAttribute('value', $("patronStrings").getFormattedString('staff.patron.items.items_renew.renewed',[bc]));
                                obj.list_circ_map[ circ_id ].row.my.circ = r[0].payload.circ;
                                obj.list_circ_map[ circ_id ].row.my.acp = r[0].payload.copy;
                                obj.list_circ_map[ circ_id ].row.my.mvr = r[0].payload.record;
                                // A renewed circ is a new circ, and has a new circ_id.
                                obj.list_circ_map[ r[0].payload.circ.id() ] = obj.list_circ_map[ circ_id ];
                            } else {
                                var msg = $("patronStrings").getFormattedString('staff.patron.items.items_renew.not_renewed',[bc, r[0].textcode + r[0].desc]);
                                l.setAttribute('value', msg);
                                alert(msg);
                            }
                            count--;
                            if (count == 0) {
                                //if (window.confirm('Action completed. Refresh list?')) obj.retrieve();
                                JSAN.use('util.widgets'); util.widgets.remove_children(x);
                            }
                            obj.refresh(circ_id);
                        } catch(E) {
   					       obj.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.items.items_renew.err_in_renew_via_barcode',[barcode]), E);
                        }
					} 
				);
			}

			for (var i = 0; i < retrieve_ids.length; i++) {
				try {
					count++;
					var barcode = retrieve_ids[i].barcode;
					var circ_id = retrieve_ids[i].circ_id;
					gen_renew(barcode,circ_id);
				} catch(E) {
					obj.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.items.items_renew.no_renew_for_barcode',[barcode]), E);
				}
			}
		} catch(E) {
			obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.items.items_renew.no_renew'),E);
		}
	},

	'items_edit' : function(which) {
			var obj = this;
			try {
				var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
				if (!retrieve_ids || retrieve_ids.length == 0) return;
				function check_date(value) {
					JSAN.use('util.date');
					try {
						if (! util.date.check('YYYY-MM-DD',value) ) { 
							throw($("patronStrings").getString('staff.patron.items.items_edit.invalid_date')); 
						}
						if (util.date.check_past('YYYY-MM-DD',value) ) { 
							throw($("patronStrings").getString('staff.patron.items.items_edit.need_later_date')); 
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
				var title = '';
				if (retrieve_ids.length > 1) {
					title += $("patronStrings").getString('staff.patron.items.items_edit.edit_due_date.plural');
				} else {
					title += $("patronStrings").getString('staff.patron.items.items_edit.edit_due_date.singular');
				}
				var value = 'YYYY-MM-DD';
				var text = $("patronStrings").getFormattedString('staff.patron.items.items_edit.new_due_date', [util.functional.map_list(retrieve_ids,function(o){return o.barcode;}).join(', ')]);
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
				}
				for (var i = 0; i < obj.retrieve_ids.length; i++) {
					obj.refresh(retrieve_ids[i].circ_id);
				}
			} catch(E) {
				obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.items.items_edit.dates_not_modified'),E);
			}
	},

	'items_mark_lost' : function(which) {
		var obj = this;
		try {
			var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
			if (!retrieve_ids || retrieve_ids.length == 0) return;
			for (var i = 0; i < retrieve_ids.length; i++) {
				var barcode = retrieve_ids[i].barcode;
				dump($("patronStrings").getFormattedString('staff.patron.items.items_edit.mark_barcode_lost', [barcode]));
				var robj = obj.network.simple_request( 'MARK_ITEM_LOST', [ ses(), { barcode: barcode } ]);
				if (typeof robj.ilsevent != 'undefined') { 
                    switch(Number(robj.ilsevent)) {
                        case 7018 /* COPY_MARKED_LOST */ :
                            alert( $("patronStrings").getFormattedString('staff.patron.items.items_edit.item_barcode', [barcode, robj.desc]) );
                        break;
                        default: throw(robj);
                    }
                } else {
    				obj.refresh(retrieve_ids[i].circ_id,true);
                }
			}
		} catch(E) {
			obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.items.items_edit.items_not_marked_lost'),E);
		}
	},

	'items_claimed_returned' : function(which) {
		var obj = this;
		try {
			JSAN.use('util.date');
			var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
			if (!retrieve_ids || retrieve_ids.length == 0) return;
			function check_date(value) {
				try {
					if (! util.date.check('YYYY-MM-DD',value) ) { 
						throw($("patronStrings").getString('staff.patron.items.items_edit.invalid_date')); 
					}
					if ( util.date.formatted_date(new Date(),'%F') == value) { 
						return true;
					}
					if (! util.date.check_past('YYYY-MM-DD',value) ) { 
						throw($("patronStrings").getString('staff.patron.items.items_claimed_returned.date_cannot_be_in_future')); 
					}
					return true;
				} catch(E) {
					alert(E);
					return false;
				}
			}

			JSAN.use('util.functional');
			var title = $("patronStrings").getString('staff.patron.items.items_claimed_returned.claimed_returned');
			var value = 'YYYY-MM-DD';
			var text = $("patronStrings").getFormattedString('staff.patron.items.items_claimed_returned.enter_returned_date',
				[util.functional.map_list(retrieve_ids,function(o){return o.barcode;}).join(', ')]);
			var backdate; var invalid = true;
			while(invalid) {
				backdate = window.prompt(text,value,title);
				if (backdate) {
					invalid = ! check_date(backdate);
				} else {
					invalid = false;
				}
			}
			//alert('backdate = ' + backdate);
			if (backdate) {
				backdate = util.date.formatted_date(backdate + ' 00:00:00','%{iso8601}');
				var barcodes = util.functional.map_list(retrieve_ids,function(o){return o.barcode;});
				for (var i = 0; i < barcodes.length; i++) {
					var robj = obj.network.simple_request(
						'MARK_ITEM_CLAIM_RETURNED', 
						[ ses(), { barcode: barcodes[i], backdate: backdate } ]
					);
					if (typeof robj.ilsevent != 'undefined') { if (robj.ilsevent != 0) throw(robj); }
				}
			}
			for (var i = 0; i < retrieve_ids.length; i++) obj.refresh(retrieve_ids[i].circ_id,true);
		} catch(E) {
			obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.items.items_claimed_returned.not_marked_claimed_returned'),E);
		}
	},

	'items_checkin' : function(which) {
		var obj = this;
		try {
			var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
			if (!retrieve_ids || retrieve_ids.length == 0) return;
			JSAN.use('util.functional');
			var msg = '';
			if (retrieve_ids.length > 1) {
				msg += $("patronStrings").getFormattedString('staff.patron.items.items_checkin.confirm_item_check_in.plural',
					[util.functional.map_list( retrieve_ids, function(o){return o.barcode;}).join(', ')]);
			} else {
				msg += $("patronStrings").getFormattedString('staff.patron.items.items_checkin.confirm_item_check_in.singular',
					[util.functional.map_list( retrieve_ids, function(o){return o.barcode;}).join(', ')]);
			}
			var r = window.confirm(msg);
			if (!r) { return; }
			JSAN.use('circ.util');
			for (var i = 0; i < retrieve_ids.length; i++) {
				var copy_id = retrieve_ids[i].copy_id;
				dump('Check in copy_id = ' + copy_id + ' barcode = ' + retrieve_ids[i].barcode + '\n');
				var robj = circ.util.checkin_via_barcode(
					ses(), { 'copy_id' : copy_id }
				);
				/* circ.util.checkin_via_barcode handles errors currently */
			}
			obj.retrieve();
		} catch(E) {
			obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.items.items_checkin.no_checkin'),E);
		}
	},

	'show_catalog' : function(which) {
		var obj = this;
		try {
			var retrieve_ids = ( which == 2 ? obj.retrieve_ids2 : obj.retrieve_ids );
			if (!retrieve_ids || retrieve_ids.length == 0) return;
			for (var i = 0; i < retrieve_ids.length; i++) {
				var doc_id = retrieve_ids[i].doc_id;
				if (!doc_id) {
					alert($("patronStrings").getFormattedString('staff.patron.items.show_catalog.barcode_not_cataloged', [retrieve_ids[i].barcode]));
					continue;
				}
				var opac_url = xulG.url_prefix( urls.opac_rdetail ) + '?r=' + doc_id;
				var content_params = { 
					'session' : ses(),
					'authtime' : ses('authtime'),
					'opac_url' : opac_url
				};
				xulG.new_tab(
					xulG.url_prefix(urls.XUL_OPAC_WRAPPER), 
					{'tab_name': $("patronStrings").getString('staff.patron.items.show_catalog.retrieving_title')}, 
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
			if (!retrieve_ids || retrieve_ids.length == 0) return;
			JSAN.use('util.window'); var win = new util.window();
			for (var i = 0; i < retrieve_ids.length; i++) {
				var circ_id = retrieve_ids[i].circ_id;
				var my_xulG = win.open(
					urls.XUL_PATRON_BILL_WIZARD,
						//+ '?patron_id=' + window.escape(obj.patron_id)
						//+ '&xact_id=' + window.escape( circ_id ),
					'billwizard',
					'chrome,resizable,modal',
					{ 'patron_id' : obj.patron_id, 'xact_id' : circ_id }
				);
			}
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
				'checkout_lib' : { 'hidden' : false },
				'circ_lib' : { 'hidden' : false },
				'title' : { 'hidden' : false, 'flex' : '3' },
				'due_date' : { 'hidden' : false },
				'renewal_remaining' : { 'hidden' : false },
				'stop_fines' : { 'hidden' : false }
			} 
		);
		var columns2 = circ.util.columns( 
			{ 
				'barcode' : { 'hidden' : false },
				'checkout_lib' : { 'hidden' : false },
				'circ_lib' : { 'hidden' : false },
				'title' : { 'hidden' : false, 'flex' : '3' },
				'checkin_time' : { 'hidden' : false },
				'stop_fines' : { 'hidden' : false }
			} 
		);

		function retrieve_row(params) {
            try { 
    			var row = params.row;

    			if (!row.my.circ_id) {
    				if (typeof params.on_retrieve == 'function') { 
                        params.on_retrieve(row); 
                    }
    				return row;
    			}
    
    			if (!row.my.circ) {
    				obj.network.simple_request(
    					'FM_CIRC_DETAILS.authoritative',
    					[ row.my.circ_id ],
    					function(req) {
    						try { 
    							var robj = req.getResultObject();
    							if (typeof robj.ilsevent != 'undefined') throw(robj);
    							if (typeof robj.ilsevent == 'null') throw('null result');
    							row.my.circ = robj.circ;
    							row.my.acp = robj.copy;
    							row.my.mvr = robj.mvr;
    							row.my.acn = robj.volume;
                                row.my.record = robj.record;
    	
    							var copy_id = row.my.circ.target_copy();
    							if (typeof copy_id == 'object') {
    								if (copy_id != null) {
    									copy_id = copy_id.id();
    								} else {
    									if (typeof robj.copy == 'object' && robj.copy != null) copy_id = robj.copy.id();
    								}
    							} else {
    									if (typeof robj.copy == 'object' && robj.copy != null) copy_id = robj.copy.id();
    							}
    							
    							params.row_node.setAttribute( 'retrieve_id', js2JSON({'copy_id':copy_id,'circ_id':row.my.circ.id(),'barcode':row.my.acp.barcode(),'doc_id': ( row.my.record ? row.my.record.id() : null ) }) );
    		
    							if (typeof params.on_retrieve == 'function') {
    								params.on_retrieve(row);
    							}
    						} catch(E) {
    							obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.items.retrieve_row.callback_error'), E);
    						}
    					}
    				);
    			} else {
                    var copy_id = row.my.circ ? row.my.circ.target_copy() : null;
    				if (typeof copy_id == 'object') {
    					if (copy_id != null) {
    						copy_id = copy_id.id();
    					} else {
    						if (typeof row.my.acp == 'object' && row.my.acp != null) copy_id = row.my.acp.id();
    					}
    				} else {
    						if (typeof row.my.acp == 'object' && row.my.acp != null) copy_id = row.my.acp.id();
    				}
 
    				params.row_node.setAttribute( 'retrieve_id', js2JSON({'copy_id':row.my.acp.id(),'circ_id':row.my.circ.id(),'barcode':row.my.acp.barcode(),'doc_id': (row.my.record ? row.my.record.id() : null) }) );
    				if (typeof params.on_retrieve == 'function') {
    					params.on_retrieve(row);
    				}
    			}
    
    			return row;
            } catch(E) {
                obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.items.retrieve_row.error_in_retrieve_row'),E);
                return params.row;
            }
		}

		JSAN.use('util.list'); obj.list = new util.list('items_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_columns' : circ.util.std_map_row_to_columns(),
				'retrieve_row' : retrieve_row,
				'on_select' : function(ev) {
					JSAN.use('util.functional');
					var sel = obj.list.retrieve_selection();
					obj.controller.view.sel_clip.setAttribute('disabled',sel.length < 1);
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
				}
			}
		);
		
		obj.list2 = new util.list('items_list2');
		obj.list2.init(
			{
				'columns' : columns2,
				'map_row_to_columns' : circ.util.std_map_row_to_columns(),
				'retrieve_row' : retrieve_row,
				'on_select' : function(ev) {
					JSAN.use('util.functional');
					var sel = obj.list2.retrieve_selection();
					obj.controller.view.sel_clip2.setAttribute('disabled',sel.length < 1);
					var list = util.functional.map_list(
						sel,
						function(o) { return JSON2js( o.getAttribute('retrieve_id') ); }
					);
					if (typeof obj.on_select2 == 'function') {
						obj.on_select2(list);
					}
				}
			}
		);
	},

	'refresh' : function(circ_id,move_to_bottom_list) {
		var obj = this;
		try {
			var nparams = obj.list_circ_map[circ_id];
            if (move_to_bottom_list) { 
                obj.list_circ_map[circ_id].my_node.setAttribute('hidden','true');
				var nparams2 = obj.list2.append( { 'row' : { 'my' : { 'circ_id' : circ_id } },  'to_bottom' : true, 'which_list' : 1 } );
				obj.list_circ_map[circ_id] = nparams2; 
            } else {
    			var which_list = nparams.which_list;
                switch(which_list) {
                    case 1:
					case '1':
                        setTimeout(function(){try{obj.list2.refresh_row(nparams);}catch(E){
													obj.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.items.refresh.error_refreshing_row2', [circ_id, nparams]),E);}},1000);
                        break;
                    default:
                        setTimeout(function(){try{obj.list.refresh_row(nparams);}catch(E){
													obj.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.items.refresh.error_refreshing_row2', [circ_id, nparams]),E);}},1000);
                        break;
                }
            }
		} catch(E) {
			obj.error.standard_unexpected_error_alert($("patronStrings").getFormattedString('staff.patron.items.refresh.error_refreshing_row', [circ_id, nparams]),E);
		}
	},

	'retrieve' : function(dont_show_me_the_list_change) {
		var obj = this;
		if (window.xulG && window.xulG.checkouts) {
			obj.checkouts = window.xulG.checkouts;
		} else {
			obj.checkouts = [];
			obj.checkouts2 = [];
			var robj = obj.network.simple_request(
				'FM_CIRC_RETRIEVE_VIA_USER.authoritative',
				[ ses(), obj.patron_id ]
			);
			if (typeof robj.ilsevent!='undefined') {
				obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.items.retrieve.err_retrieving_circulations'),E);
			} else {
				obj.checkouts = obj.checkouts.concat( robj.overdue );
				obj.checkouts = obj.checkouts.concat( robj.out );
				obj.checkouts2 = obj.checkouts2.concat( robj.lost );
				obj.checkouts2 = obj.checkouts2.concat( robj.claims_returned );
				obj.checkouts2 = obj.checkouts2.concat( robj.long_overdue );
			}
			var robj = obj.network.simple_request(
				'FM_CIRC_IN_WITH_FINES_VIA_USER.authoritative',
				[ ses(), obj.patron_id ]
			);
			if (typeof robj.ilsevent!='undefined') {
				obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.items.retrieve.err_retrieving_circulations'),E);
			} else {
				obj.checkouts2 = obj.checkouts2.concat( robj.lost );
				obj.checkouts2 = obj.checkouts2.concat( robj.claims_returned );
				obj.checkouts2 = obj.checkouts2.concat( robj.long_overdue );
			}
		}

		function gen_list_append(circ_id,which_list) {
			return function() {
				try {
					var nparams;
					switch(which_list) {
						case 1:
							nparams = obj.list2.append( { 'row' : { 'my' : { 'circ_id' : circ_id } },  'to_bottom' : true, 'which_list' : which_list } );
						break;
						default:
							nparams = obj.list.append( { 'row' : { 'my' : { 'circ_id' : circ_id } }, 'to_bottom' : true, 'which_list' : which_list } );
						break;
					}
					if (nparams) {
						obj.list_circ_map[circ_id] = nparams; // unlike item status interface, each circ should be in this list only once
					} else {
						throw('typeof nparams = ' + typeof nparams);
					}
				} catch(E) {
					obj.error.standard_unexpected_error_alert($("patronStrings").getString('staff.patron.items.gen_list_append.error'),E);
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
		obj.controller.view.sel_copy_details.setAttribute('disabled','false');
		obj.controller.view.sel_bucket.setAttribute('disabled','false');
		obj.controller.view.sel_patron.setAttribute('disabled','false');
		obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','false');
		obj.controller.view.sel_mark_items_missing.setAttribute('disabled','false');

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
		obj.controller.view.sel_copy_details2.setAttribute('disabled','false');
		obj.controller.view.sel_bucket2.setAttribute('disabled','false');
		obj.controller.view.sel_patron2.setAttribute('disabled','false');
		obj.controller.view.sel_mark_items_damaged2.setAttribute('disabled','false');
		obj.controller.view.sel_mark_items_missing2.setAttribute('disabled','false');

		this.retrieve_ids2 = list;
	}

}

dump('exiting patron.items.js\n');
