'use strict'
let util   = require('util')
let net    = require('net')
let tls    = require('tls')
let events = require('events')
let EventEmitter = events.EventEmitter	

class Connection {
	constructor(config) {
		let self = this
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

		let buffer = ''
		self.connection.on('data', function(chunk) {
			buffer += chunk
			let data = buffer.split('\r\n')
			buffer = data.pop()
			data.forEach(function(line) {
				if(line.indexOf('PING') === 0) {
					self.connection.write('PONG'+line.substring(4)+'\r\n')
					return
				}
				self.emit('raw', line)
			})
		})
		this.serverData = {
			serverName: '',
			version: '',
			userModes: [],
			channelModes: [],
			serverModes: [],
			supports: {}
		}
		this.tempParams = {
			whoisRequests: {},
			whoRequests: {},
			namesRequests: {},
			a005: 1
		}
		EventEmitter.call(this)
	}

	handleConnection() {
		if(this.config.password)
			this.connection.write('PASS '+this.config.password+'\r\n')
		if(this.config.webirc)
			this.connection.write('WEBIRC '+this.config.webirc.password+' '+this.config.username+' '+this.config.webirc.host+' '+this.config.webirc.ip+'\r\n')
		this.connection.write('USER '+this.config.username+' 8 * :'+this.config.realname+'\r\n')
		this.connection.write('NICK '+this.config.nickname+'\r\n')
		this.emit('connection', this.config)
	}
}
util.inherits(Connection, EventEmitter)

module.exports = Connection