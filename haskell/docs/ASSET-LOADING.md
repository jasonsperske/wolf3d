# Loading the shareware maps

`Wolf.Assets` implements the map path described by the original repository's `ID_CA.C` (`CA_CacheMap`, `CAL_CarmackExpand`, `CA_RLEWexpand`) and `WL_GAME.C` (`ScanInfoPlane`, `SetupGameLevel`). The loader reads local files; it does not need an asset download or a new Haskell package.

## Bytes → words → planes → game state

There are deliberately two boundaries:

```haskell
decodeMap :: ByteString -> ByteString -> Int -> Either String MapData
toLevel   :: MapData -> Either String Level
```

Decoding preserves the original data. Translation chooses how much the teaching game understands. An unimplemented object does not disappear from the decoded representation merely because it has no gameplay counterpart yet.

1. `MAPHEAD.WL1` contains a little-endian 16-bit RLEW marker followed by 100 little-endian 32-bit map offsets into `GAMEMAPS.WL1`. Zero and `0xffffffff` mean absent maps. The command-line map number is one-based.
2. Each selected map header has three 32-bit plane offsets, three 16-bit compressed plane lengths, 16-bit width and height, and a 16-byte zero-terminated name. Only 64×64 WL1 maps are accepted here.
3. Each compressed plane begins with its Carmack-expanded size in **bytes**. The remaining bytes expand to a stream of 16-bit words.
4. That word stream begins with the RLEW-expanded size in **bytes**. After RLEW expansion, each plane contains exactly 4096 words, ordered row by row (`y * width + x`).
5. Plane 0 contains walls, doors, areas, and special geometry. Plane 1 contains the player and objects. Plane 2 is retained even though the teaching engine does not use it.

## Carmack compression is a word-copy codec

A word whose high byte is neither `0xa7` nor `0xa8` is a literal. For those two tags, the low byte is a copy count. A near copy (`0xa7`) reads an additional one-byte backward distance; a far copy (`0xa8`) reads a two-byte absolute index into the expanded word buffer. If the count is zero, an extra byte supplies the low byte of a literal tag word instead.

The extra one-byte operands mean the input cursor can become odd. Casting input bytes to an array of aligned words would therefore be incorrect. `word16` explicitly assembles little-endian values at any byte position.

Copies can overlap their own destination. For example, one literal followed by a three-word copy with backward distance one expands into four copies of the literal. The implementation appends one word at a time to `Data.Sequence` and reads from the growing result. Taking a fixed slice of the original prefix would fail this case. Sequence indexing costs more than an ST array, but is concise, bounds-checked, and adequate for map loading outside the frame loop.

## RLEW compression replaces runs

The marker comes from `MAPHEAD`, rather than being hardcoded. An ordinary word is copied once. A marker is followed by a count and repeated value. Counts must be positive and fit the remaining output. A run can represent the marker itself.

Both codecs stop at their declared output size and reject trailing input. Every byte slice and backreference is checked. The 16-bit Carmack byte count bounds intermediate output; validated dimensions bound final output to 4096 words per plane. Offsets are decoded as `Integer` and checked against the file size before conversion to machine `Int`. The loader reports file-access errors and malformed data as useful messages rather than falling back silently to the demo.

These guarantees apply to decoding. A structurally valid map is not necessarily reachable, fair, or compatible with the simplified game rules.

## Translation policy

| Source data | Teaching engine |
|---|---|
| Geometry 90–101 | Door; original orientation/key restrictions are not implemented |
| Geometry 21 | Solid green elevator panel; use E nearby to win |
| Geometry 106 | Ambush floor marker, treated as floor |
| Geometry 107 and above | Area floor; area-connectivity behavior is not simulated |
| Other geometry | Solid wall |
| Object 19–22 | North/east/south/west player start, translated to our clockwise radian angle |
| Object 108–123, 126–141 | Easy-difficulty guard/officer/SS/dog positions, represented as generic guards |
| Object 214 | Boss position, represented as a generic guard |
| Higher-difficulty enemy additions | Ignored; the importer uses easy placement |
| Decorations, pickups, patrol arrows | Retained in raw data, ignored by current gameplay |
| Pushwall object marker | Wall remains fixed; no secret-wall movement |

`toLevel` requires exactly one player, a floor spawn, and correct plane sizes. Some shipped maps contain area codes at the boundary, so unlike the text demo parser it does not require every boundary cell to be a wall. The existing `tileAt` treats positions outside the array as solid, keeping collision and rays bounded. It does not require an elevator, because the boss floor uses different original completion logic. The renderer derives minimap dimensions from the tile array; 64×64 levels are shown at one pixel per cell.

## Tests

`make test` runs synthetic literal, escaped-tag, overlapping near/far copy, RLEW, malformed-size, truncation, invalid-reference, header, coordinate, spawn-facing, and elevator checks, plus the existing game tests. Its synthetic full map is constructed in code, so no original assets are needed.

`make test-assets` additionally loads the user's `../wolf3dsw` files. It verifies all ten maps, all three plane checksums, known player coordinates, valid spawn footprints, and rendering. It writes ten inspectable PPM images to `build/`. Override the directory with `make test-assets ASSET_DIR=/path/to/wolf3dsw`. The checksum goldens were independently decoded from the supplied December 1992 files; another shareware revision can decode correctly but fail these revision-specific checks.

Textures in `VSWAP`, sprite shapes, VGA UI resources, audio, collision for decorations, and faithful actor state machines are not part of this loader change. They can consume the preserved plane data in later extensions.
