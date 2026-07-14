#
# Copyright (c) 2021 Matthew Penner
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

FROM        --platform=$TARGETOS/$TARGETARCH ubuntu:24.04 AS builder

ENV         DEBIAN_FRONTEND=noninteractive

RUN         echo 'Acquire::ForceIPv4 "true";' > /etc/apt/apt.conf.d/99force-ipv4 \
            && echo 'Acquire::Languages "none";' > /etc/apt/apt.conf.d/99disable-translations

RUN         sed -i 's/archive.ubuntu.com/mirror.yandex.ru/g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true \
            && sed -i 's/security.ubuntu.com/mirror.yandex.ru/g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true \
            && sed -i 's/archive.ubuntu.com/mirror.yandex.ru/g' /etc/apt/sources.list 2>/dev/null || true \
            && sed -i 's/security.ubuntu.com/mirror.yandex.ru/g' /etc/apt/sources.list 2>/dev/null || true

RUN         apt-get update \
            && apt-get install -y --no-install-recommends \
                gcc \
                shc \
                libc-dev

WORKDIR     /build
COPY        ./git_sync.sh ./sync.sh

RUN         chmod +x sync.sh \
            && shc -r -f sync.sh -o sync_bin

FROM        --platform=$TARGETOS/$TARGETARCH debian:bookworm-slim

LABEL       author="Anton Chibisu" maintainer="admin@enalian.xyz"
LABEL       org.opencontainers.image.source="https://github.com/Enalian/ptero_gmod"

ENV         DEBIAN_FRONTEND=noninteractive

RUN         dpkg --add-architecture i386 \
			&& apt-get update \
			&& apt-get upgrade -y \
            && apt-get autoremove -y \
			&& apt-get install -y --no-install-recommends \
                ca-certificates \
				curl \
                g++ \
                gcc \
                gdb \
                iproute2 \
                locales \
                net-tools \
                netcat-traditional \
                tar \
                telnet \
                tini \
                tzdata \
                wget \
                git \
                openssh-client \
                libgcc1 \
                lib32gcc-s1 \
                lib32stdc++6 \
                lib32tinfo6 \
                libtinfo6:i386 \
                lib32z1 \
                libc-dev \
                libcurl3-gnutls:i386 \
                libcurl4-gnutls-dev:i386 \
                libcurl4:i386 \
                libfontconfig1 \
                libgcc-12-dev \
                libncurses6:i386 \
                libsdl1.2debian \
                libsdl2-2.0-0:i386 \
                libssl3:i386 \
                libssl-dev:i386 \
				libtcmalloc-minimal4:i386 \
            && apt-get clean \
            && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/log/* /usr/share/doc/* /usr/share/man/* /usr/share/bash-completion/*

# Temp fix for things that still need libssl1.1
RUN         if [ "$(uname -m)" = "x86_64" ]; then \
                wget http://mirror.yandex.ru/ubuntu/pool/main/o/openssl/libssl1.1_1.1.0g-2ubuntu4_amd64.deb \
                && dpkg -i libssl1.1_1.1.0g-2ubuntu4_amd64.deb \
                && rm libssl1.1_1.1.0g-2ubuntu4_amd64.deb; \
            fi
        
# Set the locale
RUN         sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
            && locale-gen
ENV         LANG=en_US.UTF-8
ENV         LANGUAGE=en_US:en
ENV         LC_ALL=en_US.UTF-8

# Copy needing binaries
COPY        --from=builder /build/sync_bin /usr/local/bin/pgit-clone
RUN         chmod +x /usr/local/bin/pgit-clone

# Setup user and working directory
RUN         useradd -m -u 999 -s /bin/bash container
USER        container
ENV         USER=container HOME=/home/container
WORKDIR     /home/container

STOPSIGNAL  SIGINT

COPY        --chown=container:container ./entrypoint.sh /entrypoint.sh
RUN         chmod +x /entrypoint.sh

ENTRYPOINT  ["/usr/bin/tini", "-g", "--"]
CMD         ["/entrypoint.sh"]