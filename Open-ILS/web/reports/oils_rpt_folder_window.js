
function oilsRptDrawFolderWindow( type, folderId ) {
	var node = oilsRptCurrentFolderManager.findNode(type, folderId);
	_debug('drawing folder window for folder ' + node.folder.name());

	var div = DOM.oils_rpt_folder_window_div;

	switch(type) {
		case 'template': 
			oilsRptDrawTemplateWindow(node);
			break;
		case 'report':
			oilsRptDrawReportWindow(node);
			break;
		case 'output':
			oilsRptDrawOutputWindow(node);
			break;
	}
}


function oilsRptDrawTemplateWindow(node) {
}

function oilsRptDrawReportWindow(node) {
}

function oilsRptDrawOutputWindow(node) {
}

