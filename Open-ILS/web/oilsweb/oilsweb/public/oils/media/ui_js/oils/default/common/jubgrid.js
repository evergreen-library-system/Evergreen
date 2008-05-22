dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.layout.SplitContainer');
dojo.require('dojox.grid.Grid');
dojo.require("openils.acq.Fund");
dojo.require("openils.acq.Lineitems");
dojo.require("openils.widget.FundSelector");
dojo.require("fieldmapper.OrgUtils");
dojo.require('openils.acq.Provider');

/* put all the accessors, etc. into a local object for namespacing */
var JUBGrid = {
    jubGrid : null,
    lineitems : [], // full list of lineitem objects to display 
    getLi : function(id) { 
        // given an ID, returns the lineitem object from the list
        for(var i in JUBGrid.lineitems) {
            var li = JUBGrid.lineitems[i];
            if(li.id() == id)
                return li;
        }
    },

    _getMARCAttr : function(rowIndex, attr) {
        var data = JUBGrid.jubGrid.model.getRow(rowIndex);
        if (!data) return '';
        return new openils.acq.Lineitems(
            {lineitem:JUBGrid.getLi(data.id)}).findAttr(attr, 'lineitem_marc_attr_definition')
    },
    getJUBTitle : function(rowIndex) {
        return JUBGrid._getMARCAttr(rowIndex, 'title');
    },
    getJUBIsbn : function(rowIndex) {
        return JUBGrid._getMARCAttr(rowIndex, 'isbn');
    },
    getJUBPrice : function(rowIndex) {
        return JUBGrid._getMARCAttr(rowIndex, 'price');
    },
    getJUBPubdate : function(rowIndex) {
        return JUBGrid._getMARCAttr(rowIndex, 'pubdate');
    },
    getProvider : function(rowIndex) {
        data = liGrid.model.getRow(rowIndex);
        if(!data || !data.provider) return;
        return openils.acq.Provider.retrieve(data.provider).code();
    },
    getLIDFundName : function(rowIndex) {
        var data = JUBGrid.jubDetailGrid.model.getRow(rowIndex);
        if (!data || !data.fund) return;
        try {
        return openils.acq.Fund.retrieve(data.fund).name();
        } catch (evt) {
        return data.fund;
        }
    },
    getLIDLibName : function(rowIndex) {
        var data = JUBGrid.jubDetailGrid.model.getRow(rowIndex);
        if (!data || !data.owning_lib) return;
        return fieldmapper.aou.findOrgUnit(data.owning_lib).shortname();
    },
    populate : function(gridWidget, model, lineitems) {
        JUBGrid.lineitems = lineitems;
        JUBGrid.jubGrid = gridWidget;
        JUBGrid.jubGrid.setModel(model);
        dojo.connect(gridWidget, "onRowClick", 
            function(evt) {
             openils.acq.Lineitems.loadGrid(
                 JUBGrid.jubDetailGrid, 
                    model.getRow(evt.rowIndex).id, JUBGrid.jubDetailGridLayout);
            });
        gridWidget.update();
    }
};
