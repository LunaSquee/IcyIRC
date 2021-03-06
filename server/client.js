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
			} else if(t.type === 'end') {
				self.wsocket.emit('ircdisconnect', { host: config.host })
				if(self.connections[config.host])
					delete self.connections[config.host]
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
					sender = parsed.arguments[0]
					target = config.host
				}
				self.wsocket.emit('notice', { message: parsed.trailing, nick: sender, target: target, server: config.host })
				break
			case 'PRIVMSG':
				if(parsed.trailing.indexOf('\u0001') === 0 && parsed.trailing.indexOf('\u0001ACTION') !== 0)
					return self.handleCTCP(parsed, connection, config)
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
			case 'MODE':
				/*
					User mode on channel:
					  arguments: [ '#parasprite', '+o', 'BestPony' ],
					  trailing: null,
					Channel modes:
					  arguments: [ '#parasprite', '+nt' ],
					  trailing: null,
				*/
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
						if(t[0] === 'PREFIX') {
							let d = t[1].match(/\((\w+)\)(.*)/)
							let r = d[1].split('')
							let aa = d[2].split('')
							for(let b in r)
								connection.serverData.prefixes[r[b]] = aa[b]
						}
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
					console.log(connection.serverData)
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
			case 'TOPIC':
				self.wsocket.emit('topic', { triggerType: 0, nick: parsed.prefix.nickname, topic: parsed.trailing, channel: parsed.arguments[0], server: config.host })
				break
			case '332':
				self.wsocket.emit('topic', { triggerType: 1, topic: parsed.trailing, channel: parsed.arguments[1], server: config.host })
				break
			case '333':
				self.wsocket.emit('topic', { triggerType: 2, hostmask: parsed.arguments[2], channel: parsed.arguments[1], timestamp: parsed.arguments[3], server: config.host })
				break
		}
	}

	destroy() {
		for(let t in this.connections) {
			this.connections[t].connection.write('QUIT :'+config.irc.default_quit_msg+'\r\n')
			delete this.connections[t]
		}
	}

	handleCTCP(parsed, connection, conf) {
		let ctCmd = parsed.trailing.trim().split(' ')

		for(let i in ctCmd)
			ctCmd[i] = ctCmd[i].replace(/\u0001/g, '')
		
		let ctcp = ctCmd[0]
		let result = ''

		switch(ctcp) {
			case 'VERSION':
				result = config.general.name + ' version '+config.general.version
				break
			case 'SOURCE':
				result = 'https://github.com/LunaSquee/IcyIRC'
				break
			case 'PING':
				result = ctCmd.slice(1).join(' ')
				break
			case 'CLIENTINFO':
				result = 'VERSION SOURCE PING CLIENTINFO'
				break
			default:
				result = 0
		}
		connection.connection.write('NOTICE '+parsed.prefix.nickname+' :\x01'+ctcp+' '+result+'\x01\r\n')
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
				let reason = data.reason != null ? data.reason : config.irc.default_quit_msg
				t.connection.write('QUIT :'+reason+'\r\n')
				delete this.connections[data.server]
				break
		}
	}
}

module.exports = Client