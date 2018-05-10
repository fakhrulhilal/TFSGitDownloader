var gulp = require('gulp');
var shell = require('shelljs'),
    exec = require('child_process').execSync,
    path = require('path'),
    fs = require('fs'),
    runSequence = require('run-sequence'),
    hashsum = require('gulp-hashsum');

var _build = 'build',
    manifest = 'vss-extension.json',
    checksumAlgorithm = 'sha1';

gulp.task('clean', function() {
    return shell.rm('-rf', _build);
});

function executeVerboseCommand(cmd) {
    console.log(cmd);
    exec(cmd);
}

function findFileByExtension(dir, extension) {
    return fs.readdirSync(dir).filter(function (file) {
        return fs.lstatSync(path.join(dir, file)).isFile() && extension == path.extname(file);
    });
}

function ensureExtensionExists(dir) {
    if (!fs.existsSync(dir)) {
        console.error('package not found in', dir, 'folder');
        return;
    }
    var extensions = findFileByExtension(dir, '.vsix');
    if (extensions.length < 1) {
        console.error('no package found in', dir, 'folder');
        return;
    }

    return extensions[0];
}

gulp.task('package', function() {
    if (!fs.existsSync(_build))
        shell.mkdir('-p', _build);
    var cmd = 'tfx extension create --manifest-globs ' + manifest + ' --output-path ' + _build;
    executeVerboseCommand(cmd);
});

gulp.task('publish', function() {
    var extension = ensureExtensionExists(_build);
    var cmd = 'tfx extension publish --vsix ' + path.join(_build, extension) + ' --token "' + process.env['VSS.Token'] + '"';
    executeVerboseCommand(cmd);
});

gulp.task('hash', function () {
    var extension = ensureExtensionExists(_build);
    var checksumFile = path.basename(extension) + '.' + checksumAlgorithm;
    console.log('creating checksum file:', checksumFile);
    gulp.src([path.join(_build, '*.vsix')])
        .pipe(hashsum({ 
            hash: 'sha1',
            force: true,
            dest: _build,
            filename: checksumFile,
            delimiter: ' *'
        }));
});

gulp.task('build', function (done) {
    runSequence('clean', 'package', 'hash', done);
});

gulp.task('default', ['build']);