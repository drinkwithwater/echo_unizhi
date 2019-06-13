CC ?= gcc

BUILD_PATH=./bin
all : $(BUILD_PATH)/fake $(BUILD_PATH)/normal

#all : $(BUILD_PATH)/normal


$(BUILD_PATH) :
	mkdir $(BUILD_PATH)

$(BUILD_PATH)/fake : fake/fake.c fake/udp.c | $(BUILD_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -I./fake

$(BUILD_PATH)/normal : normal/normal.c | $(BUILD_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@

clean :
	rm -rf $(BUILD_PATH)

