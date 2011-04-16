express = require 'express'
crypto = require 'crypto'
redis = require 'redis'
client = redis.createClient()

# Helper functions

say = (word) ->
  console.log word

makeHash = (word) ->
  h = crypto.createHash 'sha1'
  h.update word
  return h.digest 'hex'

# Redis functions

client.on "error", (err) ->
  say err

createUser = (username, password) ->
  client.incr 'global:nextUserId', (err, res) ->
    client.set "username:#{username}:uid", res
    client.set "uid:#{res}:username", username
    client.set "uid:#{res}:password", makeHash password
    client.lpush "users", "#{username}:#{res}"
    return

app = module.exports = express.createServer()

# Configuration

app.configure () ->
  app.set 'views', "#{__dirname}/views"
  app.set 'view engine', 'jade'
  app.use express.bodyParser()
  app.use express.methodOverride()
  app.use express.cookieParser()
  app.use express.session secret: "+N3,6.By4(S"
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

  client.get "username:#{username}:uid", (err, result) ->
    if err
      res.render 'login',
        error: 'Wrong username/password'
    else
      id = result
      client.get "uid:#{result}:password", (err, result) ->
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
  client.lrange 'users', -100, 100, (err, result) ->
    users = []
    for user in result
      parts = user.split ':'
      users.push username: parts[0], id: parts[1]
    res.render 'users',
      users: users

app.post '/follow', (req, res) ->
  id = req.session.userid
  tofollow = req.body.id

  client.lpush "uid:#{id}:following", tofollow, (err, result) ->
    if not err
      res.send 'ok'
    else
      res.send(404)
  client.lpush "uid:#{tofollow}:followers", id


# Only listen on $ node app.js

if not module.parent
  app.listen 8000
  console.log "Server running..."
