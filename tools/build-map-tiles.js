/**
 * Slices the satellite render into a Leaflet tile pyramid.
 *
 *   npm install sharp
 *   node tools/build-map-tiles.js
 *
 * Reads  html/assets/maps/san-andreas-satellite.webp   (4096 x 6144)
 * Writes html/assets/maps/tiles/{z}_{x}_{y}.webp
 *
 * Zoom 0 is the whole map in a couple of tiles; the last zoom level is the
 * source at 1:1. Leaflet upscales beyond that via maxNativeZoom, so there is
 * no point generating levels above native — they would only be blur.
 *
 * Re-run this if you swap the source image, then update MAP.imageW/imageH in
 * html/js/panels/map.js if its dimensions changed.
 */
const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const ROOT     = path.join(__dirname, '..');
const SRC      = path.join(ROOT, 'html/assets/maps/san-andreas-satellite.webp');
const OUT      = path.join(ROOT, 'html/assets/maps/tiles');
const TILE     = 512;   // must match tileSize in map.js
const QUALITY  = 82;

(async () => {
    if (!fs.existsSync(SRC)) {
        console.error('Source image not found:', SRC);
        process.exit(1);
    }

    const meta = await sharp(SRC).metadata();
    console.log(`source ${meta.width}x${meta.height}`);

    // Native zoom is the level at which the image sits at 1:1.
    const maxDim    = Math.max(meta.width, meta.height);
    const nativeZoom = Math.ceil(Math.log2(maxDim / TILE));
    console.log(`native zoom ${nativeZoom} (tile ${TILE}px)`);

    fs.rmSync(OUT, { recursive: true, force: true });
    fs.mkdirSync(OUT, { recursive: true });

    let written = 0, bytes = 0;

    for (let z = 0; z <= nativeZoom; z++) {
        const scale = Math.pow(2, nativeZoom - z);
        const w = Math.ceil(meta.width / scale);
        const h = Math.ceil(meta.height / scale);

        // Resize once per level, then cut tiles out of that buffer.
        const level = await sharp(SRC)
            .resize(w, h, { fit: 'fill', kernel: 'lanczos3' })
            .toBuffer();

        const cols = Math.ceil(w / TILE);
        const rows = Math.ceil(h / TILE);

        for (let x = 0; x < cols; x++) {
            for (let y = 0; y < rows; y++) {
                const left = x * TILE, top = y * TILE;
                // The right/bottom edge tiles are short — extend them so every
                // tile is exactly TILE px, otherwise Leaflet stretches them.
                const cw = Math.min(TILE, w - left);
                const ch = Math.min(TILE, h - top);

                let tile = sharp(level).extract({ left, top, width: cw, height: ch });
                if (cw < TILE || ch < TILE) {
                    tile = tile.extend({
                        top: 0, left: 0,
                        bottom: TILE - ch, right: TILE - cw,
                        background: { r: 0, g: 0, b: 0, alpha: 0 },
                    });
                }

                // Flat filenames, one directory: fxmanifest globs a single
                // level reliably, nested ** does not always expand.
                const file = path.join(OUT, `${z}_${x}_${y}.webp`);
                await tile.webp({ quality: QUALITY }).toFile(file);

                written++;
                bytes += fs.statSync(file).size;
            }
        }
        console.log(`  z${z}: ${w}x${h} -> ${cols}x${rows} tiles`);
    }

    console.log(`\n${written} tiles, ${(bytes / 1048576).toFixed(1)} MB total`);
    console.log(`Set nativeZoom: ${nativeZoom} in map.js if it changed.`);
})();
