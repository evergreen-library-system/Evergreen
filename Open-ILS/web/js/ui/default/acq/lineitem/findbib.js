dojo.require('openils.Util');
dojo.require('openils.BibTemplate');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.CGI');
dojo.require('dijit.form.Button');
dojo.require('openils.widget.ProgressDialog');

var limit = 15;
var offset = 0;
var template;
var container;

function drawSearch() {
    container = dojo.byId('acq-findbib-container');
    template = container.removeChild(dojo.byId('acq-findbib-template'));
    var cgi = new openils.CGI();
    searchQuery.attr('value', cgi.param('query') || '');
    searchQuery.domNode.select();
    openils.Util.registerEnterHandler(searchQuery.domNode, doSearch);
}

function doSearch() {
    while(container.childNodes[0])
        container.removeChild(container.childNodes[0])
    progressDialog.show(true);
    var query = searchQuery.attr('value');
    fieldmapper.standardRequest(
        ['open-ils.search', 'open-ils.search.biblio.multiclass.query.staff'],
        {
            async : true,
            params : [{limit : limit}, query, 1],
            oncomplete : drawResult
        }
    );
}

function drawResult(r) {
    progressDialog.hide();
    var result = openils.Util.readResponse(r);
    dojo.forEach(
        result.ids,
        function(id) {
            id = id[0];
            var div = template.cloneNode(true);
            container.appendChild(div);

            var viewMarc = dojo.query('[name=view-marc]', div)[0];
            viewMarc.onclick = function() { showMARC(id); };
            var selectRec = dojo.query('[name=select-rec]', div)[0];
            selectRec.onclick = function() { selectRecord(id); };

            new openils.BibTemplate({
                record : id,
                org_unit : fieldmapper.aou.findOrgUnit(openils.User.user.ws_ou()).shortname(),
                root : div
            }).render();
        }
    );
}

function showMARC(bibId) {
    openils.Util.show(dojo.byId('marc-div'));
    fieldmapper.standardRequest(
        ['open-ils.search', 'open-ils.search.biblio.record.html'],
        {   
            async: true,
            params: [bibId, true],
            oncomplete: function(r) {
                dojo.byId('marc-html-div').innerHTML = openils.Util.readResponse(r);
            }
        }
    );
}

function selectRecord(bibId) {
    if(window.recordFound) {
        window.recordFound(bibId);
    }
}


openils.Util.addOnLoad(drawSearch);

