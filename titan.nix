{
  lib,
  stdenv,
  fetchFromGitHub,
  rocksdb,
  cmake,
  bzip2,
  zlib,
  lz4,
  snappy,
  zstd,
  jemalloc,
  portable ? stdenv.hostPlatform.isStatic,
  sse42Support ? stdenv.hostPlatform.sse4_2Support,
  withZlib ? true,
  withBz2 ? true,
  withLz4 ? true,
  withZstd ? true,
  withSnappy ? true,
}: let
  onOff = cond:
    if cond
    then "ON"
    else "OFF";
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "titan";
    version = "${builtins.substring 0 7 finalAttrs.src.rev}";
    src = fetchFromGitHub {
      owner = "tikv";
      repo = "titan";
      rev = "23fd528bf37b0ea0c5257adb90ff1e98643a5f65";
      hash = "sha256-U2m/wrNdqGyxDkrHQJA3QwzevuVtyJWjpN4RsGRAMa8=";
    };

    nativeBuildInputs = [
      cmake
      rocksdb
      jemalloc
    ];

    cmakeFlags = [
      "-DROCKSDB_DIR=${rocksdb.src}"

      "-DFORCE_SSE42=${onOff sse42Support}"
      "-DPORTABLE=${onOff portable}"
      "-DWITH_ZLIB=${onOff withZlib}"
      "-DWITH_BZ2=${onOff withBz2}"
      "-DWITH_LZ4=${onOff withLz4}"
      "-DWITH_ZSTD=${onOff withZstd}"
      "-DWITH_SNAPPY=${onOff withSnappy}"

      "-DWITH_TITAN_TESTS=OFF"
      "-DWITH_TITAN_TOOLS=OFF"
    ];

    buildPhase = ''
      runHook preBuild
      cmake --build . --target titan
      runHook postBuild
    '';

    postInstall = ''
      cp $src/src/blob_format.h $out/include/titan/
    '';

    buildInputs =
      [
        rocksdb
      ]
      ++ lib.optional withZlib zlib
      ++ lib.optional withBz2 bzip2
      ++ lib.optional withLz4 lz4
      ++ lib.optional withZstd zstd
      ++ lib.optional withSnappy snappy;

    meta = with lib; {
      description = "Titan library";
      platforms = platforms.linux;
    };
  })
