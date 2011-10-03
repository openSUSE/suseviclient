require 'rubygems'
require 'sinatra'

helpers do
    include Rack::Utils
    alias_method :h, :escape_html
end

class VM
  attr_accessor :vmid, :name, :pwstate, :config
end


SERVER="thessalonike.suse.de"
HOSTNAME=`hostname -f`.chomp()

def vmlist
clist = `./suseviclient.sh -s "#{SERVER}"  -l`
@finallist=""
i=0
num = ARGV[0]
@vmarray = []
clist.each_line  do |line|
  i += 1
  next if i <= 3
  line = line.gsub(/\ {2,}/, "\t")
  columns = line.split("\t")

  @vmarray << VM.new
  @vmarray.last.pwstate = columns[0]
  @vmarray.last.vmid = columns[1]
  @vmarray.last.name = columns[2]
  @vmarray.last.config = columns[3]
end
end

get '/' do
  vmlist
  @title = 'Virtual Machines List'
  erb :home
end

post '/' do
  if params[:creation_type] == "pxe"
    `./suseviclient.sh -s #{SERVER} -c -n "#{params[:vmname]}" -m "#{params[:memory]}" -d "#{params[:disksize]}G --novncpass"` 
  elsif params[:creation_type] == "iso"
    `./suseviclient.sh -s #{SERVER} -c -n "#{params[:vmname]}" -m "#{params[:memory]}" -d "#{params[:disksize]}G" --iso "#{params[:pathtoimage]}" --novncpass` 
  elsif params[:creation_type] == "studio"
    `./suseviclient.sh -s #{SERVER} -c -n "#{params[:vmname]}" --studio "#{params[:appliance_id]}" --novncpass` 
  else
    "I have no idea what's happening"
  end

  redirect '/'

end

get '/:vmid/console' do
  vnc_port=`./suseviclient.sh -s #{SERVER} --showvncport #{params[:vmid]}`.chomp()
  system "python ./utils/wsproxy.py -D #{vnc_port} #{SERVER}:#{vnc_port}"
  redirect "/vnc_auto.html?host=#{HOSTNAME}&port=#{vnc_port}"
end

get '/:vmid/power/*' do
  if (params[:splat].last == 'on')
    `./suseviclient.sh -s #{SERVER} --poweron "#{params[:vmid]}"`
  elsif (params[:splat].last == "off")
    `./suseviclient.sh -s "#{SERVER}" --poweroff "#{params[:vmid]}"`
  else
    "No such power action #{params[:splat]}"
  end

  redirect '/'

end
