require 'sinatra'
require 'puma'
require_relative 'app.rb'

configure do
  set :port, 80
  enable :static
  enable :sessions
end

get '*/' do |dir|
  pass unless File.exist? "public/#{dir}/index.html"
  erb File.read("public/#{dir}/index.html"), :layout => :qchatl
end


post '/login' do
 login(params['user'], params['pass'])
end

post '/create' do
  create(params['user'], params['pass'])
  redirect '/welcome/'
end

post '/send' do
  sendmsg(params['message'], params['room'])
  redirect "/chat?room=#{params['room']}"
end

get '/log' do

  unless loggedin?
    halt 403
  end
 
  erb :log, :locals => {:room => params['room'], :mod => (isadmin || ismod)}
end

get '/chat' do

  unless loggedin?
    redirect '/'
  end
  
  enterroom(username, params['room'])

  unless File.exist? "logs/#{params['room']}"
    halt 404
  end

  erb :chat, :layout => :qchatl, :locals => {:room => params['room'], :mod => (isadmin || ismod), :users => onlineusers(params['room'])}
end

get '/err' do
  erb :err, :layout => :qchatl, :locals => {:code => params['code']}
end

get '/rooms' do
  erb :rooms, :layout => :qchatl
end

get '/logoff' do
  logoff()
end
