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
        c.oils = oilsweb.lib.context.Context.init(request, response)
        c.oils.adm.object_class = type
        meta = c.oils.adm.object_meta = oils.utils.idl.oilsGetIDLParser().IDLObject[type]

        if id is not None:
            c.oils.adm.object = osrf.ses.AtomicRequest(
                'open-ils.cstore',
                'open-ils.cstore.direct.%s.retrieve' % 
                    meta['fieldmapper'].replace('::', '.'), id)

        c.oils.apply_cookies()

    def view(self, type, id):
        self.init(type, id)
        return render('oils/%s/admin/object.html' % c.oils.core.skin)

    def update(self, type, id):
        self.init(type, id)
        c.oils.adm.mode = 'update'
        return render('oils/%s/admin/object.html' % c.oils.core.skin)

    def create(self, type):
        self.init(type)
        c.oils.adm.mode = 'create'
        return render('oils/%s/admin/object.html' % c.oils.core.skin)

    def delete(self, type, id):
        self.init(type, id)
        c.oils.adm.mode = 'delete'
        return render('oils/%s/admin/object.html' % c.oils.core.skin) # show a confirmation page

        
