# Many socket methods were not implemented.  This test case gathers several
# sample bits of code that exercise the socket interface.

require 'socket'

###############################################
# Example from UDPSocket
###############################################
s1 = UDPSocket.new
s1.bind("127.0.0.1", 0)
s2 = UDPSocket.new
s2.bind("127.0.0.1", 0)
s2.connect(*s1.addr.values_at(3,1))
s1.connect(*s2.addr.values_at(3,1))
s1.send "aaa", 0
IO.select([s2])
p s2.recvfrom_nonblock(10)  #=> ["aaa", ["AF_INET", 33302, "localhost.localdomain", "127.0.0.1"]]

###############################################
# Example from Socket#recv_nonblock
###############################################
serv = TCPServer.new("127.0.0.1", 0)
af, port, host, addr = serv.addr
c = TCPSocket.new(addr, port)
s = serv.accept
c.send "aaa", 0
IO.select([s])
p s.recv_nonblock(10) #=> "aaa"

###############################################
# Example from Socket#bind
###############################################
socket = Socket.new( Socket::AF_INET, Socket::SOCK_STREAM, 0 )
socket.setsockopt( Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true )
sock_addr = Socket.pack_sockaddr_in( 5555, '127.0.0.1' )
socket.bind( sock_addr )
# sd.listen( 50 ) # 5 is what you see in all the books. Ain't enough.

###############################################
# Example from Socket#accept_nonblock
###############################################

# accept_nonblock is defined and works, but in this case, the problem is
# Errno::EWOULDBLOCK is undefined.  MagLev raises SocketErrorEAGAIN instead
# of Errno::EWOULDBLOCK.
serv = TCPServer.new(2202)
begin
  sock = serv.accept_nonblock
rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
# rescue Exception => e
  #  puts "caught #{e.inspect}"
  puts "Ok"
  # IO.select([serv])
  # retry
end
# sock is an accepted socket.

###############################################
# Example from UNIXServer#accept
###############################################
serv = UNIXServer.new("/tmp/sock")
begin
  sock = serv.accept_nonblock
rescue Errno::EAGAIN, Errno::EWOULDBLOCK, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINTR
  puts "OK"
  # Comment out rest of example so we don't block...
  # IO.select([serv])
  # retry
ensure
  File.delete("/tmp/sock")
end

