dojo.requireLocalization("openils.reports", "reports");

var rpt_strings = dojo.i18n.getLocalization("openils.reports", "reports");

oilsRptSetSubClass('oilsRptReportEditor', 'oilsRptObject');
var oilsRptReportEditorFolderTree;

function oilsRptReportEditor(rptObject, folderWindow) {
	var tmpl = rptObject.templateObject;
	var rpt = rptObject.reportObject;
	this.folderWindow = folderWindow;

	this.template = tmpl;
	this.report = rpt;

	appendClear(DOM.oils_rpt_report_editor_template_name, tmpl.name());
	appendClear(DOM.oils_rpt_report_editor_template_creator, tmpl.owner().usrname());
	appendClear(DOM.oils_rpt_report_editor_template_description, tmpl.description());
    
    appendClear(DOM.oils_rpt_report_editor_cols,'');
	iterate(rptObject.def.select, 
		function(i) {
			if(i)
				DOM.oils_rpt_report_editor_cols.appendChild(text(i.alias));
				DOM.oils_rpt_report_editor_cols.appendChild(document.createElement('br'));
		}
	);

/*
oils_rpt_editor_pivot_label
oils_rpt_editor_pivot_data
*/

    var hasAgg = false;
    iterate(rptObject.def.select, 
        function(i) {
            if(OILS_RPT_TRANSFORMS[i.column.transform].aggregate) 
                hasAgg = true; 
        }
    );

    while(DOM.oils_rpt_editor_pivot_label.getElementsByTagName('option').length > 1)
        DOM.oils_rpt_editor_pivot_label.removeChild(DOM.oils_rpt_editor_pivot_label.lastChild);

    while(DOM.oils_rpt_editor_pivot_data.lastChild)
        DOM.oils_rpt_editor_pivot_data.removeChild(DOM.oils_rpt_editor_pivot_data.lastChild);

    if(hasAgg) {
        unHideMe(DOM.oils_rpt_editor_pivot_label_row);
        unHideMe(DOM.oils_rpt_editor_pivot_data_row);

        for(var i in rptObject.def.select) {
            var col = rptObject.def.select[i];
            if(OILS_RPT_TRANSFORMS[col.column.transform].aggregate) 
               insertSelectorVal(DOM.oils_rpt_editor_pivot_data, -1, col.alias, parseInt(i)+1);
            else
               insertSelectorVal(DOM.oils_rpt_editor_pivot_label, -1, col.alias, parseInt(i)+1);
        }

    } else {
        hideMe(DOM.oils_rpt_editor_pivot_label_row);
        hideMe(DOM.oils_rpt_editor_pivot_data_row);
    }
 

	if( rpt ) {
		DOM.oils_rpt_report_editor_name.value = rpt.name();
		DOM.oils_rpt_report_editor_description.value = rpt.description();
	}

	this.paramEditor = new oilsRptParamEditor(
		rptObject, DOM.oils_rpt_param_editor_tbody);
	this.paramEditor.draw();

	removeChildren(DOM.oils_rpt_report_editor_selected_folder);
	removeChildren(DOM.oils_rpt_output_selected_folder);

	var obj = this;
	oilsRptBuildFolder(
		'report',
		DOM.oils_rpt_report_editor_dest_folder,
		'oilsRptReportEditorFolderTree',
		rpt_strings.REPORT_EDITOR_REPORT_FOLDERS,
		function(node) { 
			appendClear(DOM.oils_rpt_report_editor_selected_folder, node.folder.name());
			obj.selectedFolder = node; });


	oilsRptBuildFolder(
		'output',
		DOM.oils_rpt_output_dest_folder,
		'oilsRptReportEditorOutputTree',
		rpt_strings.REPORT_EDITOR_OUTPUT_FOLDERS,
		function(node) { 
			appendClear(DOM.oils_rpt_output_selected_folder, node.folder.name());
			obj.selectedOutputFolder = node; });


	var obj = this;
	DOM.oils_rpt_report_editor_save.onclick = function(){obj.save();}
	DOM.oils_rpt_param_editor_sched_email.value = USER.email();
	DOM.oils_rpt_param_editor_sched_start_date.value = mkYearMonDay();

	_debug("fleshing template:\n" + tmpl.name() + '\n' + formatJSON(tmpl.data()));
}


oilsRptReportEditor.prototype.save = function() {
	var report = new rr();

	if(!this.selectedFolder) 
		return alert(rpt_strings.REPORT_EDITOR_PROVIDE_FOLDER_ALERT);

	if(!DOM.oils_rpt_report_editor_name.value)
		return alert(rpt_strings.REPORT_EDITOR_ENTER_NAME_ALERT);

	report.owner( USER.id() );
	report.template( this.template.id() );
	report.folder( this.selectedFolder.folder.id() );
	report.name( DOM.oils_rpt_report_editor_name.value );
	report.description( DOM.oils_rpt_report_editor_desc.value );
	report.recur(this.paramEditor.recur());
	report.recurance(this.paramEditor.recurInterval());


	/* collect the param data */
	var data = {};
	for( var p in this.paramEditor.params ) {
		var par = this.paramEditor.params[p];
		_debug("adding report param "+par.key+" to report data");
		var val = par.widget.getValue();

		if(!val || val.length == 0 )
			return alertId('oils_rpt_empty_param');

		if( typeof val == 'object') {
			for( var i = i; i < val.length; i++ ) {
				_debug("looking at widget value" + val[i]);
				if( val[i] == '' || val[i] == null ) 
					return alertId('oils_rpt_empty_param');
			}
		}

		data[par.key] = val;
	}

    if(getSelectorVal(DOM.oils_rpt_editor_pivot_data)) {
        data.__pivot_label = getSelectorVal(DOM.oils_rpt_editor_pivot_label);
        data.__pivot_data = getSelectorVal(DOM.oils_rpt_editor_pivot_data);
    }


	data = js2JSON(data);
	_debug("complete report data = "+data);
	report.data(data);

	_debug("Built report:\n"+js2JSON(report));


	var time;
	if( DOM.oils_rpt_report_editor_run_now.checked ) {
		DOM.oils_rpt_report_editor_run_now.checked = false;
		time = 'now';

	} else {

		var dt = DOM.oils_rpt_param_editor_sched_start_date.value;
		if(!dt || !dt.match(/^\d{4}-\d{2}-\d{2}$/) ) {
			/* for now.. make this better in the future */
			alert(rpt_strings.REPORT_EDITOR_INVALID_DATE_ALERT);
			return;
		}
		var hour = getSelectorVal(DOM.oils_rpt_param_editor_sched_start_hour);
		time = dt +'T'+hour+':00';
		_debug("built run_time "+time);
	}

	if(!this.selectedOutputFolder) 
		return alert(rpt_strings.REPORT_EDITOR_PROVIDE_OUTPUT_ALERT);

	var schedule = new rs();
	schedule.folder(this.selectedOutputFolder.folder.id());
	schedule.email(DOM.oils_rpt_param_editor_sched_email.value);
	schedule.run_time(time);
	schedule.runner(USER.id());

	schedule.excel_format((DOM.oils_rpt_format_excel.checked) ? 't' : 'f');
	schedule.html_format((DOM.oils_rpt_format_html.checked) ? 't' : 'f');
	schedule.csv_format((DOM.oils_rpt_format_csv.checked) ? 't' : 'f');
	//schedule.chart_pie((DOM.oils_rpt_format_chart_pie.checked) ? 't' : 'f');
	schedule.chart_bar((DOM.oils_rpt_format_chart_bar.checked) ? 't' : 'f');
	schedule.chart_line((DOM.oils_rpt_format_chart_line.checked) ? 't' : 'f');


	debugFMObject(report);
	debugFMObject(schedule);

	//return;

	var obj = this;
    var folderReq = new Request(OILS_RPT_REPORT_EXISTS, SESSION, report);
    folderReq.callback(
        function(r1) {
            if(r1.getResultObject() == 1) {
                alertId('oils_rpt_report_exists');
                return;
            } else {
                var req = new Request(OILS_RPT_CREATE_REPORT, SESSION, report, schedule );
                req.callback(
                    function(r) {
                        var res = r.getResultObject();
                        if(checkILSEvent(res)) {
                            alertILSEvent(res);
                        } else {
                            if( res && res != '0' ) {
                                oilsRptAlertSuccess();
                                oilsRptCurrentFolderManager.draw();
                                obj.folderWindow.draw();
                            }
                        }
                    }
                );
                req.send();
            }
        }
    );
    folderReq.send();
}


