oilsRptSetSubClass('oilsRptParamEditor','oilsRptObject');
function oilsRptParamEditor(report, tbody) {
	this.tbody = tbody;
	this.report = report;
}


oilsRptParamEditor.prototype.recur = function() {
	//var cb = $n(DOM.oils_rpt_recur_editor_table,'oils_rpt_recur');
	var cb = DOM.oils_rpt_recur;
	return (cb.checked) ? 't' : 'f';
}

oilsRptParamEditor.prototype.recurInterval = function() {
	/*
	var count = getSelectorVal($n(DOM.oils_rpt_recur_editor_table,'oils_rpt_recur_count'));
	var intvl = getSelectorVal($n(DOM.oils_rpt_recur_editor_table,'oils_rpt_recur_interval_type'));
	*/
	var count = getSelectorVal(DOM.oils_rpt_recur_count);
	var intvl = getSelectorVal(DOM.oils_rpt_recur_interval_type);
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
		this.tbody.appendChild(row);
		$n(row, 'column').appendChild(text(oilsRptMakeLabel(par.path)));
		$n(row, 'transform').appendChild(text(OILS_RPT_TRANSFORMS[par.column.transform].label));
		$n(row, 'action').appendChild(text(OILS_RPT_FILTERS[par.op].label));
		par.widget = this.buildWidget(par, $n(row, 'widget'));
		par.widget.draw();
	}

    /** draw the pre-defined template params so the user will know
        what params are already set */
    var tparams = this.report.gatherTemplateParams();

	for( var p = 0; p < tparams.length; p++ ) {
		var par = tparams[p];
		var row = oilsRptParamEditor.row.cloneNode(true);
		this.tbody.appendChild(row);
		$n(row, 'column').appendChild(text(oilsRptMakeLabel(par.path)));
		$n(row, 'transform').appendChild(text(OILS_RPT_TRANSFORMS[par.column.transform].label));
		$n(row, 'action').appendChild(text(OILS_RPT_FILTERS[par.op].label));
		par.widget = this.buildWidget(par, $n(row, 'widget'));
		par.widget.draw();
	}
}

oilsRptParamEditor.prototype.buildWidget = function(param, node) {
	var transform = param.column.transform;
	var cls = oilsRptPathClass(param.path);
	var field = oilsRptFindField(oilsIDL[cls], oilsRptPathCol(param.path));
	var dtype = field.datatype;

	_debug("building widget with param class:" + cls + ' col: '+param.column.colname + ' op: '+ param.op);

	/* get the atomic widget from the datatype */
	var atomicWidget = oilsRptTextWidget;
	var widgetArgs	= {node:node};
	widgetArgs.calFormat = OILS_RPT_TRANSFORMS[transform].cal_format;
	widgetArgs.inputSize = OILS_RPT_TRANSFORMS[transform].input_size;
	widgetArgs.regex = OILS_RPT_TRANSFORMS[transform].regex;
    widgetArgs.value = param.value;

	switch(transform) {
		case 'date':
			widgetArgs.type = 'date';
			atomicWidget = oilsRptTruncPicker;
			break;
		case 'hour_trunc':
			widgetArgs.type = 'hour';
			atomicWidget = oilsRptTruncPicker;
			break;
		case 'month_trunc':
			widgetArgs.type = 'month';
			atomicWidget = oilsRptTruncPicker;
			break;
		case 'year_trunc':
			widgetArgs.type = 'year';
			atomicWidget = oilsRptTruncPicker;
			break;
		case 'date':
			atomicWidget = oilsRptCalWidget;
			break;
		case 'age':
			atomicWidget = oilsRptAgeWidget;
			break;
		case 'days_ago':	
			widgetArgs.size = 7;
			widgetArgs.start = 1;
			atomicWidget = oilsRptNumberWidget
			break;
		case 'months_ago':	
			widgetArgs.size = 12;
			widgetArgs.start = 1;
			atomicWidget = oilsRptNumberWidget
			break;
		case 'quarters_ago':	
			widgetArgs.size = 4;
			widgetArgs.start = 1;
			atomicWidget = oilsRptNumberWidget
			break;
		case 'years_ago':	
			widgetArgs.size = 20;
			widgetArgs.start = 1;
			atomicWidget = oilsRptNumberWidget
			break;
		case 'dow':
			widgetArgs.size = 7;
			widgetArgs.start = 0;
			atomicWidget = oilsRptNumberWidget
			break;
		case 'dom':
			widgetArgs.size = 31;
			widgetArgs.start = 1;
			atomicWidget = oilsRptNumberWidget
			break;
		case 'doy':
			widgetArgs.size = 365;
			widgetArgs.start = 1;
			atomicWidget = oilsRptNumberWidget
			break;
		case 'woy':
			widgetArgs.size = 52;
			widgetArgs.start = 1;
			atomicWidget = oilsRptNumberWidget
			break;
		case 'moy':
			widgetArgs.size = 12;
			widgetArgs.start = 1;
			atomicWidget = oilsRptNumberWidget
			break;
		case 'qoy':
			widgetArgs.size = 4;
			widgetArgs.start = 1;
			atomicWidget = oilsRptNumberWidget
			break;
		case 'hod':
			widgetArgs.size = 24;
			widgetArgs.start = 0;
			atomicWidget = oilsRptNumberWidget
			break;

		case 'substring':
			atomicWidget = oilsRptSubstrWidget
			break;
	}

	if( field.selector ) {
		atomicWidget = oilsRptRemoteWidget;
		widgetArgs.class = cls;
		widgetArgs.field = field;
		widgetArgs.column = param.column.colname;
	}

	switch(cls) {
		case 'aou':
			atomicWidget = oilsRptOrgSelector;
			break;
	}

	switch(dtype) {
		case 'bool':
			atomicWidget = oilsRptBoolWidget;
			break;

        case "org_unit":
            atomicWidget = oilsRptOrgSelector;
            break;
	}

    if(widgetArgs.value != undefined) 
        return new oilsRptTemplateWidget(widgetArgs);


	switch(param.op) {
		case 'in':
		case 'not in':
			widgetArgs.inputWidget = atomicWidget;
			return new oilsRptSetWidget(widgetArgs);
        case 'is':
        case 'is not':
        case 'is blank':
        case 'is not blank':
            return new oilsRptNullWidget(widgetArgs);
		case 'between':
		case 'not between':
			widgetArgs.startWidget = atomicWidget;
			widgetArgs.endWidget = atomicWidget;
			return new oilsRptBetweenWidget(widgetArgs);
		default:
			return new atomicWidget(widgetArgs);
	}

}





