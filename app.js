(function() {
  var RedisStore, app, clients, createUser, crypto, db, express, getCookie, getNow, getTotalClients, io, makeHash, redis, say, sendMessageToFriends, socket;
  var __indexOf = Array.prototype.indexOf || function(item) {
    for (var i = 0, l = this.length; i < l; i++) {
      if (this[i] === item) return i;
    }
    return -1;
  };
  express = require('express');
  crypto = require('crypto');
  redis = require('redis');
  RedisStore = require('connect-redis');
  db = redis.createClient();
  io = require('socket.io');
  say = function(word) {
    return console.log(word);
  };
  makeHash = function(word) {
    var h;
    h = crypto.createHash('sha1');
    h.update(word);
    return h.digest('hex');
  };
  getNow = function() {
    var d, day, hour, minute, month, pad, s, second, year;
    pad = function(n) {
      if (n < 10) {
        return "0" + n;
      } else {
        return n;
      }
    };
    d = new Date;
    year = d.getUTCFullYear();
    month = pad(d.getUTCMonth() + 1);
    day = pad(d.getUTCDate());
    hour = pad(d.getUTCHours());
    minute = pad(d.getUTCMinutes());
    second = pad(d.getUTCSeconds());
    s = "" + year + "-" + month + "-" + day + "T" + hour + ":" + minute + ":" + second + "Z";
    return s;
  };
  db.on("error", function(err) {
    return say(err);
  });
  createUser = function(username, password) {
    return db.incr('global:nextUserId', function(err, res) {
      db.set("username:" + username + ":uid", res);
      db.set("uid:" + res + ":username", username);
      db.set("uid:" + res + ":password", makeHash(password));
      db.lpush("users", "" + username + ":" + res);
    });
  };
  app = module.exports = express.createServer();
  app.configure(function() {
    app.set('views', "" + __dirname + "/views");
    app.set('view engine', 'jade');
    app.use(express.bodyParser());
    app.use(express.methodOverride());
    app.use(express.cookieParser());
    app.use(express.session({
      secret: "+N3,6.By4(S",
      store: new RedisStore
    }));
    app.use(app.router);
    app.use(express.compiler({
      src: "" + __dirname + "/public",
      enable: ['less']
    }));
    app.use(express.static("" + __dirname + "/public"));
  });
  app.configure('development', function() {
    return app.use(express.errorHandler({
      dumpExceptions: true,
      showStack: true
    }));
  });
  app.get('/', function(req, res) {
    var id;
    if (!req.session.boltauth) {
      return res.redirect('/login');
    } else {
      id = req.session.userid;
      return db.llen("uid:" + id + ":timeline", function(err, data) {
        return db.lrange("uid:" + id + ":timeline", 0, data, function(err, data) {
          data = data.reverse();
          return res.render('index', {
            auth: true,
            home: true,
            messages: data
          });
        });
      });
    }
  });
  app.get('/login', function(req, res) {
    return res.render('login', {
      error: null
    });
  });
  app.post('/login', function(req, res) {
    var password, username;
    username = req.body.username;
    password = makeHash(req.body.password);
    return db.get("username:" + username + ":uid", function(err, result) {
      var id;
      if (err) {
        return res.render('login', {
          error: 'Wrong username/password'
        });
      } else {
        id = result;
        return db.get("uid:" + result + ":password", function(err, result) {
          if (err) {
            return res.render('login', {
              error: 'Database error. Try again.'
            });
          } else {
            if (result === password) {
              req.session.boltauth = 'true';
              req.session.userid = id;
              req.session.username = username;
              return res.redirect('/');
            } else {
              return res.render('login', {
                error: 'Wrong username/password'
              });
            }
          }
        });
      }
    });
  });
  app.get('/logout', function(req, res) {
    req.session.destroy();
    return res.redirect('/');
  });
  app.get('/register', function(req, res) {
    return res.render('register', {
      error: false
    });
  });
  app.post('/register', function(req, res) {
    var password, username;
    username = req.body.username;
    password = req.body.password;
    return db.get("username:" + username + ":uid", function(err, data) {
      if (data) {
        return res.render('register', {
          error: 'taken'
        });
      } else {
        createUser(username, password);
        return res.redirect('/login');
      }
    });
  });
  app.get('/users', function(req, res) {
    var id;
    if (!req.session.boltauth) {
      res.redirect('/login');
    }
    id = req.session.userid;
    return db.llen('users', function(err, result) {
      return db.lrange('users', 0, result, function(err, result) {
        var parts, user, users, _i, _len;
        users = [];
        for (_i = 0, _len = result.length; _i < _len; _i++) {
          user = result[_i];
          parts = user.split(':');
          users.push({
            username: parts[0],
            id: parts[1]
          });
        }
        return db.llen("uid:" + id + ":following", function(err, result) {
          return db.lrange("uid:" + id + ":following", 0, result, function(err, result) {
            var u, _j, _len2, _ref;
            for (_j = 0, _len2 = users.length; _j < _len2; _j++) {
              u = users[_j];
              if (_ref = u.id, __indexOf.call(result, _ref) >= 0) {
                u.follow = true;
              }
            }
            return res.render('users', {
              users: users,
              auth: true
            });
          });
        });
      });
    });
  });
  app.post('/follow', function(req, res) {
    var id, tofollow;
    id = req.session.userid;
    tofollow = req.body.id;
    db.rpush("uid:" + id + ":following", tofollow, function(er, d) {});
    db.rpush("uid:" + tofollow + ":followers", id, function(er, d) {});
    return res.send('ok');
  });
  if (!module.parent) {
    app.listen(8000);
    console.log("Server running...");
  }
  socket = io.listen(app);
  sendMessageToFriends = function(message, client) {
    var now;
    now = getNow();
    message = {
      body: message,
      author: client.username,
      id: client.id,
      sent: now
    };
    message = JSON.stringify(message);
    return db.llen("uid:" + client.id + ":followers", function(err, result) {
      return db.lrange("uid:" + client.id + ":followers", 0, result, function(err, result) {
        var user, _i, _len, _results;
        _results = [];
        for (_i = 0, _len = result.length; _i < _len; _i++) {
          user = result[_i];
          if (__indexOf.call(Object.keys(clients), user) >= 0) {
            say("sending a message to " + user);
            message = message.replace(/</g, '&lt;');
            message = message.replace(/>/g, '&gt;');
            clients[user].send(message);
            say('sent a message');
          }
          _results.push(db.rpush("uid:" + user + ":timeline", message));
        }
        return _results;
      });
    });
  };
  clients = {};
  getCookie = function(client) {
    var r, s, x, _i, _len;
    r = new RegExp(/^connect/);
    s = client.request.headers.cookie;
    s = s.split(' ');
    for (_i = 0, _len = s.length; _i < _len; _i++) {
      x = s[_i];
      if (r.test(x)) {
        s = x;
      }
    }
    s = s.substr(12, s.length - 12);
    s = s.replace(/\%2F/g, "/");
    s = s.replace(/\%2B/g, "+");
    return s;
  };
  getTotalClients = function() {
    return Object.keys(clients).length;
  };
  socket.on('connection', function(client) {
    var s, t;
    say('got a new client');
    t = getTotalClients();
    say("total: " + t);
    s = getCookie(client);
    db.get(s, function(err, r) {
      var d;
      if (!err) {
        d = JSON.parse(r);
        client.id = d.userid;
        client.username = d.username;
        return clients[client.id] = client;
      }
    });
    client.on('message', function(message) {
      return sendMessageToFriends(message, client);
    });
    return client.on('disconnect', function() {
      say('a client disappeared');
      delete clients[client.id];
      t = getTotalClients();
      return say("total: " + t);
    });
  });
}).call(this);
