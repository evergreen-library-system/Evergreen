from oilsweb.lib.base import *
from oilsweb.lib.request import RequestMgr
import logging, pylons
import oilsweb.lib.context, oilsweb.lib.util
import oilsweb.lib.bib, oilsweb.lib.acq.search, oilsweb.lib.acq.picklist
import oils.const, oils.utils.utils
from osrf.ses import ClientSession
from oils.event import Event
from oils.org import OrgUtil



class PicklistController(BaseController):

    def view(self, **kwargs):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r, picklist_id=kwargs['id'])
        pl_manager.retrieve()
        pl_manager.retrieve_entries(flesh_provider=True, offset=r.ctx.acq.offset, limit=r.ctx.acq.limit)
        r.ctx.acq.picklist = pl_manager.picklist
        r.ctx.acq.picklist_list = pl_manager.retrieve_list()
        return r.render('acq/picklist/view.html')

    def create(self, **kwargs):
        r = RequestMgr()
        if r.ctx.acq.picklist_name:
            picklist = osrf.net_obj.NetworkObject.acqpl()
            picklist.name(r.ctx.acq.picklist_name)
            picklist.owner(r.ctx.core.user.id())
            picklist_id = ClientSession.atomic_request(
                oils.const.OILS_APP_ACQ,
                'open-ils.acq.picklist.create', r.ctx.core.authtoken, picklist)
            Event.parse_and_raise(picklist_id)
            return redirect_to(controller='acq/picklist', action='view', id=picklist_id)
        return r.render('acq/picklist/create.html')

    def view_entry(self, **kwargs):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r)
        entry = pl_manager.retrieve_entry(kwargs.get('id'), flesh=1, flesh_provider=True)
        pl_manager.id = entry.picklist()
        picklist = pl_manager.retrieve()
        r.ctx.acq.picklist = pl_manager.picklist
        r.ctx.acq.picklist_entry = entry
        r.ctx.acq.picklist_entry_marc_html = oilsweb.lib.bib.marc_to_html(entry.marc())
        return r.render('acq/picklist/view_entry.html')

    def list(self):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r)
        r.ctx.acq.picklist_list = pl_manager.retrieve_list()
        return r.render('acq/picklist/view_list.html')
         

    def search(self):
        r = RequestMgr()
        r.ctx.acq.z39_sources = oilsweb.lib.acq.search.fetch_z39_sources(r.ctx)

        sc = {}
        for data in r.ctx.acq.z39_sources.values():
            for key, val in data['attrs'].iteritems():
                sc[key] = val.get('label') or key
        r.ctx.acq.search_classes = sc
        keys = sc.keys()
        keys.sort()
        r.ctx.acq.search_classes_sorted = keys
            
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


    def delete_entry(self, **kwargs):
        r = RequestMgr()
        pl_manager = oilsweb.lib.acq.picklist.PicklistMgr(r)
        entry_id = kwargs['id']
        entry = pl_manager.retrieve_entry(entry_id)
        pl_manager.delete_entry(entry_id)
        return redirect_to(controller='acq/picklist', action='view', id=entry.picklist())

    def update(self):
        r = RequestMgr()
        ses = ClientSession(oils.const.OILS_APP_ACQ)
        ses.connect()

        page = redirect_to(controller='acq/picklist', action='list')

        if r.ctx.acq.picklist_action == 'move_selected':
            page = self._move_selected(r, ses)

        ses.disconnect()
        return page

    def _move_selected(self, r, ses):
        ''' Moves the selected picklist entry's to the destination picklist '''
        for entry_id in r.ctx.acq.picklist_entry_id_list:

            entry = ses.request(
                'open-ils.acq.picklist_entry.retrieve',
                r.ctx.core.authtoken, entry_id).recv().content()
            entry = Event.parse_and_raise(entry)

            entry.picklist(r.ctx.acq.picklist_dest_id)

            status = ses.request(
                'open-ils.acq.picklist_entry.update',
                r.ctx.core.authtoken, entry).recv().content()
            Event.parse_and_raise(status)

        return redirect_to(controller='acq/picklist', action='view', id=r.ctx.acq.picklist_dest_id)


