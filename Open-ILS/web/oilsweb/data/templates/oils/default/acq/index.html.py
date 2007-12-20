from mako import runtime, filters, cache
UNDEFINED = runtime.UNDEFINED
_magic_number = 2
_modified_time = 1198108481.9620631
_template_filename='/home/erickson/code/sandbox/python/pylons/oilsweb/oilsweb/templates/oils/default/acq/index.html'
_template_uri='oils/default/acq/index.html'
_template_cache=cache.Cache(__name__, _modified_time)
_source_encoding=None
_exports = ['block_content', 'block_title']


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
        # SOURCE LINE 3
        context.write(u'\n')
        # SOURCE LINE 8
        context.write(u'\n\n')
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_content(context):
    context.caller_stack.push_frame()
    try:
        # SOURCE LINE 4
        context.write(u"\n    <div id='oils-acq-index-block'>\n        ACQ HOME\n    </div>\n")
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_title(context):
    context.caller_stack.push_frame()
    try:
        _ = context.get('_', UNDEFINED)
        # SOURCE LINE 3
        context.write(unicode(_('Evergreen Acquisitions Home')))
        return ''
    finally:
        context.caller_stack.pop_frame()


