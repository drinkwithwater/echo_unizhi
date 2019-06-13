#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <linux/if_ether.h>
#include <arpa/inet.h>


#define FAKE_IP "127.0.0.1"
#define FAKE_PORT 8000
#define DST_IP "127.0.0.1"
#define DST_PORT 5001
#define LOCAL_PORT 12306

int main(){
    int fd = socket (AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if(fd < 0)
    {
        //socket creation failed, may be because of non-root privileges
        perror("Failed to create socket");
        exit(1);
    }

	struct sockaddr_in bind_addr;
	memset(&bind_addr, 0, sizeof(bind_addr));
	bind_addr.sin_family = AF_INET;
	bind_addr.sin_addr.s_addr = htonl(INADDR_ANY);
	bind_addr.sin_port = htons(LOCAL_PORT);

	struct sockaddr_in dst_addr;
	memset(&dst_addr, 0, sizeof(bind_addr));
	dst_addr.sin_family = AF_INET;
	inet_aton(DST_IP, &dst_addr.sin_addr);
	dst_addr.sin_port = htons(DST_PORT);

	int ret = bind(fd, (struct sockaddr*)&bind_addr, sizeof(bind_addr));
	if (ret < 0){
        perror("Failed to bind socket");
        exit(1);
	}

    unsigned char *buffer = (unsigned char *)malloc(65536);

	struct sockaddr_in src_addr;

    while(1) {
		struct sockaddr_in addr;
		socklen_t addrlen;
		int packet_size;
		packet_size = recvfrom(fd, buffer , 65536 , 0 , (struct sockaddr*)&addr, &addrlen);
		if (packet_size == -1) {
			printf("Failed to get packets\n");
			return 1;
		}

		if(ntohs(addr.sin_port) == DST_PORT) {
			// if packet's srcip is dst, send to src
			sendto(fd, buffer, packet_size, 0, (struct sockaddr*)&src_addr, sizeof(src_addr));
		}else {
			memcpy(&src_addr, &addr, sizeof(src_addr));
			sendto(fd, buffer, packet_size, 0, (struct sockaddr*)&dst_addr, sizeof(dst_addr));
		}

		/*printf("Incoming Packet: \n");
		printf("Packet Size (bytes): %d\n", packet_size);
		printf("Source Address: %s\n", (char *)inet_ntoa(addr.sin_addr));
		printf("Identification: %d\n\n", ntohs(addr.sin_port));*/
	}

	free(buffer);
	return 0;
}
