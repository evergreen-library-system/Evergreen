import osrf.cache, osrf.json, osrf.ses, osrf.net_obj
import oils.const, oils.utils.utils, oils.event
import oilsweb.lib.user
import mx.DateTime.ISO

class PO_Manager(object):
    def __init__(self, request_mgr, **kwargs):
        self.request_mgr = request_mgr
        self.id = kwargs.get('poid')
        self.liid = kwargs.get('liid')
        self.ses = osrf.ses.ClientSession(oils.const.OILS_APP_ACQ)

    def retrieve_po_list(self):
        ''' Returns list of POs '''

        request = 'open-ils.acq.purchase_order.user.all.retrieve.atomic'

        list = self.ses.request(request,
                                self.request_mgr.ctx.core.authtoken.value,
                                {'flesh_lineitem_count':1,
                                 'clear_marc':1,
                                 'order_by':'id'}).recv().content()
        oils.event.Event.parse_and_raise(list)

        usermgr = oilsweb.lib.user.User(self.request_mgr.ctx.core)
        datefmt = usermgr.get_date_format()

        for po in list:
            ctime = mx.DateTime.ISO.ParseAny(po.create_time())
            po.create_time(ctime.strftime(datefmt))

            etime = mx.DateTime.ISO.ParseAny(po.edit_time())
            po.edit_time(etime.strftime(datefmt))

        return list

    def retrieve(self, **kwargs):
        if 'flesh_lineitems' in kwargs:
            flesh = kwargs['flesh_lineitems']
        else:
            flesh = 1

        po = self.ses.request('open-ils.acq.purchase_order.retrieve',
                              self.request_mgr.ctx.core.authtoken.value,
                              self.id,
                              {'flesh_lineitems':flesh}).recv().content()
        oils.event.Event.parse_and_raise(po)

        datefmt = oilsweb.lib.user.User(self.request_mgr.ctx.core).get_date_format()

        po.create_time(mx.DateTime.ISO.ParseAny(po.create_time()).strftime(datefmt))
        po.edit_time(mx.DateTime.ISO.ParseAny(po.edit_time()).strftime(datefmt))
        self.po = po

    def retrieve_lineitem(self, **kwargs):
        li = self.ses.request('open-ils.acq.po_lineitem.retrieve',
                              self.request_mgr.ctx.core.authtoken.value,
                              self.liid, {'flesh_li_details':1}).recv().content()
        datefmt = oilsweb.lib.user.User(self.request_mgr.ctx.core).get_date_format()
        li.create_time(mx.DateTime.ISO.ParseAny(li.create_time()).strftime(datefmt))
        li.edit_time(mx.DateTime.ISO.ParseAny(li.edit_time()).strftime(datefmt))
        self.li = li

    @staticmethod
    def find_li_attr(li, attr_name, attr_type='picklist_marc_attr_definition'):
        if not li.attributes():
            return ''
        for li_attr in li.attributes():
            if li_attr.attr_type() == attr_type and li_attr.attr_name() == attr_name:
                return li_attr.attr_value()
        return ''
