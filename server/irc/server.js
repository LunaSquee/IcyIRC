var util   = require('util')
var net    = require('net')
var tls    = require('tls')
var events = require('events')
var EventEmitter = events.EventEmitter	

function Connection(config) {
	var self = this
	self.config = config
	self.connection = net.createConnection(config.port || 6667, config.host, function() {
		self.handleConnection()
	})
	self.connection.setEncoding('utf8')
	self.connection.setTimeout(config.timeout)

	self.connection.on('error', function(data) {
		self.emit('closed', {type: 'error', data: data})
	})

	self.connection.on('close', function(data) {
		self.emit('closed', {type: 'close', data: data})
	})

	self.connection.on('end', function(data) {
		self.emit('closed', {type: 'end', data: data})
	})

	var buffer = ''
	self.connection.on('data', function(chunk) {
		buffer += chunk
		var data = buffer.split('\r\n')
		buffer = data.pop()
		data.forEach(function(line) {
			console.log (line)
			if(line.indexOf('PING') === 0) {
				self.connection.write('PONG'+line.substring(4))
				return
			}
			self.emit('raw', line)
		})
	})

	EventEmitter.call(this)
}
util.inherits(Connection, EventEmitter)

Connection.prototype.handleConnection = function() {
	if(this.config.password)
		this.connection.write('PASS '+this.config.password+'\r\n')
	if(this.config.webirc)
		this.connection.write('WEBIRC '+this.config.webirc.password+' '+this.config.username+' '+this.config.webirc.host+' '+this.config.webirc.ip+'\r\n')
	this.connection.write('USER '+this.config.username+' 8 * :'+this.config.realname+'\r\n')
	this.connection.write('NICK '+this.config.nickname+'\r\n')
	this.emit('connection', this.config)
}

module.exports.Connection = Connection