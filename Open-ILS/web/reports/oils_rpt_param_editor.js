oilsRptSetSubClass('oilsRptParamEditor','oilsRptObject');
function oilsRptParamEditor(report, tbody) {
	this.tbody = tbody;
	this.report = report;
}


oilsRptParamEditor.prototype.recur = function() {
	var cb = $n(DOM.oils_rpt_recur_editor_table,'oils_rpt_recur');
	return (cb.checked) ? 't' : 'f';
}

oilsRptParamEditor.prototype.recurInterval = function() {
	var count = getSelectorVal($n(DOM.oils_rpt_recur_editor_table,'oils_rpt_recur_count'));
	var intvl = getSelectorVal($n(DOM.oils_rpt_recur_editor_table,'oils_rpt_recur_interval_type'));
	return count+''+intvl;
}

oilsRptParamEditor.prototype.draw = function() {
	var params = this.report.gatherParams();
	this.params = params;

	if(!oilsRptParamEditor.row)
		oilsRptParamEditor.row = 
			DOM.oils_rpt_param_editor_tbody.removeChild(
			$n(DOM.oils_rpt_param_editor_tbody, 'tr'));

	removeChildren(this.tbody);
	_debug(formatJSON(js2JSON(params)));
			
	for( var p = 0; p < params.length; p++ ) {
		var par = params[p];
		var row = oilsRptParamEditor.row.cloneNode(true);
		$n(row, 'object').appendChild(text(oilsRptMakeLabel(oilsRptPathRel(par.path))));
		$n(row, 'column').appendChild(text(par.column.colname));
		$n(row, 'transform').appendChild(text(par.column.transform));
		$n(row, 'action').appendChild(text(par.op));
		par.widget = this.buildWidget(par, $n(row, 'widget'));
		par.widget.draw();
		//this.buildRelWidget(par, row);
		this.tbody.appendChild(row);
	}
}


/* display the time-relative options if necessary */
/*
oilsRptParamEditor.prototype.buildRelWidget = function(par, row) {

	var field = oilsRptFindField(
		oilsIDL[oilsRptPathClass(par.path)], oilsRptPathCol(par.path));

	_debug('checking rel widget for datatype '+field.datatype);

	if(field.datatype != 'timestamp') return;
	if(par.op != '=') return;

	var dom = $n(row,'reldate_div');
	unHideMe(dom);
	par.relWidget = new oilsRptRelDatePicker({node:$n(dom,'reldate'),relative:true});
	par.relWidget.draw();
	var cb = $n(row,'choose_rel');
	cb.onclick = function() {
		par.relWidgetChecked = false;
		if( cb.checked ) par.relWidgetChecked = true;
	}
}
*/


oilsRptParamEditor.prototype.buildWidget = function(param, node) {
	var path = param.path.split(/-/);
	path.pop();
	var cls = path.pop();

	var field = oilsRptFindField(
		oilsIDL[oilsRptPathClass(param.path)], oilsRptPathCol(param.path));
	var dtype = field.datatype;
	var transform = param.column.transform;

	_debug("building widget with param class:" + cls + ' col: '+param.column.colname + ' op: '+ param.op);

	switch(transform) {

	}

	switch(param.op) {
		case 'in':
		case 'not in':
			/* special case the org tree selector  */
			if( cls == 'aou' ) {
				return new oilsRptOrgMultiSelect({node:node});
			} else {
				return new oilsRptInputMultiWidget({node:node});
			}
		case 'between':
			return new oilsRptMultiInputWidget({node:node});

		default:
			switch(dtype) {
				case 'timestamp':
					return new oilsRptWidget({node:node});
				default:
					return new oilsRptWidget({node:node});
			}
	}
}

//oilsRptParamEditor.prototype.get = function(param, node) {




