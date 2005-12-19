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

	'append' : function (params) {
		switch (this.node.nodeName) {
			case 'tree' : this._append_to_tree(params); break;
			case 'listbox' : this._append_to_listbox(params); break;
			default: throw('NYI: Need .append() for ' + this.node.nodeName); break;
		}
	},

	'_append_to_tree' : function (params) {

		if (typeof params.row == 'undefined') throw('util.list.append: Object must contain a row');

		var s = ('util.list.append: params = ' + js2JSON(params) + '\n');

		var treeitem = document.createElement('treeitem');
		this.treechildren.appendChild( treeitem );
		var treerow = document.createElement('treerow');
		treeitem.appendChild( treerow );

		s += ('tree = ' + this.node + '  treechildren = ' + this.treechildren + '\n');
		s += ('treeitem = ' + treeitem + '  treerow = ' + treerow + '\n');

		if (typeof params.retrieve_row == 'function' || typeof this.retrieve_row == 'function') {

			treerow.setAttribute('retrieve_id',params.retrieve_id);
			//FIXME//Make async and fire when row is visible in list
			var row;
			if (typeof params.retrieve_row == 'function') {

				row = params.retrieve_row( params );

			} else {

				if (typeof this.retrieve_row == 'function') {

					row = this.retrieve_row( params );

				}
			}
			params.row = row;
			this._map_row_to_treecell(params,treerow);

		} else {
			this._map_row_to_treecell(params,treerow);
		}
		this.error.sdump('D_LIST',s);

		return treeitem;
	},

	'_append_to_listbox' : function (params) {

		if (typeof params.row == 'undefined') throw('util.list.append: Object must contain a row');

		var s = ('util.list.append: params = ' + js2JSON(params) + '\n');

		var listitem = document.createElement('listitem');
		this.node.appendChild( listitem );

		s += ('listbox = ' + this.node + '  listitem = ' + listitem + '\n');

		if (typeof params.retrieve_row == 'function' || typeof this.retrieve_row == 'function') {

			listitem.setAttribute('retrieve_id',params.retrieve_id);
			//FIXME//Make async and fire when row is visible in list
			var row;
			if (typeof params.retrieve_row == 'function') {

				row = params.retrieve_row( params );

			} else {

				if (typeof this.retrieve_row == 'function') {

					row = this.retrieve_row( params );

				}
			}
			params.row = row;
			this._map_row_to_listcell(params,listitem);

		} else {
			this._map_row_to_listcell(params,listitem);
		}
		this.error.sdump('D_LIST',s);

		return listitem;

	},

	'_map_row_to_treecell' : function(params,treerow) {
		var s = '';
		for (var i = 0; i < this.columns.length; i++) {
			var treecell = document.createElement('treecell');
			var value = '';
			if (typeof params.map_row_to_column == 'function')  {

				label = params.map_row_to_column(params.row,this.columns[i]);

			} else {

				if (typeof this.map_row_to_column == 'function') {

					label = this.map_row_to_column(params.row,this.columns[i]);
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
			if (typeof value == 'string') {
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

}
dump('exiting util.list.js\n');
