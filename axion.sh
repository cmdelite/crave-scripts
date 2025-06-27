#!/bin/bash

# Init
repo init -u https://github.com/AxionAOSP/android.git -b lineage-22.2 --git-lfs --depth=1
echo "~~~~~~~~~~~"
echo "init success"
echo "~~~~~~~~~~~"

# Trees
git clone https://github.com/cmdelite/manifest/ --depth 1 -b axion .repo/local_manifests
echo "~~~~~~~~~~~"
echo "trees success"
echo "~~~~~~~~~~~"

# Sync
/opt/crave/resync.sh 
echo "~~~~~~~~~~~"
echo "sync success"
echo "~~~~~~~~~~~"


# build env setup
. build/envsetup.sh
echo "~~~~~~~~~~~"
echo "build env setup success"
echo "~~~~~~~~~~~"

# sign 
gk -s
echo "~~~~~~~~~~~"
echo "sign success"
echo "~~~~~~~~~~~"

# lunch
axion gta4xlwifi userdebug gms pico
echo "~~~~~~~~~~~"
echo "lunch success"
echo "~~~~~~~~~~~"

# build
ax -br 
echo "~~~~~~~~~~~"
echo "build success"
echo "~~~~~~~~~~~"
