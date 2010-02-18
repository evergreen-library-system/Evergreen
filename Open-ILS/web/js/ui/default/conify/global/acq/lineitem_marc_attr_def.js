dojo.require('openils.widget.AutoGrid');
dojo.require('openils.PermaCrud');
dojo.require('openils.Util');
dojo.require('openils.User');
dojo.require('openils.MarcXPathParser');

var xpathParser = new openils.MarcXPathParser();

function init() {
    attrGrid.loadAll({order_by : {acqlimad : 'code'}});
}

function attrGridGetTag(rowIdx, item) {
    return item && xpathParser.parse(this.grid.store.getValue(item, 'xpath')).tags;
}

function attrGridGetSubfield(rowIdx, item) {
    return item && xpathParser.parse(this.grid.store.getValue(item, 'xpath')).subfields;
}

openils.Util.addOnLoad(init);
