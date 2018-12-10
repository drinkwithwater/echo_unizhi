#!/bin/bash
file=${1##*/}
export SUB_START=${file%.*}
system_name=$(uname -s)
if [ $system_name == "Darwin" ]; then
	export OS_NAME="mac"
elif [ $system_name == "Linux" ]; then
	export OS_NAME="linux"
fi
./skynet/skynet config
exit
