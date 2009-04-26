import osrf.ex

class Event(object):
    ''' Generic ILS event object '''

    def __init__(self, evt_hash={}):
        if 'ilsevent' in evt_hash:
            self.code = int(evt_hash['ilsevent'])
        else:
            self.code = -1
        self.text_code = evt_hash['textcode']
        self.desc = evt_hash.get('desc') or ''
        self.payload = evt_hash.get('payload')
        self.debug = evt_hash.get('stacktrace') or ''
        self.servertime = evt_hash.get('servertime') or ''
        self.ilsperm = evt_hash.get('ilsperm')
        self.ilspermloc = evt_hash.get('ilspermloc')

        self.success = False
        if self.code == 0:
            self.success = True

    def __str__(self):
        if self.ilsperm:
            return '%s: %s:%s -> %s %s@%s' % (
                self.__class__.__name__, self.code, self.text_code, self.desc, self.ilsperm, str(self.ilspermloc))
        else:
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
    def parse_and_raise(obj=None):
        ''' Parses with parse_event.  If the resulting event is a non-success
            event, it is converted to an exception and raised.  If the resulting
            event is a success event, the event object is returned.  If the
            object is not an event, the original original object is returned 
            unchanged. '''
        evt = Event.parse_event(obj)
        if evt:
            if evt.success:
                return evt
            raise evt.to_ex()
        return obj


class EventException(osrf.ex.OSRFException):
    ''' A throw-able exception wrapper for events '''
    pass

