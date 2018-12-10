git submodule update --init

cd skynet
make linux
cd ..

cd lualib-src
make
cd ..
