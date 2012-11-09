

    var g = {};
    var templateList;
    var template;
    var DEFAULT = "--Default--"

function getSearchStash() {

        try 
        {

         //   netscape.security.PrivilegeManager.enablePrivilege("UniversalXPConnect");
            if (typeof JSAN == 'undefined') 
        { 
            throw( document.getElementById("commonStrings").getString('common.jsan.missing') ); 
        }

                JSAN.errorLevel = "die"; // none, warn, or die
                JSAN.addRepository('/xul/server/');
                JSAN.use('util.error'); 
        g.error = new util.error();
                g.error.sdump('D_TRACE','getSearchStash() from search_settings.tt2 or search.tt2');

        JSAN.use('OpenILS.data'); 
        g.data = new OpenILS.data();
        g.data.stash_retrieve();

        //populate templateList, or not.
        if (g.data.search_templates)
        {		
            templateList = g.data.search_templates;
            
            //check for current template
            if (g.data.current_search_template)
            {
                template = g.data.current_search_template;
            }
        }
        else
        {
            templateList = new Array();
        }
        
        

            } catch(E) {
                try { g.error.standard_unexpected_error_alert('search_settings.tt2',E); } catch(F) { alert(E); }
        return 0;
            }
        }
        

//Creates or edits, maybe, a search template based off the currently selected values
function create_template(tName) {
    var template;
    if (!tName || tName == DEFAULT)
    {
        alert("That is not a valid name.");
        return;
    }

    template = getTemplateByName(tName, templateList);
    
    if (template == null)
    {
        
        var isNew = 1;
        template = new Object();
        populateTemplate(template);
        this.template = template;
        templateList.push(template);
        templateList.sort(compareTemplates)
    }
    else
    {
        if (confirm("Do you want to overwrite " + template.name + " template?"))
        {
            populateTemplate(template);
            this.template = template;
        }
        else
        { return;} 
        
    }
    saveCurrentTemplate( template );

    saveTemplateList(templateList);

    //Add to templateSel and select if new template
    if(isNew)
    { 
        populateTemplateOptions(templateList);
        selectOptionValue(templateSel, template.name);
    }
}//Returns the selected values of of a given element 
function getSelectedValues(elmnt)
    {
        
    elmntVals = [];
        var x = 0;
            for (x=0;x<elmnt.length;x++)
        {

            if (elmnt[x].selected)
            {
            elmntVals.push(elmnt[x].value);	
            }
        }
    return elmntVals;
    }

//Select options in element whose values are equal to the values submitted
function selectOptionValues(elmnt, values){
        elmnt.selectedIndex = -1;
    for(var i=0; i < elmnt.options.length; i++)
            {
            for (v in values)
        {   				
                if(elmnt.options[i].value == values[v])
            {
                    elmnt.options[i].selected = true;
                break;
                }
        }
    }
}//Saves templateList to File in JSON format.
function saveTemplateListToFile( templateList ) {
            try {
               // netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
                JSAN.use('util.file'); 
        var file = new util.file('search_templates');
                file.write_content( 'truncate', String( JSON.stringify(templateList) ) );
                file.close();
        alert("Template List has been updated.");
            } catch(E) {
                try { g.error.standard_unexpected_error_alert('saving in search_settings.tt2',E); } catch(F) { alert(E); }
            }
        }

//Saves current template name to file
function saveCurrentTemplateToFile( template ) {
            try {
                //netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
                JSAN.use('util.file'); 
        var file = new util.file('yesterdays_search_template');
                file.write_content( 'truncate', String( JSON.stringify(template) ) );
                file.close();
            } catch(E) {
                try { g.error.standard_unexpected_error_alert('saving in search_settings.tt2',E); } catch(F) { alert(E); }
            }
        }

//Populates dropdown from given ctype list
function populateCtypeOptions(elmnt, ctypeList)
    {
        var len = ctypeList.length;
        for(var i=0; i<len; i++)
        {
                elmnt.options[i]= new Option(ctypeList[i].value(), ctypeList[i].code());					
        }

    }

//Populates template dropdown from given template list
function populateTemplateOptions(templateList)
    {
        templateSel.options.length = 0;
        templateSel.options[0]= new Option(DEFAULT, "");
        var len = templateList.length;
        
        for(var i=1; i<=len; i++)
        {
                templateSel.options[i]= new Option(templateList[i-1].name, templateList[i-1].name);
            if (template && template.name == templateList[i-1].name)
            {		
                templateSel.options[i].selected= true;
            }
            }

    }
//returns template with a given name from templatelist
function getTemplateByName(templateName, templateList)
    {
        var len = templateList.length;
            
        for(var i=0; i<len; i++){
                if (templateList[i].name == templateName)
            {
                return templateList[i];
            }
            }
        return null;
    }

//returns template's index value in templateList with a given name from templatelist
function getTemplateIndex(templateName, templateList)
    {
        var len = templateList.length;
            
        for(var i=0; i<len; i++){
                if (templateList[i].name == templateName)
            {
                return i;
            }
            }
        return null;
    }

    
function populateTemplate(template)
    {
        template.name = document.getElementById("nameInput").value;
        template.gRows = getGlobalRowValues();
        template.attrFilters = getFilterValues();
        template.pubdate = pubdateSel.value;
        template.org = orgSel.value;
        template.sort = sortBySel.value;
        template.view = resultViewSel.value;
        template.modifier = document.getElementById("modifier").checked;
    }

function getGlobalRowValues(){

    var tBody = document.getElementById("adv_global_tbody");
    var rows = tBody.getElementsByTagName("tr");
    var gRows = [];
    for (var i=0; i<rows.length; i++)
        {	
            gRows[i] = {};
            var tds = rows[i].getElementsByTagName("td");
            var gSels = tds[0].getElementsByTagName("select");
            for (var s = 0; s<gSels.length; s++)
            {			
                gRows[i][gSels[s].name] = gSels[s].value; 	
            }
            
        }		
        return gRows;
    }
    
function getFilterValues()   {
    var filters = [];
    for (var s = 0; s < attrFilters.length; s++)
    {
        filters[s] = getSelectedValues(attrFilters[s]);
    }
    return filters;
}//Select the apropriate search options given a search template
function populateSearchOptions(template) {
    setFilterValues(template);
    selectOptionValue(pubdateSel, template.pubdate);
        if (template.pubdate == "between")
            { unHideMe(document.getElementById("adv_global_pub_date_2_span")); }
        else
            { hideMe(document.getElementById("adv_global_pub_date_2_span")); }

    selectOptionValue(orgSel, template.org);
    selectOptionValue(sortBySel, template.sort);

    selectOptionValue(resultViewSel, template.view);
    modCheck.checked = template.modifier;
    setGlobalRowValues(template);
}

function clearOptions()
    {
        resultViewSel.selectedIndex = 0;
        modCheck.checked = false;
        clearGlobalRowValues();
        clearSearchFilters();
        hideMe(document.getElementById("adv_global_pub_date_2_span")); 
    }
    
function clearSearchFilters() {
        for (var s = 0; s < attrFilters.length; s++)
        {
            if (attrFilters[s].multiple)
            { attrFilters[s].selectedIndex = -1; }
            else
            { attrFilters[s].selectedIndex = 0; }
        }
    }

function selectSearchTemplate(tName)
    {
        template = getTemplateByName(tName, templateList);

        saveCurrentTemplate( template );
            if (template)
        { populateSearchOptions(template); }	
    }

function selectSearchTemplateOrClear(tName)
    {
        template = getTemplateByName(tName, templateList);

        saveCurrentTemplate( template )
        
        if (template)
        { populateSearchOptions(template); }
        else
        { 
            clearOptions(); 
        }		
    }
function selectSearchTemplateOrClearAll(tName)
    {
        selectSearchTemplateOrClear(tName);
        clearGlobalRowInputs();
        clearPubDateInputs();
    }
function clearAll() 
    {
        clearOptions();
        clearGlobalRowInputs();
        clearPubDateInputs();
    }

//Make selections in the "global_row.tt2" according to the given search template
function setGlobalRowValues(template){
    var tBody = document.getElementById("adv_global_tbody");
    var rows = tBody.getElementsByTagName("tr");
    var gRows = [];
    for (var i=0; i<rows.length; i++)
        {	
            var tds = rows[i].getElementsByTagName("td");
            var gRowSels = tds[0].getElementsByTagName("select");
            gRow = template.gRows[i];
            var qtypeSel;
            var containsSel;
            for (var s = 0; s<gRowSels.length; s++)
            {	
                selectOptionValue(gRowSels[s], gRow[gRowSels[s].name]);	
            }
        }	
    }
    
function setFilterValues(template) {
    for (var s = 0; s < attrFilters.length; s++)
    {
        selectOptionValues(attrFilters[s], template.attrFilters[s]);
    }
}//select the first option in each Select in the "global_row.tt2)
function clearGlobalRowValues() {
    var tBody = document.getElementById("adv_global_tbody");
    var rows = tBody.getElementsByTagName("tr");
    for (var i=0; i<rows.length; i++)
        {	
            
            var tds = rows[i].getElementsByTagName("td");
            var gRowSels = tds[0].getElementsByTagName("select");
            for (var s = 0; s<gRowSels.length; s++)
            {	
                gRowSels[s].selectedIndex = 0;	
            }
            
        }	
    }

//Select a single value in an element
function selectOptionValue(elmnt, value) {

    for(var i=0; i < elmnt.options.length; i++)
            {  			
                if(elmnt.options[i].value == value)
            {
                    elmnt.options[i].selected = true;
                break;
                }
        }
    }

function compareTemplates(templateA,templateB) {
    if (templateA.name < templateB.name)
        { return -1; }
    if (templateA.name > templateB.name)
        { return 1; }
    else
        { return 0; }
}

function deleteTemplatefromTemplateList(tName, templateList) {
        var index = getTemplateIndex(tName, templateList);
        templateList.splice(index,1);

        saveTemplateList(templateList);
        
        return templateList;
    }

function removeTemplate(templateList, currentTemplate)  {
        
        var tempTemplate = getTemplateByName(textIn.value, templateList);
        
        if (tempTemplate)
        {			
            if(confirm("Are you sure you want to delete Template '" + tempTemplate.name + "'?"))
            {			
                deleteTemplatefromTemplateList(tempTemplate.name, templateList);
                populateTemplateOptions(templateList);
                
                //deleted template is the current template in use
                if (currentTemplate.name == tempTemplate.name)
                {
                
                    saveCurrentTemplate(null);
                    clearOptions();				
                    templateSel.selectedIndex = 0;
                }
                else
                {
                    selectOptionValue(templateSel, currentTemplate.name);
                }
                textIn.value = "";
                        
            }
            else {
                return;
            }
        }
        else {
            alert("Template '" + textIn.value + "' does not exist.");
        }
    }

function saveTemplateList(templateList)
    {
        //cache templateList	
        g.data.search_templates = templateList; 
        g.data.stash('search_templates');
        saveTemplateListToFile(templateList);
}

function saveCurrentTemplate(template)
    {
        g.data.current_search_template = template; 
        g.data.stash('current_search_template');
        saveCurrentTemplateToFile(template) 
}

function clearGlobalRowInputs() {
    var tBody = document.getElementById("adv_global_tbody");
    if(tBody) {	
        var rows = tBody.getElementsByTagName("tr");
        if(rows.length > 0)			
        for (var i=0; i<rows.length; i++)
            {	
                var tds = rows[i].getElementsByTagName("td");
                if (tds.length > 0) {
                    var inputs = tds[0].getElementsByTagName("input");
                    if (inputs.length > 0) {
                        inputs[0].value = '';
                    }
                }
            }
        }
    }
function clearPubDateInputs()
    {
        document.getElementById("adv_global_pub_date_1").value = '';
        document.getElementById("adv_global_pub_date_2").value = '';
    }
    