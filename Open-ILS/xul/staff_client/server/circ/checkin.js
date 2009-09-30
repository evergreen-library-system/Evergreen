dump('entering circ.checkin.js\n');

if (typeof circ == 'undefined') circ = {};
circ.checkin = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('util.barcode');
	JSAN.use('util.date');
	this.OpenILS = {}; JSAN.use('OpenILS.data'); this.OpenILS.data = new OpenILS.data(); this.OpenILS.data.init({'via':'stash'});
	this.data = this.OpenILS.data;
}

circ.checkin.prototype = {

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
				'route_to' : { 'hidden' : false },
				'alert_message' : { 'hidden' : false },
				'checkin_time' : { 'hidden' : false }
			},
			{
				'except_these' : [ 'uses', 'checkin_time_full' ]
			}
		);

		JSAN.use('util.list'); obj.list = new util.list('checkin_list');
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
						obj.error.sdump('D_TRACE', 'circ/copy_status: selection list = ' + js2JSON(obj.selection_list) );
						if (obj.selection_list.length == 0) {
							obj.controller.view.sel_edit.setAttribute('disabled','true');
							obj.controller.view.sel_backdate.setAttribute('disabled','true');
							obj.controller.view.sel_opac.setAttribute('disabled','true');
							obj.controller.view.sel_patron.setAttribute('disabled','true');
							obj.controller.view.sel_last_patron.setAttribute('disabled','true');
							obj.controller.view.sel_copy_details.setAttribute('disabled','true');
							obj.controller.view.sel_bucket.setAttribute('disabled','true');
							obj.controller.view.sel_spine.setAttribute('disabled','true');
							obj.controller.view.sel_transit_abort.setAttribute('disabled','true');
							obj.controller.view.sel_clip.setAttribute('disabled','true');
							obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','true');
						} else {
							obj.controller.view.sel_edit.setAttribute('disabled','false');
							obj.controller.view.sel_backdate.setAttribute('disabled','false');
							obj.controller.view.sel_opac.setAttribute('disabled','false');
							obj.controller.view.sel_patron.setAttribute('disabled','false');
							obj.controller.view.sel_last_patron.setAttribute('disabled','false');
							obj.controller.view.sel_copy_details.setAttribute('disabled','false');
							obj.controller.view.sel_bucket.setAttribute('disabled','false');
							obj.controller.view.sel_spine.setAttribute('disabled','false');
							obj.controller.view.sel_transit_abort.setAttribute('disabled','false');
							obj.controller.view.sel_clip.setAttribute('disabled','false');
							obj.controller.view.sel_mark_items_damaged.setAttribute('disabled','false');
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
					'save_columns' : [ [ 'command' ], function() { obj.list.save_columns(); } ],
					'sel_clip' : [
						['command'],
						function() { 
                            obj.list.clipboard(); 
                            obj.controller.view.checkin_barcode_entry_textbox.focus();
                        }
					],
					'sel_edit' : [
						['command'],
						function() {
							try {
								obj.spawn_copy_editor();
							} catch(E) {
								alert(E);
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
							JSAN.use('circ.util');
							circ.util.abort_transits(obj.selection_list);
						}
					],
					'sel_patron' : [
						['command'],
						function() {
							JSAN.use('circ.util');
							circ.util.show_last_few_circs(obj.selection_list);
						}
					],
					'sel_last_patron' : [
						['command'],
						function() {
							var patrons = {};
							for (var i = 0; i < obj.selection_list.length; i++) {
								var circs = obj.network.simple_request('FM_CIRC_RETRIEVE_VIA_COPY',[ses(),obj.selection_list[i].copy_id,1]);
								if (circs.length > 0) {
									patrons[circs[0].usr()] = 1;
								} else {
									alert(document.getElementById('circStrings').getFormattedString('staff.circ.item_no_circs', [obj.selection_list[i].barcode]));
								}
							}
							for (var i in patrons) {
								xulG.new_patron_tab({},{'id' : i});
							}
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
					'sel_backdate' : [
						['command'],
						function() {
							JSAN.use('circ.util');
							for (var i = 0; i < obj.selection_list.length; i++) {
                                var circ_id = obj.selection_list[i].circ_id; 
                                var copy_id = obj.selection_list[i].copy_id; 
                                if (!circ_id) {
                                    var blob = obj.network.simple_request('FM_ACP_DETAILS',[ses(),copy_id]);
                                    if (blob.circ) circ_id = blob.circ.id();
                                }
                                if (!circ_id) continue;
								circ.util.backdate_post_checkin( circ_id );
							}
						}
					],
					'sel_mark_items_damaged' : [
						['command'],
						function() {
							var funcs = [];
							JSAN.use('cat.util'); JSAN.use('util.functional');
							cat.util.mark_item_damaged( util.functional.map_list( obj.selection_list, function(o) { return o.copy_id; } ) );
						}
					],
					'sel_bucket' : [
						['command'],
						function() {
							JSAN.use('cat.util');
							cat.util.add_copies_to_bucket(obj.selection_list);
						}
					],
					'checkin_barcode_entry_textbox' : [
						['keypress'],
						function(ev) {
							if (ev.keyCode && ev.keyCode == 13) {
								obj.checkin();
							}
						}
					],
					'checkin_effective_date_label' : [
						['render'],
						function(e) {
							return function() {
								obj.controller.view.checkin_effective_datepicker.value =
									util.date.formatted_date(new Date(),'%F');
							};
						}
					],
					'checkin_effective_datepicker' : [
						['change'],
						function(ev) {
							if (ev.target.nodeName == 'datepicker') {
								try {
									if ( ev.target.dateValue > new Date() ) throw(document.getElementById('circStrings').getString('staff.circ.future_date'));
									var x = document.getElementById('background');
									if (x) {
										if ( ev.target.value == util.date.formatted_date(new Date(),'%F') ) {
											x.setAttribute('style','background-color: green');
											document.getElementById('background-text').setAttribute('value',document.getElementById('circStrings').getString('staff.circ.process_item'));
										} else {
											x.setAttribute('style','background-color: red');
											document.getElementById('background-text').setAttribute('value',document.getElementById('circStrings').getFormattedString('staff.circ.backdated_checkin', [ev.target.value]));
										}
									}

								} catch(E) {
									var x = document.getElementById('background');
									if (x) {
                                        x.setAttribute('style','background-color: green');
                                        document.getElementById('background-text').setAttribute('value',document.getElementById('circStrings').getString('staff.circ.process_item'));
                                    }
									dump('checkin:effective_date: ' + E + '\n');
                                    ev.target.disabled = true;
									//alert(document.getElementById('circStrings').getFormattedString('staff.circ.backdate.exception', [E]));
                                    ev.target.value = util.date.formatted_date(new Date(),'%F');
                                    ev.target.disabled = false;
			                        JSAN.use('util.sound'); var sound = new util.sound(); sound.bad();
                                    
								}
							}
						}
					],
					'cmd_broken' : [
						['command'],
						function() { alert(document.getElementById('circStrings').getString('staff.circ.unimplemented')); }
					],
					'cmd_checkin_submit_barcode' : [
						['command'],
						function() {
							obj.checkin();
						}
					],
					'cmd_checkin_print' : [
						['command'],
						function() {
							var p = { 
								'template' : 'checkin'
							};
							obj.list.print(p);
						}
					],
					'cmd_csv_to_clipboard' : [ ['command'], function() { 
                        obj.list.dump_csv_to_clipboard(); 
                        obj.controller.view.checkin_barcode_entry_textbox.focus();
                    } ],
					'cmd_csv_to_printer' : [ ['command'], function() { 
                        obj.list.dump_csv_to_printer(); 
                        obj.controller.view.checkin_barcode_entry_textbox.focus();
                    } ],
					'cmd_csv_to_file' : [ ['command'], function() { 
                        obj.list.dump_csv_to_file( { 'defaultFileName' : 'checked_in.txt' } ); 
                        obj.controller.view.checkin_barcode_entry_textbox.focus();
                    } ]
				}
			}
		);
		this.controller.render();
		this.controller.view.checkin_barcode_entry_textbox.focus();

	},

	'test_barcode' : function(bc) {
		var obj = this;
		var x = document.getElementById('strict_barcode');
		if (x && x.checked != true) return true;
		var good = util.barcode.check(bc);
		if (good) {
			return true;
		} else {
			if ( 1 == obj.error.yns_alert(
						document.getElementById('circStrings').getFormattedString('staff.circ.check_digit.bad', [bc]),
						document.getElementById('circStrings').getString('staff.circ.barcode.bad'),
						document.getElementById('circStrings').getString('staff.circ.cancel'),
						document.getElementById('circStrings').getString('staff.circ.barcode.accept'),
						null,
						document.getElementById('circStrings').getString('staff.circ.confirm'),
						'/xul/server/skin/media/images/bad_barcode.png'
			) ) {
				return true;
			} else {
				return false;
			}
		}
	},

	'checkin' : function() {
		var obj = this;
		try {
			var barcode = obj.controller.view.checkin_barcode_entry_textbox.value;
			if (!barcode) return;
			if (barcode) {
				if ( obj.test_barcode(barcode) ) { /* good */ } else { /* bad */ return; }
			}
			var backdate = obj.controller.view.checkin_effective_datepicker.value;
			var auto_print = document.getElementById('checkin_auto');
			if (auto_print) auto_print = auto_print.getAttribute('checked') == 'true';
			JSAN.use('circ.util');
			circ.util.checkin_via_barcode(
				ses(), 
                { 
                    'barcode' : barcode,
 					'disable_textbox' : function() { 
						obj.controller.view.checkin_barcode_entry_textbox.disabled = true; 
						obj.controller.view.cmd_checkin_submit_barcode.setAttribute('disabled', 'true'); 
					},
					'enable_textbox' : function() { 
						obj.controller.view.checkin_barcode_entry_textbox.disabled = false; 
						obj.controller.view.cmd_checkin_submit_barcode.setAttribute('disabled', 'false'); 
					},
					'checkin_result' : function(checkin) {
						obj.controller.view.checkin_barcode_entry_textbox.disabled = false;
						obj.controller.view.cmd_checkin_submit_barcode.setAttribute('disabled', 'false'); 
						obj.checkin2(checkin,backdate);
					}
                }, 
                backdate, 
                auto_print
			);
		} catch(E) {
			obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getFormattedString('staff.circ.checkin.exception', [E]));
			if (typeof obj.on_failure == 'function') {
				obj.on_failure(E);
			}
			if (typeof window.xulG == 'object' && typeof window.xulG.on_failure == 'function') {
				obj.error.sdump('D_CIRC', document.getElementById('circStrings').getString('staff.circ.util.checkin.exception.external') + '\n');
				window.xulG.on_failure(E);
			} else {
				obj.error.sdump('D_CIRC', document.getElementById('circStrings').getString('staff.circ.util.checkin.exception.no_external') + '\n');
			}
		}

	},

	'checkin2' : function(checkin,backdate) {
		var obj = this;
		try {
			if (!checkin) return obj.on_failure(); /* circ.util.checkin handles errors and returns null currently */
			if (checkin.ilsevent == 7010 /* COPY_ALERT_MESSAGE */
				|| checkin.ilsevent == 1203 /* COPY_BAD_STATUS */
				|| checkin.ilsevent == -1 /* offline */
				|| checkin.ilsevent == 1502 /* ASSET_COPY_NOT_FOUND */
				|| checkin.ilsevent == 1203 /* COPY_BAD_STATUS */
				|| checkin.ilsevent == 7009 /* CIRC_CLAIMS_RETURNED */ 
				|| checkin.ilsevent == 7011 /* COPY_STATUS_LOST */ 
				|| checkin.ilsevent == 7012 /* COPY_STATUS_MISSING */) return obj.on_failure();
			var retrieve_id = js2JSON( { 'circ_id' : checkin.circ ? checkin.circ.id() : null , 'copy_id' : checkin.copy.id(), 'barcode' : checkin.copy.barcode(), 'doc_id' : (typeof checkin.record != 'undefined' ? ( typeof checkin.record.ilsevent == 'undefined' ? checkin.record.doc_id() : null ) : null ) } );
			if (checkin.circ && checkin.circ.checkin_time() == 'now') checkin.circ.checkin_time(backdate);
			if (document.getElementById('trim_list')) {
				var x = document.getElementById('trim_list');
				if (x.checked) { obj.list.trim_list = 20; } else { obj.list.trim_list = null; }
			}
			obj.list.append(
				{
					'retrieve_id' : retrieve_id,
					'row' : {
						'my' : {
							'circ' : checkin.circ,
							'mvr' : checkin.record,
							'acp' : checkin.copy,
							'status' : checkin.status,
							'route_to' : checkin.route_to,
							'message' : checkin.message
						}
					},
					'to_top' : true
				//I could override map_row_to_column here
				}
			);
			obj.list.node.view.selection.select(0);

			JSAN.use('util.sound'); var sound = new util.sound(); sound.circ_good();

			if (typeof obj.on_checkin == 'function') {
				obj.on_checkin(checkin);
			}
			if (typeof window.xulG == 'object' && typeof window.xulG.on_checkin == 'function') {
				obj.error.sdump('D_CIRC', document.getElementById('circStrings').getString('staff.circ.checkin.exception.external') + '\n');
				window.xulG.on_checkin(checkin);
			} else {
				obj.error.sdump('D_CIRC', document.getElementById('circStrings').getString('staff.circ.checkin.exception.no_external') + '\n');
			}

			return true;

		} catch(E) {
			obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getFormattedString('staff.circ.checkin2.exception', [E]));
			if (typeof obj.on_failure == 'function') {
				obj.on_failure(E);
			}
			if (typeof window.xulG == 'object' && typeof window.xulG.on_failure == 'function') {
				obj.error.sdump('D_CIRC', document.getElementById('circStrings').getString('staff.circ.checkin2.exception.external') + '\n');
				window.xulG.on_failure(E);
			} else {
				obj.error.sdump('D_CIRC', document.getElementById('circStrings').getString('staff.circ.checkin2.exception.no_external') + '\n');
			}
		}

	},

	'on_checkin' : function() {
		this.controller.view.checkin_barcode_entry_textbox.disabled = false;
		this.controller.view.checkin_barcode_entry_textbox.select();
		this.controller.view.checkin_barcode_entry_textbox.value = '';
		this.controller.view.checkin_barcode_entry_textbox.focus();
	},

	'on_failure' : function() {
		this.controller.view.checkin_barcode_entry_textbox.disabled = false;
		this.controller.view.checkin_barcode_entry_textbox.select();
		this.controller.view.checkin_barcode_entry_textbox.focus();
	},
	
	'spawn_copy_editor' : function() {

		var obj = this;

		JSAN.use('util.functional');

		var list = obj.selection_list;

		list = util.functional.map_list(
			list,
			function (o) {
				return o.copy_id;
			}
		);

		JSAN.use('cat.util'); cat.util.spawn_copy_editor( { 'copy_ids' : list, 'edit' : 1 } );

	}

}

dump('exiting circ.checkin.js\n');
