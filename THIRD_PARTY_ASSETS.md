# Third-party assets

This file lists every redistributed third-party media file and every project
asset derived from third-party media. The project's MIT license does not apply
to these files unless explicitly stated otherwise below.

## `textures/minecart_lift_ropes_item.png`

- Original filename: `textures/ropes_item.png`
- Source: <https://github.com/minetest-mods/ropes>
- Source commit inspected: `64d3d855f3bff871d689a9831abf7cbfb76cff22`
- Local SHA-256: `25d46322acef1af66aa4d7dbdf65439b175ca52f077195e4df50590c773876b3`
- Original author: not established from the available repository metadata
- Artwork license: **unclear / legally problematic**
- Usage status: retained in the repository but no longer referenced by the mod

The Ropes repository contains an MIT license for its software and
documentation, but does not clearly assign that license to this texture.
The unresolved upstream issue below specifically asks for clarification of
the rope textures' license:

<https://github.com/minetest-mods/ropes/issues/25>

This file is explicitly excluded from this project's MIT license. It remains
in the project with its license status clearly marked as unresolved. Anyone
redistributing the project should review the upstream issue and understand
that no confirmed artwork license is currently available for this file.

## `textures/minecart_lift_rope.png`

- Original filename: `textures/ropes_3.png`
- Source: <https://github.com/minetest-mods/ropes>
- Source commit inspected: `64d3d855f3bff871d689a9831abf7cbfb76cff22`
- Local SHA-256: `2d9903ff4aa5cd042dbbd38ee30178074fb3223a31b9743410b950f35e33be5a`
- Original author: not established from the available repository metadata
- Artwork license: **unclear / legally problematic**

The same unresolved license status described above applies to this file. It is
retained in the project, but it is not covered by the project's MIT license.

The unresolved upstream license question is tracked in:

<https://github.com/minetest-mods/ropes/issues/25>

## Rope creak sounds

- Local files:
  - `sounds/minecart_lift_rope_creak.1.ogg`
  - `sounds/minecart_lift_rope_creak.2.ogg`
  - `sounds/minecart_lift_rope_creak.3.ogg`
- Original sound: `ropes_creak.ogg`
- Source package: <https://github.com/minetest-mods/ropes>
- Original creator: jergonda
- Original source: <https://freesound.org/people/jergonda/sounds/254735/>
- License: CC0 / public domain
- Local SHA-256 values:
  - `ef3d706fd9e2b71f74a45a8c994949acda13d90d80733ed84e176a21d4590ce8`
  - `920b13f7e76c4dcec02d63d2caa0e8c92d56745bb11f57d8e672fedf67cc4037`
  - `7cd54f2d976e0caa2ad822b044d4a94c5c096536d5ececd28ca3abf7de4c8873`

The upstream `sounds/license.txt` identifies these sounds as public domain via
CC0. They may be used, modified, and redistributed without attribution; the
source is retained here for provenance and credit.

## Chest Cart textures and GIMP source files

### Active derived artwork

- Local files:
  - `textures/minecart_lift_chest_front.png`
  - `textures/minecart_lift_chest_side.png`
  - `textures/minecart_lift_chest_top.png`
  - `textures/minecart_lift_chest_front.xcf`
  - `textures/minecart_lift_chest_side.xcf`
  - `textures/minecart_lift_chest_top.xcf`
- Chest source files:
  - `mods/default/textures/default_chest_front.png`
  - `mods/default/textures/default_chest_side.png`
  - `mods/default/textures/default_chest_top.png`
- Cart source files:
  - `mods/carts/textures/carts_cart_front.png`
  - `mods/carts/textures/carts_cart_side.png`
  - `mods/carts/textures/carts_cart_top.png`
- Source project: Minetest Game
- Source repository: <https://github.com/luanti-org/minetest_game>
- Changes: the chest and cart artwork was combined, rearranged, masked, and
  resized to match the custom Chest Cart model
- License: **CC BY-SA 3.0 Unported**
- Copyright: Minetest Game developers and contributors

The chest source artwork is licensed under CC BY-SA 3.0. The cart source
artwork is CC0, but the combined work remains subject to the ShareAlike terms
of the chest artwork. The six derived PNG and XCF files listed above are
therefore distributed under CC BY-SA 3.0, not under this project's MIT
license. See the upstream license and attribution list:

<https://github.com/luanti-org/minetest_game/blob/master/mods/default/license.txt>

### Unmodified Default Chest copies

- Local files:
  - `textures/chest_cart_front.png`
  - `textures/chest_cart_side.png`
  - `textures/chest_cart_top.png`
- Original filenames:
  - `default_chest_front.png`
  - `default_chest_side.png`
  - `default_chest_top.png`
- Source project: Minetest Game `default` mod
- Source repository: <https://github.com/luanti-org/minetest_game>
- Changes: filenames only; image contents are unmodified
- License: **CC BY-SA 3.0 Unported**
- Copyright: Minetest Game developers and contributors
- Usage status: retained as artwork source files but not referenced by the mod

These files are distributed under CC BY-SA 3.0, not under this project's MIT
license.

### Unmodified Carts copies

- Local files:
  - `textures/cart_front.png`
  - `textures/cart_side.png`
  - `textures/cart_top.png`
- Original filenames:
  - `carts_cart_front.png`
  - `carts_cart_side.png`
  - `carts_cart_top.png`
- Source project: Minetest Game `carts` mod
- Source repository: <https://github.com/luanti-org/minetest_game>
- Original artwork: PixelBOX by Gambit
- Changes: filenames only; image contents are unmodified
- License: **CC0 / public domain dedication**
- Usage status: retained as artwork source files but not referenced by the mod

The files may be used, modified, and redistributed without attribution under
CC0. Their source and author are retained here for provenance and credit.

## Original project artwork

The following artwork was created for this project and is covered by the
project's MIT license:

- `textures/minecart_lift_winch.png`
