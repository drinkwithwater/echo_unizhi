

local udp = require "udp"

local dst = udp.addr("127.0.0.1", 12306)

--local fd1 = udp.create_client()
--local fd2 = udp.create_client()

--local clientlist = {fd1, fd2}

local word = "abcde"
for j = 1, 2 do
	local clientfd = udp.create_client()
	for i=1, 2 do
		local buffer = word:rep(i)
		udp.sendto(clientfd, dst, buffer)

		while true do
			local addr, recv = udp.recvfrom(clientfd)
			if addr then
				if recv ~= buffer then
					print(i, buffer, recv)
				else
					print(i, addr)
				end
				break
			end
		end

		udp.usleep(10000)
	end
	udp.close(clientfd)
end

