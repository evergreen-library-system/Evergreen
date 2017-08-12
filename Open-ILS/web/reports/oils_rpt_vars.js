/* dom nodes with IDs are inserted into DOM as DOM[id] */
var DOM = {};

/* JS object version of the IDL */
var oilsIDL;

/* the currently building report */
var oilsRpt;

/* UI tree  */
var oilsRptTree;

var oilsRptCurrentOrg;
var oilsRptMyOrgs;

var oilsRptCookie;

var oilsRptTemplateFolderTree;
var oilsRptReportFolderTree;
var oilsRptOutputFolderTree;
var oilsRptSharedTemplateFolderTree;
var oilsRptSharedReportFolderTree;
var oilsRptSharedOutputFolderTree;

var oilsRptOutputLimit = 10;
var oilsRptOutputLimit2 = 10;
var oilsRptOutputOffset = 0;

var OILS_RPT_INVALID_DATA = 'oils_rpt_invalid_input';

/* URL to retrieve the IDL from */
var OILS_IDL_URL = "/reports/fm_IDL.xml";

var OILS_IDL_OUTPUT_URL = '/reporter/'
var OILS_IDL_OUTPUT_FILE = 'report-data.html';

/* multi-select which shows the user 
	what data they want to see in the report */
var oilsRptDisplaySelector;

var oilsRptFilterSelector;

var oilsRptHavingSelector;

//var oilsRptOrderBySelector;

/* display the currently building report object in an external window */
var oilsRptDebugWindow;

/* if true, show the debugging window */
var oilsRptDebugEnabled = false;

var oilsMouseX;
var oilsMouseY;
var oilsPageXMid;
var oilsPageYMid;

var oilsIDLReportsNS = 'http://open-ils.org/spec/opensrf/IDL/reporter/v1';
var oilsIDLPersistNS = 'http://open-ils.org/spec/opensrf/IDL/persistence/v1';

/* the current transform manager for the builder transform window */
var oilsRptCurrentTform;

/* the current transform manager for the builder filter window */
var oilsRptCurrentFilterTform;
var oilsRptCurrentAggFilterTform;

/* the current operation manager for the filter window */
var oilsRptCurrentFilterOpManager;
var oilsRptCurrentAggFilterOpManager;

var OILS_RPT_FETCH_FOLDERS			= 'open-ils.reporter:open-ils.reporter.folder.visible.retrieve';
var OILS_RPT_FETCH_FOLDER_DATA	= 'open-ils.reporter:open-ils.reporter.folder_data.retrieve';
var OILS_RPT_FETCH_TEMPLATE		= 'open-ils.reporter:open-ils.reporter.template.retrieve';
var OILS_RPT_UPDATE_FOLDER			= 'open-ils.reporter:open-ils.reporter.folder.update';
var OILS_RPT_DELETE_FOLDER			= 'open-ils.reporter:open-ils.reporter.folder.delete';
var OILS_RPT_CREATE_FOLDER			= 'open-ils.reporter:open-ils.reporter.folder.create';
var OILS_RPT_FETCH_ORG_FULL_PATH = 'open-ils.reporter:open-ils.reporter.org_unit.full_path';
var OILS_RPT_FETCH_ORG_TREE		= 'open-ils.actor:open-ils.actor.org_tree.retrieve';
var OILS_RPT_DELETE_TEMPLATE		= 'open-ils.reporter:open-ils.reporter.template.delete.cascade';
var OILS_RPT_DELETE_REPORT			= 'open-ils.reporter:open-ils.reporter.report.delete.cascade';
var OILS_RPT_DELETE_SCHEDULE		= 'open-ils.reporter:open-ils.reporter.schedule.delete';
var OILS_RPT_TEMPLATE_HAS_RPTS	= 'open-ils.reporter:open-ils.reporter.template_has_reports';
var OILS_RPT_REPORT_HAS_OUTS		= 'open-ils.reporter:open-ils.reporter.report_has_output';
var OILS_RPT_CREATE_REPORT			= 'open-ils.reporter:open-ils.reporter.report.create';
var OILS_RPT_CREATE_TEMPLATE		= 'open-ils.reporter:open-ils.reporter.template.create';
var OILS_RPT_CREATE_SCHEDULE		= 'open-ils.reporter:open-ils.reporter.schedule.create';
var OILS_RPT_UPDATE_REPORT			= 'open-ils.reporter:open-ils.reporter.report.update';
var OILS_RPT_UPDATE_TEMPLATE		= 'open-ils.reporter:open-ils.reporter.template.update';
var OILS_RPT_UPDATE_SCHEDULE		= 'open-ils.reporter:open-ils.reporter.schedule.update';
var OILS_RPT_FETCH_OUTPUT			= 'open-ils.reporter:open-ils.reporter.schedule.retrieve_by_folder';
var OILS_RPT_FETCH_REPORT			= 'open-ils.reporter:open-ils.reporter.report.retrieve';
var OILS_RPT_FETCH_TEMPLATE		= 'open-ils.reporter:open-ils.reporter.template.retrieve';
var OILS_RPT_MAGIC_FETCH			= 'open-ils.reporter:open-ils.reporter.magic_fetch';
var OILS_RPT_REPORT_EXISTS      = 'open-ils.reporter:open-ils.reporter.report.exists';
var OILS_RPT_TEMPLATE_EXISTS      = 'open-ils.reporter:open-ils.reporter.template.exists';

var oilsRptCurrentFolderManager;

//var oilsRptFolderWindowCache = {};

var oilsRptObjectCache = {};

var OILS_RPT_DTYPE_STRING = 'string';
var OILS_RPT_DTYPE_INT = 'int';
var OILS_RPT_DTYPE_FLOAT = 'float';
var OILS_RPT_DTYPE_TIMESTAMP = 'timestamp';
