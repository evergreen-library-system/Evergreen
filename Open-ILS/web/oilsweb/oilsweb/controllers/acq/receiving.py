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

class ReceivingController(BaseController):
    
    def process(self, **kwargs):
        r = RequestMgr()
        return r.render('acq/receiving/process.html')
