(function($) {

  var Client;

  Client = (function() {

    function Client() {
      this.socket = io.connect('http://localhost');
      this.cookie = this.getCookie();
      this.onConnect();
      this.bind();
    }

    Client.prototype.bind = function() {
      this.socket.on('message', $.proxy(this.onMessage, this));
    };

    Client.prototype.onMessage = function(message) {
      console.log(message);
      var html = '<div class="message new"><strong>' + message.author +
        '</strong>' + '<span>' + message.body + '</span>' +
        '<abbr class="timeago" title="' + message.sent + '"></abbr>' +
        '</div>';

      $('#messages').prepend(html);
      $('abbr.timeago').timeago();
      setTimeout(function() {
        $('.new').removeClass('new');
      }, 2000);

    };

    Client.prototype.onConnect = function() {
      this.socket.emit('auth', {
        cookie: this.cookie
      });
    };

    Client.prototype.send = function(message) {
      this.socket.emit('message', {
        message: message,
        cookie: this.cookie
      });
    };

    Client.prototype.getCookie = function() {
      return $.cookie('connect.sid');
    };

    return Client;

  })();

  $(function() {

    var client;

    // socket.io

    client = new Client;

    // UI stuff

    $('a.follow').click(function() {
      var id = $(this).attr('rel');
      $.post('/follow', {id: id}, function(data, st, xhr) {
        if (xhr.status == 200) {
          console.log('success');
          console.log(data);
        } else {
          console.log('error');
        }
      });
      return false;
    });

    $('#send-button').click(function() {
      var t = $('#send-text').val();
      client.send(t);
      $('#send-text').val('');
      return false;
    });

    $('abbr.timeago').timeago();
  });

})(jQuery);
