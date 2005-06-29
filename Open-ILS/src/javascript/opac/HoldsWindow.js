var resourceFormats = [ 
	"text", 
	"moving image",
	"sound recording",
	"software, multimedia",
	"still images",
	"cartographic",
	"mixed material",
	"notated music",
	"three dimensional object" ];


/* 
	@param record the id of the target item 
	@param type is the hold level (M, T, V, C) for metarecord, title,
		volume, and copy respectively.
	@param requestor is the user object (fieldmapper) for the requestor
	@param recipient is the user object (fieldmapper) for the hold recipient
		role in the holds process 
	@param requestor_login is the login session of the hold requestor
	*/
function HoldsWindow(record, type, requestor, recipient, requestor_login) {

	this.record = record;
	this.div = elem("div");
	this.requestor = requestor;
	this.recipient	= recipient;
	this.type = type;
	this.session = requestor_login;

	add_css_class(this.div, "holds_window");
	add_css_class(this.div, "hide_me");
	getDocument().body.appendChild(this.div);
}


HoldsWindow.prototype.process = function() {

	/* collect the checked items */
	var formats = "";
	if(this.type == "M") {
		for(var idx in resourceFormats) {
			var form = resourceFormats[idx];
			var item = getById( form + "_hold_checkbox");
			if(item.checked) {
				formats += modsFormatToMARC(form);
			}
		}
		
		if(formats.length == 0) {
			alert("Please select at least one item format");
			this.toggle();
		}
	} 

	var sel = getById("holds_org_selector");
	var orgNode = sel.options[sel.selectedIndex];
	var org = findOrgUnit(orgNode.value);

	/* for now... */
	var email = this.recipient.email();
	var phone = this.recipient.day_phone();

	this.sendHoldsRequest(formats, org, email, phone);
}

/* formats is a string of format characters, org is the 
	org unit used for delivery */
HoldsWindow.prototype.sendHoldsRequest = function(formats, org, email, phone) {
	var hold = new ahr();
	hold.pickup_lib(org.id());
	hold.requestor(this.requestor.id());
	hold.usr(this.recipient.id());
	hold.hold_type(this.type);
	hold.email_notify(email);
	hold.phone_notify(phone);
	if(this.type == "M") hold.holdable_formats(formats);
	hold.target(this.record);

	var req = new RemoteRequest(
		"open-ils.circ",
		"open-ils.circ.holds.create",
		this.session, hold );

	req.send(true);
	var res = req.getResultObject();
	if(res == 1) 
		alert("Hold request was succesfully submitted");

}

HoldsWindow.prototype.buildWindow = function() {

	var d = elem("div");
	var id = this.record;

	var usr = this.recipient;
	if(!usr) return;
	var org = usr.home_ou();
	d.appendChild(this.buildPickuplibSelector(org));

	if(this.type == "M")
		d.appendChild(this.buildResourceSelector());
	d.appendChild(this.buildSubmit());

	this.div.appendChild(d);
}

HoldsWindow.prototype.toggle = function() {
	swapClass( this.div, "hide_me", "show_me" );


	/* workaround for IE select box widget bleed through, blegh... */
	if(IE) {

		var sels = getDocument().getElementsByTagName("select");
		if(sels.length == 0) return;

		if(this.div.className.indexOf("hide_me") != -1)  {
			for(var i = 0; i!= sels.length; i++) {
				var s = sels[i];
				if(s && s.id != "holds_org_selector") {
					remove_css_class(s, "invisible");
					add_css_class(s, "visible");
				}
			}
		}
	
		if(this.div.className.indexOf("show_me") != -1)  {
			for(var i = 0; i!= sels.length; i++) {
				var s = sels[i];
				if(s && s.id != "holds_org_selector") {
					remove_css_class(s, "visible");
					add_css_class(s, "invisible");
				}
			}
		}
	}
}

/*
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
			"alwaysraised, chrome" )
	
		hwindow.win.document.write("<html>" + wrapper.innerHTML + "</html>");
		hwindow.win.document.close();
		hwindow.win.document.title = "View MARC";
		hwindow.win.focus();
	}

	return func;
}
*/

HoldsWindow.prototype.buildSubmit = function() {
	var div = elem("div");


	/*
	var bdiv = elem("div",  
			{style:	
				"border-top: 1px solid lightgrey;" +
				"border-bottom: 1px solid lightgrey;" +
				"width:100%;text-align:center;"});
				*/

	var bdiv = elem("div");  
	add_css_class(bdiv, "holds_window_buttons");

	var button = elem("input", 
		{type:"submit", style:"margin-left: 10px;", value:"Place Hold"});

	var cancel = elem("input", 
		{type:"submit", style:"margin-right: 10px;",value:"Cancel"});
	var obj = this;

	cancel.onclick = function() { obj.toggle(); }
	button.onclick = function() { obj.toggle(); obj.process(); }

	div.appendChild(elem("br"));
	bdiv.appendChild(cancel);
	bdiv.appendChild(button);
	div.appendChild(bdiv);

	return div;
}

/* builds a selecor where the client can select the location to which
	the item is sent */
HoldsWindow.prototype.buildPickuplibSelector = function(selected_id) {

	var div = elem("div");
	var tdiv = elem("div",{style:"margin-left:10px"}, null,
		"1. Select the location where the item(s) shall be delivered");

	var sdiv = elem("div");
	var selector = elem("select",{id:"holds_org_selector"});

	/* this is not copied over... XXX fix me */
	selector.onchange = function() {
		var idx = selector.selectedIndex;
		var option = selector.options[idx];
		var org = findOrgUnit(option.value);

		var d = getById("selector_error_div");
		if(d) div.removeChild(d);

		if(parseInt(findOrgType(org.ou_type()).depth()) < 2) {
			var err = elem("div",
				{id:"selector_error_div", style:"color:red"},null, 
				org.name() + " is a library system, please select a single branch");
			div.appendChild(err);
		} else {
		}
	}

	var center = elem("center");
	center.appendChild(selector);
	sdiv.appendChild(center);
	_buildOrgList(selector, selected_id, null);

	div.appendChild(elem("br"));
	div.appendChild(tdiv);
	div.appendChild(elem("br"));
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
	var big_div = elem('div', {style:"margin-left: 10px;"});

	var desc_div = elem("div",null, null, 
		"2. Select all acceptible item formats");

	
	var table = elem("table");	

	for( var idx in resourceFormats ) {
		var row = table.insertRow(table.rows.length)
	
		var pic_cell = row.insertCell(0);
		var name_cell = row.insertCell(1);
		var box_cell = row.insertCell(2);
		var box = elem("input", 
			{type:"checkbox", id: resourceFormats[idx] + "_hold_checkbox"}, null);

		if(idx == 0) { /* select text by default */
			box.setAttribute("checked","checked");
			box.checked = true;
		}
		
		pic_cell.appendChild(mkResourceImage(resourceFormats[idx]));
		name_cell.appendChild(mktext(resourceFormats[idx]));
		box_cell.appendChild(mktext(" "));
		box_cell.appendChild(box);
	}

	big_div.appendChild(elem("br"));
	big_div.appendChild(desc_div);
	big_div.appendChild(elem("br"));
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


