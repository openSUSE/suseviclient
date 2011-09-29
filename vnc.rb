#!/usr/bin/env ruby

#This is optional addon to suseviclient.sh.
#It enables us to pass keystrokes to VM and automate custom scenarios
#To use it you have to install ruby-vnc:
#gem install ruby-vnc

require 'rubygems'
require 'net/vnc'

if ARGV[0] == nil or ARGV[0] == '--help'
  puts "Usage:
  ./vnc.rb <server> <port> <password> <string_to_pass_to_server>"
  exit
end

server, port, password, string = ARGV

port=port[2,3]

#keystrokes = "netsetup=dhcp autoyast=http://users.suse.cz/~ytsarev/tiny.xml".chars.to_a
keystrokes = string.chars.to_a

vnccode = "vnc.type '"
counter = 0

for character in keystrokes
  if "#{character}" == ":"
  vnccode += "'
    vnc.key_down :shift
    vnc.key_down ':' 
    vnc.key_up :shift
    sleep 1
    vnc.type '"
  elsif character == "~"
	vnccode += "'
	vnc.key_down :shift
	vnc.key_down '`'
	vnc.key_up :shift
	sleep 1
	vnc.type '"
  else
   vnccode += "#{character}"
  end
	
  counter+=1
	
  if (counter % 13) == 0
    vnccode += "'
    sleep 1
    vnc.type '"
  end
  if counter == keystrokes.length
    vnccode += "'"
  end
end		

#puts vnccode


Net::VNC.open "#{server}:#{port}", :shared => false, :password => password do |vnc|
  vnc.key_press :down
  eval(vnccode)
  vnc.key_press :return
end
