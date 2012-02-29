express = require 'express'
crypto = require 'crypto'
redis = require 'redis'
RedisStore = require('connect-redis')(express)
db = redis.createClient()
io = require 'socket.io'

# Helper functions

say = (word) ->
  console.log word

makeHash = (word) ->
  h = crypto.createHash 'sha1'
  h.update word
  return h.digest 'hex'

# Return utc now in format suitable for jquery.timeago
getNow = ->
  pad = (n) ->
    if n < 10
      return "0#{n}"
    else
      return n
  d = new Date
  year = d.getUTCFullYear()
  month = pad (d.getUTCMonth() + 1)
  day = pad d.getUTCDate()
  hour = pad d.getUTCHours()
  minute = pad d.getUTCMinutes()
  second = pad d.getUTCSeconds()
  s = "#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}Z"
  return s

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

# Express configuration

app.configure () ->
  app.set 'views', "#{__dirname}/views"
  app.set 'view engine', 'jade'
  app.use express.bodyParser()
  app.use express.methodOverride()
  app.use express.cookieParser()
  app.use express.session secret: "+N3,6.By4(S", store: new RedisStore
  app.use app.router
  app.use express.compiler
    src: "#{__dirname}/public"
    enable: ['less']
  app.use express.static("#{__dirname}/public")
  return

app.configure 'development', () ->
  app.use express.errorHandler(dumpExceptions: true, showStack: true)

# Routes

app.get '/', (req, res) ->
  if not req.session.boltauth
    res.redirect '/login'
  else
    id = req.session.userid
    # Select logged in user's messages
    db.llen "uid:#{id}:timeline", (err, data) ->
      db.lrange "uid:#{id}:timeline", 0, data, (err, data) ->
        data = data.reverse()
        res.render 'index',
          auth: true
          home: true
          messages: data

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
            req.session.username = username
            res.redirect '/'
          else
            res.render 'login',
              error: 'Wrong username/password'

app.get '/logout', (req, res) ->
  req.session.destroy()
  res.redirect '/'

app.get '/register', (req, res) ->
  res.render 'register',
    error: false

app.post '/register', (req, res) ->
  username = req.body.username
  password = req.body.password
  # Check if user exists
  db.get "username:#{username}:uid", (err, data) ->
    if data
      res.render 'register',
        error: 'taken'
    else
      createUser username, password
      res.redirect '/login'

app.get '/users', (req, res) ->
  if not req.session.boltauth
    res.redirect '/login'
  id = req.session.userid
  db.llen 'users', (err, result) ->
    db.lrange 'users', 0, result, (err, result) ->
      users = []
      for user in result
        parts = user.split ':'
        users.push
          username: parts[0]
          id: parts[1]
      # Now that we have the users array, let's add to each object a key to
      # indicate whether we already follow this user
      db.llen "uid:#{id}:following", (err, result) ->
        db.lrange "uid:#{id}:following", 0, result, (err, result) ->
          # Loop over and assign
          for u in users
            if u.id in result
              u.follow = true
          res.render 'users',
            users: users
            auth: true

app.post '/follow', (req, res) ->
  id = req.session.userid
  tofollow = req.body.id

  db.rpush "uid:#{id}:following", tofollow, (er, d) ->
  db.rpush "uid:#{tofollow}:followers", id, (er, d) ->

  res.send 'ok'

# Only listen on $ node app.js

if not module.parent
  app.listen 8000
  console.log "Server running..."

socket = io.listen app

# Socket helpers

sendMessageToFriends = (message, client) ->
  now = getNow()
  message = 
    body: message
    author: client.username
    id: client.id
    sent: now
  message = JSON.stringify message
  db.llen "uid:#{client.id}:followers", (err, result) ->
    db.lrange "uid:#{client.id}:followers", 0, result, (err, result) ->
      for user in result
        # Send through sockets first
        if user in Object.keys clients
          say "sending a message to #{user}"
          message = message.replace /</g, '&lt;'
          message = message.replace />/g, '&gt;'
          clients[user].send message
          say 'sent a message'
          # And then save it in redis
        db.rpush "uid:#{user}:timeline", message

clients = {}

getCookie = (client) ->
  r = new RegExp /^connect/
  s = client.request.headers.cookie
  s = s.split ' '
  for x in s
    if r.test x
      s = x
  s = s.substr(12, (s.length - 12))
  s = s.replace /\%2F/g, "/"
  s = s.replace /\%2B/g, "+"
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
      client.username = d.username
      clients[client.id] = client

  client.on 'message', (message) ->
    sendMessageToFriends message, client

  client.on 'disconnect', ->
    say 'a client disappeared'
    delete clients[client.id]
    t = getTotalClients()
    say "total: #{t}"
