# -*- coding: utf-8 -*-
# dmgbuild settings for FieldWhisperer.
# Called by Distribution/create-dmg.sh via:
#   python3 -m dmgbuild -s this-file -D app=<path> -D background=<path> \
#                       "FieldWhisperer" ~/Desktop/FieldWhisperer.dmg
import os

application = defines.get('app')                       # full path to .app
appname     = os.path.basename(application)            # "FieldWhisperer.app"

# Output format
format = 'UDZO'

# Contents
files    = [application]
symlinks = {'Applications': '/Applications'}

# Background + window
background  = defines.get('background')
window_rect = ((100, 100), (700, 500))   # (top-left origin, size) → 600×400

# Icon view
default_view     = 'icon-view'
show_status_bar  = False
show_tab_view    = False
show_toolbar     = False
show_pathbar     = False
show_sidebar     = False
arrange_by       = None
icon_size        = 100
text_size        = 12

icon_locations = {
    appname:        (150, 200),
    'Applications': (450, 200),
}
