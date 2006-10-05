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
		this.tbody.appendChild(row);
		$n(row, 'object').appendChild(text(oilsRptMakeLabel(oilsRptPathRel(par.path))));
		$n(row, 'column').appendChild(text(par.column.colname));
		$n(row, 'transform').appendChild(text(par.column.transform));
		$n(row, 'action').appendChild(text(par.op));
		par.widget = this.buildWidget(par, $n(row, 'widget'));
		par.widget.draw();
		//this.buildRelWidget(par, row);
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

	switch(transform) {
		case 'hour_trunc':
		case 'month_trunc':
		case 'year_trunc':
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
			widgetArgs.start = 1;
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
	}

	switch(cls) {
		case 'aou':
			atomicWidget = oilsRptOrgSelector;
			break;
	}

	switch(param.op) {
		case 'in':
		case 'not in':
			widgetArgs.inputWidget = atomicWidget;
			return new oilsRptSetWidget(widgetArgs);
		case 'between':
		case 'not between':
			widgetArgs.startWidget = atomicWidget;
			widgetArgs.endWidget = atomicWidget;
			return new oilsRptBetweenWidget(widgetArgs);
		default:
			return new oilsRptAtomicWidget(widgetArgs);
	}

	/*
	switch(param.op) {
		case 'in':
		case 'not in':
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
	*/
}

//oilsRptParamEditor.prototype.get = function(param, node) {




