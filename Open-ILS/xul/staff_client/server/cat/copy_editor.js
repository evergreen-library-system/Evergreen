var g = {};

function my_init() {
	try {
		/******************************************************************************************************/
		/* setup JSAN and some initial libraries */

		netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
		if (typeof JSAN == 'undefined') { throw( "The JSAN library object is missing."); }
		JSAN.errorLevel = "die"; // none, warn, or die
		JSAN.addRepository('/xul/server/');
		JSAN.use('util.error'); g.error = new util.error();
		g.error.sdump('D_TRACE','my_init() for cat/copy_editor.xul');

		JSAN.use('util.functional');
		JSAN.use('OpenILS.data'); g.data = new OpenILS.data(); g.data.init({'via':'stash'});
		JSAN.use('util.network'); g.network = new util.network();

		g.cgi = new CGI();

		g.docid = g.cgi.param('docid');
		g.handle_update = g.cgi.param('handle_update');

		/******************************************************************************************************/
		/* Get the copy ids from various sources and flesh them */

		var copy_ids = [];
		if (g.cgi.param('copy_ids')) copy_ids = JSON2js( g.cgi.param('copy_ids') );
		if (!copy_ids) copy_ids = [];
		if (window.xulG && window.xulG.copy_ids) copy_ids = copy_ids.concat( window.xulG.copy_ids );

		if (copy_ids.length > 0) g.copies = g.network.request(
			api.FM_ACP_FLESHED_BATCH_RETRIEVE.app,
			api.FM_ACP_FLESHED_BATCH_RETRIEVE.method,
			[ copy_ids ]
		);

		/******************************************************************************************************/
		/* And other fleshed copies if any */

		if (!g.copies) g.copies = [];
		if (window.xulG && window.xulG.copies) g.copies = g.copies.concat( window.xulG.copies );
		if (g.cgi.param('copies')) g.copies = g.copies.concat( JSON2js( g.cgi.param('copies') ) );

		/******************************************************************************************************/
		/* We try to retrieve callnumbers for existing copies, but for new copies, we rely on this */

		if (window.xulG && window.xulG.callnumbers) g.callnumbers = window.xulG.callnumbers;
		if (g.cgi.param('callnumbers')) g.callnumbers =  JSON2js( g.cgi.param('callnumbers') );

		/******************************************************************************************************/
		/* Is the interface an editor or a viewer, single or multi copy, existing copies or new copies? */

		if (g.cgi.param('edit') == '1') { 
			g.edit = true;
			document.getElementById('caption').setAttribute('label','Copy Editor'); 
			document.getElementById('save').setAttribute('hidden','false'); 
		}

		//if (g.cgi.param('single_edit') == '1') {
		//{
			g.single_edit = true;
			document.getElementById('caption').setAttribute('label','Copy Editor'); 
			document.getElementById('save').setAttribute('hidden','false'); 
		//}

		if (g.copies.length > 0 && g.copies[0].id() < 0) {
			document.getElementById('copy_notes').setAttribute('hidden','true');
			g.apply("status",5 /* In Process */);
		} else {
			g.panes_and_field_names.right_pane4.push(
				[
					"Status",
					{ 
						render: 'fm.status().name();', 
						input: 'c = function(v){ g.apply("status",v); }; x = util.widgets.make_menulist( util.functional.map_list( g.data.list.ccs, function(obj) { return [ obj.name(), obj.id() ]; } ).sort() ); x.addEventListener("command",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
					}
				]
			);
		}

		if (g.copies.length != 1) {
			document.getElementById('copy_notes').setAttribute('hidden','true');
		}

		/******************************************************************************************************/
		/* Show the Record Details? */

		if (g.docid) {
			document.getElementById('brief_display').setAttribute(
				'src',
				urls.XUL_BIB_BRIEF + '?docid=' + g.docid
			);
		} else {
			document.getElementById('brief_display').setAttribute('hidden','true');
		}

		/******************************************************************************************************/
		/* Add stat cats to the panes_and_field_names.right_pane4 */

		var stat_cat_seen = {};

		function add_stat_cat(sc) {

			if (typeof g.data.hash.asc == 'undefined') { g.data.hash.asc = {}; g.data.stash('hash'); }

			var sc_id = sc;

			if (typeof sc == 'object') {

				sc_id = sc.id();
			}

			if (typeof stat_cat_seen[sc_id] != 'undefined') { return; }

			stat_cat_seen[ sc_id ] = 1;

			if (typeof sc != 'object') {

				sc = g.network.simple_request(
					'FM_ASC_BATCH_RETRIEVE',
					[ ses(), [ sc_id ] ]
				)[0];

			}

			g.data.hash.asc[ sc.id() ] = sc; g.data.stash('hash');

			var label_name = g.data.hash.aou[ sc.owner() ].shortname() + " : " + sc.name();

			var temp_array = [
				label_name,
				{
					render: 'var l = util.functional.find_list( fm.stat_cat_entries(), function(e){ return e.stat_cat() == ' 
						+ sc.id() + '; } ); l ? l.value() : null;',
					input: 'c = function(v){ g.apply_stat_cat(' + sc.id() + ',v); }; x = util.widgets.make_menulist( util.functional.map_list( g.data.hash.asc[' + sc.id() 
						+ '].entries(), function(obj){ return [ obj.value(), obj.id() ]; } ).sort() ); '
						+ 'x.addEventListener("command",function(f){ return function(ev) { f(ev.target.value); } }(c),false);',
				}
			];

			dump('temp_array = ' + js2JSON(temp_array) + '\n');

			g.panes_and_field_names.right_pane4.push( temp_array );
		}

		/* The stat cats for the pertinent library */
		for (var i = 0; i < g.data.list.my_asc.length; i++) {
			add_stat_cat( g.data.list.my_asc[i] );	
		}

		/* Other stat cats present on these copies */
		for (var i = 0; i < g.copies.length; i++) {
			var entries = g.copies[i].stat_cat_entries();
			if (!entries) entries = [];
			for (var j = 0; j < entries.length; j++) {
				var sc_id = entries[j].stat_cat();
				add_stat_cat( sc_id );
			}
		}

		/******************************************************************************************************/
		/* Do it */

		g.summarize( g.copies );
		g.render();

	} catch(E) {
		var err_msg = "!! This software has encountered an error.  Please tell your friendly " +
			"system administrator or software developer the following:\ncat/copy_editor.xul\n" + E + '\n';
		try { g.error.sdump('D_ERROR',err_msg); } catch(E) { dump(err_msg); dump(js2JSON(E)); }
		alert(err_msg);
	}
}

/******************************************************************************************************/
/* Apply a value to a specific field on all the copies being edited */

g.apply = function(field,value) {
	g.error.sdump('D_TRACE','field = ' + field + '  value = ' + value + '\n');
	for (var i = 0; i < g.copies.length; i++) {
		var copy = g.copies[i];
		try {
			copy[field]( value ); copy.ischanged('1');
		} catch(E) {
			alert(E);
		}
	}
}

/******************************************************************************************************/
/* Apply a stat cat entry to all the copies being edited */

g.apply_stat_cat = function(sc_id,entry_id) {
	g.error.sdump('D_TRACE','sc_id = ' + sc_id + '  entry_id = ' + entry_id + '\n');
	for (var i = 0; i < g.copies.length; i++) {
		var copy = g.copies[i];
		try {
			copy.ischanged('1');
			var temp = copy.stat_cat_entries();
			if (!temp) temp = [];
			temp = util.functional.filter_list(
				temp,
				function (obj) {
					return (obj.stat_cat() != sc_id);
				}
			);
			temp.push( 
				util.functional.find_id_object_in_list( 
					g.data.hash.asc[sc_id].entries(), 
					entry_id
				)
			);
			copy.stat_cat_entries( temp );

		} catch(E) {
			alert(E);
		}
	}
}


/******************************************************************************************************/
/* These need data from the middle layer to render */

g.special_exception = {
	'Call Number' : function(label,value) {
		if (value>0) { /* an existing call number */
			g.network.request(
				api.FM_ACN_RETRIEVE.app,
				api.FM_ACN_RETRIEVE.method,
				[ value ],
				function(req) {
					var cn = '??? id = ' + value;
					try {
						cn = req.getResultObject().label();
					} catch(E) {
						g.error.sdump('D_ERROR','callnumber retrieve: ' + E);
					}
					label.setAttribute('value',cn);
				}
			);
		} else { /* a yet to be created call number */
			if (g.callnumbers) {
				label.setAttribute('value',g.callnumbers[value]);
			}
		}
	},
	'Creator' : function(label,value) {
		if (value == null || value == '' || value == 'null') return;
		g.network.simple_request(
			'FM_AU_RETRIEVE_VIA_ID',
			[ ses(), value ],
			function(req) {
				var p = '??? id = ' + value;
				try {
					p = req.getResultObject();
					p = p.usrname();

				} catch(E) {
					g.error.sdump('D_ERROR','patron retrieve: ' + E);
				}
				label.setAttribute('value',p);
			}
		);
	},
	'Last Editor' : function(label,value) {
		if (value == null || value == '' || value == 'null') return;
		g.network.simple_request(
			'FM_AU_RETRIEVE_VIA_ID',
			[ ses(), value ],
			function(req) {
				var p = '??? id = ' + value;
				try {
					p = req.getResultObject();
					p = p.usrname();

				} catch(E) {
					g.error.sdump('D_ERROR','patron retrieve: ' + E);
				}
				label.setAttribute('value',p);
			}
		);
	}

}

/******************************************************************************************************/
g.readonly_stat_cat_names = [];
g.editable_stat_cat_names = [];

/******************************************************************************************************/
/* These get show in the left panel */

g.panes_and_field_names = {

	'left_pane' :
[
	[
		"Alert Message",
		{
			render: 'fm.alert_message();',
			input: 'c = function(v){ g.apply("alert_message",v); }; x = document.createElement("textbox"); x.addEventListener("change",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],

	[
		"Barcode",		 
		{
			render: 'fm.barcode();',
		}
	], 
	[
		"Creation Date",
		{ 
			render: 'util.date.formatted_date( fm.create_date(), "%F");',
		}
	],
	[
		"Last Edit Date",
		{ 
			render: 'util.date.formatted_date( fm.edit_date(), "%F");',
		}
	],
	[
		"Creator",
		{ 
			render: 'fm.creator();',
		}
	],
	[
		"Last Editor",
		{
			render: 'fm.editor();',
		}
	],

],

'right_pane' :
[
	[
		"Call Number", 	
		{
			render: 'fm.call_number();',
		}
	],
	[
		"OPAC Visible?",
		{ 
			render: 'fm.opac_visible() ? "Yes" : "No";', 
			input: 'c = function(v){ g.apply("opac_visible",v); }; x = util.widgets.make_menulist( [ [ "Yes", "1" ], [ "No", "0" ] ] ); x.addEventListener("command",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
	[
		"Reference?",
		{ 
			render: 'fm.ref() ? "Yes" : "No";', 
			input: 'c = function(v){ g.apply("ref",v); }; x = util.widgets.make_menulist( [ [ "Yes", "1" ], [ "No", "0" ] ] ); x.addEventListener("command",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
	[
		"Shelving Location",
		{ 
			render: 'fm.location().name();', 
			input: 'c = function(v){ g.apply("location",v); }; x = util.widgets.make_menulist( util.functional.map_list( g.data.list.acpl, function(obj) { return [ obj.name(), obj.id() ]; }).sort()); x.addEventListener("command",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',

		}
	],
	[
		"Circulation Library",		
		{ 	
			render: 'fm.circ_lib().shortname();',
			input: 'c = function(v){ g.apply("circ_lib",v); }; x = util.widgets.make_menulist( util.functional.map_list( util.functional.filter_list(g.data.list.my_aou, function(obj) { return g.data.hash.aout[ obj.ou_type() ].can_have_vols(); }), function(obj) { return [ obj.shortname(), obj.id() ]; }).sort() ); x.addEventListener("command",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		} 
	],

	[
		"Copy Number",
		{ 
			render: 'fm.copy_number();',
			input: 'c = function(v){ g.apply("copy_number",v); }; x = document.createElement("textbox"); x.addEventListener("change",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
],

'right_pane2' :
[
	[
		"Loan Duration",
		{ 
			render: 'switch(fm.loan_duration()){ case 1: "Short"; break; case 2: "Normal"; break; case 3: "Long"; break; }',
			input: 'c = function(v){ g.apply("loan_duration",v); }; x = util.widgets.make_menulist( [ [ "Short", "1" ], [ "Normal", "2" ], [ "Long", "3" ] ] ); x.addEventListener("command",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',

		}
	],
	[
		"Holdable?",
		{ 
			render: 'fm.holdable() ? "Yes" : "No";', 
			input: 'c = function(v){ g.apply("holdable",v); }; x = util.widgets.make_menulist( [ [ "Yes", "1" ], [ "No", "0" ] ] ); x.addEventListener("command",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
	[
		"Circulate?",
		{ 	
			render: 'fm.circulate() == null ? "<Unset>" : ( fm.circulate() == 1 ? "Yes" : "No" )',
			input: 'c = function(v){ g.apply("circulate",v); }; x = util.widgets.make_menulist( [ [ "Yes", "1" ], [ "No", "0" ] ] ); x.addEventListener("command",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
	 [
		"Circulate as Type",	
		{ 	
			render: 'fm.circ_as_type();',
			input: 'c = function(v){ g.apply("circ_as_type",v); }; x = document.createElement("textbox"); x.addEventListener("change",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		} 
	],
	[
		"Circulation Modifier",
		{	
			render: 'fm.circ_modifier();',
			input: 'c = function(v){ g.apply("circ_modifier",v); }; x = document.createElement("textbox"); x.addEventListener("change",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
],

'right_pane3' :
[
	[
		"Fine Level",
		{
			render: 'switch(fm.fine_level()){ case 1: "Low"; break; case 2: "Normal"; break; case 3: "High"; break; }',
			input: 'c = function(v){ g.apply("fine_level",v); }; x = util.widgets.make_menulist( [ [ "Low", "1" ], [ "Normal", "2" ], [ "High", "3" ] ] ); x.addEventListener("command",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
	[
		"Deposit?",
		{ 
			render: 'fm.deposit() ? "Yes" : "No";',
			input: 'c = function(v){ g.apply("deposit",v); }; x = util.widgets.make_menulist( [ [ "Yes", "1" ], [ "No", "0" ] ] ); x.addEventListener("command",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
	[
		"Deposit Amount",
		{ 
			render: 'util.money.sanitize( fm.deposit_amount() );',
			input: 'c = function(v){ g.apply("deposit_amount",v); }; x = document.createElement("textbox"); x.addEventListener("change",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
	[
		"Price",
		{ 
			render: 'util.money.sanitize( fm.price() );', 
			input: 'c = function(v){ g.apply("price",v); }; x = document.createElement("textbox"); x.addEventListener("change",function(f){ return function(ev) { f(ev.target.value); } }(c), false);',
		}
	],
],

'right_pane4' : 
[
]

};

/******************************************************************************************************/
/* This loops through all our fieldnames and all the copies, tallying up counts for the different values */

g.summarize = function( copies ) {
	/******************************************************************************************************/
	/* Setup */

	JSAN.use('util.date'); JSAN.use('util.money');
	g.summary = {};
	g.field_names = [];
	for (var i in g.panes_and_field_names) {
		g.field_names = g.field_names.concat( g.panes_and_field_names[i] );
	}
	g.field_names = g.field_names.concat( g.editable_stat_cat_names );
	g.field_names = g.field_names.concat( g.readonly_stat_cat_names );

	/******************************************************************************************************/
	/* Loop through the field names */

	for (var i = 0; i < g.field_names.length; i++) {

		var field_name = g.field_names[i][0];
		var render = g.field_names[i][1].render;
		g.summary[ field_name ] = {};

		/******************************************************************************************************/
		/* Loop through the copies */

		for (var j = 0; j < copies.length; j++) {

			var fm = copies[j];
			var cmd = render || ('fm.' + field_name + '();');
			var value = '???';

			/**********************************************************************************************/
			/* Try to retrieve the value for this field for this copy */

			try { 
				value = eval( cmd ); 
			} catch(E) { 
				g.error.sdump('D_ERROR','Attempted ' + cmd + '\n' +  E + '\n'); 
			}
			if (typeof value == 'object' && value != null) {
				alert('FIXME: field_name = ' + field_name + '  value = ' + js2JSON(value) + '\n');
			}

			/**********************************************************************************************/
			/* Tally the count */

			if (g.summary[ field_name ][ value ]) {
				g.summary[ field_name ][ value ]++;
			} else {
				g.summary[ field_name ][ value ] = 1;
			}
		}
	}
	g.error.sdump('D_TRACE','summary = ' + js2JSON(g.summary) + '\n');
}

/******************************************************************************************************/
/* Display the summarized data and inputs for editing */

g.render = function() {

	/******************************************************************************************************/
	/* Library setup and clear any existing interface */

	JSAN.use('util.widgets'); JSAN.use('util.date'); JSAN.use('util.money'); JSAN.use('util.functional');

	for (var i in g.panes_and_field_names) {
		var p = document.getElementById(i);
		if (p) util.widgets.remove_children(p);
	}

	/******************************************************************************************************/
	/* Prepare the panes */

	if (g.single_edit) {
		
		/******************************************************************************************************/
		/* For a less dangerous batch edit, choose one field here */

		var gb = document.createElement('groupbox'); document.getElementById('input_placeholder').appendChild(gb);
		var c = document.createElement('caption'); gb.appendChild(c);
		c.setAttribute('label','Choose a field to edit');
		JSAN.use('util.widgets'); JSAN.use('util.functional');
		var ml = util.widgets.make_menulist(
			util.functional.map_list(
				g.panes_and_field_names.right_pane,
				function(o,i) { return [ o[0], i ]; }
			)
		);
		gb.appendChild(ml);
		ml.addEventListener(
			'command',
			function(ev) {
				g.render_input(gb, g.panes_and_field_names.right_pane[ ev.target.value ][1].input);
				ml.disabled = true;
			}, 
			false
		);

	}

	/******************************************************************************************************/
	/* multi-copy mode has a groupbox for each field */

	var groupbox; var caption; var vbox; var grid; var rows;
	
	/******************************************************************************************************/
	/* Loop through the field names */

	for (h in g.panes_and_field_names) {
		if (!document.getElementById(h)) continue;
		for (var i = 0; i < g.panes_and_field_names[h].length; i++) {
			try {
				var f = g.panes_and_field_names[h][i]; var fn = f[0];
				groupbox = document.createElement('groupbox'); document.getElementById(h).appendChild(groupbox);
				caption = document.createElement('caption'); groupbox.appendChild(caption);
				caption.setAttribute('label',fn);
				vbox = document.createElement('vbox'); groupbox.appendChild(vbox);
				grid = util.widgets.make_grid( [ { 'flex' : 1 }, {}, {} ] ); vbox.appendChild(grid);
				grid.setAttribute('flex','1');
				rows = grid.lastChild;
				var row;
				
				/**************************************************************************************/
				/* Loop through each value for the field */

				for (var j in g.summary[fn]) {
					var value = j; var count = g.summary[fn][j];
					row = document.createElement('row'); rows.appendChild(row);
					var label1 = document.createElement('description'); row.appendChild(label1);
					if (g.special_exception[ fn ]) {
						g.special_exception[ fn ]( label1, value );
					} else {
						label1.appendChild( document.createTextNode(value) );
					}
					var label2 = document.createElement('description'); row.appendChild(label2);
					var unit = count == 1 ? 'copy' : 'copies';
					label2.appendChild( document.createTextNode(count + ' ' + unit) );
				}
				var hbox = document.createElement('hbox'); 
				hbox.setAttribute('id',fn);
				vbox.appendChild(hbox);

				/**************************************************************************************/
				/* Render the input widget */

				if (!g.single_edit) {
					if (f[1].input && g.edit) {
						g.render_input(hbox,f[1].input);
					}
				}

			} catch(E) {
				g.error.sdump('D_ERROR','copy editor: ' + E + '\n');
			}
		}
	}
}

/******************************************************************************************************/
/* This actually draws the change button and input widget for a given field */
g.render_input = function(node,input_cmd) {
	try {
		var spacer = document.createElement('spacer'); node.appendChild(spacer);
		spacer.setAttribute('flex','1');
		var deck = document.createElement('deck'); node.appendChild(deck);
		var btn = document.createElement('button'); deck.appendChild(btn);
		deck.setAttribute('style','width: 200px; min-width: 200px;');
		btn.setAttribute('label','Change');
		var x; var c; eval( input_cmd );
		btn.addEventListener('command',
			function(f) {
				return function(ev) {
					ev.target.parentNode.selectedIndex = 1;
					c(ev.target.parentNode.lastChild.value);
				}
			}(c),
			false
		);
		if (x) deck.appendChild(x);

	} catch(E) {
		g.error.sdump('D_ERROR',E + '\n');
	}
}

/******************************************************************************************************/
/* store the copies in the global xpcom stash */

g.stash_and_close = function() {
	if (g.handle_update) {
		try {
			var r = g.network.request(
				api.FM_ACP_FLESHED_BATCH_UPDATE.app,
				api.FM_ACP_FLESHED_BATCH_UPDATE.method,
				[ ses(), g.copies ]
			);
			if (typeof r.ilsevent != 'undefined') {
				g.error.standard_unexpected_error_alert('copy update',r);
			}
			/* FIXME -- revisit the return value here */
		} catch(E) {
			alert('copy update error: ' + js2JSON(E));
		}
	}
	g.data.temp_copies = js2JSON( g.copies );
	g.data.stash('temp_copies');
	g.error.sdump('D_CAT','in modal window, g.data.temp_copies = \n' + g.data.temp_copies + '\n');
	window.close();
}

/******************************************************************************************************/
/* spawn copy notes interface */

g.copy_notes = function() {
	JSAN.use('util.window'); var win = new util.window();
	win.open(urls.XUL_COPY_NOTES + '?copy_id=' + window.escape(g.copies[0].id()),'Copy Notes','chrome,resizable,modal');
}

