dump('entering circ.in_house_use.js\n');
// vim:noet:sw=4:ts=4:

if (typeof circ == 'undefined') circ = {};
circ.in_house_use = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('util.barcode');
	JSAN.use('util.date');
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
	JSAN.use('util.sound'); this.sound = new util.sound();
}

circ.in_house_use.prototype = {

	'init' : function( params ) {

		var obj = this;

		obj.entry_cap = Number( obj.data.hash.aous['ui.circ.in_house_use.entry_cap'] ) || 99;
		obj.entry_warn = Number( obj.data.hash.aous['ui.circ.in_house_use.entry_warn'] ) || 20;

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'barcode' : { 'hidden' : false },
				'title' : { 'hidden' : false },
				'status' : { 'hidden' : false },
				'location' : { 'hidden' : false },
				'call_number' : { 'hidden' : false },
				'uses' : { 'hidden' : false }
			} 
		);

		JSAN.use('util.list'); obj.list = new util.list('in_house_use_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_columns' : circ.util.std_map_row_to_columns(),
				'on_select' : function() {
					var sel = obj.list.retrieve_selection();
					obj.controller.view.sel_clip.setAttribute('disabled', sel.length < 1);
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
							obj.controller.view.in_house_use_barcode_entry_textbox.focus();
						}
					],
					'in_house_use_menu_placeholder' : [
						['render'],
						function(e) {
							return function() {
								JSAN.use('util.widgets'); JSAN.use('util.functional'); JSAN.use('util.fm_utils');
								var items = [ [ document.getElementById('circStrings').getString('staff.circ.in_house_use.barcode') , 'barcode' ] ].concat(
									util.functional.map_list(
										util.functional.filter_list(
											obj.data.list.my_cnct,
											function(o) {
												return util.fm_utils.compare_aou_a_is_b_or_ancestor(o.owning_lib(), obj.data.list.au[0].ws_ou());
											}
										).sort(

											function(a,b) {
												try { 
													return util.fm_utils.sort_func_aou_by_depth_and_then_string(
														[ a.owning_lib(), a.name() ],
														[ b.owning_lib(), b.name() ]
													);
												} catch(E) {
													alert(document.getElementById('circStrings').getString('staff.circ.in_house_use.noncat_sort_error') + ' ' + E);
													return 0;
												}
											}

										),
										function(o) {
											return [ obj.data.hash.aou[ o.owning_lib() ].shortname() + ' : ' + o.name(), o.id() ];
										}
									)
								);
								g.error.sdump('D_TRACE', document.getElementById('circStrings').getString('staff.circ.in_house_use.items_dump') + js2JSON(items));
								util.widgets.remove_children( e );
								var ml = util.widgets.make_menulist(
									items
								);
								e.appendChild( ml );
								ml.setAttribute('id','in_house_use_menulist');
								ml.setAttribute('accesskey','');
								ml.addEventListener(
									'command',
									function(ev) {
										var tb = obj.controller.view.in_house_use_barcode_entry_textbox;
										if (ev.target.value == 'barcode') {
											tb.disabled = false;
											tb.value = '';
											tb.focus();
										} else {
											tb.disabled = true;
											tb.value = document.getElementById('circStrings').getString('staff.circ.in_house_use.noncataloged');
										}
									}, false
								);
								obj.controller.view.in_house_use_menu = ml;
							};
						},
					],
					'in_house_use_barcode_entry_textbox' : [
						['keypress'],
						function(ev) {
							if (ev.keyCode && ev.keyCode == 13) {
								obj.in_house_use();
							}
						}
					],
					'in_house_use_multiplier_label' : [
						['render'],
						function(e) {
							return function() {
								obj.controller.view.in_house_use_multiplier_textbox.select();
								obj.controller.view.in_house_use_multiplier_textbox.value = 1;
							};
						}
					],
					'in_house_use_multiplier_textbox' : [
						['change'],
						function(ev) {
							if (ev.target.nodeName == 'textbox') {
								try {
									var value = Number(ev.target.value);
									if (value > 0) {
										if (value > 99) { throw(value); }
									} else {
										throw(value);
									}
								} catch(E) {
									dump('in_house_use:multiplier: ' + E + '\n');
									obj.sound.circ_bad();
									setTimeout(
										function() {
											obj.controller.view.in_house_use_multiplier_textbox.focus();
											obj.controller.view.in_house_use_multiplier_textbox.select();
										}, 0
									);
								}
							}
						}
					],
					'cmd_broken' : [
						['command'],
						function() { alert(document.getElementById('circStrings').getString('staff.circ.unimplemented')); }
					],
					'cmd_in_house_use_submit_barcode' : [
						['command'],
						function() {
							obj.in_house_use();
						}
					],
					'cmd_in_house_use_print' : [
						['command'],
						function() {
							var p = { 
								'template' : 'in_house_use'
							};
							obj.list.print(p);
						}
					],
					'cmd_csv_to_clipboard' : [ ['command'], function() { 
                        obj.list.dump_csv_to_clipboard(); 
                        obj.controller.view.in_house_use_barcode_entry_textbox.focus();
                    } ],
					'cmd_csv_to_printer' : [ ['command'], function() { 
                        obj.list.dump_csv_to_printer(); 
                        obj.controller.view.in_house_use_barcode_entry_textbox.focus();
                    } ],
					'cmd_csv_to_file' : [ ['command'], function() { 
                        obj.list.dump_csv_to_file( { 'defaultFileName' : 'checked_in.txt' } ); 
                        obj.controller.view.in_house_use_barcode_entry_textbox.focus();
                    } ]

				}
			}
		);
		this.controller.render();
		this.controller.view.in_house_use_barcode_entry_textbox.focus();

	},

	'test_barcode' : function(bc) {
		var obj = this;
		var good = util.barcode.check(bc);
		var x = document.getElementById('strict_barcode');
		if (x && x.checked != true) return true;
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

	'in_house_use' : function() {
		var obj = this;
		try {
			var barcode;
			if (obj.controller.view.in_house_use_menu.value == '' || obj.controller.view.in_house_use_menu.value == 'barcode') {
				barcode = obj.controller.view.in_house_use_barcode_entry_textbox.value;
				if (barcode) {
					if ( obj.test_barcode(barcode) ) { /* good */ } else { /* bad */ return; }
				}
			} else {
				barcode = ( obj.controller.view.in_house_use_menu.value );
				//barcode = obj.data.hash.cnct[ obj.controller.view.in_house_use_menu.value ].name()
			}
			var multiplier = Number( obj.controller.view.in_house_use_multiplier_textbox.value );

			if (barcode == '') {
				obj.controller.view.in_house_use_barcode_entry_textbox.focus();
				return; 
			}

			if (multiplier == 0 || multiplier > obj.entry_cap) {
				obj.controller.view.in_house_use_multiplier_textbox.focus();
				obj.controller.view.in_house_use_multiplier_textbox.select();
				return;
			}

			if (multiplier > obj.entry_warn) {
				var r = obj.error.yns_alert(
					document.getElementById('circStrings').getFormattedString('staff.circ.in_house_use.confirm_multiple', [barcode, multiplier]),
					document.getElementById('circStrings').getString('staff.circ.in_house_use.confirm_multiple.title'),
					document.getElementById('circStrings').getString('staff.circ.in_house_use.yes'),
					document.getElementById('circStrings').getString('staff.circ.in_house_use.no'),
					null,
					document.getElementById('circStrings').getString('staff.circ.confirm.msg')
				);
				if (r != 0) {
					obj.controller.view.in_house_use_multiplier_textbox.focus();
					obj.controller.view.in_house_use_multiplier_textbox.select();
					return;
				}
			}

			JSAN.use('circ.util');

			if (obj.controller.view.in_house_use_menu.value == 'barcode') {

				var copy = obj.network.simple_request('FM_ACP_RETRIEVE_VIA_BARCODE',[ barcode ]); 
				if (copy.ilsevent) { 
					switch(Number(copy.ilsevent)) {
						case -1 : 
							obj.error.standard_network_error_alert(document.getElementById('circStrings').getString('staff.circ.in_house_use.failed.verbose'));
							break;
						case 1502 /* ASSET_COPY_NOT_FOUND */ : 
							obj.error.yns_alert(
								copy.textcode,
								document.getElementById('circStrings').getString('staff.circ.in_house_use.failed'),
								document.getElementById('circStrings').getString('staff.circ.in_house_use.ok'),
								null,
								null,
								document.getElementById('circStrings').getString('staff.circ.confirm.msg')
							);
							break;
						default:
							throw(copy);
					}
					return; 
				}
	
				var mods = obj.network.simple_request('MODS_SLIM_RECORD_RETRIEVE_VIA_COPY.authoritative',[ copy.id() ]);
				var result = obj.network.simple_request('FM_AIHU_CREATE',
					[ ses(), { 'copyid' : copy.id(), 'location' : obj.data.list.au[0].ws_ou(), 'count' : multiplier } ]
				);

			} else {
				var result = obj.network.simple_request('FM_ANCIHU_CREATE',
					[ ses(), { 'non_cat_type' : obj.controller.view.in_house_use_menu.value, 'location' : obj.data.list.au[0].ws_ou(), 'count' : multiplier } ]
				);
				mods = new mvr(); mods.title( obj.data.hash.cnct[ obj.controller.view.in_house_use_menu.value ].name()); 
				copy = new acp(); copy.barcode( '' );
			}

			if (document.getElementById('trim_list')) {
				var x = document.getElementById('trim_list');
				if (x.checked) { obj.list.trim_list = 20; } else { obj.list.trim_list = null; }
			}
			obj.list.append(
				{
					'row' : {
						'my' : {
							'mvr' : mods,
							'acp' : copy,
							'uses' : result.length
						}
					},
					'to_top' : true
				//I could override map_row_to_column here
				}
			);
			obj.sound.circ_good();

			if (typeof obj.on_in_house_use == 'function') {
				obj.on_in_house_use(result);
			}
			if (typeof window.xulG == 'object' && typeof window.xulG.on_in_house_use == 'function') {
				obj.error.sdump('D_CIRC', + document.getElementById('circStrings').getString('staff.circ.in_house_use.external') + '\n');
				window.xulG.on_in_house_use(result);
			} else {
				obj.error.sdump('D_CIRC', + document.getElementById('circStrings').getString('staff.circ.in_house_use.no_external') + '\n');
			}

		} catch(E) {
			obj.error.standard_unexpected_error_alert(document.getElementById('circStrings').getString('staff.circ.in_house_use.failed'), E);
			if (typeof obj.on_failure == 'function') {
				obj.on_failure(E);
			}
			if (typeof window.xulG == 'object' && typeof window.xulG.on_failure == 'function') {
				obj.error.sdump('D_CIRC', + document.getElementById('circStrings').getString('staff.circ.in_house_use.on_failure.external') + '\n');
				window.xulG.on_failure(E);
			} else {
				obj.error.sdump('D_CIRC', + document.getElementById('circStrings').getString('staff.circ.in_house_use.on_failure.external') + '\n');
			}
		}

	},

	'on_in_house_use' : function() {
		this.controller.view.in_house_use_multiplier_textbox.select();
		this.controller.view.in_house_use_multiplier_textbox.value = '1';
		this.controller.view.in_house_use_barcode_entry_textbox.value = '';
		this.controller.view.in_house_use_barcode_entry_textbox.focus();
	},

	'on_failure' : function() {
		this.controller.view.in_house_use_barcode_entry_textbox.select();
		this.controller.view.in_house_use_barcode_entry_textbox.focus();
	}
}

dump('exiting circ.in_house_use.js\n');
