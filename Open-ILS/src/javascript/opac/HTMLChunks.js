function RecordResultRow(id) {
	if(id==null)
		throw new EXArg( "RecordResultRow required ID" );

	//var docfrag = document.createDocumentFragment();
	var table	= document.createElement("table");
	var tbody	= document.createElement("tbody");

	var toptd	= document.createElement("td");
	var td1		= document.createElement("td");
	var td2		= document.createElement("td");
	var td3		= document.createElement("td");
	var td4		= document.createElement("td");

	td1.id = "record_result_row_box_" + id;
	add_css_class( td1, "record_result_row_box");

	td2.id = "record_result_title_box_" + id;
	add_css_class( td2, "record_result_title_box");

	td3.id = "record_result_copy_count_box_" + id;
	add_css_class( td3, "record_result_copy_count_box");

	td4.id = "record_result_author_box_" + id;
	add_css_class(td3, "record_result_author_box");

	var row1		= document.createElement("tr");
	var row2		= document.createElement("tr");

	row1.appendChild(td2);
	row1.appendChild(td3);
	row2.appendChild(td4);
	tbody.appendChild(row1);
	tbody.appendChild(row2);
	table.appendChild(tbody);
	td1.appendChild(table);

	this.obj = td1;

}

RecordResultRow.prototype.toString = function() {
	return this.obj.string;
}


function LineDiv(type) {
	if( type == "small")
		this.string = "<div class='small_line_div'></div>";
	else {
		if( type == "big") {
			this.string = "<div class='big_line_div'></div>";
		} else 
			this.string = "<div class='line_div'></div>";
	}
}

LineDiv.prototype.toString = function() {
	return this.string;
}

