/* --------------------------------------------------------------------- 
	Represents a set of values, an inputWidget collects data and a 
	multi-select displays the data and allows the user to remove items
	--------------------------------------------------------------------- */
function oilsRptSetWidget(args) {
	this.node = args.node;
	this.inputWidget = new args.inputWidget(args);
	this.dest = elem('select',
		{multiple:'multiple','class':'oils_rpt_small_info_selector'});
}

oilsRptSetWidget.prototype.draw = function() {

	this.addButton = elem('input',{type:'submit',value:"Add"})
	this.delButton = elem('input',{type:'submit',value:"Del"})

	var obj = this;
	this.addButton.onclick = function() {
		obj.addDisplayItems(obj.inputWidget.getDisplayValue());
	}

	this.delButton.onclick = function(){obj.removeSelected()};

	removeChildren(this.node);
	this.inputWidget.draw();
	this.node.appendChild(elem('br'))
	this.node.appendChild(this.addButton);
	this.node.appendChild(this.delButton);
	this.node.appendChild(elem('br'))
	this.node.appendChild(this.dest);
}

oilsRptSetWidget.prototype.addDisplayItems = function(list) {
	if( list.constructor != Array ) list = [list];
	for(var i = 0; i < list.length; i++) {
		var item = list[i];

		/* no dupes */
		var exists = false;
		iterate(this.dest.options, 
			function(o){if(o.getAttribute('value') == item.value) {exists = true; return;}});
		if(exists) continue;

		_debug('Inserting SetWidget values ' + js2JSON(item));
		insertSelectorVal(this.dest, -1, item.label, this.objToStr(item.value));
	}
}

oilsRptSetWidget.prototype.removeSelected = function() {
	oilsDelSelectedItems(this.dest);
}

oilsRptSetWidget.prototype.getValue = function() {
	var vals = [];
	var obj = this;
	iterate(this.dest, function(i){vals.push(obj.strToObj(i.getAttribute('value')))});
	return vals;
}

oilsRptSetWidget.prototype.objToStr = function(obj) {
	if( typeof obj == 'string' ) return obj;
	//return ':'+obj.transform+':'+obj.params[0];
	var str = ':'+obj.transform;
	for( var i = 0; i < obj.params.length; i++ ) 
		str += ':' + obj.params[i];
	_debug("objToStr(): built string " + str);
	return str;

}

oilsRptSetWidget.prototype.strToObj = function(str) {
	if( str.match(/^:.*/) ) {
		var parts = str.split(/:/);
		_debug("strToObj(): " + str + ' : ' + parts);
		parts.shift();
		var tform = parts.shift();
		//var tform = str.replace(/^:(.*):.*/,'$1');
		//var param = str.replace(/^:.*:(.*)/,'$1');
		return { transform : tform, params : parts };
	}
	return str;
}


/* --------------------------------------------------------------------- 
	represents a widget that has start and end values.  start and end
	are gathered from start/end widgets
	--------------------------------------------------------------------- */
function oilsRptBetweenWidget(args) {
	this.node = args.node;
	this.startWidget = new args.startWidget(args);
	this.endWidget = new args.endWidget(args);
}
oilsRptBetweenWidget.prototype.draw = function() {
	removeChildren(this.node);
	this.startWidget.draw();
	this.node.appendChild(elem('hr'));
	this.node.appendChild(elem('div',
		{style:'text-align:center;width:100%;font-weight:bold'},' - And - '));
	this.node.appendChild(elem('hr'));
	this.endWidget.draw();
}
oilsRptBetweenWidget.prototype.getValue = function() {
	return [
		this.startWidget.getValue(),
		this.endWidget.getValue()
	];
}




/* --------------------------------------------------------------------- 
	ATOMIC WIDGETS
	--------------------------------------------------------------------- */


/* --------------------------------------------------------------------- 
	Atomic text input widget
	--------------------------------------------------------------------- */
function oilsRptTextWidget(args) {
	this.node = args.node;
	this.dest = elem('input',{type:'text',size:12});
	oilsRptMonitorWidget(this.dest);
}
oilsRptTextWidget.prototype.draw = function() {
	this.node.appendChild(this.dest);
}

/* returns the "real" value for the widget */
oilsRptTextWidget.prototype.getValue = function() {
	return this.dest.value;
}

/* returns the label and "real" value for the widget */
oilsRptTextWidget.prototype.getDisplayValue = function() {
	return { label : this.getValue(), value : this.getValue() };
}



/* --------------------------------------------------------------------- 
	Atomic bool input widget
	--------------------------------------------------------------------- */
function oilsRptBoolWidget(args) {
	this.node = args.node;
	this.selector = elem('select');
	insertSelectorVal(this.selector, -1,'True','t');
	insertSelectorVal(this.selector, -1,'False','f');
}

oilsRptBoolWidget.prototype.draw = function() {
	this.node.appendChild(this.selector);
}

/* returns the "real" value for the widget */
oilsRptBoolWidget.prototype.getValue = function() {
	return getSelectorVal(this.selector);
}

/* returns the label and "real" value for the widget */
oilsRptBoolWidget.prototype.getDisplayValue = function() {
	var val = getSelectorVal(this.selector);
	var label = 'True';
	if (val == 'f') labal = 'False';
	return { label : label, value : val };
}


/* If you monitor a text widget with this function, it 
	will style the input differently to indicate the
	field needs data.  If a regex is provided, it will
	style the field differently until the data matches 
	the regex.  The style comes from OILS_RPT_INVALID_DATA. */
function oilsRptMonitorWidget(input, regex) {
	addCSSClass(input, OILS_RPT_INVALID_DATA);
	var func = function() {
		var val = input.value;
		if(!val) {
			addCSSClass(input, OILS_RPT_INVALID_DATA);
		} else {
			if( regex ) {
				if( val && val.match(regex) ) 
					removeCSSClass(input, OILS_RPT_INVALID_DATA);
				else
					addCSSClass(input, OILS_RPT_INVALID_DATA);
			} else {
				removeCSSClass(input, OILS_RPT_INVALID_DATA);
			}
		}
	}

	input.onkeyup = func;
	input.onchange = func;
}




/* --------------------------------------------------------------------- 
	Atomic calendar widget
	--------------------------------------------------------------------- */
function oilsRptCalWidget(args) {
	this.node = args.node;
	this.calFormat = args.calFormat;
	this.input = elem('input',{type:'text',size:12});

	oilsRptMonitorWidget(this.input, args.regex);

	if( args.inputSize ) {
		this.input.setAttribute('size',args.inputSize);
		this.input.setAttribute('maxlength',args.inputSize);
	}
}

oilsRptCalWidget.prototype.draw = function() {
	this.button = DOM.generic_calendar_button.cloneNode(true);
	this.button.id = oilsNextId();
	this.input.id = oilsNextId();

	this.node.appendChild(this.button);
	this.node.appendChild(this.input);
	unHideMe(this.button);

	_debug('making calendar widget with format ' + this.calFormat);

	Calendar.setup({
		inputField	: this.input.id,
		ifFormat		: this.calFormat,
		button		: this.button.id,
		align			: "Tl",	
		singleClick	: true
	});
}

oilsRptCalWidget.prototype.getValue = function() {
	return this.input.value;
}

oilsRptCalWidget.prototype.getDisplayValue = function() {
	return { label : this.getValue(), value : this.getValue() };
}


/* --------------------------------------------------------------------- 
	Atomic org widget
	--------------------------------------------------------------------- */
function oilsRptOrgSelector(args) {
	this.node = args.node;
	this.selector = elem('select',
		{multiple:'multiple','class':'oils_rpt_small_info_selector'});
}

oilsRptOrgSelector.prototype.draw = function(org) {
	if(!org) org = globalOrgTree;
	var opt = insertSelectorVal( this.selector, -1, 
		org.shortname(), org.id(), null, findOrgDepth(org) );
	if( org.id() == oilsRptCurrentOrg )
		opt.selected = true;
	
	/* sometimes we need these choices 
	if( !isTrue(findOrgType(org.ou_type()).can_have_vols()) )
		opt.disabled = true;
		*/

	if( org.children() ) {
		for( var c = 0; c < org.children().length; c++ )
			this.draw(org.children()[c]);
	}
	this.node.appendChild(this.selector);
}

oilsRptOrgSelector.prototype.getValue = function() {
	var vals = [];
	iterate(this.selector, /* XXX this.selector.options?? */
		function(o){
			if( o.selected )
				vals.push(o.getAttribute('value'))
		}
	);
	return vals;
}

oilsRptOrgSelector.prototype.getDisplayValue = function() {
	var vals = [];
	iterate(this.selector,
		function(o){
			if( o.selected )
				vals.push({ label : o.innerHTML, value : o.getAttribute('value')});
		}
	);
	return vals;
}


/* --------------------------------------------------------------------- 
	Atomic age widget
	--------------------------------------------------------------------- */
function oilsRptAgeWidget(args) {
	this.node = args.node;
	this.count = elem('select');
	this.type = elem('select');
}

oilsRptAgeWidget.prototype.draw = function() {

	//insertSelectorVal(this.count, -1, ' -- Select One -- ', '');
	for( var i = 1; i < 25; i++ )
		insertSelectorVal(this.count, -1, i, i);

	//insertSelectorVal(this.type, -1, ' -- Select One -- ', '');
	insertSelectorVal(this.type, -1, rpt_strings.WIDGET_DAYS, 'days');
	insertSelectorVal(this.type, -1, rpt_strings.WIDGET_MONTHS, 'months');
	insertSelectorVal(this.type, -1, rpt_strings.WIDGET_YEARS, 'years');
	this.node.appendChild(this.count);
	this.node.appendChild(this.type);
}

oilsRptAgeWidget.prototype.getValue = function() {
	var count = getSelectorVal(this.count);
	var type = getSelectorVal(this.type);
	return count+''+type;
}

oilsRptAgeWidget.prototype.getDisplayValue = function() {
	var val = { value : this.getValue() };
	var label = getSelectorVal(this.count) + ' ';
	for( var i = 0; i < this.type.options.length; i++ ) {
		var opt = this.type.options[i];
		if( opt.selected )
			label += opt.innerHTML;
	}
	val.label = label;
	return val;
}



/* --------------------------------------------------------------------- 
	Atomic substring picker
	--------------------------------------------------------------------- */
function oilsRptSubstrWidget(args) {
	this.node = args.node
	this.data = elem('input',{type:'text',size:12})
	this.offset = elem('input',{type:'text',size:5})
	this.length = elem('input',{type:'text',size:5})
}

oilsRptSubstrWidget.prototype.draw = function() {
	this.node.appendChild(text('string: '))
	this.node.appendChild(this.data);
	this.node.appendChild(elem('br'));
	this.node.appendChild(text('offset: '))
	this.node.appendChild(this.offset);
	this.node.appendChild(elem('br'));
	this.node.appendChild(text('length: '))
	this.node.appendChild(this.length);
}

oilsRptSubstrWidget.prototype.getValue = function() {
	return {
		transform : 'substring',
		params : [ this.data.value, this.offset.value, this.length.value ]
	};
}

oilsRptSubstrWidget.prototype.getDisplayValue = function() {
	return {
		label : this.data.value + ' : ' + this.offset.value + ' : ' + this.length.value,
		value : this.getValue()
	};
}


/* --------------------------------------------------------------------- 
	Atomic number picker
	--------------------------------------------------------------------- */
function oilsRptNumberWidget(args) {
	this.node = args.node;
	this.size = args.size || 32;
	this.start = args.start;
	this.selector = elem('select');
}
oilsRptNumberWidget.prototype.draw = function() {
	//insertSelectorVal(this.selector, -1, ' -- Select One -- ', '');
	for( var i = this.start; i < (this.size + this.start); i++ )
		insertSelectorVal(this.selector, -1, i, i);
	this.node.appendChild(this.selector);
	var obj = this;
}

oilsRptNumberWidget.prototype.getValue = function() {
	return getSelectorVal(this.selector);
}

oilsRptNumberWidget.prototype.getDisplayValue = function() {
	return { label : this.getValue(), value : this.getValue() };
}


/* --------------------------------------------------------------------- 
	Relative dates widget
	-------------------------------------------------------------------- */

function oilsRptNullWidget(args) {
    this.node = args.node;
    this.type = args.type;
}
oilsRptNullWidget.prototype.draw = function() {}
oilsRptNullWidget.prototype.getValue = function() {
    return null;
}

function oilsRptTemplateWidget(args) {
    this.node = args.node;
    this.value = args.value;
}
oilsRptTemplateWidget.prototype.draw = function() {
    this.node.appendChild(text(''+this.value));
}

/* --------------------------------------------------------------------- 
	Relative dates widget
	-------------------------------------------------------------------- */
function oilsRptTruncPicker(args) {
	this.node = args.node;
	this.type = args.type;
	this.realSpan = elem('span');
	this.relSpan = elem('span');
	hideMe(this.relSpan);
	args.node = this.realSpan;
	this.calWidget = new oilsRptCalWidget(args);
	args.node = this.node;

	this.selector = elem('select');
	insertSelectorVal(this.selector,-1,rpt_strings.WIDGET_REAL_DATE,1);
	insertSelectorVal(this.selector,-1,rpt_strings.WIDGET_RELATIVE_DATE,2);

	this.numberPicker = 
		new oilsRptNumberWidget({node:this.relSpan,size:90,start:1});

	this.label = 'Day(s)';
	if(this.type == 'month') this.label = rpt_strings.WIDGET_MONTHS;
	if(this.type == 'quarter') this.label = rpt_strings.WIDGET_QUARTERS;
	if(this.type == 'year') this.label = rpt_strings.WIDGET_YEARS;
	if(this.type == 'date') this.label = rpt_strings.WIDGET_DAYS;
}

oilsRptTruncPicker.prototype.draw = function() {
	this.node.appendChild(this.selector);
	this.node.appendChild(this.realSpan);
	this.node.appendChild(this.relSpan);
	this.calWidget.draw();
	this.numberPicker.draw();
	this.relSpan.appendChild(text(this.label+' ago'));

	var obj = this;
	this.selector.onchange = function() {
		if( getSelectorVal(obj.selector) == 1 ) {
			unHideMe(obj.realSpan);
			hideMe(obj.relSpan);
		} else {
			unHideMe(obj.relSpan);
			hideMe(obj.realSpan);
		}
	}
}

oilsRptTruncPicker.prototype.getValue = function() {
	if( getSelectorVal(this.selector) == 2) {
		var val = this.numberPicker.getValue();
		var tform = 'relative_' + this.type;
		return { transform : tform, params : ['-'+val] };
	}
	return this.calWidget.getValue();
}

oilsRptTruncPicker.prototype.getDisplayValue = function() {
	if( getSelectorVal(this.selector) == 2) {
		var num = this.numberPicker.getValue();
		return { label : num +' '+this.label+' ago', value : this.getValue() };
	}
	return this.calWidget.getDisplayValue();
}


/* --------------------------------------------------------------------- 
	Atomic remote object picker
	--------------------------------------------------------------------- */

function oilsRptRemoteWidget(args) {
	this.node	= args.node;
	this.class	= args.class;
	this.field	= args.field;
	this.column = args.column;
	this.source = elem('select',
		{multiple:'multiple','class':'oils_rpt_small_info_selector'});
}

oilsRptRemoteWidget.prototype.draw = function() {
	var orgcol;
	iterate(oilsIDL[this.class].fields,
		function(i) {
			if(i.type == 'link' && i.class == 'aou') 
				orgcol = i.name;
		}
	);

	if(orgcol) _debug("found org column for remote widget: " + orgcol);

	var orgs = [];
	iterate(oilsRptMyOrgs,function(i){orgs.push(i.id());});
	var req = new Request(OILS_RPT_MAGIC_FETCH, SESSION, {
		hint:this.class,
		org_column : orgcol,
		org : orgs
	}); 

	var obj = this;
	this.node.appendChild(this.source);
	req.callback(function(r){obj.render(r.getResultObject())});
	req.send();
}

oilsRptRemoteWidget.prototype.render = function(objs) {
	for( var i = 0; i < objs.length; i++ ) {
		var obj = objs[i];
		var label = obj[this.field.selector]();
		var value = obj[this.column]();
		_debug("inserted remote object "+label + ' : ' + value);
		insertSelectorVal(this.source, -1, label, value);
	}
}

oilsRptRemoteWidget.prototype.getDisplayValue = function() {
	var vals = [];
	iterate(this.source,
		function(o){
			if( o.selected )
				vals.push({ label : o.innerHTML, value : o.getAttribute('value')});
		}
	);
	return vals;
}

oilsRptRemoteWidget.prototype.getValue = function() {
	var vals = [];
	iterate(this.source,
		function(o){
			if( o.selected )
				vals.push(o.getAttribute('value'))
		}
	);
	return vals;
}




/* --------------------------------------------------------------------- 
	CUSTOM WIDGETS
	--------------------------------------------------------------------- */

/* --------------------------------------------------------------------- 
	custom my-orgs picker 
	--------------------------------------------------------------------- */
function oilsRptMyOrgsWidget(node, orgid, maxorg) {
	_debug('fetching my orgs with max org of ' + maxorg);
	this.node = node;
	this.orgid = orgid;
	this.maxorg = maxorg || 1;
	this.active = true;
	if( maxorg < 1 ) {
		this.node.disabled = true;
		this.active = false;
	}
}

oilsRptMyOrgsWidget.prototype.draw = function() {
	if(!oilsRptMyOrgs) {
		var req = new Request(OILS_RPT_FETCH_ORG_FULL_PATH, this.orgid);
		var obj = this;
		req.callback(
			function(r) { obj.drawWidget(r.getResultObject()); }
		);
		req.send();
	} else {
		this.drawWidget(oilsRptMyOrgs);
	}
}

oilsRptMyOrgsWidget.prototype.drawWidget = function(orglist) {
	var sel = this.node;
	var started = false;
	oilsRptMyOrgs = orglist;
	for( var i = 0; i < orglist.length; i++ ) {
		var org = orglist[i];
		var opt = insertSelectorVal( this.node, -1, 
			org.name(), org.id(), null, findOrgDepth(org) );
		if( org.id() == this.orgid )
			opt.selected = true;
		if(!started) {
			if( org.id() == this.maxorg ) 
				started = true;
			else opt.disabled = true;
		}
	}
}

oilsRptMyOrgsWidget.prototype.getValue = function() {
	return getSelectorVal(this.node);
}


