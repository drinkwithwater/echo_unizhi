#define LUA_LIB
#include "skynet.h"
#include "skynet_malloc.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include <lua.h>
#include <lauxlib.h>

#include <netinet/in.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <unistd.h>

#define BUFFER_SIZE 2048

#define IPV4_ADDR_SIZE (sizeof(struct sockaddr_in))

const char recvBuffer[2100];


void left(struct sockaddr_in *addr, char * buffer){
	memcpy(addr, buffer, sizeof(struct sockaddr_in));
}

void right(struct sockaddr_in *addr, char* buffer){
	memcpy(buffer, addr, sizeof(struct sockaddr_in));
}

// lcreate(port)
// ip use default 0.0.0.0
static int lcreate(lua_State *L){
	int port = luaL_checkinteger(L, 1);

	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	if(fd<0){
		return 0;
	}

	struct sockaddr_in addr;

	addr.sin_addr.s_addr=htonl(INADDR_ANY);
	addr.sin_family=AF_INET;
	addr.sin_port=htons(port);

	int err = bind(fd, (struct sockaddr*)&addr, IPV4_ADDR_SIZE);
	if(err<0){
		close(fd);
		return 0;
	}
	int flag = fcntl(fd, F_GETFL, 0);
	fcntl(fd, F_SETFL, flag | O_NONBLOCK);
	lua_pushinteger(L, fd);
	return 1;
}

// create a client udp socket
static int lcreateclient(lua_State *L){
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	int flag = fcntl(fd, F_GETFL, 0);
	fcntl(fd, F_SETFL, flag | O_NONBLOCK);
	lua_pushinteger(L, fd);
	return 1;
}

static int lclose(lua_State *L){
	int fd = luaL_checkinteger(L, 1);
	close(fd);
	return 0;
}

// sendto(fd,addrstr,buffer)
static int lsendto(lua_State *L){
	int fd = luaL_checkinteger(L, 1);

	size_t vAddrLen;
	struct sockaddr_in *dst_addr = (struct sockaddr_in *)luaL_checklstring(L, 2, &vAddrLen);

	size_t vLen;
	const char *vBuffer=luaL_checklstring(L, 3, &vLen);

	int re = sendto(fd, vBuffer, vLen, 0, (struct sockaddr *)dst_addr, IPV4_ADDR_SIZE);
	lua_pushinteger(L, re);
	return 1;
}

// sendtoipport(fd,buffer,ip,port)
static int lsendtoipport(lua_State *L){
	int fd = luaL_checkinteger(L, 1);
	size_t vLen;
	const char *vBuffer=luaL_checklstring(L, 2, &vLen);

	const char * addr = luaL_checkstring(L, 3);
	int port = luaL_checkinteger(L, 4);

	struct sockaddr_in my_addr;

	my_addr.sin_addr.s_addr=inet_addr(addr);
	my_addr.sin_family=AF_INET;
	my_addr.sin_port=htons(port);

	int re = sendto(fd, vBuffer, vLen, 0, (struct sockaddr *) &my_addr, IPV4_ADDR_SIZE);
	lua_pushinteger(L, re);
	return 1;
}

void* mPointerBuffer = NULL;
static int lrecvfrom_ptr(lua_State *L){
	int fd = luaL_checkinteger(L, 1);

	struct sockaddr_in my_addr;
	socklen_t addrlen = IPV4_ADDR_SIZE;

	if(!mPointerBuffer){
		mPointerBuffer = skynet_malloc(BUFFER_SIZE);
	}

	int recvLen = recvfrom(fd, mPointerBuffer, BUFFER_SIZE, 0, (struct sockaddr *)&my_addr, &addrlen);

	if(recvLen>0){
		lua_pushinteger(L, recvLen);
		lua_pushlightuserdata(L, mPointerBuffer);
		lua_pushlstring(L, (char *)&my_addr, IPV4_ADDR_SIZE);

		mPointerBuffer = NULL;
		return 3;
	}else{
		lua_pushinteger(L, recvLen);
		return 1;
	}
}

// return len, buffer, addr
static int lrecvfrom(lua_State *L){
	int fd = luaL_checkinteger(L, 1);

	struct sockaddr_in my_addr;
	socklen_t addrlen = IPV4_ADDR_SIZE;
	int recvLen = recvfrom(fd, (void*)recvBuffer, 2048, 0, (struct sockaddr *)&my_addr, &addrlen);

	if(recvLen>0){
		lua_pushinteger(L, recvLen);
		lua_pushlstring(L, recvBuffer, recvLen);
		lua_pushlstring(L, (char *)&my_addr, IPV4_ADDR_SIZE);
		return 3;
	}else{
		lua_pushinteger(L, recvLen);
		return 1;
	}
}

static int ludp_address(lua_State *L){
	size_t vLen;

	struct sockaddr_in *my_addr = (struct sockaddr_in *)luaL_checklstring(L, 1, &vLen);

	lua_pushinteger(L, my_addr->sin_addr.s_addr);
	lua_pushinteger(L, my_addr->sin_port);
	return 2;
}

static int lptrunpack_littleIII(lua_State *L){
	unsigned char * ptr = lua_touserdata(L, 1);
	for(int i=0;i<3;i++){
		unsigned int cur = 0;
		for(int j=3;j>=0;j--){
			cur *= 256;
			cur += ptr[j];
		}
		lua_pushinteger(L, cur);
		ptr = ptr + 4;
	}
	return 3;
}

static const struct luaL_Reg l_methods[] = {
    { "lcreate" , lcreate},
    { "lcreateclient" , lcreateclient},
    { "close" , lclose},
    { "sendto" , lsendto},
    { "sendtoipport" , lsendtoipport},
    { "recvfrom" , lrecvfrom},
    { "recvfrom_ptr" , lrecvfrom_ptr},
    { "udp_address" , ludp_address},
    { "ptrunpack_littleIII" , lptrunpack_littleIII},
    {NULL, NULL},
};

LUAMOD_API int luaopen_testudp(lua_State* L) {
    luaL_checkversion(L);

    luaL_newlib(L, l_methods);

    return 1;
}

