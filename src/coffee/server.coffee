url      = require 'url'
events   = require 'events'
express  = require 'express'
bodyParser = require 'body-parser'
http     = require 'http'
ioModule = require 'socket.io'

app = express()
app.use bodyParser.urlencoded({ extended: false })

# zomg FIXME
# app.use express.static __dirname + '/../../public'
# app.set 'views', __dirname + '/ui/views'
# app.set 'view engine', 'html'
# app.engine 'html', require('hbs').__express

# Emits events as web users do things.
emitter = new events.EventEmitter

# Get important thingies from main scope
log               = null
config            = null
em                = null
fm                = null
state             = null
setLogger         = (logger)   -> log    = logger
setConfig         = (conf)     -> config = conf
setFeedManager    = (fmanager) -> fm     = fmanager
setEpisodeManager = (emanager) -> em     = emanager
setState          = (st)       ->
  state  = st
  app.use express.static "#{state.approot}/public"


# show a form for adding new items
# show a list of added items
app.get '/', (req, res) ->
  return if (write = authenticate req, res) == null
  # Maybe add, but definitely get a feed -- if requested
  url_parts = url.parse req.url, true
  if feedUrl = url_parts.query.feed or url_parts.query.f
    return maybeAddButGetFeed feedUrl, res

  res.sendFile "#{state.pubroot}/index.html"

# serve up a composite feed of all subscribed feeds
app.get '/composite', (req, res) ->
  res.contentType 'application/xml'
  res.send fm.getCompositeRSS()

actionGetEpisode = (req, res) ->
  eid = req.params.eid
  log.log "Client is requesting eid [#{eid}]"
  unless em.sendById eid, res
    res.send 403
app.get '/episode/:eid', actionGetEpisode
app.get '/episode/:eid/:filename', actionGetEpisode

# SOCKET.IO EVENTS
#
chunk = (bytesDownloaded, percentDownloaded, ep) ->
  console.log "fetched #{bytesDownloaded} b, #{percentDownloaded}%"

#
# END SOCKET IO EVENTS

# BEGIN STUFF WE CAN KILL
#
app.get '/refresh', (req, res) ->
  data = {}
  emitter.emit 'refreshAll'
  # res.render 'add.html', data
  res.send 200

#app.get '/debug', (req, res) ->
  #data = {}
  #em.debug()
  #stream = res.render 'add.html', data
  #stream.pipe res

# Take provided URL and add it to the 'database'
app.post '/add', (req, res) ->
  data =
    added: 'maybe'
    url:   req.param 'url'

  emitter.emit 'newUrl', data.url

  res.render 'add.html', data

# Returns altered podcast, adding it if it isn't in our collection already
app.get '/feeds', (req, res) ->
  res.send JSON.stringify fm.toMinimal()

#
# END STUFF WE CAN KILL



maybeAddButGetFeed = (url, res) ->
  fm.summonFeed {url: url}, (feed) ->
    res.send fm.getRSS(feed)

# Authenticate the user via http auth according to our config'd rules.
# Returns true if the user has write access, false if not, null if we give
# a 401 -- that means res is finished with and the caller can prolly return.
authenticate = (req, res) ->
  return true if config.guestsCanManage

  header = req.headers['authorization'] || ''      # get the header
  token  = header.split(/\s+/).pop() || ''         # and the encoded auth token
  auth   = new Buffer(token, 'base64').toString()  # convert from base64
  parts  = auth.split /:/                          # split on colon
  user   = parts[0]
  pass   = parts[1]

  if user is config.httpUser and pass is config.httpPass
    log.debug 'AUTH: User authenticated.'
    true
  else if config.guestsCanRead
    log.debug 'AUTH: This guest can read just like the rest of them.'
    false
  else
    log.debug 'AUTH: User must authenticate. 401, Sir.'
    res.setHeader 'WWW-Authenticate', 'Basic'
    res.send 401
    null

socketIOConnection = (socket) ->
  socket.emit 'init',
    config: config
    feeds:  fm.toMinimal()
  socket.on 'newFeed', ->
    console.log 'Adding pheed'

# This function should be called at the end of setup to start the web server et al
listen = ->
  s = http.createServer app
  s.on 'error', (err) ->
    log.error "Could not bind to port. Got error code #{err.code}"
    process.exit 1

  io = ioModule.listen s
  io.sockets.on 'connection', socketIOConnection

  s.listen config.port

exports.setLogger         = setLogger
exports.setConfig         = setConfig
exports.setFeedManager    = setFeedManager
exports.setEpisodeManager = setEpisodeManager
exports.setState          = setState
exports.emitter           = emitter
exports.listen            = listen

# Signals
exports.chunk = chunk
