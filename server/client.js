'use strict'
let util = require('util')
let dns = require('dns')
let config = require(__dirname + '/../scripts/config')
let Connector = require(__dirname+'/irc/server')
let parser = require(__dirname+'/parser')

class Client {
	constructor(ircData, wsocket) {
		this.nickname = ircData.nick
		this.wsocket = wsocket
		this.createIRC({
			nickname: ircData.nick,
			host: ircData.server,
			port: ircData.port || 6667,
			autojoin: ircData.channels || [],
			password: ircData.password || null,
			username: config.general.name.toLowerCase(),
			realname: '['+config.general.name+'] '+ircData.nick,
			timeout: 0,
			webirc: null/*{
				password: config.irc.webirc.password,
				ip: wsocket.handshake.address,
				hostname: null
			}*/
		})
		this.connections = {}
	}

	createIRC(config) {
		let connection = new Connector(config)
		let self = this

		connection.on('connection', function() {
			console.log('establised')
			console.log(config)
			
			self.connections[config.host] = connection
			self.wsocket.emit('ircconnect', config)
		})

		connection.on('closed', function(t) {
			var msg = 'Failed to connect to the server.'
			if(t.type === 'error') {
				switch(t.data.code) {
					case 'ENOTFOUND':
						msg = 'Failed to connect: The IRC server at '+config.host+':'+config.port+' was not found'
						break
				}
				self.wsocket.emit('ircconnect', { host: config.host, error: msg })
			}
		})

		connection.on('raw', function(line) {
			console.log(line)
			self.handleResponse(line, connection, connection.config)
		})
	}

	handleResponse(line, connection, config) {
		let parsed = parser.parse(line)
		let self = this
		console.log(parsed)
		switch(parsed.command) {
			case 'NOTICE':
				let sender = parsed.prefix.nickname
				let target = parsed.arguments[0]
				if(sender == null) {
					sender = ''
					target = config.host
				}
				self.wsocket.emit('notice', { message: parsed.trailing, nick: sender, target: target, server: config.host })
				break
			case 'PRIVMSG':
				self.wsocket.emit('privmsg', { message: parsed.trailing, nick: parsed.prefix.nickname, target: parsed.arguments[0], server: config.host })
				break
			case '375':
			case '372':
			case '376':
				self.wsocket.emit('motd', { message: parsed.trailing, server: config.host })
				break
			case 'JOIN':
				if(parsed.prefix.nickname == config.nickname)
					connection.tempParams.namesRequests[parsed.trailing] = 1
				self.wsocket.emit('join', { channel: parsed.trailing, nick: parsed.prefix.nickname, server: config.host })
				break
			case 'PART':
				self.wsocket.emit('part', { channel: parsed.arguments[0], nick: parsed.prefix.nickname, reason: parsed.trailing || '', server: config.host })
				break
			case 'QUIT':
				self.wsocket.emit('quit', { nick: parsed.prefix.nickname, reason: parsed.trailing || '', server: config.host })
				break
			case 'NICK':
				let oldNick = parsed.prefix.nickname
				if(oldNick === config.nickname)
					connection.config.nickname = parsed.trailing
				self.wsocket.emit('nick', { oldNick: oldNick, nick: parsed.trailing, server: config.host })
				break
			case 'KICK':
				self.wsocket.emit('kick', { kicker: parsed.prefix.nickname, kickee: parsed.arguments[1], channel: parsed.arguments[0], reason: parsed.trailing || '' })
				break
			case '004':
				connection.serverData.serverName = parsed.arguments[1]
				connection.serverData.version = parsed.arguments[2]
				connection.serverData.userModes = ( parsed.arguments[3] != null ? parsed.arguments[3].split('') : [] )
				connection.serverData.channelModes = ( parsed.arguments[4] != null ? parsed.arguments[4].split('') : [] )
				connection.serverData.serverModes = ( parsed.arguments[5] != null ? parsed.arguments[5].split('') : [] )
				break
			case '005':
				let argv = parsed.arguments.slice(1)
				for(let a in argv) {
					let t = argv[a]
					if(t.indexOf('=') != -1) {
						t = t.split('=')
						connection.serverData.supports[t[0]] = t[1]
					} else {
						connection.serverData.supports[t] = true
					}
				}
				connection.tempParams.a005 += 1

				if(config.autojoin && connection.tempParams.a005 == 3) {
					for(let t in config.autojoin)
						connection.connection.write('JOIN '+config.autojoin[t]+'\r\n')
					connection.tempParams.a005 = 4
				}
				break
			case '353':
				let f = parsed.trailing.trim().split(' ')
				let lpt = {channel: parsed.arguments[2], nicks: {}, server: config.host, part: (connection.tempParams.namesRequests[parsed.arguments[2]] != null ? 1 : null)}
				for(let t in f) {
					t = f[t]
					let nick = t
					let mode = t.match(/^\@|\&|\+|\~|\!|\%/)
					if(mode && t.indexOf(mode[0]) === 0) {
						mode = mode[0]
						nick = t.substring(1)
					} else {
						mode = ''
					}
					lpt.nicks[nick] = mode
				}
				self.wsocket.emit('names', lpt)
				break
			case '366':
				if(parsed.arguments[1] in connection.tempParams.namesRequests)
					delete connection.tempParams.namesRequests[parsed.arguments[1]]
		}
	}

	destroy() {
		for(let t in this.connections) {
			this.connections[t].connection.write('QUIT '+config.irc.default_quit_msg+'\r\n')
			delete this.connections[t]
			//this.connections[t].connection.end()
		}
	}

	handleInput(data) {
		let self = this
		let t = self.connections[data.server]
		if(!t) return
		switch(data.type) {
			case 'rawinput':
				if(data['appendAction'] != null)
					data.message = '\x01ACTION '+data.message+'\x01'
				self.wsocket.emit('privmsg', {nick: t.config.nickname, message: data.message, target: data.target})
				t.connection.write('PRIVMSG '+data.target+' :'+data.message+'\r\n')
				break
			case 'part':
				t.connection.write('PART '+data.channel+' :'+data.reason+'\r\n')
				break
			case 'join':
				t.connection.write('JOIN '+data.channel+'\r\n')
				break
			case 'nick':
				t.connection.write('NICK '+data.newNick+'\r\n')
				break
			case 'quit':
				t.connection.write('QUIT :'+data.reason || config.irc.default_quit_msg+'\r\n')
				break
		}
	}
}

module.exports = Client