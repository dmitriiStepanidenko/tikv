# Nix development shell and according packages

## Limitations
1. grpcio (and, may be others c/cpp library) won't compile without CXXFLAGS, that force gcc >= 12 to treat some warning as warning. OFC you can just change gcc to older version, but I (and nixpkgs community) consider that as bad practice.
2. Current implementation won't pair great with git submodules. All nix dependencies expects to provide correct hash, so every time when submodule updates, according version and hash inside nix should updates also

## Important remarks
1. I was choosed to use flake for two main reasons:
  1. I don't see nightly version of rust in nixpkgs, so I decided to use rust-overlay. Rust-overlay provides almost all rust versions.
  2. In a start of 2025 I tried to compile some plugins for comsmic desktop and I get into situation where rust build hooks didn't woked particularly well with git rust dependencies. So, I decided to use crane, to have more control and repeat official build steps from Makefile as close as possible. If I not mistaken, then particullary broken thig is state in this repository: https://github.com/NixOS/nixpkgs/issues/359340
2. Current implementation uses toolchain from rust-toolchain.toml 
3. Nix have immutable store, wehere it stores all artifacts. So, for example, when we reference parent dir in "build.rs" inside librocksdb_sys, nix couldn't find it and fails with error. So, I fixed this kind of error by packaging rocksdb, titan and crocksdb and then by providing needed static libraries during compilation. Ideally, in future, this packages should move to their own repositories

## Needed future improvements (todo)
1. [ ] Move all packages to according repos and simply call them via flake inputs
2. [ ] Write distinct doc file for build flags for each package
3. [ ] Get rid of patches by changing original repos
