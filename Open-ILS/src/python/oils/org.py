import osrf.ses
import oils.event, oils.const

class OrgUtil(object):
    ''' Collection of general purpose org_unit utility functions '''

    _org_tree = None  
    _org_types = None  

    @staticmethod
    def fetch_org_tree():
        ''' Returns the whole org_unit tree '''
        if OrgUtil._org_tree:
            return OrgUtil._org_tree
        tree = osrf.ses.ClientSession.atomic_request(
            oils.const.OILS_APP_ACTOR,
            'open-ils.actor.org_tree.retrieve')
        oils.event.Event.parse_and_raise(tree)
        OrgUtil._org_tree = tree
        return tree

    @staticmethod
    def fetch_org_types():
        ''' Returns the list of org_unit_type objects '''
        if OrgUtil._org_types:
            return OrgUtil._org_types
        types = osrf.ses.ClientSession.atomic_request(
            oils.const.OILS_APP_ACTOR,
            'open-ils.actor.org_types.retrieve')
        oils.event.Event.parse_and_raise(types)
        OrgUtil._org_types = types
        return types


    @staticmethod
    def get_org_type(org_unit):
        ''' Given an org_unit, this returns the org_unit_type object it's linked to '''
        types = OrgUtil.fetch_org_types()
        return [t for t in types if t.id() == org_unit.ou_type()][0]


