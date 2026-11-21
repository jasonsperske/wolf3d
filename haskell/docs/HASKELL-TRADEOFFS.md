# Where Haskell helps, and where it costs

This implementation is a learning experiment, not a benchmark proving one language superior. The relevant comparisons are about this code and its design; well-structured C can also separate effects, use explicit state, and be thoroughly tested.

## Pure updates make dependencies visible

`step :: Double -> Input -> World -> World` says exactly what the simulation consumes. A test can create a world, advance it 60 ticks, and inspect the position without a window or mocked clock. Debugging can preserve the pre-tick world while inspecting the post-tick world. Replay and branching simulations become natural extensions.

The cost is plumbing. Functions need access to the values they use, and record updates become verbose as the world grows. Keeping every old world for debugging retains memory. Purity permits replay but does not guarantee cross-platform bit-identical floating-point results. IO-driven input still needs deliberate recording at tick boundaries.

## Algebraic data types describe the alternatives

`Outcome = Playing | Won | Lost` cannot simultaneously say "won" and "lost." `DoorState = Closed | Opening Double | Open` makes progress relevant only during opening. Pattern matching keeps state transitions together. Compiler warnings help reveal missing cases when a state is added.

Types do not prove everything here. `Opening 42` is representable; a public `World` constructor can pair the wrong door map with a level. The parser and transition functions maintain these invariants by convention and tests. Hiding constructors or introducing bounded progress types would strengthen this at the price of more teaching overhead. `-Wall` warns about many mistakes, but warnings are not mathematical proofs.

## Immutability simplifies ownership

Updating the player shares the unchanged level. Rendering cannot secretly advance the simulation. Guard traversal computes damage explicitly instead of modifying player health from several call sites. There are no manual frees for Haskell maps, guards, or pixels.

Allocation and garbage collection remain real costs. The renderer creates a framebuffer each frame, traversals allocate lists, and the FFI copy materializes pixel elements. A real-time engine must inspect allocation rate and frame-time spikes, not just average throughput. Strict fields reduce thunk buildup but do not eliminate allocation, deeply force containers, or automatically choose an efficient layout.

## Local mutation is useful

`ST` combines an immutable public interface with in-place pixel writes. It lets the compiler enforce that the mutable buffer stays local. This is a strong fit for a software renderer: pixel loops stay straightforward without exposing a writable framebuffer to arbitrary game code.

The concepts are more advanced than a C array: monads, state-thread variables, mutable versus immutable array types, and freezing. Compiler errors around inferred state constraints can be intimidating. For learners, start with what `render` promises, then study its local implementation. You do not need a monad transformer stack to write this engine.

## Small abstractions keep the math readable

Vector operations, pattern matching, list comprehensions, and immutable maps express intent compactly. DDA shares one implementation between wall rendering and line-of-sight tests. Pure code makes focused edge-case tests inexpensive.

Compact source can hide work. `sortOn` allocates and sorts every frame; `map` constructs lists; boxed arrays and records add indirection. At this scale they favor clarity. At thousands of actors, use measured data to choose arrays, strict folds, spatial indexing, or mutable structures. "Functional" is not a storage layout.

## The platform boundary adds friction

The C adapter isolates SDL struct layouts and exposes a few scalar/pointer calls. Haskell's `bracket_` ties platform cleanup to normal exit and exceptions. No C code knows what a guard, wall, or hit point is. Packed pixels and a documented input bitmask make the boundary inspectable.

The cost is two toolchains, matching C signatures, native headers, library discovery, and FFI lifetime rules. The compiler cannot verify that `platform_present` reads exactly the allocated number of pixels. `unsafe` FFI calls assume short native operations; presentation can wait for vsync and would deserve a `safe` call or dedicated presentation thread if Haskell concurrency were introduced. The game currently runs on one thread, so this is a deliberate minimal-shell choice.

A Haskell SDL binding would eliminate the handwritten C adapter but add package/API concepts and dependency resolution. This edition prioritizes a Make build with GHC-bundled Haskell libraries. It is predominantly Haskell, not literally zero C.

## Numerical simplicity changes behavior

Doubles make geometry easy to read and avoid fixed-point bookkeeping. They are a reasonable modern baseline. They do not reproduce the original integer rounding, collision edge cases, or timing. This branch uses a fixed simulation timestep, yet input is sampled per rendered frame and floating-point computations can vary across platforms. Exact original demo playback would require much stronger compatibility constraints.

## What to measure next

Build with optimization (the Make default is `-O2`). Run the game with `+RTS -s`, traverse several rooms, then quit. Inspect bytes allocated, maximum residency, and GC time. For serious frame-pacing work, record individual frame durations and compare optimized builds on the same hardware, resolution, scene, and workload.

The likely inspection points are the `elems`/`pokeArray` copy, fresh frame allocation, list-based sprite sorting, and repeated visibility queries. These are hypotheses from the code, not measured bottleneck claims. Headless tests establish behavior, and a one-frame SDL smoke test establishes basic integration; neither establishes sustained interactive performance.
