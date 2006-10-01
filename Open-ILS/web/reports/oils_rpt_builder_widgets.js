function oilsRptBuilderWidget(node) {
	this.init(node);
}

oilsRptBuilderWidget.prototype.init = function(node) {
	if(!node) return;
	this.node = node;
	_debug(this.node.id);

	this.selector = $n(this.node, 'selector');
//	this.widgetNode = $n(this.node, 'widget_td');
	var obj = this;
	this.selector.onchange = function() { 
		obj.showWidgets(
			obj.selector.options[obj.selector.selectedIndex]);
	}
	//this.hideWidgets();
}


/*
oilsRptBuilderWidget.prototype.hideWidgets = function(node) {
	if(!node) node = this.widgetNode;
	if( node.nodeType != 1 ) return;
	if( node.getAttribute('widget') ) {
		hideMe(node);
	} else {
		var cs = node.childNodes;
		for( var i = 0; cs && i < cs.length; i++ )
			this.hideWidgets(cs[i]);
	}
}


oilsRptBuilderWidget.prototype.showWidgets = function(opt) {
	_debug("showing widget with opt value: "+opt.value);
	this.hideWidgets();
	var widget = opt.getAttribute('widget');
	if( widget ) unHideMe($n(this.node, widget));
}
*/

oilsRptBuilderWidget.prototype.getCurrentOpt = function() {
	return this.selector.options[this.selector.selectedIndex];
}




/* ------------------------------------------------------------------------- */
oilsRptTFormManager.prototype = new oilsRptBuilderWidget();
oilsRptTFormManager.prototype.constructor = oilsRptTFormManager;
oilsRptTFormManager.baseClass = oilsRptBuilderWidget.prototype.constructor;
function oilsRptTFormManager(node) { this.init(node); }

/* displays the appropriate transforms for the given types and flags */
oilsRptTFormManager.prototype.build = function( dtype, show_agg, show_noagg ) {
	for( var i = 0; i < this.selector.options.length; i++ ) {
		var opt = this.selector.options[i];
		var t = opt.getAttribute('datatype');
		if( t && t != dtype ){
			hideMe(opt);
		} else {
			var ag = opt.getAttribute('aggregate');
			if( ag && show_agg )
				unHideMe(opt);
			else if( ag && ! show_agg )
				hideMe(opt)
			else if( !ag && show_noagg )
				unHideMe(opt);
			else hideMe(opt);
		}
	}
}

oilsRptTFormManager.prototype.getCurrentTForm = function() {
	var opt = this.getCurrentOpt();
	var data = {
		value		 : opt.value,
		datatype  : opt.getAttribute('datatype'),
		aggregate : opt.getAttribute('aggregate'),
	};
	//data.params = this.getWidgetParams(data);
	return data;
}


/*
oilsRptTFormManager.prototype.getWidgetParams = function(obj) {
	switch(obj.datatype) {
		case 'string' :
			switch(obj.value) {
				case 'substring':
					return [ 
						$n(this.widgetNode, 'string_substring_offset').value,
						$n(this.widgetNode, 'string_substring_length').value
					];
			}
	}
	return null;
}
*/




/* ------------------------------------------------------------------------- */

oilsRptOpManager.prototype = new oilsRptBuilderWidget();
oilsRptOpManager.prototype.constructor = oilsRptOpManager;
oilsRptOpManager.baseClass = oilsRptBuilderWidget.prototype.constructor;
function oilsRptOpManager(node) { this.init(node); }


