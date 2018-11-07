#!/bin/bash -e
cd $(dirname $0)
rm -rf bin
mkdir -p bin
docker build -t build-ffmpeg-raspi .
# extract the built ffmpeg
docker run -v $(pwd)/bin:/mnt --rm build-ffmpeg-raspi bash -c 'cp -R -v /out_bin/* /mnt/'
