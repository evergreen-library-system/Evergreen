from oilsweb.lib.base import *
import logging, pylons
import oilsweb.lib.context, oilsweb.lib.util
import oilsweb.lib.bib, oilsweb.lib.acq.search
import oils.const, oils.utils.utils
import osrf.net_obj

import simplejson

from osrf.ses import ClientSession
from oils.event import Event
from oils.org import OrgUtil

from oilsweb.lib.request import RequestMgr
from oilsweb.lib.acq.fund import FundMgr
from oilsweb.lib.acq.picklist import PicklistMgr
from oilsweb.lib.acq import provider_mgr

class PicklistController(BaseController):
    
    def view(self, **kwargs):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r, picklist_id=kwargs['id'])
        pl_manager.retrieve()
        pl_manager.retrieve_lineitems(flesh_provider=True,
                                      sort_attr="author",
                                      sort_dir="asc",
                                      offset=r.ctx.acq.offset.value,
                                      limit=r.ctx.acq.limit.value)
        r.ctx.acq.picklist.value = pl_manager.picklist
        r.ctx.acq.picklist_list.value = pl_manager.retrieve_list()
        return r.render('acq/picklist/view.html')
    
    def create(self, **kwargs):
        r = RequestMgr()
        if r.ctx.acq.picklist_name.value:
            picklist = osrf.net_obj.NetworkObject.acqpl()
            picklist.name(r.ctx.acq.picklist_name.value)
            picklist.owner(r.ctx.core.user.value.id())
            picklist_id = ClientSession.atomic_request(
                oils.const.OILS_APP_ACQ,
                'open-ils.acq.picklist.create', r.ctx.core.authtoken.value, picklist)
            Event.parse_and_raise(picklist_id)
            return redirect_to(controller='acq/picklist', action='view', id=picklist_id)
        return r.render('acq/picklist/create.html')
    
    def view_lineitem(self, **kwargs):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r)
        fmgr = FundMgr(r)
        lineitem = pl_manager.retrieve_lineitem(kwargs.get('id'),
                                                flesh_attrs=1,
                                                flesh_provider=1,
                                                flesh_li_details=1)
        pl_manager.id = lineitem.picklist()
        picklist = pl_manager.retrieve()
        r.ctx.acq.picklist.value = pl_manager.picklist
        r.ctx.acq.lineitem.value = lineitem
        r.ctx.acq.lineitem_marc_html.value = oilsweb.lib.bib.marc_to_html(lineitem.marc())
        
        r.ctx.acq.provider_list.value = provider_mgr.list(r)
        r.ctx.acq.fund_list.value = fmgr.retrieve_org_funds()
        
        return r.render('acq/picklist/view_lineitem.html')
    
    
    def json(self, **kwargs):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r, picklist_id=kwargs['id'])
        pl_manager.retrieve()
        pl_manager.retrieve_lineitems(flesh_provider=True,
                                      sort_attr="author",
                                      sort_dir="asc")
        
        items = []
        for title in pl_manager.picklist.entries():
            label = ''.join(PicklistMgr.find_lineitem_attr(title, x) for x in ("title", "publisher", "pubdate", "pagination", "isbn", "price"))
            item = {
                'id': title.id(),
                'copies': title.item_count(),
                'title': PicklistMgr.find_lineitem_attr(title, "title"),
                'isbn': PicklistMgr.find_lineitem_attr(title, "isbn"),
                'price': PicklistMgr.find_lineitem_attr(title, "price"),
                'provider': PicklistMgr.find_lineitem_attr(title, "provider"),
                'label': label
            }
            items.append(item)
        
        pylons.response.headers["Content-type"] = "text/x-json"
        return simplejson.dumps({'identifier': 'id',
                                 'label': 'label',
                                 'items': items
                                 })
    
    
    def list(self):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r)
        r.ctx.acq.picklist_list.value = pl_manager.retrieve_list()
        return r.render('acq/picklist/view_list.html')
    
    def listall(self):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r)
        r.ctx.acq.picklist_list.value = pl_manager.retrieve_list(all=True)
        return r.render('acq/picklist/view_listall.html')
    
    def search(self):
        r = RequestMgr()
        r.ctx.acq.z39_sources.value = oilsweb.lib.acq.search.fetch_z39_sources(r.ctx)
        
        sc = {}
        for data in r.ctx.acq.z39_sources.value.values():
            for key, val in data['attrs'].iteritems():
                sc[key] = val.get('label') or key
        r.ctx.acq.search_classes.value = sc
        keys = sc.keys()
        keys.sort()
        r.ctx.acq.search_classes_sorted.value = keys
        
        return r.render('acq/picklist/search.html')
    
    def do_search(self):
        r = RequestMgr()
        picklist_id = oilsweb.lib.acq.search.multi_search(
            r, oilsweb.lib.acq.search.compile_multi_search(r))
        return redirect_to(controller='acq/picklist', action='view', id=picklist_id)
    
    def delete(self, **kwargs):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r, picklist_id=kwargs['id'])
        pl_manager.delete()
        return redirect_to(controller='acq/picklist', action='list')
    
    
    def delete_lineitem(self, **kwargs):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r)
        lineitem_id = kwargs['id']
        lineitem = pl_manager.retrieve_lineitem(lineitem_id)
        pl_manager.delete_lineitem(lineitem_id)
        return redirect_to(controller='acq/picklist', action='view', id=lineitem.picklist())
    
    def update(self):
        r = RequestMgr()
        ses = ClientSession(oils.const.OILS_APP_ACQ)
        ses.connect()
        page = None
        
        if r.ctx.acq.lineitem_id:
            page = self._update_lineitem_count(r, ses)
        elif r.ctx.acq.picklist_action.value == 'move_selected':
            page = self._move_selected(r, ses)
        
        if not page:
            page = redirect_to(controller='acq/picklist', action='list')
        
        ses.disconnect()
        return page
    
    def update_lineitem(self):
        r = RequestMgr()
        ses = ClientSession(oils.const.OILS_APP_ACQ)
        ses.connect()
        
        if r.ctx.acq.lineitem_detail_id.value:
            # update fund assignment, etc
            detail = ses.request('open-ils.acq.lineitem_detail.retrieve',
                                 r.ctx.core.authtoken.value,
                                 r.ctx.acq.lineitem_detail_id.value).recv().content()
            detail = Event.parse_and_raise(detail)
            
            # Update all the fields that are editable via the form
            detail.fund(r.ctx.acq.fund_id.value)
            
            detail = ses.request('open-ils.acq.lineitem_detail.update',
                                 r.ctx.core.authtoken.value,
                                 detail).recv().content()
            Event.parse_and_raise(detail)
        elif r.ctx.acq.provider_id.value:
            lineitem = ses.request('open-ils.acq.lineitem.retrieve',
                                   r.ctx.core.authtoken.value,
                                   r.ctx.acq.lineitem_id.value).recv().content()
            lineitem = Event.parse_and_raise(lineitem)
            
            lineitem.provider(r.ctx.acq.provider_id.value)
            lineitem = ses.request('open-ils.acq.lineitem.update',
                                   r.ctx.core.authtoken.value,
                                   lineitem).recv().content()
            Event.parse_and_raise(lineitem)
        
        return redirect_to(controller='acq/picklist', action='view_lineitem',
                           id=r.ctx.acq.lineitem_id.value)
    
    def approve_lineitem(self):
        r = RequestMgr()
        ses = ClientSession(oils.const.OILS_APP_ACQ)
        ses.connect
        
        li = ses.request('open-ils.acq.lineitem.retrieve',
                         r.ctx.core.authtoken.value,
                         r.ctx.acq.lineitem_id.value).Recv().content()
        li = Event.parse_and_raise(li)
        
        li.state("approved")
        
        li = ses.request('open-ils.acq.lineitem.update',
                         r.ctx.core.authtoken.value,
                         li).recv().content()
        li = Event.parse_and_raise(li)
        
        return redirect_to(controller='acq/picklist', action='view',
                           id=r.ctx.acq.picklist_id.value)
    
    def _update_lineitem_count(self, r, ses):
        ''' Updates # of copies to order for single lineitem '''
        
        picklist_id = r.ctx.acq.picklist_source_id.value
        lineitem_id = r.ctx.acq.lineitem_id.value
        new_count = int(r.ctx.acq.lineitem_item_count.value)
        
        lineitem = ses.request('open-ils.acq.lineitem.retrieve',
                               r.ctx.core.authtoken.value,
                               lineitem_id, {'flesh_li_details':1}).recv().content()
        lineitem = Event.parse_and_raise(lineitem)
        
        # Make sure the lineitem count is correct.
        lineitem.item_count(len(lineitem.lineitem_details()))
        
        # Can't remove detail records yet
        assert (lineitem.item_count() <= new_count), "Can't delete detail records"
        
        for i in range(new_count - lineitem.item_count()):
            detail = osrf.net_obj.NetworkObject.acqlid()
            detail.lineitem(lineitem.id())
            detail = ses.request('open-ils.acq.lineitem_detail.create',
                                 r.ctx.core.authtoken.value,
                                 detail, dict())
            Event.parse_and_raise(detail)
        
        if (lineitem.item_count() != new_count):
            # Update the number of detail records
            lineitem.item_count(new_count)
        
        lineitem = ses.request('open-ils.acq.lineitem.update',
                               r.ctx.core.authtoken.value, lineitem)
        Event.parse_and_raise(lineitem)
        
        # fail()
        return redirect_to(controller='acq/picklist', action='view',
                           id=picklist_id)
    
    def _move_selected(self, r, ses):
        ''' Moves the selected picklist lineitem's to the destination picklist '''
        for lineitem_id in r.ctx.acq.lineitem_id_list.value:
            
            lineitem = ses.request(
                'open-ils.acq.lineitem.retrieve',
                r.ctx.core.authtoken.value, lineitem_id).recv().content()
            lineitem = Event.parse_and_raise(lineitem)
            
            lineitem.picklist(r.ctx.acq.picklist_dest_id.value)
            
            status = ses.request(
                'open-ils.acq.lineitem.update',
                r.ctx.core.authtoken.value, lineitem).recv().content()
            Event.parse_and_raise(status)
        
        return redirect_to(controller='acq/picklist', action='view',
                           id=r.ctx.acq.picklist_dest_id.value)


