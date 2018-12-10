/**
 *
 * Copyright (C) 2015 by David Lin
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALING IN
 * THE SOFTWARE.
 *
 */
#define LUA_LIB

#include "skynet.h"
#include "skynet_malloc.h"

#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>

#include <lua.h>
#include <lauxlib.h>

#include <netinet/in.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>

#include "ikcp.h"

#define UNPACK_BUFFER_SIZE 4*1024

#define KCP_USER(kcp) ((struct UserInfo*)kcp->user)

#define POLL_EVENT_CLOSE -1
#define POLL_EVENT_MSG 1



// ---------------------- fff {{{ unpack tool-------------------------------
struct UnpackTool {
	int mHead;
	int mSize;
	int mCap;
	char *mBuffer;
};

struct UserInfo{
	int udpFd;
	int udpSocket;
	struct sockaddr_in dstAddr;
	struct UnpackTool unpackTool;
	ikcpcb *prev;
	ikcpcb *next;
	ikcpcb *eventNext;
	int event;
	int waitSend;
	int waitSendIncr;
};

static struct UserInfo* user_create(int udpFd, int udpSocket, const char* dstAddrBuffer){
    struct UserInfo* info = malloc(sizeof(struct UserInfo));
	if(info == NULL){
		return NULL;
	}

	info->udpFd = udpFd;
	info->udpSocket = udpSocket;
	memcpy(&(info->dstAddr), dstAddrBuffer, sizeof(struct sockaddr_in));

	info->waitSend=0;
	info->waitSendIncr=0;

	struct UnpackTool * unpackTool = &(info->unpackTool);
	unpackTool->mHead=0;
	unpackTool->mSize=0;
	unpackTool->mCap=UNPACK_BUFFER_SIZE;
	unpackTool->mBuffer=malloc(UNPACK_BUFFER_SIZE);
	return info;
}

static void user_release(struct UserInfo* userInfo){
	free(userInfo->unpackTool.mBuffer);
	free(userInfo);
}

static char* user_pop(struct UserInfo* userInfo, int *pLen){
	struct UnpackTool * unpackTool = &(userInfo->unpackTool);
	if(unpackTool->mSize>=2){
		int nLen = ((unsigned char)unpackTool->mBuffer[unpackTool->mHead])* 256 + (unsigned char)unpackTool->mBuffer[unpackTool->mHead+1];
		if(unpackTool->mSize>=nLen + 2){

			char * point = unpackTool->mBuffer + unpackTool->mHead + 2;
			*pLen = nLen;

			unpackTool->mHead += (nLen + 2);
			unpackTool->mSize -= (nLen + 2);

			return point;
		}
	}
	return NULL;
}


static int kcp_user_recv(ikcpcb* kcp){
	int nLen = ikcp_peeksize(kcp);
	if(nLen>0){
		struct UnpackTool * unpackTool = &(KCP_USER(kcp)->unpackTool);
		// case 1: mHead=0 & cap enough, just copy
		// case 2: mHead=0 & cap not enough, expand and copy
		// case 3: mHead!=0 & cap enough, shrink and copy
		// case 4: mHead!=0 & cap not enough, expand and copy
		if(unpackTool->mSize + nLen > unpackTool->mCap){
			// expand buffer..
			int nNewCap = unpackTool->mCap;
			while(nNewCap<unpackTool->mSize + nLen){
				nNewCap*=2;
			}
			char *nNewBuffer=malloc(nNewCap);
			memcpy(nNewBuffer, unpackTool->mBuffer + unpackTool->mHead, unpackTool->mSize);

			unpackTool->mHead=0;
			unpackTool->mSize=unpackTool->mSize;
			unpackTool->mCap=nNewCap;
			free(unpackTool->mBuffer);
			unpackTool->mBuffer=nNewBuffer;
		}else if(unpackTool->mHead + unpackTool->mSize + nLen > unpackTool->mCap){
			// shift left
			for(int i=0;i<unpackTool->mSize;i++){
				unpackTool->mBuffer[i]=unpackTool->mBuffer[unpackTool->mHead+i];
			}
			unpackTool->mHead=0;
		}
		nLen = ikcp_recv(kcp, unpackTool->mBuffer + unpackTool->mHead + unpackTool->mSize, nLen);
		//memcpy(unpackTool->mBuffer + unpackTool->mHead + unpackTool->mSize, vBuffer, nLen);
		unpackTool->mSize+=nLen;
	}
	return nLen;
}


// ---------------------- fff }}} -------------------------------


static int kcp_output_callback(const char *buf, int len, ikcpcb *kcp, void *arg) {
    struct UserInfo* info = (struct UserInfo*)arg;

	sendto(info->udpSocket, buf, len, 0, (struct sockaddr *)&(info->dstAddr), sizeof(info->dstAddr));

    return 0;
}

static int lkcp_recv(lua_State* L){
	ikcpcb* kcp = (ikcpcb*)lua_touserdata(L, 1);
	if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
	}

	struct UserInfo* user = KCP_USER(kcp);

	int nInnerLen=0;
	char * nRecvBuffer = user_pop(user, &nInnerLen);
	while(nRecvBuffer==NULL){
		int hr = kcp_user_recv(kcp);
		if(hr>0){
			nRecvBuffer = user_pop(user, &nInnerLen);
		}else{
			break;
		}
	}

	if(nRecvBuffer!=NULL){
		lua_pushinteger(L, nInnerLen);
		lua_pushlstring(L, nRecvBuffer, nInnerLen);
		return 2;
	}else{
		lua_pushinteger(L, 0);
		return 1;
	}
}

static int lkcp_send(lua_State* L){
	ikcpcb* kcp = (ikcpcb*)lua_touserdata(L, 1);
	if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
	}
	size_t size;
	const char *data;

	switch(lua_type(L, 2)) {
	case LUA_TUSERDATA:
	case LUA_TLIGHTUSERDATA:
		data = lua_touserdata(L,2);
		size = luaL_checkinteger(L,3);
		break;
	default:
		data =  luaL_checklstring(L, 2, &size);
		break;
	}
    int32_t hr = ikcp_send(kcp, data, size);
    ikcp_flush(kcp);

    lua_pushinteger(L, hr);
    return 1;
}

// use ptr+4 as input
static int lkcp_input_ptr4(lua_State* L){
	ikcpcb* kcp = (ikcpcb*)lua_touserdata(L, 1);
	if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
	}
	// use ptr instead of string copy !!!
	char * data = lua_touserdata(L, 2);
	int size = luaL_checkinteger(L, 3);
    int32_t hr = ikcp_input(kcp, data + 4, size - 4);

	// call update once
	unsigned int updateTime = luaL_checkinteger(L, 4);
	ikcp_update(kcp, updateTime);

    lua_pushinteger(L, hr);
    return 1;
}

static int lkcp_wndsize(lua_State* L){
	ikcpcb* kcp = (ikcpcb*)lua_touserdata(L, 1);
	if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
	}
    int32_t sndwnd = luaL_checkinteger(L, 2);
    int32_t rcvwnd = luaL_checkinteger(L, 3);
    ikcp_wndsize(kcp, sndwnd, rcvwnd);
    return 0;
}

static int lkcp_setmtu(lua_State* L){
	ikcpcb* kcp = (ikcpcb*)lua_touserdata(L, 1);
	if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
	}
    int32_t mtu = luaL_checkinteger(L, 2);
    ikcp_setmtu(kcp, mtu);
    return 0;
}

static int lkcp_getfd(lua_State* L){
	ikcpcb* kcp = (ikcpcb*)lua_touserdata(L, 1);
	if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
	}
	struct UserInfo * userInfo = KCP_USER(kcp);

    lua_pushinteger(L, userInfo->udpFd);
    return 1;
}

static int lkcp_setaddr(lua_State* L){
	ikcpcb* kcp = (ikcpcb*)lua_touserdata(L, 1);
	if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
	}
	// check addr
	size_t addrLen;
	const char * dstAddrBuffer = luaL_checklstring(L, 2, &addrLen);
	if(kcp->user!=NULL){
		memcpy(&(KCP_USER(kcp)->dstAddr), dstAddrBuffer, sizeof(struct sockaddr_in));
	}
	return 0;
}


/******************************************/

struct PollList {
	int udpSocket;

	ikcpcb *head;
	ikcpcb *tail;
	int size;

	ikcpcb *eventHead;
	ikcpcb *eventTail;

	int waitSendThreshold;
	int waitSendIncrThreshold;
};

static ikcpcb* poll_delete_kcp(struct PollList* poll, ikcpcb* kcp){
	ikcpcb* next = NULL;
	if( poll->head != kcp && poll->tail != kcp ){
		ikcpcb* before = KCP_USER(kcp)->prev;
		ikcpcb* after = KCP_USER(kcp)->next;
		KCP_USER(before)->next = after;
		KCP_USER(after)->prev = before;
		next = after;
	}else if(poll->head == kcp){
		ikcpcb * after = KCP_USER(kcp)->next;
		poll->head = after;
		if(after!=NULL){
			KCP_USER(after)->prev = NULL;
		}else{
			poll->tail = NULL;
		}
		next = after;
	}else if(poll->tail == kcp){
		ikcpcb* before = KCP_USER(kcp)->prev;
		poll->tail = before;
		if(before!=NULL){
			KCP_USER(before)->next = NULL;
		}else{
			poll->head = NULL;
		}
		next = NULL;
	}
	user_release(KCP_USER(kcp));
	kcp->user = NULL;
    ikcp_release(kcp);
	poll->size--;
	return next;
}

static void poll_push(struct PollList *poll, ikcpcb *cur){
	struct UserInfo * curInfo = KCP_USER(cur);
	if(poll->tail==NULL){
		poll->head = cur;
		poll->tail = cur;
		curInfo->prev = NULL;
		curInfo->next = NULL;
	}else{
		ikcpcb *tail = poll->tail;
		struct UserInfo * tailInfo = KCP_USER(tail);

		tailInfo->next= cur;

		curInfo->prev= tail;
		curInfo->next = NULL;

		poll->tail = cur;
	}
	poll->size++;
}

static void poll_push_event(struct PollList *poll, ikcpcb *cur){
	struct UserInfo * curInfo = KCP_USER(cur);
	if(poll->eventTail==NULL){
		poll->eventHead = cur;
		poll->eventTail = cur;
		curInfo->eventNext = NULL;
	}else{
		ikcpcb *tail = poll->eventTail;
		struct UserInfo * tailInfo = KCP_USER(tail);

		tailInfo->eventNext = cur;

		curInfo->eventNext = NULL;

		poll->eventTail = cur;
	}
}

static int lpoll_create(lua_State* L){
	// check udpsocket
	int udpSocket = luaL_checkinteger(L, 1);

	struct PollList* poll = lua_newuserdata(L, sizeof(struct PollList));
    luaL_getmetatable(L, "poll_meta");
    lua_setmetatable(L, -2);

	poll->udpSocket = udpSocket;

	poll->head = NULL;
	poll->tail = NULL;
	poll->size = 0;

	poll->waitSendThreshold = 30;
	poll->waitSendIncrThreshold = 15;

	return 1;
}

static int lpoll_setwaitsendinit(lua_State* L){
	struct PollList* poll = (struct PollList*)luaL_checkudata(L, 1, "poll_meta");
	int value = luaL_checkinteger(L, 2);
	poll->waitSendThreshold = value;
	return 0;
}

static int lpoll_setwaitsendincr(lua_State* L){
	struct PollList* poll = (struct PollList*)luaL_checkudata(L, 1, "poll_meta");
	int value = luaL_checkinteger(L, 2);
	poll->waitSendIncrThreshold = value;
	return 0;
}

static int lpoll_destroy(lua_State* L){
	struct PollList* poll = (struct PollList*)luaL_checkudata(L, 1, "poll_meta");
	ikcpcb* kcp = poll->head;
	while(kcp!=NULL){
		kcp = poll_delete_kcp(poll, kcp);
	}
	return 0;
}


static int lpoll_close_kcp(lua_State* L){
	struct PollList* poll = (struct PollList*)luaL_checkudata(L, 1, "poll_meta");
	ikcpcb* kcp = (ikcpcb*)lua_touserdata(L, 2);
	poll_delete_kcp(poll, kcp);
	return 0;
}

static int lpoll_open_kcp(lua_State* L){
	// check poll
    struct PollList* poll = (struct PollList*)luaL_checkudata(L, 1, "poll_meta");
	// check fd
    int fd = luaL_checkinteger(L, 2);
	// check token
    int32_t conv = luaL_checkinteger(L, 3);

	// check addr
	size_t addrLen;
	const char * dstAddrBuffer = luaL_checklstring(L, 4, &addrLen);

	// create user info
    struct UserInfo* info = user_create(fd, poll->udpSocket, dstAddrBuffer);
    if (info == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: fail to create kcp");
        return 2;
    }

	// create kcp
    ikcpcb* kcp = ikcp_create(conv, (void*)info);
    if (kcp == NULL) {
		user_release(info);
        lua_pushnil(L);
        lua_pushstring(L, "error: fail to create kcp");
        return 2;
    }

    kcp->output = kcp_output_callback;

	// set default parameter
    ikcp_nodelay(kcp, 1, 20, 2, 1);
    ikcp_setmtu(kcp, 1000);
	kcp->stream=1;

	// first time update
	ikcp_update(kcp, 0);

	poll_push(poll, kcp);

	lua_pushlightuserdata(L, kcp);
    return 1;
}

// update kcp & put event into list
static int lpoll_update(lua_State* L){
	struct PollList* poll = (struct PollList*)luaL_checkudata(L, 1, "poll_meta");
	unsigned int updateTime = luaL_checkinteger(L, 2);
	poll->eventHead = NULL;
	poll->eventTail = NULL;
	ikcpcb* kcp = poll->head;
	while(kcp!=NULL){
		ikcp_update(kcp, updateTime);

		// check waitsnd
		struct UserInfo * userInfo = KCP_USER(kcp);
		int waitSend = ikcp_waitsnd(kcp);
		if(waitSend < userInfo->waitSend){
			userInfo->waitSendIncr = 0;
		}else if(waitSend > userInfo->waitSend && waitSend > poll->waitSendThreshold){
			userInfo->waitSendIncr ++;
			if( userInfo->waitSendIncr > poll->waitSendIncrThreshold){
				userInfo->event = POLL_EVENT_CLOSE;
				poll_push_event(poll, kcp);
				kcp = userInfo->next;
				continue;
			}
		}
		userInfo->waitSend = waitSend;

		// check message
		int len = ikcp_peeksize(kcp);
		if(len>0){
			userInfo->event = POLL_EVENT_MSG;
			poll_push_event(poll, kcp);
		}
		kcp = userInfo->next;
	}

	return 0;
}

static int lpoll_select(lua_State* L){
	struct PollList* poll = (struct PollList*)luaL_checkudata(L, 1, "poll_meta");
	ikcpcb* next = NULL;
	if(lua_isnil(L, 2)){
		next = poll->eventHead;
	}else {
		ikcpcb* cur = lua_touserdata(L, 2);
		if(KCP_USER(cur)->event == POLL_EVENT_CLOSE){
			next = poll_delete_kcp(poll, cur);
		}else{
			next = KCP_USER(cur)->next;
		}
	}
	if(next == NULL){
		lua_pushnil(L);
		return 1;
	}else{
		lua_pushlightuserdata(L, next);
		lua_pushinteger(L, KCP_USER(next)->udpFd);
		lua_pushinteger(L, KCP_USER(next)->event);
		return 3;
	}
}

static int lpoll_get_size(lua_State* L){
	struct PollList* poll = (struct PollList*)luaL_checkudata(L, 1, "poll_meta");
	lua_pushinteger(L, poll->size);
	return 1;
}

static const struct luaL_Reg lpoll_methods [] = {
    { "select" , lpoll_select },
    { "update" , lpoll_update },
    { "openKcp" , lpoll_open_kcp },
    { "closeKcp" , lpoll_close_kcp},
    { "size" , lpoll_get_size},
    { "setWaitSendInit" , lpoll_setwaitsendinit},
    { "setWaitSendIncr" , lpoll_setwaitsendincr},
	{NULL, NULL},
};

static void bindPoll(lua_State* L){
    luaL_newmetatable(L, "poll_meta");

    lua_newtable(L);
    luaL_setfuncs(L, lpoll_methods, 0);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, lpoll_destroy);
    lua_setfield(L, -2, "__gc");
}

/******************************************/

static const struct luaL_Reg l_methods[] = {
    { "lkcp_recv" , lkcp_recv },
    { "lkcp_send" , lkcp_send },
    { "lkcp_input_ptr4" , lkcp_input_ptr4 },

    { "lkcp_wndsize" , lkcp_wndsize },
    { "lkcp_setmtu" , lkcp_setmtu },
    { "lkcp_getfd" , lkcp_getfd},
    { "lkcp_setaddr" , lkcp_setaddr},

    { "lpoll_create" , lpoll_create},

    {NULL, NULL},
};

LUAMOD_API int luaopen_pollkcp(lua_State* L) {
    luaL_checkversion(L);

	bindPoll(L);

    luaL_newlib(L, l_methods);
	ikcp_allocator(malloc, free);


    return 1;
}

