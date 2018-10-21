#!/bin/bash
file=${1##*/}
export SUB_START=${file%.*}
export OS_NAME="android"
./skynet/skynet config
exit
