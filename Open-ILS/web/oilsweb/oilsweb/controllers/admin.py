from oilsweb.lib.request import RequestMgr
from oilsweb.lib.base import *
import oilsweb.lib.util
from oilsweb.lib.context import Context, SubContext, ContextItem
import oils.utils.idl
import oils.utils.csedit
import osrf.ses

class AdminContext(SubContext):
    ''' Define the CGI/Context params for this application '''
    def __init__(self):
        self.object = ContextItem()
        self.object_class = ContextItem()
        self.object_meta = ContextItem()
        self.mode = ContextItem(default_value='view')
        self.prefix = ContextItem()
    def postinit(self):
        self.prefix = "%s/admin" % Context.getContext().core.prefix

Context.applySubContext('adm', AdminContext)

class AdminController(BaseController):

    def init(self, type, id=None):
        r = RequestMgr()
        r.ctx.adm.object_class = type
        meta = r.ctx.adm.object_meta = oils.utils.idl.oilsGetIDLParser().IDLObject[type]

        if id is not None:
            r.ctx.adm.object = osrf.ses.AtomicRequest(
                'open-ils.cstore',
                'open-ils.cstore.direct.%s.retrieve' % 
                    meta['fieldmapper'].replace('::', '.'), id)
        return r

    def test(self, type, id):
        r = self.init()
        return r.render('dashboard.html')

    def view(self, type, id):
        r = self.init(type, id)
        return r.render('admin/object.html')

    def update(self, type, id):
        r = self.init(type, id)
        c.oils.adm.mode = 'update'
        return r.render('admin/object.html')

    def create(self, type):
        r = self.init(type, id)
        c.oils.adm.mode = 'create'
        return r.render('admin/object.html')

    def delete(self, type, id):
        r = self.init(type, id)
        c.oils.adm.mode = 'delete'
        return r.render('admin/object.html')

        
