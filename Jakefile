var fs    = require('fs'),
    chld  = require('child_process'),
    spawn = chld.spawn,
    exec  = chld.exec;

desc('The default task');
task('default', ['mkdirs', 'build_coffee', 'launch_help'], function () {}, true);

desc('Build Coffeescript');
task('build', ['build_coffee'], function() {}, true);

desc('Make Data and DB Dirs');
task('mkDirs', ['mkdirs'], function() {}, true);

desc('Run the app in development mode');
task('run', ['run_dev'], function() {}, true);

desc('Provide help with launching');
task('launch_help', [], function() {
    cl = function(m){console.log(m);};
    cl('To launch, type');
    cl('    node src/podproxy.js');
    complete();
}, true);

desc('Launch dev environment');
task('go', [], function() {
    require('environmenter')('environmenter.json');
});

desc('Launch with nodemon');
task('nm', [], function() {
    console.log('Running: nodemon -w src/coffee/ src/coffee/podproxy.coffee');
    console.log('Running: coffee -cw -o public/js/ src/ui/coffee/podproxy.coffee');
    var pp  = spawn('nodemon', ['-w', 'src/coffee/', 'src/coffee/podproxy.coffee']),
        cof = spawn('coffee', ['-cw', '-o', 'public/js/', 'src/ui/coffee/podproxy.coffee']);
    out = function(data) { process.stdout.write(data); }
    pp.stdout.on('data', out);  pp.stderr.on('data', out);
    cof.stdout.on('data', out); cof.stderr.on('data', out);
    pp.on('exit', function(code) {
        console.log('nodemon exited with code ' + code);
        cof.kill();
        complete();
    });
});


desc('Builds Coffeescript');
task('build_coffee', [], function () {
    console.log('Building CoffeeScript');
    exec('coffee -c -o src/ src/coffee/*.coffee', function (err) {
        if (err) {
            console.log(err);
        }
        exec('coffee -c -o public/js/ src/ui/coffee/*.coffee', function (err) {
            if (err) {
                console.log(err);
            }
            complete();
        });
    });
}, true);

desc('Make Data and DB Dirs');
task('mkdirs', [], function() {
    var count    = 0,
        total    = 3,
        dbDir    = __dirname + '/db',
        dataDir  = __dirname + '/data',
        pubJsDir = __dirname + '/public/js';
    makeDir = function(dir) {
        fs.stat(dir, function(err, stat) {
            if (err || !stat) {
                fs.mkdir(dir, null, function(err) {
                    if (err) console.log("ERROR mkdir "+dir+": "+err);
                    else     console.log("Created dir: "+dir);
                    count++;
                    if (count === total) {
                        complete();
                    }
                });
            } else {
                count++;
                if (count === total) {
                    complete();
                }
            }
        });
    };
    makeDir(dbDir);
    makeDir(dataDir);
    makeDir(pubJsDir);
}, true);


desc('Run the app in development mode');
task('run_dev', [], function () {
    var pp = spawn('node', ['src/podproxy.js']);
    console.log('Running: node src/podproxy.js');
    out = function(data) { process.stdout.write(data); }
    pp.stdout.on('data', out);
    pp.stderr.on('data', out);
    pp.on('exit', function(code) {
        console.log('podproxy exited with code ' + code);
        complete();
    });
}, true);

function rmAll(files, cb) {
    var toDo = files.length, done = 0, isErr = false;

    files.forEach(function (file) {
        fs.exists(file, function(exists) {
            if (!exists) {
                done++;
                return;
            }
            fs.unlink(file, function (err) {
                if (isErr) {
                    return;
                }
                if (err) {
                    isErr = true;
                    return cb(err);
                }
                done++;
                if (done === toDo) {
                    return cb(null);
                }
            });
        });
    });
}

desc('Removes all generated files');
task('clean', [], function (err) {
    fs.readDir('src/', function (err, files) {
        if (err) {
            console.log(err);
            complete();
            return;
        }
        jss = [];
        files.forEach(function (file) {
            if (/\.js$/.match(file)) {
                jss.push(file);
            }
        });
        rmAll(jss, function (err) {
            console.log("Generated files cleaned.");
            complete();
        });
    });
}, true);
