app =
  templates: {}

$ ->
  target = "http://#{location.hostname}:#{location.port}"
  socket = io.connect target
  unless socket
    return alert "Failed to establish connection to #{target}"

  app.socket             = socket
  app.templates.feedItem = $('#template-feed-item').html()

  go socket

# Invoked once upon connection. Sets up all the things.
go = (socket) ->
  socket.on 'init', (data, socket) -> init data

init = (data) ->
  app.config = data.config
  app.feeds  = data.feeds

  console.log app.feeds
  feedList = $('#feeds ul')

  for f in app.feeds
    feedList.append Mustache.to_html app.templates.feedItem,
      title:   f.title
      epcount: f.episodeCount
