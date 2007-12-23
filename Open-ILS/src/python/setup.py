#!/usr/bin/env python
from distutils.core import setup
import os, os.path

dir = os.path.dirname(__file__)

setup(name='Evergreen',
    version='1.2',
    requires='OpenSRF',
    description='Evergreen Python Modules',
    author='Bill Erickson',
    author_email='open-ils-dev@list.georgialibraries.org',
    url='http://www.open-ils.org/',
    packages=['oils', 'oils.utils'],
    package_dir={'': dir}
)
