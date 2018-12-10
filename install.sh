git clone https://github.com/cloudwu/skynet
cd skynet
if [ $system_name == "Darwin" ]; then
	make mac
elif [ $system_name == "Linux" ]; then
	make linux
fi
cd ..
