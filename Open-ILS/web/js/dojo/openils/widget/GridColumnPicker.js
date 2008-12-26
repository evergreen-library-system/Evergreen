/* ---------------------------------------------------------------------------
 * Copyright (C) 2008  Georgia Public Library Service
 * Bill Erickson <erickson@esilibrary.com>
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


/**
 * Create a new menu that can be used as a grid column picker.  This version
 * takes advantage of Dojo's 1.2 headerMenu attribute for selecting which
 * columns to display.  As columns are chosen, they are updated on the server
 * with user settings.
 */

if(!dojo._hasResource['openils.widget.GridColumnPicker']) {
    dojo.provide('openils.widget.GridColumnPicker');
    dojo.require('dijit.Menu');
    dojo.require('fieldmapper.Fieldmapper');
    dojo.require('openils.Util');

    dojo.declare(
        'openils.widget.GridColumnPicker',
        [dijit.Menu],
        {

            USER_PERSIST_SETTING : 'ui.grid_columns',

            init : function(grid, persistPrefix, authtoken) {

                this.grid = grid;
                this.persistPrefix = persistPrefix
                this.authtoken = authtoken;
                this.cells = this.grid.structure[0].cells[0];
                var self = this;

                dojo.forEach(this.getChildren(),
                    function(child) {
                        for(var i in self.cells) {
                            var name = self.cells[i].name;
                            if(name == child.attr('label')) {
                                child.field = {label:name, ident:self.cells[i].field};
                                break;
                            }   
                        }
                    }
                );
            },

            onClose : function() {
                this.inherited('onClose',arguments);
                this.persist();
            },

            persist : function() {
                var selected = [];
                var autoFields = [];
                dojo.forEach(this.getChildren(),
                    function(child) {
                        if(child.checked) {
                            selected.push(child.field.ident)
                        }
                    }
                );
                var setting = {};
                setting[this.USER_PERSIST_SETTING+'.'+this.persistPrefix] = {'columns':selected, 'auto':autoFields};
                fieldmapper.standardRequest(
                    ['open-ils.actor', 'open-ils.actor.patron.settings.update'],
                    {   async: true,
                        params: [this.authtoken, null, setting],
                        oncomplete: function(r) {
                            openils.Util.readResponse(r);
                        }
                    }
                );
            } 
        }
    );
}
