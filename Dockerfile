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

ARG MDEPS
ARG CDEPS
ARG RDEPS
COPY src/ /work/src/
ARG APKBUILDS=$(echo /work/src/abuild/base/*/APKBUILD)
RUN for file in "$APKBUILDS"; do \
    if [ -f "$file" ] && $(source $file); then \
    source $file; \
    export MDEPS=$(echo $MDEPS ${makedepends} | sed -e 's,-dev,,g' -e "s,>.*,,g" -e "s,<.*,,g" -e "s,=.*,,g") && \
    export CDEPS=$(echo $CDEPS ${checkdepends} | sed -e 's,-dev,,g' -e "s,>.*,,g" -e "s,<.*,,g" -e "s,=.*,,g") && \
    export RDEPS=$(echo $RDEPS ${depends} | sed -e 's,-dev,,g' -e "s,>.*,,g" -e "s,<.*,,g" -e "s,=.*,,g") \
    fi \
    done; \
    export MDEPS=$(echo $MDEPS | sed -e "s, ,\n,g" | sort | uniq) && \
    export CDEPS=$(echo $CDEPS | sed -e "s, ,\n,g" | sort | uniq) && \
    export RDEPS=$(echo $RDEPS | sed -e "s, ,\n,g" | sort | uniq); \
    for dep in ${MDEPS}; do \
    DEPDIR=$(echo /work/src/aports/*/$dep); \
    if [ -d ${DEPDIR} ]; then \
    mkdir -p /work/src/abuild/make/$dep/ && \
    cp -rf ${DEPDIR}/* /work/src/abuild/make/$dep/; \
    fi \
    done; \
    for dep in ${CDEPS}; do \
    DEPDIR=$(echo /work/src/aports/*/$dep); \
    if [ -d ${DEPDIR} ]; then \
    mkdir -p /work/src/abuild/check/$dep/ && \
    cp -rf ${DEPDIR}/* /work/src/abuild/check/$dep/; \
    fi \
    done; \
    for dep in ${RDEPS}; do \
    DEPDIR=$(echo /work/src/aports/*/$dep); \
    if [ -d ${DEPDIR} ]; then \
    mkdir -p /work/src/abuild/runtime/$dep/ && \
    cp -rf ${DEPDIR}/* /work/src/abuild/runtime/$dep/; \
    fi \
    done; \
    export APKBUILDS=$(echo /work/src/abuild/*/*/APKBUILD) && \
    mkdir -p /work/abuild/src; \
    for file in ${APKBUILDS}; do \
    DIRPATH=$(echo $file | sed -e 's,APKBUILD,,g') && \
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
COPY cfg/wsl.conf /etc/wsl.conf
COPY cfg/weston.ini /home/wslg/.config/weston.ini
COPY cfg/local.conf /etc/fonts/local.conf

# Copy default icon file.
COPY cfg/linux.png /usr/share/icons/wsl/linux.png

RUN mkdir -p /etc/ld.so.conf.d && \
    echo "/usr/lib/wsl/lib" > /etc/ld.so.conf.d/ld.wsl.conf
COPY cfg/tls.crt /etc/rdp-tls.crt
COPY cfg/tls.key /etc/rdp-tls.key

# Append WSLg setttings to pulseaudio.
COPY cfg/default_wslg.pa /etc/pulse/default_wslg.pa
RUN cat /etc/pulse/default_wslg.pa >> /etc/pulse/default.pa
RUN rm /etc/pulse/default_wslg.pa
CMD /usr/bin/WSLGd
