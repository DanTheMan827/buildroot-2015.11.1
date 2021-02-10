FROM dantheman827/buildroot-2015.11.1:latest-base as builder1
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
        libaudiofile-dev \
        upx && \
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

# Set git identity
RUN git config --global user.email "dockerfile@example.com" && \
    git config --global user.name "Dockerfile"

# Copy toolchain.cmake
COPY "toolchain.cmake" "/buildroot-2015.11.1"
RUN chmod a=u "/buildroot-2015.11.1/toolchain.cmake"

# Copy new GL headers
RUN rm -rf "$SYSROOT/usr/include/EGL" "$SYSROOT/usr/include/GLES" "$SYSROOT/usr/include/GLES2" "$SYSROOT/usr/include/KHR"
COPY "gl_headers" "$SYSROOT/usr/include/"

# Set up builder3
FROM builder2 as builder3
RUN mkdir -p /staging/usr/include/

# Copy patches
COPY "patches/" "/patches"

# Install gl4es
RUN wget "https://github.com/ptitSeb/gl4es/archive/v1.1.2.tar.gz" -O - | tar -xzvf - -C /tmp && \
    mkdir -p /tmp/gl4es-1.1.2/build/ && \
    cd /tmp/gl4es-1.1.2/build/ && \
    cmake .. -DCMAKE_TOOLCHAIN_FILE=/buildroot-2015.11.1/toolchain.cmake -DNOX11=ON -DNOEGL=ON -DSTATICLIB=ON && \
    make "-j$(grep -c ^processor /proc/cpuinfo)" && \
    mkdir -p "/staging/usr/lib/" && \
    cp lib/libGL.a "$SYSROOT/" && \
    cp lib/libGL.a "/staging/usr/lib/" && \
    cd /tmp && \
    rm -rf "/tmp/gl4es-1.1.2/"

# Install SDL2
RUN cd /tmp && \
    git clone "https://github.com/sdl-mirror/SDL.git" && \
    cd SDL && \
    git checkout 5c829aac66a491b9d23b12f4c37bf896dc11f3a8 && \
    git am /patches/SDL2/* && \
    ./configure \
      --disable-video-rpi \
      --disable-video-x11-xcursor \
      --disable-video-x11-xinerama \
      --disable-video-x11-xinput \
      --disable-video-x11-xrandr \
      --disable-video-x11-scrnsaver \
      --disable-video-x11-vm \
      --disable-video-x11 \
      --without-x \
      --disable-video-opengl \
      --enable-video-opengles \
      --disable-video-vulkan \
      --disable-oss \
      --enable-alsa \
      --enable-alsa-shared \
      --enable-video-mali \
      --disable-dbus \
      --disable-video-kmsdrm \
      --enable-arm-simd \
      --enable-arm-neon \
      --host=arm-buildroot-linux-gnueabihf \
      --prefix=/usr && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && rm -rf "/tmp/SDL-mirror"

# Install hidapi
RUN git clone "https://github.com/signal11/hidapi.git" "/tmp/hidapi" && \
    cd "/tmp/hidapi" && \
    ./bootstrap && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && rm -rf "/tmp/hidapi"

# Install dbus
RUN wget "https://dbus.freedesktop.org/releases/dbus/dbus-1.12.16.tar.gz" -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/dbus-1.12.16/" && \
    ./configure CC=arm-buildroot-linux-gnueabihf-gcc "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/dbus-1.12.16"

# Install attr
RUN wget "http://download.savannah.gnu.org/releases/attr/attr-2.4.48.tar.gz" -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/attr-2.4.48/" && \
    ./configure "--prefix=/usr" "--disable-static" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/attr-2.4.48/"

# Install bluez
ADD bluez-5.54-sixaxis-auto.tar.gz /tmp
RUN cd "/tmp/bluez-5.54-sixaxis-auto" && \
    ./bootstrap && \
    ./configure "--host=arm-buildroot-linux-gnueabihf" "--prefix=/usr" "--disable-systemd" "--disable-cups" "--disable-obex" "--enable-library" "--enable-static" "--enable-sixaxis" "--exec-prefix=/usr" "--enable-deprecated" &&  \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/bluez-5.54-sixaxis-auto/"

# Install SDL2 Mixer
RUN wget "https://www.libsdl.org/projects/SDL_mixer/release/SDL2_mixer-2.0.1.tar.gz" -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/SDL2_mixer-2.0.1/" && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/SDL2_mixer-2.0.1/"

# Install SDL2 Image
RUN wget "https://www.libsdl.org/projects/SDL_image/release/SDL2_image-2.0.1.tar.gz" -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/SDL2_image-2.0.1/" && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/SDL2_image-2.0.1/"

# Install Freetype
RUN wget "https://download.savannah.gnu.org/releases/freetype/freetype-2.10.2.tar.gz" -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/freetype-2.10.2/" && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" --enable-freetype-config && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cp "$SYSROOT/usr/bin/freetype-config" /buildroot-2015.11.1/output/host/usr/bin/freetype-config && \
    cd "/tmp" && \
    rm -rf "/tmp/freetype-2.10.2/"

# Install SDL2_ttf
RUN wget "https://www.libsdl.org/projects/SDL_ttf/release/SDL2_ttf-2.0.15.tar.gz" -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/SDL2_ttf-2.0.15/" && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging" && \
    cd "/tmp" && \
    rm -rf "/tmp/SDL2_ttf-2.0.15/"

# Install zstd
RUN git clone "https://github.com/facebook/zstd.git" "/tmp/zstd" && \
    cd "/tmp/zstd/lib" && \
    make install CC=arm-buildroot-linux-gnueabihf-gcc "DESTDIR=$SYSROOT" PREFIX=/usr "-j$(grep -c ^processor /proc/cpuinfo)" && \
    make install CC=arm-buildroot-linux-gnueabihf-gcc "DESTDIR=/staging" PREFIX=/usr "-j$(grep -c ^processor /proc/cpuinfo)" && \
    cd "/tmp" && rm -rf "/tmp/zstd"

# Install gulrak/filesystem
RUN cd /tmp && \
    git clone https://github.com/gulrak/filesystem.git filesystem && \
    cp -r filesystem/include/ghc "$SYSROOT/usr/include" && \
    cp -r filesystem/include/ghc "/staging/usr/include" && \
    rm -rf /tmp/filesystem

# chmod /staging
RUN chmod -R a=u "/staging/" && find /staging/

FROM builder2
COPY --from=builder3 /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
RUN mv "$SYSROOT/usr/bin/freetype-config" /buildroot-2015.11.1/output/host/usr/bin/freetype-config

# Create arm-linux symlinks
RUN cd /buildroot-2015.11.1/output/host/usr/bin && \
    ls -1 arm-buildroot-linux-gnueabihf-* | while read line; do \
      newname="`echo -n $line | sed -e 's#^arm-buildroot-linux-gnueabihf#arm-linux#'`"; \
      [ ! -e "$newname" ] && ln -s "$line" "$newname"; \
    done; exit 0

# Setup environment
COPY ["retrolink", "/buildroot-2015.11.1/output/host/usr/bin"]
COPY ["importpath_gcc", "importpath_r16", "/buildroot-2015.11.1/output/host/"]
COPY [".bashrc", "/root/"]

CMD ["/bin/bash"]
