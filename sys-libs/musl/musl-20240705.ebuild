# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit crossdev flag-o-matic toolchain-funcs prefix

DESCRIPTION="Light, fast and, simple C library focused on standards-conformance and safety"
HOMEPAGE="https://musl.libc.org"

MUSL_COMMIT="dd1e63c3638d5f9afb857fccf6ce1415ca5f1b8b"
MIMALLOC_VER="2.1.7"
GETENT_COMMIT="93a08815f8598db442d8b766b463d0150ed8e2ab"
GETENT_FILE="musl-getent-${GETENT_COMMIT}.c"

SRC_URI="
	https://git.musl-libc.org/cgit/musl/snapshot/musl-${MUSL_COMMIT}.tar.gz
	https://github.com/microsoft/mimalloc/archive/refs/tags/v${MIMALLOC_VER}.tar.gz
	https://dev.gentoo.org/~blueness/musl-misc/getconf.c
	https://gitlab.alpinelinux.org/alpine/aports/-/raw/${GETENT_COMMIT}/main/musl/getent.c -> ${GETENT_FILE}
	https://dev.gentoo.org/~blueness/musl-misc/iconv.c
"

KEYWORDS="-* ~amd64"
S="${WORKDIR}/musl-${MUSL_COMMIT}"

LICENSE="MIT LGPL-2 GPL-2"
SLOT="0"
IUSE="crypt headers-only split-usr"

QA_SONAME="usr/lib/libc.so"
QA_DT_NEEDED="usr/lib/libc.so"
# bug #830213
QA_PRESTRIPPED="usr/lib/crtn.o"

# We want crypt on by default for this as sys-libs/libxcrypt isn't (yet?)
# built as part as crossdev. Also, elide the blockers when in cross-*,
# as it doesn't make sense to block the normal CBUILD libxcrypt at all
# there when we're installing into /usr/${CHOST} anyway.
if is_crosspkg ; then
	IUSE="${IUSE/crypt/+crypt}"
else
	RDEPEND="crypt? ( !sys-libs/libxcrypt[system] )"
	PDEPEND="!crypt? ( sys-libs/libxcrypt[system] )"
fi

PATCHES=(
	"${FILESDIR}"/0001-implement-necessary-bits-for-musl-integration.patch
	"${FILESDIR}"/0001-plumb-in-support-for-externally-provided-allocator-l.patch
	"${FILESDIR}"/default-locpath.patch
	"${FILESDIR}"/fix-bind-textdomain-codeset.patch
	"${FILESDIR}"/iconv-001.patch
	"${FILESDIR}"/iconv-002.patch
	"${FILESDIR}"/libcc-compiler-rt.patch
	"${FILESDIR}"/llvm18.patch
	"${FILESDIR}"/loongarch-tlsdesc.patch
	"${FILESDIR}"/lto.patch
	"${FILESDIR}"/memcpy.patch
	"${FILESDIR}"/mimalloc-errno.patch
	"${FILESDIR}"/mimalloc-tweak-options.patch
	"${FILESDIR}"/plt.patch
	"${FILESDIR}"/ppc-alt.patch
	"${FILESDIR}"/riscv-hwprobe.patch
)

just_headers() {
	use headers-only && target_is_not_host
}

pkg_setup() {
	if [[ ${CTARGET} == ${CHOST} ]] ; then
		case ${CHOST} in
			*-musl*) ;;
			*) die "Use sys-devel/crossdev to build a musl toolchain" ;;
		esac
	fi

	# Fix for bug #667126, copied from glibc ebuild:
	# make sure host make.conf doesn't pollute us
	if target_is_not_host || tc-is-cross-compiler ; then
		CHOST=${CTARGET} strip-unsupported-flags
	fi
}

src_unpack() {
	default

	cp -r "${WORKDIR}"/mimalloc-${MIMALLOC_VER} \
		"${WORKDIR}"/musl-${MUSL_COMMIT}/mimalloc || die
}

src_prepare() {
	default

	mkdir "${WORKDIR}"/misc || die
	cp "${DISTDIR}"/getconf.c "${WORKDIR}"/misc/getconf.c || die
	cp "${DISTDIR}/${GETENT_FILE}" "${WORKDIR}"/misc/getent.c || die
	cp "${DISTDIR}"/iconv.c "${WORKDIR}"/misc/iconv.c || die
	cp "${FILESDIR}"/mimalloc.c \
		"${S}"/mimalloc/src/mimalloc.c || die
	cp "${FILESDIR}"/mimalloc-verify-syms.sh \
		"${S}"/mimalloc-verify-syms.sh || die
	rm "${S}"/src/string/x86_64/memcpy.s || die
}

src_configure() {
	strip-flags
	tc-getCC ${CTARGET}

	just_headers && export CC=true

	local libgcc=$($(tc-getCC) ${CFLAGS} ${CPPFLAGS} ${LDFLAGS} -print-libgcc-file-name)

	local sysroot
	target_is_not_host && sysroot=/usr/${CTARGET}
	./configure \
		LIBCC=${libgcc} \
		--target=${CTARGET} \
		--prefix="${EPREFIX}${sysroot}/usr" \
		--syslibdir="${EPREFIX}${sysroot}/lib" \
		--with-malloc=external \
		--disable-gcc-wrapper || die
}

src_compile() {

	emake obj/include/bits/alltypes.h
	just_headers && return 0

	emake \
		EXTRA_OBJ="${S}/src/malloc/external/mimalloc.o"

	if ! is_crosspkg ; then
		emake -C "${T}" getconf getent iconv \
			CC="$(tc-getCC)" \
			CFLAGS="${CFLAGS}" \
			CPPFLAGS="${CPPFLAGS}" \
			LDFLAGS="${LDFLAGS}" \
			VPATH="${WORKDIR}/misc"
	fi

	$(tc-getCC) ${CPPFLAGS} ${CFLAGS} -c -o libssp_nonshared.o "${FILESDIR}"/stack_chk_fail_local.c || die
	$(tc-getAR) -rcs libssp_nonshared.a libssp_nonshared.o || die
}

src_install() {
	local target="install"
	just_headers && target="install-headers"
	emake DESTDIR="${D}" ${target}
	just_headers && return 0

	# musl provides ldd via a sym link to its ld.so
	local sysroot=
	target_is_not_host && sysroot=/usr/${CTARGET}
	local ldso=$(basename "${ED}${sysroot}"/lib/ld-musl-*)
	dosym -r "${sysroot}/lib/${ldso}" "${sysroot}/usr/bin/ldd"

	if ! use crypt ; then
		# Allow sys-libs/libxcrypt[system] to provide it instead
		rm "${ED}${sysroot}/usr/include/crypt.h" || die
		rm "${ED}${sysroot}"/usr/*/libcrypt.a || die
	fi

	if ! is_crosspkg ; then
		# Fish out of config:
		#   ARCH = ...
		#   SUBARCH = ...
		# and print $(ARCH)$(SUBARCH).
		local arch=$(awk '{ k[$1] = $3 } END { printf("%s%s", k["ARCH"], k["SUBARCH"]); }' config.mak)

		# The musl build system seems to create a symlink:
		# ${D}/lib/ld-musl-${arch}.so.1 -> /usr/lib/libc.so.1 (absolute)
		# During cross or within prefix, there's no guarantee that the host is
		# using musl so that file may not exist. Use a relative symlink within
		# ${D} instead.
		rm "${ED}"/lib/ld-musl-${arch}.so.1 || die
		if use split-usr; then
			dosym ../usr/lib/libc.so /lib/ld-musl-${arch}.so.1
			# If it's still a dead symlink, OK, we really do need to abort.
			[[ -e "${ED}"/lib/ld-musl-${arch}.so.1 ]] || die
		else
			dosym libc.so /usr/lib/ld-musl-${arch}.so.1
			[[ -e "${ED}"/usr/lib/ld-musl-${arch}.so.1 ]] || die
		fi

		cp "${FILESDIR}"/ldconfig.in-r3 "${T}"/ldconfig.in || die
		sed -e "s|@@ARCH@@|${arch}|" "${T}"/ldconfig.in > "${T}"/ldconfig || die
		eprefixify "${T}"/ldconfig
		into /
		dosbin "${T}"/ldconfig
		into /usr
		dobin "${T}"/getconf
		dobin "${T}"/getent
		dobin "${T}"/iconv
		newenvd - "00musl" <<-EOF
		# 00musl autogenerated by sys-libs/musl ebuild; DO NOT EDIT.
		LDPATH="include ld.so.conf.d/*.conf"
		EOF
	fi

	if target_is_not_host ; then
		into /usr/${CTARGET}
		dolib.a libssp_nonshared.a
	else
		dolib.a libssp_nonshared.a
	fi
}

pkg_preinst() {
	# Nothing to do if just installing headers
	just_headers && return

	# Prepare /etc/ld.so.conf.d/ for files
	mkdir -p "${EROOT}"/etc/ld.so.conf.d
}

pkg_postinst() {
	target_is_not_host && return 0

	[[ -n "${ROOT}" ]] && return 0

	ldconfig || die
}
