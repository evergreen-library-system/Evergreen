dojo.require('dojox.grid.DataGrid');
dojo.require('dojox.grid.cells.dijit');
dojo.require('dojo.data.ItemFileWriteStore');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.CurrencyTextBox');
dojo.require('dijit.Dialog');
dojo.require('dojox.widget.PlaceholderMenuItem');
dojo.require('fieldmapper.OrgUtils');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.PermaCrud');

var svCache = {};
var surveyMap;
var svId;
var questionId;


/** really need to put this in a shared location... */
function getOrgInfo(rowIndex, item) {
    if(!item) return '';
    var orgId = this.grid.store.getValue(item, this.field);
    return fieldmapper.aou.findOrgUnit(orgId).shortname();
}

function getDateTimeField(rowIndex, item) {
    if(!item) return '';
    var data = this.grid.store.getValue(item, this.field);
    var date = dojo.date.stamp.fromISOString(data);
    return dojo.date.locale.format(date, {formatLength:'short'});
}

function formatBool(inDatum) {
    switch (inDatum) {
        case 't':
            return "<span style='color:green;'>&#x2713;</span>";
        case 'f':
            return "<span style='color:red;'>&#x2717;</span>";
    default:
        return'';
    }
}

function endSurvey() {
    _endSurvey(svGrid.selection.getSelected(), 0);
}   

function _endSurvey(list, idx) {
    if(idx >= list.length) // we've made it through the list
        return;
   
    var item = list[idx];
    var svId = svGrid.store.getValue(item, 'id');
    var pcrud = new openils.PermaCrud();
    var survey = pcrud.retrieve('asv', svId);
    console.log(survey);
    var today = new Date();
    var date = dojo.date.stamp.toISOString(today);
    survey.end_date(date);
    survey.ischanged(true);
    pcrud.update(survey);
    _endSurvey(list, ++idx);               

}

function buildSVGrid() {
    var store = new dojo.data.ItemFileWriteStore({data:asv.initStoreData('id', {identifier:'id'})});
    svGrid.setStore(store);
    svGrid.render();
    var user = new openils.User();
    var pcrud = new openils.PermaCrud();
    var retrieveSurveys = function(orgList) {
              pcrud.search('asv',
                     {owner : orgList},
                     {
                         async : true,
                         streaming : true,
                         onresponse : function(r) {
                             var survey = openils.Util.readResponse(r);
                             if(!survey) return'';
                             svCache[survey.id()] = survey;
                             store.newItem(survey.toStoreItem());
                         }
                     }
                    );
    }
    user.getPermOrgList('ADMIN_SURVEY', retrieveSurveys, true, true);

}

function svPage() {
    var pcrud = new openils.PermaCrud();
    var survey = pcrud.retrieve('asv', surveyId);
    dojo.byId("name").innerHTML = survey.name();
    dojo.byId("description").innerHTML = survey.description();
    dojo.byId("start_date").innerHTML = survey.start_date();
    dojo.byId("end_date").innerHTML = survey.end_date();
    dojo.byId("opac").innerHTML = survey.opac();
    dojo.byId("poll").innerHTML = survey.poll();
    dojo.byId("required").innerHTML = survey.required();
    dojo.byId("usr_summary").innerHTML = survey.usr_summary();
    dojo.byId("svQuestion").innerHTML = survey.question();
    dojo.byId("svAnswer").innerHTML = survey.answer();
    
}

function svNewSurvey() {
    new openils.User().buildPermOrgSelector('ADMIN_SURVEY', asvOwningOrg);
    svSurveyDialog.show();

}

function svCreate(args) {
  
    var sv = new asv();
    sv.name(args.svName);
    sv.owner(args.svOwner);
    sv.description(args.svDescription);
    sv.start_date(args.svStart_date);
    sv.end_date(args.svEnd_date);
    if(args.svPoll == 'on')
        sv.poll('t')
        else
            sv.poll('f');

    if(args.svPoll == 'on')
        sv.poll('t')
        else
            sv.poll('f');

    if(args.svOpac == 'on')
        sv.opac('t')
        else
            sv.opac('f');

    if(args.svRequired == 'on')
        sv.required('t')
        else
            sv.required('f');

    if(args.svUsr_summary == 'on')
        sv.usr_summary('t')
        else
            sv.usr_summary('f');
    console.log(sv.name());
    var pcrud = new openils.PermaCrud();
    pcrud.create(sv,
                 {           
                     oncomplete: function(r) {
                         var obj = openils.Util.readResponse(r);
                         if(!obj) return console.log('no obj');
                         svGrid.store.newItem(asv.toStoreItem(obj));
                         svSurveyDialog.hide();
                         svId = obj.id();
                         document.location.href = "/eg/conify/global/action/survey/edit/"+svId;
                         //redirect(svId);
                     }
                 }
                 );
}

function redirect(svId) {

}
    

function deleteFromGrid() {
    _deleteFromGrid(svGrid.selection.getSelected(), 0);
}   

function _deleteFromGrid(list, idx) {
    if(idx >= list.length) // we've made it through the list
        return;

    var item = list[idx];
    var code = svGrid.store.getValue(item, 'id');
  
    fieldmapper.standardRequest(
       ['open-ils.circ', 'open-ils.circ.survey.delete.cascade'],
       {   async: true,
               streaming: true,
               params: [openils.User.authtoken, code],
               onresponse: function(r) {
               if(stat = openils.Util.readResponse(r)) {
                   console.log(stat);
                   svGrid.store.deleteItem(item); 
                   // buildSVGrid();
               }
               _deleteFromGrid(list, ++idx);               
               
           }
       }
    );
}
openils.Util.addOnLoad(buildSVGrid);


