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

if(!dojo._hasResource['openils.acq.PO']) {

    dojo._hasResource['openils.acq.PO'] = true;
    dojo.provide('openils.acq.PO');
    dojo.require('fieldmapper.Fieldmapper');
    dojo.require('fieldmapper.dojoData');

    /** Declare the PO class with dojo */
    dojo.declare('openils.acq.PO', null, {
        /* add instance methods here if necessary */
    });

    openils.acq.PO.cache = {};

    openils.acq.PO.retrieve = function(id, oncomplete, args) {

        var req = ['open-ils.acq', 'open-ils.acq.purchase_order.retrieve'];
        var par = [openils.User.authtoken, id, args];

        if(oncomplete) {
            fieldmapper.standardRequest(
                req, 
                {   params:par, 
                    async: true,
                    oncomplete:function(r) {
                        var po = r.recv().content();
                        openils.acq.PO.cache[po.id()] = po;
                        oncomplete(po);
                    }
                }
            );
        } else {
            return openils.acq.PO.cache[po.id()] = 
                fieldmapper.standardRequest(req, par);
        }
    }

    openils.acq.PO.create = function(po, oncomplete) {
        var req = ['open-ils.acq', 'open-ils.acq.purchase_order.create'];
        var par = [openils.User.authtoken, po];

        fieldmapper.standardRequest(
            req,
            {   params: par,
                async: true, 
                oncomplete: function(r) {
                    var po_id = r.recv().content();
                    po.id(po_id);
                    openils.acq.PO.cache[po_id] = po;
                    oncomplete(po_id);
                }
            }
        );
    }
};
        

