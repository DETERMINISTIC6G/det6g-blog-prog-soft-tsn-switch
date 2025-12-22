FROM ubuntu:22.04

LABEL maintainer="Huu-Nghia <huunghia.nguyen@montimage.eu>"

ARG DEBIAN_FRONTEND=noninteractive

# install pre-requirement
RUN apt-get update && apt-get install -y curl gnupg ca-certificates

RUN curl -fsSL https://download.opensuse.org/repositories/home:p4lang/xUbuntu_22.04/Release.key \
   | gpg --dearmor \
   > /usr/share/keyrings/p4lang.gpg

RUN echo "deb [signed-by=/usr/share/keyrings/p4lang.gpg] \
   http://download.opensuse.org/repositories/home:/p4lang/xUbuntu_22.04/ /" \
   > /etc/apt/sources.list.d/p4lang.list

RUN apt-get update \
    -o Acquire::AllowInsecureRepositories=true \
    -o Acquire::AllowDowngradeToInsecureRepositories=true \
  && apt-get install -y --allow-unauthenticated p4lang-p4c


# install requirements
RUN apt install -y automake cmake libgmp-dev \
    libpcap-dev libboost-dev libboost-test-dev libboost-program-options-dev \
    libboost-system-dev libboost-filesystem-dev libboost-thread-dev \
    libevent-dev libtool flex bison pkg-config g++ libssl-dev git


WORKDIR /tsn/
# the patch
RUN git clone https://github.com/DETERMINISTIC6G/det6g-blog-prog-soft-tsn-switch.git switch

WORKDIR /tsn/switch
# clone source code
RUN git clone https://github.com/p4lang/behavioral-model.git

WORKDIR /tsn/switch/behavioral-model

# apply our patch
# the latest patch is available here: https://github.com/p4lang/behavioral-model/compare/main...montimage-projects:behavioral-model:main
RUN git checkout 199af48 #same moment we patched BMv2
RUN git apply ../bmv2/bmv2.patch
# compile and install (will take few minutes)
RUN ./autogen.sh && ./configure && make -j 2 && make install

ENTRYPOINT ["/usr/local/bin/simple_switch"]