express = require 'express'
crypto = require 'crypto'
redis = require 'redis'
RedisStore = require 'connect-redis'
db = redis.createClient()
io = require 'socket.io'

# Helper functions

say = (word) ->
  console.log word

makeHash = (word) ->
  h = crypto.createHash 'sha1'
  h.update word
  return h.digest 'hex'

# Redis functions

db.on "error", (err) ->
  say err

createUser = (username, password) ->
  db.incr 'global:nextUserId', (err, res) ->
    db.set "username:#{username}:uid", res
    db.set "uid:#{res}:username", username
    db.set "uid:#{res}:password", makeHash password
    db.lpush "users", "#{username}:#{res}"
    return

app = module.exports = express.createServer()

# Configuration

app.configure () ->
  app.set 'views', "#{__dirname}/views"
  app.set 'view engine', 'jade'
  app.use express.bodyParser()
  app.use express.methodOverride()
  app.use express.cookieParser()
  app.use express.session secret: "+N3,6.By4(S", store: new RedisStore
  app.use app.router
  app.use express.static("#{__dirname}/public")
  return

app.configure 'development', () ->
  app.use express.errorHandler(dumpExceptions: true, showStack: true)

# Routes

app.get '/', (req, res) ->
  if not req.session.boltauth
    res.redirect '/login'
  else
    res.render 'index'

app.get '/login', (req, res) ->
  res.render 'login',
    error: null

app.post '/login', (req, res) ->
  # Extract username/password from POST
  username = req.body.username
  password = makeHash req.body.password

  db.get "username:#{username}:uid", (err, result) ->
    if err
      res.render 'login',
        error: 'Wrong username/password'
    else
      id = result
      db.get "uid:#{result}:password", (err, result) ->
        if err
          res.render 'login',
            error: 'Database error. Try again.'
        else
          if result is password
            req.session.boltauth = 'true'
            req.session.userid = id
            res.redirect '/'
          else
            res.render 'login',
              error: 'Wrong username/password'

app.get '/register', (req, res) ->
  res.render 'register'

app.post '/register', (req, res) ->
  username = req.body.username
  password = req.body.password
  createUser username, password
  res.redirect '/login'

app.get '/users', (req, res) ->
  db.lrange 'users', -100, 100, (err, result) ->
    users = []
    for user in result
      parts = user.split ':'
      users.push username: parts[0], id: parts[1]
    res.render 'users',
      users: users

app.post '/follow', (req, res) ->
  id = req.session.userid
  tofollow = req.body.id

  db.lpush "uid:#{id}:following", tofollow, (err, result) ->
    if not err
      res.send 'ok'
    else
      res.send(404)
  db.lpush "uid:#{tofollow}:followers", id


# Only listen on $ node app.js

if not module.parent
  app.listen 8000
  console.log "Server running..."

socket = io.listen app

# Socket helpers

sendMessageToFriends = (message, client) ->
  db.llen "uid:#{client.id}:followers", (err, result) ->
    db.lrange "uid:#{client.id}:followers", 0, result, (err, result) ->
      for user in result
        clients[user].send message

clients = {}

getCookie = (client) ->
  s = client.request.headers.cookie
  s = s.substr(12, (s.length - 12))
  s = s.replace "%2B", "+"
  s = s.replace "%2F", "/"
  return s

getTotalClients = ->
  return Object.keys(clients).length

# Kick it

socket.on 'connection', (client) ->
  say 'got a new client'
  t = getTotalClients()
  say "total: #{t}"
  s = getCookie client
  db.get s, (err, r) ->
    if not err
      d = JSON.parse r
      client.id = d.userid
      clients[client.id] = client

  client.on 'message', (message) ->
    sendMessageToFriends message, client

  client.on 'disconnect', ->
    say 'a client disappeared'
    delete clients[client.id]
    t = getTotalClients()
    say "total: #{t}"
