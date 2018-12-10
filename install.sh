git submodule update --init
cd skynet
if [ $system_name == "Darwin" ]; then
	make mac
elif [ $system_name == "Linux" ]; then
	make linux
fi
cd ..
