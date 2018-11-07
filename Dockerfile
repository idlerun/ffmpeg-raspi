ARG baseimg=raspbian/jessie
FROM $baseimg as build
ENV DEBIAN_FRONTEND=noninteractive
ENV SRC_DIR=/src
ENV TARGET_DIR=/target
ENV PKG_CONFIG_PATH="$TARGET_DIR/lib/pkgconfig"
ENV PATH=$TARGET_DIR:$TARGET_DIR/bin:$PATH
RUN mkdir -p $SRC_DIR $TARGET_DIR $PKG_CONFIG_PATH
RUN apt-get update
RUN apt-get install -y wget
RUN apt-get install -y git
RUN apt-get install -y libtool
RUN apt-get install -y autoconf
RUN apt-get install -y cmake
RUN apt-get install -y build-essential
RUN apt-get install -y pkg-config
RUN apt-get install -y libasound2-dev
WORKDIR $SRC_DIR

FROM build as dep-x264
RUN git clone --depth 1 --branch stable https://git.videolan.org/git/x264
WORKDIR /src/x264
RUN ./configure --prefix=$TARGET_DIR --enable-shared --disable-opencl --enable-pic
RUN make -j4
RUN make install

FROM build as dep-vpx
RUN git clone --depth 1 --branch v1.7.0 https://chromium.googlesource.com/webm/libvpx
WORKDIR /src/libvpx
RUN ./configure --prefix=$TARGET_DIR --enable-shared --disable-examples --disable-unit-tests --enable-pic
RUN make -j4
RUN make install

FROM build as dep-webp
RUN git clone --depth 1 --branch 1.0.0 https://github.com/webmproject/libwebp.git
WORKDIR /src/libwebp
RUN ./autogen.sh
RUN ./configure --prefix=$TARGET_DIR --enable-shared --disable-examples
RUN make -j4
RUN make install

FROM build as dep-lame
RUN wget https://cytranet.dl.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz && \
    tar xf lame-3.100.tar.gz && \
    rm -f lame-3.100.tar.gz
WORKDIR /src/lame-3.100
RUN ./configure --prefix=$TARGET_DIR --enable-shared --disable-static
RUN make -j4
RUN make install

FROM build as dep-openssl
RUN git clone --depth 1 --branch OpenSSL_1_1_0-stable https://github.com/openssl/openssl.git
WORKDIR /src/openssl
RUN ./config --prefix=$TARGET_DIR --openssldir=$TARGET_DIR -Wl,-rpath,$TARGET_DIR/lib
RUN make -j4
RUN make install

FROM build as dep-opus
RUN git clone --depth 1 --branch v1.2.1 https://github.com/xiph/opus.git
WORKDIR /src/opus
RUN ./autogen.sh
RUN ./configure --prefix=$TARGET_DIR --enable-shared --disable-doc --disable-extra-programs
RUN make -j4
RUN make install

FROM build as dep-vidstab
RUN git clone --depth 1 --branch release-0.98b https://github.com/georgmartius/vid.stab.git
WORKDIR /src/vid.stab
RUN cmake -DCMAKE_INSTALL_PREFIX="$TARGET_DIR"
RUN make -j4
RUN make install

FROM build as ffmpeg-bins
RUN git clone --depth 1 --branch release/4.1 https://github.com/FFmpeg/FFmpeg.git
WORKDIR /src/FFmpeg
COPY --from=dep-x264 /target/ /target/
COPY --from=dep-vpx /target/ /target/
COPY --from=dep-webp /target/ /target/
COPY --from=dep-lame /target/ /target/
COPY --from=dep-openssl /target/ /target/
COPY --from=dep-vidstab /target/ /target/
COPY --from=dep-opus /target/ /target/
RUN ./configure \
    --arch=armel --target-os=linux \
    --prefix="$TARGET_DIR" \
    --extra-cflags="-I$TARGET_DIR/include" \
    --extra-ldflags="-L$TARGET_DIR/lib" \
    --enable-rpath \
    --libdir=$TARGET_DIR/lib \
    --enable-shared \
    \
    --enable-pic \
    --enable-neon \
    --disable-debug \
    \
    --enable-gpl \
    --enable-nonfree \
    \
    --enable-indev=alsa --enable-outdev=alsa \
    --enable-libx264 \
    --enable-libvpx \
    --enable-libwebp \
    --enable-libmp3lame \
    --enable-openssl \
    --enable-libopus \
    --enable-libvidstab
RUN make -j4
RUN make install


FROM build
RUN echo 'deb http://ftp.us.debian.org/debian sid main' >> /etc/apt/sources.list
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 04EE7237B7D453EC 7638D0442B90D010 8B48AD6246925553
RUN apt-get update
RUN apt-get install -y patchelf
RUN mkdir -p /stage/lib /out_bin/lib
COPY --from=ffmpeg-bins /target/bin/ffmpeg /stage/
COPY --from=ffmpeg-bins /target/lib /stage/lib/
WORKDIR /stage
RUN patchelf --set-rpath '$ORIGIN/lib' ffmpeg
RUN find lib -type f -name '*.so*' | xargs -n 1 patchelf --set-rpath '$ORIGIN'
RUN cp -v $(ldd ffmpeg | grep '/stage/./lib/' | sed -e 's/.*=> //' | cut -d' ' -f1) /out_bin/lib
RUN cp ffmpeg /out_bin