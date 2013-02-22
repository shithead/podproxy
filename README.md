PodProxy
===

PodProxy is a podcatcher (podcast client) with unique features.

Status: Backend is functional. I need to build a nice web front for this thing.

Dependencies
===

You'll definitely need [Node](http://nodejs.org/) and
[npm](https://npmjs.org/), but also

CoffeeScript

    npm install coffee-script -g

Jake

    npm install jake -g

Usage
===

    npm install               # install local dependencies
    jake                      # build the project
    node src/podproxy.js -?   # read the usage
    node src/podproxy.js      # launch! (no flags are required)


More
===

Get a proxied feed by adding http://your.server:9555/?f=http://some.rss/feed to
your podcatcher app.

License
===

Dual GPL/BSD
