from oilsweb.lib.base import *
import logging, pylons
import oilsweb.lib.context, oilsweb.lib.util
import oilsweb.lib.bib
import oils.const, oils.utils.utils
import osrf.net_obj

import simplejson

from osrf.ses import ClientSession
from oils.event import Event
from oils.org import OrgUtil
from oilsweb.lib.request import RequestMgr

class PicklistController(BaseController):
    
    def view(self, **kwargs):
        r = RequestMgr()
        r.ctx.acq.picklist.value = kwargs['id']
        return r.render('acq/picklist/view.html')
    
    def list(self):
        r = RequestMgr()
        return r.render('acq/picklist/view_list.html')
    
    def listall(self):
        r = RequestMgr()
        return r.render('acq/picklist/view_list.html')
    
    def bib_search(self):
        r = RequestMgr()
        return r.render('acq/picklist/bib_search.html')
    

