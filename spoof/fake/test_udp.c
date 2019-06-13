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


#define MAX_DATA_SIZE 1024


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


int fakesend(void)
{
    int raw_sock;
    uint8_t packet[ETH_DATA_LEN];
    uint8_t udp_packet[ETH_DATA_LEN];
    uint8_t data[MAX_DATA_SIZE];
    char *sending_data = "AAAAAAAA";
    char *localhost = "127.0.0.1";
    char *srchost = "65.65.65.65";
    unsigned int packet_size;
    unsigned int data_size;
    struct sockaddr_in src_addr;
    struct sockaddr_in dst_addr;

    src_addr.sin_family = AF_INET;
    src_addr.sin_port = htons(12312);
    inet_aton(srchost, &src_addr.sin_addr);

    dst_addr.sin_family = AF_INET;
    dst_addr.sin_port = htons(10086);
    inet_aton(localhost, &dst_addr.sin_addr);

    strcpy((char *)data, sending_data);
    data_size = strlen(sending_data);

    printf("[+] Build UDP packet...\n\n");
    packet_size = build_udp_packet(src_addr, dst_addr, udp_packet, data, data_size);
    hexdump(udp_packet, packet_size);
    printf("\n\n");

    printf("[+] Build IP packet...\n\n");
    packet_size = build_ip_packet(src_addr.sin_addr, dst_addr.sin_addr, IPPROTO_UDP, packet, udp_packet, packet_size);
    hexdump(packet, packet_size);
    printf("\n\n");

    printf("[+] Send UDP packet...\n");
    if((raw_sock = socket(AF_INET, SOCK_RAW, IPPROTO_RAW)) < 0){
        perror("socket");
        exit(1);
    }
    send_udp_packet(raw_sock, src_addr, dst_addr, data, data_size);

    return 0;
}

#define FAKE_IP "127.0.0.1"
#define FAKE_PORT 8000
#define DST_IP "127.0.0.1"
#define DST_PORT 8000
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
	memset(&bind_addr, 0, sizeof(bind_addr));
	bind_addr.sin_family = AF_INET;
	bind_addr.sin_addr.s_addr = htonl(DST_IP);
	bind_addr.sin_port = htons(DST_PORT);

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
			sendto(fd, buffer, packet_size, 0, (struct sockaddr*)&src_addr, sizeof(src_addr));
		}else {
			memcpy(&addr, &src_addr, sizeof(src_addr));
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
