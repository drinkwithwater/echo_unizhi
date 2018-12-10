file=${1##*/}
export SUB_START=${file%.*}
./skynet/skynet config
exit
