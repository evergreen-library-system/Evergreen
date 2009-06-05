dojo.require('openils.widget.AutoGrid');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.PermaCrud');
var formula;
var formCache = [];

function draw() {

    if(formulaId) {
        openils.Util.hide('formula-list-div');
        drawFormulaSummary();
    } else {

        openils.Util.hide('formula-entry-div');
        fListGrid.onPostCreate = function(fmObject) {
            location.href = location.href + '/' + fmObject.id();
        }

        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.distribution_formula.ranged.retrieve'],
            {   async: true,
                params: [openils.User.authtoken],
                onresponse: function (r) { 
                    var form = openils.Util.readResponse(r);
                    formCache[form.id()] = form;
                    fListGrid.store.newItem(form.toStoreItem());
                }
            }
        );

    }
}
openils.Util.addOnLoad(draw);

function drawFormulaSummary() {
    openils.Util.show('formula-entry-div');
    dfeListGrid.overrideEditWidgets.formula = new
        dijit.form.TextBox({style:'display:none', value: formulaId});
    dfeListGrid.loadAll({order_by:{acqdfe : 'formula'}}, {formula : formulaId});
    var pcrud = new openils.PermaCrud;
    var formulaName = pcrud.retrieve('acqdf', formulaId);
    dojo.byId('formula_head').innerHTML = formulaName.name();
}

function getItemCount(rowIndex, item) {
    if(!item) return '';
    var form = formCache[this.grid.store.getValue(item, "id")];
    if(!form) return 0;
    var count = 0;
    dojo.forEach(form.entries(), function(e) { count = count + e.item_count(); });
    return count;
}

