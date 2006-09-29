oilsRptSetSubClass('oilsRptParamEditor','oilsRptObject');
function oilsRptParamEditor(report, tbody) {
	this.tbody = tbody;
	this.report = report;
}


oilsRptParamEditor.prototype.draw = function() {
	var params = this.report.gatherParams();

	if(!oilsRptParamEditor.row)
		oilsRptParamEditor.row = 
			DOM.oils_rpt_param_editor_tbody.removeChild(
			$n(DOM.oils_rpt_param_editor_tbody, 'tr'));

	_debug(formatJSON(js2JSON(params)));
			
	for( var p = 0; p < params.length; p++ ) {
		var par = params[p];
		var row = oilsRptParamEditor.row.cloneNode(true);
		$n(row, 'object').appendChild(text(oilsRptMakeLabel(par.relation)));
		$n(row, 'column').appendChild(text(par.column.colname));
		$n(row, 'action').appendChild(text(par.op));
		this.buildWidget(par, $n(row, 'widget')).draw();
		this.tbody.appendChild(row);
	}
}


oilsRptParamEditor.prototype.buildWidget = function(param, node) {
	_debug("building widget with param op "+ param.op);
	switch(param.op) {
		default:
			return new oilsRptWidget({node:node});
	}
}



