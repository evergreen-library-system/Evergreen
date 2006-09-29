oilsRptSetSubClass('oilsRptParamEditor','oilsRptObject');
function oilsRptParamEditor(report, tbody) {
	this.tbody = tbody;
	this.report = report;
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
		$n(row, 'object').appendChild(text(oilsRptMakeLabel(par.relation)));
		$n(row, 'column').appendChild(par.column.colname);
		$n(row, 'transform').appendChild(text(par.column.transform));
		$n(row, 'action').appendChild(text(par.op));
		par.widget = this.buildWidget(par, $n(row, 'widget'));
		par.widget.draw();
		this.tbody.appendChild(row);
	}
}


oilsRptParamEditor.prototype.buildWidget = function(param, node) {
	var cls = param.relation.split(/-/).pop();
	_debug("building widget with param class:" + cls + ' col: '+param.column.colname + ' op: '+ param.op);
	switch(param.op) {
		case 'in':
		case 'not in':

			/* we have to special case org selection for now, 
				until we have generic object fetch support */
			if( cls == 'aou' ) {
				return new oilsRptOrgMultiSelect({node:node});
			} else {
				return new oilsRptOrgMultiSelect({node:node});
			}

		default:
			return new oilsRptWidget({node:node});
	}
}

//oilsRptParamEditor.prototype.get = function(param, node) {




