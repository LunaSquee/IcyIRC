# Server stuff! yay!

'use strict'

commander = require 'commander'

paxjson = require __dirname + '/../package.json'
config = require __dirname + '/../script/config'

io = require 'socket.io'
# irc = require './irc'

args = commander
    .command 'icyirc'
    .version paxjson.version
    .option('-d, --dev', 'run in development/debug mode')
    .option('-p, --port <number>', 'set the server http port', config.server.port || 8000)
    .parse process.argv

config.server.port = args.port

if args.dev
    process.env.NODE_ENV = 'development'
    console.log 'running in development mode'

express = require 'express'
defaultRouter = express.Router()
app = express()
inDev = app.get('env') == 'development'

htmloptions =
    root: __dirname + '/../build/document/'
    dotfiles: 'deny'
    maxAge: 365*24*60*60*1000

defaultRouter.get '/', (req, res) ->
    res.sendFile 'index.html', htmloptions

defaultRouter.get '/:server', (req, res) ->
    res.sendFile 'index.html', htmloptions

app.use '/', defaultRouter
app.use '/build/', express.static __dirname + '/../build/', { maxAge: 365*24*60*60*1000 }

# launch the server!
server = app.listen config.server.port, "0.0.0.0", ->
    console.log 'IcyIRC http server listening on port %d', server.address().port

server.on 'error', (err) ->
    console.error 'Server '+err, config.server.port
    process.exit 1

# initialize

sockets = io.listen(server)
sockets.on 'connection', (client) ->
    ircdata = {}
    console.log 'client connected'
    client.on 'clientevent', (data) ->
        switch data.type
            when "initirc"
                console.log 'client initiated'
                ircdata = data.props
                console.log data.props
                client.emit 'ircconnect', data.props
            when "rawinput"
                if data.message == 'testjoin'
                    client.emit 'join', {channel:'#ponies', nick:ircdata.nick, server:ircdata.server}
                    nicks = {channel:'#ponies', nicks:{'best_pony':'~', 'fluttershy':'@', 'rainbowdash':'@', 'squeely':'%', 'pinkiepie':'~', 'applejack':'+','derpy':'+','somepony':''}}
                    nicks.nicks[ircdata.nick] = '~'
                    client.emit 'names', nicks
                if data.message == 'testjoin-more'
                    client.emit 'join', {channel:'#horsie', nick:ircdata.nick, server:ircdata.server}
                    client.emit 'names', {channel:'#horsie', nicks:{'icydiamond':'~', 'squeely':'%', 'pinkiepie':'~', 'applejack':'+','derpy':'+','randomz':''}}
                console.log 'client broadcast'
                console.log data
                client.emit 'echoback', data.message
            when "part"
                console.log 'client requested part from '+data.channel
            when "quit"
                console.log 'client requested connection close'
            when "nick"
                client.emit 'nick', {oldNick: ircdata.nick, nick: data.newNick}
                console.log 'client requested to change nick from '+ircdata.nick+' to '+data.newNick
                ircdata.nick = data.newNick
