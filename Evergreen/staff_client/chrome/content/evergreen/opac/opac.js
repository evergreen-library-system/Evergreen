sdump('D_OPAC','Loading opac.js\n');

//var OPAC_URL = "http://gapines.org:8080/opac/?top_target=advanced_search";
var OPAC_URL = "http://gapines.org/opac/?top_target=advanced_search";
//var OPAC_URL = "http://google.com/";

/* init the opac */
function opac_init(p) {
	sdump('D_OPAC',"Initing OPAC\n");

	var box = p.w.document.getElementById('opac_vbox');
	p.opac_iframe = box.appendChild(document.createElement("browser"));

	p.opac_iframe.setAttribute("type", "content-primary");
	p.opac_iframe.setAttribute("id", "opac_opac_iframe");
	p.opac_iframe.setAttribute("flex", "1");
	p.opac_iframe.setAttribute("src", OPAC_URL) 

	opac_build_callbacks(p);

	p.opac_iframe.contentWindow.IAMXUL = true;
	p.opac_iframe.contentWindow.xulEvtRecordResultDisplayed 
		= p.xulEvtRecordResultDisplayed;

	p.opac_iframe.contentWindow.xulEvtMRResultDisplayed 
		= p.xulEvtMRResultDisplayed;

	p.opac_iframe.contentWindow.xulEvtRecordDetailDisplayed 
		= p.xulEvtRecordDetailDisplayed;

	/* shove BIG G in so global variables may be accessed */
	p.opac_iframe.contentWindow.G = mw.G;

}


function opac_build_navigation(p) {
	p.webForward = function webForward() {
		try {
			if(p.opac_iframe.webNavigation.canGoForward)
				p.opac_iframe.webNavigation.goForward();
		} catch(E) {
			sdump('D_OPAC','goForward error: ' + js2JSON(E) + '\n');
		}
	}

	p.webBack = function webBack() {
		try {
			if(p.opac_iframe.webNavigation.canGoBack)
				p.opac_iframe.webNavigation.goBack();
		} catch(E) {
			sdump('D_OPAC','goBack error: ' + js2JSON(E) + '\n');
		}
	}
}

/* -------------------------------------------------------------------------- 
	XUL Callbacks
	-------------------------------------------------------------------------- */

function opac_build_callbacks(p) {
	p.xulEvtRecordResultDisplayed = function(ui_obj, record) {
		ui_obj.addItem("Edit MARC", function() { 
				spawn_marc_editor( 
					p.w.app_shell, 'new_tab', 'main_tabbox', { 
						'find_this_id' : record.doc_id() 
					} 
				).find_this_id = record.doc_id();
			}
		);

		ui_obj.addItem("Open Copy Browser", function() { 
				spawn_copy_browser(
					p.w.app_shell, 'new_tab', 'main_tabbox', {
						'find_this_id' : record.doc_id()
					}
				).find_this_id = record.doc_id();
			}
		);

	}

	p.xulEvtMRResultDisplayed = function(ui_obj, record) {
		sdump('D_OPAC',"xulEvtMRRsultsDisplayed()\n");
	}


	p.xulEvtRecordDetailDisplayed = function(ui_obj, record) {
		ui_obj.addItem("Edit MARC", function() { 
				spawn_marc_editor( 
					p.w.app_shell, 'new_tab', 'main_tabbox', { 
						'find_this_id' : record.doc_id() 
					} 
				).find_this_id = record.doc_id();
			}
		);

		ui_obj.addItem("Open Copy Browser", function() { 
				spawn_copy_browser(
					p.w.app_shell, 'new_tab', 'main_tabbox', {
						'find_this_id' : record.doc_id()
					}
				).find_this_id = record.doc_id();
			}
		);
	}
}
