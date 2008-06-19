const g_max_copies_that_can_be_added_at_a_time_per_volume = 100;
var g = {};

function my_init() {
	try {

		/***********************************************************************************************************/
		/* Initial setup */

		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
				if (typeof JSAN == 'undefined') { throw( $("commonStrings").getString('common.jsan.missing') ); }
		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('/xul/server/');
		JSAN.use('util.error'); g.error = new util.error();
		g.error.sdump('D_TRACE','my_init() for cat/volume_copy_creator.xul');

		JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
		JSAN.use('util.widgets'); JSAN.use('util.functional');

		JSAN.use('util.network'); g.network = new util.network();

		/***********************************************************************************************************/
		/* What record am I dealing with?  Am I adding just copies or copies and volumes? */

		g.doc_id = xul_param('doc_id');
		document.getElementById('summary').setAttribute('src',urls.XUL_BIB_BRIEF); // + '?docid=' + window.escape(g.doc_id));
		get_contentWindow(document.getElementById('summary')).xulG = { 'docid' : g.doc_id };

		g.copy_shortcut = xul_param('copy_shortcut',{'JSON2js_if_cgi':true});
		g.error.sdump('D_ERROR','location.href = ' + location.href + '\n\ncopy_short cut = ' + g.copy_shortcut + '\n\nou_ids = ' + xul_param('ou_ids'));

		var ou_ids = xul_param('ou_ids',{'JSON2js_if_cgi' : true, 'concat' : true});;

		/***********************************************************************************************************/
		/* For the call number drop down */

		var cn_blob;
		try {
			cn_blob = g.network.simple_request('BLOB_MARC_CALLNUMBERS_RETRIEVE',[g.doc_id]);
		} catch(E) {
			cn_blob = [];
		}
		if ((!g.copy_shortcut)) {
			var hbox = document.getElementById('marc_cn');
			var ml = util.widgets.make_menulist(
				util.functional.map_list(
					cn_blob,
					function(o) {
						for (var i in o) {
							return [ o[i], i ];
						}
					}
				).sort(
					function(a,b) {
						a = a[1]; b = b[1];
						if (a == '082') return -1; 
						if (b == '082') return 1; 
						if (a == '092')  return -1; 
						if (b == '092')  return 1; 
						if (a < b) return -1; 
						if (a > b) return 1; 
						return 0;
					}
				)
			); hbox.appendChild(ml);
			ml.setAttribute('editable','true');
			ml.setAttribute('width', '200');
			var btn = document.createElement('button');
			btn.setAttribute('label',$('catStrings').getString('staff.cat.volume_copy_creator.my_init.btn.label'));
			btn.setAttribute('accesskey','A');
			btn.setAttribute('image','/xul/server/skin/media/images/down_arrow.gif');
			hbox.appendChild(btn);
			btn.addEventListener(
				'command',
				function() {
					var nl = document.getElementsByTagName('textbox');
					for (var i = 0; i < nl.length; i++) {
						if (nl[i].getAttribute('rel_vert_pos')==2 
							&& !nl[i].disabled) nl[i].value = ml.value;
					}
					if (g.last_focus) setTimeout( function() { g.last_focus.focus(); }, 0 );
				}, 
				false
			);
		}

		/***********************************************************************************************************/
		/* render the orgs and volumes/input */

		var rows = document.getElementById('rows');

		var node_id = 0;
		for (var i = 0; i < ou_ids.length; i++) {
			try {
				var org = g.data.hash.aou[ ou_ids[i] ];
				if ( get_bool( g.data.hash.aout[ org.ou_type() ].can_have_vols() ) ) {
					var row = document.createElement('row'); rows.appendChild(row); row.setAttribute('ou_id',ou_ids[i]);
					g.render_library_label(row,ou_ids[i]);
					g.render_volume_count_entry(row,ou_ids[i]);
				}
			} catch(E) {
				g.error.sdump('D_ERROR',E);
			}
		}

		g.load_prefs();

	} catch(E) {
		var err_msg = $("commonStrings").getFormattedString('common.exception', ['cat/volume_copy_creator.js', E]);
		try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); dump(js2JSON(E)); }
		alert(err_msg);
	}
}

g.render_library_label = function(row,ou_id) {
	var label = document.createElement('label'); row.appendChild(label);
	label.setAttribute('ou_id',ou_id);
	label.setAttribute('value',g.data.hash.aou[ ou_id ].shortname());
}

g.render_volume_count_entry = function(row,ou_id) {
	var hb = document.createElement('vbox'); row.appendChild(hb);
	var tb = document.createElement('textbox'); hb.appendChild(tb);
	tb.setAttribute('ou_id',ou_id); tb.setAttribute('size','3'); tb.setAttribute('cols','3');
	tb.setAttribute('rel_vert_pos','1'); 
	if ( (!g.copy_shortcut) && (!g.last_focus) ) { tb.focus(); g.last_focus = tb; }
	var node;
	function render_copy_count_entry(ev) {
		if (ev.target.disabled) return;
		if (! isNaN( Number( ev.target.value) ) ) {
			if ( Number( ev.target.value ) > g_max_copies_that_can_be_added_at_a_time_per_volume ) {
				g.error.yns_alert($("catStrings").getFormattedString('staff.cat.volume_copy_creator.render_volume_count_entry.message', [g_max_copies_that_can_be_added_at_a_time_per_volume]),
					$("catStrings").getString('staff.cat.volume_copy_creator.render_volume_count_entry.title'),
					$("catStrings").getString('staff.cat.volume_copy_creator.render_volume_count_entry.ok_label'),null,null,'');
				return;
			}
			if (node) { row.removeChild(node); node = null; }
			//ev.target.disabled = true;
			node = g.render_callnumber_copy_count_entry(row,ou_id,ev.target.value);
		}
	}
	util.widgets.apply_vertical_tab_on_enter_handler( 
		tb, 
		function() { render_copy_count_entry({'target':tb}); setTimeout(function(){util.widgets.vertical_tab(tb);},0); }
	);
	tb.addEventListener( 'change', render_copy_count_entry, false);
	tb.addEventListener( 'focus', function(ev) { g.last_focus = ev.target; }, false );
	setTimeout(
		function() {
			try {
			if (g.copy_shortcut) {
				JSAN.use('util.functional');
				tb.value = util.functional.map_object_to_list(
					g.copy_shortcut[ou_id],
					function(o,i) {
						return g.copy_shortcut[ou_id][i];
					}
				).length
				render_copy_count_entry({'target':tb});
				tb.disabled = true;
			}
			} catch(E) {
				alert(E);
			}
		}, 0
	);
}

g.render_callnumber_copy_count_entry = function(row,ou_id,count) {
	var grid = util.widgets.make_grid( [ {}, {} ] ); row.appendChild(grid);
	grid.setAttribute('flex','1');
	grid.setAttribute('ou_id',ou_id);
	var rows = grid.lastChild;
	var r = document.createElement('row'); rows.appendChild( r );
	var x = document.createElement('label'); r.appendChild(x);
	x.setAttribute('value', $("catStrings").getString('staff.cat.volume_copy_creator.render_callnumber_copy_count_entry.call_nums')); x.setAttribute('style','font-weight: bold');
	x = document.createElement('label'); r.appendChild(x);
	x.setAttribute('value',$("catStrings").getString('staff.cat.volume_copy_creator.render_callnumber_copy_count_entry.num_of_copies')); x.setAttribute('style','font-weight: bold');
	x.setAttribute('size','3'); x.setAttribute('cols','3');


	function handle_change(tb1,tb2,hb3) {
		if (tb1.value == '') return;
		if (isNaN( Number( tb2.value ) )) return;
		if ( Number( tb2.value ) > g_max_copies_that_can_be_added_at_a_time_per_volume ) {
			g.error.yns_alert($("catStrings").getFormattedString('staff.cat.volume_copy_creator.render_volume_count_entry.message', [g_max_copies_that_can_be_added_at_a_time_per_volume]),
				$("catStrings").getString('staff.cat.volume_copy_creator.render_volume_count_entry.title'),
				$("catStrings").getString('staff.cat.volume_copy_creator.render_volume_count_entry.ok_label'),null,null,'');
            return;
		}

		//if (tb1.disabled || tb2.disabled) return;

		//tb1.disabled = true;
		//tb2.disabled = true;

		util.widgets.remove_children(hb3);

		g.render_barcode_entry(hb3,tb1.value,Number(tb2.value),ou_id);
		document.getElementById("Create").disabled = false;
	}

	function handle_change_tb1(ev) {
		var _tb1 = ev.target;	
		var _hb1 = _tb1.parentNode;
		var _hb2 = _hb1.nextSibling;
		var _tb2 = _hb2.firstChild;
		var _hb3 = _hb2.nextSibling;
		handle_change(_tb1,_tb2,_hb3);
	}

	function handle_change_tb2(ev) {
		var _tb2 = ev.target;	
		var _hb2 = _tb2.parentNode;
		var _hb1 = _hb2.previousSibling;
		var _tb1 = _hb1.firstChild;
		var _hb3 = _hb2.nextSibling;
		handle_change(_tb1,_tb2,_hb3);
	}

	for (var i = 0; i < count; i++) {
		var r = document.createElement('row'); rows.appendChild(r);
		var hb1 = document.createElement('vbox'); r.appendChild(hb1);
		var hb2 = document.createElement('vbox'); r.appendChild(hb2);
		var hb3 = document.createElement('vbox'); r.appendChild(hb3);
		var tb1 = document.createElement('textbox'); hb1.appendChild(tb1);
		tb1.setAttribute('rel_vert_pos','2');
		tb1.setAttribute('ou_id',ou_id);
		util.widgets.apply_vertical_tab_on_enter_handler( 
			tb1, 
			function() { handle_change_tb1({'target':tb1}); setTimeout(function(){util.widgets.vertical_tab(tb1);},0); }
		);
		var tb2 = document.createElement('textbox'); hb2.appendChild(tb2);
		tb2.setAttribute('size','3'); tb2.setAttribute('cols','3');
		tb2.setAttribute('rel_vert_pos','3');
		tb2.setAttribute('ou_id',ou_id);
		util.widgets.apply_vertical_tab_on_enter_handler( 
			tb2, 
			function() { handle_change_tb2({'target':tb2}); setTimeout(function(){util.widgets.vertical_tab(tb2);},0); }
		);

		tb1.addEventListener( 'change', handle_change_tb1, false);
		tb1.addEventListener( 'focus', function(ev) { g.last_focus = ev.target; }, false );
		tb2.addEventListener( 'change', handle_change_tb2, false);
		tb2.addEventListener( 'focus', function(ev) { g.last_focus = ev.target; }, false );
		if ( !g.last_focus ) { tb2.focus(); g.last_focus = tb2; }

		setTimeout(
			function(idx,tb){
				return function() {
					try {
					JSAN.use('util.functional');
					if (g.copy_shortcut) {
						var label = util.functional.map_object_to_list(
							g.copy_shortcut[ou_id],
							function(o,i) {
								return i;
							}
						)[idx];
						tb.value = label; handle_change_tb1({'target':tb});
						tb.disabled = true;
					}
					} catch(E) {
						alert(E);
					}
				}
			}(i,tb1),0
		);
	}

	return grid;
}

g.render_barcode_entry = function(node,callnumber,count,ou_id) {
	try {
		function ready_to_create(ev) {
			document.getElementById("Create").disabled = false;
		}

		JSAN.use('util.barcode'); 

		for (var i = 0; i < count; i++) {
			var tb = document.createElement('textbox'); node.appendChild(tb);
			tb.setAttribute('ou_id',ou_id);
			tb.setAttribute('callnumber',callnumber);
			tb.setAttribute('rel_vert_pos','4');
			util.widgets.apply_vertical_tab_on_enter_handler( 
				tb, 
				function() { ready_to_create({'target':tb}); setTimeout(function(){util.widgets.vertical_tab(tb);},0); }
			);
			//tb.addEventListener('change',ready_to_create,false);
			tb.addEventListener('change', function(ev) {
				var barcode = String( ev.target.value ).replace(/\s/g,'');
				if (barcode != ev.target.value) ev.target.value = barcode;
				if ($('check_barcodes').checked && ! util.barcode.check(barcode) ) {
					g.error.yns_alert($("catStrings").getFormattedString('staff.cat.volume_copy_creator.render_barcode_entry.alert_message', [barcode]),
						$("catStrings").getString('staff.cat.volume_copy_creator.render_barcode_entry.alert_title'),
						$("catStrings").getString('staff.cat.volume_copy_creator.render_barcode_entry.alert_ok_button'),null,null,
						$("catStrings").getString('staff.cat.volume_copy_creator.render_barcode_entry.alert_confirm'));
					setTimeout( function() { ev.target.select(); ev.target.focus(); }, 0);
				}
			}, false);
			tb.addEventListener( 'focus', function(ev) { g.last_focus = ev.target; }, false );
		}
	} catch(E) {
		g.error.sdump('D_ERROR','g.render_barcode_entry: ' + E);
	}
}

g.new_node_id = -1;

g.stash_and_close = function() {

	try {

		var nl = document.getElementsByTagName('textbox');

		var volumes_hash = {};

		var barcodes = [];
		
		for (var i = 0; i < nl.length; i++) {
			if ( nl[i].getAttribute('rel_vert_pos') == 4 ) barcodes.push( nl[i] );
			if ( nl[i].getAttribute('rel_vert_pos') == 2 )  {
				var ou_id = nl[i].getAttribute('ou_id');
				var callnumber = nl[i].value;
				if (typeof volumes_hash[ou_id] == 'undefined') { volumes_hash[ou_id] = {} }
				if (typeof volumes_hash[ou_id][callnumber] == 'undefined') { volumes_hash[ou_id][callnumber] = [] }
			}
		};
	
		for (var i = 0; i < barcodes.length; i++) {
			var ou_id = barcodes[i].getAttribute('ou_id');
			var callnumber = barcodes[i].getAttribute('callnumber');
			var barcode = barcodes[i].value;

			if (typeof volumes_hash[ou_id] == 'undefined') { volumes_hash[ou_id] = {} }
			if (typeof volumes_hash[ou_id][callnumber] == 'undefined') { volumes_hash[ou_id][callnumber] = [] }

			if (barcode != '') volumes_hash[ou_id][callnumber].push( barcode );
		}

		var volumes = [];
		var copies = [];
		var volume_labels = {};

		for (var ou_id in volumes_hash) {
			for (var cn in volumes_hash[ou_id]) {

				var acn_id = g.network.simple_request(
					'FM_ACN_FIND_OR_CREATE',
					[ ses(), cn, g.doc_id, ou_id ]
				);

				if (typeof acn_id.ilsevent != 'undefined') {
					g.error.standard_unexpected_error_alert($("catStrings").getFormattedString('staff.cat.volume_copy_creator.stash_and_close.problem_with_volume', [cn]), acn_id);
					continue;
				}

				volume_labels[ acn_id ] = { 'label' : cn, 'owning_lib' : ou_id };

				for (var i = 0; i < volumes_hash[ou_id][cn].length; i++) {
					var copy = new acp();
					copy.id( g.new_node_id-- );
					copy.isnew('1');
					copy.barcode( volumes_hash[ou_id][cn][i] );
					copy.call_number( acn_id );
					copy.circ_lib(ou_id);
					/* FIXME -- use constants */
					copy.deposit(0);
					copy.price(0);
					copy.deposit_amount(0);
					copy.fine_level(2);
					copy.loan_duration(2);
					copy.location(1);
					copy.status(0);
					copy.circulate(get_db_true());
					copy.holdable(get_db_true());
					copy.opac_visible(get_db_true());
					copy.ref(get_db_false());
					copies.push( copy );
				}
			}
		}

		JSAN.use('util.window'); var win = new util.window();
		if (copies.length > 0) {
			JSAN.use('cat.util');
            copies = cat.util.spawn_copy_editor( { 'edit' : 1, 'docid' : g.doc_id, 'copies' : copies });
            try {
                //case 1706 /* ITEM_BARCODE_EXISTS */ :
                if (copies && copies.length > 0 && $('print_labels').checked) {
                    JSAN.use('util.functional');
                    JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
                    data.temp_barcodes_for_labels = util.functional.map_list( copies, function(o){return o.barcode();}) ; 
                    data.stash('temp_barcodes_for_labels');
                    var w = win.open(
                        urls.XUL_SPINE_LABEL,
                        'spine_labels',
                        'chrome,resizable,width=750,height=550'
                    );
                }
            } catch(E) {
                g.error.standard_unexpected_error_alert($(catStrings).getString('staff.cat.volume_copy_creator.stash_and_close.tree_err2'),E);
            }
	}

		if (typeof window.refresh == 'function') window.refresh();

		window.close();

	} catch(E) {
		g.error.standard_unexpected_error_alert($(catStrings).getString('staff.cat.volume_copy_creator.stash_and_close.tree_err3'),E);
	}
}

g.load_prefs = function() {
	try {
		netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
		JSAN.use('util.file'); var file = new util.file('volume_copy_creator.prefs');
		if (file._file.exists()) {
			var prefs = file.get_object(); file.close();
			if (prefs.check_barcodes) {
				if ( prefs.check_barcodes == 'false' ) {
					$('check_barcodes').checked = false;
				} else {
					$('check_barcodes').checked = prefs.check_barcodes;
				}
			} else {
				$('check_barcodes').checked = false;
			}
			if (prefs.print_labels) {
				if ( prefs.print_labels == 'false' ) {
					$('print_labels').checked = false;
				} else {
					$('print_labels').checked = prefs.print_labels;
				}
			} else {
				$('print_labels').checked = false;
			}

		}
	} catch(E) {
		g.error.standard_unexpected_error_alert($(catStrings).getString('staff.cat.volume_copy_creator.load_prefs.err_retrieving_prefs'),E);
		
	}
}

g.save_prefs = function () {
	try {
		netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
		JSAN.use('util.file'); var file = new util.file('volume_copy_creator.prefs');
		file.set_object(
			{
				'check_barcodes' : $('check_barcodes').checked,
				'print_labels' : $('print_labels').checked,
			}
		);
		file.close();
	} catch(E) {
		g.error.standard_unexpected_error_alert($(catStrings).getString('staff.cat.volume_copy_creator.save_prefs.err_storing_prefs'),E);
	}
}


