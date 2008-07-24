dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.layout.SplitContainer');
dojo.require('dijit.Dialog');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.Button');
dojo.require('dojox.grid.Grid');

dojo.require("openils.User");
dojo.require("openils.acq.Fund");
dojo.require("openils.acq.Lineitem");
dojo.require('openils.acq.Provider');
dojo.require("openils.widget.FundSelector");
dojo.require('openils.editors');
dojo.require('openils.Event');
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
        return new openils.acq.Lineitem(
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
    getJUBActualPrice : function(rowIndex) {
        var data = JUBGrid.jubGrid.model.getRow(rowIndex);
        if (!data) return '';
        var price = new openils.acq.Lineitem(
            {lineitem:JUBGrid.getLi(data.id)}).getActualPrice();
        if(price) return price.price;
        return ''
    },
    getJUBEstimatedPrice : function(rowIndex) {
        var data = JUBGrid.jubGrid.model.getRow(rowIndex);
        if (!data) return '';
	    var price = new openils.acq.Lineitem(
            {lineitem:JUBGrid.getLi(data.id)}).getEstimatedPrice();
        if(price) return price.price;
        return ''
    },
    getJUBPubdate : function(rowIndex) {
        return JUBGrid._getMARCAttr(rowIndex, 'pubdate');
    },
    getProvider : function(rowIndex) {
        data = JUBGrid.jubGrid.model.getRow(rowIndex);
        if(!data || !data.provider) return;
        return openils.acq.Provider.retrieve(data.provider).code();
    },
    getCopyLocation : function(rowIndex) {
        var data = JUBGrid.jubDetailGrid.model.getRow(rowIndex);
        if(!data || !data.location) return '';
        return openils.CopyLocation.retrieve(data.location).name();
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
    getLIDFundCode : function(rowIndex) {
        var data = JUBGrid.jubDetailGrid.model.getRow(rowIndex);
        if (!data || !data.fund) return;
        try {
            return openils.acq.Fund.retrieve(data.fund).code();
        } catch (evt) {
            return data.fund;
        }
    },
    getLIDLibName : function(rowIndex) {
        var data = JUBGrid.jubDetailGrid.model.getRow(rowIndex);
        if (!data || !data.owning_lib) return;
        return fieldmapper.aou.findOrgUnit(data.owning_lib).shortname();
    },

    gridDataChanged : function(newVal, rowIdx, cellIdx) {
        // cellIdx == -1 if you are editing a column that
        // is not represented in the data model. Khaaaaaaan!!! 
    },

    populate : function(gridWidget, model, lineitems) {
        for (var i in lineitems) {
            JUBGrid.lineitems[lineitems[i].id()] = lineitems[i];
        }
        JUBGrid.jubGrid = gridWidget;
        JUBGrid.jubGrid.setModel(model);
        if(JUBGrid.showDetails) {
            dojo.connect(gridWidget, "onRowClick", 
                function(evt) {
                    var jub = model.getRow(evt.rowIndex);
                    var grid;

                    JUBGrid.jubDetailGrid.lineitemID = jub.id;

                    if (jub.state == "approved") {
                        grid = JUBGrid.jubDetailGridLayoutReadOnly;
                    } else {
                        grid = JUBGrid.jubDetailGridLayout;
                    }
                    openils.acq.Lineitem.loadLIDGrid(
                        JUBGrid.jubDetailGrid, 
                        JUBGrid.jubGrid.model.getRow(evt.rowIndex).id, grid);
                }
            );
        }
        gridWidget.update();
    },

    approveJUB: function(evt) {
	var list = [];
	var selected = JUBGrid.jubGrid.selection.getSelected();

	for (var idx = 0; idx < selected.length; idx++) {
	    var rowIdx = selected[idx];
	    var jub = JUBGrid.jubGrid.model.getRow(rowIdx);
	    var li = new openils.acq.Lineitem({lineitem:JUBGrid.getLi(jub.id)});
	    var approveStore = function(evt) {
		if (evt) {
		    // something bad happened
		    console.log("jubgrid.js: approveJUB: error:");
		    console.dir(evt);
		    alert("Error: "+evt.desc);
		} else {
		    var approveACQLI = function(jub, rq) {
			JUBGrid.jubGrid.model.store.setValue(jub,
							     "state",
							     "approved");
			JUBGrid.jubGrid.update();
			// Reload lineitem details, read-only
			openils.acq.Lineitem.loadLIDGrid(
			    JUBGrid.jubDetailGrid, li.id(),
			    JUBGrid.jubDetailGridLayoutReadOnly);
		    };

		    JUBGrid.jubGrid.model.store.fetch({query:{id:jub.id},
						       onItem: approveACQLI});
		}
	    };

	    li.approve(approveStore);
	}
    },

    removeSelectedJUBs: function(evt) {

        function deleteList(list, idx, oncomplete) {
            if(idx >= list.length) 
                return oncomplete();
            fieldmapper.standardRequest([
                'open-ils.acq',
                'open-ils.acq.lineitem.delete'], 
                {   async: true,
                    params: [openils.User.authtoken, list[idx].id()],
                    oncomplete: function(r) {
                        var res = r.recv().content();
                        if(openils.Event.parse(res))
                            alert(openils.Event.parse(res));
                        deleteList(list, ++idx, oncomplete);
                    }
                }
            );
        }

        var lineitems = JUBGrid.lineitems;
        var deleteMe = [];
        var keepMe = [];
        var selected = JUBGrid.jubGrid.selection.getSelected();

        for(var id in lineitems) {
            var deleted = false;
            for(var i = 0; i < selected.length; i++) {
                var rowIdx = selected[i];
	            var jubid = JUBGrid.jubGrid.model.getRow(rowIdx).id;
                if(jubid == id) {
                    deleteMe.push(lineitems[id]);
                    deleted = true;
                }
            }
            if(!deleted) 
                keepMe[id] = lineitems[id];
        }

        JUBGrid.lineitems = keepMe;
        deleteList(deleteMe, 0, function(){
            JUBGrid.jubGrid.model.store = 
                new dojo.data.ItemFileReadStore({data:jub.toStoreData(keepMe)});
            JUBGrid.jubGrid.model.refresh();
            JUBGrid.jubGrid.update();
        });
    },

    deleteLID: function(evt) {
	var list =[];
	var selected = JUBGrid.jubDetailGrid.selection.getSelected();
	for (var idx = 0; idx < selected.length; idx++) {
	    var rowIdx = selected[idx];
	    var lid = JUBGrid.jubDetailGrid.model.getRow(rowIdx);
	    var deleteFromStore = function (evt) {

		if (evt) {
		    // something bad happened
		    alert("Error: "+evt.desc);
		} else {
		    var deleteItem = function(item, rq) {
			JUBGrid.jubDetailGrid.model.store.deleteItem(item);
		    };
		    var updateCount = function(item) {
			var newval = JUBGrid.jubGrid.model.store.getValue(item, "item_count");
			JUBGrid.jubGrid.model.store.setValue(item, "item_count", newval-1);
			JUBGrid.jubGrid.update();
		    };

		    JUBGrid.jubDetailGrid.model.store.fetch({query:{id:lid.id},
							     onItem: deleteItem});
		    JUBGrid.jubGrid.model.store.fetch({query:{id:JUBGrid.jubDetailGrid.lineitemID},
						       onItem: updateCount});
		}
		JUBGrid.jubDetailGrid.update(); 
	    };

	    openils.acq.Lineitem.deleteLID(lid.id, deleteFromStore);
	}
    },

    createLID: function(fields) {
	fields['lineitem'] = JUBGrid.jubDetailGrid.lineitemID;
	var addToStore = function () {
	    JUBGrid.jubDetailGrid.model.store.newItem(fields);
	    JUBGrid.jubDetailGrid.refresh();
	    JUBGrid.jubGrid.update();
	    JUBGrid.jubGrid.refresh();
	}
	openils.acq.Lineitem.createLID(fields, addToStore);
    },
};

