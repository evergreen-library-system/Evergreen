import logging

from oilsweb.lib.base import *
from oilsweb.lib.context import Context, SubContext, ContextItem

log = logging.getLogger(__name__)


class BaseContext(SubContext):
    def postinit(self):
        self.prefix = "%s/base" % Context.getContext().core.prefix
Context.applySubContext('base', BaseContext)


class BaseController(BaseController):
    ''' Controller for globally shared interfaces '''

    def dashboard(self):
        c.oils = Context.init(request, response)
        return render('oils/%s/dashboard.html' % c.oils.core.skin)

