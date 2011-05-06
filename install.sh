sudo apt-get install git-core g++ curl libssl-dev apache2-utils -y
cd ~

git clone git://github.com/joyent/node.git
git clone git://github.com/antirez/redis.git
git clone git://github.com/isaacs/npm.git

cd ~/node
git checkout v0.4.7
./configure
make
sudo make install

cd ~/redis/src

git checkout 2.2.5
./configure
make
sudo make install

cd ~/npm
sudo make install

npm install coffee-script
npm install express
npm install jade
npm install less
npm install hiredis redis
npm install socket.io
