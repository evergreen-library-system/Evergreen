import osrf.cache, osrf.json, osrf.ses, osrf.net_obj
import oils.const, oils.utils.utils, oils.event
import oilsweb.lib.user
import mx.DateTime.ISO

class PicklistMgr(object):
    def __init__(self, request_mgr, **kwargs):
        self.request_mgr = request_mgr
        self.id = kwargs.get('picklist_id')
        self.picklist = kwargs.get('picklist')
        self.ses = osrf.ses.ClientSession(oils.const.OILS_APP_ACQ)

    def retrieve(self):
        picklist = self.ses.request(
            'open-ils.acq.picklist.retrieve', 
            self.request_mgr.ctx.core.authtoken.value, self.id, {'flesh_lineitem_count':1, 'flesh_username':1}).recv().content()

        oils.event.Event.parse_and_raise(picklist)
        self.picklist = picklist

        usermgr = oilsweb.lib.user.User(self.request_mgr.ctx.core)

        picklist.create_time(
            mx.DateTime.ISO.ParseAny(
            picklist.create_time()).strftime(usermgr.get_date_format()))

        picklist.edit_time(
            mx.DateTime.ISO.ParseAny(
            picklist.edit_time()).strftime(usermgr.get_date_format()))
           

    def delete(self, picklist_id=None):
        picklist_id = picklist_id or self.id
        status = self.ses.request(
            'open-ils.acq.picklist.delete',
            self.request_mgr.ctx.core.authtoken.value, picklist_id).recv().content()
        oils.event.Event.parse_and_raise(status)
        return status

    def delete_lineitem(self, lineitem_id):
        status = self.ses.request(
            'open-ils.acq.lineitem.delete',
            self.request_mgr.ctx.core.authtoken.value, lineitem_id).recv().content()
        oils.event.Event.parse_and_raise(status)
        return status


    def retrieve_lineitems(self, **kwargs):
        # grab the lineitems
        lineitems = self.ses.request(
            'open-ils.acq.lineitem.picklist.retrieve',
            self.request_mgr.ctx.core.authtoken.value, 
            self.picklist.id(),
            {
                "offset" : kwargs.get('offset'),
                "limit" : kwargs.get('limit'),
                "idlist" : kwargs.get('idlist'),
                "flesh_attrs" : 1,
                "clear_marc" : 1
            }
        ).recv().content()

        if kwargs.get('flesh_provider'):
            for lineitem in lineitems:
                if lineitem.provider():
                    provider = self.ses.request(
                        'open-ils.acq.provider.retrieve', 
                        self.request_mgr.ctx.core.authtoken.value, 
                        lineitem.provider()).recv().content()
                    lineitem.provider(provider)

        self.picklist.entries(lineitems)

    def retrieve_list(self, all=False):
        ''' Returns my list of picklist objects '''
        if (all):
            request = 'open-ils.acq.picklist.user.all.retrieve.atomic'
        else:
            request = 'open-ils.acq.picklist.user.retrieve'

        list = self.ses.request(request,
                                self.request_mgr.ctx.core.authtoken.value,
                                {'flesh_lineitem_count':1, 'flesh_username':1}).recv().content()
        oils.event.Event.parse_and_raise(list)

        usermgr = oilsweb.lib.user.User(self.request_mgr.ctx.core)

        for picklist in list:
            picklist.create_time(
                mx.DateTime.ISO.ParseAny(
                picklist.create_time()).strftime(usermgr.get_date_format()))
    
            picklist.edit_time(
                mx.DateTime.ISO.ParseAny(
                picklist.edit_time()).strftime(usermgr.get_date_format()))
    
        return list
        

    def retrieve_lineitem(self, lineitem_id, **kwargs):
        args = {'flesh_attrs': kwargs.get('flesh_attrs')}
        lineitem = self.ses.request(
            'open-ils.acq.lineitem.retrieve',
            self.request_mgr.ctx.core.authtoken.value, lineitem_id, args).recv().content()
        oils.event.Event.parse_and_raise(lineitem)
        if kwargs.get('flesh_provider'):
            if lineitem.provider():
                provider = self.ses.request(
                    'open-ils.acq.provider.retrieve', 
                    self.request_mgr.ctx.core.authtoken.value, 
                    lineitem.provider()).recv().content()
                lineitem.provider(provider)

        return lineitem

    def create_or_replace(self, pl_name):

        # find and delete any existing picklist with the requested name
        data = self.ses.request(
            'open-ils.acq.picklist.name.retrieve',
            self.request_mgr.ctx.core.authtoken.value, pl_name).recv()
        if data:
            self.delete(data.content().id())
        
        # create the new one
        picklist = osrf.net_obj.NetworkObject.acqpl()
        picklist.name(pl_name)
        picklist.owner(self.request_mgr.ctx.core.user.value.id()) 

        picklist = self.ses.request(
            'open-ils.acq.picklist.create',
            self.request_mgr.ctx.core.authtoken.value, picklist).recv().content()
        oils.event.Event.parse_and_raise(picklist)

        return picklist

    def create_lineitem(self, lineitem):
        status = self.ses.request(
            'open-ils.acq.lineitem.create',
            self.request_mgr.ctx.core.authtoken.value, lineitem).recv().content()
        oils.event.Event.parse_and_raise(status)
        return status

    @staticmethod
    def find_lineitem_attr(lineitem, attr_name, attr_type='lineitem_marc_attr_definition'):
        for lineitem_attr in lineitem.attributes():
            if lineitem_attr.attr_type() == attr_type and lineitem_attr.attr_name() == attr_name:
                return lineitem_attr.attr_value()
        return ''

            
