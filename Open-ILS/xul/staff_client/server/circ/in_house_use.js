dump('entering circ.in_house_use.js\n');

if (typeof circ == 'undefined') circ = {};
circ.in_house_use = function (params) {

	JSAN.use('util.error'); this.error = new util.error();
	JSAN.use('util.network'); this.network = new util.network();
	JSAN.use('util.barcode');
	JSAN.use('util.date');
	JSAN.use('OpenILS.data'); this.data = new OpenILS.data(); this.data.init({'via':'stash'});
}

circ.in_house_use.prototype = {

	'init' : function( params ) {

		var obj = this;

		JSAN.use('circ.util');
		var columns = circ.util.columns( 
			{ 
				'barcode' : { 'hidden' : false },
				'title' : { 'hidden' : false },
				'status' : { 'hidden' : false },
				'location' : { 'hidden' : false },
				'call_number' : { 'hidden' : false },
				'uses' : { 'hidden' : false },
			} 
		);

		JSAN.use('util.list'); obj.list = new util.list('in_house_use_list');
		obj.list.init(
			{
				'columns' : columns,
				'map_row_to_columns' : circ.util.std_map_row_to_columns(),
				'on_select' : function() {
					var sel = obj.list.retrieve_selection();
					document.getElementById('clip_button').disabled = sel.length < 1;
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
						function() { obj.list.clipboard(); }
					],
					'in_house_use_menu_placeholder' : [
						['render'],
						function(e) {
							return function() {
								JSAN.use('util.widgets'); JSAN.use('util.functional'); JSAN.use('util.fm_utils');
								var items = [ [ 'Barcode:' , 'barcode' ] ].concat(
									util.functional.map_list(
										util.functional.filter_list(
											obj.data.list.cnct,
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
													alert('error in noncat sorting: ' + E);
													return 0;
												}
											}

										),
										function(o) {
											return [ obj.data.hash.aou[ o.owning_lib() ].shortname() + ' : ' + o.name(), o.id() ];
										}
									)
								);
								g.error.sdump('D_TRACE','items = ' + js2JSON(items));
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
											tb.value = 'Non-Cataloged';
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
										if (value > 99) ev.target.value = 99;
									} else {
										ev.target.value = 1;
									}
								} catch(E) {
									dump('in_house_use:multiplier: ' + E + '\n');
									ev.target.value = 1;
								}
							}
						}
					],
					'cmd_broken' : [
						['command'],
						function() { alert('Not Yet Implemented'); }
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
							obj.list.on_all_fleshed = function() {
								try {
									dump( js2JSON( obj.list.dump_with_keys() ) + '\n' );
									obj.data.stash_retrieve();
									var lib = obj.data.hash.aou[ obj.data.list.au[0].ws_ou() ];
									lib.children(null);
									var p = { 
										'lib' : lib,
										'staff' : obj.data.list.au[0],
										'header' : obj.data.print_list_templates.in_house_use.header,
										'line_item' : obj.data.print_list_templates.in_house_use.line_item,
										'footer' : obj.data.print_list_templates.in_house_use.footer,
										'type' : obj.data.print_list_templates.in_house_use.type,
										'list' : obj.list.dump_with_keys(),
									};
									JSAN.use('util.print'); var print = new util.print();
									print.tree_list( p );
									setTimeout(function(){obj.list.on_all_fleshed = null;},0);
								} catch(E) {
									alert(E); 
								}
							}
							obj.list.full_retrieve();
						}
					],
					'cmd_in_house_use_export' : [
						['command'],
						function() {
							obj.list.on_all_fleshed = function() {
								try {
									dump(obj.list.dump_csv() + '\n');
									copy_to_clipboard(obj.list.dump_csv());
									setTimeout(function(){obj.list.on_all_fleshed = null;},0);
								} catch(E) {
									alert(E); 
								}
							}
							obj.list.full_retrieve();
						}
					],

					'cmd_in_house_use_reprint' : [
						['command'],
						function() {
						}
					],
					'cmd_in_house_use_done' : [
						['command'],
						function() {
						}
					],
				}
			}
		);
		this.controller.render();
		this.controller.view.in_house_use_barcode_entry_textbox.focus();

	},

	'test_barcode' : function(bc) {
		var obj = this;
		var good = util.barcode.check(bc);
		if (good) {
			return true;
		} else {
			if ( 1 == obj.error.yns_alert(
						'Bad checkdigit; possible mis-scan.  Use this barcode ("' + bc + '") anyway?',
						'Bad Barcode',
						'Cancel',
						'Accept Barcode',
						null,
						'Check here to confirm this action',
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

			if (multiplier == 0 || multiplier > 99) {
				obj.controller.view.in_house_use_multiplier_textbox.focus();
				obj.controller.view.in_house_use_multiplier_textbox.select();
				return;
			}

			if (multiplier > 20) {
				var r = obj.error.yns_alert('Are you sure you want to mark ' + barcode + ' as having been used ' + multiplier + ' times?','In-House Use Verification', 'Yes', 'No', null, 'Check here to confirm this message.');
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
					switch(copy.ilsevent) {
						case -1 : obj.error.standard_network_error_alert('In House Use Failed.  If you wish to use the offline interface, in the top menubar select Circulation -> Offline Interface'); break;
						case 1502 /* ASSET_COPY_NOT_FOUND */ : obj.error.yns_alert(copy.textcode,'In House Use Failed','Ok',null,null,'Check here to confirm this message'); break;
						default: throw(copy);
					}
					return; 
				}
	
				var mods = obj.network.simple_request('MODS_SLIM_RECORD_RETRIEVE_VIA_COPY',[ copy.id() ]);
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
							'uses' : result.length,
						}
					},
					'to_top' : true,
				//I could override map_row_to_column here
				}
			);

			if (typeof obj.on_in_house_use == 'function') {
				obj.on_in_house_use(result);
			}
			if (typeof window.xulG == 'object' && typeof window.xulG.on_in_house_use == 'function') {
				obj.error.sdump('D_CIRC','circ.in_house_use: Calling external .on_in_house_use()\n');
				window.xulG.on_in_house_use(result);
			} else {
				obj.error.sdump('D_CIRC','circ.in_house_use: No external .on_in_house_use()\n');
			}

		} catch(E) {
			obj.error.standard_unexpected_error_alert('In House Use Failed',E);
			if (typeof obj.on_failure == 'function') {
				obj.on_failure(E);
			}
			if (typeof window.xulG == 'object' && typeof window.xulG.on_failure == 'function') {
				obj.error.sdump('D_CIRC','circ.in_house_use: Calling external .on_failure()\n');
				window.xulG.on_failure(E);
			} else {
				obj.error.sdump('D_CIRC','circ.in_house_use: No external .on_failure()\n');
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
