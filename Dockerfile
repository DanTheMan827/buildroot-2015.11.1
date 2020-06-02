# Build with old debian because buildroot won't on newer
FROM debian:jessie as builder1

RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        wget \
        curl \
        command-not-found \
        nano \
        vim \
        gcc \
        g++ \
        make \
        git \
        cpio \
        python \
        unzip \
        rsync \
        bc \
        subversion \
        locales \
        build-essential && \
    apt-get clean && \
    sed -i 's/^# *\(en_US.UTF-8\)/\1/' "/etc/locale.gen" && \
    locale-gen

ADD buildroot-2015.11.1.tar.gz /

COPY [".config", "/buildroot-2015.11.1/"]
COPY ["icu4c-56_1-src.tgz", "ipkg-0.99.163.tar.gz", "/buildroot-2015.11.1/dl/"]

RUN make -C "/buildroot-2015.11.1/" && chmod -R a=u "/buildroot-2015.11.1"

# Use new debian and copy the built buildroot from the previous stage
FROM debian:latest as builder2
COPY --from=0 "/buildroot-2015.11.1" "/buildroot-2015.11.1"

# Create a sdl2-config patched to the sysroot that buildroot built
RUN sed \
        -Ee 's#^prefix=/usr$#prefix="/buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/usr"#' \
        -e 's#^exec_prefix=/usr$#exec_prefix=${prefix}#' \
        "/buildroot-2015.11.1/output/build/sdl2-2.0.3/sdl2-config" > "/buildroot-2015.11.1/output/host/usr/bin/sdl2-config" && \
    chmod +x "/buildroot-2015.11.1/output/host/usr/bin/sdl2-config" && \
    ln -s "sdl2-config" "/buildroot-2015.11.1/output/host/usr/bin/arm-buildroot-linux-gnueabihf-sdl2-config"

# Update apt, install packages, and update command-not-found data
RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        wget \
        curl \
        command-not-found \
        nano \
        vim \
        gcc \
        g++ \
        make \
        git \
        cpio \
        python \
        unzip \
        rsync \
        bc \
        subversion \
        locales \
        build-essential \
        bsdmainutils \
        libaudiofile-dev && \
    apt-get clean && \
    apt update && \
    update-command-not-found

# Generate locale
RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && \
    locale-gen

# Set path
ENV BUILDROOT /buildroot-2015.11.1
ENV SYSROOT $BUILDROOT/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot
ENV PATH $BUILDROOT/output/host/usr/bin:$PATH

# Copy toolchain.cmake
COPY "toolchain.cmake" "/buildroot-2015.11.1"
RUN chmod a=u "/buildroot-2015.11.1/toolchain.cmake"

FROM builder2 as builder3
RUN mkdir /staging/

# Install hidapi
RUN git clone "https://github.com/signal11/hidapi.git" "/tmp/hidapi" && \
    cd "/tmp/hidapi" && \
    ./bootstrap && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && rm -rf "/tmp/hidapi"

# Install dbus
RUN wget "https://dbus.freedesktop.org/releases/dbus/dbus-1.12.16.tar.gz" -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/dbus-1.12.16/" && \
    ./configure CC=arm-buildroot-linux-gnueabihf-gcc "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/dbus-1.12.16"

# Install attr
RUN wget "http://download.savannah.gnu.org/releases/attr/attr-2.4.48.tar.gz" -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/attr-2.4.48/" && \
    ./configure "--prefix=/usr" "--disable-static" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/attr-2.4.48/"

# Install bluez
ADD bluez-5.54-sixaxis-auto.tar.gz /tmp
RUN cd "/tmp/bluez-5.54-sixaxis-auto" && \
    ./bootstrap && \
    ./configure "--host=arm-buildroot-linux-gnueabihf" "--prefix=/usr" "--disable-systemd" "--disable-cups" "--disable-obex" "--enable-library" "--enable-static" "--enable-sixaxis" "--exec-prefix=/usr" "--enable-deprecated" &&  \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/bluez-5.54-sixaxis-auto/"

# Install SDL2 Mixer
RUN wget "https://www.libsdl.org/projects/SDL_mixer/release/SDL2_mixer-2.0.1.tar.gz" -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/SDL2_mixer-2.0.1/" && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/SDL2_mixer-2.0.1/"

RUN chmod -R a=u "/staging/"

FROM builder2
COPY --from=builder3 /staging/* /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/

# Create arm-linux symlinks
RUN cd /buildroot-2015.11.1/output/host/usr/bin && \
    ls -1 arm-buildroot-linux-gnueabihf-* | while read line; do \
      newname="`echo -n $line | sed -e 's#^arm-buildroot-linux-gnueabihf#arm-linux#'`"; \
      [ ! -e "$newname" ] && ln -s "$line" "$newname"; \
    done

# Setup environment
COPY ["retrolink", "/buildroot-2015.11.1/output/host/usr/bin"]
COPY ["importpath_gcc", "importpath_r16", "/buildroot-2015.11.1/output/host/"]
COPY [".bashrc", "/root/"]

CMD ["/bin/bash"]
