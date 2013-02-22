# Get important thingies from main scope
log        = null
config     = null
emitter    = null
setLogger  = (logger) -> log     = logger
setConfig  = (conf)   -> config  = conf
setEmitter = (em)     -> emitter = em

lastId = 0   # will be the last episode id used. (0 is not used.)

class Feed
  constructor: (input) ->
    @url          = input.url
    @category     = input.category
    @title        = input.title
    @slug         = null  # will be set by FeedManager; unneeded until ep downloading
    @description  = input.description
    @image_url    = input.image_url
    @image_title  = input.image_title
    @link         = input.link
    @successDate  = input.successDate    # last time we successfully got the feed
    @failDate     = input.failDate       # last time we failed
    @failReason   = input.failReason     # explains why the fail at @lastFail
    @etag         = input.etag           # for caching
    @lastModified = input.lastModified   # for caching
    @autoDownloadEpisodes     = input.autoDownloadEpisodes      # per-feed override
    @autoDeleteBeyondEpisodes = input.autoDeleteBeyondEpisodes  # per-feed override
    @episodes     = []
    for i in input.episodes || []
      @add new Episode i
  add: (episode, parsed = false) ->  # Adds item if unique; updates fields otherwise
    if parsed
      episode.url      = episode.enclosures?[0]?.url
      episode.length   = episode.enclosures?[0]?.length
      episode.type     = episode.enclosures?[0]?.type
      episode.feedSlug = @slug

    for e in @episodes
      if e.guid is episode.guid
        e.title       = episode.title  # note that the slug will not change.
        e.description = episode.description
        e.date        = episode.date
        e.pubdate     = episode.pubdate
        e.link        = episode.link
        e.author      = episode.author
        return false  # We updated the existing episode

    if episode.id > lastId   # Always keep the highest id number where it belongs.
      lastId = episode.id
    else if !episode.id      # Assign the next id, in order
      lastId++
      episode.id = lastId

    ep = new Episode episode
    @episodes.push ep
    emitter.emit 'newEpisode', ep
    true
  getAutoDownloadEpisodes: ->
    if @autoDownloadEpisodes
      @autoDownloadEpisodes
    else config.autoDownloadEpisodes
  getAutoDeleteBeyondEpisodes: ->
    if @autoDeleteBeyondEpisodes
      @autoDeleteBeyondEpisodes
    else config.autoDeleteBeyondEpisodes
  getEpisodes: -> @episodes
  getEpisodeCount: -> @episodes.length
  done: ->  # invoked when the caller is done adding episodes
    @episodes.sort (a, b) -> a.pubdate < b.pubdate



# A feed item. It absolutely could lack an enclosure (url/length/type),
# but probably doesn't.
class Episode
  constructor: (input, feed) ->
    @id          = input.id          # unique number to identify the enclosure
    @title       = input.title
    @description = input.description
    @date        = input.date
    @pubdate     = input.pubdate
    @link        = input.link
    @guid        = input.guid        # the thing that uniquely identifies the item
    @author      = input.author
    @url         = input.url         # enclosure url
    @length      = input.length      # enclosure byte length
    @type        = input.type        # enclosure mime type
    @file        = input.file        # filename on disk
    @fetchDate   = input.fetchDate   # last time we attempted to download the episode
    @failReason  = input.failReason  # if fetch at @fetchDate failed, here's the reason
    @feedSlug    = input.feedSlug    # just so we know where to download to
  getLastPart: ->  # Grab the filename from the end of @url
    tmp = new RegExp('([^/]+)$').exec(@url)
    tmp[1] or null
  getFullLocation: (dataDir) ->
    if @file then "#{dataDir}/#{@feedSlug}/#{@file}" else null
  getDownloadUrl: ->
    portPart = if config.port is 80 then '' else ":#{config.port}"
    lastPart = @getLastPart()
    "http://#{config.host}#{portPart}/episode/#{@id}#{if lastPart then '/'+lastPart else ''}"
  getPrettySize: (precision = 2) ->
    kilobyte = 1024
    megabyte = kilobyte * 1024
    gigabyte = megabyte * 1024
    terabyte = gigabyte * 1024
    if @length >= 0 and @length < kilobyte
      "#{@length} b"
    else if @length >= kilobyte and @length < megabyte
      "#{(@length / kilobyte).toFixed(precision)} Kb"
    else if @length >= megabyte and @length < gigabyte
      "#{(@length / megabyte).toFixed(precision)} Mb"
    else if @length >= gigabyte and @length < terabyte
      "#{(@length / gigabyte).toFixed(precision)} Gb"
    else if @length >= terabyte
      "#{(@length / terabyte).toFixed(precision)} Tb"
    else
      "#{@length} b"
  getFieldsForRSS: ->
    ret =
      title:           @title
      description:     @description
      url:             @url
      guid:            @guid
      author:          @author
      date:            @date
    if @url    then ret.enclosureUrl    = @getDownloadUrl()
    if @length then ret.enclosureLength = @length
    if @type   then ret.enclosureType   = @type
    ret
  

exports.Feed       = Feed
exports.Episode    = Episode
exports.setLogger  = setLogger
exports.setConfig  = setConfig
exports.setEmitter = setEmitter
