from mako import runtime, filters, cache
UNDEFINED = runtime.UNDEFINED
_magic_number = 2
_modified_time = 1198103797.7045071
_template_filename=u'/home/erickson/code/sandbox/python/pylons/oilsweb/oilsweb/templates/oils/base.html'
_template_uri=u'oils/default/acq/../../base.html'
_template_cache=cache.Cache(__name__, _modified_time)
_source_encoding=None
_exports = ['block_body', 'block_css', 'block_body_content', 'block_head']


def render_body(context,**pageargs):
    context.caller_stack.push_frame()
    try:
        __M_locals = dict(pageargs=pageargs)
        self = context.get('self', UNDEFINED)
        # SOURCE LINE 1
        context.write(u'<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">\n\n<!-- This file defines the most basic requirements of an XHTML block -->\n\n')
        # SOURCE LINE 5
        locale = 'en-US' 
        
        __M_locals.update(dict([(__M_key, locals()[__M_key]) for __M_key in ['locale'] if __M_key in locals()]))
        context.write(u" <!-- XXX GET LOCALE FROM PYTHON -->\n<html xmlns='http://www.w3.org/1999/xhtml' lang='")
        # SOURCE LINE 6
        context.write(unicode(locale))
        context.write(u"' xml:lang='")
        context.write(unicode(locale))
        context.write(u"'>\n    ")
        # SOURCE LINE 7
        context.write(unicode(self.block_head()))
        context.write(u'\n    ')
        # SOURCE LINE 8
        context.write(unicode(self.block_body()))
        context.write(u'\n</html>\n\n')
        # SOURCE LINE 18
        context.write(u'\n\n')
        # SOURCE LINE 22
        context.write(u'\n')
        # SOURCE LINE 23
        context.write(u'\n\n')
        # SOURCE LINE 28
        context.write(u'\n\n')
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_body(context):
    context.caller_stack.push_frame()
    try:
        self = context.get('self', UNDEFINED)
        # SOURCE LINE 20
        context.write(u'\n<body>')
        # SOURCE LINE 21
        context.write(unicode(self.block_body_content()))
        context.write(u'</body>\n')
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_css(context):
    context.caller_stack.push_frame()
    try:
        c = context.get('c', UNDEFINED)
        # SOURCE LINE 25
        context.write(u"\n    <link rel='stylesheet' type='text/css' href='")
        # SOURCE LINE 26
        context.write(unicode(c.oils.core.media_prefix))
        context.write(u'/css/skin/')
        context.write(unicode(c.oils.core.skin))
        context.write(u".css'/>\n    <link rel='stylesheet' type='text/css' href='")
        # SOURCE LINE 27
        context.write(unicode(c.oils.core.media_prefix))
        context.write(u'/css/theme/')
        context.write(unicode(c.oils.core.theme))
        context.write(u".css'/>\n")
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_body_content(context):
    context.caller_stack.push_frame()
    try:
        return ''
    finally:
        context.caller_stack.pop_frame()


def render_block_head(context):
    context.caller_stack.push_frame()
    try:
        self = context.get('self', UNDEFINED)
        def block_title():
            context.caller_stack.push_frame()
            try:
                _ = context.get('_', UNDEFINED)
                # SOURCE LINE 14
                context.write(unicode(_('Evergreen Acquisitions')))
                return ''
            finally:
                context.caller_stack.pop_frame()
        # SOURCE LINE 11
        context.write(u' <!-- haha.. blockhead -->\n    <!-- Construct a sane default HTML head -->\n    <head>\n        ')
        # SOURCE LINE 14
        context.write(u'\n        <title>')
        # SOURCE LINE 15
        context.write(unicode(self.block_title()))
        context.write(u'</title>\n        ')
        # SOURCE LINE 16
        context.write(unicode(self.block_css()))
        context.write(u'\n    </head>\n')
        return ''
    finally:
        context.caller_stack.pop_frame()


