dojo.require('openils.widget.AutoGrid');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.PermaCrud');

function draw() {
    if (! targetId) {
        pListGrid.loadAll({order_by:{acqedi : "id"}});       
        // The following code does no good ...
//        pListGrid.onPostCreate = function(fmObject) {
//            location.href = location.href + '/' + fmObject.id();
//        };
        return;
    }
   
    var pcrud = new openils.PermaCrud();
    pcrud.retrieve('acqedi', targetId, {
        // ... because this code here does nothing yet
        oncomplete : function(r) {
            console.log('edi_account is' + js2JSON(openils.Util.readResponse(r)));
        }
    });
}

openils.Util.addOnLoad(draw);

