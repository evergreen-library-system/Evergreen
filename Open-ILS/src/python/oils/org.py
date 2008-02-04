import osrf.ses
import oils.event, oils.const
import sys

class OrgUtil(object):
    ''' Collection of general purpose org_unit utility functions '''

    _org_tree = None  
    _org_types = None  
    _flat_org_tree = {}

    @staticmethod
    def _verify_tree():
        if not OrgUtil._org_tree:
            OrgUtil.fetch_org_tree()

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
        OrgUtil.flatten_org_tree(tree)
        return tree

    @staticmethod
    def flatten_org_tree(node):
        ''' Creates links from an ID-based hash to the org units in the org tree '''
        if not node:
            node = OrgUtil._org_tree
        OrgUtil._flat_org_tree[int(node.id())] = node
        for child in node.children():
            OrgUtil.flatten_org_tree(child)

    @staticmethod
    def get_org_unit(org_id):
        OrgUtil._verify_tree()
        if isinstance(org_id, osrf.net_obj.NetworkObject):
            return org_id
        return OrgUtil._flat_org_tree[int(org_id)]
        

    @staticmethod
    def fetch_org_types():
        ''' Returns the list of org_unit_type objects '''

        if OrgUtil._org_types:
            return OrgUtil._org_types

        types = osrf.ses.ClientSession.atomic_request(
            oils.const.OILS_APP_ACTOR, 'open-ils.actor.org_types.retrieve')

        oils.event.Event.parse_and_raise(types)
        OrgUtil._org_types = types
        return types


    @staticmethod
    def get_org_type(org_unit):
        ''' Given an org_unit, this returns the org_unit_type object it's linked to '''
        types = OrgUtil.fetch_org_types()
        return [t for t in types if t.id() == org_unit.ou_type()][0]


    @staticmethod
    def get_related_tree(org_unit):
        ''' Returns a cloned tree of orgs including all ancestors and 
            descendants of the provided org '''

        OrgUtil._verify_tree()
        org = org_unit = OrgUtil.get_org_unit(org_unit.id()).shallow_clone()
        while org.parent_ou():
            parent = org.parent_ou()
            if not isinstance(parent, osrf.net_obj.NetworkObject):
                parent = OrgUtil._flat_org_tree[parent]
            parent = parent.shallow_clone()
            parent.children([org])
            org = parent
        root = org

        def trim_org(node):
            node = node.shallow_clone()
            children = node.children()
            if len(children) > 0:
                node.children([])
                for child in children:
                    node.children().append(trim_org(child))
            return node

        trim_org(org_unit)
        return root

    @staticmethod
    def get_union_tree(org_id_list):
        ''' Returns the smallest org tree which encompases all of the orgs in org_id_list '''

        OrgUtil._verify_tree()
        if len(org_id_list) == 0:
            return None
        main_tree = OrgUtil.get_related_tree(OrgUtil.get_org_unit(org_id_list[0]))

        if len(org_id_list) == 1:
            return main_tree

        for org in org_id_list[1:]:
            node = OrgUtil.get_related_tree(OrgUtil.get_org_unit(org))
            main_node = main_tree

            while node.id() == main_node.id():
                child = node.children()[0]
                main_child_node = main_node.children()[0]
                child.parent_ou(node)
                main_child_node.parent_ou(main_node)
                node = child
                main_node = main_child_node

            main_node.parent_ou().children().append(node)

        return main_tree

    @staticmethod
    def get_related_list(org_unit):
        ''' Returns a flat list of related org_units '''
        OrgUtil._verify_tree()
        tree = OrgUtil.get_related_tree(org_unit)
        orglist = []
        def flatten(node):
            orglist.append(node)
            for child in node.children():
                flatten(child)
        flatten(tree)
        return orglist

    @staticmethod
    def get_min_depth(org_id_list):
        ''' Returns the minimun depth (highest tree position) of all orgs in the list '''
        depth = None
        for org in org_id_list:
            new_depth = OrgUtil.get_org_type(OrgUtil.get_org_unit(org)).depth()
            if depth is None:
                depth = new_depth
            elif new_depth < depth:
                depth = new_depth
        return depth

    @staticmethod
    def debug_tree(org_unit, indent=0):
        ''' Simple function to print the tree of orgs provided '''
        for i in range(indent):
            sys.stdout.write('_')
        print '%s id=%s depth=%s' % (org_unit.shortname(), str(org_unit.id()), str(OrgUtil.get_org_type(org_unit).depth()))
        indent += 1
        for child in org_unit.children():
            OrgUtil.debug_tree(child, indent)
        

