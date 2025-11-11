{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  bzip2,
  zlib,
  lz4,
  snappy,
  zstd,
  pkg-config,
  # Custom inputs
  titan,
  tikvRustRocksdbSrc,
  rocksdb,
}:
stdenv.mkDerivation (finalAttrs: {
  name = "crocksdb";
  version = "${builtins.substring 0 7 finalAttrs.src.rev}";
  src = fetchFromGitHub tikvRustRocksdbSrc;

  nativeBuildInputs = [
    cmake
    pkg-config
    rocksdb
    titan
  ];

  buildInputs = [
    zlib
    bzip2
    lz4
    snappy
    zstd
  ];

  dontUseCmakeConfigure = true;

  buildPhase = ''
    $CXX -c \
      -DROCKSDB_PLATFORM_POSIX \
      -DPORTABLE=1 \
      -DWITH_BZ2=1 \
      -DWITH_LZ4=1 \
      -DWITH_SNAPPY=1 \
      -DWITH_ZLIB=1 \
      -DWITH_ZSTD=1 \
      -DWITH_JEMALLOC=ON \
      -DFAIL_ON_WARNINGS=NO \
      -DFORCE_SSE42=1 \
      -DOPENSSL \
      -w -include cstdint -include algorithm \
      -std=c++17 \
      -fno-rtti \
      -I$src/librocksdb_sys/crocksdb \
      -I${rocksdb.src} \
      -I${rocksdb.src}/include \
      -I${titan.src}/include \
      -I${titan.src} \
      $src/librocksdb_sys/crocksdb/c.cc \
      -o c.o

    ar rcs libcrocksdb.a c.o
  '';

  installPhase = ''
        mkdir -p $out/lib
        mkdir -p $out/include
        cp libcrocksdb.a $out/lib/
        cp $src/librocksdb_sys/crocksdb/crocksdb/c.h $out/include/

        mkdir -p $out/lib/pkgconfig
        cat > $out/lib/pkgconfig/crocksdb.pc <<EOF
    prefix=$out
    libdir=\''${prefix}/lib
    includedir=\''${prefix}/include

    Name: crocksdb
    Description: C wrapper for RocksDB
    Version: ${finalAttrs.version}
    Libs: -L\''${libdir} -lcrocksdb -L${rocksdb}/lib -lrocksdb -L${titan}/lib -ltitan
    Cflags: -I\''${includedir}
    EOF
  '';

  meta = with lib; {
    description = "Build crocksdb c.cc file";
    platforms = platforms.linux;
  };
})
