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
        self.prefix.value = "%s/admin" % Context.get_context().core.prefix.value

Context.apply_sub_context('adm', AdminContext)

class AdminController(BaseController):

    def init(self, obj_type, obj_id=None):
        r = RequestMgr()
        r.ctx.adm.object_class.value = obj_type
        meta = r.ctx.adm.object_meta.value = oils.utils.idl.IDLParser.get_class(obj_type)

        if obj_id is not None:
            r.ctx.adm.object.value = osrf.ses.ClientSession.atomic_request(
                'open-ils.cstore',
                'open-ils.cstore.direct.%s.retrieve' % 
                    meta.fieldmapper.replace('::', '.'), obj_id)
        return r

    def index(self):
        r = RequestMgr()
        return r.render('admin/index.html')

    def view(self, **kwargs):
        r = self.init(kwargs['type'], kwargs['id'])
        r.ctx.adm.mode.value = 'view'
        return r.render('admin/object.html')

    def update(self, **kwargs):
        r = self.init(kwargs['type'], kwargs['id'])
        r.ctx.adm.mode.value = 'update'
        return r.render('admin/object.html')

    def create(self, **kwargs):
        r = self.init(kwargs['type'])
        r.ctx.adm.mode.value = 'create'
        return r.render('admin/object.html')

    def delete(self, **kwargs):
        r = self.init(kwargs['type'], kwargs['id'])
        r.ctx.adm.mode.value = 'delete'
        return r.render('admin/object.html')

        
