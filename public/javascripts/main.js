(function($) {

  $(function() {
    
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

  });

})(jQuery);
