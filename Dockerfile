# Build with old debian because buildroot won't on newer
FROM debian:jessie

RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
RUN apt-get update && apt-get upgrade -y && apt-get install wget curl command-not-found nano vim gcc g++ make git cpio python unzip rsync bc subversion locales build-essential -y && apt-get clean

RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen
RUN locale-gen

RUN curl "https://buildroot.org/downloads/buildroot-2015.11.1.tar.gz" | tar -xzvf - -C /root/

COPY .config /root/buildroot-2015.11.1/.config
COPY ipkg-0.99.163.tar.gz /root/buildroot-2015.11.1/dl/ipkg-0.99.163.tar.gz

RUN make -C /root/buildroot-2015.11.1/

# Use new debian and copy the built buildroot from the previous stage
FROM debian:latest
COPY --from=0 /root/buildroot-2015.11.1 /root/buildroot-2015.11.1

# Create a sdl2-config patched to the sysroot that buildroot built
RUN sed -Ee 's#^prefix=/usr$#prefix="/root/buildroot-2015.11.1/output/host/usr/arm-buildroot-linux-gnueabihf/sysroot/usr"#' -e 's#^exec_prefix=/usr$#exec_prefix=${prefix}#' /root/buildroot-2015.11.1/output/build/sdl2-2.0.3/sdl2-config > /root/buildroot-2015.11.1/output/host/usr/bin/sdl2-config && chmod +x /root/buildroot-2015.11.1/output/host/usr/bin/sdl2-config && ln -s sdl2-config /root/buildroot-2015.11.1/output/host/usr/bin/arm-buildroot-linux-gnueabihf-sdl2-config

# Update apt, install packages, and update command-not-found data
RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
RUN apt-get update && apt-get upgrade -y && apt-get install wget curl command-not-found nano vim gcc g++ make git cpio python unzip rsync bc subversion locales build-essential -y && apt-get clean
RUN update-command-not-found

# Setup environment
COPY importpath_gcc /root/buildroot-2015.11.1/output/host
COPY importpath_r16 /root/buildroot-2015.11.1/output/host
COPY .bashrc /root/.bashrc

CMD ["/bin/bash"]
