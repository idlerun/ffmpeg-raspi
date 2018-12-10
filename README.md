---
page: https://idle.run/ffmpeg-raspi
title: "FFmpeg build for Raspberry Pi"
tags: ffmpeg raspberry pi
date: 2018-11-09
---

## Overview

Uses a Docker build to isolate all of the checkout libs and everything needed to create a
build of ffmpeg for the Raspberry Pi (or other arm devices, in theory).

Creates a shared lib because static build doesn't seem to work correctly with ALSA devices. All .so libraries are bundled alongside the binary to keep it portable like a static build.

## Requirements

Install Docker as described here: https://www.raspberrypi.org/blog/docker-comes-to-raspberry-pi/

```
curl -sSL https://get.docker.com | sh
```

Download or checkout this repo

## Usage

Run `build.sh`. Expect it to take a very long time (several hours) as it has a lot of work to do.

It will create a Docker image named `build-ffmpeg-raspi` which contains all source and the compiled ffmpeg. Then it runs a container with that image to pull out the `ffmpeg` binaries to the host.
