dojo.require("dijit.Dialog");
dojo.require('dijit.layout.TabContainer');
dojo.require('dijit.layout.ContentPane');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.TextBox');
dojo.require('dojox.grid.Grid');
dojo.require("fieldmapper.OrgUtils");
dojo.require('openils.Event');
dojo.require('openils.User');
dojo.require('openils.acq.LineitemAttr');

var provider = null;
var marcRegex = /^\/\/\*\[@tag="(\d+)"]\/\*\[@code="(\w)"]$/;
var attrDefStores;


function getOrgInfo(rowIndex) {
    data = providerGrid.model.getRow(rowIndex);
    if(!data) return;
    return fieldmapper.aou.findOrgUnit(data.owner).shortname();
}

function getTag(rowIdx) {
    data = this.grid.model.getRow(rowIdx);
    if(!data) return;
    return data.xpath.replace(marcRegex, '$1');
}

function getSubfield(rowIdx) {
    data = this.grid.model.getRow(rowIdx);
    if(!data) return;
    return data.xpath.replace(marcRegex, '$2');
}


function loadStores(onload) {
    if(attrDefStores) 
        return onload();
    openils.acq.LineitemAttr.createAttrDefStores(
        function(stores) {
            attrDefStores = stores;
            onload();
        }
    )
}


function loadMarcAttrGrid() {
    loadStores(
        function() {
            var store = new dojo.data.ItemFileReadStore({data:attrDefStores.marc});
            var model = new dojox.grid.data.DojoData(
                null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
            liMarcAttrGrid.setModel(model);
            liMarcAttrGrid.update();
        }
    );
}

function loadGeneratedAttrGrid() {
    loadStores(
        function() {
            var store = new dojo.data.ItemFileReadStore({data:attrDefStores.generated});
            var model = new dojox.grid.data.DojoData(
                null, store, {rowsPerPage: 20, clientSort: true, query:{id:'*'}});
            liGeneratedAttrGrid.setModel(model);
            liGeneratedAttrGrid.update();
        }
    );
}

/*
function createOrderRecordField(fields) {
    fields.provider = providerId;
    if(!fields.xpath) 
        fields.xpath = '//*[@tag="'+fields.tag+'"]/*[@code="'+fields.subfield+'"]';
    delete fields.tag;
    delete fields.subfield;
    openils.acq.Provider.createLineitemProviderAttrDef(fields, 
        function(id) {
            loadPADGrid();
        }
    );
}

function setORDesc() {
    var code = dijit.byId('oils-acq-provider-or-code');
    var desc = dijit.byId('oils-acq-provider-or-desc');
    desc.setValue(code.getDisplayedValue());
}

function deleteORDataFields() {
    var list = []
    var selected = padGrid.selection.getSelected();
    for(var idx = 0; idx < selected.length; idx++) 
        list.push(padGrid.model.getRow(selected[idx]).id);
    openils.acq.Provider.lineitemProviderAttrDefDeleteList(
        list, function(){loadPADGrid();});
}
*/


//dojo.addOnLoad(loadLIAttrGrid);


