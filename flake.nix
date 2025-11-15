{
  description = "Build a cargo project with a custom toolchain";

  inputs = {
    # pinning to this version cuz of this:
    # - https://github.com/oxalica/rust-overlay/issues/242
    # - https://github.com/NixOS/nixpkgs/commit/1ec0227cc062251c36140ef1e7c37b1cd1b370f1
    nixos-25-05.url = "github:nixos/nixpkgs?ref=release-25.05";
    nixpkgs.follows = "nixos-25-05";

    crane = {
      url = "github:ipetkov/crane";
    };

    flake-utils.url = "github:numtide/flake-utils";

    rust-overlay = {
      # rust-overalay holds only N latest nightly, so we have to pin to some older commit to get needed nightly version
      url = "github:oxalica/rust-overlay?ref=06871d5c5f78b0ae846c5758702531b4cabfab9b";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    crane,
    flake-utils,
    rust-overlay,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            rust-overlay.overlays.default
          ];
        };
        openssl = pkgs.openssl.override {
          static = true;
        };
        inherit (pkgs) liburing;
        inherit (pkgs) lib;

        tikvRocksdbSrc = {
          owner = "tikv";
          repo = "rocksdb";
          rev = "9b26403a82ac38854372b4d6a259b9ea89bcfaf3";
          hash = "sha256-BQIdibYKNpMqpnWiQG+FybrYhA8tFIKy4FILjojWU2Q=";
        };
        rocksdb-custom = pkgs.rocksdb.overrideAttrs (oldAttrs: {
          version = builtins.substring 0 7 tikvRocksdbSrc.rev;
          src = pkgs.fetchFromGitHub tikvRocksdbSrc;
          enableJemalloc = true;
          enableShared = false;
          buildInputs = oldAttrs.buildInputs or [] ++ [liburing liburing.dev openssl.dev];
          cmakeFlags = (oldAttrs.cmakeFlags or []) ++ ["-DWITH_OPENSSL=ON"];
        });
        titan = pkgs.callPackage ./titan.nix {
          rocksdb = rocksdb-custom;
          portable = true;
        };
        tikvRustRocksdbSrc = {
          owner = "tikv";
          repo = "rust-rocksdb";
          rev = "755d152ec4eb443039296ceecf9a072a1142e014";
          hash = "sha256-N6xx8QGuIICFWJIdM1YgGs4Qppz1Q3kFmO3AoU1p7dc=";
        };
        crocksdb = pkgs.callPackage ./crocksdb.nix {
          rocksdb = rocksdb-custom;
          inherit tikvRustRocksdbSrc titan;
        };

        rustToolchain = pkgs.pkgsBuildHost.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        # If you wanna use different version of gcc, uncomment this and remain rustToolchain in line before
        # and add gcc into nativeBuildInputs/ override it via stdenv
        # Cuz rustToolchain always overwrites default stdenv to latest gcc
        #rustToolchain = pkgs.buildEnv {
        #  name = "rust-toolchain-bins-only";
        #  paths = [rustToolchainStock];
        #  pathsToLink = ["/bin" "/lib" "/libexec" "/share"];
        #  # Explicitly exclude stdenv-related stuff
        #  ignoreCollisions = false;
        #};

        craneLibToolchain = (crane.mkLib pkgs).overrideToolchain rustToolchain;
        craneLib = craneLibToolchain;

        buildPlatformSuffix = pkgs.lib.strings.toLower pkgs.pkgsBuildHost.stdenv.hostPlatform.rust.cargoShortTarget;
        commonCargoExtraArgs = "--no-default-features --features \"${enableFeatures}\"  -Z unstable-options --target ${buildPlatformSuffix}";

        enableFeatures = "memory-engine pprof-fp jemalloc mem-profiling portable sse test-engine-kv-rocksdb test-engine-raft-raft-engine trace-async-tasks openssl-vendored";

        src = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter = path: type: let
            # Check if it's a .data file
            isDataFile = pkgs.lib.hasSuffix ".data" path;
            # Check if it's a .in file
            isInFile = pkgs.lib.hasSuffix ".in" path;
            # Check if it passes the Cargo filter
            isCargoSource = craneLib.filterCargoSources path type;
          in
            isDataFile || isCargoSource || isInFile;
        };

        # "-w" : If we are building pacakge, we don't need any warning on someone's c/cpp code
        # especially when it can broke our build :(
        #
        # "-include" flags for the same reason. grpcio-sys won't compile abseil-cpp with gcc >= 13
        CXXFLAGS = lib.concatStringsSep " " [
          "-w"
          "-Wno-dev"
          "-include cstdint"
          "-include algorithm"
        ];

        patchedCargoLock = pkgs.stdenv.mkDerivation {
          src = ./Cargo.lock;
          name = "Cargo_lock";
          dontUnpack = true;
          patches = [
            ./0001-cargo-lock.patch
          ];
          prePatch = ''
            cp $src Cargo.lock
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp Cargo.lock $out
            runHook postInstall
          '';
        };
        isRocksDbRepo = p:
          lib.hasPrefix
          "git+https://github.com/tikv/rust-rocksdb.git#"
          p.source;
        cargoVendorDir = craneLib.vendorCargoDeps {
          src = patchedCargoLock;
          overrideVendorGitCheckout = ps: drv:
            if lib.any (p: isRocksDbRepo p && p.name == "librocksdb_sys") ps
            then
              drv.overrideAttrs (_old: {
                patches = [./0002-libtitan-in-rocks.patch];
                postPatch = ''
                  cp librocksdb_sys/libtitan_sys/titan/src/blob_format.h librocksdb_sys/libtitan_sys/titan/include/titan/blob_format.h
                  echo applied cp blob_format.h
                '';
              })
            else drv;
        };

        RUSTFLAGS = lib.concatStringsSep " " [
          "-L ${crocksdb}/lib"
          "-L ${rocksdb-custom}/lib"
          "-L ${titan}/lib"
          "-L ${liburing}/lib"
          "-L ${pkgs.jemalloc}/lib"
          "-l static=crocksdb"
          "-l static=rocksdb"
          "-l static=titan"
          "-l static=jemalloc"
          "-l uring"
          "-l uring-ffi"
        ];
        commonArgs = {
          inherit src;
          inherit cargoVendorDir;

          cargoExtraArgs = "${commonCargoExtraArgs}";
          inherit RUSTFLAGS;
          inherit cargoArtifacts;

          nativeBuildInputs = [
            pkgs.pkg-config
            pkgs.cmake
            pkgs.gnumake
            titan
            rocksdb-custom
            crocksdb
            pkgs.jemalloc
          ];
          doCheck = false;

          #hardeningDisable = ["all"];

          buildInputs = [
            pkgs.git
            openssl
            openssl.dev

            titan
            rocksdb-custom
            crocksdb

            pkgs.snappy
            pkgs.lz4
            pkgs.zstd
            pkgs.bzip2

            pkgs.jemalloc
            liburing
            liburing.dev
          ];

          inherit CXXFLAGS;
          OPENSSL_NO_VENDOR = "1";
          PKG_CONFIG_PATH = "${openssl.dev}/lib/pkgconfig";
        };
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;
        individualCrateArgs =
          commonArgs
          // {
            inherit RUSTFLAGS;
            inherit (craneLib.crateNameFromCargoToml {inherit src;}) version;
            doCheck = false;
          };
        tikv = craneLib.buildPackage (individualCrateArgs
          // {
            inherit src;
            pname = "tikv-server";
            doCheck = false;
            cargoExtraArgs = "${commonCargoExtraArgs} -p tikv-server -p tikv-ctl";
          });
      in {
        packages = {
          inherit tikv;
          # Next mostly for debug purposes
          inherit cargoArtifacts;
          inherit rocksdb-custom;
          inherit titan;
          inherit crocksdb;
        };
        inherit pkgs;

        devShells.default = craneLib.devShell {
          # Automatically inherit any build inputs from `cargoArtifacts`
          inputsFrom = [cargoArtifacts];

          env = {
            OPENSSL_NO_VENDOR = "1";
            PKG_CONFIG_PATH = "${openssl.dev}/lib/pkgconfig";

            # comment this to see c/cpp warnings as errors (grpcio won't compile)
            inherit CXXFLAGS;
          };
        };
        nixosModules = {
          tikv = {
            config,
            lib,
            pkgs,
            ...
          }: let
            tikvPackage = self.packages.${pkgs.system}.tikv;
          in
            import ./tikv-service.nix {inherit config lib tikvPackage craneLib pkgs;};

          tikv-multi = {
            config,
            lib,
            pkgs,
            ...
          }: let
            tikvPackage = self.packages.${pkgs.system}.tikv;
          in
            import ./tikv-service.nix {inherit config lib tikvPackage craneLib pkgs;};

          default = self.nixosModules.tikv;
        };
      }
    )
    // {
      nixosConfigurations = let
        system = "x86_64-linux";
      in {
        vm = nixpkgs.lib.makeOverridable inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs;
          };
          modules = [
            self.nixosModules."${system}".tikv
            ./test-service.nix
          ];
        };
      };
    };
}
