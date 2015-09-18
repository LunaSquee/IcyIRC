# Server stuff! yay!

'use strict'

commander = require 'commander'

paxjson = require __dirname + '/../package.json'
config = require __dirname + '/../script/config'

io = require 'socket.io'

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
    console.log 'client connected'
    client.on 'initirc', (props) ->
        console.log 'client broadcast '+props
        client.emit 'ircconnect'