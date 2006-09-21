/* dom nodes with IDs are inserted into DOM as DOM[id] */
var DOM = {};

/* JS object version of the IDL */
var oilsIDL;

/* the currently building report */
var oilsRpt;

/* UI tree  */
var oilsRptTree;

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
