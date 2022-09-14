FROM alpine:3.16.2

COPY chroot/entrypoint.sh /

RUN \
	apk add ifupdown-ng=0.12.1-r0 openrc=0.44.10-r7 \
		alpine-conf fakeroot=1.25.3-r3 \
		openssl libattr=2.5.1-r1 \
		attr=2.5.1-r1 libacl=2.3.1-r0 \
		tar=1.34-r0 pkgconf \
		patch=2.7.6-r7 libgcc=11.2.1_git20220219-r2 \
		libstdc++=11.2.1_git20220219-r2 lzip=1.23-r0 \
		ca-certificates brotli-libs=1.0.9-r6 \
		nghttp2-libs=1.47.0-r0 libcurl \
		curl abuild=3.9.0-r0 \
		binutils libmagic=5.41-r0 \
		file=5.41-r0 libgomp=11.2.1_git20220219-r2 \
		libatomic=11.2.1_git20220219-r2 gmp=6.2.1-r2 \
		isl22=0.22-r0 mpfr4=4.1.0-r0 \
		mpc1=1.2.1-r0 gcc=11.2.1_git20220219-r2 \
		musl-dev=1.2.3-r0 libc-dev=0.7.2-r3 \
		g++=11.2.1_git20220219-r2 make=4.3-r0 \
		fortify-headers=1.1-r1 build-base=0.5-r3 \
		expat=2.4.8-r0 pcre2=10.40-r0 \
		git alpine-sdk=1.0-r1 \
		ncurses-terminfo-base=6.3_p20220521-r0 ncurses-libs=6.3_p20220521-r0 \
		readline=8.1.2-r0 bash=5.1.16-r2 \
		dosfstools=4.2-r1 lddtree=1.26-r2 \
		xz-libs=5.2.5-r1 zstd-libs=1.5.2-r1 \
		kmod=29-r2 kmod-openrc=29-r2 \
		libblkid=2.38-r1 argon2-libs=20190702-r1 \
		device-mapper-libs=2.02.187-r2 json-c=0.16-r0 \
		libuuid=2.38-r1 cryptsetup-libs=2.4.3-r0 \
		kmod-libs=29-r2 mkinitfs \
		grub=2.06-r2 grub-efi=2.06-r2 \
		mtools=4.0.39-r0 lz4-libs=1.9.3-r1 \
		lzo=2.10-r3 squashfs-tools=4.5.1-r0 \
		sudo=1.9.10-r0 blkid=2.38-r1 \
		syslinux=6.04_pre1-r10 libburn=1.5.4-r1 \
		libedit=20210910.3.1-r0 libisofs=1.5.4-r2 \
		libisoburn=1.5.4-r2 xorriso=1.5.4-r2 && \
	adduser build \
		-G abuild \
		-D -s /bin/bash \
		-h /build && \
	echo "%abuild ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/abuild && \
	su build -c "abuild-keygen -a -i -n" && \
	mv /build/.abuild /

VOLUME build
USER build
ENV USER=build

ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "/build/aports/scripts/start.sh" ]
