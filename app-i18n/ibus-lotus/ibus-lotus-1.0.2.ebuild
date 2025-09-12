# Copyright 1999-2020 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI="8"

MY_PV="${PV/_rc/-RC}"
DESCRIPTION="Vietnamese IME for IBus (fork of ibus-bamboo)"
HOMEPAGE="https://github.com/LotusInputEngine/ibus-lotus"

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/LotusInputEngine/${PN}.git"
else
	SRC_URI="https://github.com/LotusInputEngine/${PN}/archive/v${MY_PV}.tar.gz -> ${P}.tar.gz"
fi

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="-* ~amd64 ~x86"

RDEPEND="app-i18n/ibus
	!app-i18n/ibus-lotus"
DEPEND="${RDEPEND}
	x11-libs/libX11
	x11-libs/libXtst"
BDEPEND="${DEPEND}
	dev-build/make
	dev-lang/go"

src_install() {
	emake DESTDIR="${D}" PREFIX="${EPREFIX}/usr" install
}
