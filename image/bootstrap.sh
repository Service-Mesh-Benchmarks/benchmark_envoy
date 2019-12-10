#!/bin/bash

set -xe 
apt-get update

install_system_dependencies() {
    curl -sL https://deb.nodesource.com/setup_10.x | bash -
    apt-get install -y git python nodejs cpuset linux-tools-common linux-tools-generic linux-tools-$(uname -r) tuned jq
    npm install -g forever
}

install_vegeta() {
    curl -L https://github.com/tsenart/vegeta/releases/download/v12.7.0/vegeta-12.7.0-linux-amd64.tar.gz | tar xvz
    mv vegeta /usr/bin/vegeta
}

install_envoy_and_bazel_dependencies() {
    
    ARCH="$(uname -m)"
    
    # Setup basic requirements and install them.
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y --no-install-recommends software-properties-common apt-transport-https
    
    # gcc-7
    add-apt-repository -y ppa:ubuntu-toolchain-r/test
    apt-get update
    apt-get install -y --no-install-recommends g++-7
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-7 1000
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 1000
    update-alternatives --config gcc
    update-alternatives --config g++
    
    apt-get install -y --no-install-recommends curl wget make cmake git python python-pip python-setuptools python3 python3-pip \
      unzip bc libtool ninja-build automake zip time gdb strace tshark tcpdump patch xz-utils rsync ssh-client
    
    # clang 8.
    case $ARCH in
        'ppc64le' )
            LLVM_VERSION=8.0.0
            LLVM_RELEASE="clang+llvm-${LLVM_VERSION}-powerpc64le-unknown-unknown"
            wget "https://releases.llvm.org/${LLVM_VERSION}/${LLVM_RELEASE}.tar.xz"
            tar Jxf "${LLVM_RELEASE}.tar.xz"
            mv "./${LLVM_RELEASE}" /opt/llvm
            rm "./${LLVM_RELEASE}.tar.xz"
            echo "/opt/llvm/lib" > /etc/ld.so.conf.d/llvm.conf
            ldconfig
            ;;
        'x86_64' )
            wget -O - http://apt.llvm.org/llvm-snapshot.gpg.key | apt-key add -
            apt-add-repository "deb http://apt.llvm.org/xenial/ llvm-toolchain-xenial-8 main"
            apt-get update
            apt-get install -y --no-install-recommends clang-8 clang-format-8 clang-tidy-8 lld-8 libc++-8-dev libc++abi-8-dev llvm-8
            ;;
    esac
    
    # Bazel and related dependencies.
    case $ARCH in
        'ppc64le' )
            BAZEL_LATEST="$(curl https://oplab9.parqtec.unicamp.br/pub/ppc64el/bazel/ubuntu_16.04/latest/ 2>&1 \
              | sed -n 's/.*href="\([^"]*\).*/\1/p' | grep '^bazel' | head -n 1)"
            curl -fSL https://oplab9.parqtec.unicamp.br/pub/ppc64el/bazel/ubuntu_16.04/latest/${BAZEL_LATEST} \
              -o /usr/local/bin/bazel
            chmod +x /usr/local/bin/bazel
            ;;
    esac
    
    apt-get install -y aspell
    rm -rf /var/lib/apt/lists/*
    
    # Setup tcpdump for non-root.
    groupadd pcap
    chgrp pcap /usr/sbin/tcpdump
    chmod 750 /usr/sbin/tcpdump
    setcap cap_net_raw,cap_net_admin=eip /usr/sbin/tcpdump
    
    # virtualenv
    pip3 install virtualenv
    
    # sourced from https://github.com/envoyproxy/envoy-build-tools/blob/4433e52437af6936d0af95ebc3b16b4b6df38618/build_container/build_container_common.sh
    
    if [[ "$(uname -m)" == "x86_64" ]]; then
      # buildifier
      VERSION=0.28.0
      SHA256=3d474be62f8e18190546881daf3c6337d857bf371faf23f508e9b456b0244267
      curl --location --output /usr/local/bin/buildifier https://github.com/bazelbuild/buildtools/releases/download/"$VERSION"/buildifier \
        && echo "$SHA256  /usr/local/bin/buildifier" | sha256sum --check \
        && chmod +x /usr/local/bin/buildifier
    
      # bazelisk
      VERSION=1.0
      SHA256=820f1432bb729cf1d51697a64ce57c0cff7ea4013acaf871b8c24b6388174d0d
      curl --location --output /usr/local/bin/bazel https://github.com/bazelbuild/bazelisk/releases/download/v${VERSION}/bazelisk-linux-amd64 \
        && echo "$SHA256  /usr/local/bin/bazel" | sha256sum --check \
        && chmod +x /usr/local/bin/bazel
    fi
    
    apt-get clean
}

download_and_build_envoy() {
   git clone https://github.com/AkshatM/envoy.git
   mv envoy 'source'

   USE_BAZEL_VERSION=0.29.1 /source/ci/do_ci.sh bazel.debug.server_only
   if [ ! -e /build/envoy/source/exe/envoy ]; then
	   echo "Failed to build baseline!"
   fi
   mv /build/envoy/source/exe/envoy /root/baseline_envoy
   echo "Baseline build finished!"

   rm -rf /build

   echo "Build finished!"
}

install_system_dependencies
install_vegeta
install_envoy_and_bazel_dependencies
download_and_build_envoy

sysctl -w net.ipv4.tcp_low_latency=1
# kernel module for power management is not enabled on DigitalOceans machines
#for ((i=0; i < 4; i++)); do 
#	echo performance > /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor
#done
