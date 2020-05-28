# Build with old debian because buildroot won't on newer
FROM debian:jessie

RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
RUN apt-get update && apt-get upgrade -y && apt-get install wget curl command-not-found nano vim gcc g++ make git cpio python unzip rsync bc subversion locales build-essential -y && apt-get clean

RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen
RUN locale-gen

RUN curl "https://buildroot.org/downloads/buildroot-2015.11.1.tar.gz" | tar -xzvf - -C /root/

COPY .config /root/buildroot-2015.11.1/.config
COPY icu4c-56_1-src.tgz /root/buildroot-2015.11.1/dl/icu4c-56_1-src.tgz
COPY ipkg-0.99.163.tar.gz /root/buildroot-2015.11.1/dl/ipkg-0.99.163.tar.gz

RUN echo "MESA3D_CONF_OPTS += --disable-static" | cat - /root/buildroot-2015.11.1/package/mesa3d/mesa3d.mk > /root/mesa3d.mk && mv /root/mesa3d.mk /root/buildroot-2015.11.1/package/mesa3d/mesa3d.mk

RUN make -C /root/buildroot-2015.11.1/

# Use new debian and copy the built buildroot from the previous stage
FROM debian:latest
COPY --from=0 /root/buildroot-2015.11.1 /root/buildroot-2015.11.1

# Create a sdl2-config patched to the sysroot that buildroot built
RUN sed -Ee 's#^prefix=/usr$#prefix="/root/buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/usr"#' -e 's#^exec_prefix=/usr$#exec_prefix=${prefix}#' /root/buildroot-2015.11.1/output/build/sdl2-2.0.3/sdl2-config > /root/buildroot-2015.11.1/output/host/usr/bin/sdl2-config && chmod +x /root/buildroot-2015.11.1/output/host/usr/bin/sdl2-config && ln -s sdl2-config /root/buildroot-2015.11.1/output/host/usr/bin/arm-buildroot-linux-gnueabihf-sdl2-config

# Update apt, install packages, and update command-not-found data
RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
RUN apt-get update && apt-get upgrade -y && apt-get install wget curl command-not-found nano vim gcc g++ make git cpio python unzip rsync bc subversion locales build-essential bsdmainutils libaudiofile-dev -y && apt-get clean
RUN apt update && update-command-not-found

# Generate locale
RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen

# Set path
ENV PATH /root/buildroot-2015.11.1/output/host/usr/bin:$PATH

# Install hidapi
RUN git clone https://github.com/signal11/hidapi.git /root/hidapi && \
    cd /root/hidapi && \
    ./bootstrap && \
    ./configure --prefix=/usr --host=arm-buildroot-linux-gnueabihf && \
    make install DESTDIR=/root/buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/ && \
    cd /root && rm -rf /root/hidapi

# Setup environment
COPY importpath_gcc /root/buildroot-2015.11.1/output/host
COPY importpath_r16 /root/buildroot-2015.11.1/output/host
COPY .bashrc /root/.bashrc

CMD ["/bin/bash"]
