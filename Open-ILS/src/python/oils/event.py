
class Event(object):
    ''' Generic ILS event object '''

    def __init__(self, evt_hash={}):
        self.code = evt_hash.get('ilsevent') or -1 
        self.text_code = evt_hash.get('textcode') or ''
        self.desc = evt_hash.get('desc') or ''
        self.payload = evt_hash.get('payload') or None
        self.debug = evt_hash.get('stacktrace') or ''
        self.servertime = evt_hash.get('servertime') or ''

        self.success = False
        if self.code == int(0):
            self.success = True

    def __str__(self):
        return '%s: %s:%s -> %s' % (
            self.__class__.__name__, self.code, self.text_code, self.desc)

    # XXX eventually, add events file parsing...

    @staticmethod
    def parse_event(evt=None):
        ''' If the provided evt object is a dictionary object that looks
            like an ILS event, construct an Event object and return it.
            Returns None otherwise.  '''

        if evt and 'ilsevent' in evt and 'textcode' in evt:
            return Event(evt)

        return None
