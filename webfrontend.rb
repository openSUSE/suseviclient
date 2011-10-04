require 'rubygems'
require 'sinatra'
require 'rack-flash'

use Rack::Flash

helpers do
    include Rack::Utils
    alias_method :h, :escape_html
end

class VM
  attr_accessor :vmid, :name, :pwstate, :config
end

enable :sessions

HOSTNAME=`hostname -f`.chomp()

def vmlist
clist = `./suseviclient.sh -s "#{session[:server]}"  -l`
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
  @serverlist = File.open('./serverlist.conf')
	if session[:server].nil? 
	session[:server] = @serverlist.gets.chomp()
	@serverlist.pos = 0
  end
  
  vmlist
  @title = 'Virtual Machines List'
	session[:vmarray] = @vmarray
  erb :home
end

post '/' do
  if params[:vmname] == ''
  flash[:error] = "<li>VM name should be specified</li>"
  end
  
  if params[:memory] == ''
  flash[:error] = "#{flash[:error]}" + "<li>Memory should be specified</li>"
  end

  redirect '/' if  (! flash[:error].nil? or flash[:error])
  halt "WTF - #{params[:vmname]}"
  if params[:creation_type] == "pxe"
    `./suseviclient.sh -s #{session[:server]} -c -n "#{params[:vmname]}" -m "#{params[:memory]}" -d "#{params[:disksize]}G --novncpass"` 
  elsif params[:creation_type] == "iso"
    `./suseviclient.sh -s #{session[:server]} -c -n "#{params[:vmname]}" -m "#{params[:memory]}" -d "#{params[:disksize]}G" --iso "#{params[:pathtoimage]}" --novncpass` 
  elsif params[:creation_type] == "studio"
    `./suseviclient.sh -s #{session[:server]} -c -n "#{params[:vmname]}" --studio "#{params[:appliance_id]}" --novncpass` 
  else
    "I have no idea what's happening"
  end

  redirect '/'

end

get '/:vmid/console' do
  vnc_port=`./suseviclient.sh -s #{session[:server]} --showvncport #{params[:vmid]}`.chomp()
	if $?.to_i != 0 
		halt 'Seem that VNC is not enabled on this virtual machine'
  end
  system "python ./utils/wsproxy.py -D #{vnc_port} #{session[:server]}:#{vnc_port}"
  redirect "/vnc_auto.html?host=#{HOSTNAME}&port=#{vnc_port}"
end

get '/:vmid/power/*' do
  if (params[:splat].last == 'on')
    `./suseviclient.sh -s #{session[:server]} --poweron "#{params[:vmid]}"`
  elsif (params[:splat].last == "off")
    `./suseviclient.sh -s "#{session[:server]}" --poweroff "#{params[:vmid]}"`
  else
    "No such power action #{params[:splat]}"
  end

  redirect '/'

end

put '/' do
 session[:server] = params[:server].chomp()
 redirect '/' 
end

get '/:id' do
  @vm = session[:vmarray].find { |vm| vm.vmid == "#{params[:id]}" }
  @title = "Edit VM  ##{params[:id]}"
  erb :edit
end

put '/:id' do
  `./suseviclient.sh -s #{session[:server]} -e "#{params[:id]}" -n "#{params[:name].chomp()}"`
  redirect '/'
end

