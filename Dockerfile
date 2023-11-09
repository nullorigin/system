FROM alpine:latest AS base-env

ENV PATH=/usr/bin:/usr/sbin:/bin:/sbin
ENV LLVM=1
ENV LLVM_IAS=1

RUN echo "== Setting up the base environment ==" && \
    apk update && \
    apk upgrade && \
    apk add alpine-sdk sudo && \
    abuild-keygen -a -i -n

FROM base-env AS abuild-env
ARG WSLG_VERSION="<current>"
ARG WSLG_ARCH="x86_64"
RUN echo "WSLg (" ${WSLG_ARCH} "):" ${WSLG_VERSION} > /work/versions.txt
RUN echo "alpine:" `cat /etc/os-release | head -2 | tail -1` >> /work/versions.txt

ARG MAKEDEPS[]
ARG CHKDEPS[]
ARG DEPS[]
ARG FILEPATHS[]
ARG i
COPY /src/ /work/src/
ARG APKBUILDS=$(echo /work/src/aports/*/*/APKBUILD)
RUN for file in "$APKBUILDS"; do \
    if [ -f "$file" ] && $(source $file); then \
    source $file; \
    export MAKEDEPS[i]=$(echo ${makedepends}) && \
    export CHKDEPS[i]=$(echo ${checkdepends}) && \
    export DEPS[i]=$(echo ${depends}) && \
    export FILEPATHS[i]=$(echo ${file}); \
    i=$[i++]; \
    fi \
    done; \
    export APKPATH=$(echo ${DEPS} | sed -e "s, ,\n,g" | \
    sed -e 's,-dev,,g' -e "s,>.*,,g" -e "s,<.*,,g" -e "s,=.*,,g" | \
    grep -v '!' | sort | uniq); \
    for dep in ${APKDEPS}; do \
    export APKDEP_DIR=$(echo /work/src/apk/$dep); \
    if [ -d ${APKDEP_DIR} ]; then \
    mkdir -p /work/abuild/$dep/ && \
    cp -rf ${APKDEP_DIR}/* /work/abuild/$dep/; \
    fi \
    done; \
    export APKBUILDS=$(echo /work/src/aports/*/*/APKBUILD) && \
    mkdir -p /work/abuild/src; \
    for filepath in ${APKBUILDS}; do \
    cd /work/abuild && \
    DIRPATH=$(echo $filepath | sed -e 's,APKBUILD,,g') && \
    cd ${DIRPATH} && \
    abuild -F checksum && \
    abuild -F -P /work/ -s /work/abuild/src -r; \
    done;
########################################################################
########################################################################
FROM alpine:latest AS runtime

RUN mkdir -p /home/abuild && \
    apk update && \
    apk upgrade

COPY --from=abuild-env /work/abuild/ /home/abuild/

RUN apk add --allow-untrusted $(echo /home/abuild/x86_64/*.apk) && \
    apk cache clean

# Create wslg user.
RUN adduser -u 1000 --disabled-password --home /home/wslg wslg && \
    mkdir /home/wslg/.config && \
    chown wslg /home/wslg/.config

# Copy config files.
COPY config/wsl.conf /etc/wsl.conf
COPY config/weston.ini /home/wslg/.config/weston.ini
COPY config/local.conf /etc/fonts/local.conf

# Copy default icon file.
COPY config/linux.png /usr/share/icons/wsl/linux.png

RUN mkdir -p /etc/ld.so.conf.d && \
    echo "/usr/lib/wsl/lib" > /etc/ld.so.conf.d/ld.wsl.conf
COPY config/tls.crt /etc/rdp-tls.crt
COPY config/tls.key /etc/rdp-tls.key

# Append WSLg setttings to pulseaudio.
COPY config/default_wslg.pa /etc/pulse/default_wslg.pa
RUN cat /etc/pulse/default_wslg.pa >> /etc/pulse/default.pa
RUN rm /etc/pulse/default_wslg.pa
CMD /bin/WSLGd
