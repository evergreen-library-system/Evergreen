from mako import runtime, filters, cache
UNDEFINED = runtime.UNDEFINED
_magic_number = 2
_modified_time = 1198182658.882432
_template_filename=u'/home/erickson/code/ILS/branches/acq-experiment/Open-ILS/web/oilsweb/oilsweb/templates/oils/default/footer.html'
_template_uri=u'oils/default/acq/../footer.html'
_template_cache=cache.Cache(__name__, _modified_time)
_source_encoding=None
_exports = []


def render_body(context,**pageargs):
    context.caller_stack.push_frame()
    try:
        __M_locals = dict(pageargs=pageargs)
        c = context.get('c', UNDEFINED)
        _ = context.get('_', UNDEFINED)
        # SOURCE LINE 1
        context.write(unicode(_('Powered By')))
        context.write(u" <img src='")
        context.write(unicode(c.oils.core.media_prefix))
        context.write(u"/images/eg_tiny_logo.jpg'/>\n\n")
        return ''
    finally:
        context.caller_stack.pop_frame()


