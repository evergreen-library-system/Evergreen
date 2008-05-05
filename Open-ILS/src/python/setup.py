#!/usr/bin/env python
from setuptools import setup

setup(name='Evergreen',
    version='1.4.0',
    install_requires='OpenSRF>=1.0',
    description='Evergreen Python Modules',
    author='Bill Erickson',
    author_email='erickson@esilibrary.com',
    license='GPL',
    url='http://www.open-ils.org/',
    packages=['oils', 'oils.utils'],
)
