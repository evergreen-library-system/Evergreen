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
	this.moneySummaryRow = args.moneySummaryRow;
	this.selectColName = args.selectColName;
	this.selectAllName = args.selectAllName;
	this.selectNoneName = args.selectNoneName;
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
		if( $n(r,'selected') && $n(r,'selected').checked )
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
		if( this.selectCol ) {
			var obj = this;
			var td = elem('td',null,this.selectColName);

			var all = elem('a',{href:'javascript:void(0);','class':'fm_select_link' }, this.selectAllName);
			var none = elem('a',{href:'javascript:void(0);', 'class':'fm_select_link'}, this.selectNoneName);

			all.onclick = function(){obj.selectAll()};
			none.onclick = function(){obj.selectNone()};

			td.appendChild(all);
			td.appendChild(none);
			this.thead_tr.appendChild(td);
		}

		if (this.moneySummaryRow) {
			this.moneySummaryRow = elem('tr');

			if( this.selectCol )
				this.moneySummaryRow.appendChild(elem('td'));

			for( var i = 0; i < this.keys.length; i++ ) {
				var key = this.keys[i];

				var td = elem('td');
				td.setAttribute('name', this.table.id + key);

				if (this.money && grep(this.money,function(i){return (i==key)}) )
					td.appendChild(text('0.00'));

				this.moneySummaryRow.appendChild(td);
			}

			this.tbody.appendChild(this.moneySummaryRow);
		}

		for( var i = 0; i < this.keys.length; i++ ) 
			this.thead_tr.appendChild(elem('td',null,this.keys[i]));

		if ( this.sortdata ) {
			var sortdata = this.sortdata;
			this.obj.sort(function(a, b){
				var ret = 1;
				var left = a[sortdata[0]]().toLowerCase();
				var right = b[sortdata[0]]().toLowerCase();
				if (left == right) return 0;
				if (left < right)
					ret = -1;
				return ret * sortdata[1];
			});
		}
	
		for( var i = 0; i < this.obj.length; i++ ) 
			this.buildObjectRow(this.obj[i]);
	}

	return this.table;
}


FMObjectBuilder.prototype.selectAll = function() {
	for( var i = 0; i < this.rows.length; i++ ) {
		var r = $(this.rows[i]);
		$n(r,'selected').checked = true;
	}
}

FMObjectBuilder.prototype.selectNone = function() {
	for( var i = 0; i < this.rows.length; i++ ) {
		var r = $(this.rows[i]);
		$n(r,'selected').checked = false;
	}
}


/* */
FMObjectBuilder.prototype.setKeys = function(o) {
	var sortme = false;
	if( this.display[o.classname] ) {
		this.keys = this.display[o.classname].fields;
		this.bold = this.display[o.classname].bold;
		this.money = this.display[o.classname].money;
		this.sortdata = this.display[o.classname].sortdata;
	}

	if(!this.keys && FM_TABLE_DISPLAY[o.classname])
		this.keys = FM_TABLE_DISPLAY[o.classname].fields;

	if(!this.bold && FM_TABLE_DISPLAY[o.classname])
		this.bold = FM_TABLE_DISPLAY[o.classname].bold;

	if(!this.money && FM_TABLE_DISPLAY[o.classname])
		this.money = FM_TABLE_DISPLAY[o.classname].money;

	if(!this.sortdata && FM_TABLE_DISPLAY[o.classname])
		this.sortdata = FM_TABLE_DISPLAY[o.classname].sortdata;

	if(!this.keys) {
		this.keys = fmclasses[o.classname];
		sortme = true;
	}

	if(sortme) this.keys = this.keys.sort();
}

/* use this method to insert object rows after the table has been rendered */
FMObjectBuilder.prototype.add = function(obj) {
	this.obj.push(obj);
	this.buildObjectRow(obj);
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
		data = this.munge(data);
		this.fleshData(td, data, this.keys[i]);
		row.appendChild(td);
	}
	this.tbody.appendChild(row);
	if (this.moneySummaryRow) this.tbody.appendChild(this.moneySummaryRow);
}

FMObjectBuilder.prototype.munge = function(data) {
	if(!data) return;
	if(typeof data == 'string') {
		if( data.match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/) ) {
			data = data.replace(/T/,' ');
			data = data.replace(/:\d{2}-.*/,'');
		}
	}

	return data;
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
		if (this.money && grep(this.money,function(i){return (i==key)}) ) {
			td.setAttribute('align', 'right');
			data = parseFloat(data).toFixed(2);

			if (isNaN(data)) data = '0.00';

			if (this.moneySummaryRow) {
				var summary_td = $n(this.moneySummaryRow, this.table.id + key);
				summary_td.innerHTML = parseFloat(parseFloat(summary_td.innerHTML) + parseFloat(data)).toFixed(2);
			}
		}

		if( this.bold && grep(this.bold,function(i){return (i==key)}) ) {
			var span = elem('span',{'class':'fm_table_bold'}, data);
			td.appendChild(span);
		} else {
			td.appendChild(text( data ));
		}
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




