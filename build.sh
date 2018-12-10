#!/bin/bash -e
cd $(dirname $0)
docker build -t build-ffmpeg-raspi -f Dockerfile /opt/vc
# extract the built ffmpeg

docker rm -f tmp &>/dev/null || true
docker create --user $(id -u):$(id -g) --name tmp build-ffmpeg-raspi
rm -rf bin
docker cp tmp:/out_bin bin
docker rm -f tmp
