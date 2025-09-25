# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit autotools xdg

DESCRIPTION="Portable Nintendo Entertainment System emulator written in C++ (with framecounter and input display)"
HOMEPAGE="https://github.com/108Pi/nestopiaRTA"
SRC_URI="
	https://github.com/108Pi/nestopiaRTA/archive/refs/tags/${PV}.tar.gz
		-> ${P}.tar.gz
"

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~amd64 ~x86"
IUSE="doc"
S="${WORKDIR}/nestopiaRTA-${PV}"

RDEPEND="
	app-arch/libarchive:=
	media-libs/libepoxy
	media-libs/libsamplerate
	media-libs/libsdl2[joystick,sound]
	sys-libs/zlib:=
	>=x11-libs/fltk-1.4:1=[opengl]
"
DEPEND="${RDEPEND}
	!games-emulation/nestopia"
BDEPEND="
	dev-build/autoconf-archive
	virtual/pkgconfig
"

src_prepare() {
	default

	eautoreconf
}

src_configure() {
	econf $(use_enable doc)
}
