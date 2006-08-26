dump('entering util.list.js\n');

if (typeof main == 'undefined') main = {};
util.list = function (id) {

	this.node = document.getElementById(id);

	if (!this.node) throw('Could not find element ' + id);
	switch(this.node.nodeName) {
		case 'listbox' : 
		case 'tree' : break;
		case 'richlistbox' :
			throw(this.node.nodeName + ' not yet supported'); break;
		default: throw(this.node.nodeName + ' not supported'); break;
	}

	JSAN.use('util.error'); this.error = new util.error();

	return this;
};

util.list.prototype = {

	'row_count' : { 'total' : 0, 'fleshed' : 0 },

	'init' : function (params) {

		var obj = this;

		JSAN.use('util.widgets');

		if (typeof params.map_row_to_column == 'function') obj.map_row_to_column = params.map_row_to_column;
		if (typeof params.retrieve_row == 'function') obj.retrieve_row = params.retrieve_row;

		obj.prebuilt = false;
		if (typeof params.prebuilt != 'undefined') obj.prebuilt = params.prebuilt;

		if (typeof params.columns == 'undefined') throw('util.list.init: No columns');
		obj.columns = params.columns;

		switch(obj.node.nodeName) {
			case 'tree' : obj._init_tree(params); break;
			case 'listbox' : obj._init_listbox(params); break;
			default: throw('NYI: Need ._init() for ' + obj.node.nodeName); break;
		}
	},

	'register_all_fleshed_callback' : function(f) {
		this.on_all_fleshed = f;
	},

	'_init_tree' : function (params) {
		var obj = this;
		if (this.prebuilt) {
		
			this.treechildren = this.node.lastChild;	
		
		} else {
			var treecols = document.createElement('treecols');
			this.node.appendChild(treecols);

			for (var i = 0; i < this.columns.length; i++) {
				var treecol = document.createElement('treecol');
				for (var j in this.columns[i]) {
					treecol.setAttribute(j,this.columns[i][j]);
				}
				treecols.appendChild(treecol);
				treecol.addEventListener(
					'click', 
					function(ev) {
						var sortDir = ev.target.getAttribute('sortDir') || 'desc';
						if (sortDir == 'desc') sortDir = 'asc'; else sortDir = 'desc';
						//alert('sort ' + ev.target.id + ' ' + sortDir);
						ev.target.setAttribute('sortDir',sortDir);
						obj._sort_tree(ev.target,sortDir);
					},
					false
				);
				var splitter = document.createElement('splitter');
				splitter.setAttribute('class','tree-splitter');
				treecols.appendChild(splitter);
			}

			var treechildren = document.createElement('treechildren');
			this.node.appendChild(treechildren);
			this.treechildren = treechildren;
		}
		if (typeof params.on_select == 'function') {
			this.node.addEventListener(
				'select',
				params.on_select,
				false
			);
		}
		if (typeof params.on_click == 'function') {
			this.node.addEventListener(
				'click',
				params.on_click,
				false
			);
		}
		/*
		this.node.addEventListener(
			'mousemove',
			function(ev) { obj.detect_visible(); },
			false
		);
		*/
		this.node.addEventListener(
			'keypress',
			function(ev) { obj.auto_retrieve(); },
			false
		);
		this.node.addEventListener(
			'click',
			function(ev) { obj.auto_retrieve(); },
			false
		);
		window.addEventListener(
			'resize',
			function(ev) { obj.auto_retrieve(); },
			false
		);
		/* FIXME -- find events on scrollbar to trigger this */
		obj.detect_visible_polling();	
		/*
		var scrollbar = document.getAnonymousNodes( document.getAnonymousNodes(this.node)[1] )[1];
		var slider = document.getAnonymousNodes( scrollbar )[2];
		alert('scrollbar = ' + scrollbar.nodeName + ' grippy = ' + slider.nodeName);
		scrollbar.addEventListener('click',function(){alert('sb click');},false);
		scrollbar.addEventListener('command',function(){alert('sb command');},false);
		scrollbar.addEventListener('scroll',function(){alert('sb scroll');},false);
		slider.addEventListener('click',function(){alert('slider click');},false);
		slider.addEventListener('command',function(){alert('slider command');},false);
		slider.addEventListener('scroll',function(){alert('slider scroll');},false);
		*/
		this.node.addEventListener('scroll',function(){ obj.auto_retrieve(); },false);

		this.restores_columns(params);
	},

	'_init_listbox' : function (params) {
		if (this.prebuilt) {
		} else {
			var listhead = document.createElement('listhead');
			this.node.appendChild(listhead);

			var listcols = document.createElement('listcols');
			this.node.appendChild(listcols);

			for (var i = 0; i < this.columns.length; i++) {
				var listheader = document.createElement('listheader');
				listhead.appendChild(listheader);
				var listcol = document.createElement('listcol');
				listcols.appendChild(listcol);
				for (var j in this.columns[i]) {
					listheader.setAttribute(j,this.columns[i][j]);
					listcol.setAttribute(j,this.columns[i][j]);
				};
			}
		}
	},

	'save_columns' : function (params) {
		var obj = this;
		switch (this.node.nodeName) {
			case 'tree' : this._save_columns_tree(params); break;
			default: throw('NYI: Need .save_columns() for ' + this.node.nodeName); break;
		}
	},

	'_save_columns_tree' : function (params) {
		var obj = this;
		try {
			var id = obj.node.getAttribute('id'); if (!id) {
				alert("FIXME: The columns for this list cannot be saved because the list has no id.");
				return;
			}
			var my_cols = {};
			var nl = obj.node.getElementsByTagName('treecol');
			for (var i = 0; i < nl.length; i++) {
				var col = nl[i];
				var col_id = col.getAttribute('id');
				if (!col_id) {
					alert('FIXME: A column in this list does not have an id and cannot be saved');
					continue;
				}
				var col_hidden = col.getAttribute('hidden'); 
				var col_width = col.getAttribute('width'); 
				var col_ordinal = col.getAttribute('ordinal'); 
				my_cols[ col_id ] = { 'hidden' : col_hidden, 'width' : col_width, 'ordinal' : col_ordinal };
			}
			netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
			JSAN.use('util.file'); var file = new util.file('tree_columns_for_'+window.escape(id));
			file.set_object(my_cols);
			file.close();
			alert('Columns saved.');
		} catch(E) {
			obj.error.standard_unexpected_error_alert('_save_columns_tree',E);
		}
	},

	'restores_columns' : function (params) {
		var obj = this;
		switch (this.node.nodeName) {
			case 'tree' : this._restores_columns_tree(params); break;
			default: throw('NYI: Need .restores_columns() for ' + this.node.nodeName); break;
		}
	},

	'_restores_columns_tree' : function (params) {
		var obj = this;
		try {
			var id = obj.node.getAttribute('id'); if (!id) {
				alert("FIXME: The columns for this list cannot be restored because the list has no id.");
				return;
			}

			netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
			JSAN.use('util.file'); var file = new util.file('tree_columns_for_'+window.escape(id));
			if (file._file.exists()) {
				var my_cols = file.get_object(); file.close();
				var nl = obj.node.getElementsByTagName('treecol');
				for (var i = 0; i < nl.length; i++) {
					var col = nl[i];
					var col_id = col.getAttribute('id');
					if (!col_id) {
						alert('FIXME: A column in this list does not have an id and cannot be saved');
						continue;
					}
					if (typeof my_cols[col_id] != 'undefined') {
						col.setAttribute('hidden',my_cols[col_id].hidden); 
						col.setAttribute('width',my_cols[col_id].width); 
						col.setAttribute('ordinal',my_cols[col_id].ordinal); 
					} else {
						obj.error.sdump('D_ERROR','WARNING: Column ' + col_id + ' did not have a saved state.');
					}
				}
			}
		} catch(E) {
			obj.error.standard_unexpected_error_alert('_restore_columns_tree',E);
		}
	},

	'clear' : function (params) {
		var obj = this;
		switch (this.node.nodeName) {
			case 'tree' : this._clear_tree(params); break;
			case 'listbox' : this._clear_listbox(params); break;
			default: throw('NYI: Need .clear() for ' + this.node.nodeName); break;
		}
		this.error.sdump('D_LIST','Clearing list ' + this.node.getAttribute('id') + '\n');
		this.row_count.total = 0;
		this.row_count.fleshed = 0;
		if (typeof obj.on_all_fleshed == 'function') {
			setTimeout( function() { obj.on_all_fleshed(); }, 0 );
		}
	},

	'_clear_tree' : function(params) {
		var obj = this;
		if (obj.error.sdump_levels.D_LIST_DUMP_ON_CLEAR) {
			obj.error.sdump('D_LIST_DUMP_ON_CLEAR',obj.dump());
		}
		if (obj.error.sdump_levels.D_LIST_DUMP_WITH_KEYS_ON_CLEAR) {
			obj.error.sdump('D_LIST_DUMP_WITH_KEYS_ON_CLEAR',obj.dump_with_keys());
		}
		while (obj.treechildren.lastChild) obj.treechildren.removeChild( obj.treechildren.lastChild );
	},

	'_clear_listbox' : function(params) {
		var obj = this;
		var items = [];
		var nl = this.node.getElementsByTagName('listitem');
		for (var i = 0; i < nl.length; i++) {
			items.push( nl[i] );
		}
		for (var i = 0; i < items.length; i++) {
			this.node.removeChild(items[i]);
		}
	},

	'append' : function (params) {
		var rnode;
		var obj = this;
		switch (this.node.nodeName) {
			case 'tree' : rnode = this._append_to_tree(params); break;
			case 'listbox' : rnode = this._append_to_listbox(params); break;
			default: throw('NYI: Need .append() for ' + this.node.nodeName); break;
		}
		if (rnode && params.attributes) {
			for (var i in params.attributes) {
				rnode.setAttribute(i,params.attributes[i]);
			}
		}
		this.row_count.total++;
		if (this.row_count.fleshed == this.row_count.total) {
			if (typeof this.on_all_fleshed == 'function') {
				setTimeout( function() { obj.on_all_fleshed(); }, 0 );
			}
		}
		return rnode;
	},

	'_append_to_tree' : function (params) {

		var obj = this;

		if (typeof params.row == 'undefined') throw('util.list.append: Object must contain a row');

		var s = ('util.list.append: params = ' + (params) + '\n');

		var treechildren_node = this.treechildren;

		if (params.node && params.node.nodeName == 'treeitem') {
			params.node.setAttribute('container','true'); /* params.node.setAttribute('open','true'); */
			if (params.node.lastChild.nodeName == 'treechildren') {
				treechildren_node = params.node.lastChild;
			} else {
				treechildren_node = document.createElement('treechildren');
				params.node.appendChild(treechildren_node);
			}
		}

		var treeitem = document.createElement('treeitem');
		treeitem.setAttribute('retrieve_id',params.retrieve_id);
		if (typeof params.to_top == 'undefined') {
			treechildren_node.appendChild( treeitem );
		} else {
			if (treechildren_node.firstChild) {
				treechildren_node.insertBefore( treeitem, treechildren_node.firstChild );
			} else {
				treechildren_node.appendChild( treeitem );
			}
		}
		var treerow = document.createElement('treerow');
		treeitem.appendChild( treerow );
		treerow.setAttribute('retrieve_id',params.retrieve_id);

		s += ('tree = ' + this.node + '  treechildren = ' + treechildren_node + '\n');
		s += ('treeitem = ' + treeitem + '  treerow = ' + treerow + '\n');

		if (typeof params.retrieve_row == 'function' || typeof this.retrieve_row == 'function') {

			obj.put_retrieving_label(treerow);
			treerow.addEventListener(
				'flesh',
				function() {

					if (treerow.getAttribute('retrieved') == 'true') return; /* already running */

					treerow.setAttribute('retrieved','true');

					//dump('fleshing = ' + params.retrieve_id + '\n');

					function inc_fleshed() {
						if (treerow.getAttribute('fleshed') == 'true') return; /* already fleshed */
						treerow.setAttribute('fleshed','true');
						obj.row_count.fleshed++;
						if (obj.row_count.fleshed == obj.row_count.total) {
							if (typeof obj.on_all_fleshed == 'function') {
								setTimeout( function() { obj.on_all_fleshed(); }, 0 );
							}
						}
					}

					params.row_node = treeitem;
					params.on_retrieve = function(p) {
						try {
							p.row = params.row;
							obj._map_row_to_treecell(p,treerow);
							inc_fleshed();
						} catch(E) {
							alert('fixme2: ' + E);
						}
					}

					if (typeof params.retrieve_row == 'function') {

						params.retrieve_row( params );

					} else if (typeof obj.retrieve_row == 'function') {

							obj.retrieve_row( params );

					} else {
					
							inc_fleshed();
					}
				},
				false
			);
			/*
			setTimeout(
				function() {
					util.widgets.dispatch('flesh',treerow);
				}, 0
			);
			*/
		} else {
			obj.put_retrieving_label(treerow);
			treerow.addEventListener(
				'flesh',
				function() {
					//dump('fleshing anon\n');
					if (treerow.getAttribute('fleshed') == 'true') return; /* already fleshed */
					obj._map_row_to_treecell(params,treerow);
					treerow.setAttribute('retrieved','true');
					treerow.setAttribute('fleshed','true');
					obj.row_count.fleshed++;
					if (obj.row_count.fleshed == obj.row_count.total) {
						if (typeof obj.on_all_fleshed == 'function') {
							setTimeout( function() { obj.on_all_fleshed(); }, 0 );
						}
					}
				},
				false
			);
			/*
			setTimeout(
				function() {
					util.widgets.dispatch('flesh',treerow);
				}, 0
			);
			*/
		}
		this.error.sdump('D_LIST',s);

		setTimeout( function() { obj.auto_retrieve(); }, 0 );

		return treeitem;
	},

	'put_retrieving_label' : function(treerow) {
		var obj = this;
		try {
			/*
			var cols_idx = 0;
			dump('put_retrieving_label.  columns = ' + js2JSON(obj.columns) + '\n');
			while( obj.columns[cols_idx] && obj.columns[cols_idx].hidden && obj.columns[cols_idx].hidden == 'true') {
				dump('\t' + cols_idx);
				var treecell = document.createElement('treecell');
				treerow.appendChild(treecell);
				cols_idx++;
			}
			*/
			for (var i = 0; i < obj.columns.length; i++) {
			var treecell = document.createElement('treecell'); treecell.setAttribute('label','Retrieving...');
			treerow.appendChild(treecell);
			}
			/*
			dump('\t' + cols_idx + '\n');
			*/
		} catch(E) {
			alert(E);
		}
	},

	'detect_visible' : function() {
		var obj = this;
		try {
			//dump('detect_visible  obj.node = ' + obj.node + '\n');
			/* FIXME - this is a hack.. if the implementation of tree changes, this could break */
			try {
				var scrollbar = document.getAnonymousNodes( document.getAnonymousNodes(obj.node)[1] )[1];
				var curpos = scrollbar.getAttribute('curpos');
				var maxpos = scrollbar.getAttribute('maxpos');
				//alert('curpos = ' + curpos + ' maxpos = ' + maxpos + ' obj.curpos = ' + obj.curpos + ' obj.maxpos = ' + obj.maxpos + '\n');
				if ((curpos != obj.curpos) || (maxpos != obj.maxpos)) {
					if ( obj.auto_retrieve() > 0 ) {
						obj.curpos = curpos; obj.maxpos = maxpos;
					}
				}
			} catch(E) {
				obj.error.sdump('D_XULRUNNER', 'List implementation changed? ' + E);
			}
		} catch(E) { obj.error.sdump('D_ERROR',E); }
	},

	'detect_visible_polling' : function() {
		try {
			//alert('detect_visible_polling');
			var obj = this;
			obj.detect_visible();
			setTimeout(function() { try { obj.detect_visible_polling(); } catch(E) { alert(E); } },2000);
		} catch(E) {
			alert(E);
		}
	},


	'auto_retrieve' : function(params) {
		var obj = this;
		switch (this.node.nodeName) {
			case 'tree' : obj._auto_retrieve_tree(params); break;
			default: throw('NYI: Need .auto_retrieve() for ' + obj.node.nodeName); break;
		}
	},

	'_auto_retrieve_tree' : function (params) {
		var obj = this;
		if (!obj.auto_retrieve_in_progress) {
			obj.auto_retrieve_in_progress = true;
			setTimeout(
				function() {
					try {
							//alert('auto_retrieve\n');
							var count = 0;
							var startpos = obj.node.treeBoxObject.getFirstVisibleRow();
							var endpos = obj.node.treeBoxObject.getLastVisibleRow();
							if (startpos > endpos) endpos = obj.node.treeBoxObject.getPageLength();
							//dump('startpos = ' + startpos + ' endpos = ' + endpos + '\n');
							for (var i = startpos; i < endpos + 4; i++) {
								try {
									//dump('trying index ' + i + '\n');
									var item = obj.node.contentView.getItemAtIndex(i).firstChild;
									if (item && item.getAttribute('retrieved') != 'true' ) {
										//dump('\tgot an unfleshed item = ' + item + ' = ' + item.nodeName + '\n');
										util.widgets.dispatch('flesh',item); count++;
									}
								} catch(E) {
									//dump(i + ' : ' + E + '\n');
								}
							}
							obj.auto_retrieve_in_progress = false;
							return count;
					} catch(E) { alert(E); }
				}, 1
			);
		}
	},

	'full_retrieve' : function(params) {
		var obj = this;
		switch (this.node.nodeName) {
			case 'tree' : obj._full_retrieve_tree(params); break;
			default: throw('NYI: Need .full_retrieve() for ' + obj.node.nodeName); break;
		}
	},

	'_full_retrieve_tree' : function(params) {
		var obj = this;
		try {
			if (obj.row_count.total == obj.row_count.fleshed) {
				//alert('Full retrieve... tree seems to be in sync\n' + js2JSON(obj.row_count));
				if (typeof obj.on_all_fleshed == 'function') {
					setTimeout( function() { obj.on_all_fleshed(); }, 0 );
				} else {
					alert('.full_retrieve called with no callback?');
				}
			} else {
				//alert('Full retrieve... syncing tree' + js2JSON(obj.row_count));
				JSAN.use('util.widgets');
				var nodes = obj.treechildren.childNodes;
				for (var i = 0; i < nodes.length; i++) {
					util.widgets.dispatch('flesh',nodes[i].firstChild);
				}
			}
		} catch(E) {
			obj.error.standard_unexpected_error_alert('_full_retrieve_tree',E);
		}
	},

	'_append_to_listbox' : function (params) {

		var obj = this;

		if (typeof params.row == 'undefined') throw('util.list.append: Object must contain a row');

		var s = ('util.list.append: params = ' + (params) + '\n');

		var listitem = document.createElement('listitem');

		s += ('listbox = ' + this.node + '  listitem = ' + listitem + '\n');

		if (typeof params.retrieve_row == 'function' || typeof this.retrieve_row == 'function') {

			setTimeout(
				function() {
					listitem.setAttribute('retrieve_id',params.retrieve_id);
					//FIXME//Make async and fire when row is visible in list
					var row;

					params.row_node = listitem;
					params.on_retrieve = function(row) {
						params.row = row;
						obj._map_row_to_listcell(params,listitem);
						obj.node.appendChild( listitem );
					}

					if (typeof params.retrieve_row == 'function') {

						row = params.retrieve_row( params );

					} else {

						if (typeof obj.retrieve_row == 'function') {

							row = obj.retrieve_row( params );

						}
					}
				}, 0
			);
		} else {
			this._map_row_to_listcell(params,listitem);
			this.node.appendChild( listitem );
		}

		this.error.sdump('D_LIST',s);
		return listitem;

	},

	'_map_row_to_treecell' : function(params,treerow) {
		var obj = this;
		var s = '';
		util.widgets.remove_children(treerow);
		for (var i = 0; i < this.columns.length; i++) {
			var treecell = document.createElement('treecell');
			var label = '';
			if (params.skip_columns && (params.skip_columns.indexOf(i) != -1)) {
				treecell.setAttribute('label',label);
				treerow.appendChild( treecell );
				s += ('treecell = ' + treecell + ' with label = ' + label + '\n');
				continue;
			}
			if (params.skip_all_columns_except && (params.skip_all_columns_except.indexOf(i) == -1)) {
				treecell.setAttribute('label',label);
				treerow.appendChild( treecell );
				s += ('treecell = ' + treecell + ' with label = ' + label + '\n');
				continue;
			}
			if (typeof params.map_row_to_column == 'function')  {

				label = params.map_row_to_column(params.row,this.columns[i]);

			} else {

				if (typeof this.map_row_to_column == 'function') {

					label = this.map_row_to_column(params.row,this.columns[i]);

				} else {

					throw('No map_row_to_column function');

				}
			}
			treecell.setAttribute('label',label);
			treerow.appendChild( treecell );
			s += ('treecell = ' + treecell + ' with label = ' + label + '\n');
		}
		this.error.sdump('D_LIST',s);
	},

	'_map_row_to_listcell' : function(params,listitem) {
		var obj = this;
		var s = '';
		for (var i = 0; i < this.columns.length; i++) {
			var value = '';
			if (typeof params.map_row_to_column == 'function')  {

				value = params.map_row_to_column(params.row,this.columns[i]);

			} else {

				if (typeof this.map_row_to_column == 'function') {

					value = this.map_row_to_column(params.row,this.columns[i]);
				}
			}
			if (typeof value == 'string' || typeof value == 'number') {
				var listcell = document.createElement('listcell');
				listcell.setAttribute('label',value);
				listitem.appendChild(listcell);
				s += ('listcell = ' + listcell + ' with label = ' + value + '\n');
			} else {
				listitem.appendChild(value);
				s += ('listcell = ' + value + ' is really a ' + value.nodeName + '\n');
			}
		}
		this.error.sdump('D_LIST',s);
	},

	'select_all' : function(params) {
		var obj = this;
		switch(this.node.nodeName) {
			case 'tree' : return this._select_all_from_tree(params); break;
			default: throw('NYI: Need ._select_all_from_() for ' + this.node.nodeName); break;
		}
	},

	'_select_all_from_tree' : function(params) {
		var obj = this;
		this.node.view.selection.selectAll();
	},

	'retrieve_selection' : function(params) {
		var obj = this;
		switch(this.node.nodeName) {
			case 'tree' : return this._retrieve_selection_from_tree(params); break;
			default: throw('NYI: Need ._retrieve_selection_from_() for ' + this.node.nodeName); break;
		}
	},

	'_retrieve_selection_from_tree' : function(params) {
		var obj = this;
		var list = [];
		var start = new Object();
		var end = new Object();
		var numRanges = this.node.view.selection.getRangeCount();
		for (var t=0; t<numRanges; t++){
			this.node.view.selection.getRangeAt(t,start,end);
			for (var v=start.value; v<=end.value; v++){
				var i = this.node.contentView.getItemAtIndex(v);
				list.push( i );
			}
		}
		return list;
	},

	'dump' : function(params) {
		var obj = this;
		switch(this.node.nodeName) {
			case 'tree' : return this._dump_tree(params); break;
			default: throw('NYI: Need .dump() for ' + this.node.nodeName); break;
		}
	},

	'_dump_tree' : function(params) {
		var obj = this;
		var dump = [];
		for (var i = 0; i < this.treechildren.childNodes.length; i++) {
			var row = [];
			var treeitem = this.treechildren.childNodes[i];
			var treerow = treeitem.firstChild;
			for (var j = 0; j < treerow.childNodes.length; j++) {
				row.push( treerow.childNodes[j].getAttribute('label') );
			}
			dump.push( row );
		}
		return dump;
	},

	'dump_with_keys' : function(params) {
		var obj = this;
		switch(this.node.nodeName) {
			case 'tree' : return this._dump_tree_with_keys(params); break;
			default: throw('NYI: Need .dump_with_keys() for ' + this.node.nodeName); break;
		}

	},

	'_dump_tree_with_keys' : function(params) {
		var obj = this;
		var dump = [];
		for (var i = 0; i < this.treechildren.childNodes.length; i++) {
			var row = {};
			var treeitem = this.treechildren.childNodes[i];
			var treerow = treeitem.firstChild;
			for (var j = 0; j < treerow.childNodes.length; j++) {
				row[ obj.columns[j].id ] = treerow.childNodes[j].getAttribute('label');
			}
			dump.push( row );
		}
		return dump;
	},

	'dump_selected_with_keys' : function(params) {
		var obj = this;
		switch(this.node.nodeName) {
			case 'tree' : return this._dump_tree_selection_with_keys(params); break;
			default: throw('NYI: Need .dump_selection_with_keys() for ' + this.node.nodeName); break;
		}

	},

	'_dump_tree_selection_with_keys' : function(params) {
		var obj = this;
		var dump = [];
		var list = obj._retrieve_selection_from_tree();
		for (var i = 0; i < list.length; i++) {
			var row = {};
			var treeitem = list[i];
			var treerow = treeitem.firstChild;
			for (var j = 0; j < treerow.childNodes.length; j++) {
				var value = treerow.childNodes[j].getAttribute('label');
				//FIXME
				//if (params.skip_hidden_columns) if (obj.node.firstChild.childNodes[j].getAttribute('hidden')) continue;
				var id = obj.columns[j].id; if (params.labels_instead_of_ids) id = obj.columns[j].label;
				row[ id ] = value;
			}
			dump.push( row );
		}
		return dump;
	},

	'clipboard' : function() {
		try {
			var obj = this;
			var dump = obj.dump_selected_with_keys({'skip_hidden_columns':true,'labels_instead_of_ids':true});
			JSAN.use('OpenILS.data'); var data = new OpenILS.data(); data.stash_retrieve();
			data.list_clipboard = dump; data.stash('list_clipboard');
			JSAN.use('util.window'); var win = new util.window();
			win.open(urls.XUL_LIST_CLIPBOARD,'list_clipboard','chrome,resizable,modal');
		} catch(E) {
			this.error.standard_unexpected_error_alert('clipboard',E);
		}
	},

	'dump_retrieve_ids' : function(params) {
		var obj = this;
		switch(this.node.nodeName) {
			case 'tree' : return this._dump_retrieve_ids_tree(params); break;
			default: throw('NYI: Need .dump_retrieve_ids() for ' + this.node.nodeName); break;
		}
	},

	'_dump_retrieve_ids_tree' : function(params) {
		var obj = this;
		var dump = [];
		for (var i = 0; i < this.treechildren.childNodes.length; i++) {
			var treeitem = this.treechildren.childNodes[i];
			dump.push( treeitem.getAttribute('retrieve_id') );
		}
		return dump;
	},

	'_sort_tree' : function(col,sortDir) {
		var obj = this;
		try {
			if (obj.node.getAttribute('no_sort')) {
				return;
			}
			if (obj.on_all_fleshed) {
				alert('This list is busy rendering/retrieving data.');
				return;
			}
			var col_pos;
			for (var i = 0; i < obj.columns.length; i++) { 
				if (obj.columns[i].id == col.id) col_pos = function(a){return a;}(i); 
			}
			obj.on_all_fleshed =
				function() {
					try {
						JSAN.use('util.money');
						var rows = [];
						var treeitems = obj.treechildren.childNodes;
						for (var i = 0; i < treeitems.length; i++) {
							var treeitem = treeitems[i];
							var treerow = treeitem.firstChild;
							var treecell = treerow.childNodes[ col_pos ];
							value = ( { 'value' : treecell ? treecell.getAttribute('label') : '', 'node' : treeitem } );
							rows.push( value );
						}
						rows = rows.sort( function(a,b) { 
							a = a.value; b = b.value; 
							if (col.getAttribute('sort_type')) {
								switch(col.getAttribute('sort_type')) {
									case 'number' :
										a = Number(a); b = Number(b);
									break;
									case 'money' :
										a = util.money.dollars_float_to_cents_integer(a);
										b = util.money.dollars_float_to_cents_integer(b);
									break;
									case 'title' : /* special case for "a" and "the".  doesn't use marc 245 indicator */
										a = String( a ).toUpperCase().replace( /^(THE|A)\s+/, '' );
										b = String( b ).toUpperCase().replace( /^(THE|A)\s+/, '' );
									break;
									default:
										a = String( a ).toUpperCase();
										b = String( a ).toUpperCase();
									break;
								}
							}
							if (a < b) return -1; 
							if (a > b) return 1; 
							return 0; 
						} );
						if (sortDir == 'asc') rows = rows.reverse();
						while(obj.treechildren.lastChild) obj.treechildren.removeChild( obj.treechildren.lastChild );
						for (var i = 0; i < rows.length; i++) {
							obj.treechildren.appendChild( rows[i].node );
						}
					} catch(E) {
						obj.error.standard_unexpected_error_alert('sorting',E); 
					}
					setTimeout(function(){ obj.on_all_fleshed = null; },0);
				}
			obj.full_retrieve();
		} catch(E) {
			obj.error.standard_unexpected_error_alert('pre sorting', E);
		}
	},

}
dump('exiting util.list.js\n');
