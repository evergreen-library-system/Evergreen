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

    def init(self, obj_type, obj_id=None):
        r = RequestMgr()
        r.ctx.adm.object_class = obj_type
        meta = r.ctx.adm.object_meta = oils.utils.idl.IDLParser.get_class(obj_type)

        if obj_id is not None:
            r.ctx.adm.object = osrf.ses.ClientSession.atomic_request(
                'open-ils.cstore',
                'open-ils.cstore.direct.%s.retrieve' % 
                    meta.fieldmapper.replace('::', '.'), obj_id)
        return r

    def index(self):
        r = RequestMgr()
        return r.render('admin/index.html')

    def view(self, **kwargs):
        r = self.init(kwargs['type'], kwargs['id'])
        r.ctx.adm.mode = 'view'
        return r.render('admin/object.html')

    def update(self, **kwargs):
        r = self.init(kwargs['type'], kwargs['id'])
        r.ctx.adm.mode = 'update'
        return r.render('admin/object.html')

    def create(self, **kwargs):
        r = self.init(kwargs['type'])
        r.ctx.adm.mode = 'create'
        return r.render('admin/object.html')

    def delete(self, **kwargs):
        r = self.init(kwargs['type'], kwargs['id'])
        r.ctx.adm.mode = 'delete'
        return r.render('admin/object.html')

        
