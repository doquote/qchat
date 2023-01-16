require 'sinatra'
require 'pstore' #database de preguiçoso
require 'digest'
require 'securerandom'
require 'cgi'

$users = PStore.new 'users'
$sessions = PStore.new 'sessions'
$online = {}

def username
  $sessions.transaction do
    $sessions[session[:sessionid]]
  end
end

def ismod
  $users.transaction(true) do
    user = $users[username]
    user[:power] == :mod
  end
end

def isadmin
  $users.transaction(true) do
    user = $users[username]
    user[:power] == :admin
  end
end

def userexists?(user)
  $users.transaction(true) { $users.keys.include? user }
end

def firstuser?
  $users.transaction(true) { $users.keys }.empty?
end

def usertype(user)
  $users.transaction(true) { $users[user][:power] }
end

def create(user, pass, type)
  $users.transaction do
    $users[user] = { pass: Digest::SHA256.digest(pass), power: type }
  end
end

def execute(cmd, room)
  returnmsg = '<p><i>[SISTEMA]</i>: '

  unless ismod || isadmin
    returnmsg += "Sem permissão (#{username}: #{cmd}).</p>"
    return returnmsg
  end

  if cmd.split.size < 2
    returnmsg += "Erro de sintaxe. (#{username}: #{cmd})</p>"
    return returnmsg
  end

  admincmds = %w[mod unmod newroom deleteroom]

  
  return adminexecute(cmd) if isadmin && admincmds.include?(cmd.split[0].sub '/', '')

  case cmd.split[0].sub('/', '')
  when 'delete'
    if cmd.split[1] == 'all'
      File.write "logs/#{room}", ''
    else
      delete(room, cmd.split[1])
      returnmsg += 'mensagem deletada.'
    end
  when 'ban'
    if userexists? cmd.split[1]
      ban(cmd.split[1])
      returnmsg += "#{cmd.split[1]} foi banido(a)."
    else
      returnmsg += 'Este usuário não existe.'
    end
  end
  returnmsg += " (#{username}: #{cmd})</p>"
  returnmsg
end

def adminexecute(cmd)
  returnmsg = '<p><i>[SISTEMA]: </i>'

  case cmd.split[0].sub('/', '')
  when 'mod'
    if userexists? cmd.split[1]
      mod(cmd.split[1])
      returnmsg += "#{cmd.split[1]} agora é moderador(a)."
    else
      returnmsg += 'Este usuário não existe.'
    end
  when 'unmod'
    if userexists? cmd.split[1]
      unmod(cmd.split[1])
      returnmsg += "#{cmd.split[1]} não é mais moderador(a)."
    else
      returnmsg += 'Este usuário não existe.'
    end
  when 'newroom'
    if File.exist? "logs/#{cmd.split[1]}"
      returnmsg += 'Esta sala já existe.'
    else
      newroom(cmd.split[1])
      returnmsg += "Sala \"#{cmd.split[1]}\" criada"
    end
  when 'deleteroom'
    if File.exist? "logs/#{cmd.split[1]}"
      deleteroom(cmd.split[1])
      returnmsg += "Sala \"#{cmd.split[1]}\" deletada."
    else
      returnmsg += 'Esta sala já não existe.'
    end
  end
  returnmsg += " (#{username}: #{cmd})</p>"
  returnmsg
end

def delete(room, msgpos)
  chatlog = File.readlines("logs/#{room}")
  chatlog.delete_at(msgpos.to_i - 1)

  File.open("logs/#{room}", 'w') do |fp|
    fp.puts chatlog.join
    fp.close
  end
end

def banned?(user)
  bannedusers = File.read 'banned'

  bannedusers.include? user
end

def online?(user, room)
  $online[room].include? user
end

def ban(user)
  $users.transaction do
    $users.delete user
  end

  File.open('banned', 'a') do |fp|
    fp.puts user
    fp.close
  end

  $sessions.transaction do
  $sessions.each do |s|
    $sessions.delete s[0] if s[1] == user
  end
  end
end

def mod(user)
  $users.transaction do
    $users[user][:power] = :mod
  end
end

def unmod(_user)
  $users.transaction do
    $users[cmd.split[1]][:power] = :normal
  end
end

def newroom(room)
  f = File.new("logs/#{room}", 'w')

  f.close
  
  File.open('rooms', 'a') do |fp|
    fp.puts room
  end
end

def deleteroom(room)
  File.delete "logs/#{room}"

  rooms = File.readlines 'rooms'

  index = 0

  rooms.each_index do |i|
    index = i if rooms[i].include? room
  end

  rooms.delete_at index

  File.open('rooms', 'w') do |fp|
    fp.puts rooms.join
  end
end

def login(user, pass)
  if banned? user
    redirect '/err?code=3'
  end
  
  unless userexists? user
    redirect '/err?code=2'
  end

  userdata = $users.transaction(true){
    $users[user]
  }

  unless Digest::SHA256.digest(pass) == userdata[:pass]
    redirect '/err?code=1'
  end

  unless session[:sessionid].nil?
    redirect '/chat?room=geral'
  end

  sessionid = SecureRandom.hex(64)
  
  session[:sessionid] = sessionid

  $sessions = PStore.new('sessions')

  $sessions.transaction do

  $sessions[sessionid] = user

  end
  
  redirect '/rooms'
end

def create user, pass
  if banned? user
    redirect '/err?code=3'
  end

  if userexists? user
    redirect '/err?code=4'
  end

  type = firstuser? ? :admin : :normal
  
  $users.transaction do
    $users[user] = { pass: Digest::SHA256.digest(pass), power: type }
  end
end

def sendmsg message, room
  msg = "<p><i>#{username}</i>: #{CGI.escapeHTML(message)}</p>"

  if message.start_with? '/'
    msg = execute(message, room)
  end

  unless message.split[0] == '/deleteroom'
  File.open("logs/#{room}", 'a') do |fp|
    fp.puts msg
    fp.close
  end
  end
end

def enterroom(user, room)

  return if !$online[room].nil? && online?(user, room)
  
  if $online.one? {|r| r.include? [user]}
    r = $online.select {|r| $online[r].include? user}
    exitroom(user, r.keys[0])
  end
  
  if $online[room].nil?
    $online[room] = [user]
  end
    
  unless online?(user, room)
    $online[room].push user
  end

  File.open("logs/#{room}", 'a') do |fp|
    fp.puts "<p><i>[SISTEMA]</i>: #{user} entrou na sala.</p>"
    fp.close
  end
end

def exitroom(user, room)
 
  $online[room] -= [user]

  File.open("logs/#{room}", 'a') do |fp|
    fp.puts "<p><i>[SISTEMA]</i>: #{user} saiu da sala.</p>"
    fp.close
  end
end

def loggedin?
  session[:sessionid] != nil && $sessions.transaction {$sessions[session[:sessionid]] != nil}

end

def onlineusers(room)
  $online[room]
end

def logoff
  $sessions.transaction do
    $sessions.delete session[:sessionid]
  end

  redirect '/'
end
