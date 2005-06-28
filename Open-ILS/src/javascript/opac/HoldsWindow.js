function HoldsWindow(record) {
	this.record = record;
}

HoldsWindow.prototype.buildHoldsWindowCallback = function(type) {

	var hwindow = this;
	var func = function() {

		var wrapper = elem("div");
		var id = hwindow.record.doc_id();

		var org = UserSession.instance().userObject.home_ou();
		wrapper.appendChild(hwindow.buildPickuplibSelector(org));
		if(type == "M")
			wrapper.appendChild(hwindow.buildResourceSelector());
		wrapper.appendChild(hwindow.buildSubmit());

		hwindow.win = window.open(null,"PLACE_HOLD_" + id,
			"location=0,menubar=0,status=0,resizeable,resize," +
			"outerHeight=500,outerWidth=500,height=500," +
			"width=500,scrollbars=1," +
			/*"screenX=100,screenY=100,top=100,left=100," + */
			"alwaysraised, chrome" )
	
		hwindow.win.document.write("<html>" + wrapper.innerHTML + "</html>");
		hwindow.win.document.close();
		hwindow.win.document.title = "View MARC";
		hwindow.win.focus();
	}

	return func;
}

HoldsWindow.prototype.buildSubmit = function() {
	var div = elem("div");
	var bdiv = elem("div")

	bdiv.setAttribute("style", 
		"border-top: 1px solid lightgrey;" +
		"border-bottom: 1px solid lightgrey;" +
		"width:100%;text-align:center;");

	var button = elem("input", 
		{type:"submit", value:"Place Hold"});

	div.appendChild(elem("br"));
	bdiv.appendChild(button);
	div.appendChild(bdiv);

	return div;
}

/* builds a selecor where the client can select the location to which
	the item is sent */
HoldsWindow.prototype.buildPickuplibSelector = function(selected_id) {

	var div = elem("div");
	var tdiv = elem("div",null, null,
		"Select the location where the item(s) shall be delivered");

	var sdiv = elem("div");
	var selector = elem("select");

	/* this is not copied over... XXX fix me */
	selector.onchange = function() {
		alert("Change!");
		var idx = selector.selectedIndex;
		var option = selector.options[idx];
		var org = findOrgUnit(option.value);

		var d = getById("selector_error_div");
		if(d) div.removeChild(d);

		if(parseInt(findOrgType(org.ou_type()).depth()) < 2) {
			alert("A REGION was selected");
			var err = elem("div",
				{id:"selector_error_div", style:"color:red"},null, 
				org.name() + " is a library system, please select a single branch");
			div.appendChild(err);
		} else {
			alert("Depth is " + findOrgType(org.ou_type()).depth());
		}
	}

	sdiv.appendChild(selector);
	_buildOrgList(selector, selected_id, null);

	div.appendChild(elem("br"));
	div.appendChild(tdiv);
	div.appendChild(sdiv);
	return div;
}

/* utility function for building a org list selector object */
function _buildOrgList(selector, selected_id, org) {

	if(selected_id == null) selected_id = -1;

	if(org == null) {
		org = globalOrgTree;

	} else { /* add the org to the list */
		var index = selector.options.length;
		if(IE) {
			var node = elem("pre");
			for(var x=2; x <= findOrgType(org.ou_type()).depth(); x++) {
				node.appendChild(mktext("    "));
			}
			node.appendChild(mktext(org.name()));
			var select = new Option("", org.id());
			selector.options[index] = select;
			select.appendChild(node);
	
		} else {
			var pad = (findOrgType(org.ou_type()).depth() - 1) * 12;
			var select = new Option(org.name(), org.id());
			select.setAttribute("style", "padding-left: " + pad);
			selector.options[index] = select;
		}

		if(parseInt(org.id()) == parseInt(selected_id)) {
			selector.selectedIndex = index;
			selector.options[index].selected = true;
		}
	}

	for(var idx in org.children()) 
		_buildOrgList(selector, selected_id, org.children()[idx]);
}

HoldsWindow.prototype.buildResourceSelector = function() {

	/* useful message */
	var big_div = elem('div');

	var desc_div = elem("div",null, null, 
		"Select all acceptible item formats");

	var resources = [ 
		"text", 
		"moving image",
		"sound recording",
		"software, multimedia",
		"still images",
		"cartographic",
		"mixed material",
		"notated music",
		"three dimensional object" ];
	
	var table = elem("table");	

	for( var idx in resources ) {
		var row = table.insertRow(table.rows.length)
	
		var pic_cell = row.insertCell(0);
		var name_cell = row.insertCell(1);
		var box_cell = row.insertCell(2);
		var box = elem("input", 
			{type:"checkbox", id: resources[idx] + "_hold_checkbox"}, null);

		if(idx == 0) { /* select text by default */
			box.setAttribute("checked","checked");
			box.checked = true;
		}
		
		pic_cell.appendChild(mkResourceImage(resources[idx]));
		name_cell.appendChild(mktext(resources[idx]));
		box_cell.appendChild(mktext(" "));
		box_cell.appendChild(box);
	}

	big_div.appendChild(elem("br"));
	big_div.appendChild(desc_div);
	big_div.appendChild(table);
	return big_div;

}

function mkResourceImage(resource) {
	var pic = elem("img");
	pic.setAttribute("src", "/images/" + resource + ".jpg");
	pic.setAttribute("width", "20");
	pic.setAttribute("height", "20");
	pic.setAttribute("title", resource);
	return pic;
}


