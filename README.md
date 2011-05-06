# Bolt

Bolt is a simple, proof-of-concept Twitter clone. It's written in node.js using
the express web framework and redis for persistance. As a bonus, it uses
socket.io to deliver your messages to your followers in virtually real time.

### Installation

To install all the dependencies on an Ubuntu server, you can use the
`install.sh` script. Run it as `root`.

### Dependencies:

* node.js
* redis
* npm
* npm install coffee-script
* npm install express
* npm install jade
* npm install less
* npm install hiredis redis
* npm install socket.io 

### Running

Make sure redis is running, and then execute:

    $ coffee app.coffee
