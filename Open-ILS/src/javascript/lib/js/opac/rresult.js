var records = new Array();
var table;
var rowtemplate;
var mrid;

function rresultDoSearch() {

	table = getId(config.ids.result.main_table);
	rowtemplate = table.removeChild(getId(config.ids.result.row_template));
	removeChildren(table);
	mrid = getMrid();

	/*
	rresultGetCount();
	rresultCollectIds();
	*/
}
