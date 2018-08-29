dojo.requireLocalization("openils.reports", "reports");

var rpt_strings = dojo.i18n.getLocalization("openils.reports", "reports");

oilsRptSetSubClass('oilsRptReportEditor', 'oilsRptObject');
var oilsRptReportEditorFolderTree;

function oilsRptReportEditor(rptObject, folderWindow, readonly) {
	var tmpl = rptObject.templateObject;
	var rpt = rptObject.reportObject;
	this.folderWindow = folderWindow;
    this.readonly = readonly;

	this.template = tmpl;
	this.report = rpt;

    if (rpt && rpt.runs() && rpt.runs().length)
        this.last_run = rpt.runs()[rpt.runs().length - 1];

	appendClear(DOM.oils_rpt_report_editor_template_name, tmpl.name());
	appendClear(DOM.oils_rpt_report_editor_template_creator, tmpl.owner().usrname());
	appendClear(DOM.oils_rpt_report_editor_template_description, tmpl.description());

    hideMe(DOM.oils_rpt_report_editor_template_doc_url_row);
    if (rptObject.def.version >= 4) {
        if (URL = rptObject.def.doc_url) {
            var link = DOM.oils_rpt_report_editor_template_doc_url;
            link.innerHTML = URL;
            if (typeof xulG == 'undefined') {
                link.setAttribute('href', URL);
                link.setAttribute('target', '_blank');
            } else {
                link.onclick = function() {xulG.new_tab(URL); return false}
            }
            unHideMe(DOM.oils_rpt_report_editor_template_doc_url_row);
        }
    }
    
    appendClear(DOM.oils_rpt_report_editor_cols,'');
	iterate(rptObject.def.select, 
		function(i) {
			if(i)
				DOM.oils_rpt_report_editor_cols.appendChild(text(i.alias));
                if (i.field_doc) {
				    DOM.oils_rpt_report_editor_cols.appendChild(
                        elem('span', {'class':'oils_rpt_field_hint'}, i.field_doc));
                }
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


    // schedule defaults.
    DOM.oils_rpt_param_editor_sched_start_date.value = mkYearMonDay();
    setSelector(DOM.oils_rpt_param_editor_sched_start_hour, '12:00');
    DOM.oils_rpt_report_editor_run_now.checked = true;
    DOM.oils_rpt_report_editor_schedule.checked = false;
    DOM.oils_rpt_param_editor_sched_start_date.disabled = true;
    DOM.oils_rpt_param_editor_sched_start_hour.disabled = true;

    // recur defaults
    setSelector(DOM.oils_rpt_recur_interval_type, 'days');
    setSelector(DOM.oils_rpt_recur_count, '1');

	if( rpt ) {
        // populate the report edit form w/ report data

        this.orig_rpt_name = rpt.name();

		DOM.oils_rpt_report_editor_name.value = rpt.name();
		DOM.oils_rpt_report_editor_name.onchange(); // validation
		DOM.oils_rpt_report_editor_desc.value = rpt.description();

        if (rpt.recur() == 't') {
            DOM.oils_rpt_recur.checked = true;
            DOM.oils_rpt_recur.onclick(); // enable recurrance selector
        }

        if (rpt.recurrence()) {
            console.log('editing report with recurrence: ' + rpt.recurrence());
            var parts = rpt.recurrence().split(/ /);
            var type = parts[1];
            var count = Number(parts[0]);

            if (type.match(/^mon/)) {
                // PG stores 'months' as 'mon(s)'
                type = 'months'; 
            } else if (type.match(/^day/)) {
                // PG stores weeks as days.  Assuming a person would typically
                // use weeks to represent sets of 7 days, translate back to
                // weeks when we can.
                if (count % 7 == 0) {
                    type = 'weeks';
                    count = count / 7;
                }
            }

            setSelector(DOM.oils_rpt_recur_count, count);
            setSelector(DOM.oils_rpt_recur_interval_type, type);
        }

        if (rpt.data()) { 
            var rpt_data = JSON2js(rpt.data());
            if (rpt_data.__pivot_label)
                setSelector(DOM.oils_rpt_editor_pivot_label, rpt_data.__pivot_label);
            if (rpt_data.__pivot_data)
                setSelector(DOM.oils_rpt_editor_pivot_data, rpt_data.__pivot_data);
            DOM.oils_rpt_editor_do_rollup.checked = rpt_data.__do_rollup == '1';
        }

        if (run = this.last_run) {
		    DOM.oils_rpt_report_editor_name.disabled = true;
		    DOM.oils_rpt_report_editor_desc.disabled = true;
            DOM.oils_rpt_format_csv.checked = run.csv_format() == 't';
            DOM.oils_rpt_format_excel.checked = run.excel_format() == 't';
            DOM.oils_rpt_format_html.checked = run.html_format() == 't';
            DOM.oils_rpt_format_chart_bar.checked = run.chart_bar() == 't';
            DOM.oils_rpt_format_chart_line.checked = run.chart_line() == 't';
            DOM.oils_rpt_param_editor_sched_email.value = run.email();

            if (run.run_time()) {
                console.log('view/edit report with last run_time: ' + run.run_time());
                if (new Date(Date.parse(run.run_time())) >= new Date() || this.readonly) {
                    // Next run of the edited report is scheduled for some time in the future.
                    // Propagate the value into the data selector and de-select run-now.
                    // Ditto read-only mode, so the user can see info on the most recent run.

                    DOM.oils_rpt_param_editor_sched_start_date.value = 
                        run.run_time().match(/(\d{4}-\d{2}-\d{2})/)[1]

                    setSelector(
                        DOM.oils_rpt_param_editor_sched_start_hour,
                        run.run_time().match(/T(\d{2})/)[1] + ':00'
                    );

                    DOM.oils_rpt_report_editor_run_now.checked = false;
                    DOM.oils_rpt_report_editor_schedule.checked = true;
                    DOM.oils_rpt_param_editor_sched_start_date.disabled = false;
                    DOM.oils_rpt_param_editor_sched_start_hour.disabled = false;
                }
            } 
        }
	}

    if (this.readonly) {
        DOM.oils_rpt_report_editor_name.disabled = true;
        DOM.oils_rpt_report_editor_desc.disabled = true;
        DOM.oils_rpt_recur.disabled = true;
        DOM.oils_rpt_recur_count.disabled = true;
        DOM.oils_rpt_recur_interval_type.disabled = true;
        DOM.oils_rpt_report_editor_run_now.disabled = true;
        DOM.oils_rpt_format_csv.disabled = true;
        DOM.oils_rpt_format_excel.disabled = true;
        DOM.oils_rpt_format_html.disabled = true;
        DOM.oils_rpt_format_chart_bar.disabled = true;
        DOM.oils_rpt_format_chart_line.disabled = true;
        DOM.oils_rpt_param_editor_sched_email.disabled = true;

        hideMe(DOM.oils_rpt_report_editor_save);
        hideMe(DOM.oils_rpt_report_editor_save_new);
        hideMe(DOM.oils_rpt_report_editor_cancel);
        unHideMe(DOM.oils_rpt_report_editor_exit);

    } else {
        // these DOM elements are shared across instances
        // of the UI.  Re-enable everything.
        DOM.oils_rpt_report_editor_name.disabled = false;
        DOM.oils_rpt_report_editor_desc.disabled = false;
        DOM.oils_rpt_recur.disabled = false;
        DOM.oils_rpt_recur_count.disabled = false;
        DOM.oils_rpt_recur_interval_type.disabled = false;
        DOM.oils_rpt_report_editor_run_now.disabled = false;
        DOM.oils_rpt_format_csv.disabled = false;
        DOM.oils_rpt_format_excel.disabled = false;
        DOM.oils_rpt_format_html.disabled = false;
        DOM.oils_rpt_format_chart_bar.disabled = false;
        DOM.oils_rpt_format_chart_line.disabled = false;
        DOM.oils_rpt_param_editor_sched_email.disabled = false;
        DOM.oils_rpt_report_editor_save.disabled = false;

        unHideMe(DOM.oils_rpt_report_editor_save);
        unHideMe(DOM.oils_rpt_report_editor_cancel);
        hideMe(DOM.oils_rpt_report_editor_exit);

    }

    // avoid showing save-as-new for new reports, since the
    // regular save button acts as save-as-new
    if (rpt && !this.readonly) {
        unHideMe(DOM.oils_rpt_report_editor_save_new);
    } else {
        hideMe(DOM.oils_rpt_report_editor_save_new);
    }

	this.paramEditor = new oilsRptParamEditor(
		rptObject, DOM.oils_rpt_param_editor_tbody, this.readonly);
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
			obj.selectedFolder = node; 
        },
        null,
        function(node) {
            // apply the previously selected report folder
            if (rpt && rpt.folder() == node.folder.id()) {
			    appendClear(DOM.oils_rpt_report_editor_selected_folder, node.folder.name());
			    obj.selectedFolder = node; 
            }
        }
    );

	oilsRptBuildFolder(
		'output',
		DOM.oils_rpt_output_dest_folder,
		'oilsRptReportEditorOutputTree',
		rpt_strings.REPORT_EDITOR_OUTPUT_FOLDERS,
		function(node) { 
			appendClear(DOM.oils_rpt_output_selected_folder, node.folder.name());
			obj.selectedOutputFolder = node; 
        },
        null,
        function(node) {
            // apply the previously selected output folder
            if (obj.last_run && obj.last_run.folder() == node.folder.id()) {
			    appendClear(DOM.oils_rpt_output_selected_folder, node.folder.name());
			    obj.selectedOutputFolder = node; 
            }
        }
    );


	var obj = this;
	DOM.oils_rpt_report_editor_save.onclick = function(){obj.save();}
	DOM.oils_rpt_report_editor_save_new.onclick = function(){obj.save({save_new : true});}
	DOM.oils_rpt_report_editor_exit.onclick = function(){obj.exit();}
	DOM.oils_rpt_report_editor_cancel.onclick = function(){obj.exit();}

	DOM.oils_rpt_param_editor_sched_email.value = 
        this.last_run ? this.last_run.email() : USER.email();

	_debug("fleshing template:\n" + tmpl.name() + '\n' + formatJSON(tmpl.data()));
}


// options.save_new : save as a new report, even if we
// were editing an exitingn report.
//
// options.modify_schedule : update the pending schedule
// object instead of creating a new one.
oilsRptReportEditor.prototype.save = function(options) {
    if (!options) options = {};

	if(!this.selectedFolder) 
		return alert(rpt_strings.REPORT_EDITOR_PROVIDE_FOLDER_ALERT);

	if(!DOM.oils_rpt_report_editor_name.value)
		return alert(rpt_strings.REPORT_EDITOR_ENTER_NAME_ALERT);

	if(!this.selectedOutputFolder) 
		return alert(rpt_strings.REPORT_EDITOR_PROVIDE_OUTPUT_ALERT);

	var report = this.report;

    if (report && options.save_new) {
        // user is saving an existing report as a new report.
        // The new report must have a different name.
        if (DOM.oils_rpt_report_editor_name.value == this.orig_rpt_name) 
            return alert(rpt_strings.REPORT_EDITOR_ENTER_NEW_NAME_ALERT);

        report = null;
    }

    if (!report) {
        report = new rr();
        report.isnew(true);
	    report.owner( USER.id() );
	    report.template( this.template.id() );
    }

	report.folder( this.selectedFolder.folder.id() );
	report.name( DOM.oils_rpt_report_editor_name.value );
	report.description( DOM.oils_rpt_report_editor_desc.value );
	report.recur(this.paramEditor.recur());
	report.recurrence(this.paramEditor.recurInterval());

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
    data.__do_rollup = DOM.oils_rpt_editor_do_rollup.checked ? '1' : '0';

	data = js2JSON(data);
	_debug("complete report data = "+data);
	report.data(data);

	_debug("Built report:\n"+js2JSON(report));


	var time;
	if( DOM.oils_rpt_report_editor_run_now.checked ) {
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

    // if the last run has yet to actually start, then we update it
    // instead of creating a new one.
    var schedule = options.save_new ? null : this.last_run;

    if (schedule && !schedule.start_time()) {
        if (!options.modify_schedule) {
            // warn the user that this action will modify an existing
            // schedule object if they continue
            return this.showPendingScheduleDialog();
        }
    } else {
        // no schedules exist or the most recent one has already
        // started.  Create a new one.
	    schedule = new rs();
        schedule.isnew(true);
    }

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

    if (report.isnew()) {
        this.createReport(report, schedule);
    } else {
        this.updateReport(report, schedule);
    }
}

// Modify an existing report.
// Modify or create the schedule depending on isnew()
oilsRptReportEditor.prototype.updateReport = function(report, schedule) {

    var this_ = this;
    function success() {
        oilsRptAlertSuccess();
        this_.exit();
    }

    oilsRptUpdateReport(report, function(ok) {
        if (!ok) return oilsRptAlertFailure();

        if (schedule.isnew()) {

            var req = new Request(OILS_RPT_CREATE_SCHEDULE, SESSION, schedule);
            req.callback(function(res) {
                if(checkILSEvent(res)) 
                    return alertILSEvent(res);
                success();
            });
            req.send()

        } else {

            oilsRptUpdateSchedule(schedule, function(ok2) {
                if (ok2) return success();
                _debug("schedule update failed " + js2JSON(schedule));
                oilsRptAlertFailure();
            });
        }
    });
}

oilsRptReportEditor.prototype.createReport = function(report, schedule) {
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
                                obj.exit();
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

oilsRptReportEditor.prototype.showPendingScheduleDialog = function() {
    hideMe(DOM.oils_rpt_editor_table);
    unHideMe(DOM.oils_rpt_editor_sched_confirm);

    function close() {
        unHideMe(DOM.oils_rpt_editor_table);
        hideMe(DOM.oils_rpt_editor_sched_confirm);
    }

    var this_ = this;
    DOM.oils_rpt_report_editor_sched_apply.onclick = function() {
        close();
        this_.save({modify_schedule : true});
    }

    DOM.oils_rpt_report_editor_sched_asnew.onclick = function() {

        if (DOM.oils_rpt_report_editor_name.value == this_.orig_rpt_name) {
            // user is saving as new but has not yet modified the name
            // Prompt for a new name, then udpate the name entry so save() 
            // will see it.  Don't let them escape until they comply.
            var new_name;
            while (true) { 

                new_name = prompt(
                    rpt_strings.REPORT_EDITOR_ENTER_NEW_NAME_ALERT, 
                    this_.orig_rpt_name
                );
                
                if (new_name && new_name != this_.orig_rpt_name)
                    break;
            }

            DOM.oils_rpt_report_editor_name.value = new_name;
        } 

        close();
        this_.save({save_new : true})
    }
    DOM.oils_rpt_report_editor_sched_cancel.onclick = close;
}


oilsRptReportEditor.prototype.exit = function() {
    unHideMe(DOM.oils_rpt_folder_window_contents_table);                   
    unHideMe(DOM.oils_rpt_folder_table_right_td);
    hideMe(DOM.oils_rpt_folder_table_alt_td);
    hideMe(DOM.oils_rpt_editor_div);
}
