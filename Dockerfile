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
        alsa-lib \
        alsa-lib-dev  \
        autoconf  \
        automake  \
        binutils  \
        bison  \
        cairo \
        cairo-dev \
        clang  \
        clang-dev  \
        cmake  \
        curl \
        dbus  \
        dbus-dev  \
        dbus-glib  \
        dbus-glib-dev  \
        diffutils  \
        elfutils-dev  \
        file  \
        flex  \
        fontconfig-dev  \
        gawk  \
        gcc  \
        g++ \
        libc-dev  \
        libc6-compat \
        gettext \
        glib \
        gobject-introspection  \
        gobject-introspection-dev  \
        harfbuzz  \
        harfbuzz-dev  \
        linux-headers  \
        intltool \
        libatomic_ops  \
        libcap-dev  \
        libffi  \
        libffi-dev  \
        libgudev  \
        libgudev-dev  \
        libjpeg-turbo  \
        libjpeg-turbo-dev  \
        libltdl  \
        libpng-dev  \
        librsvg-dev \
        tiff  \
        tiff-dev  \
        libusb  \
        libusb-dev  \
        libwebp  \
        libwebp-dev  \
        libxml2 \
        libxml2-dev  \
        make  \
        meson  \
        newt  \
        nss  \
        nss-dev  \
        openldap  \
        openssl-dev  \
        linux-pam-dev  \
        pango  \
        pango-dev  \
        patch  \
        perl-xml-parser \
        polkit-dev  \
        python3 \
        python3-dev \
        py3-mako  \
        py3-markupsafe \
        rpm \
        sed \
        sqlite-dev \
        elogind-dev  \
        tar \
        unzip  \
        vala  \
        vala-devhelp \
        vala-lint \
        libuser

RUN echo "== Install UI dependencies ==" && \
        apk add \
            libdrm-dev \
            libepoxy-dev \
            libevdev \
            libevdev-dev \
            libinput \
            libinput-dev \
            libpciaccess-dev \
            libsm-dev \
            libsndfile \
            libsndfile-dev \
            libxcursor \
            libxcursor-dev \
            libxdamage-dev \
            libxfont2-dev \
            libxi \
            libxi-dev \
            libxkbcommon-dev \
            libxkbfile-dev \
            libxrandr-dev \
            libxshmfence-dev \
            libxtst \
            libxtst-dev \
            libxxf86vm-dev \
            wayland-dev \
            wayland-protocols-dev \
            xkbcomp \
            xkeyboard-config \
            xorg-server-dev \
            util-macros

# Create an image with builds of FreeRDP and Weston
FROM build-env AS dev

ARG WSLG_VERSION="<current>"
ARG WSLG_ARCH="x86_64"
ARG SYSTEMDISTRO_DEBUG_BUILD
ARG FREERDP_VERSION=2

WORKDIR /work
RUN echo "WSLg (" ${WSLG_ARCH} "):" ${WSLG_VERSION} > /work/versions.txt

RUN echo "alpine:" `cat /etc/os-release | head -2 | tail -1` >> /work/versions.txt

#
# Build runtime dependencies.
#

ENV BUILDTYPE=${SYSTEMDISTRO_DEBUG_BUILD:+debug}
ENV BUILDTYPE=${BUILDTYPE:-debugoptimized}
RUN echo "== System distro build type:" ${BUILDTYPE} " =="

ENV BUILDTYPE_NODEBUGSTRIP=${SYSTEMDISTRO_DEBUG_BUILD:+debug}
ENV BUILDTYPE_NODEBUGSTRIP=${BUILDTYPE_NODEBUGSTRIP:-release}
RUN echo "== System distro build type (no debug strip):" ${BUILDTYPE_NODEBUGSTRIP} " =="

# FreeRDP is always built with RelWithDebInfo
ENV BUILDTYPE_FREERDP=${BUILDTYPE_FREERDP:-RelWithDebInfo}
RUN echo "== System distro build type (FreeRDP):" ${BUILDTYPE_FREERDP} " =="

ENV WITH_DEBUG_FREERDP=${SYSTEMDISTRO_DEBUG_BUILD:+ON}
ENV WITH_DEBUG_FREERDP=${WITH_DEBUG_FREERDP:-OFF}
RUN echo "== System distro build type (FreeRDP Debug Options):" ${WITH_DEBUG_FREERDP} " =="

ENV DESTDIR=/work/build
ENV PREFIX=/usr
ENV PKG_CONFIG_PATH=${DESTDIR}${PREFIX}/lib/pkgconfig:${DESTDIR}${PREFIX}/lib/${WSLG_ARCH}-linux-gnu/pkgconfig:${DESTDIR}${PREFIX}/share/pkgconfig
ENV C_INCLUDE_PATH=${DESTDIR}${PREFIX}/include/freerdp${FREERDP_VERSION}:${DESTDIR}${PREFIX}/include/winpr${FREERDP_VERSION}:${DESTDIR}${PREFIX}/include/wsl/stubs:${DESTDIR}${PREFIX}/include
ENV CPLUS_INCLUDE_PATH=${C_INCLUDE_PATH}
ENV LIBRARY_PATH=${DESTDIR}${PREFIX}/lib
ENV LD_LIBRARY_PATH=${LIBRARY_PATH}
ENV CC=/usr/bin/gcc
ENV CXX=/usr/bin/g++

# Setup DebugInfo folder
COPY debuginfo /work/debuginfo
RUN chmod +x /work/debuginfo/gen_debuginfo.sh

# Build DirectX-Headers
COPY vendor/DirectX-Headers-1.0 /work/vendor/DirectX-Headers-1.0
WORKDIR /work/vendor/DirectX-Headers-1.0
RUN /usr/bin/meson --prefix=${PREFIX} build \
        --buildtype=${BUILDTYPE_NODEBUGSTRIP} \
        -Dbuild-test=false && \
    ninja -C build -j8 install && \
    echo 'DirectX-Headers:' `git --git-dir=/work/vendor/DirectX-Headers-1.0/.git rev-parse --verify HEAD` >> /work/versions.txt

# Build mesa with the minimal options we need.
COPY vendor/mesa /work/vendor/mesa
WORKDIR /work/vendor/mesa
RUN /usr/bin/meson --prefix=${PREFIX} build \
        --buildtype=${BUILDTYPE_NODEBUGSTRIP} \
        -Dgallium-drivers=swrast,d3d12 \
        -Dvulkan-drivers= \
        -Dllvm=disabled && \
    ninja -C build -j8 install && \
    echo 'mesa:' `git --git-dir=/work/vendor/mesa/.git rev-parse --verify HEAD` >> /work/versions.txt

# Build PulseAudio
COPY vendor/pulseaudio /work/vendor/pulseaudio
WORKDIR /work/vendor/pulseaudio
RUN /usr/bin/meson --prefix=${PREFIX} build \
        --buildtype=${BUILDTYPE_NODEBUGSTRIP} \
        -Ddatabase=simple \
        -Ddoxygen=false \
        -Dgsettings=disabled \
        -Dtests=false && \
    ninja -C build -j8 install && \
    echo 'pulseaudio:' `git --git-dir=/work/vendor/pulseaudio/.git rev-parse --verify HEAD` >> /work/versions.txt

# Build FreeRDP
COPY vendor/FreeRDP /work/vendor/FreeRDP
WORKDIR /work/vendor/FreeRDP
RUN cmake -G Ninja \
        -B build \
        -DCMAKE_INSTALL_PREFIX=${PREFIX} \
        -DCMAKE_INSTALL_LIBDIR=${PREFIX}/lib \
        -DCMAKE_BUILD_TYPE=${BUILDTYPE_FREERDP} \
        -DWITH_DEBUG_ALL=${WITH_DEBUG_FREERDP} \
        -DWITH_ICU=ON \
        -DWITH_SERVER=ON \
        -DWITH_CHANNEL_GFXREDIR=ON \
        -DWITH_CHANNEL_RDPAPPLIST=ON \
        -DWITH_CLIENT=OFF \
        -DWITH_CLIENT_COMMON=OFF \
        -DWITH_CLIENT_CHANNELS=OFF \
        -DWITH_CLIENT_INTERFACE=OFF \
        -DWITH_PROXY=OFF \
        -DWITH_SHADOW=OFF \
        -DWITH_SAMPLE=OFF && \
    ninja -C build -j8 install && \
    echo 'FreeRDP:' `git --git-dir=/work/vendor/FreeRDP/.git rev-parse --verify HEAD` >> /work/versions.txt

# Build rdpapplist RDP virtual channel plugin
COPY rdpapplist /work/rdpapplist
WORKDIR /work/rdpapplist
RUN /usr/bin/meson --prefix=${PREFIX} build \
        --buildtype=${BUILDTYPE} && \
    ninja -C build -j8 install

# Build Weston
COPY vendor/weston /work/vendor/weston
WORKDIR /work/vendor/weston
RUN /usr/bin/meson --prefix=${PREFIX} build \
        --buildtype=${BUILDTYPE} \
        -Dbackend-default=rdp \
        -Dbackend-drm=false \
        -Dbackend-drm-screencast-vaapi=false \
        -Dbackend-headless=false \
        -Dbackend-wayland=false \
        -Dbackend-x11=false \
        -Dbackend-fbdev=false \
        -Dcolor-management-colord=false \
        -Dscreenshare=false \
        -Dsystemd=false \
        -Dwslgd=true \
        -Dremoting=false \
        -Dpipewire=false \
        -Dshell-fullscreen=false \
        -Dcolor-management-lcms=false \
        -Dshell-ivi=false \
        -Dshell-kiosk=false \
        -Ddemo-clients=false \
        -Dsimple-clients=[] \
        -Dtools=[] \
        -Dresize-pool=false \
        -Dwcap-decode=false \
        -Dtest-junit-xml=false && \
    ninja -C build -j8 install && \
    echo 'weston:' `git --git-dir=/work/vendor/weston/.git rev-parse --verify HEAD` >> /work/versions.txt

# Build WSLGd Daemon
ENV CC=/usr/bin/clang
ENV CXX=/usr/bin/clang++

COPY WSLGd /work/WSLGd
WORKDIR /work/WSLGd
RUN /usr/bin/meson --prefix=${PREFIX} build \
        --buildtype=${BUILDTYPE} && \
    ninja -C build -j8 install

########################################################################
########################################################################

## Create the distro image with just what's needed at runtime

FROM alpine:3.18.4 AS runtime

RUN echo "== Install Core/UI Runtime Dependencies ==" && \
    apk add \
            cairo \
            chrony \
            dbus \
            dbus-glib \
            dhcp \
            e2fsprogs \
            font-freefont \
            libinput \
            libjpeg-turbo \
            libltdl \
            libpng \
            librsvg \
            libsndfile \
            wayland-libs-server \
            wayland-libs-client \
            wayland-libs-cursor \
            libwebp \
            libxcursor \
            libxkbcommon \
            libxrandr \
            iproute2 \
            nftables \
            pango \
            procps-ng \
            rpm \
            sed \
            tzdata \
            wayland-protocols-dev \
            xwayland \
            xtrans

# Install packages to aid in development, if not remove some packages. 

# Clear the tdnf cache to make the image smaller
RUN apk cache clean

# Remove extra doc
RUN rm -rf /usr/lib/python3.7 /usr/share/gtk-doc

# Create wslg user.
RUN adduser -u 1000 --disabled-password --home /home/wslg wslg && \
    mkdir /home/wslg/.config && \
    chown wslg /home/wslg/.config

# Copy config files.
COPY config/wsl.conf /etc/wsl.conf
COPY config/weston.ini /home/wslg/.config/weston.ini
COPY config/local.conf /etc/fonts/local.conf

# Copy default icon file.
COPY resources/linux.png /usr/share/icons/wsl/linux.png

# Copy the built artifacts from the build stage.
COPY --from=dev /work/build/usr/ /usr/
COPY --from=dev /work/build/etc/ /etc/

# Append WSLg setttings to pulseaudio.
COPY config/default_wslg.pa /etc/pulse/default_wslg.pa
RUN cat /etc/pulse/default_wslg.pa >> /etc/pulse/default.pa
RUN rm /etc/pulse/default_wslg.pa

# Copy the licensing information for PulseAudio
COPY --from=dev /work/vendor/pulseaudio/GPL \
                /work/vendor/pulseaudio/LGPL \
                /work/vendor/pulseaudio/LICENSE \
                /work/vendor/pulseaudio/NEWS \
                /work/vendor/pulseaudio/README /usr/share/doc/pulseaudio/

# Copy the licensing information for Weston
COPY --from=dev /work/vendor/weston/COPYING /usr/share/doc/weston/COPYING

# Copy the licensing information for FreeRDP
COPY --from=dev /work/vendor/FreeRDP/LICENSE /usr/share/doc/FreeRDP/LICENSE

# copy the documentation and licensing information for mesa
COPY --from=dev /work/vendor/mesa/docs /usr/share/doc/mesa/

COPY --from=dev /work/versions.txt /etc/versions.txt

CMD /usr/bin/WSLGd
