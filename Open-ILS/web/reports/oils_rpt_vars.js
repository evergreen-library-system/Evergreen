/* dom nodes with IDs are inserted into DOM as DOM[id] */
var DOM = {};

/* JS object version of the IDL */
var oilsIDL;

/* the currently building report */
var oilsRpt;

/* UI tree  */
var oilsRptTree;

var oilsRptCurrentOrg;

var oilsRptTemplateFolderTree;
var oilsRptReportFolderTree;
var oilsRptOutputFolderTree;
var oilsRptSharedTemplateFolderTree;
var oilsRptSharedReportFolderTree;
var oilsRptSharedOutputFolderTree;


/* URL to retrieve the IDL from */
var OILS_IDL_URL = "/reports/fm_IDL.xml";

/* multi-select which shows the user 
	what data they want to see in the report */
var oilsRptDisplaySelector;

var oilsRptFilterSelector;

/* display the currently building report object in an external window */
var oilsRptDebugWindow;

/* if true, show the debugging window */
var oilsRptDebugEnabled = false;

var oilsMouseX;
var oilsMouseY;
var oilsPageXMid;
var oilsPageYMid;

var oilsIDLReportsNS = 'http://open-ils.org/spec/opensrf/IDL/reporter/v1';
var oilsIDLPersistNS = 'http://open-ils.org/spec/opensrf/IDL/persistance/v1';

/* the current transform manager for the builder transform window */
var oilsRptCurrentTform;

/* the current transform manager for the builder filter window */
var oilsRptCurrentFilterTform;

/* the current operation manager for the filter window */
var oilsRptCurrentFilterOpManager;

var OILS_RPT_FETCH_FOLDERS			= 'open-ils.reporter:open-ils.reporter.folder.visible.retrieve';
var OILS_RPT_FETCH_FOLDER_DATA	= 'open-ils.reporter:open-ils.reporter.folder_data.retrieve';
var OILS_RPT_FETCH_TEMPLATE		= 'open-ils.reporter:open-ils.reporter.template.retrieve';
var OILS_RPT_UPDATE_FOLDER			= 'open-ils.reporter:open-ils.reporter.folder.update';
var OILS_RPT_DELETE_FOLDER			= 'open-ils.reporter:open-ils.reporter.folder.delete';
var OILS_RPT_CREATE_FOLDER			= 'open-ils.reporter:open-ils.reporter.folder.create';
var OILS_RPT_FETCH_ORG_FULL_PATH = 'open-ils.reporter:open-ils.reporter.org_unit.full_path';
var OILS_RPT_FETCH_ORG_TREE		= 'open-ils.actor:open-ils.actor.org_tree.retrieve';
var OILS_RPT_DELETE_TEMPLATE		= 'open-ils.reporter:open-ils.reporter.template.delete';
var OILS_RPT_DELETE_REPORT			= 'open-ils.reporter:open-ils.reporter.report.delete';
var OILS_RPT_TEMPLATE_HAS_RPTS	= 'open-ils.reporter:open-ils.reporter.template_has_reports';
var OILS_RPT_CREATE_REPORT			= 'open-ils.reporter:open-ils.reporter.report.create';
var OILS_RPT_CREATE_TEMPLATE		= 'open-ils.reporter:open-ils.reporter.template.create';

var oilsRptCurrentFolderManager;

//var oilsRptFolderWindowCache = {};

var oilsRptObjectCache = {};
