events     = require 'events'
request    = require 'request'
FeedParser = require 'feedparser'
feeddata   = require './feeddata'
RSS        = require 'rss'

Feed = feeddata.Feed

emitter = new events.EventEmitter

# Get important thingies from main scope
log       = null
config    = {}
setConfig = (conf) ->
  config = conf
  feeddata.setConfig conf
setLogger = (logger) ->
  log = logger
  feeddata.setLogger logger
feeddata.setEmitter emitter

feeds     = []  # array of feed objects
queuelist = []  # array of feed objects to be refreshed asap
jobs      = []  # array of url: {downloading: true|false}
composite = []  # array of last config.compositeCount all episodes, in pubdate order

# Create feed by URL if not exist; refresh if new; call back with it.
summonFeed = (f, cb = null, allowRefresh = true) ->
  if not f.url
    log.error "summonFeed() called without url!"
    return null
  if feed = getFeedByUrl f.url
    cb feed if cb
  else
    log.debug 'Creating new feed object...'
    feed = new Feed f
    if allowRefresh
      refreshFeed feed, ->
        feeds.push feed
        emitter.emit 'feed', feed
        cb feed if cb
    else
      feeds.push feed
      emitter.emit 'feed', feed
      cb feed if cb

count = -> feeds.length

toJSON = -> JSON.stringify feeds

toMinimal = ->
  ret = []
  for f in feeds
    ret.push
      url:          f.url
      title:        f.title
      successDate:  f.successDate
      failDate:     f.failDate
      failReason:   f.failReason
      episodeCount: f.getEpisodeCount()
  ret

slugify = (feedTitle) ->  # build dir name to dump feed's episodes into.
  # Take "cheese: foo's #2" and make "cheese_ foo_s _2". Also, make sure the
  # output isn't in cantBe by adding underscores till we win.
  cantBe = (f.slug for f in feeds)
  out    = feedTitle.replace /[^a-z0-9-\.]+/i, '_'
  loop
    ok = true
    for avoid in cantBe
      if out == avoid
        out += '_'
        ok = false
        break
    break if ok
  out

queue = (feed = null) ->  # maybe add a new feed to the que; also check what's next!
  if feed?.url
    log.debug "Queued #{feed.url}"
    queuelist.push feed
  else
    log.debug "Feed queue nudged."
  if queuelist.length
    if jobs.length < config.simulFeedUpdate
      log.debug "Popping off the feed queue."
      refreshFeed queuelist.pop()
  else
    log.debug "Feed queue empty."

refreshAll = ->
  log.log 'Refreshing all feeds...'
  queue f for f in feeds

refreshFeed = (feed, cb = null) ->
  log.log "Refreshing #{feed.url}"
  if jobs[feed.url]?.downloading
    log.warn "Feed fetch already in progress. Not doubling job."
    return
  jobs[feed.url] = downloading: true
  reqObj = uri: feed.url
  if feed.etag and feed.lastModified then reqObj.headers =
    'If-Modified-Since': feed.lastModified
    'If-None-Match':     feed.etag
  request reqObj, (error, response, body) ->
    if error or response.statusCode != 200
      delete jobs[feed.url]
      feed.failReason = "Feed refresh failed. #{error} on #{new Date}"
      log.warn "Feed refresh FAILED: #{feed.url}: #{error}"
      cb() if cb
    else
      parser = getParser ->
        feed.done()
        queue()
        emitter.emit 'refreshed', feed
        cb() if cb
      parser.newItemCount = 0
      parser.feed         = feed
      parser.parseString body

getRSS = (f) ->
  feed = new RSS
    title:       f.title
    description: f.description
    feed_url:    f.url
    site_url:    f.link
    image_url:   f.image_url
    image_title: f.image_title
    # author:      'bar'
  for e in f.episodes
    feed.item e.getFieldsForRSS()
  feed.xml()

getCompositeRSS = ->  # Get a feed composed of the latest X episodes from all (real) feeds
  feed = new RSS
    title:       "Composite Feed from #{config.host}"
    description: 'All your feeds, mish-mashed and stuff'
    feed_url:    "http://#{config.host}:#{config.port}/composite"
    site_url:    "http://#{config.host}:#{config.port}"
  for e in composite
    feed.item e.getFieldsForRSS()
  feed.xml()

#
# Private methods follow
#

getParser = (cbOnParseEnd = null) ->
  parser = new FeedParser
  parser.on 'article', (article) ->
    if parser.feed.add article, true
      parser.newItemCount++
  parser.on 'error', (e) ->
    log.warn "Failed to parse #{parser.feed.url}: #{e}"
    parser.feed.failReason = e
    parser.feed.failDate   = new Date
  parser.on 'meta', (meta) ->
    parser.feed.title       = meta.title
    parser.feed.slug        = slugify(meta.title) unless parser.feed.slug
    parser.feed.description = meta.description
    parser.feed.link        = meta.link
    parser.feed.image_url   = meta.image?.url
    parser.feed.image_title = meta.image?.title
  parser.on 'end', ->
    log.log "Parsed #{parser.newItemCount} new articles from #{parser.feed.title}"
    parser.feed.failReason  = null
    parser.feed.successDate = new Date
    delete jobs[parser.feed.url]
    log.log 'Refreshed Feeds.'
    cbOnParseEnd() if cbOnParseEnd
  parser

getFeedByUrl = (u) ->
  for f in feeds
    if f.url is u
      return f
  null

# take a fully populated feed object that has just been pushed onto the feeds
# array and recompute compositeCount
emitter.on 'feed', (feed) ->
  for e in feed.episodes            # look at each new episode
    done = true
    for cur, idx in composite       # compare to each episode in the current composite
      if e.pubdate > cur.pubdate    # if it's newer,
        composite.splice idx, 0, e  # splice it in
        done = false
        break
    if idx is composite.length and composite.length < config.compositeCount
      composite.push e              # space left over in composite; push !
      done = false

    break if done                   # we didn't find anywhere to put the current new episode -- DONE


init = ->  # refresh all feeds on startup and on a timer.
  refreshAll() if config.refreshOnStartup
  setInterval refreshAll, config.refreshHourlyInterval * 3600000


exports.setLogger       = setLogger
exports.setConfig       = setConfig
exports.summonFeed      = summonFeed
exports.count           = count
exports.toJSON          = toJSON
exports.toMinimal       = toMinimal
exports.slugify         = slugify
exports.refreshFeed     = refreshFeed
exports.refreshAll      = refreshAll
exports.getRSS          = getRSS
exports.getCompositeRSS = getCompositeRSS
exports.emitter         = emitter
exports.init            = init
