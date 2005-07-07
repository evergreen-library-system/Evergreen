/* @target is the object next to which the box should pop up.
	*/
function PopupBox(target, body) {
	this.target = target;
	this.div = elem("div");
	add_css_class(this.div,"popup_box");
	add_css_class(this.div,"hide_me");
	if(body) this.div.appendChild(body);
	getDocument().body.appendChild(this.div);
}

PopupBox.prototype.setBody = function(body) {
	if(body) this.div.appendChild(body);
}

PopupBox.prototype.addNode = function(node) {
	if(node) {
		this.div.appendChild(node);
		this.lines();
	}
}

PopupBox.prototype.addText = function(text) {
	if(text) {
		this.div.appendChild(mktext(text));
		this.lines();
	}
}

PopupBox.prototype.lines = function(count) {
	if(count == null) count = 1;
	for( var x = 0; x < count; x++ ) {
		this.div.appendChild(elem("br"));
	}
}

PopupBox.prototype.title = function(title) {

	if(title != null) {

		var div = elem("div");
		add_css_class(div, "popup_box_title");
		div.appendChild(mktext(title));
		this.lines();

		if(this.div.firstChild)
			this.div.insertBefore(div, this.div.firstChild);
		else
			this.div.appendChild(div);
	}
}


PopupBox.prototype.show = function() {

	remove_css_class(this.div,"hide_me");

	var A = getXYOffsets(this.target, this.div);
	var newx = A[0];
	var newy = A[1];

	var W = getWindowSize();
	var wx = W[0];
	var wy = W[1];


	var x =  getObjectWidth(this.div);
	var y =  getObjectHeight(this.div);

	//alert(wx + " : " + wy + " : " + x + " : " + y + " : " + newx + " : " + newy);

	if( (newx + x) > wx )
		newx = newx - x;

	if( (newy + y) > wy )
		newy = newy - y - getObjectHeight(this.target);

	this.div.style.left = newx;
	this.div.style.top = newy;

	add_css_class(this.div,"show_me");
}

PopupBox.prototype.hide = function() {
	remove_css_class(this.div,"show_me");
	add_css_class(this.div,"hide_me");
}

/* pass in an array of DOM nodes and they will
	be displayed as a group along the box */
PopupBox.prototype.makeGroup = function(group) {

	var center = elem("center");
	var table = elem("table");
	center.appendChild(table);
	add_css_class(table, "popup_box_group");
	var row = table.insertRow(0);

	for(var i = 0; i!= group.length; i++) {
		var cell = row.insertCell(row.cells.length);
		cell.appendChild(group[i]);
	}

	this.div.appendChild(elem("br"));
	this.div.appendChild(center);
}
