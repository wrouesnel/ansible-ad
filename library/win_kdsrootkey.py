#!/usr/bin/python
# -*- coding: utf-8 -*-

# (c) 2014, Chris Hoffman <choffman@chathamfinancial.com>
#
# This file is part of Ansible
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.

# this is a windows documentation stub.  actual code lives in the .ps1
# file of the same name

ANSIBLE_METADATA = {"metadata_version": "1.1", "status": ["development"], "supported_by": "core"}


DOCUMENTATION = r"""
---
module: win_kdsrootkey
version_added: "1.0"
short_description: Generates a new root key for the Microsoft Group Key Distribution Service (KdsSvc) within Active Directory (AD).
description:
    - Generates a new root key for the Microsoft Group Key Distribution Service (KdsSvc) within Active Directory (AD).
options:
   timeshift:
    description:
      - Timeshift when root key was created
    required: false
    default: -10 h
    aliases: []
notes:
    - For Windows targets only
author: "Alex Movergan"
"""

EXAMPLES = r"""
- name: Generate new KDS root key
  win_kdsrootkey:
    timeshift: "10"
"""
