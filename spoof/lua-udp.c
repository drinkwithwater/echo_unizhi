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

const char recvBuffer[2100];

// lcreate_server(port)
// ip use default 0.0.0.0
static int lcreate_server(lua_State *L){
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
static int lcreate_client(lua_State *L){
	int fd = socket(AF_INET, SOCK_DGRAM, 0);
	int flag = fcntl(fd, F_GETFL, 0);
	fcntl(fd, F_SETFL, flag | O_NONBLOCK);
	lua_pushinteger(L, fd);
	return 1;
}

// close(fd)
static int lclose(lua_State *L){
	int fd = luaL_checkinteger(L, 1);
	close(fd);
	return 0;
}

// sendto(fd,addrstr,buffer)
static int lsendto(lua_State *L){
	int vFd = luaL_checkinteger(L, 1);

	struct sockaddr_in *vDstAddr = (struct sockaddr_in *)luaL_checkudata(L, 2, "addr_meta");

	size_t vLen;
	const char *vBuffer=luaL_checklstring(L, 3, &vLen);

	sendto(vFd, vBuffer, vLen, 0, (struct sockaddr *)vDstAddr, IPV4_ADDR_SIZE);
	return 0;
}

// return len, buffer, addr
static int lrecvfrom(lua_State *L){
	int vFd = luaL_checkinteger(L, 1);

	struct sockaddr_in nRecvAddr;
	socklen_t nAddrLen = IPV4_ADDR_SIZE;
	int nRecvLen = recvfrom(vFd, (void*)recvBuffer, 2048, 0, (struct sockaddr *)&nRecvAddr, &nAddrLen);

	if(nRecvLen>0){
		struct sockaddr_in *nAddr = (struct sockaddr_in *)lua_newuserdata(L, IPV4_ADDR_SIZE);
		luaL_getmetatable(L, "addr_meta");
		lua_setmetatable(L, -2);
		nAddr->sin_addr.s_addr=nRecvAddr.sin_addr.s_addr;
		nAddr->sin_family=nRecvAddr.sin_family;
		nAddr->sin_port=nRecvAddr.sin_port;
		lua_pushlstring(L, recvBuffer, nRecvLen);
		return 2;
	}else{
		return 0;
	}
}

/********************************************************/
/** socket addr *****************************************/
/********************************************************/

static int laddr(lua_State *L){
	size_t vLen;
	const char *vIP = luaL_checklstring(L, 1, &vLen);
	int vPort = luaL_checkinteger(L, 2);

    struct sockaddr_in *nAddr = (struct sockaddr_in *)lua_newuserdata(L, IPV4_ADDR_SIZE);
	nAddr->sin_addr.s_addr=inet_addr(vIP);
	nAddr->sin_family=AF_INET;
	nAddr->sin_port=htons(vPort);

    luaL_getmetatable(L, "addr_meta");
    lua_setmetatable(L, -2);
	return 1;
}

static int laddr_get(lua_State *L){
	struct sockaddr_in *nAddr = luaL_checkudata(L, 1, "addr_meta");
	size_t vLen;
	const char *vKey = luaL_checklstring(L, 2, &vLen);
	if(strcmp(vKey, "ip") == 0){
		lua_pushstring(L, inet_ntoa(nAddr->sin_addr));
		return 1;
	}else if(strcmp(vKey, "port") == 0){
		lua_pushinteger(L, ntohs(nAddr->sin_port));
		return 1;
	}else{
		return 0;
	}
}

static int laddr_tostring(lua_State *L){
	struct sockaddr_in *nAddr = luaL_checkudata(L, 1, "addr_meta");
	char nTemp[100];
	sprintf(nTemp, "%s:%d", inet_ntoa(nAddr->sin_addr), ntohs(nAddr->sin_port));
	lua_pushstring(L, nTemp);
	return 1;
}

/*************************/

static int lusleep(lua_State *L){
	int usecond = luaL_checkinteger(L, 1);
	usleep(usecond);
	return 0;
}

static const struct luaL_Reg l_methods[] = {
    { "create_server" , lcreate_server},
    { "create_client" , lcreate_client},
    { "close" , lclose},
    { "sendto" , lsendto},
    { "recvfrom" , lrecvfrom},
    { "addr" , laddr},
    { "usleep" , lusleep},
    {NULL, NULL},
};

LUAMOD_API int luaopen_udp(lua_State* L) {
    luaL_checkversion(L);


    luaL_newmetatable(L, "addr_meta");
    lua_pushcfunction(L, laddr_get);
    lua_setfield(L, -2, "__index");
    //lua_pushcfunction(L, laddr_set);
    //lua_setfield(L, -2, "__newindex");
    lua_pushcfunction(L, laddr_tostring);
    lua_setfield(L, -2, "__tostring");

    luaL_newlib(L, l_methods);

    return 1;
}

