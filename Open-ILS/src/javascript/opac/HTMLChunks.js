
function RecordResultRow(id) {

	if(id==null)
		throw new EXArg( "RecordResultRow required ID" );

	var table	= createAppElement("table");
	table.setAttribute("border","1");
	var tbody	= createAppElement("tbody");
	var thead	= createAppElement("thead");

	add_css_class(table,"record_result_row_table");

	var toptd	= createAppElement("td");
	var td1		= createAppElement("td");
	var td2		= createAppElement("td");
	var td4		= createAppElement("td");

	td1.id = "record_result_row_box_" + id;
	add_css_class( td1, "record_result_row_box");

	td2.id = "record_result_title_box_" + id;
	add_css_class( td2, "record_result_title_box");

	td4.id = "record_result_author_box_" + id;
	add_css_class(td4, "record_result_author_box");

	var row1		= createAppElement("tr");
	var row2		= createAppElement("tr");
	row2.id = "record_result_author_row_" + id;

	row1.appendChild(td2);
	row2.appendChild(td4);
	tbody.appendChild(row1);
	tbody.appendChild(row2);
	table.appendChild(thead);
	table.appendChild(tbody);
	td1.appendChild(table);

	this.obj = td1;

}

function addResultRow(row) {
	td1 = row.appendChild( createAppElement("TD") );
}



RecordResultRow.prototype.toString = function() {
	return this.obj.string;
}

function LineDiv(type) {
	this.obj  = createAppElement("div");
	if( type == "small")
		add_css_class(this.obj,"small_line_div");
	else {
		if( type == "big") {
		add_css_class(this.obj,"big_line_div");
		} else 
			add_css_class(this.obj,"line_div");
	}
}

LineDiv.prototype.toString = function() {
	return this.obj.toString();
}

