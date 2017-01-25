log    = require 'logly'
fs     = require 'fs'
fm     = require './feedmanager'
em     = require './episodemanager'
server = require './server'

console.log '                 _                           '
console.log ' _ __   ___   __| |_ __  _ __ _____  ___   _ '
console.log '| \'_ \\ / _ \\ / _` | \'_ \\| \'__/ _ \\ \\/ / | | |'
console.log '| |_) | (_) | (_| | |_) | | | (_) >  <| |_| |'
console.log '| .__/ \\___/ \\__,_| .__/|_|  \\___/_/\\_\\\\__, |'
console.log '|_|               |_|  v. 0.1 wtf bbq  |___/ '

# console.log '                 _'
# console.log ' _ __   ___   __| |_ __  _ __ _____  ___   _'
# console.log '| \'_ \\ / _ \\ / _` | \\'_ \| \\'__/ _ \\ \/ / | | |'
# console.log '| |_) | (_) | (_| | |_) | | | (_) >  <| |_| |'
# console.log '| .__/ \\___/ \\__,_| .__/|_|  \\___/_/\_\\__, |'
# console.log '|_|               |_|  v. 0.1 wtf bbq  |___/ '
# console.log '|_|'
appVersion = '0.1 wtf bbq'
appName    = 'PodProxy'
appRepoUrl = 'https://github.com/djthread/podproxy'

log.name 'pprox'
log.mode 'debug'

# Global config defaults
config =
  host:                     'localhost'
  port:                     9555
  dataDir:                  'data'  # relative to the Podzi top-level
  dbDir:                    'db'    # relative to the Podzi top-level
  httpUser:                 null
  httpPass:                 null
  guestsCanRead:            true
  guestsCanManage:          true
  refreshOnStartup:         false
  refreshHourlyInterval:    6
  autoDownloadEpisodes:     0
  autoDeleteBeyondEpisodes: 2
  simulFeedUpdate:          2
  simulEpDownload:          1
  compositeCount:           50  # how many episodes to show in the /composite feed
  diskSyncIntervalSeconds:  60

state = {}  # internal state stuff that we don't want to save along with the config
do ->
  approot = __dirname.replace /\/(src|app)$/, ''
  state =
    approot: approot
    pubroot: "#{approot}/public"

# Set state with absoulte dir paths
if config.dbDir.substr 0, 1 is '/'
  state.dbDir = config.dbDir
else
  state.dbDir = "#{state.approot}/#{config.dbDir}"

if config.dataDir.substr 0, 1 is '/'
  state.dataDir = config.dataDir
else
  state.dataDir = "#{state.approot}/#{config.dataDir}"

state.configFile = "#{state.dbDir}/config.json"
state.feedFile   = "#{state.dbDir}/feeds.json"


# Set up the logger and give it and the global config hash to our modules
fm.setLogger     log
em.setLogger     log
server.setLogger log
fm.setConfig     config
em.setConfig     config
server.setConfig config
em.setState      state
server.setState  state

# Web needs the data, but we'll still use signals where appropriate
server.setFeedManager    fm
server.setEpisodeManager em

# Load the jsons, start application
bootstrap = (cb) ->
  fs.exists state.dbDir, (exists) ->
    unless exists
      log.log "#{state.dbDir}: missing. starting new one.."
      fs.mkdir state.dbDir, (err) ->
        if err
          log.log "#{state.dbDir}: creating failed."

  fs.readFile state.configFile, (err, data) ->
    if err
      log.log "#{state.configFile}: #{err}. starting new one.."
    else
      c = {}
      try
        c = JSON.parse data
      catch SyntaxError
        log.log "#{state.configFile} had invalid JSON. starting a new one.."

      loadConfig c
      syncConfigToDisk()  # sync right away in case cli params overrode anything.

    log.log "Config ready: #{JSON.stringify config}"

    fs.readFile state.feedFile, (err, data) ->
      if err
        log.log "#{state.feedFile} data not found. starting new one.."
      else
        f = []
        try
          f = JSON.parse data
        catch SyntaxError
          log.log "#{state.feedFile} had invalid JSON. starting a new one.."

        for feedData, idx in f
          fm.summonFeed feedData, ->
            log.log "Init: Loaded #{fm.count()} feeds."
            if cb and idx is f.length
              return cb()
      cb() if cb

loadConfig = (data = {}) ->
  for key, val of data
    if config[key] != undefined then config[key] = val

  die = (msg) -> log.error '>>'+msg; process.exit 1
  
  args = process.argv

  while args.length
    switch a = args.shift()
      when '--host', '-h'
        config.host = args.shift() or die 'Hostname expected.'
      when '--port', '-p'
        config.port = args.shift()
        unless config.port.match /^\d+$/ then die 'Number expected.'
      when '--user', '-u'
        config.httpUser = args.shift() or die 'Username expected.'
      when '--pass', '-p'
        config.httpPass = args.shift() or die 'Password expected.'
      when '--readOnly', '-ro'
        config.guestsCanRead   = false
      when '--locked', '-l'
        config.guestsCanRead   = false
        config.guestsCanManage = false
      when '--refresh', '-r'
        config.refreshOnStartup = true
      when '--interval', '-i'
        config.refreshHourlyInterval = args.shift()
        unless config.refreshHourlyInterval.match /^\d+$/ then die 'Number expected.'
      when '--help', '-?'
        cl = (l) -> console.log l
        cl ''
        cl "#{appName} v#{appVersion}"
        cl appRepoUrl
        cl ''
        cl '  --host,     -h   Set the hostname. (default is localhost)'
        cl '  --port,     -p   Set the port number. (default is 9555)'
        cl '  --readOnly, -ro  Guests may look, but not touch. (default is no HTTP auth)'
        cl "  --locked,   -l   Lock down #{appName}. HTTP authentication is requried."
        cl '  --user,     -u   Set the username for http authentication.'
        cl '  --pass,     -p   Set the password for http authentication.'
        cl '  --refresh,  -r   Refresh on startup. (default is not to)'
        cl '  --interval, -i   Set the refresh interval in hours. (default is 6)'
        cl '  --dlLast,   -dl  Number of recent episodes to have cached. (def 1)'
        cl '  --onlyKeep, -ok  Auto-delete episodes past this many per feed (def 2)'
        cl ''
        cl "These settings only need to be used once when invoking #{appName}. They will"
        cl 'then be stored and automatically used next time.'
        cl ''
        process.exit()
      else
        unless a.match /(node|\.js|coffee)$/
          die "What?: #{a}"

  #if !a.match /node$/ or !a.match /coffee/ or !a.match /\.(js|coffee)$/
  # these are logical implications that we'll just go ahead and clearly enforce
  if config.guestsCanManage then config.guestsCanRead   = true
  if  !config.guestsCanRead then config.guestsCanManage = false

syncToDisk = ->
  syncConfigToDisk()
  syncFeedsToDisk()

syncConfigToDisk = ->
  fs.writeFile state.configFile, JSON.stringify(config), (err) ->
    if err
      log.error "Failed to write #{state.configFile}!"
      process.exit 1

syncFeedsToDisk = ->
  fs.writeFile state.feedFile, fm.toJSON(), (err) ->
    if err
      log.error "Failed to write #{state.feedFile}"
      process.exit 1

# Link up some stuffs
server.emitter.on 'newUrl', (url) -> fm.summonFeed {url: url}
server.emitter.on 'refreshAll', -> fm.refreshAll()
fm.emitter.on 'refreshed', (feed) -> em.gander feed
fm.emitter.on 'newEpisode', (ep) -> em.add ep
em.emitter.on 'chunk', (bytesDownloaded, percentDownloaded, ep) ->
  server.chunk bytesDownloaded, percentDownloaded, ep

# Let's go !
bootstrap ->
  syncToDisk()
  setInterval syncToDisk, config.diskSyncIntervalSeconds * 1000
  fm.init()
  server.listen()
