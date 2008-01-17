import osrf.cache, osrf.json, osrf.ses
import oils.const, oils.utils.utils, oils.event

class PicklistMgr(object):
    def __init__(self, request_mgr, **kwargs):
        self.request_mgr = request_mgr
        self.id = kwargs.get('picklist_id')
        self.picklist = kwargs.get('picklist')
        self.ses = osrf.ses.ClientSession(oils.const.OILS_APP_ACQ)

    def retrieve(self):

        picklist = self.ses.request(
            'open-ils.acq.picklist.retrieve', 
            self.request_mgr.ctx.core.authtoken, self.id).recv().content()

        oils.event.Event.parse_and_raise(picklist)
        self.picklist = picklist

    def retrieve_entries(self, **kwargs):
        # grab the picklist entries
        entries = self.ses.request(
            'open-ils.acq.picklist_entry.picklist.retrieve',
            self.request_mgr.ctx.core.authtoken, 
            self.picklist.id(),
            {
                "offset" : kwargs.get('offset'),
                "limit" : kwargs.get('limit'),
                "flesh" : 1,
                "clear_marc" : 1
            }
        ).recv().content()

        self.picklist.entries(entries)

    def retrieve_entry(self, entry_id):
        entry = self.ses.request(
            'open-ils.acq.picklist_entry.retrieve',
            self.request_mgr.ctx.core.auththoken, entry_id).recv.content()
        oils.event.Event.parse_and_raise(entry)
        return entry

    @staticmethod
    def find_entry_attr(entry, attr_name, attr_type='picklist_marc_attr_definition'):
        for entry_attr in entry.attributes():
            if entry_attr.attr_type() == attr_type and entry_attr.attr_name() == attr_name:
                return entry_attr.attr_value()
        return ''

            
