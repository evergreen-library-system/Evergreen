sdump('D_OPAC','Loading opac.js\n');

//var OPAC_URL = "http://gapines.org:8080/opac/?top_target=advanced_search";
var OPAC_URL = "http://gapines.org/opac/?top_target=advanced_search";
//var OPAC_URL = "http://google.com/";

var opac_progressListener = new Object();
var opac_iframe;
var opac_appframe; /* i hold the actual opac iframe */


/* init the opac */
function opac_init(p) {
	sdump('D_OPAC',"Initing OPAC\n");

	var box = p.w.document.getElementById('opac_vbox');
	opac_iframe = box.appendChild(document.createElement("browser"));

	opac_iframe.setAttribute("type", "content-primary");
	opac_iframe.setAttribute("id", "opac_opac_iframe");
	opac_iframe.setAttribute("flex", "1");
	opac_iframe.setAttribute("src", OPAC_URL) 

	opac_iframe.contentWindow.IAMXUL = true;
	opac_iframe.contentWindow.xulEvtRecordResultDisplayed 
		= xulEvtRecordResultDisplayed;

	opac_iframe.contentWindow.xulEvtMRResultDisplayed 
		= xulEvtMRResultDisplayed;

	opac_iframe.contentWindow.xulEvtRecordDetailDisplayed 
		= xulEvtRecordDetailDisplayed;

	/* shove BIG G in so global variables may be accessed */
	opac_iframe.contentWindow.G = mw.G;

}



function webForward() {
	try {
		if(opac_iframe.webNavigation.canGoForward)
			opac_iframe.webNavigation.goForward();
	} catch(E) {
		sdump('D_OPAC','goForward error: ' + js2JSON(E) + '\n');
	}
}

function webBack() {
	try {
		if(opac_iframe.webNavigation.canGoBack)
			opac_iframe.webNavigation.goBack();
	} catch(E) {
		sdump('D_OPAC','goBack error: ' + js2JSON(E) + '\n');
	}
}


/* -------------------------------------------------------------------------- 
	XUL Callbacks
	-------------------------------------------------------------------------- */


var xulEvtRecordResultDisplayed = function(ui_obj, record) {
	ui_obj.addItem("Edit MARC", function() { 
			spawn_marc_editor( true, [ record.doc_id() ] );
		}
	);

	ui_obj.addItem("Open Copy Browser", function() { 
			spawn_copy_browser(true, [ record.doc_id() ]); 
		}
	);

}

var xulEvtMRResultDisplayed = function(ui_obj, record) {
	sdump('D_OPAC',"xulEvtMRRsultsDisplayed()\n");
}


var xulEvtRecordDetailDisplayed = function(ui_obj, record) {
	ui_obj.addItem("Edit MARC", function() { 
			spawn_marc_editor( true, [ record.doc_id() ] );
		}
	);

	ui_obj.addItem("Open Copy Browser", function() { 
			spawn_copy_browser(true, [ record.doc_id() ]); 
		}
	);

}


