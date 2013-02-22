fs      = require 'fs'
events  = require 'events'
request = require 'request'

# Get important thingies from main scope
log       = null
config    = null
state     = null
setLogger = (lo)   -> log    = lo
setConfig = (conf) -> config = conf
setState  = (st)   -> state  = st

emitter = new events.EventEmitter

episodes  = {}  # episode id: Episode object -- for all episodes, ever
queuelist = []  # array of episode ids to be downloaded asap
jobs      = []  # array of episode ids for active downloads

add = (episode) ->
  if episodes[episode.id]
    log.debug "EM: Tried to add episode: #{episode.title} [#{episode.id}], but we already had it."
  else
    episodes[episode.id] = episode
    log.debug "EM: Added episode: #{episode.title} [#{episode.id}]."

sendById = (eid, res) ->  # Given an episode id and web response object, serve up an episode.
  if ep = episodes[eid]
    if fullLocation = ep.getFullLocation(state.dataDir)
      # the file is entirely downloaded!
      log.log "EM: Feeding client episode from #{fullLocation}"
      res.writeHead 200,
        'Content-Type':   ep.type
        'Content-Length': ep.length
      fileStream = fs.createReadStream fullLocation
      fileStream.pipe res
    else
      log.log "EM: Don't have episode, 302ing client to #{ep.url}"
      res.writeHead 302, 'Location': ep.url
      res.send()
  else
    null  # we has no file :(

gander = (feed) ->  # take a gander at a refreshed feed; maybe download episode(s)
  log.debug "EM: Taking a gander at the last #{config.autoDownloadEpisodes} eps of #{feed.title}"
  return unless jobs.length < config.simulEpDownload
  realCount = 0  # Number of actual downloadables we've considered
  for ep in feed.episodes
    continue unless ep.url  # skip it if there is no enclosure
    realCount++             # ok, it's an episode
    continue if ep.file     # skip it if we already have it downloaded
    break if realCount > feed.getAutoDownloadEpisodes()  # we already has enough episodes of this feed
    queue ep.id             # YOU'RE NEXTT

debug = ->
  console.log episodes
  console.log queuelist
  console.log jobs
      

#
# Private methods follow
#

queue = (eid = null) ->
  episode = episodes[eid]
  if episode
    log.debug "EM: Queued #{episode.url}"
    already = false
    for eid in jobs.concat queuelist
      if eid == episode.id
        already = true
        break
    if already
      log.debug "EM: episode #{episode.url} [#{episode.id}] is already coming."
    else
      queuelist.push episode.id
  else
    log.debug "EM: Episode queue nudged."
  if jobs.length < config.simulEpDownload and queuelist.length
    log.debug "EM: Popping off the episode queue."
    download queuelist.pop()

download = (eid) ->
  episode = episodes[eid]
  log.debug "EM: download [#{eid}]... title: #{episode.title}"
  getUniqueDownloadTarget episode, (target) ->
    return unless target
    log.log "EM: Downloading #{episode.url} to #{target} [#{episode.getPrettySize()}]"
    episode.fetchDate = new Date
    requestOptions    =
      url:      episode.url
      timeout:  10000
      encoding: null
    requestCallback   = (err, response, body) ->
      if err
        episode.failReason = err
        log.error "EM: Error downloading #{episode.url}: #{err}"
      else
        episode.failReason = null
        regex              = ".*#{state.dataDir}/#{episode.feedSlug}/"
        episode.file       = target.replace new RegExp(regex), ''
        log.log "EM: Downloaded #{episode.url} to #{target}"
        if (doneId = jobs.indexOf eid) != -1
          jobs.splice doneId, 1
        else
          log.error 'EM: ZOMG THE SKY IS FALLING'
      queue()  # nudge the queue. maybe another download will start.

    jobs.push eid
    bytes        = 0  # bytes downloaded
    lastPercent  = 0  # last percent (integer) emitted
    toDiskStream = fs.createWriteStream target
    req = request(requestOptions, requestCallback)
    req.on 'data', (buf) ->
      bytes     += buf.length
      curPercent = Math.floor(bytes / episode.length * 100)
      toDiskStream.write buf
      if curPercent > lastPercent
        emitter.emit 'chunk', bytes, curPercent, episode
        lastPercent = curPercent
    req.on 'end',         -> toDiskStream.end()
    req.on 'error', (err) -> toDiskStream.end(); fs.unlink target


# Get the full filename to download the enclosure to, relative to dataDir
getUniqueDownloadTarget = (episode, cb) ->
  url  = episode.url
  slug = episode.feedSlug
  unless url and slug
    log.error "EM: Tried to get target episode filename from #{url}, #{slug}!"
    return
  filename = episode.getLastPart() or episode.id
  situateDir state.dataDir, (mainDir) ->
    situateDir "#{mainDir}/#{slug}", (feedDir) ->
      target = "#{feedDir}/#{filename}"
      fs.stat target, (err, stats) ->
        if err or !stats or !stats.ino
          cb target  # success!
        else
          cb "#{feedDir}/#{episode.id}"  # screw it, just use the id

situateDir = (dir, cb) ->
  log.debug "EM: SituateDir: #{dir}"
  fs.stat dir, (err, stat) ->
    if err then fs.mkdir dir, null, (err) ->
      if err
        log.error "EM: mkdir #{dir} fail: #{err}"
      else
        log.log "EM: Created dir: #{dir}"
        cb dir
    else cb dir

exports.add       = add
exports.sendById  = sendById
exports.gander    = gander
exports.setLogger = setLogger
exports.setConfig = setConfig
exports.setState  = setState
exports.debug     = debug
exports.emitter   = emitter
