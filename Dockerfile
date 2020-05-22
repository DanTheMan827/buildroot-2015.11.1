FROM debian:jessie

RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
RUN apt-get update && apt-get upgrade -y && apt-get install wget curl command-not-found nano vim gcc g++ make git cpio python unzip rsync bc subversion locales build-essential -y && apt-get clean

RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen
RUN locale-gen

RUN curl "https://buildroot.org/downloads/buildroot-2015.11.1.tar.gz" | tar -xzvf - -C /root/

COPY .config /root/buildroot-2015.11.1/.config
COPY ipkg-0.99.163.tar.gz /root/buildroot-2015.11.1/dl/ipkg-0.99.163.tar.gz

RUN make -C /root/buildroot-2015.11.1/

CMD ["/bin/bash"]
