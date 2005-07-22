sdump('D_TRACE','Loading patron_edit.js\n');

function patron_edit_init(p) {
	sdump('D_PATRON_EDIT',"TESTING: patron_edit.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	patron_edit_list_box_init( p );

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function patron_edit_list_box_init( p ) {
	p.patron_edit_cols = [
		{
			'id' : 'fieldname', 'label' : getString('patron_edit_fieldname'), 'flex' : 0,
			'primary' : false, 'hidden' : false, 'fm_class' : 'row',
			'fm_field_render' : '.label.toString()'
		},
		{
			'id' : 'current_value', 'label' : getString('patron_edit_current_value'), 'flex' : 1,
			'primary' : false, 'hidden' : false, 'fm_class' : 'row', 
			'fm_field_render' : 'evil_eval(row.fm_class,row.fm_field_render)'
		},
		{
			'id' : 'new_value', 'label' : getString('patron_edit_new_value'), 'flex' : 0, 
			'fm_class' : 'row', 'fm_field_render' : 'create_entry_widget($$)'
		}
	];

	p.list_box = list_box_init( { 'w' : p.w, 'node' : p.node, 'cols' : p.patron_edit_cols, 'debug' : p.app } );
	p.clear_patron_edit = function () { 
		p.list_box.clear_rows(); 
	};

	p.add_rows = function (au) {
		sdump('D_PATRON_EDIT','p.add_row(' + au + ')\n');
		return patron_edit_add_rows(p,au);
	}
}

function patron_edit_add_rows(p, au) {
	sdump('D_PATRON_EDIT',arg_dump(arguments,{1:true}));

	var obj_string ='au';

	var edit = patron_edit_rows();

	function evil_eval( hint, render_code ) {
		sdump('D_PATRON_EDIT',arg_dump(arguments));
		var cmd = parse_render_string( hint, render_code );
		var col = '';
		sdump('D_PATRON_EDIT','evil_cmd = ' + cmd + '\n');
		try {
			col = eval( cmd );
			sdump('D_PATRON_EDIT','evil_eval = ' + col + '\n');
		} catch(E) {
			sdump('D_ERROR',E + '\n');
		}
		return col;
	}

	function create_entry_widget(row) {
		var obj;
		try {
			sdump('D_PATRON_EDIT',arg_dump(arguments));
			if (row.rdefault) {
				row.rdefault = evil_eval( row.fm_class, row.rdefault );
			}
			if (row.entry_widget) {
				obj = p.w.document.createElement( row.entry_widget );
				obj.setAttribute('flex','1');
				if (row.entry_widget_attributes) {
					for (var i in row.entry_widget_attributes) {
						obj.setAttribute( i, row.entry_widget_attributes[i] );
					}
				}
				switch(row.entry_widget) {
					case 'menulist':
						if (row.populate_with) {
							var menupopup = p.w.document.createElement('menupopup');
							obj.appendChild( menupopup );

							for (var i in row.populate_with) {

								var menuitem = p.w.document.createElement('menuitem');
								menupopup.appendChild( menuitem );
								menuitem.setAttribute('label', i );
								menuitem.setAttribute('value', row.populate_with[ i ] );
								if (row.rdefault) {
									if ( (row.rdefault == i) || (row.rdefault == row.populate_with[ i ]) ) {
										sdump('D_PATRON_EDIT','Selected ' + i + '\n');
										menuitem.setAttribute('selected','true');
									}
								}
							}
						}
						break;
					default:
						if (row.rdefault) obj.setAttribute('value', row.rdefault);
						break;
				}
			}
			if (row.entry_event && row.entry_code) {
				obj.addEventListener( row.entry_event, new Function('ev',row.entry_code), false);
			}
		} catch(E) {
			alert(E + '\n' + js2JSON(E) + '\n');
			sdump('D_ERROR',E + '\n');
			obj = 'error';
		}
		return obj;
	}

	setTimeout(
		function() {

			for (var i = 0; i < edit.length; i++) {

				var row = edit[i];

				var cols = [];

				for (var j = 0; j < p.patron_edit_cols.length; j++) {
					var hash = p.patron_edit_cols[j];
					sdump('D_PATRON_EDIT','Considering ' + js2JSON(hash) + '\n');
					var listcell = p.w.document.createElement('listcell');
					listcell.setAttribute('pack','start');
					listcell.setAttribute('align','start');
					listcell.setAttribute('style','border-left: black solid thin');
					var col = '';
					if (hash.fm_field_render) {

						switch( hash.fm_class ) {
							case 'row' : obj_string = 'row'; break;
							case 'au' : obj_string = 'au'; break;
						}
						var cmd = parse_render_string( obj_string, hash.fm_field_render );
						sdump('D_PATRON_EDIT','cmd = ' + cmd + '\n');
						try {
							col = eval( cmd );
							sdump('D_PATRON_EDIT','eval = ' + col + '\n');
						} catch(E) {
							sdump('D_ERROR',E + '\n');
						}
						if (typeof(col) == 'string') {
							listcell.setAttribute('label',col);
						} else {
							if (col==null) {
								listcell.setAttribute('label','');
							} else {
								listcell.appendChild( col );
							}
						}
					}
					cols.push( listcell );
				}

				if (!row['style']) row['style'] = '';
				if (!row['class']) row['class'] = '';
				var listitem = p.list_box.add_row(
					cols, { 'style' : row['style'], 'class' : row['class'] }
				);

				if (p.list_box.apply_to_each_listitem) {
					p.list_box.apply_to_each_listitem( i, listitem );
				}
			}
		}, 0
	);
}
