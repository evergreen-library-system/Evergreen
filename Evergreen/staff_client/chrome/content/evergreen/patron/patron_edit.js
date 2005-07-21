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
			'render_xul' : 'textbox'
		}
	];

	p.list_box = list_box_init( { 'w' : p.w, 'node' : p.node, 'cols' : p.patron_edit_cols, 'debug' : p.app } );
	p.clear_patron_edit = function () { 
		p.list_box.clear_rows(); 
	};

	p.add_rows = function (edit) {
		sdump('D_PATRON_EDIT','p.add_row(' + edit + ')\n');
		return patron_edit_add_rows(p,edit);
	}

	p.add_rows( patron_edit_rows() );
}

function patron_edit_add_rows(p, edit) {
	sdump('D_PATRON_EDIT',arg_dump(arguments,{1:true}));

	var au = p._patron;

	var obj_string ='au';

	function evil_eval( hint, render_code ) {
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
							listcell.appendChild( col );
						}
					}
					if (hash.render_xul) {
						var xul = p.w.document.createElement( hash.render_xul );
						listcell.appendChild( xul );
						if (hash.render_xul == 'checkbox') xul.setAttribute('checked', 'true');
					}
					cols.push( listcell );
				}

				var listitem = p.list_box.add_row(
					cols, {}
				);

				if (p.list_box.apply_to_each_listitem) {
					p.list_box.apply_to_each_listitem( i, listitem );
				}
			}
		}, 0
	);
}
