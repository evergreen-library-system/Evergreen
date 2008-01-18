import osrf.ex

class Event(object):
    ''' Generic ILS event object '''


    def __init__(self, evt_hash={}):
        self.code = int(evt_hash['ilsevent'])
        self.text_code = evt_hash['textcode']
        self.desc = evt_hash.get('desc') or ''
        self.payload = evt_hash.get('payload')
        self.debug = evt_hash.get('stacktrace') or ''
        self.servertime = evt_hash.get('servertime') or ''

        self.success = False
        if self.code == 0:
            self.success = True

    def __str__(self):
        return '%s: %s:%s -> %s' % (
            self.__class__.__name__, self.code, self.text_code, self.desc)

    # XXX eventually, add events file parsing...

    def to_ex(self):
        return EventException(unicode(self))
        

    @staticmethod
    def parse_event(evt=None):
        ''' If the provided evt object is a dictionary object that looks
            like an ILS event, construct an Event object and return it.
            Returns None otherwise.  '''

        if isinstance(evt, dict) and 'ilsevent' in evt and 'textcode' in evt:
            return Event(evt)

        return None

    @staticmethod
    def parse_and_raise(evt=None):
        ''' Parses with parse_event.  If the resulting event is a non-success
            event, it is converted to an exception and raised '''
        evt = Event.parse_event(evt)
        if evt and not evt.success:
            raise evt.to_ex()


class EventException(osrf.ex.OSRFException):
    ''' A throw-able exception wrapper for events '''
    pass

