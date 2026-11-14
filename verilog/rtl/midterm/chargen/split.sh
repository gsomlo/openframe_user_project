#!/bin/bash

DEST='../../../../cf_rom_sync_midterm_build'

# split utfglphrom 4096x72bit image across 4x9 1024x8bit tiles:
for ((r=0;r<4;r++)); do
  let ROW=r*1024+1
  for ((c=0;c<9;c++)); do
    let CO2=(9-c)*2
    let CO1=CO2-1
    tail -n +$ROW utfglphrom.rom | head -n 1024 | cut -c$CO1-$CO2 \
         > "$DEST/CF_ROM_SYNC.rom_grid.r[$r].c[$c].rom_tile.rom"
  done
done
