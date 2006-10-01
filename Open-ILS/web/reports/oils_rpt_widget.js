oilsRptSetSubClass('oilsRptWidget', 'oilsRptObject');
oilsRptWidget.OILS_RPT_TRANSFORM_WIDGET = 0;
oilsRptWidget.OILS_RPT_OPERATION_WIDGET = 1;

function oilsRptWidget(args) {
	this.initWidget(args);
	this.dest = elem('input',{type:'text'});
}

oilsRptWidget.prototype.initWidget = function(args) {
	if(!args) return;
	this.init();
	this.node	= args.node;
	this.type	= args.type;
	this.action = args.action;
	this.column	= args.column;
}

oilsRptWidget.prototype.getValue = function() {
	return this.dest.value;
}

oilsRptWidget.prototype.draw = function() {
	appendClear(this.node, this.dest);
}

/* ----------------------------------------------------------- */

/* multiple input boxes */
oilsRptSetSubClass('oilsRptMultiInputWidget', 'oilsRptWidget');
function oilsRptMultiInputWidget(args) {
	this.initInputWidget(args);
}

oilsRptMultiInputWidget.prototype.initInputWidget = function(args) {
	if(!args) return;
	this.initWidget(args);
	this.count = (args.count) ? args.count : 2;
	this.dest = [];
	for( var i = 0; i < this.count; i++ )
		this.dest.push(elem('input',{type:'text'}));
}

oilsRptMultiInputWidget.prototype.getValue = function() {
	var vals = [];
	for( var i = 0; i < this.dest.length; i++ )
		vals.push(this.dest.value);
	return vals;
}

oilsRptMultiInputWidget.prototype.draw = function() {
	removeChildren(this.node);
	for( var i = 0; i < this.dest.length; i++ ) {
		this.node.appendChild(this.label[i]);
		this.node.appendChild(this.dest[i]);
	}
}

oilsRptMultiInputWidget.prototype.setLabels = function(labels) {
	this.labels = labels;	
}




/* ----------------------------------------------------------- */

oilsRptSetSubClass('oilsRptMultiWidget', 'oilsRptWidget');
function oilsRptMultiWidget(args) {
	this.initMultiWidget(args);
}

oilsRptMultiWidget.prototype.initMultiWidget = function(args) {
	if(!args) return;
	this.initWidget(args);
	this.dest = elem('select',
		{multiple:'multiple','class':'oils_rpt_small_info_selector'});

	var obj = this;

	this.addButton = elem('input',{type:'submit',value:"Add"})
	this.addButton.onclick = this.getSourceCollector();
	this.delButton = elem('input',{type:'submit',value:"Del"})
	this.delButton.onclick = function(){obj.removeSelected()};
}

oilsRptMultiWidget.prototype.getValue = function() {
	var vals = [];
	for( var i = 0; i < this.dest.options.length; i++ )
		vals.push(this.dest.options[i].value);
	return vals;
}

oilsRptMultiWidget.prototype.removeSelected = function() {
	oilsDelSelectedItems(this.dest);
}

oilsRptMultiWidget.prototype.addItem = function(name, val) {
	for( var i = 0; i < this.dest.options.length; i++ ) {
		if( this.dest.options[i].value == val ) 
			return;
	}
	insertSelectorVal(this.dest, -1, name, val);
}

oilsRptMultiWidget.prototype.setSource = function(src) {
	this.source = src;
}

oilsRptMultiWidget.prototype.drawMultiWidget = function() {
	appendClear(this.node, this.source);
	this.node.appendChild(elem('br'))
	this.node.appendChild(this.addButton);
	this.node.appendChild(this.delButton);
	this.node.appendChild(elem('br'))
	this.node.appendChild(this.dest);
}


/* ----------------------------------------------------------- */

oilsRptSetSubClass('oilsRptInputMultiWidget', 'oilsRptMultiWidget');
function oilsRptInputMultiWidget(args) {
	this.initInputMultiWidget(args);
}
oilsRptInputMultiWidget.prototype.initInputMultiWidget = function(args) {
	if(!args) return;
	this.initMultiWidget(args);
	this.setSource(elem('input',{type:'text'}));
}

oilsRptInputMultiWidget.prototype.draw = function() {
	this.drawMultiWidget();
}

oilsRptInputMultiWidget.prototype.getSourceCollector = function() {
	var obj = this;
	return function() {
		obj.addItem(obj.source.value, obj.source.value);
	}
}


/* ----------------------------------------------------------- */

oilsRptSetSubClass('oilsRptSelectorMultiWidget', 'oilsRptMultiWidget');
function oilsRptSelectorMultiWidget(args) {
	this.initSelectorMultiWidget(args);
}
oilsRptSelectorMultiWidget.prototype.initSelectorMultiWidget = function(args) {
	if(!args) return;
	this.initMultiWidget(args);
	this.setSource(
		elem('select',{multiple:'multiple', 'class':'oils_rpt_small_info_selector'}));
}

oilsRptSelectorMultiWidget.prototype.getSourceCollector = function() {
	var obj = this;
	return function() {
		for( var i = 0; i < obj.source.options.length; i++ ) {
			if( obj.source.options[i].selected )
				obj.addItem(obj.source.options[i].innerHTML, 
					obj.source.options[i].value);
		}
	}
}

/* ----------------------------------------------------------- */

oilsRptSetSubClass('oilsRptRemoteWidget', 'oilsRptSelectorMultiWidget');
function oilsRptRemoteWidget(args) {
	this.initRemoteWidget(args);
}
oilsRptRemoteWidget.prototype.initRemoteWidget = function(args) {
	if(!args) return;
	this.initSelectorMultiWidget(args);
	this.selector = args.selector;
}

oilsRptRemoteWidget.prototype.draw = function() {
	this.fetch();
	//this.draw();
}

oilsRptRemoteWidget.prototype.setFetch = function(func) {
	this.fetch = func;
}


/* --------------------------------------------------------------------- */

/* standalone org widget */
function oilsRptMyOrgsWidget(node, orgid) {
	this.node = node;
	this.orgid = orgid;
}

oilsRptMyOrgsWidget.prototype.draw = function() {
	var req = new Request(OILS_RPT_FETCH_ORG_FULL_PATH, this.orgid);
	var obj = this;
	req.callback(
		function(r) { obj.drawWidget(r.getResultObject()); }
	);
	req.send();
}

oilsRptMyOrgsWidget.prototype.drawWidget = function(orglist) {
	var sel = this.node;
	for( var i = 0; i < orglist.length; i++ ) {
		var org = orglist[i];
		var opt = insertSelectorVal( this.node, -1, 
			org.name(), org.id(), null, findOrgDepth(org) );
		if( org.id() == this.orgid )
			opt.selected = true;
	}
}

oilsRptMyOrgsWidget.prototype.getValue = function() {
	return getSelectorVal(this.node);
}

/* --------------------------------------------------------------------- */

oilsRptSetSubClass('oilsRptOrgMultiSelect','oilsRptSelectorMultiWidget');
function oilsRptOrgMultiSelect(args) {
	this.initSelectorMultiWidget(args);
}

oilsRptOrgMultiSelect.prototype.draw = function(org) {
	if(!org) org = globalOrgTree;
	var opt = insertSelectorVal( this.source, -1, 
		org.shortname(), org.id(), null, findOrgDepth(org) );
	if( org.id() == oilsRptCurrentOrg )
		opt.selected = true;
	if( org.children() ) {
		for( var c = 0; c < org.children().length; c++ )
			this.draw(org.children()[c]);
	}
	this.drawMultiWidget();
}





