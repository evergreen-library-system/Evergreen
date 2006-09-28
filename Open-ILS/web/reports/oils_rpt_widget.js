oilsRptSetSubClass('oilsRptWidget', 'oilsRptObject');
oilsRptWidget.OILS_RPT_TRANSFORM_WIDGET = 0;
oilsRptWidget.OILS_RPT_OPERATION_WIDGET = 1;

function oilsRptWidget(args) {
	this.init(args);
	this.dest = elem('input',{type:'text'});
}

oilsRptWidget.prototype.init = function(args) {
	if(!args) return;
	this.super.init();
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

oilsRptSetSubClass('oilsRptMultiWidget', 'oilsRptWidget');
function oilsRptMultiWidget(args) {
	this.init(args);
}

oilsRptMultiWidget.prototype.init = function(args) {
	if(!args) return;
	this.super.init(args);
	this.dest = elem('select',
		{multiple:'multiple','class':'oils_rpt_info_selector'});
	this.addButton = elem('button',null, 'Add');
	this.addButton = this.getSourceCollector();
}

oilsRptMultiWidget.prototype.getValue = function() {
	var vals = [];
	for( var i = 0; i < this.dest.options.length; i++ )
		vals.push(this.dest.options[i].value);
	return vals;
}

oilsRptMultiWidget.prototype.removeSelected = function() {
	oilsDeleteSelectedItems(this.dest);
}

oilsRptMultiWidget.prototype.addItem = function(name, val) {
	for( var i = 0; i < this.dest.options.length; i++ )
		if( this.dest.options[i].value == val ) 
			return;
	insertSelectorVal(this.dest, -1, name, val);
}

oilsRptMultiWidget.prototype.setSource = function(src) {
	this.source = src;
}

oilsRptMultiWidget.prototype.draw = function() {
	appendClear(this.node, this.source);
	appendClear(this.node, this.dest);
}


/* ----------------------------------------------------------- */

oilsRptSetSubClass('oilsRptInputMultiWidget', 'oilsRptMultiWidget');
function oilsRptInputMultiWidget(args) {
	this.init(args);
}
oilsRptInputMultiWidget.prototype.init = function(args) {
	if(!args) return;
	this.super.init(args);
	this.setSource(elem('input',{type:'text'}));
}

oilsRptInputMultiWidget.prototype.addItem = function(name, val) {
	this.super.addItem(name, val);
	this.source.value = "";
	this.source.focus();
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
	this.init(args);
}
oilsRptSelectorMultiWidget.prototype.init = function(args) {
	if(!args) return;
	this.super.init(args);
	this.setSource(
		elem('select',{multiple:multiple, 'class':'oils_rpt_info_selector'}));
}

oilsRptSelectorMultiWidget.prototype.getSourceCollector = function() {
	var obj = this;
	return function() {
		for( var i = 0; i < obj.source.options.length; i++ )
			obj.addItem(obj.source.options.name, obj.source.options.value);
	}
}

/* ----------------------------------------------------------- */

oilsRptSetSubClass('oilsRptRemoteWidget', 'oilsRptSelectorMultiWidget');
function oilsRptRemoteWidget(args) {
	this.init(args);
}
oilsRptRemoteWidget.prototype.init = function(args) {
	if(!args) return;
	this.super.init(args);
	this.selector = args.selector;
}

oilsRptRemoteWidget.prototype.draw = function() {
	this.fetch();
	this.super.draw();
}

oilsRptRemoteWidget.prototype.setFetch = function(func) {
	this.fetch = func;
}





