import logging

from oilsweb.lib.request import RequestMgr
from oilsweb.lib.base import *
from oilsweb.lib.context import Context, SubContext, ContextItem

log = logging.getLogger(__name__)


class BaseContext(SubContext):
    def postinit(self):
        self.prefix = "%s/base" % Context.get_context().core.prefix
Context.apply_sub_context('base', BaseContext)


class BaseController(BaseController):
    ''' Controller for globally shared interfaces '''

    def dashboard(self):
        r = RequestMgr()
        return r.render('dashboard.html')

