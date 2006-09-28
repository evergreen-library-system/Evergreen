/* 
	Fieldmapper object table
*/

var ID_GEN = 1;



function drawFMObjectTable( args ) {

	var destination = args.dest;
	var obj = args.obj;

	if( typeof destination == 'string' ) 
		destination = $(destination);
	var builder = new FMObjectBuilder(obj, args);
	destination.appendChild(builder.build());
	return builder;
}


/* Constructor for the builder object */
function FMObjectBuilder( obj, args ) {
	this.obj		= obj;
	this.table	= elem('table');
	this.thead	= elem('thead');
	this.tbody	= elem('tbody');
	this.thead_tr = elem('tr');
	this.subtables = [];
	this.display = args.display;
	this.selectCol = args.selectCol;
	this.selectColName = args.selectColName;
	this.rows = [];
	if(!this.display) this.display = {};

	this.table.appendChild(this.thead);
	this.table.appendChild(this.tbody);
	this.thead.appendChild(this.thead_tr)

	addCSSClass(this.table, 'fm_table');
	addCSSClass(this.table, 'sortable');
	this.table.id = 'fm_table_' + (ID_GEN++);
}


FMObjectBuilder.prototype.getSelected = function() {
	var objs = [];
	for( var i = 0; i < this.rows.length; i++ ) {
		var r = $(this.rows[i]);
		if( $n(r,'selected').checked )
			objs.push(this.obj[i]);
	}
	return objs;
}

/* Builds the table */
FMObjectBuilder.prototype.build = function() {
	var o = this.obj;

	if( instanceOf(this.obj, Array) ) 
		o = this.obj[0];
	else this.obj = [this.obj];

	if( o ) {

		this.setKeys(o);
		if( this.selectCol )
			this.thead_tr.appendChild(elem('td',null,this.selectColName));
		for( var i = 0; i < this.keys.length; i++ ) 
			this.thead_tr.appendChild(elem('td',null,this.keys[i]));
	
		for( var i = 0; i < this.obj.length; i++ ) 
			this.buildObjectRow(this.obj[i]);
	}

	return this.table;
}


/* */
FMObjectBuilder.prototype.setKeys = function(o) {
	var sortme = false;
	if( this.display[o.classname] ) 
		this.keys = this.display[o.classname].fields;

	if(!this.keys && FM_TABLE_DISPLAY[o.classname])
		this.keys = FM_TABLE_DISPLAY[o.classname].fields;

	if(!this.keys) {
		this.keys = fmclasses[o.classname];
		sortme = true;
	}

	if(sortme) this.keys = this.keys.sort();
}

/* Inserts one row into the table to represent a single object */
FMObjectBuilder.prototype.buildObjectRow = function(obj) {
	var row = elem('tr');
	row.id = 'fm_table_' + (ID_GEN++);
	this.rows.push(row.id);

	if(this.selectCol) {
		var td = elem('td');
		td.appendChild(elem('input',{type:'checkbox',name:'selected'}));
		row.appendChild(td);
	}

	for( var i = 0; i < this.keys.length; i++ ) {
		var td = elem('td');	
		var data = obj[this.keys[i]]();
		this.fleshData(td, data, this.keys[i]);
		row.appendChild(td);
	}
	this.tbody.appendChild(row);
}

FMObjectBuilder.prototype.dataName = function(data) {
	var name;
	if( this.display[data.classname] ) 
		name = this.display[data.classname].name;

	if(!name && FM_TABLE_DISPLAY[data.classname])
		name = FM_TABLE_DISPLAY[data.classname].name;

	if(!name) name = 'id';

	return data[name]();
	return name;
}


FMObjectBuilder.prototype.fleshData = function(td, data, key) {
	if(data == null) data = '';

	if( typeof data == 'object' ) {
		var atext;

		if( data._isfieldmapper ) 
			atext = this.dataName(data);

		else if (instanceOf(data, Array) )
			atext = data.length;

		if( atext ) {

			var master = this;
			var expand = function () { 
				var buildme = true;
				var row = td.parentNode.nextSibling;
				if( row && row.getAttribute('subrow') == key) buildme = false;
				master.hideSubTables();
				if(buildme) master.buildSubTable(td, data, key);
			};

			var a = elem('a',{href:'javascript:void(0);'});
			a.onclick = expand;
			a.appendChild(text(atext));
			td.appendChild(a);

		} else {
			td.appendChild(text(''));
		}

	} else {
		td.appendChild(text( data ));
	}
}

FMObjectBuilder.prototype.hideSubTables = function() {

	/* clear out any existing subrows */
	for( var i = 0; i < this.tbody.childNodes.length; i++ ) {
		var r = this.tbody.childNodes[i];
		if( r.getAttribute('subrow') )
			this.tbody.removeChild(r);
	}

	/* un-style any selected tds */
	var tds = this.tbody.getElementsByTagName('td');
	for( i = 0; i < tds.length; i++ )
		removeCSSClass( tds[i], 'fm_selected' );
}

FMObjectBuilder.prototype.buildSubTable = function(td, obj, key) {

	var left = parseInt(td.offsetLeft);
	var div	= elem('div');
	var row	= elem('tr');
	var subtd= elem('td');

	if( td.parentNode.nextSibling ) 
		this.tbody.insertBefore(row, td.parentNode.nextSibling);
	else
		this.tbody.appendChild(row);

	row.appendChild(subtd);
	row.setAttribute('subrow', key);
	subtd.appendChild(div);

	addCSSClass(td, 'fm_selected');
	subtd.setAttribute('colspan',this.keys.length);
	if(this.selectCol)
		subtd.setAttribute('colspan',this.keys.length + 1);

	subtd.setAttribute('style', 'width: 100%; padding-left:'+left+'px;');
	var builder = drawFMObjectTable({dest:div, obj:obj, display:this.display});
	builder.table.setAttribute('style', 'width: auto;');
	addCSSClass(builder.table, 'fm_selected');

	var newleft = left - (builder.table.clientWidth / 2) + (td.clientWidth / 2);

	if( newleft < left ) {
		if( newleft < 0 ) newleft = 0;
		newleft = parseInt(newleft);
		var style = subtd.getAttribute('style');
		style = style.replace(new RegExp(left), newleft);
		subtd.setAttribute('style', style);
	}
}




