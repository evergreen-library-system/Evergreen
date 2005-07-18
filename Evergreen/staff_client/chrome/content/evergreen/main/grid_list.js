sdump('D_TRACE','Loading grid_list.js\n');

function grid_list_init(p) {
	sdump('D_GRID_LIST',"TESTING: grid_list.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	p.grid = p.node.getElementsByAttribute('name','grid')[0];
	p.popup = p.node.getElementsByTagName('popup')[0];
	p.grid_columns = p.grid.firstChild;
	p.grid_rows = p.grid.lastChild;

	p._context_function = function (ev) { alert('default _context_function'); };
	p.popup.addEventListener('popupshowing',function (ev) { return p._context_function(ev); },false);

	grid_list_make_columns( p, p.grid_columns, p.cols )

	p.clear_grid = function () {
		sdump('D_GRID_LIST','p.clear_grid()\n');
		empty_widget( p.grid_rows );
	}

	p.add_rows = function (new_rows) { 
		sdump('D_GRID_LIST','p.add_rows()\n');
		return grid_list_add_rows(p,p.grid_rows,new_rows); 
	}

	p.register_context_builder = function (f) {
		sdump('D_GRID_LIST','p.register_context_builder(' + f + ')\n');
		return p._context_function = f;
	}

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function grid_list_make_columns( p, gridcols, cols ) {
	sdump('D_GRID_LIST',arg_dump(arguments,{2:'.length'}));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var d = p.w.document;
	// cols[ idx ] = { 'id':???, 'label':???, 'primary':???, 'flex':??? }
	for (var i = 0; i < cols.length; i++) {
		var col = cols[i];
		sdump('D_GRID_LIST','Col ' + i + ' : ' + js2JSON( col ) + '\n');
		var gridcol = d.createElement( 'column' );
		gridcols.appendChild( gridcol );
		for (var j in col) {
			gridcol.setAttribute( j, col[j] );
		}
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return gridcols;
}

function grid_list_add_rows( p, grid_rows, new_rows ) {
	sdump('D_GRID_LIST',arg_dump(arguments,{2:'.length'}));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var d = p.w.document;
	var offset = 0;
	if (grid_rows.childNodes.length > 0) { offset = grid_rows.lastChild.id; }
	for (var i = 0; i < new_rows.length; i++) {
		var new_row = new_rows[i];

		gridrows.appendChild( newrow );

	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function grid_list_remove_row_by_id( p, grid_rows, id ) {
	sdump('D_GRID_LIST',arg_dump(arguments));
	var row = grid_rows.getElementsByAttribute('id',id)[0];
	grid_rows.removeChild( row );
}
