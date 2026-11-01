"""Write a Finder layout against the mounted image, without GUI automation."""
from pathlib import Path
import sys

from ds_store import DSStore
from mac_alias import Alias

root = Path(sys.argv[1]).resolve()
background = Alias.for_file(str(root / '.background/background.tiff'))
with DSStore.open(str(root / '.DS_Store'), 'w+') as store:
    store['.']['vSrn'] = ('long', 1)
    store['.']['icvl'] = ('type', b'icnv')
    store['.']['bwsp'] = {
        'WindowBounds': '{{160, 120}, {640, 440}}',
        'ShowToolbar': False, 'ShowStatusBar': False, 'ShowPathbar': False,
        'ShowSidebar': False, 'ContainerShowSidebar': False,
        'PreviewPaneVisibility': False, 'ShowTabView': False, 'SidebarWidth': 0,
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundType': 2,
        'backgroundColorRed': 1.0, 'backgroundColorGreen': 1.0,
        'backgroundColorBlue': 1.0,
        'backgroundImageAlias': background.to_bytes(),
        'gridOffsetX': 0.0, 'gridOffsetY': 0.0, 'gridSpacing': 100.0,
        'arrangeBy': 'none', 'showIconPreview': True, 'showItemInfo': False,
        'labelOnBottom': True, 'textSize': 13.0, 'iconSize': 96.0,
        'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
    }
    store['Whoa Type.app']['Iloc'] = (160, 207)
    store['Applications']['Iloc'] = (480, 207)
