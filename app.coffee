express = require 'express'
crypto = require 'crypto'
redis = require 'redis'
RedisStore = require('connect-redis')(express)

# This is so that Bolt works on Heroku --- if Heroku supported websockets.
if process.env.REDISTOGO_URL
  console.log 'redis to go'
  db = require('redis-url').createClient process.env.REDISTOGO_URL
else
  console.log 'not to go'
  db = redis.createClient()

redisStore = new RedisStore
  client: db

io = require 'socket.io'

# Helper functions

say = (word) -> console.log word

makeHash = (word) ->
  h = crypto.createHash 'sha1'
  h.update word
  h.digest 'hex'

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
  "#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}Z"

# Redis functions

db.on "error", (err) -> say err

createUser = (username, password) ->
  db.incr 'global:nextUserId', (err, res) ->
    db.set "username:#{username}:uid", res
    db.set "uid:#{res}:username", username
    db.set "uid:#{res}:password", makeHash password
    db.lpush "users", "#{username}:#{res}"

app = module.exports = express.createServer()

# Express configuration

app.configure ->
  app.set 'views', "#{__dirname}/views"
  app.set 'view engine', 'jade'
  app.use express.bodyParser()
  app.use express.methodOverride()
  app.use express.cookieParser()
  app.use express.session
    secret: "+N3,6.By4(S"
    store: redisStore
    cookie:
      path: '/'
      httpOnly: false
      maxAge: 14400000
  app.use app.router
  app.use express.compiler
    src: "#{__dirname}/public"
    enable: ['less']
  app.use express.static("#{__dirname}/public")

app.configure 'development', ->
  app.use express.errorHandler
    dumpExceptions: true
    showStack: true

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
  io = io.listen app
  app.listen process.env.PORT or 8000
  console.log "Server running..."


# Socket helpers

sendMessageToFriends = (message, socket) ->
  console.log 'sending message to friends'
  sid = message.cookie
  message = message.message
  getUserByCookie sid, (client) ->

    now = getNow()
    message = 
      body: message
      author: client.username
      id: client.userid
      sent: now
    # message = JSON.stringify message

    db.llen "uid:#{client.userid}:followers", (err, result) ->
      db.lrange "uid:#{client.userid}:followers", 0, result, (err, result) ->
        for user in result
          # Send through sockets first
          if user in Object.keys clients
            say "sending a message to #{user}"
            message.body = message.body.replace /</g, '&lt;'
            message.body = message.body.replace />/g, '&gt;'

            clients[user].socket.emit 'message', message

            # And then save it in redis
          db.rpush "uid:#{user}:timeline", JSON.stringify message

clients = {}

getTotalClients = -> Object.keys(clients).length

getUserByCookie = (cookie, callback) ->
  db.get "sess:#{cookie}", (err, r) ->
    callback JSON.parse r

registerClient = (sid, socket) ->
  getUserByCookie sid.cookie, (data) ->
    client =
      id: data.userid
      username: data.username
      socket: socket

    clients[client.id] = client
    # client.id = d.userid
    # client.username = d.username
    # clients[client.id] = client

# Kick it

io.sockets.on 'connection', (client) ->
  say 'got a new client'

  client.on 'auth', (data) ->
    registerClient data, client

  client.on 'message', (message) ->
      sendMessageToFriends message

  client.on 'disconnect', ->
    say 'a client disappeared'
    delete clients[client.id]
    t = getTotalClients()
    say "total: #{t}"
