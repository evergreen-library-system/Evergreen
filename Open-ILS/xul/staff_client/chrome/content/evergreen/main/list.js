dump('entering main/list.js\n');

if (typeof main == 'undefined') main = {};
main.list = function (id) {

	this.node = document.getElementById(id);

	if (!this.node) throw('Could not find element ' + id);
        if (this.node.nodeName != 'tree') throw(id + ' is not a tree');

	JSAN.use('util.error'); this.error = new util.error();

	return this;
};

main.list.prototype = {

	'init' : function (params) {

		if (typeof params.map_row_to_column == 'function') this.map_row_to_column = params.map_row_to_column;

		this.prebuilt = false;
		if (typeof params.prebuilt != 'undefined') this.prebuilt = params.prebuilt;

		if (typeof params.columns == 'undefined') throw('main.list.init: No columns');
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

		if (typeof params.row == 'undefined') throw('main.list.append: Object must contain a row');

		dump('main.list.append: params = ' + js2JSON(params) + '\n');

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
dump('exiting main/list.js\n');
