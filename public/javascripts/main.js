(function($) {

  $(function() {

    var userID = 123;
    
    var socket = new io.Socket('localhost', {
      port: 8000,
      rememberTransport: false
    });
    if (typeof(home) !== 'undefined') {
      socket.connect();
    }
    socket.on('connect', function() {
      //socket.send(userID);
    });
    socket.on('message', function(message) {
      console.log(message);
      message = JSON.parse(message);
      var html = "<div class='message new'><strong>" + message.author + "</strong>" +
        "<span>" + message.body + "</span>" +
        "<abbr class='timeago' title='" + message.sent + "'></abbr>" +
        "</div>";
      $('#messages').prepend(html);
      $('abbr.timeago').timeago();
      setTimeout(function() {
        $('.new').removeClass('new'); 
      }, 2000);
    });

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
      socket.send(t);
      $('#send-text').val("");
      return false;
    });

    $('abbr.timeago').timeago();
  });

})(jQuery);
