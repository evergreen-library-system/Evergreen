dump('entering util.list.js\n');

if (typeof main == 'undefined') main = {};
util.list = function (id) {

	this.node = document.getElementById(id);

	if (!this.node) throw('Could not find element ' + id);
	switch(this.node.nodeName) {
		case 'tree' : break;
		case 'richlistbox' :
		case 'listbox' : 
			throw(this.node.nodeName + ' not yet supported'); break;
		default: throw(this.node.nodeName + ' not supported'); break;
	}

	JSAN.use('util.error'); this.error = new util.error();

	return this;
};

util.list.prototype = {

	'init' : function (params) {

		if (typeof params.map_row_to_column == 'function') this.map_row_to_column = params.map_row_to_column;

		this.prebuilt = false;
		if (typeof params.prebuilt != 'undefined') this.prebuilt = params.prebuilt;

		if (typeof params.columns == 'undefined') throw('util.list.init: No columns');
		this.columns = params.columns;

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

	'append' : function (params) {
		switch (this.node.nodeName) {
			case 'tree' : this.append_to_tree(params); break;
			default: throw('NYI: Need .append() for ' + this.node.nodeName); break;
		}
	},

	'append_to_tree' : function (params) {

		if (typeof params.row == 'undefined') throw('util.list.append: Object must contain a row');

		dump('util.list.append: params = ' + js2JSON(params) + '\n');

		var treeitem = document.createElement('treeitem');
		this.treechildren.appendChild( treeitem );
		var treerow = document.createElement('treerow');
		treeitem.appendChild( treerow );

		dump('tree = ' + this.node + '  treechildren = ' + this.treechildren + '\n');
		dump('treeitem = ' + treeitem + '  treerow = ' + treerow + '\n');

		for (var i = 0; i < this.columns.length; i++) {
			var treecell = document.createElement('treecell');
			var label = '';
			if (typeof params.map_row_to_column == 'function')  {

				label = params.map_row_to_column(params.row,this.columns[i]);

			} else {

				if (typeof this.map_row_to_column == 'function') {

					label = this.map_row_to_column(params.row,this.columns[i]);
				}
			}
			treecell.setAttribute('label',label);
			treerow.appendChild( treecell );
			dump('treecell = ' + treecell + ' with label = ' + label + '\n');
		}

		return treeitem;
	}

}
dump('exiting util.list.js\n');
