#!/usr/bin/env bash

# Exit on error
# Error on undefined variable
set -e
set -u

# This should match the DEPS_VERSION in CMakeLists.txt.
# This is mostly to ensure the path the files end up at if you build deps yourself
# are the same as the ones when extracting from the downloaded packages.
DEPS_VERSION=8

# Package versions
PKGCONFIG_VERSION=0.29.2
NASM_VERSION=2.15.05
ZLIB_VERSION=1.2.13
GMP_VERSION=6.2.1
NETTLE_VERSION=3.7.3
CURL_VERSION=7.83.1
SDL2_VERSION=2.26.5
GLEW_VERSION=2.2.0
PNG_VERSION=1.6.37
JPEG_VERSION=2.1.5.1
WEBP_VERSION=1.2.2
FREETYPE_VERSION=2.12.1
OPENAL_VERSION=1.21.1  # Not using 1.22.0 due to https://github.com/kcat/openal-soft/issues/719
OGG_VERSION=1.3.5
VORBIS_VERSION=1.3.7
OPUS_VERSION=1.3.1
OPUSFILE_VERSION=0.12
LUA_VERSION=5.4.4
NACLSDK_VERSION=44.0.2403.155
NCURSES_VERSION=6.2
WASISDK_VERSION=16.0
WASMTIME_VERSION=2.0.2

# Require the compiler names to be explicitly hardcoded, we should not inherit them
# from environment as we heavily cross-compile.
CC='false'
CXX='false'
# Set defaults.
LD='ld'
AR='ar'
RANLIB='ranlib'
CONFIGURE_SHARED=(--disable-shared --enable-static)
# Always reset flags, we heavily cross-compile and must not inherit any stray flag
# from environment.
CFLAGS=''
CXXFLAGS=''
CPPFLAGS=''
LDFLAGS=''

# Extract an archive into the given subdirectory of the build dir and cd to it
# Usage: extract <filename> <directory>
extract() {
	rm -rf "${BUILD_DIR}/${2}"
	mkdir -p "${BUILD_DIR}/${2}"
	case "${1}" in
	*.tar.bz2)
		tar xjf "${DOWNLOAD_DIR}/${1}" -C "${BUILD_DIR}/${2}"
		;;
	*.tar.xz)
		tar xJf "${DOWNLOAD_DIR}/${1}" -C "${BUILD_DIR}/${2}"
		;;
	*.tar.gz|*.tgz)
		tar xzf "${DOWNLOAD_DIR}/${1}" -C "${BUILD_DIR}/${2}"
		;;
	*.zip)
		unzip -d "${BUILD_DIR}/${2}" "${DOWNLOAD_DIR}/${1}"
		;;
	*.cygtar.bz2)
		# Some Windows NaCl SDK packages have incorrect symlinks, so use
		# cygtar to extract them.
		"${SCRIPT_DIR}/cygtar.py" -xjf "${DOWNLOAD_DIR}/${1}" -C "${BUILD_DIR}/${2}"
		;;
	*.dmg)
		mkdir -p "${BUILD_DIR}/${2}-dmg"
		hdiutil attach -mountpoint "${BUILD_DIR}/${2}-dmg" "${DOWNLOAD_DIR}/${1}"
		cp -R "${BUILD_DIR}/${2}-dmg/"* "${BUILD_DIR}/${2}/"
		hdiutil detach "${BUILD_DIR}/${2}-dmg"
		rmdir "${BUILD_DIR}/${2}-dmg"
		;;
	*)
		echo "Unknown archive type for ${1}"
		exit 1
		;;
	esac
	cd "${BUILD_DIR}/${2}"
}

# Download a file if it doesn't exist yet, and extract it into the build dir
# Usage: download <filename> <URL> <dir>
download() {
	if [ ! -f "${DOWNLOAD_DIR}/${1}" ]; then
		curl -L --fail -o "${DOWNLOAD_DIR}/${1}" "${2}"
	fi
	extract "${1}" "${3}"
}

# Build pkg-config
build_pkgconfig() {
	download "pkg-config-${PKGCONFIG_VERSION}.tar.gz" "http://pkgconfig.freedesktop.org/releases/pkg-config-${PKGCONFIG_VERSION}.tar.gz" pkgconfig
	cd "pkg-config-${PKGCONFIG_VERSION}"
	# The default -O2 is dropped when there's user-provided CFLAGS.
	CFLAGS="${CFLAGS} -O2" ./configure --host="${HOST}" --prefix="${PREFIX}" --with-internal-glib
	make
	make install
}

# Build NASM
build_nasm() {
	case "${PLATFORM}" in
	macos-*-*)
		download "nasm-${NASM_VERSION}-macosx.zip" "https://www.nasm.us/pub/nasm/releasebuilds/${NASM_VERSION}/macosx/nasm-${NASM_VERSION}-macosx.zip" nasm
		cp "nasm-${NASM_VERSION}/nasm" "${PREFIX}/bin"
		;;
	*)
		echo "Unsupported platform for NASM"
		exit 1
		;;
	esac
}

# Build zlib
build_zlib() {
	download "zlib-${ZLIB_VERSION}.tar.xz" "https://zlib.net/zlib-${ZLIB_VERSION}.tar.xz" zlib
	cd "zlib-${ZLIB_VERSION}"
	case "${PLATFORM}" in
	windows-*-*)
		LOC="${CFLAGS}" make -f win32/Makefile.gcc PREFIX="${HOST}-"
		make -f win32/Makefile.gcc install BINARY_PATH="${PREFIX}/bin" LIBRARY_PATH="${PREFIX}/lib" INCLUDE_PATH="${PREFIX}/include" SHARED_MODE=1
		;;
	*)
		# The default -O3 is dropped when there's user-provided CFLAGS.
		CFLAGS="${CFLAGS} -O3" ./configure --prefix="${PREFIX}" --static --const
		make
		make install
	esac
}

# Build GMP
build_gmp() {
	download "gmp-${GMP_VERSION}.tar.bz2" "https://gmplib.org/download/gmp/gmp-${GMP_VERSION}.tar.bz2" gmp
	cd "gmp-${GMP_VERSION}"
	case "${PLATFORM}" in
	windows-*-msvc)
		# Configure script gets confused if we override the compiler. Shouldn't
		# matter since gmp doesn't use anything from libgcc.
		local CC_BACKUP="${CC}"
		local CXX_BACKUP="${CXX}"
		unset CC
		unset CXX
		;;
	esac

	# The default -O2 is dropped when there's user-provided CFLAGS.
	case "${PLATFORM}" in
	macos-*-*)
		# The assembler objects are incompatible with PIE
		CFLAGS="${CFLAGS} -O2" ./configure --host="${HOST}" --prefix="${PREFIX}" "${CONFIGURE_SHARED[@]}" --disable-assembly
		;;
	*)
		CFLAGS="${CFLAGS} -O2" ./configure --host="${HOST}" --prefix="${PREFIX}" "${CONFIGURE_SHARED[@]}"
		;;
	esac

	make
	make install
	case "${PLATFORM}" in
	windows-*-msvc)
		export CC="${CC_BACKUP}"
		export CXX="${CXX_BACKUP}"
		;;
	esac
}

# Build Nettle
build_nettle() {
	# download "nettle-${NETTLE_VERSION}.tar.gz" "https://www.lysator.liu.se/~nisse/archive/nettle-${NETTLE_VERSION}.tar.gz" nettle
	download "nettle-${NETTLE_VERSION}.tar.gz" "https://ftp.gnu.org/gnu/nettle/nettle-${NETTLE_VERSION}.tar.gz" nettle
	cd "nettle-${NETTLE_VERSION}"
	# The default -O2 is dropped when there's user-provided CFLAGS.
	CFLAGS="${CFLAGS} -O2" ./configure --host="${HOST}" --prefix="${PREFIX}" "${CONFIGURE_SHARED[@]}"
	make
	make install
}

# Build cURL
build_curl() {
	download "curl-${CURL_VERSION}.tar.bz2" "https://curl.haxx.se/download/curl-${CURL_VERSION}.tar.bz2" curl
	cd "curl-${CURL_VERSION}"
	# The user-provided CFLAGS doesn't drop the default -O2
	./configure --host="${HOST}" --prefix="${PREFIX}" --without-ssl --without-libssh2 --without-librtmp --without-libidn2 --disable-file --disable-ldap --disable-crypto-auth --disable-gopher --disable-ftp --disable-tftp --disable-dict --disable-imap --disable-mqtt --disable-smtp --disable-pop3 --disable-telnet --disable-rtsp --disable-threaded-resolver --disable-alt-svc "${CONFIGURE_SHARED[@]}"
	make
	make install
}

# Build SDL2
build_sdl2() {
	case "${PLATFORM}" in
	windows-*-mingw)
		download "SDL2-devel-${SDL2_VERSION}-mingw.tar.gz" "https://www.libsdl.org/release/SDL2-devel-${SDL2_VERSION}-mingw.tar.gz" sdl2
		cd "SDL2-${SDL2_VERSION}"
		make install-package arch="${HOST}" prefix="${PREFIX}"
		;;
	windows-*-msvc)
		download "SDL2-devel-${SDL2_VERSION}-VC.zip" "https://www.libsdl.org/release/SDL2-devel-${SDL2_VERSION}-VC.zip" sdl2
		cd "SDL2-${SDL2_VERSION}"
		mkdir -p "${PREFIX}/SDL2/cmake"
		cp "cmake/"* "${PREFIX}/SDL2/cmake"
		mkdir -p "${PREFIX}/SDL2/include"
		cp "include/"* "${PREFIX}/SDL2/include"

		case "${PLATFORM}" in
		*-i686-*)
			local sdl2_lib_dir='lib/x86'
			;;
		*-amd64-*)
			local sdl2_lib_dir='lib/x64'
			;;
		*)
			echo "Unsupported platform for SDL2"
			exit 1
			;;
		esac

		mkdir -p "${PREFIX}/SDL2/${sdl2_lib_dir}"
		cp "${sdl2_lib_dir}/"{SDL2.lib,SDL2main.lib} "${PREFIX}/SDL2/${sdl2_lib_dir}"
		cp "${sdl2_lib_dir}/"*.dll "${PREFIX}/SDL2/${sdl2_lib_dir}"
		;;
	macos-*-*)
		download "SDL2-${SDL2_VERSION}.dmg" "https://libsdl.org/release/SDL2-${SDL2_VERSION}.dmg" sdl2
		rm -rf "${PREFIX}/SDL2.framework"
		cp -R "SDL2.framework" "${PREFIX}"
		;;
	*)
		download "SDL2-${SDL2_VERSION}.tar.gz" "https://www.libsdl.org/release/SDL2-${SDL2_VERSION}.tar.gz" sdl2
		cd "SDL2-${SDL2_VERSION}"
		# The default -O3 is dropped when there's user-provided CFLAGS.
		CFLAGS="${CFLAGS} -O3" ./configure --host="${HOST}" --prefix="${PREFIX}" "${CONFIGURE_SHARED[@]}"
		make
		make install
		;;
	esac
}

# Build GLEW
build_glew() {
	download "glew-${GLEW_VERSION}.tgz" "https://downloads.sourceforge.net/project/glew/glew/${GLEW_VERSION}/glew-${GLEW_VERSION}.tgz" glew
	cd "glew-${GLEW_VERSION}"
	case "${PLATFORM}" in
	windows-*-*)
		make SYSTEM="linux-mingw${BITNESS}" GLEW_DEST="${PREFIX}" CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" STRIP="${HOST}-strip" LD="${LD}" CFLAGS.EXTRA="${CFLAGS}" LDFLAGS.EXTRA="${LDFLAGS}"
		make install SYSTEM="linux-mingw${BITNESS}" GLEW_DEST="${PREFIX}" CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" STRIP="${HOST}-strip" LD="${LD}" CFLAGS.EXTRA="${CFLAGS}" LDFLAGS.EXTRA="${LDFLAGS}"
		mv "${PREFIX}/lib/glew32.dll" "${PREFIX}/bin/"
		rm "${PREFIX}/lib/libglew32.a"
		cp lib/libglew32.dll.a "${PREFIX}/lib/"
		;;
	macos-*-*)
		make SYSTEM=darwin GLEW_DEST="${PREFIX}" CC="${CC}" LD="${CC}" CFLAGS.EXTRA="${CFLAGS} -dynamic -fno-common" LDFLAGS.EXTRA="${LDFLAGS}"
		make install SYSTEM=darwin GLEW_DEST="${PREFIX}" CC="${CC}" LD="${CC}" CFLAGS.EXTRA="${CFLAGS} -dynamic -fno-common" LDFLAGS.EXTRA="${LDFLAGS}"
		install_name_tool -id "@rpath/libGLEW.${GLEW_VERSION}.dylib" "${PREFIX}/lib/libGLEW.${GLEW_VERSION}.dylib"
		;;
	linux-*-*)
		make GLEW_DEST="${PREFIX}" CC="${CC}" LD="${CC}" CFLAGS.EXTRA="${CFLAGS}" LDFLAGS.EXTRA="${LDFLAGS}"
		make install GLEW_DEST="${PREFIX}" CC="${CC}" LD="${CC}" CFLAGS.EXTRA="${CFLAGS}" LDFLAGS.EXTRA="${LDFLAGS}"
		;;
	*)
		echo "Unsupported platform for GLEW"
		exit 1
		;;
	esac
}

# Build PNG
build_png() {
	download "libpng-${PNG_VERSION}.tar.gz" "https://download.sourceforge.net/libpng/libpng-${PNG_VERSION}.tar.gz" png
	cd "libpng-${PNG_VERSION}"
	# The default -O2 is dropped when there's user-provided CFLAGS.
	CFLAGS="${CFLAGS} -O2" ./configure --host="${HOST}" --prefix="${PREFIX}" "${CONFIGURE_SHARED[@]}"
	make
	make install
}

# Build JPEG
build_jpeg() {
	download "libjpeg-turbo-${JPEG_VERSION}.tar.gz" "https://downloads.sourceforge.net/project/libjpeg-turbo/${JPEG_VERSION}/libjpeg-turbo-${JPEG_VERSION}.tar.gz" jpeg

	case "${PLATFORM}" in
	windows-*-*)
		local SYSTEM_NAME='Windows'
		;;
	macos-*-*)
		local SYSTEM_NAME='Darwin'
		;;
	linux-*-*)
		local SYSTEM_NAME='Linux'
		;;
	*)
		# Other platforms can build but we need need to explicitly
		# set CMAKE_SYSTEM_NAME for CMAKE_CROSSCOMPILING to be set
		# and CMAKE_SYSTEM_PROCESSOR to not be ignored by cmake.
		echo "Unsupported platform for JPEG"
		exit 1
		;;
	esac

	case "${PLATFORM}" in
	*-amd64-*)
		local SYSTEM_PROCESSOR='x86_64'
		# Ensure NASM is available
		nasm --help >/dev/null
		;;
	*-i686-*)
		local SYSTEM_PROCESSOR='i386'
		# Ensure NASM is available
		nasm --help >/dev/null
		;;
	*-arm64-*)
		local SYSTEM_PROCESSOR='aarch64'
		;;
	*-armhf-*)
		local SYSTEM_PROCESSOR='arm'
		;;
	*)
		echo "Unsupported platform for JPEG"
		exit 1
		;;
	esac

	local jpeg_cmake_call=(cmake -S . -B build -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
		-DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
		-DCMAKE_SYSTEM_NAME="${SYSTEM_NAME}" -DCMAKE_SYSTEM_PROCESSOR="${SYSTEM_PROCESSOR}" \
		-DWITH_JPEG8=1)
	cd "libjpeg-turbo-${JPEG_VERSION}"
	case "${PLATFORM}" in
	windows-*-mingw)
		"${jpeg_cmake_call[@]}" -DCMAKE_TOOLCHAIN_FILE="${SCRIPT_DIR}/../cmake/cross-toolchain-mingw${BITNESS}.cmake" -DENABLE_SHARED=0
		;;
	windows-*-msvc)
		"${jpeg_cmake_call[@]}" -DCMAKE_TOOLCHAIN_FILE="${SCRIPT_DIR}/../cmake/cross-toolchain-mingw${BITNESS}.cmake" -DENABLE_SHARED=1
		;;
	*)
		"${jpeg_cmake_call[@]}" -DENABLE_SHARED=0
		;;
	esac
	make -C build
	make -C build install
}

# Build WebP
build_webp() {
	download "libwebp-${WEBP_VERSION}.tar.gz" "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-${WEBP_VERSION}.tar.gz" webp
	cd "libwebp-${WEBP_VERSION}"
	# The default -O2 is dropped when there's user-provided CFLAGS.
	CFLAGS="${CFLAGS} -O2" ./configure --host="${HOST}" --prefix="${PREFIX}" --disable-libwebpdemux "${CONFIGURE_SHARED[@]}"
	make
	make install
}

# Build FreeType
build_freetype() {
	download "freetype-${FREETYPE_VERSION}.tar.gz" "https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.gz" freetype
	cd "freetype-${FREETYPE_VERSION}"
	# The default -O2 is dropped when there's user-provided CFLAGS.
	CFLAGS="${CFLAGS} -O2" ./configure --host="${HOST}" --prefix="${PREFIX}" "${CONFIGURE_SHARED[@]}" --without-bzip2 --without-png --with-harfbuzz=no --with-brotli=no
	make
	make install
	cp -a "${PREFIX}/include/freetype2" "${PREFIX}/include/freetype"
	mv "${PREFIX}/include/freetype" "${PREFIX}/include/freetype2/freetype"
}

# Build OpenAL
build_openal() {
	local openal_cmake_call=(cmake -S . -B . -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
		-DCMAKE_C_FLAGS="${CFLAGS}" -DCMAKE_CXX_FLAGS="${CXXFLAGS}" \
		-DCMAKE_BUILD_TYPE=Release -DALSOFT_EXAMPLES=OFF)
	case "${PLATFORM}" in
	windows-*-*)
		download "openal-soft-${OPENAL_VERSION}-bin.zip" "https://openal-soft.org/openal-binaries/openal-soft-${OPENAL_VERSION}-bin.zip" openal
		cd "openal-soft-${OPENAL_VERSION}-bin"
		cp -r "include/AL" "${PREFIX}/include"
		case "${PLATFORM}" in
		windows-i686-*)
			cp "libs/Win32/libOpenAL32.dll.a" "${PREFIX}/lib"
			cp "bin/Win32/soft_oal.dll" "${PREFIX}/bin/OpenAL32.dll"
			;;
		windows-amd64-*)
			cp "libs/Win64/libOpenAL32.dll.a" "${PREFIX}/lib"
			cp "bin/Win64/soft_oal.dll" "${PREFIX}/bin/OpenAL32.dll"
			;;
		esac
		;;
	macos-*-*)
		download "openal-soft-${OPENAL_VERSION}.tar.bz2" "https://openal-soft.org/openal-releases/openal-soft-${OPENAL_VERSION}.tar.bz2" openal
		cd "openal-soft-${OPENAL_VERSION}"
		"${openal_cmake_call[@]}"
		make
		make install
		install_name_tool -id "@rpath/libopenal.${OPENAL_VERSION}.dylib" "${PREFIX}/lib/libopenal.${OPENAL_VERSION}.dylib"
		;;
	linux-*-*)
		download "openal-soft-${OPENAL_VERSION}.tar.bz2" "https://openal-soft.org/openal-releases/openal-soft-${OPENAL_VERSION}.tar.bz2" openal
		cd "openal-soft-${OPENAL_VERSION}"
		"${openal_cmake_call[@]}" -DLIBTYPE=STATIC 
		make
		make install
		;;
	*)
		echo "Unsupported platform for OpenAL"
		exit 1
		;;
	esac
}

# Build Ogg
build_ogg() {
	download "libogg-${OGG_VERSION}.tar.gz" "https://downloads.xiph.org/releases/ogg/libogg-${OGG_VERSION}.tar.gz" ogg
	cd "libogg-${OGG_VERSION}"
	# This header breaks the vorbis and opusfile Mac builds
	cat <(echo '#include <stdint.h>') include/ogg/os_types.h > os_types.tmp
	mv os_types.tmp include/ogg/os_types.h
	# The user-provided CFLAGS doesn't drop the default -O2
	./configure --host="${HOST}" --prefix="${PREFIX}" "${CONFIGURE_SHARED[@]}"
	make
	make install
}

# Build Vorbis
build_vorbis() {
	download "libvorbis-${VORBIS_VERSION}.tar.gz" "https://downloads.xiph.org/releases/vorbis/libvorbis-${VORBIS_VERSION}.tar.gz" vorbis
	cd "libvorbis-${VORBIS_VERSION}"
	# The user-provided CFLAGS doesn't drop the default -O3
	./configure --host="${HOST}" --prefix="${PREFIX}" "${CONFIGURE_SHARED[@]}" --disable-examples
	make
	make install
}

# Build Opus
build_opus() {
	download "opus-${OPUS_VERSION}.tar.gz" "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" opus
	cd "opus-${OPUS_VERSION}"
	# The default -O2 is dropped when there's user-provided CFLAGS.
	case "${PLATFORM}" in
	windows-*-*)
		# With MinGW _FORTIFY_SOURCE (added by configure) can only by used with -fstack-protector enabled.
		CFLAGS="${CFLAGS} -O2 -D_FORTIFY_SOURCE=0" ./configure --host="${HOST}" --prefix="${PREFIX}" "${CONFIGURE_SHARED[@]}"
		;;
	*)
		CFLAGS="${CFLAGS} -O2" ./configure --host="${HOST}" --prefix="${PREFIX}" "${CONFIGURE_SHARED[@]}"
		;;
	esac
	make
	make install
}

# Build OpusFile
build_opusfile() {
	download "opusfile-${OPUSFILE_VERSION}.tar.gz" "https://downloads.xiph.org/releases/opus/opusfile-${OPUSFILE_VERSION}.tar.gz" opusfile
	cd "opusfile-${OPUSFILE_VERSION}"
	# The default -O2 is dropped when there's user-provided CFLAGS.
	CFLAGS="${CFLAGS} -O2" ./configure --host="${HOST}" --prefix="${PREFIX}" "${CONFIGURE_SHARED[@]}" --disable-http
	make
	make install
}


# Build Lua
build_lua() {
	download "lua-${LUA_VERSION}.tar.gz" "https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz" lua
	cd "lua-${LUA_VERSION}"
	case "${PLATFORM}" in
	windows-*-*)
		local LUA_PLATFORM=mingw
		;;
	macos-*-*)
		local LUA_PLATFORM=macosx
		;;
	linux-*-*)
		local LUA_PLATFORM=linux
		;;
	*)
		echo "Unsupported platform for Lua"
		exit 1
		;;
	esac
	make "${LUA_PLATFORM}" CC="${CC}" AR="${AR} rcu" RANLIB="${RANLIB}" MYCFLAGS="${CFLAGS}" MYLDFLAGS="${LDFLAGS}"
	case "${PLATFORM}" in
	windows-*-mingw)
		make install TO_BIN="lua.exe luac.exe" TO_LIB="liblua.a" INSTALL_TOP="${PREFIX}"
		;;
	windows-*-msvc)
		make install TO_BIN="lua.exe luac.exe lua54.dll" TO_LIB="liblua.a" INSTALL_TOP="${PREFIX}"
		touch "${PREFIX}/lib/lua54.dll.a"
		;;
	*)
		make install INSTALL_TOP="${PREFIX}"
		;;
	esac
}

# Build ncurses
build_ncurses() {
	download "ncurses-${NCURSES_VERSION}.tar.gz" "https://ftp.gnu.org/pub/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz" ncurses
	cd "ncurses-${NCURSES_VERSION}"
	# The default -O2 is dropped when there's user-provided CFLAGS.
	# Configure terminfo search dirs based on the ones used in Debian. By default it will only look in (only) the install directory.
	CFLAGS="${CFLAGS} -O2" ./configure --host="${HOST}" --prefix="${PREFIX}" --enable-widec "${CONFIGURE_SHARED[@]}" --with-terminfo-dirs=/etc/terminfo:/lib/terminfo --with-default-terminfo-dir=/usr/share/terminfo
	make
	make install
}

# "Builds" (downloads) the WASI SDK
build_wasisdk() {
	case "${PLATFORM}" in
	windows-*-*)
		local WASISDK_PLATFORM=mingw
		;;
	macos-*-*)
		local WASISDK_PLATFORM=macos
		;;
	linux-*-*)
		local WASISDK_PLATFORM=linux
		;;
	esac
	case "${PLATFORM}" in
	*-amd64-*)
		;;
	*)
		echo "wasi doesn't have release for ${PLATFORM}"
		exit 1
		;;
	esac
	local WASISDK_VERSION_MAJOR="$(echo "${WASISDK_VERSION}" | cut -f1 -d'.')"
	download "wasi-sdk_${WASISDK_PLATFORM}.tar.gz" "https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASISDK_VERSION_MAJOR}/wasi-sdk-${WASISDK_VERSION}-${WASISDK_PLATFORM}.tar.gz" wasisdk
	cp -r "wasi-sdk-${WASISDK_VERSION}" "${PREFIX}/wasi-sdk"
}

# "Builds" (downloads) wasmtime
build_wasmtime() {
	case "${PLATFORM}" in
	windows-*-*)
		local WASMTIME_PLATFORM=windows
		local ARCHIVE_EXT=zip
		;;
	macos-*-*)
		local WASMTIME_PLATFORM=macos
		local ARCHIVE_EXT=tar.xz
		;;
	linux-*-*)
		local WASMTIME_PLATFORM=linux
		local ARCHIVE_EXT=tar.xz
		;;
	esac
	case "${PLATFORM}" in
	*-amd64-*)
		local WASMTIME_ARCH=x86_64
		;;
	linux-arm64-*|macos-arm64-*)
		local WASMTIME_ARCH=aarch64
		;;
	*)
		echo "wasmtime doesn't have release for ${PLATFORM}"
		exit 1
		;;
	esac
	local folder_name="wasmtime-v${WASMTIME_VERSION}-${WASMTIME_ARCH}-${WASMTIME_PLATFORM}-c-api"
	local archive_name="${folder_name}.${ARCHIVE_EXT}"
	download "${archive_name}" "https://github.com/bytecodealliance/wasmtime/releases/download/v${WASMTIME_VERSION}/${archive_name}" wasmtime
	cd "${folder_name}"
	cp -r include/* "${PREFIX}/include"
	cp -r lib/* "${PREFIX}/lib"
}

# Build the NaCl SDK
build_naclsdk() {
	case "${PLATFORM}" in
	windows-*-*)
		local NACLSDK_PLATFORM=win
		local EXE=.exe
		local TAR_EXT=cygtar
		;;
	macos-*-*)
		local NACLSDK_PLATFORM=mac
		local EXE=
		local TAR_EXT=tar
		;;
	linux-*-*)
		local NACLSDK_PLATFORM=linux
		local EXE=
		local TAR_EXT=tar
		;;
	esac
	case "${PLATFORM}" in
	*-i686-*)
		local NACLSDK_ARCH=x86_32
		local DAEMON_ARCH=i686
		;;
	*-amd64-*)
		local NACLSDK_ARCH=x86_64
		local DAEMON_ARCH=amd64
		;;
	*-armhf-*|linux-arm64-*)
		local NACLSDK_ARCH=arm
		local DAEMON_ARCH=armhf
		;;
	esac
	download "naclsdk_${NACLSDK_PLATFORM}-${NACLSDK_VERSION}.${TAR_EXT}.bz2" "https://storage.googleapis.com/nativeclient-mirror/nacl/nacl_sdk/${NACLSDK_VERSION}/naclsdk_${NACLSDK_PLATFORM}.tar.bz2" naclsdk
	cp pepper_*"/tools/sel_ldr_${NACLSDK_ARCH}${EXE}" "${PREFIX}/nacl_loader${EXE}"
	cp pepper_*"/tools/irt_core_${NACLSDK_ARCH}.nexe" "${PREFIX}/irt_core-${DAEMON_ARCH}.nexe"
	case "${PLATFORM}" in
	windows-i686-*|*-amd64-*)
		cp pepper_*"/toolchain/${NACLSDK_PLATFORM}_x86_newlib/bin/x86_64-nacl-gdb${EXE}" "${PREFIX}/nacl-gdb${EXE}"

		rm -rf "${PREFIX}/pnacl"

		patch -d pepper_*"/toolchain/${NACLSDK_PLATFORM}_pnacl/bin/pydir" \
			-p1 < "${SCRIPT_DIR}/naclsdk-pydir-python3.patch" >/dev/null

		cp -a pepper_*"/toolchain/${NACLSDK_PLATFORM}_pnacl" "${PREFIX}/pnacl"
		rm -rf "${PREFIX}/pnacl/bin/"{i686,x86_64}-nacl-*
		rm -rf "${PREFIX}/pnacl/arm-nacl"
		rm -rf "${PREFIX}/pnacl/arm_bc-nacl"
		rm -rf "${PREFIX}/pnacl/docs"
		rm -rf "${PREFIX}/pnacl/i686_bc-nacl"
		rm -rf "${PREFIX}/pnacl/include"
		rm -rf "${PREFIX}/pnacl/x86_64-nacl"
		rm -rf "${PREFIX}/pnacl/x86_64_bc-nacl"
	esac
	case "${PLATFORM}" in
	windows-i686-*)
		cp pepper_*"/tools/sel_ldr_x86_64.exe" "${PREFIX}/nacl_loader-amd64.exe"
		cp pepper_*"/tools/irt_core_x86_64.nexe" "${PREFIX}/irt_core-amd64.nexe"
		;;
	linux-amd64-*|linux-i686-*)
		cp pepper_*"/tools/nacl_helper_bootstrap_${NACLSDK_ARCH}" "${PREFIX}/nacl_helper_bootstrap"
		# Fix permissions on a few files which deny access to non-owner
		chmod 644 "${PREFIX}/irt_core-${DAEMON_ARCH}.nexe"
		chmod 755 "${PREFIX}/nacl_helper_bootstrap" "${PREFIX}/nacl_loader"
		;;
	linux-armhf-*|linux-arm64-*)
		cp pepper_*"/tools/nacl_helper_bootstrap_arm" "${PREFIX}/nacl_helper_bootstrap"
		# Fix permissions on a few files which deny access to non-owner
		chmod 644 "${PREFIX}/irt_core-${DAEMON_ARCH}.nexe"
		chmod 755 "${PREFIX}/nacl_helper_bootstrap" "${PREFIX}/nacl_loader"
		;;
	esac
	case "${PLATFORM}" in
	linux-arm64-*)
		mkdir -p "${PREFIX}/lib-armhf"
		cp -a pepper_*"/tools/lib/arm_trusted/lib/." "${PREFIX}/lib-armhf/."
		# Copy the library loader instead of renaming it because there may still be some
		# references to ld-linux-armhf.so.3 in binaries.
		cp "${PREFIX}/lib-armhf/ld-linux-armhf.so.3" "${PREFIX}/lib-armhf/ld-linux-armhf"
		# We can't use patchelf or 'nacl_helper_bootstrap nacl_loader' will complain:
		#   bootstrap_helper: nacl_loader: ELF file has unreasonable e_phnum=13
		sed -e 's|/lib/ld-linux-armhf.so.3|lib-armhf/ld-linux-armhf|' -i "${PREFIX}/nacl_loader"
		;;
	esac
}

build_naclports() {
	download "naclports-${NACLSDK_VERSION}.tar.bz2" "https://storage.googleapis.com/nativeclient-mirror/nacl/nacl_sdk/${NACLSDK_VERSION}/naclports.tar.bz2" naclports
	mkdir -p "${PREFIX}/pnacl_deps/"{include,lib}
	cp pepper_*"/ports/include/"{lauxlib.h,lua.h,lua.hpp,luaconf.h,lualib.h} "${PREFIX}/pnacl_deps/include"
	cp -a pepper_*"/ports/include/freetype2" "${PREFIX}/pnacl_deps/include"
	cp pepper_*"/ports/lib/newlib_pnacl/Release/"{liblua.a,libfreetype.a,libpng16.a} "${PREFIX}/pnacl_deps/lib"
}

# The import libraries generated by MinGW seem to have issues, so we use LLVM's version instead.
# So LLVM must be installed, e.g. 'sudo apt install llvm'
build_genlib() {
	case "${PLATFORM}" in
	windows-*-msvc)
		mkdir -p "${PREFIX}/def"
		cd "${PREFIX}/def"
		for DLL_A in $(find "${PREFIX}/lib" -type f -name '*.dll.a'); do
			local DLL="$("${HOST}-dlltool" -I "${DLL_A}" 2> /dev/null || echo $(basename ${DLL_A} .dll.a).dll)"
			local DEF="$(basename ${DLL} .dll).def"
			local LIB="$(basename ${DLL_A} .dll.a).lib"

			case "${PLATFORM}" in
			*-i686-*)
				local MACHINE='i386'
				;;
			*-amd64-*)
				local MACHINE='i386:x86-64'
				;;
			*)
				echo "Unsupported platform for genlib"
				exit 1
				;;
			esac

			# Using gendef from mingw-w64-tools
			gendef "${PREFIX}/bin/${DLL}"

			# Fix some issues with gendef output
			sed -i "s/\(glew.*\)@4@4/\1@4/;s/ov_halfrate_p@0/ov_halfrate_p/" "${DEF}"

			llvm-dlltool -d "${DEF}" -D "$(basename "${DLL}")" -m "${MACHINE}" -l "../lib/${LIB}"
		done
		;;
	*)
		echo "Unsupported platform for genlib"
		exit 1
		;;
	esac
}

# Install all the necessary files to the location expected by CMake
build_install() {
	PKG_PREFIX="${WORK_DIR}/${PKG_BASEDIR}"
	rm -rf "${PKG_PREFIX}"
	rsync -a --link-dest="${PREFIX}" "${PREFIX}/" "${PKG_PREFIX}"

	# Ensure existence in case the selected set of deps didn't have these
	mkdir -p "${PKG_PREFIX}/bin"
	mkdir -p "${PKG_PREFIX}/include"
	mkdir -p "${PKG_PREFIX}/lib"

	# Remove all unneeded files
	rm -rf "${PKG_PREFIX}/man"
	rm -rf "${PKG_PREFIX}/def"
	rm -rf "${PKG_PREFIX}/share"
	rm -rf "${PKG_PREFIX}/lib/pkgconfig"
	find "${PKG_PREFIX}/bin" -not -type d -not -name '*.dll' -execdir rm -f -- {} \;
	find "${PKG_PREFIX}/lib" -name '*.la' -execdir rm -f -- {} \;
	find "${PKG_PREFIX}/lib" -name '*.dll.a' -execdir bash -c 'rm -f -- "$(basename "{}" .dll.a).a"' \;
	find "${PKG_PREFIX}/lib" -name '*.dylib' -execdir bash -c 'rm -f -- "$(basename "{}" .dylib).a"' \;

	# Strip libraries
	case "${PLATFORM}" in
	windows-*-mingw)
		find "${PKG_PREFIX}/bin" -name '*.dll' -execdir "${HOST}-strip" --strip-unneeded -- {} \;
		find "${PKG_PREFIX}/lib" -name '*.a' -execdir "${HOST}-strip" --strip-unneeded -- {} \;
		;;
	windows-*-msvc)
		find "${PKG_PREFIX}/bin" -name '*.dll' -execdir "${HOST}-strip" --strip-unneeded -- {} \;
		find "${PKG_PREFIX}/lib" -name '*.a' -execdir rm -f -- {} \;
		find "${PKG_PREFIX}/lib" -name '*.exp' -execdir rm -f -- {} \;
		;;
	esac

	# Remove empty directories
	find "${PKG_PREFIX}/" -mindepth 1 -type d -empty -delete
}

# Create a redistributable package for the dependencies
build_package() {
	cd "${WORK_DIR}"
	rm -f "${PKG_BASEDIR}.tar.xz"
	XZ_OPT='-9' tar cvJf "${PKG_BASEDIR}.tar.xz" "${PKG_BASEDIR}"
}

build_wipe() {
	rm -rf "${BUILD_BASEDIR}/" "${PKG_BASEDIR}/" "${PKG_BASEDIR}.tar.xz"
}

# Common setup code
common_setup() {
	HOST="${2}"
	"common_setup_${1}"
	common_setup_arch
	WORK_DIR="${PWD}"
	SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
	DOWNLOAD_DIR="${WORK_DIR}/download_cache"
	PKG_BASEDIR="${PLATFORM}_${DEPS_VERSION}"
	BUILD_BASEDIR="build-${PKG_BASEDIR}"
	BUILD_DIR="${WORK_DIR}/${BUILD_BASEDIR}"
	PREFIX="${BUILD_DIR}/prefix"
	PATH="${PREFIX}/bin:${PATH}"
	PKG_CONFIG="pkg-config"
	PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"
	CPPFLAGS+=" -I${PREFIX}/include"
	LDFLAGS+=" -L${PREFIX}/lib"
	mkdir -p "${DOWNLOAD_DIR}"
	mkdir -p "${PREFIX}/bin"
	mkdir -p "${PREFIX}/include"
	mkdir -p "${PREFIX}/lib"
	export CC CXX LD AR RANLIB PKG_CONFIG PKG_CONFIG_PATH PATH CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
}

common_setup_arch () {
	case "${PLATFORM}" in
	*-amd64-*)
		CLFLAGS+=' -march=x86-64 -mcx16'
		CXXFLAGS+=' -march=x86-64 -mcx16'
		;;
	*-i686-*)
		CFLAGS+=' -march=i686 -msse2 -mfpmath=sse'
		CXXFLAGS+=' -march=i686 -msse2 -mfpmath=sse'
		;;
	*-arm64-*)
		CFLAGS+=' -march=armv8-a'
		CXXFLAGS+=' -march=armv8-a'
		;;
	*-armhf-*)
		CFLAGS+=' -march=armv7-a -mfpu=neon'
		CXXFLAGS+=' -march=armv7-a -mfpu=neon'
		;;
	*)
		echo "Unsupported platform"
		exit 1
		;;
	esac
}

# -D__USE_MINGW_ANSI_STDIO=0 instructs MinGW to *not* use its own implementation
# of printf and instead use the system one. It's bad when MinGW uses its own
# implementation because this can cause extra DLL dependencies.
# The separate implementation exists because Microsoft's implementation at some
# point did not implement certain printf specifiers, in particular %lld (long long).
# Lua does use this one, which results in compiler warnings. But this is OK because
# the Windows build of Lua is only used in developer gamelogic builds, and Microsoft
# supports %lld since Visual Studio 2013.
common_setup_msvc() {
	CONFIGURE_SHARED=(--enable-shared --disable-static)
	# Libtool bug prevents -static-libgcc from being set in LDFLAGS
	CC="${HOST}-gcc -static-libgcc"
	CXX="${HOST}-g++ -static-libgcc"
	LD="${HOST}-ld"
	AR="${HOST}-ar"
	RANLIB="${HOST}-ranlib"
	CFLAGS+=' -D__USE_MINGW_ANSI_STDIO=0'
}

common_setup_mingw() {
	CC="${HOST}-gcc"
	CXX="${HOST}-g++"
	LD="${HOST}-ld"
	AR="${HOST}-ar"
	RANLIB="${HOST}-ranlib"
	CFLAGS+=' -D__USE_MINGW_ANSI_STDIO=0'
}

common_setup_macos() {
	CC='clang'
	CXX='clang++'
	CFLAGS+=" -arch ${MACOS_ARCH}"
	CXXFLAGS+=" -arch ${MACOS_ARCH}"
	LDFLAGS+=" -arch ${MACOS_ARCH}"
	export CMAKE_OSX_ARCHITECTURES="${MACOS_ARCH}"
}

common_setup_linux() {
	CC="${HOST/-unknown-/-}-gcc"
	CXX="${HOST/-unknown-/-}-g++"
	CFLAGS+=' -fPIC'
	CXXFLAGS+=' -fPIC'
}

# Set up environment for 32-bit i686 Windows for Visual Studio (compile all as .dll)
setup_windows-i686-msvc() {
	BITNESS=32
	CFLAGS+=' -mpreferred-stack-boundary=2'
	CXXFLAGS+=' -mpreferred-stack-boundary=2'
	common_setup msvc i686-w64-mingw32
}

# Set up environment for 64-bit amd64 Windows for Visual Studio (compile all as .dll)
setup_windows-amd64-msvc() {
	BITNESS=64
	common_setup msvc x86_64-w64-mingw32
}

# Set up environment for 32-bit i686 Windows for MinGW (compile all as .a)
setup_windows-i686-mingw() {
	BITNESS=32
	common_setup mingw i686-w64-mingw32
}

# Set up environment for 64-bit amd64 Windows for MinGW (compile all as .a)
setup_windows-amd64-mingw() {
	BITNESS=64
	common_setup mingw x86_64-w64-mingw32
}

# Set up environment for 64-bit amd64 macOS
setup_macos-amd64-default() {
	MACOS_ARCH=x86_64
	export MACOSX_DEPLOYMENT_TARGET=10.9 # works with CMake
	common_setup macos x86_64-apple-darwin11
}

# Set up environment for 32-bit i686 Linux
setup_linux-i686-default() {
	common_setup linux i686-unknown-linux-gnu
}

# Set up environment for 64-bit amd64 Linux
setup_linux-amd64-default() {
	common_setup linux x86_64-unknown-linux-gnu
}

# Set up environment for 32-bit armhf Linux
setup_linux-armhf-default() {
	common_setup linux arm-unknown-linux-gnueabihf
}

# Set up environment for 64-bit arm Linux
setup_linux-arm64-default() {
	common_setup linux aarch64-unknown-linux-gnu
}

# Usage
if [ "${#}" -lt "2" ]; then
	cat <<-EOF
	usage: ${0} <platform> <package[s]...>

	Script to build dependencies for platforms which do not provide them

	Platforms:
	  windows-i686-msvc windows-amd64-msvc windows-i686-mingw windows-amd64-mingw macos-amd64-default linux-amd64-default linux-i686-default linux-arm64-default linux-armhf-default

	Packages:
	  pkgconfig nasm zlib gmp nettle curl sdl2 glew png jpeg webp freetype openal ogg vorbis opus opusfile lua naclsdk naclports wasisdk wasmtime

	Virtual packages:
	  install - create a stripped down version of the built packages that CMake can use
	  package - create a zip/tarball of the dependencies so they can be distributed
	  wipe - remove products of build process, excepting download cache but INCLUDING installed files. Must be last

	Packages required for each platform:

	Native Windows compile:
	  pkgconfig zlib gmp nettle curl sdl2 glew png jpeg webp freetype openal ogg vorbis opus opusfile lua naclsdk naclports genlib

	Linux to Windows cross-compile:
	  zlib gmp nettle curl sdl2 glew png jpeg webp freetype openal ogg vorbis opus opusfile lua naclsdk naclports

	Native macOS compile:
	  pkgconfig nasm gmp nettle sdl2 glew png jpeg webp freetype openal ogg vorbis opus opusfile lua naclsdk naclports

	Linux amd64 and i686 native compile:
	  naclsdk naclports (and possibly others depending on what packages your distribution provides)

	Linux arm64 and armhf native compile:
	  naclsdk (and possibly others depending on what packages your distribution provides)

	EOF
	exit 1
fi

# Enable parallel build
export MAKEFLAGS="-j`nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null || echo 1`"

# Setup platform
PLATFORM="${1}"; shift
"setup_${PLATFORM}"

# Build packages
for pkg in "${@}"; do
	cd "${WORK_DIR}"
	"build_${pkg}"
done
