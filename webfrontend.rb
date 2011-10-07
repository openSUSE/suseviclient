require 'rubygems'
require 'sinatra'
require 'rack-flash'

use Rack::Session::Pool
use Rack::Flash

helpers do
    include Rack::Utils
    alias_method :h, :escape_html
end

class VM
  attr_accessor :vmid, :name, :pwstate, :config, :memory, :disksize, :datastore

  def validate(params)
 
  if params[:vmname] == '' or not params[:vmname] =~ /^[A-Za-z0-9 ]{1,20}$/
      errorpool = "#{errorpool}" "<li>VM name should be specified and consist of no more then 20 alphanumeric characters</li>"
  end


  if params[:memory] == '' or not params[:memory] =~ /^[0-9]{1,6}$/
  errorpool = "#{errorpool}" + "<li>Memory should be specified and be an integer value</li>"
  end

  if params[:disksize] == '' or not params[:disksize] =~ /^[0-9]{1,6}$/
  errorpool = "#{errorpool}" + "<li>Disk size  should be specified and be an integer value</li>"
  end
 
  if params[:datastore] == '' or not params[:datastore] =~ /^[A-Za-z0-9]{1,20}$/
      errorpool = "#{errorpool}" "<li>Datastore should be specified and consist of no more then 20 alphanumeric characters</li>"
  end

 
  errorpool   
  end
  
  def create(server,type, pathtoiso, pathtovmdk, applianceid)
    if type == "pxe"
      `./suseviclient.sh -s "#{server}" -c -n "#{name}" -m "#{memory}" -d "#{disksize}G" --ds "#{datastore}" --novncpass` 
    elsif type == "iso"
      `./suseviclient.sh -s "#{server}" -c -n "#{name}" -m "#{memory}" -d "#{disksize}G" --ds "#{datastore}" --iso "#{pathtoiso}" --novncpass`
    elsif type == "vmdk"
      `./suseviclient.sh -s "#{server}" -c -n "#{name}" -m "#{memory}" -d "#{disksize}G" --ds "#{datastore}" --vmdk "#{pathtovmdk}" --novncpass` 
    elsif type == "studio"
      `./suseviclient.sh -s "#{server}" -c -n "#{name}" --studio "#{applianceid}" --novncpass` 
    else
      "I have no idea what's happening"
    end
  end
end

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

def vmfsdatastores(server)
`./suseviclient.sh  -s #{server} --dslist --vmfs`
end

get '/' do
  @serverlist = File.open('./serverlist.conf')
	if session[:server].nil? 
	session[:server] = @serverlist.gets.chomp()
	@serverlist.pos = 0
  end
  
  vmlist
  @datastores = vmfsdatastores(session[:server])
  @title = 'Virtual Machines List'
	session[:vmarray] = @vmarray
  erb :home
end

post '/' do
 
  vm = VM.new
  
  flash[:error] = vm.validate(params) 

  redirect '/' if  (! flash[:error].nil? or flash[:error])

  vm.name = params[:vmname]
  vm.memory = params[:memory]
  vm.disksize = params[:disksize]
  vm.datastore = params[:datastore]
  flash[:notice] = "<li>" + vm.create(session[:server], params[:creation_type], params[:pathtoiso], params[:pathtovmdk], params[:applianceid]) + "</li>"

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

