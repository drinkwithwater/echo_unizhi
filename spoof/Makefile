CC ?= gcc

BUILD_PATH=./bin

SKYNET_ROOT = ../skynet
LUA_INC ?= $(SKYNET_ROOT)/3rd/lua

CFLAGS = -Wl,-E -g -O2 -Wall -I$(LUA_INC)
SHARED = -fPIC --shared

all : $(BUILD_PATH)/fake $(BUILD_PATH)/normal

#all : $(BUILD_PATH)/normal


$(BUILD_PATH) :
	mkdir $(BUILD_PATH)

$(BUILD_PATH)/fake : fake/fake.c fake/udp.c | $(BUILD_PATH)
	$(CC) $^ -o $@ -I./fake

$(BUILD_PATH)/normal : normal/normal.c | $(BUILD_PATH)
	$(CC) $^ -o $@

$(BUILD_PATH)/udp.so : lua-udp.c | $(BUILD_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@

$(BUILD_PATH)/spoof.so : lua-spoof.c fake/udp.c | $(BUILD_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -I./fake

clean :
	rm -rf $(BUILD_PATH)
