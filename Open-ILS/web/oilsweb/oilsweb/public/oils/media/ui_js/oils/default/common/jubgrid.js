dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.layout.SplitContainer');
dojo.require('dijit.Dialog');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.Grid');

dojo.require("openils.User");
dojo.require("openils.acq.Fund");
dojo.require("openils.acq.Lineitems");
dojo.require('openils.acq.Provider');
dojo.require("openils.widget.FundSelector");
dojo.require('openils.editors');
dojo.require("openils.widget.OrgUnitFilteringSelect");
dojo.require("fieldmapper.OrgUtils");

var globalUser = new openils.User();

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
    getJUBAuthor : function(rowIndex) {
        return JUBGrid._getMARCAttr(rowIndex, 'author');
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
        data = JUBGrid.jubGrid.model.getRow(rowIndex);
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
		JUBGrid.jubDetailGrid.lineitemID = model.getRow(evt.rowIndex).id;
		openils.acq.Lineitems.loadGrid(
                    JUBGrid.jubDetailGrid, 
                    JUBGrid.jubGrid.model.getRow(evt.rowIndex).id, JUBGrid.jubDetailGridLayout);
            });
        gridWidget.update();
    },
    deleteLID: function(evt) {
	var list =[];
	var selected = JUBGrid.jubDetailGrid.selection.getSelected();
	for (var idx = 0; idx < selected.length; idx++) {
	    var rowIdx = selected[idx];
	    var lid = JUBGrid.jubDetailGrid.model.getRow(rowIdx);
	    var deleteFromStore = function () {
		var deleteItem = function(item, rq) {
		    JUBGrid.jubDetailGrid.model.store.deleteItem(item);
		};
		JUBGrid.jubDetailGrid.model.store.fetch({query:{id:lid.id},
							 onItem: deleteItem});
	    };

	    openils.acq.Lineitems.deleteLID(lid.id, deleteFromStore);
	    JUBGrid.jubDetailGrid.update();

	    var updateCount = function(item) {
		var newval = JUBGrid.jubGrid.model.store.getValue(item, "item_count");
		JUBGrid.jubGrid.model.store.setValue(item, "item_count", newval-1);
		JubGrid.jubGrid.update();
	    };

	    JUBGrid.jubGrid.model.store.fetch({query:{id:JUBGrid.jubDetailGrid.lineitemID},
					       onItem: updateCount});
	}
    },
    createLID: function(evt) {
	console.dir(evt);
    },
};

