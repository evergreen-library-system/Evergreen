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

/* transforms for the different data types */
/*
var oilsRptTransforms = {
	'string'		: [ 'substring' ],
	'numeric'	: [ 'sum', 'average' ],
	'timestamp' : [ 'month_trunc', 'months_ago', 'quarters_ago', 'age' ],
	'all'			: [ 'raw', 'count', 'count_distinct', 'min', 'max' ]
};
*/

/* for ease of use, shove everything in the 'all' slot into the other tforms */
/*
for( var t in oilsRptTransforms ) {
	if( t == 'all' ) continue;
	for( var a in oilsRptTransforms['all'] ) 
		oilsRptTransforms[t].push( oilsRptTransforms['all'][a] );
}
delete oilsRptTransforms.all;
*/
/* --------------------------------------------------- */


/*
var oilsRptRegexClasses = {
	'number' : /\d+/
}
*/

/* the current transform manager for the builder transform window */
var oilsRptCurrentTform;

/* the current transform manager for the builder filter window */
var oilsRptCurrentFilterTform;

/* the current operation manager for the filter window */
var oilsRptCurrentFilterOpManager;
