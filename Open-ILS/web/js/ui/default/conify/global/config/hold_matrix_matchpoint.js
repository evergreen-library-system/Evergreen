dojo.require('dojox.grid.DataGrid');
dojo.require('dojox.grid.cells.dijit');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('fieldmapper.OrgUtils');
//dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.PermGrp');
dojo.require('openils.PermaCrud');

var marcType = {};
var marcForm = {};
var vrForm = {};
var pcrud = new openils.PermaCrud();
var hmCache = [];

function getOrgInfo(rowIndex, item) {
    if(!item) return '';
    var orgId = this.grid.store.getValue(item, this.field);
    if(orgId != null) {
        return fieldmapper.aou.findOrgUnit(orgId).shortname();
    }
    return '';
}
function getGroupName (rowIndex, item) {
    if(!item) return '';
    var grpId = this.grid.store.getValue(item, this.field);
    if (grpId != null) {
        grpName = openils.PermGrp.groupIdMap[grpId].name();
        return grpName;
    }
    return '';
}
function getMarcType(rowIndex, item) {
    if(!item) return '';
    var mt = this.grid.store.getValue(item, this.field);
    if(mt != null){
        mtObject = marcType[mt];
        return mtObject.value();
    }
    return'';
}
function getMarcForm(rowIndex, item){
    if(!item) return '';
    var mf = this.grid.store.getValue(item, this.field);
    if(mf != null){
        mfObject = marcForm[mf];
        return mfObject.value();
    }
    return'';
}
function getVrForm(rowIndex, item){
    if(!item) return '';
    var vr = this.grid.store.getValue(item, this.field);
    console.log(vr);
    if(vr != null){
        vrObject = vrForm[vr];
        return vrObject.value();
    }
    return'';
}
function formatReference(inDatum) {
    switch (inDatum) {
        case 't':
            return "<span style='color:green;'>&#x2713;</span>";
        case 'f':
            return "<span style='color:red;'>&#x2717;</span>";
    default:
        return '';
    }
}

function init() {
    var pending = 4

    pcrud.retrieveAll(
        'citm',
        { async : true,
          oncomplete: function (r) {
             var list = openils.Util.readResponse(r);
              marcType = openils.Util.mapList(list, 'code', true);
              if(--pending == 0) {
                  buildHMGrid();
              }
          }
        }
    );
    pcrud.retrieveAll(
        'cifm',
        { async : true,
          oncomplete: function (r) {
              var list = openils.Util.readResponse(r);
              marcForm = openils.Util.mapList(list, 'code', true);
              if(--pending == 0) {
                  buildHMGrid();
              }
          }
        }
    );
    pcrud.retrieveAll(
        'cvrfm',
        { async : true,
          oncomplete: function (r) {
              var list = openils.Util.readResponse(r);
              vrForm = openils.Util.mapList(list, 'code', true);
              if(--pending == 0) {
                  buildHMGrid();
              }
          }
        }
    );
    openils.PermGrp.fetchGroupTree(
        function() {
            openils.PermGrp.flatten();
            if(--pending == 0) {
                  buildHMGrid();
              }
        }
    );
}
function buildHMGrid() {
    var store = new dojo.data.ItemFileWriteStore({data:chmm.initStoreData('id', {identifier:'id'})});
    hmGrid.setStore(store);
    hmGrid.render();

    fieldmapper.standardRequest(
        ['open-ils.pcrud', 'open-ils.pcrud.search.chmm'],
        {   async: true,
            params: [openils.User.authtoken, {id:{'!=':null}}],
            onresponse: function (r) {
                if(obj = openils.Util.readResponse(r)) {
                    store.newItem(chmm.itemToStoreData(obj));
                    // cmCache[obj.code()] = obj;
                }
           }
        }
    );
}
function deleteFromGrid() {
    _deleteFromGrid(hmGrid.selection.getSelected(), 0);
}   

function _deleteFromGrid(list, idx) {
    if(idx >= list.length) // we've made it through the list
        return;

    var item = list[idx];
    var id = hmGrid.store.getValue(item, 'id');

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.delete.chmm'],
        {   async: true,
            params: [openils.User.authtoken, id],
            oncomplete: function(r) {
                if(stat = openils.Util.readResponse(r)) {
                    // delete succeeded, remove it from the grid and the local cache
                    hmGrid.store.deleteItem(item); 
                    delete hmCache[item.code];
                }
                _deleteFromGrid(list, ++idx);
            }
        }
    );
}

openils.Util.addOnLoad(init);