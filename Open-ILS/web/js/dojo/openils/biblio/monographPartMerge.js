/* ---------------------------------------------------------------------------
 * Copyright (C) 2014  C/W MARS Inc.
 * Dan Pearl <dpearl@cwmars.org>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * ---------------------------------------------------------------------------
 */

/*
 * Support for the facility to merge multiple part designations into
 * one.
 */

if(!dojo._hasResource["openils.biblio.monographPartMerge"]) {
    dojo._hasResource["openils.biblio.monographPartMerge"] = true;
    dojo.provide("openils.biblio.monographPartMerge");
    dojo.declare("openils.biblio.monographPartMerge", null, {}); 

    /*
     * Generate a pop-up to control part merging 
     */
    openils.biblio.monographPartMerge.showMergeDialog = function(gridControl) {
         dojo.requireLocalization("openils.biblio","biblio_messages");

	var items = gridControl.getSelectedItems();
	var total = items.length;

	if (total < 2 )	// Validate number of selected items
	    {
  	    alert(dojo.i18n.getLocalization("openils.biblio","biblio_messages").SELECT_TWO);
	    return;
	    }

  	var mergePartsPopup = new dijit.Dialog({title: 
  	        dojo.i18n.getLocalization("openils.biblio","biblio_messages").MERGE_PARTS_TITLE}); 

	var mergeDiv = dojo.create("div");

       /* 
        * Establish handler when an item is clicked upon 
        */ 
	mergeDiv.processMerge = function (obj) {
	    mergePartsPopup.hide();
	    dojo.require('openils.PermaCrud');  

            var searchParams = {};
            searchParams["part"] = new Array() ; 

            /*
             * Establish a list of id's of monograph_parts that are affected by remap. Later, find
             * all copy_part_map items that reference any of these parts 
             */

	    dojo.forEach (this.items, 
               function(item) { 
                      searchParams["part"].push(String(item.id)) 	/* Must be String in json */
               });
	    // var testString = searchParams["part"].join(', ');        /* DEBUG */

	    var pcrud = new openils.PermaCrud();
            var cpmList = pcrud.search("acpm", searchParams);

	    dojo.forEach(cpmList,
		    function (g) {
                       g.part(parseInt(obj.itemID))		/* Assign "winner" DB id of mono_part. */
                       g.ischanged(true);
		    });

           if (cpmList.length > 0) {
               pcrud.apply( cpmList);
           }
 
           /*
            * Close the connection and commit the transaction.  This is necessary to do before
            * the subsequent delete operation (because of ON DELETE CASCADE issues).
            */

	   pcrud.disconnect(); 

           /*
            * Update the AutoGrid to delete the items being mapped out of existence so that 
            * the display reflects the updated situation.
            * Then use a PermaCrud connection to delete/eliminate the object.  This
            * code is adapted from the delete case in AutoGrid.js. Note that this code
            * uses a total==1 as the exit condition (because you are not deleting the 
            * winning/prevailing/surviving part.
            */

	   dojo.forEach (items, 
               function(item) { 
                  if (item.id != parseInt(obj.itemID)) {
                     var fmObject = new fieldmapper[gridControl.fmClass]().fromStoreItem(item);
                     new openils.PermaCrud()['eliminate'](
                            fmObject, {
                                oncomplete : function(r) {
                                    gridControl.store.deleteItem(item);
                                    if (--total == 1 && gridControl.onPostSubmit) {
                                        gridControl.onPostSubmit();
                                    }
                                }
                            }
                      );
                   }
                }
           );

	};

 	mergeDiv.innerHTML = "<div class=\"biblio-merge-prevail-title\" >" +
                              dojo.i18n.getLocalization("openils.biblio","biblio_messages").CLICK_PREVAILING +
                              "</div>";  
	mergeDiv.items = items;

        /* 
         * Create a DIV for each selected item, and put in the container DIV
         */
	for (var i = 0; i < total; i++) {
	    var newDiv = dojo.create("div"); 
  	    newDiv.className = "biblio-merge-item";
	    newDiv.itemID = items[i].id;
	    newDiv.onclick = function() {mergeDiv.processMerge(this);};
	    var newText = new String(items[i].label);
            
            /* To make spacing more visible, replace spaces with a middot character */
	    newText = newText.replace(/ /g, String.fromCharCode(183) /* middot*/);
	    newDiv.appendChild(document.createTextNode( newText ));  
	    mergeDiv.appendChild(newDiv);
	}
	mergePartsPopup.setContent(mergeDiv); 

	mergePartsPopup.show();

    };

}
