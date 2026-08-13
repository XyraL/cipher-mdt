# Map assets

| Path | What it is |
|---|---|
| `tiles/{z}_{x}_{y}.webp` | What the MDT actually loads — a Leaflet tile pyramid, 129 tiles across 5 zoom levels, flat in one directory so fxmanifest can glob them with a single `*`. Generated, not hand-edited. |
| `san-andreas-satellite.webp` | The 4096×6144 source render the tiles are cut from. Kept so the tiles can be rebuilt; **not** served to the NUI. |
| `OULSEN-LICENSE.txt` | MIT licence for the satellite render ([Oulsen/oulsen_satmap](https://github.com/Oulsen/oulsen_satmap)). |

## Rebuilding the tiles

After swapping the source image:

```bash
npm install sharp
node tools/build-map-tiles.js
```

If the new image has different dimensions, update `MAP.imageW` / `MAP.imageH` /
`MAP.nativeZoom` at the top of `html/js/panels/map.js` — the build script prints
the native zoom it used.

## Calibrating the world bounds

`MAP.world` in `map.js` says which GTA world rectangle the render covers. If unit
dots land slightly off, stand somewhere recognisable in-game, note your coords,
open the Live Map, and nudge `minX/maxX/minY/maxY` until the dot sits on you.
