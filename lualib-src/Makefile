CC ?= gcc


LUA_INC ?= ../skynet/3rd/lua
BUILD_PATH ?= ../luaclib

CFLAGS = -Wl,-E -g -O2 -Wall -I$(LUA_INC)
SHARED = -fPIC --shared


# skynet

LUA_CLIB = pollkcp lkcp testudp

all : \
  $(foreach v, $(LUA_CLIB), $(BUILD_PATH)/$(v).so)


$(BUILD_PATH) :
	mkdir $(BUILD_PATH)

$(BUILD_PATH)/lkcp.so : lua-lkcp.c kcp/ikcp.c | $(BUILD_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -I$(SKYNET_ROOT)/skynet-src -Ikcp

$(BUILD_PATH)/pollkcp.so : lua-pollkcp.c kcp/ikcp.c | $(BUILD_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -I$(SKYNET_ROOT)/skynet-src -Ikcp

$(BUILD_PATH)/testudp.so : lua-testudp.c | $(BUILD_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -I$(SKYNET_ROOT)/skynet-src

show:
	echo cc=$(CC)
	echo flags=$(CFLAGS)
	echo shared=$(SHARED)

clean :
	rm -f $(BUILD_PATH)/*.so

