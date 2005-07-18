sdump('D_TRACE','Loading grid_list.js\n');

function grid_list_init(p) {
	sdump('D_GRID_LIST',"TESTING: grid_list.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	p.grid = p.node.getElementsByAttribute('name','grid')[0];
	//p.popup = p.node.getElementsByTagName('popup')[0];
	p.grid_columns = p.grid.firstChild;
	p.grid_rows = p.grid.lastChild;

	p._context_function = function (ev) { alert('default _context_function'); };
	//p.popup.addEventListener('popupshowing',function (ev) { return p._context_function(ev); },false);

	grid_list_make_columns( p, p.cols )

	p.clear_grid = function () {
		sdump('D_GRID_LIST','p.clear_grid()\n');
		while( p.grid_rows.childNodes.length > 1 ) {
			p.grid_rows.removeChild( p.grid_rows.lastChild );
		}
	}

	p.add_rows = function (new_rows) { 
		sdump('D_GRID_LIST','p.add_rows()\n');
		return grid_list_add_rows(p,new_rows); 
	}

	p.remove_row_by_id = function (id) {
		sdump('D_GRID_LIST','p.remove_row_by_id()\n');
		return grid_list_remove_row_by_id(p,id); 
	}

	p.register_context_builder = function (f) {
		sdump('D_GRID_LIST','p.register_context_builder(' + f + ')\n');
		return p._context_function = f;
	}

	sdump('D_TRACE_EXIT',arg_dump(arguments));
	return p;
}

function grid_list_make_columns( p, cols ) {
	sdump('D_GRID_LIST',arg_dump(arguments,{2:'.length'}));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	var d = p.w.document;
	// cols[ idx ] = { 'id':???, 'label':???, 'primary':???, 'flex':??? }
	var header = p.w.document.createElement('row');
	p.grid_rows.appendChild( header );
	for (var i = 0; i < cols.length; i++) {
		var col = cols[i];
		sdump('D_GRID_LIST','Col ' + i + ' : ' + js2JSON( col ) + '\n');
		var gridcol = d.createElement( 'column' );
		p.grid_columns.appendChild( gridcol );
		for (var j in col) {
			gridcol.setAttribute( j, col[j] );
		}
		var th = p.w.document.createElement('label');
		header.appendChild( th );
		th.setAttribute('value', col.label);
		th.setAttribute('style','font-weight: bold;');
	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function grid_list_add_rows( p, new_rows ) {
	sdump('D_GRID_LIST',arg_dump(arguments,{2:'.length'}));
	sdump('D_TRACE_ENTER',arg_dump(arguments));
	for (var i = 0; i < new_rows.length; i++) {
		var new_row = new_rows[i];

		p.grid_rows.appendChild( new_row );

	}
	sdump('D_TRACE_EXIT',arg_dump(arguments));
}

function grid_list_remove_row_by_id( p, id ) {
	sdump('D_GRID_LIST',arg_dump(arguments));
	var row = p.grid_rows.getElementsByAttribute('id',id)[0];
	p.grid_rows.removeChild( row );
}
