#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <linux/if_ether.h>
#include <arpa/inet.h>

#include "udp.h"

void hexdump(unsigned char *data, unsigned int data_bytes)
{
    int bin_p, ascii_p;

    bin_p = ascii_p = 0;

    while(bin_p < data_bytes){
        int j;
        int whitespaces;
        for(j = 0; j < 8 && bin_p < data_bytes; j++){
            printf("%02x ", data[bin_p++]);
        }

        whitespaces = (8 - j) * 3;
        for(j = 0; j < whitespaces; j++){
            printf(" ");
        }

        for(j = 0; j < 8 && ascii_p < data_bytes; j++){
            if(isprint(data[ascii_p])){
                printf("%c", data[ascii_p++]);
            }else{
                printf(".");
                ascii_p++;
            }
        }

        printf("\n");
    }
}

#define FAKE_IP "65.65.65.65"
#define FAKE_PORT 12306

int fakesend(int raw_sock, uint8_t *data, unsigned int data_size, struct sockaddr_in dst_addr)
{
    char *srchost = FAKE_IP;
    struct sockaddr_in src_addr;

    src_addr.sin_family = AF_INET;
    src_addr.sin_port = htons(FAKE_PORT);
    inet_aton(srchost, &src_addr.sin_addr);

    //packet_size = build_udp_packet(&src_addr, &dst_addr, udp_packet, data, data_size);

    //packet_size = build_ip_packet(&src_addr.sin_addr, &dst_addr.sin_addr, IPPROTO_UDP, packet, udp_packet, packet_size);

    send_udp_packet(raw_sock, &src_addr, &dst_addr, data, data_size);

    return 0;
}

#define DST_IP "54.180.49.100"
#define DST_PORT 10085
//#define DST_IP "127.0.0.1"
//#define DST_PORT 5001
#define LOCAL_PORT 12306


int main(){
	int raw_fd;
    if((raw_fd = socket(AF_INET, SOCK_RAW, IPPROTO_RAW)) < 0){
        perror("socket failed");
        exit(1);
    }

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
		socklen_t addrlen = sizeof(addr);
		int packet_size;
		packet_size = recvfrom(fd, buffer , 65536 , 0 , (struct sockaddr*)&addr, &addrlen);
		if (packet_size == -1) {
			printf("Failed to get packets\n");
			return 1;
		}

		if(packet_size > 0){
			printf("yes, recv sth\n");

			//send_udp_packet(raw_fd, &addr, &addr, buffer, packet_size);
			fakesend(raw_fd, buffer, packet_size, addr);
			/*if(addr.sin_port == dst_addr.sin_port && memcmp(&addr.sin_addr, &dst_addr.sin_addr, sizeof(addr.sin_addr)) == 0) {
				printf("try spoofing\n");
				// if packet's srcip is dst, send to src
				//sendto(fd, buffer, packet_size, 0, (struct sockaddr*)&src_addr, sizeof(src_addr));
				fakesend(raw_fd, buffer, packet_size, addr);
			}else {
				printf("not spoofing\n");
				//memcpy(&src_addr, &addr, sizeof(src_addr));
				fakesend(raw_fd, buffer, packet_size, addr);
				//send_udp_packet(raw_fd, &addr, &addr, buffer, packet_size);
				//sendto(fd, buffer, packet_size, 0, (struct sockaddr*)&addr, sizeof(addr));
			}*/
		}

		printf("Incoming Packet: \n");
		printf("Packet Size (bytes): %d\n", packet_size);
		printf("Source Address: %s\n", (char *)inet_ntoa(addr.sin_addr));
		printf("Identification: %d\n\n", ntohs(addr.sin_port));
	}

	free(buffer);
	return 0;
}
