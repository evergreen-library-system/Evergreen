sdump('D_TRACE','Loading list_box.js\n');

function list_box_init( p ) {
	sdump('D_LIST_BOX',"TESTING: list_box.js: " + mw.G['main_test_variable'] + '\n');
	sdump('D_CONSTRUCTOR',arg_dump(arguments));

	p.listbox = p.w.document.createElement('listbox');
	p.node.appendChild( p.listbox );
	p.listbox.setAttribute('flex','1');
	p.listbox.setAttribute('seltype','multiple');

		var listhead = p.w.document.createElement('listhead');
		p.listbox.appendChild( listhead );

		var listcols = p.w.document.createElement('listcols');
		p.listbox.appendChild( listcols );

			/*if (window.navigator.userAgent.match( /Firefox/ ))*/  {
				//sdump('D_FIREFOX','Kludge: Adding extra listheader and listcol\n');
				var listheader = p.w.document.createElement('listheader');
				listhead.appendChild( listheader );
				listheader.setAttribute('label', '');
				var listcol = p.w.document.createElement('listcol');
				listcols.appendChild( listcol );
			}

			for (var i = 0; i < p.cols.length; i++ ) {

				var listheader = p.w.document.createElement('listheader');
				listhead.appendChild( listheader );
				listheader.setAttribute('label', p.cols[i].label);

				var listcol = p.w.document.createElement('listcol');
				listcols.appendChild( listcol );
				listcol.setAttribute('flex', p.cols[i].flex);
			}

	p.add_row = function (cols, params) {

		var listitem = p.w.document.createElement('listitem');
		p.listbox.appendChild( listitem );
		listitem.setAttribute('allowevents','true');
		listitem.setAttribute('style','border-bottom: black solid thin');
		for (var i in params) {
			listitem.setAttribute( i, params[i] );
		}

		/* if (window.navigator.userAgent.match( /Firefox/ )) */ {
			//sdump('D_FIREFOX','Kludge: Setting label on listitem\n');
			listitem.setAttribute('label',' ');
		}

		for (var i = 0; i < cols.length; i++) {

			try {
				listitem.appendChild( cols[i] );
			} catch(E) {
				sdump('D_ERROR', cols[i] + '\n' + E + '\n');
			}
		}
		
		return listitem;
	}

	p.clear_rows = function () {
		var count = p.listbox.getRowCount();
		for (var i = 0; i < count; i++) {
			p.listbox.removeChild( p.listbox.lastChild );
		}
	}

	return p;
}

