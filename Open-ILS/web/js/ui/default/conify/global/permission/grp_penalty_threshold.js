dojo.require('dojox.grid.DataGrid');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('dijit.form.NumberTextBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.PermGrp');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.widget.PermGrpFilteringSelect');
dojo.require('fieldmapper.OrgUtils');

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
        fieldmapper.standardRequest(
            ['open-ils.actor', 'open-ils.actor.grp_penalty_threshold.ranged.retrieve'],
            {   async: true,
                params: [openils.User.authtoken, GPT.contextOrg],
                oncomplete: GPT._gridComplete
            }
        );
    },

    init : function() {
        GPT.contextOrg = openils.User.user.ws_ou();

        var connect = function() {
            dojo.connect(GPT.contextOrgSelector, 'onChange',
                function() {
                    GPT.contextOrg = this.getValue();
                    GPT.buildGrid();
                }
            );
        };
        new openils.User().buildPermOrgSelector('VIEW_GROUP_PENALTY_THRESHOLD', GPT.contextOrgSelector, null, connect);

        GPT.loadCsp(
            function() {
                openils.PermGrp.fetchGroupTree(
                    function() { openils.PermGrp.flatten(); GPT.buildGrid(); }
                );
            }
        );
    },

    create : function(args) {
        if(!(args.grp && args.org_unit && args.penalty && args.threshold))
            return;

        var thresh = new pgpt();
        thresh.grp(args.grp);
        thresh.org_unit(args.org_unit);
        thresh.penalty(args.penalty);
        thresh.threshold(args.threshold);

        fieldmapper.standardRequest(
            ['open-ils.permacrud', 'open-ils.permacrud.create.pgpt'],
            {   async: true,
                params: [openils.User.authtoken, thresh],
                oncomplete: function(r) {
                    if(new String(openils.Util.readResponse(r)) != '0')
                        GPT.buildGrid();
                }
            }
        );
    },

    getGroupName : function(rowIdx, item) {
        if(!item) return '';
        var grpId = this.grid.store.getValue(item, this.field);
        return openils.PermGrp.groupIdMap[grpId].name();
    },

    drawCspSelector : function() {
        GPT.penaltySelector.store = 
            new dojo.data.ItemFileReadStore({data:csp.toStoreData(GPT.standingPenalties)});
        GPT.penaltySelector.startup();
    },

    loadCsp : function(onload) {
        GPT.penaltyMap = {};
        fieldmapper.standardRequest(
            ['open-ils.permacrud', 'open-ils.permacrud.search.csp.atomic'],
            {   async: true,
                params: [openils.User.authtoken, {id:{'<':100}}],
                oncomplete: function(r) {
                    if(list = openils.Util.readResponse(r, false, true)) {
                        list = list.sort(
                            function(a, b) {
                                // why not take this opportunity to do some other stuff? ;)
                                GPT.penaltyMap[a.id()] = a;
                                GPT.penaltyMap[b.id()] = b;
                                if(a.id() > b.id()) 
                                    return 1;
                                return -1;
                            }
                        );
                        GPT.standingPenalties = list;
                        if(onload) onload(list);
                    }
                }
            }
        );
    }, 

    getOrgInfo : function(rowIndex, item) {
        if(item) {
            var orgId = this.grid.store.getValue(item, this.field);
            return fieldmapper.aou.findOrgUnit(orgId).shortname();
        }
    },

    getPenaltyInfo : function(rowIndex, item) {
        if(item) {
            var pId = this.grid.store.getValue(item, this.field);
            return GPT.penaltyMap[pId].name();
        }
    }
};

openils.Util.addOnLoad(GPT.init);
