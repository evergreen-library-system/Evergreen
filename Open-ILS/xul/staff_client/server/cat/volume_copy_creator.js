function my_init() {
	try {

		/***********************************************************************************************************/
		/* Initial setup */

		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
				if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('/xul/server/');
		JSAN.use('util.error'); g.error = new util.error();
		g.error.sdump('D_TRACE','my_init() for cat/volume_copy_creator.xul');

		JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
		JSAN.use('util.widgets'); JSAN.use('util.functional');

		JSAN.use('util.network'); g.network = new util.network();

		g.cgi = new CGI();

		/***********************************************************************************************************/
		/* What record am I dealing with?  Am I adding just copies or copies and volumes? */

		g.doc_id = g.cgi.param('doc_id');
		g.copy_shortcut = g.cgi.param('copy_shortcut');
		g.error.sdump('D_ERROR','location.href = ' + location.href + '\n\ncopy_short cut = ' + g.copy_shortcut + '\n\nou_ids = ' + g.cgi.param('ou_ids'));
		if (g.copy_shortcut) g.copy_shortcut = JSON2js( g.copy_shortcut );

		var ou_ids = [];
		if (g.cgi.param('ou_ids')) 
			ou_ids = JSON2js( g.cgi.param('ou_ids') );
		if (!ou_ids) ou_ids = [];
		if (window.xulG && window.xulG.ou_ids) 
			ou_ids = ou_ids.concat( window.xulG.ou_ids );

		/***********************************************************************************************************/
		/* For the call number drop down */

		var cn_blob;
		try {
			cn_blob = g.network.simple_request('BLOB_MARC_CALLNUMBERS_RETRIEVE',[g.doc_id]);
		} catch(E) {
			cn_blob = [];
		}
		if ((!g.copy_shortcut) && (cn_blob.length > 0)) {
			var hbox = document.getElementById('marc_cn');
			var ml = util.widgets.make_menulist(
				util.functional.map_list(
					cn_blob,
					function(o) {
						for (var i in o) {
							return [ o[i], o[i] ];
						}
					}
				).sort(
					function(b,a) {
						if (a == 82 && b == 92) return -1;
						if (a == 92 && b == 82) return 1;
						if (a == 82) return -1;
						if (a == 92) return -1;
						if (a < b) return -1;
						if (a > b) return 1;
						return 0;
					}
				)
			); hbox.appendChild(ml);
			ml.setAttribute('editable','true');
			var btn = document.createElement('button');
			btn.setAttribute('label','Apply');
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
				var row = document.createElement('row'); rows.appendChild(row); row.setAttribute('ou_id',ou_ids[i]);
				g.render_library_label(row,ou_ids[i]);
				g.render_volume_count_entry(row,ou_ids[i]);
			} catch(E) {
				g.error.sdump('D_ERROR',E);
			}
		}

	} catch(E) {
		var err_msg = "!! This software has encountered an error.  Please tell your friendly " +
			"system administrator or software developer the following:\ncat/volume_copy_creator.xul\n" +E+ '\n';
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
		if (! isNaN( parseInt( ev.target.value) ) ) {
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
	x.setAttribute('value','Call Numbers'); x.setAttribute('style','font-weight: bold');
	x = document.createElement('label'); r.appendChild(x);
	x.setAttribute('value','# of Copies'); x.setAttribute('style','font-weight: bold');

	function handle_change(tb1,tb2,hb3) {
		if (tb1.value == '') return;
		if (isNaN( parseInt( tb2.value ) )) return;

		//if (tb1.disabled || tb2.disabled) return;

		//tb1.disabled = true;
		//tb2.disabled = true;

		util.widgets.remove_children(hb3);

		g.render_barcode_entry(hb3,tb1.value,parseInt(tb2.value),ou_id);
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
		util.widgets.apply_vertical_tab_on_enter_handler( 
			tb1, 
			function() { handle_change_tb1({'target':tb1}); setTimeout(function(){util.widgets.vertical_tab(tb1);},0); }
		);
		var tb2 = document.createElement('textbox'); hb2.appendChild(tb2);
		tb2.setAttribute('size','3'); tb2.setAttribute('cols','3');
		tb2.setAttribute('rel_vert_pos','3');
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

		for (var i = 0; i < count; i++) {
			var tb = document.createElement('textbox'); node.appendChild(tb);
			tb.setAttribute('ou_id',ou_id);
			tb.setAttribute('callnumber',callnumber);
			tb.setAttribute('rel_vert_pos','4');
			util.widgets.apply_vertical_tab_on_enter_handler( 
				tb, 
				function() { ready_to_create({'target':tb}); setTimeout(function(){util.widgets.vertical_tab(tb);},0); }
			);
			tb.addEventListener('change',ready_to_create,false);
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
		};
	
		for (var i = 0; i < barcodes.length; i++) {
			var ou_id = barcodes[i].getAttribute('ou_id');
			var callnumber = barcodes[i].getAttribute('callnumber');
			var barcode = barcodes[i].value;

			if (typeof volumes_hash[ou_id] == 'undefined') { volumes_hash[ou_id] = {} }
			if (typeof volumes_hash[ou_id][callnumber] == 'undefined') { volumes_hash[ou_id][callnumber] = [] }

			volumes_hash[ou_id][callnumber].push( barcode );
		}

		var volumes = [];
		var copies = [];
		var volume_labels = {};

		for (var ou_id in volumes_hash) {
			for (var cn in volumes_hash[ou_id]) {
				var volume = new acn();
				var acn_id;
				if (!g.copy_shortcut) {
					acn_id = g.new_node_id--;
					volume.isnew('1');
				} else {
					acn_id = g.copy_shortcut[ou_id][cn];
				}
				volume.id( acn_id );
				volume.record(g.doc_id);
				volume.label(cn);
				volume.owning_lib(ou_id);
				volume.copies( [] );
				volumes.push( volume );

				volume_labels[ acn_id ] = cn;

				for (var i = 0; i < volumes_hash[ou_id][cn].length; i++) {
					var copy = new acp();
					copy.id( g.new_node_id-- );
					copy.isnew('1');
					copy.barcode( volumes_hash[ou_id][cn][i] );
					copy.call_number( acn_id );
					copy.circ_lib(ou_id);
					/* FIXME -- use constants */
					copy.deposit(0);
					copy.fine_level(2);
					copy.loan_duration(2);
					copy.location(1);
					copy.status(0);
					copies.push( copy );
				}
			}
		}

		JSAN.use('util.window'); var win = new util.window();
		var w = win.open(
			urls.XUL_COPY_EDITOR
				+'?copies='+window.escape(js2JSON(copies))
				+'&callnumbers='+window.escape(js2JSON(volume_labels))
				+'&edit=1',
			title,
			'chrome,modal,resizable'
		);
		/* FIXME -- need to unique the temp space, and not rely on modalness of window */
		g.data.stash_retrieve();
		copies = JSON2js( g.data.temp_copies );

		for (var i = 0; i < copies.length; i++) {
			var copy = copies[i];
			var volume = util.functional.find_id_object_in_list( volumes, copy.call_number() );
			var temp = volume.copies();
			temp.push( copy );
			volume.copies( temp );
		}

		try {
			var r = g.network.request(
				api.FM_ACN_TREE_UPDATE.app,
				api.FM_ACN_TREE_UPDATE.method,
				[ ses(), volumes ]
			);
			if (typeof r.ilsevent != 'undefined') {
				switch(r.ilsevent) {
					case 1706 /* ITEM_BARCODE_EXISTS */ :
						alert('Some of these barcodes are or have been in use.  Please change them.');
						return;
					break;
					default: g.error.standard_unexpected_error_alert('volume tree update',r); break;
				}
			} else {
				JSAN.use('util.functional');
				var w = win.open(
					urls.XUL_SPINE_LABEL
					+ '?barcodes=' + window.escape( js2JSON( util.functional.map_list(copies,function(o){return o.barcode();}) ) ),
					'spine_labels',
					'chrome,modal,resizable,width=750,height=550'
				);
			}
		} catch(E) {
			g.error.standard_unexpected_error_alert('volume tree update 2',E);
		}

		window.close();

	} catch(E) {
		g.error.standard_unexpected_error_alert('volume tree update 3',E);
	}
}


