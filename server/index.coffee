'use strict'

commander = require 'commander'

paxjson = require __dirname + '/../package.json'
config = require __dirname + '/../scripts/config'
Client = require __dirname + '/client'

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

process.title = config.general.name

express = require 'express'
morgan = require 'morgan'
favicon = require 'serve-favicon'
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

app.use morgan 'dev'
app.use '/', express.static __dirname + '/../build/icons/', { maxAge: 365*24*60*60*1000 }
app.use '/', defaultRouter
app.use '/build/', express.static __dirname + '/../build/', { maxAge: 365*24*60*60*1000 }
app.use favicon __dirname + '/../build/icons/favicon.ico'

server = app.listen config.server.port, "0.0.0.0", ->
    console.log 'IcyIRC http server listening on port %d', server.address().port

server.on 'error', (err) ->
    console.error 'Server: '+err, config.server.port
    process.exit 1

process.on 'uncaughtException', (e) ->
    console.error '[Uncaught exception] ' + e
    console.error e.stack

sockets = io.listen(server)
clients = {}
sockets.on 'connection', (client) ->
    address = client.handshake.address
    console.log client.id+' -> New connection from ' + address

    client.on 'initirc', (props) ->
        clients[client.id] = new Client(props, client)

    client.on 'disconnect', () ->
        console.log(client.id+' -> '+address+' disconnected')
        if clients[client.id]
            clients[client.id].destroy()
            delete clients[client.id]

    client.on 'error', (e) ->
        console.log('error occured')
        console.log(e.stack)

    client.on 'clientevent', (data) ->
        if !clients[client.id]
            return
        clients[client.id].handleInput(data)