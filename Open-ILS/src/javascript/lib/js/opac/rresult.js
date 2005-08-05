var records = new Array();
var table;
var rowtemplate;
var mrid;

function rresultDoSearch() {

	table = G.ui.result.main_table;
	rowtemplate = table.removeChild(G.ui.result.row_template);
	removeChildren(table);
	mrid = getMrid();

	/*
	rresultGetCount();
	rresultCollectIds();
	*/
}
