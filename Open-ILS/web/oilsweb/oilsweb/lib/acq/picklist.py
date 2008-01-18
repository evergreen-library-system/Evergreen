import osrf.cache, osrf.json, osrf.ses, osrf.net_obj
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

        if kwargs.get('flesh_provider'):
            for entry in entries:
                if entry.provider():
                    provider = self.ses.request(
                        'open-ils.acq.provider.retrieve', 
                        self.request_mgr.ctx.core.authtoken, 
                        entry.provider()).recv().content()
                    entry.provider(provider)

        self.picklist.entries(entries)

    def retrieve_list(self):
        ''' Returns my list of picklist objects '''
        list = self.ses.request(
            'open-ils.acq.picklist.user.retrieve', 
            self.request_mgr.ctx.core.authtoken).recv().content()
        oils.event.Event.parse_and_raise(list)
        return list
        

    def retrieve_entry(self, entry_id, **kwargs):
        args = {'flesh': kwargs.get('flesh')}
        entry = self.ses.request(
            'open-ils.acq.picklist_entry.retrieve',
            self.request_mgr.ctx.core.authtoken, entry_id, args).recv().content()
        oils.event.Event.parse_and_raise(entry)
        if kwargs.get('flesh_provider'):
            if entry.provider():
                provider = self.ses.request(
                    'open-ils.acq.provider.retrieve', 
                    self.request_mgr.ctx.core.authtoken, 
                    entry.provider()).recv().content()
                entry.provider(provider)

        return entry

    def create_or_replace(self, pl_name):

        # find and delete any existing picklist with the requested name
        data = self.ses.request(
            'open-ils.acq.picklist.name.retrieve',
            self.request_mgr.ctx.core.authtoken, pl_name).recv()
        if data:
            picklist = data.content()
            status = self.ses.request(
                'open-ils.acq.picklist.delete',
                self.request_mgr.ctx.core.authtoken, picklist.id()).recv().content()
            oils.event.Event.parse_and_raise(status)
        
        # create the new one
        picklist = osrf.net_obj.NetworkObject.acqpl()
        picklist.name(pl_name)
        picklist.owner(self.request_mgr.ctx.core.user.id()) 
        picklist = self.ses.request(
            'open-ils.acq.picklist.create',
            self.request_mgr.ctx.core.authtoken, picklist).recv().content()
        oils.event.Event.parse_and_raise(picklist)
        return picklist

    def create_entry(self, entry):
        status = self.ses.request(
            'open-ils.acq.picklist_entry.create',
            self.request_mgr.ctx.core.authtoken, entry).recv().content()
        oils.event.Event.parse_and_raise(status)
        return status

    @staticmethod
    def find_entry_attr(entry, attr_name, attr_type='picklist_marc_attr_definition'):
        for entry_attr in entry.attributes():
            if entry_attr.attr_type() == attr_type and entry_attr.attr_name() == attr_name:
                return entry_attr.attr_value()
        return ''

            
