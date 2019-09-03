#define LUA_LIB

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

#include "udp.h"

// lcreate_server(port)
// ip use default 0.0.0.0
static int lcreate(lua_State *L){
	int raw_fd = socket(AF_INET, SOCK_RAW, IPPROTO_RAW);
    if(raw_fd < 0){
		return 0;
    }

	lua_pushinteger(L, raw_fd);
	return 1;
}

// close(fd)
static int lclose(lua_State *L){
	int fd = luaL_checkinteger(L, 1);
	close(fd);
	return 0;
}

// sendto(fd,srcaddr,dstaddr,buffer)
static int lsendspoof(lua_State *L){
	int vFd = luaL_checkinteger(L, 1);

	struct sockaddr_in *vSrcAddr = (struct sockaddr_in *)lua_touserdata(L, 2);
	struct sockaddr_in *vDstAddr = (struct sockaddr_in *)lua_touserdata(L, 3);

	size_t vLen;
	const char *vBuffer = luaL_checklstring(L, 4, &vLen);

    send_udp_packet(vFd, vSrcAddr, vDstAddr, vBuffer, vLen);
	return 0;
}

static const struct luaL_Reg l_methods[] = {
    { "create" , lcreate},
    { "close" , lclose},
    { "sendspoof" , lsendspoof},
    {NULL, NULL},
};

LUAMOD_API int luaopen_spoof(lua_State* L) {
    luaL_checkversion(L);


    luaL_newlib(L, l_methods);

    return 1;
}

