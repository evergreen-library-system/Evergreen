// Modified by Jason for Evergreen

function startEvergreenStaffClient() {
	if (! window.open('chrome://evergreen/content/','auth_win','chrome') )
		alert('Could not start Evergreen');
}

function startEvergreenOPAC() {
	var text = evergreenGetSelectedText();
	var url = 'http://gapines.org/';
	if (text) {
		url = 'http://gapines.org/opac/'
		+ '?target=mr_result'
		+ '&mr_search_type=keyword'
		+ '&mr_search_query=' + encodeURIComponent( text )
		+ '&mr_search_location=1'
		+ '&mr_search_depth=0'
		+ '&page=0'
		+ '&sub_frame=1';
	}
	if (! window.open(url,'gapines.org') )
		alert('Could not load http://gapines.org/');
}

function evergreenGetSelectedText() {
	var node = document.popupNode;
	var selection = "";
	var nodeLocalName = node.localName.toUpperCase();
	if ((nodeLocalName == "TEXTAREA") || (nodeLocalName == "INPUT" && node.type == "text")) {
		selection = node.value.substring(node.selectionStart, node.selectionEnd);
	} 
	else {
		var focusedWindow = new XPCNativeWrapper(document.commandDispatcher.focusedWindow, 'document', 'getSelection()');
		selection = focusedWindow.getSelection().toString();
	}
	selection = selection.replace(/(^\s+)|(\s+$)/g, "");

	return selection;
}

