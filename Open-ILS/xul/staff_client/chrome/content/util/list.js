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

	'init' : function (params) {

		JSAN.use('util.widgets');

		if (typeof params.map_row_to_column == 'function') this.map_row_to_column = params.map_row_to_column;
		if (typeof params.retrieve_row == 'function') this.retrieve_row = params.retrieve_row;

		this.prebuilt = false;
		if (typeof params.prebuilt != 'undefined') this.prebuilt = params.prebuilt;

		if (typeof params.columns == 'undefined') throw('util.list.init: No columns');
		this.columns = params.columns;

		switch(this.node.nodeName) {
			case 'tree' : this._init_tree(params); break;
			case 'listbox' : this._init_listbox(params); break;
			default: throw('NYI: Need ._init() for ' + this.node.nodeName); break;
		}
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
			function(ev) { obj.detect_visible(); },
			false
		);
		this.node.addEventListener(
			'click',
			function(ev) { obj.detect_visible(); },
			false
		);
		window.addEventListener(
			'resize',
			function(ev) { obj.detect_visible(); },
			false
		);
		obj.detect_visible_polling();	
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

	'clear' : function (params) {
		switch (this.node.nodeName) {
			case 'tree' : this._clear_tree(params); break;
			case 'listbox' : this._clear_listbox(params); break;
			default: throw('NYI: Need .clear() for ' + this.node.nodeName); break;
		}
		this.error.sdump('D_LIST','Clearing list ' + this.node.getAttribute('id') + '\n');
	},

	'_clear_tree' : function(params) {
		while (this.treechildren.lastChild) this.treechildren.removeChild( this.treechildren.lastChild );
	},

	'_clear_listbox' : function(params) {
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
		treechildren_node.appendChild( treeitem );
		var treerow = document.createElement('treerow');
		treeitem.appendChild( treerow );

		s += ('tree = ' + this.node + '  treechildren = ' + treechildren_node + '\n');
		s += ('treeitem = ' + treeitem + '  treerow = ' + treerow + '\n');

		if (typeof params.retrieve_row == 'function' || typeof this.retrieve_row == 'function') {

			treerow.setAttribute('retrieve_id',params.retrieve_id);
			obj.put_retrieving_label(treerow);
			treerow.addEventListener(
				'flesh',
				function() {
					//dump('fleshing = ' + params.retrieve_id + '\n');
					var row;

					params.row_node = treeitem;
					params.on_retrieve = function(row) {
						params.row = row;
						obj._map_row_to_treecell(params,treerow);
					}

					if (typeof params.retrieve_row == 'function') {

						row = params.retrieve_row( params );

					} else {

						if (typeof obj.retrieve_row == 'function') {

							row = obj.retrieve_row( params );

						}
					}

					treerow.setAttribute('retrieved','true');
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
					obj._map_row_to_treecell(params,treerow);
					treerow.setAttribute('retrieved','true');
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

		setTimeout( function() { obj.detect_visible(); }, 0 );

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
		try {
			var obj = this;
			//dump('detect_visible  obj.node = ' + obj.node + '\n');
			/* FIXME - this is a hack.. if the implementation of tree changes, this could break */
			var scrollbar = document.getAnonymousNodes( document.getAnonymousNodes(obj.node)[1] )[1];
			var curpos = scrollbar.getAttribute('curpos');
			var maxpos = scrollbar.getAttribute('maxpos');
			//alert('curpos = ' + curpos + ' maxpos = ' + maxpos + ' obj.curpos = ' + obj.curpos + ' obj.maxpos = ' + obj.maxpos + '\n');
			if ((curpos != obj.curpos) || (maxpos != obj.maxpos)) {
				if ( obj.auto_retrieve() > 0 ) {
					obj.curpos = curpos; obj.maxpos = maxpos;
				}
			}
		} catch(E) { alert(E); }
	},

	'detect_visible_polling' : function() {
		try {
			//alert('detect_visible_polling');
			var obj = this;
			obj.detect_visible();
			setTimeout(function() { try { obj.detect_visible_polling(); } catch(E) { alert(E); } },1);
		} catch(E) {
			alert(E);
		}
	},

	'auto_retrieve' : function () {
		try {
				//alert('auto_retrieve\n');
				var obj = this; var count = 0;
				var startpos = obj.node.treeBoxObject.getFirstVisibleRow();
				var endpos = obj.node.treeBoxObject.getLastVisibleRow();
				if (startpos > endpos) endpos = obj.node.treeBoxObject.getPageLength();
				//dump('startpos = ' + startpos + ' endpos = ' + endpos + '\n');
				for (var i = startpos; i < endpos + 2; i++) {
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
				return count;
		} catch(E) { alert(E); }
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

	'retrieve_selection' : function(params) {
		switch(this.node.nodeName) {
			case 'tree' : return this._retrieve_selection_from_tree(params); break;
			default: throw('NYI: Need ._retrieve_selection_from_() for ' + this.node.nodeName); break;
		}
	},

	'_retrieve_selection_from_tree' : function(params) {
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
		switch(this.node.nodeName) {
			case 'tree' : return this._dump_tree(params); break;
			default: throw('NYI: Need .dump() for ' + this.node.nodeName); break;
		}
	},

	'_dump_tree' : function(params) {
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

	'dump_retrieve_ids' : function(params) {
		switch(this.node.nodeName) {
			case 'tree' : return this._dump_retrieve_ids_tree(params); break;
			default: throw('NYI: Need .dump_retrieve_ids() for ' + this.node.nodeName); break;
		}
	},

	'_dump_retrieve_ids_tree' : function(params) {
		var dump = [];
		for (var i = 0; i < this.treechildren.childNodes.length; i++) {
			var treeitem = this.treechildren.childNodes[i];
			dump.push( treeitem.getAttribute('retrieve_id') );
		}
		return dump;
	},

}
dump('exiting util.list.js\n');
