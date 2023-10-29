# Create a builder image with the compilers, etc. needed
FROM alpine:3.18.4 AS build-env

# Install all the required packages for building. This list is probably
# longer than necessary.
RUN echo "== Install Git/CA certificates ==" && \
    apk add \
        git \
        ca-certificates

RUN echo "== Install Core dependencies ==" && \
    apk add \
        alsa-lib-dev \
        autoconf \
        automake \
        binutils \
        bison \
        cairo-dev \
        clang \
        clang-dev \
        cmake  \
        curl \
        dbus-dev \
        dbus-glib \
        dbus-glib-dev \
        diffutils \
        elfutils-dev  \
        file \
        flex \
        fontconfig-dev \
        gawk \
        gcc \
        g++ \
        libc-dev \
        libc6-compat \
        gettext \
        glib \
        gobject-introspection-dev \
        harfbuzz-dev \
        linux-headers \
        intltool \
        libatomic_ops \
        libcap-dev \
        libffi \
        libffi-dev \
        libgudev-dev \
        libjpeg-turbo-dev \
        libltdl \
        libpng-dev \
        librsvg-dev \
        tiff-dev \
        libusb-dev \
        libwebp-dev \
        libxml2-dev \
        make \
        meson \
        newt \
        nss-dev \
        openldap \
        openssl-dev \
        linux-pam-dev \
        pango-dev \
        patch \
        perl-xml-parser \
        polkit-dev \
        python3-dev \
        py3-mako \
        py3-markupsafe \
        rpm \
        sed \
        sqlite-dev \
        elogind-dev \
        tar \
        unzip \
        vala \
        vala-lint

RUN echo "== Install UI dependencies ==" && \
        apk add \
            freerdp-dev \
            libdrm-dev \
            libepoxy-dev \
            libevdev-dev \
            libinput-dev \
            libpciaccess-dev \
            libsm-dev \
            libsndfile-dev \
            libxcursor \
            libxcursor-dev \
            libxdamage-dev \
            libxfont2-dev \
            libxi-dev \
            libxkbcommon-dev \
            libxkbfile-dev \
            libxrandr-dev \
            libxshmfence-dev \
            libxtst-dev \
            libxxf86vm-dev \
            wayland-dev \
            wayland-protocols-dev \
            xkbcomp-dev \
            xkeyboard-config-dev \
            xorg-server-dev \
            util-macros

# Create an image with builds of FreeRDP and Weston
FROM build-env AS dev

ARG WSLG_VERSION="<current>"
ARG WSLG_ARCH="x86_64"

WORKDIR /work
RUN echo "WSLg (" ${WSLG_ARCH} "):" ${WSLG_VERSION} > /work/versions.txt

RUN echo "alpine:" `cat /etc/os-release | head -2 | tail -1` >> /work/versions.txt

ENV DESTDIR=/work/build
ENV PREFIX=/usr
ENV PKG_CONFIG_PATH=${DESTDIR}${PREFIX}/lib/pkgconfig:${DESTDIR}${PREFIX}/lib/${WSLG_ARCH}-linux-musl/pkgconfig:${DESTDIR}${PREFIX}/share/pkgconfig
ENV C_INCLUDE_PATH=${DESTDIR}${PREFIX}/include/winpr2:${DESTDIR}${PREFIX}/include/wsl/stubs:${DESTDIR}${PREFIX}/include
ENV CPLUS_INCLUDE_PATH=${C_INCLUDE_PATH}
ENV LIBRARY_PATH=${DESTDIR}${PREFIX}/lib
ENV LD_LIBRARY_PATH=${LIBRARY_PATH}
ENV CC=/usr/bin/gcc
ENV CXX=/usr/bin/g++

# Build DirectX-Headers
COPY vendor/DirectX-Headers-1.0 /work/vendor/DirectX-Headers-1.0
WORKDIR /work/vendor/DirectX-Headers-1.0
RUN /usr/bin/meson --prefix=${PREFIX} build \
        --buildtype='debugoptimized' \
        -Dbuild-test=false && \
    ninja -C build -j8 install && \
    echo 'DirectX-Headers:' `git --git-dir=/work/vendor/DirectX-Headers-1.0/.git rev-parse --verify HEAD` >> /work/versions.txt

# Build rdpapplist RDP virtual channel plugin
COPY rdpapplist /work/rdpapplist
WORKDIR /work/rdpapplist
RUN /usr/bin/meson --prefix=${PREFIX} build \
        --buildtype='debugoptimized' && \
    ninja -C build -j8 install

# Build WSLGd Daemon
ENV CC=/usr/bin/clang
ENV CXX=/usr/bin/clang++

COPY WSLGd /work/WSLGd
WORKDIR /work/WSLGd
RUN /usr/bin/meson --prefix=${PREFIX} build \
        --buildtype='debugoptimized' && \
    ninja -C build -j8 install

########################################################################
########################################################################

## Create the distro image with just what's needed at runtime

FROM alpine:3.18.4 AS runtime

RUN echo "== Install Core/UI Runtime Dependencies ==" && \
    apk add \
            weston \
            mesa \
            freerdp \
            pulseaudio \
            xwayland \
            xauth \
            xinit \
            xrandr \
            xapp \
            xdg-utils \
            xdg-user-dirs \
            xorg-server \
            xtrans \
            tzdata \
            procps \
            nftables \
            iproute2 \
            libinput \
            dbus \
            dbus-glib \
            libjpeg \
            rpm \
            chrony \
            e2fsprogs \
            wayland-protocols \
            dhcpcd \
            nano \
            sed \
            font-freefont \
            librsvg \
            libxkbcommon \
            util-linux

# Clear the cache to make the image smaller
RUN apk cache clean

# Remove extra doc
RUN rm -rf /usr/lib/python3.7 /usr/share/gtk-doc

# Create wslg user.
RUN adduser -u 1000 --disabled-password --home /home/wslg wslg && \
    mkdir /home/wslg/.config && \
    chown wslg /home/wslg/.config

RUN ln -s /etc /usr/etc
# Copy config files.
COPY config/wsl.conf /etc/wsl.conf
COPY config/weston.ini /home/wslg/.config/weston.ini
COPY config/local.conf /etc/fonts/local.conf

# Copy default icon file.
COPY resources/linux.png /usr/share/icons/wsl/linux.png

# Copy the built artifacts from the build stage.
COPY --from=dev /work/build/usr/ /usr/
RUN cp -pfru /usr/bin/* /bin && \
cp -pfru /usr/sbin/* /sbin && \
rm -rf /usr/bin/ && rm -rf /usr/sbin/ && \
ln -s /sbin /usr/sbin && \
ln -s /bin /usr/bin
# Append WSLg setttings to pulseaudio.
COPY config/default_wslg.pa /etc/pulse/default_wslg.pa
RUN cat /etc/pulse/default_wslg.pa >> /etc/pulse/default.pa
RUN rm /etc/pulse/default_wslg.pa

COPY --from=dev /work/versions.txt /etc/versions.txt

CMD /usr/bin/WSLGd
