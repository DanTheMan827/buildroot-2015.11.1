FROM dantheman827/buildroot-2015.11.1:latest-base
FROM dantheman827/buildroot-2015.11.1:latest-base
RUN cd "/buildroot-2015.11.1" && rm -rf "output/build" "output/images" "dl"

FROM debian:latest as basebuilder
COPY --from=0 "/buildroot-2015.11.1/output/build/sdl2-2.0.3/sdl2-config" "/buildroot-2015.11.1/output/host/usr/bin/sdl2-config"
COPY --from=1 "/buildroot-2015.11.1" "/buildroot-2015.11.1"

# Create a sdl2-config patched to the sysroot that buildroot built
RUN sed \
        -Ee 's#^prefix=/usr$#prefix="/buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/usr"#' \
        -e 's#^exec_prefix=/usr$#exec_prefix=${prefix}#' \
        -i "/buildroot-2015.11.1/output/host/usr/bin/sdl2-config" && \
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

# Set git identity
RUN git config --global user.email "dockerfile@example.com" && \
    git config --global user.name "Dockerfile"

# Copy toolchain.cmake
COPY "toolchain.cmake" "/buildroot-2015.11.1"
RUN chmod a=u "/buildroot-2015.11.1/toolchain.cmake"

# Set path
ENV BUILDROOT /buildroot-2015.11.1
ENV SYSROOT $BUILDROOT/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot
ENV PATH $BUILDROOT/output/host/usr/bin:$PATH

# Copy new GL headers
RUN rm -rf "$SYSROOT/usr/include/EGL" "$SYSROOT/usr/include/GLES" "$SYSROOT/usr/include/GLES2" "$SYSROOT/usr/include/KHR"
COPY "gl_headers" "/buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/"

RUN mkdir -p /staging/usr/include/ /staging/usr/lib/

# Install zstd
FROM basebuilder as zstd
RUN git clone "https://github.com/facebook/zstd.git" "/tmp/zstd" && \
    cd "/tmp/zstd/lib" && \
    make install CC=arm-buildroot-linux-gnueabihf-gcc "DESTDIR=$SYSROOT" PREFIX=/usr "-j$(grep -c ^processor /proc/cpuinfo)" && \
    make install CC=arm-buildroot-linux-gnueabihf-gcc "DESTDIR=/staging/" PREFIX=/usr "-j$(grep -c ^processor /proc/cpuinfo)" && \
    cd "/tmp" && rm -rf "/tmp/zstd" && \
    chmod -R a=u "/staging/" && find /staging/

# Install gulrak/filesystem
FROM basebuilder as gulrakfs
RUN cd /tmp && \
    git clone https://github.com/gulrak/filesystem.git filesystem && \
    cp -r filesystem/include/ghc "$SYSROOT/usr/include" && \
    cp -r filesystem/include/ghc "/staging/usr/include" && \
    cd /tmp && \
    rm -rf /tmp/filesystem && \
    chmod -R a=u "/staging/" && find /staging/

# Install boost
FROM basebuilder as boost
COPY --from=zstd /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
RUN wget "https://netactuate.dl.sourceforge.net/project/boost/boost/1.75.0/boost_1_75_0.tar.gz" -q -O - | tar -xzvf - -C "/tmp/" && \
    cd "/tmp/boost_1_75_0" && \
    ./bootstrap.sh && \
    sed -e 's/    using gcc ;/    using gcc : arm : arm-buildroot-linux-gnueabihf-g++ ;/' -i project-config.jam && \
    ./b2 install toolset=gcc-arm --prefix="$SYSROOT/usr/" ; \
    ./b2 install toolset=gcc-arm --prefix="/staging/usr/" ; \
    cd /tmp && \
    rm -rf "/tmp/boost_1_75_0" && \
    chmod -R a=u "/staging/" && find /staging/

# Install gl4es
FROM basebuilder as gl4es
RUN wget "https://github.com/ptitSeb/gl4es/archive/v1.1.4.tar.gz" -q -O - | tar -xzvf - -C /tmp && \
    mkdir -p /tmp/gl4es-1.1.4/build/ && \
    cd /tmp/gl4es-1.1.4/build/ && \
    cmake .. -DCMAKE_TOOLCHAIN_FILE=/buildroot-2015.11.1/toolchain.cmake -DNOX11=ON -DNOEGL=ON -DSTATICLIB=ON && \
    make "-j$(grep -c ^processor /proc/cpuinfo)" && \
    rm -r * && \
    cmake .. -DCMAKE_TOOLCHAIN_FILE=/buildroot-2015.11.1/toolchain.cmake -DNOX11=ON -DNOEGL=ON && \
    make "-j$(grep -c ^processor /proc/cpuinfo)" && \
    ln -s libGL.so.1 ../lib/libGL.so && \
    mkdir -p "/staging/usr/lib/" && \
    cp ../lib/* "$SYSROOT/usr/lib/" && \
    cp ../lib/* "/staging/usr/lib/" && \
    cd /tmp && \
    rm -rf "/tmp/gl4es-1.1.4/" && \
    chmod -R a=u "/staging/" && find /staging/

# Install libGLU
FROM basebuilder as glu
COPY --from=gl4es /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
RUN git clone "https://github.com/ptitSeb/GLU.git" "/tmp/GLU" && \
    cd /tmp/GLU && \
    sed -e 's/\[glBegin\],//' -i configure.ac && \
    autoconf && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make "-j$(grep -c ^processor /proc/cpuinfo)" && \
    cp .libs/* "$SYSROOT/usr/lib" && \
    cp .libs/* "/staging/usr/lib" && \
    cd /tmp && \
    rm -rf "/tmp/GLU/" && \
    chmod -R a=u "/staging/" && find /staging/

# Install hidapi
FROM basebuilder as hidapi
RUN git clone "https://github.com/signal11/hidapi.git" "/tmp/hidapi" && \
    cd "/tmp/hidapi" && \
    ./bootstrap && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/hidapi" && \
    chmod -R a=u "/staging/" && find /staging/

# Install dbus
FROM basebuilder as dbus
RUN wget "https://dbus.freedesktop.org/releases/dbus/dbus-1.12.16.tar.gz" -q -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/dbus-1.12.16/" && \
    ./configure CC=arm-buildroot-linux-gnueabihf-gcc "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/dbus-1.12.16" && \
    chmod -R a=u "/staging/" && find /staging/

# Install bluez
FROM basebuilder as bluez
COPY --from=dbus /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY "patches/" "/patches"
RUN git clone "https://github.com/bluez/bluez.git" "/tmp/bluez" && \
    cd "/tmp/bluez" && \
    git checkout 5.54 && \
    git am /patches/bluez/*.patch && \
    ./bootstrap && \
    ./configure "--host=arm-buildroot-linux-gnueabihf" "--prefix=/usr" "--disable-systemd" "--disable-cups" "--disable-obex" "--enable-library" "--enable-static" "--enable-sixaxis" "--exec-prefix=/usr" "--enable-deprecated" &&  \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/bluez/" && \
    chmod -R a=u "/staging/" && find /staging/

# Install attr
FROM basebuilder as attr
RUN wget "http://download.savannah.gnu.org/releases/attr/attr-2.4.48.tar.gz" -q -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/attr-2.4.48/" && \
    ./configure "--prefix=/usr" "--disable-static" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/attr-2.4.48/" && \
    chmod -R a=u "/staging/" && find /staging/

# Install Freetype
FROM basebuilder as freetype
RUN wget "https://download.savannah.gnu.org/releases/freetype/freetype-2.10.2.tar.gz" -q -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/freetype-2.10.2/" && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" --enable-freetype-config && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cp "$SYSROOT/usr/bin/freetype-config" /buildroot-2015.11.1/output/host/usr/bin/freetype-config && \
    cd "/tmp" && \
    rm -rf "/tmp/freetype-2.10.2/" && \
    chmod -R a=u "/staging/" && find /staging/

# Install SDL2
FROM basebuilder as sdl2
COPY "patches/" "/patches"
RUN cd /tmp && \
    git clone "https://github.com/sdl-mirror/SDL.git" SDL && \
    cd SDL && \
    git checkout 5c829aac66a491b9d23b12f4c37bf896dc11f3a8 && \
    git am /patches/SDL2/*.patch && \
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
    sed -e "s#\"/usr\"#\"$SYSROOT/usr\"#" -i "$SYSROOT/usr/lib/cmake/SDL2/sdl2-config.cmake" "/staging/usr/lib/cmake/SDL2/sdl2-config.cmake" && \
    cd "/tmp" && rm -rf "/tmp/SDL" && \
    chmod -R a=u "/staging/" && find /staging/

# Install SDL2 Mixer
FROM sdl2 as sdl_mixer
RUN rm -rf "/staging/" && \
    mkdir -p /staging/usr/include/ /staging/usr/lib/ && \
    wget "https://www.libsdl.org/projects/SDL_mixer/release/SDL2_mixer-2.0.4.tar.gz" -q -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/SDL2_mixer-2.0.4/" && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/SDL2_mixer-2.0.4/" && \
    chmod -R a=u "/staging/" && find /staging/

# Install SDL2 Image
FROM sdl2 as sdl_image
RUN rm -rf "/staging/" && \
    mkdir -p /staging/usr/include/ /staging/usr/lib/ && \
    wget "https://www.libsdl.org/projects/SDL_image/release/SDL2_image-2.0.5.tar.gz" -q -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/SDL2_image-2.0.5/" && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/SDL2_image-2.0.5/" && \
    chmod -R a=u "/staging/" && find /staging/

# Install SDL2 Net
FROM sdl2 as sdl_net
RUN rm -rf "/staging/" && \
    mkdir -p /staging/usr/include/ /staging/usr/lib/ && \
    wget "https://www.libsdl.org/projects/SDL_net/release/SDL2_net-2.0.1.tar.gz" -q -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/SDL2_net-2.0.1/" && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging/" && \
    cd "/tmp" && \
    rm -rf "/tmp/SDL2_net-2.0.1/" && \
    chmod -R a=u "/staging/" && find /staging/

# Install SDL2_ttf
FROM sdl2 as sdl_ttf
COPY --from=freetype /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
RUN rm -rf "/staging/" && \
    mkdir -p /staging/usr/include/ /staging/usr/lib/ && \
    wget "https://www.libsdl.org/projects/SDL_ttf/release/SDL2_ttf-2.0.15.tar.gz" -q -O - | tar -xzvf - -C "/tmp" && \
    cd "/tmp/SDL2_ttf-2.0.15/" && \
    ./configure "--prefix=/usr" "--host=arm-buildroot-linux-gnueabihf" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=$SYSROOT" && \
    make install "-j$(grep -c ^processor /proc/cpuinfo)" "DESTDIR=/staging" && \
    cd "/tmp" && \
    rm -rf "/tmp/SDL2_ttf-2.0.15/" && \
    chmod -R a=u "/staging/" && find /staging/

# continue from basebuilder and copy /staging from all the other builders
FROM basebuilder
COPY --from=zstd /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=gulrakfs /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=boost /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=gl4es /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=glu /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=hidapi /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=dbus /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=bluez /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=attr /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=freetype /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=sdl2 /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=sdl_mixer /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=sdl_image /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=sdl_net /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/
COPY --from=sdl_ttf /staging/ /buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/

RUN sed -e "s#libdir='/usr/lib'#libdir='$SYSROOT/usr/lib'#" -i $SYSROOT/usr/lib/*.la; exit 0
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
