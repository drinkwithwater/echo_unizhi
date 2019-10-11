
local udp = require "udp"

local dst = udp.addr("127.0.0.1", 8000)

serverfd = udp.create_server(8000)
clientfd = udp.create_client()

udp.sendto(clientfd, dst, "jklfdjsldfs")

print(udp.recvfrom(serverfd))

udp.close(serverfd)
udp.close(clientfd)
