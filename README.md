![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# VGA Maze Runner

This project is a Tiny Tapeout VGA maze generator and maze game.

It generates a maze on-chip, shows the maze being built live on a VGA monitor, and then lets a player race against a single wall-following solver using a PMOD gamepad.

## Authorship

The majority of the RTL in the current version was written by GPT 5.4 using OpenCode.

This version is a rework of an earlier hand-written implementation. The rework was guided by user feedback to:

- replace the earlier generator with a better algorithm choice
- improve module structure and maintainability
- keep the Tiny Tapeout `1x1` area constraint in mind
- preserve the Tiny Tapeout VGA sync block and PMOD controller interface

In short: the current code is AI-generated RTL, but it was not produced blindly. The algorithm choice, modularization, tool use, and fit-for-area direction were steered by the user.

## What It Does

- generates a perfect maze using a procedural binary-tree generator by default
- uses a `10x10` maze in the default top-level configuration
- keeps alternate stored-map generators available as compile-time options
- renders the maze directly to VGA without a framebuffer
- shows the maze changing while generation is in progress
- lets the player move through the maze with a gamepad
- includes one wall-following solver

## Controls

- D-pad: move the player
- `A`: start or stop the solver
- `B`: reset player and solver positions
- `SELECT`: generate a new maze
- `START`: speed up generation while the maze is still being built

## Design Overview

- `src/tt_um_phsauter_vga_maze.v`: Tiny Tapeout top-level wrapper
- `src/hvsync_generator.v`: VGA timing generator from the Tiny Tapeout template
- `src/gamepad_pmod.v`: PMOD gamepad interface modules
- `src/maze_game_core.v`: gameplay, control FSM, seed handling, solver control, compile-time generator selection
- `src/maze_gen_binary_tree.v`: stored binary-tree generator
- `src/maze_gen_proc_binary_tree.v`: procedural binary-tree generator used by default
- `src/maze_gen_eller.v`: larger optional Eller generator kept as an alternate module
- `src/maze_map.v`: legacy compact maze wall storage module retained for comparison/refactoring work
- `src/maze_wall_query.v`: shared wall lookup logic for movement and rendering
- `src/maze_solver_hand.v`: reusable wall-follower solver block
- `src/maze_video.v`: VGA-side rendering and live generation highlight overlay

## Why This Architecture

Tiny Tapeout `1x1` area is tight, so the design avoids large memories and framebuffers.

The current default implementation uses a procedural binary-tree maze formula plus a row-by-row reveal, which minimizes state while still producing a real playable maze. Stored-map generator variants are still kept in the codebase as alternate compile-time options for comparison and future experiments.

The renderer uses power-of-two cell sizing so pixel-to-cell conversion is cheap, and the generator is throttled so the build process is visible instead of finishing instantly.

## External Hardware

- VGA output
- PMOD gamepad

## Running The Tests

From `test/`:

```sh
make -B
```

This runs the cocotb smoke tests against the RTL.

## Lint / Synthesis Checks

Examples used during development:

```sh
verilator --lint-only --top-module tt_um_phsauter_vga_maze -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND src/tt_um_phsauter_vga_maze.v src/maze_game_core.v src/maze_gen_eller.v src/maze_input_edges.v src/maze_map.v src/maze_solver_hand.v src/maze_video.v src/maze_wall_query.v src/gamepad_pmod.v src/hvsync_generator.v
```

```sh
yosys -p "read_verilog src/tt_um_phsauter_vga_maze.v src/maze_game_core.v src/maze_gen_eller.v src/maze_input_edges.v src/maze_map.v src/maze_solver_hand.v src/maze_video.v src/maze_wall_query.v src/gamepad_pmod.v src/hvsync_generator.v; hierarchy -top tt_um_phsauter_vga_maze; proc; opt; stat"
```

## More Info

- project metadata: `info.yaml`
- Tiny Tapeout datasheet text: `docs/info.md`
