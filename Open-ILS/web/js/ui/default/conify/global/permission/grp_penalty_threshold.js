dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.form.NumberTextBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.PermGrp');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.widget.PermGrpFilteringSelect');

var GPT = {

    _gridComplete : function(r) {
        if(GPT.list = openils.Util.readResponse(r, false, true)) {
            GPT.list = GPT.list.sort(
                function(a, b) {
                    if(a.id() > b.id()) 
                        return 1;
                    return -1;
                }
            );
            var store = new dojo.data.ItemFileReadStore({data:pgpt.toStoreData(GPT.list)});
            gptGrid.setStore(store);
            gptGrid.render();
        }
    },

    buildGrid  : function() {
        openils.PermGrp.fetchGroupTree(
            function() {
                openils.PermGrp.flatten();
                fieldmapper.standardRequest(
                    ['open-ils.permacrud', 'open-ils.permacrud.search.pgpt.atomic'],
                    {   async: true,
                        params: [openils.User.authtoken, {id:{'!=':null}}],
                        oncomplete: GPT._gridComplete
                    }
                );
            }
        );
    },

    create : function(args) {

        return alert(js2JSON(args));

        if(!(args.name && args.label)) return;

        var penalty = new pgpt();
        penalty.name(args.name);
        penalty.label(args.label);


        fieldmapper.standardRequest(
            ['open-ils.permacrud', 'open-ils.permacrud.create.pgpt'],
            {   async: true,
                params: [openils.User.authtoken, penalty],
                oncomplete: function(r) {
                    if(new String(openils.Util.readResponse(r)) != '0')
                        gptBuildGrid();
                }
            }
        );
    },

    getGroupName : function(rowIdx, item) {
        if(!item) return '';
        var grpId = this.grid.store.getValue(item, this.field);
        return openils.PermGrp.groupIdMap[grpId].name();
    },

    _loadCspComplete : function(r) {
        if(list = openils.Util.readResponse(r, false, true)) {
            list = list.sort(
                function(a, b) {
                    if(a.id() > b.id()) 
                        return 1;
                    return -1;
                }
            );
            GPT.penaltySelector.store = 
                new dojo.data.ItemFileReadStore({data:csp.toStoreData(list)});
            GPT.penaltySelector.startup();

        }
    },

    loadCsp : function() {
        fieldmapper.standardRequest(
            ['open-ils.permacrud', 'open-ils.permacrud.search.csp.atomic'],
            {   async: true,
                params: [openils.User.authtoken, {id:{'!=':null}}],
                oncomplete: GPT._loadCspComplete
            }
        );
    }
};

openils.Util.addOnLoad(GPT.buildGrid);
