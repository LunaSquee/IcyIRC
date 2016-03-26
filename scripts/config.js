// Give proper credit: https://github.com/daniel-j/parasprite-radio/blob/master/scripts/config.js
var fs = require('fs')
var toml = require('toml')
var filename = __dirname+'/../config.toml'

var config

try {
	config = toml.parse(fs.readFileSync(filename))
} catch (e) {
	throw 'config.toml parse error: ' + e
}

module.exports = config