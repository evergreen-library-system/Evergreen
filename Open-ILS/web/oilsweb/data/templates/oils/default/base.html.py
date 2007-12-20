from mako import runtime, filters, cache
UNDEFINED = runtime.UNDEFINED
_magic_number = 2
_modified_time = 1198183376.8275831
_template_filename=u'/home/erickson/code/ILS/branches/acq-experiment/Open-ILS/web/oilsweb/oilsweb/templates/oils/default/base.html'
_template_uri=u'oils/default/acq/../base.html'
_template_cache=cache.Cache(__name__, _modified_time)
_source_encoding=None
_exports = ['block_footer', 'block_navigate', 'block_content', 'block_header', 'block_body_content', 'block_sidebar']


def _mako_get_namespace(context, name):
    try:
        return context.namespaces[(__name__, name)]
    except KeyError:
        _mako_generate_namespaces(context)
        return context.namespaces[(__name__, name)]
def _mako_generate_namespaces(context):
    pass
def _mako_inherit(template, context):
    _mako_generate_namespaces(context)
    return runtime._inherit_from(context, u'../base.html', _template_uri)
def render_body(context,**pageargs):
    context.caller_stack.push_frame()
    try:
        __M_locals = dict(pageargs=pageargs)
        # SOURCE LINE 1
        context.write(u'\n\n')
        # SOURCE LINE 23
        context.write(u'\n\n')
        # SOURCE LINE 25
        context.write(u'\n')
        # SOURCE LINE 26
        context.write(u'\n')
        # SOURCE LINE 27
        context.write(u'\n')
        # SOURCE LINE 30
        context.write(u'\n')
        # SOURCE LINE 33
        context.write(u'\n')
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_footer(context):
    context.caller_stack.push_frame()
    try:
        # SOURCE LINE 31
        context.write(u'\n    ')
        # SOURCE LINE 32
        runtime._include_file(context, u'footer.html', _template_uri)
        context.write(u'\n')
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_navigate(context):
    context.caller_stack.push_frame()
    try:
        # SOURCE LINE 28
        context.write(u'\n    ')
        # SOURCE LINE 29
        runtime._include_file(context, u'navigate.html', _template_uri)
        context.write(u'\n')
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_content(context):
    context.caller_stack.push_frame()
    try:
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_header(context):
    context.caller_stack.push_frame()
    try:
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_body_content(context):
    context.caller_stack.push_frame()
    try:
        self = context.get('self', UNDEFINED)
        # SOURCE LINE 3
        context.write(u"\n    <div id='oils-base-body-block'> \n        <div id='oils-base-header-block'>\n            ")
        # SOURCE LINE 6
        context.write(unicode(self.block_header()))
        context.write(u"\n        </div>\n        <div id='oils-base-main-block' class='container'>\n            <div id='oils-base-navigate-block'>\n                ")
        # SOURCE LINE 10
        context.write(unicode(self.block_navigate()))
        context.write(u"\n            </div>\n            <div id='oils-base-content-block'>\n                ")
        # SOURCE LINE 13
        context.write(unicode(self.block_content()))
        context.write(u"\n            </div>\n            <div id='oils-base-sidebar-block'>\n                ")
        # SOURCE LINE 16
        context.write(unicode(self.block_sidebar()))
        context.write(u"\n            </div>\n        </div>\n        <div id='oils-base-footer-block'>\n            ")
        # SOURCE LINE 20
        context.write(unicode(self.block_footer()))
        context.write(u'\n        </div>\n    </div>\n')
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_sidebar(context):
    context.caller_stack.push_frame()
    try:
        return ''
    finally:
        context.caller_stack.pop_frame()


