FROM raspbian/stretch as build
ENV DEBIAN_FRONTEND=noninteractive
ENV PKG_CONFIG_PATH="/target/lib/pkgconfig"
ENV PATH=/target:/target/bin:$PATH
RUN mkdir -p /src /target/lib/pkgconfig
ENV SRC_DIR=/src
ENV TARGET_DIR=/target
RUN apt-get update
RUN apt-get install -y \
    wget git libtool autoconf \
    cmake build-essential pkg-config\
    libasound2-dev patchelf
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
RUN wget -q https://www.openssl.org/source/openssl-1.1.1.tar.gz
RUN tar xf openssl-1.1.1.tar.gz
WORKDIR /src/openssl-1.1.1
RUN ./config shared --prefix=$TARGET_DIR
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


# require for enable-omx h264 hardware decoding
FROM build as dep-libomxil
RUN wget https://ayera.dl.sourceforge.net/project/omxil/omxil/Bellagio%200.9.3/libomxil-bellagio-0.9.3.tar.gz && \
    tar xf libomxil-bellagio-0.9.3.tar.gz && \
    rm -f libomxil-bellagio-0.9.3.tar.gz
WORKDIR /src/libomxil-bellagio-0.9.3
# avoids error:  case value 2130706435 not in enumerated type OMX_INDEXTYPE [-Werror=switch]
RUN sed -e "s/-Wall -Werror//" -i configure
RUN ./configure  --prefix=$TARGET_DIR
RUN make
RUN make install


FROM build as dep-mmal
RUN git clone https://github.com/raspberrypi/userland.git
WORKDIR /src/userland
RUN mkdir -p /src/userland/build
WORKDIR /src/userland/build
RUN cmake -DVMCS_INSTALL_PREFIX=/target -DCMAKE_INSTALL_PREFIX=/target ..
RUN make -j4
RUN make install


FROM build as ffmpeg-bins
RUN wget -q https://ffmpeg.org/releases/ffmpeg-4.1.tar.bz2
RUN tar xf ffmpeg-4.1.tar.bz2
WORKDIR /src/ffmpeg-4.1
COPY --from=dep-x264 /target/ /target/
COPY --from=dep-vpx /target/ /target/
COPY --from=dep-webp /target/ /target/
COPY --from=dep-lame /target/ /target/
COPY --from=dep-openssl /target/ /target/
COPY --from=dep-vidstab /target/ /target/
COPY --from=dep-opus /target/ /target/
COPY --from=dep-libomxil /target/ /target/
COPY --from=dep-mmal /target/ /target/

RUN mkdir -p /opt/vc/lib
COPY lib/*.so* /opt/vc/lib/
ENV LD_LIBRARY_PATH=/opt/vc/lib

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
    --enable-omx \
    --enable-omx-rpi \
    --enable-mmal \
    --enable-decoder=h264_mmal \
    --enable-decoder=mpeg2_mmal \
    --enable-encoder=h264_omx \
    --enable-encoder=h264_omx \
    \
    --enable-libvpx \
    --enable-libwebp \
    --enable-libmp3lame \
    --enable-openssl \
    --enable-libopus \
    --enable-libvidstab
RUN make -j4
RUN make install
RUN mkdir -p /out_bin/lib
# copy required libs into lib dir
RUN find /target/lib -type f -name '*.so*' | xargs -n 1 patchelf --set-rpath '$ORIGIN'
RUN cp /target/bin/ffmpeg /target/ffmpeg
RUN patchelf --set-rpath '/opt/vc/lib:$ORIGIN/lib' \
             /target/ffmpeg
RUN cp -v $(ldd /target/ffmpeg | grep '/target/lib/' | sed -e 's/.*=> //' | cut -d' ' -f1) /out_bin/lib
# remove any libs that are already present in /opt/vc/lib on host
RUN for F in /opt/vc/lib/*.so*; do rm -f $(basename $F); done
# loads from /opt/vc/lib on host
RUN patchelf --add-needed libopenmaxil.so /target/ffmpeg
RUN mv /target/ffmpeg /out_bin/

