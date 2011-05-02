# Schema

### Basic user

    username:honza:uid
      => 1
    uid:1:username
      => honza
    uid:1:password
      => "password hash"
    users
      => [honza:1, ..]

### Following

    uid:1:following
      => [2, 3, ..]
    uid:1:followers
      => [3, 4, ..]

### Timelines

    uid:1:timeline
      => [list of messages honza will see on his homepage]
