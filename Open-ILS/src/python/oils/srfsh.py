# -----------------------------------------------------------------------
# Copyright (C) 2010 Equinox Software, Inc.
# Bill Erickson <berick@esilibrary.com>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# -----------------------------------------------------------------------
import oils.utils.idl
from oils.utils.utils import md5sum
import osrf.json

def handle_login(srfsh, args):
    ''' Login w/ args '''

    username = args[0]
    password = args[1]

    seed = srfsh.handle_request([
        'open-ils.auth', 
        'open-ils.auth.authenticate.init', 
        '"%s"' % username
    ])

    password = md5sum(seed + md5sum(password))

    response = srfsh.handle_request([
        'open-ils.auth', 
        'open-ils.auth.authenticate.complete', 

        osrf.json.to_json( 
            {   # handle_request accepts json-encoded params
                'username'    : username,
                'password'    : password,
                'type'        : args[2] if len(args) > 2 else None,
                'workstation' : args[3] if len(args) > 3 else None
            }
        )
    ])

def handle_auth_verify(srfsh, args):
    ''' Verify auth w/ args '''

    username = args[0]
    password = args[1]

    seed = srfsh.handle_request([
        'open-ils.auth', 
        'open-ils.auth.authenticate.init', 
        '"%s"' % username
    ])

    password = md5sum(seed + md5sum(password))

    response = srfsh.handle_request([
        'open-ils.auth', 
        'open-ils.auth.authenticate.verify', 

        osrf.json.to_json( 
            {   # handle_request accepts json-encoded params
                'username'    : username,
                'password'    : password,
                'type'        : args[2] if len(args) > 2 else None,
            }
        )
    ])


def handle_org_setting(srfsh, args):
    ''' Retrieves the requested org setting.

    Arguments:
        org unit id,
        org setting name
    '''

    org_unit = args[0]
    setting = args[1]

    srfsh.handle_request([
        'open-ils.actor', 
        'open-ils.actor.ou_setting.ancestor_default', 
        org_unit, 
        ',"%s"' % setting
    ])

def handle_idl(srfsh, args):
    ''' Handles the 'idl' command.

    Argument options inlude:
        idl show class <classname>
    '''

    # all IDL commands require the IDL to be present
    if oils.utils.idl.IDLParser._global_parser is None:
        srfsh.report("Loading and parsing IDL...", True, True)
        oils.utils.idl.IDLParser.parse()
        srfsh.report("OK\n", True, True)

    if args[0] == 'show':

        if args[1] == 'class':
            class_ = args[2]
            srfsh.report(str(oils.utils.idl.IDLParser.get_class(class_)))


def load(srfsh, config): 
    ''' Srfsh plugin loader '''

    # load the IDL
    if config.get("load_idl", "") == "true":
        oils.utils.idl.IDLParser.parse()

    # register custom commands
    srfsh.add_command(command = 'login', handler = handle_login)
    srfsh.add_command(command = 'auth_verify', handler = handle_auth_verify)
    srfsh.add_command(command = 'idl', handler = handle_idl)
    srfsh.add_command(command = 'org_setting', handler = handle_org_setting)

    # add some service names to the tab complete word bank
    srfsh.tab_complete_words.append('open-ils.auth')
    srfsh.tab_complete_words.append('open-ils.cstore')
    # TODO: load services for tab-complete from opensrf settings...

