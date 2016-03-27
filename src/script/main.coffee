socket = io()

window.irc = window.irc || {}

window.getURLParam = (param) ->
    sPageURL = window.location.search.substring(1)
    sURLVariables = sPageURL.split '&'
    for index, sURLVariable of sURLVariables
        sParameterName = sURLVariable.split '='
        if sParameterName[0] == param
            return sParameterName[1]

if !String.prototype.isEmpty
    String.prototype.isEmpty = ->
        if this != null && this.length >= 0 && /\S/.test(this)
            return false
        else
            return true

if !String.prototype.hashCode
    String.prototype.hashCode = ->
        hash = 0
        for index, varib of this
           hash = this.charCodeAt(index) + ((hash << 5) - hash)
        return hash

if !String.prototype.startsWith
    String.prototype.startsWith = (c) ->
        if !c.isEmpty() && this.indexOf(c) == 0
            return true
        else
            return false

if !String.prototype.contains
    String.prototype.contains = (c) ->
        if !c.isEmpty() && this.indexOf(c) != -1
            return true
        else
            return false

if !String.prototype.linkify
    String.prototype.linkify = () ->
        text = this || ""
        re = /\b((?:https?:\/\/|www\d{0,3}[.]|[a-z0-9.\-]+[.][a-z]{2,4}\/)(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{}:'".,<>?«»“”‘’]))/gi
        parsed = text.replace re, (url) ->
            href = url
            if url.indexOf('http') != 0
                href = 'http://' + url
            return '<a href="' + href + '" target="_blank">' + url + '</a>'
        return parsed

if !String.prototype.colorize
    String.prototype.colorize = () ->
        text = this || ""
        #control codes
        rex = /\x03([0-9]{1,2})(?:[,]{1}([0-9]{1,2}){1})?([^\x03]+)/
        matches = undefined
        colors = undefined
        if rex.test(text)
            while cp = rex.exec(text)
                if cp[2]
                    cbg = cp[2]
                text = text.replace(cp[0], '<span class="fg' + cp[1] + ' bg' + cbg + '">' + cp[3] + '</span>')
        #bold,italics,underline (more could be added.)
        bui = [
            [ /\x02([^\x02]+)(\x02)?/
                [
                    '<b>'
                    '</b>'
                ]
            ]
            [
                /\x1F([^\x1F]+)(\x1F)?/
                    [
                        '<u>'
                        '</u>'
                    ]
            ]
            [
                /\x1D([^\x1D]+)(\x1D)?/
                [
                    '<i>'
                    '</i>'
                ]
            ]
        ]
        i = 0
        while i < bui.length
            bc = bui[i][0]
            style = bui[i][1]
            if bc.test(text)
                while bmatch = bc.exec(text)
                    text = text.replace(bmatch[0], style[0] + bmatch[1] + style[1])
            i++
        text

class Message extends Backbone.Model
        defaults:
            # expected properties:
            # - sender
            # - raw
            # optionally or afterwards set properties:
            # - kickee (kick message)
            # - time
            'type': 'message'

        initialize: ->
            if this.get('raw')
                this.set({text: this.parse(this.get('raw'))}) #todo: parse and escape
            this.set({time: new Date()})

        parse: (text) ->
            return text

        # Set output text for status messages
        setText: ->
            text = ''
            switch (this.get('type'))
                when 'join'
                    text = this.get('nick') + ' has joined '+this.get('channel')
                when 'part'
                    text = this.get('nick') + ' has left '+this.get('channel')+' ('+this.get("text")+')'
                when 'quit'
                    text = this.get('nick') + ' has quit ('+this.get("text")+')'
                when 'action'
                    text = this.get('nick') + ' '+this.get("text")
                when 'nick'
                    text = this.get('oldNick') + ' is now known as ' + this.get('newNick')
                when 'notice'
                    text = "[NOTICE] " + this.get('text')
                when 'mode'
                    text = this.get("nick")+' sets mode '+this.get('text')
                when 'topic'
                    text = this.get("nick")+' set the topic of '+this.get('text')
                when 'topic_now'
                    text = 'The topic '+this.get('text')
                when 'raw'
                    text = this.get("nick")+': '+this.get('text')
                when 'error'
                    text = this.get('raw')
                when 'kick'
                    pref = if this.get("kickee") != irc.me.get("nick") then this.get("kickee")+' has been' else 'You have been'
                    text = pref+' kicked by '+this.get("nick")+' (Reason: '+this.get('text')+')'
            this.set({text: text})

class Stream extends Backbone.Collection
    model: Message

class Person extends Backbone.Model
    defaults:
        opStatus: ''

class Participants extends Backbone.Collection
    model: Person

    getByNick: (nick) ->
        return this.detect (person) ->
            if person.get('nick').toLowerCase() == nick.toLowerCase()
                return person

class Frame extends Backbone.Model
    defaults:
        'type': 'channel'
        'active': true
        'server':''

    initialize: ->
        this.stream = new Stream
        this.participants = new Participants

class FrameList extends Backbone.Collection
    model: Frame

    getByName: (name) ->
        return this.detect (frame) ->
            if frame.get('name').toLowerCase() == name.toLowerCase()
                return frame

    getByServer: (name) ->
        return this.detect (frame) ->
            if frame.get('server').toLowerCase() == name.toLowerCase()
                return frame

    getActive: ->
        return this.detect (frame) ->
            if frame.get('active') == true
                return frame

    setActive: (frame) ->
        this.each (frm) ->
            frm.set({active: false})

        frame.set({active: true})

    getChannels: ->
        return this.filter (frame) ->
            if frame.get('type') == 'channel'
                return frame

window.frames = new FrameList

# VIEWS
# =====
class MessageView extends Backbone.View
    tmpl: require('template/msg.tmpl.mustache')
    initialize: ->
        this.render()

    render: =>
        context =
            sender: this.model.get('sender')
            text: this.model.get('text')

        $(@el).addClass(@model.get('type')+' message').html this.tmpl(context).linkify()
        $(@el).find('.text').html $(@el).find('.text').html().toString().colorize()

        if context.sender && context.sender.toLowerCase() != irc.me.get("nick").toLowerCase()
            if context.text && context.text.indexOf(irc.me.get("nick")) != -1
                $(this.el).addClass("mentioned")
        
        return this

class NickListView extends Backbone.View
    el: $('#userList'),
    tmpl: require('template/nick.tmpl.mustache'),
    bound: null,

    initialize: ->
        _.bindAll(this)
    
    switchChannel: (ch) ->
        if ch.get("type") == "channel"
            this.bound = ch
        ch.participants.bind('add', this.addOne, this)
        ch.participants.bind('change', this.changeNick, this)
        ch.participants.bind('update', this.update, this)

    addOne: (p) ->
        if this.bound
            this.update(this.bound.participants)
    
    update: (participants) ->
        this.addAll participants

    opNickRegex: new RegExp('^[~&@%+]')

    getPrefixName: (mode) ->
        prefix = ""
        switch(mode)
            when "~" then prefix = "Owner"
            when "&" then prefix = "Admin"
            when "@" then prefix = "Operator"
            when "%" then prefix = "Half-Op"
            when "+" then prefix = "Voice"
        return prefix

    WhoisOp: (names) ->
        ops = []
        names.forEach (e) ->
            if e.startsWith("~") || e.startsWith("&") || e.startsWith("@")
                ops.push(e)
        return ops

    sortNamesArray: (names) ->
        names.sort (a,b) ->
            modes = "~&@%+"
            rex = new RegExp('^['+modes+']')
            nicks = [a.replace(rex,'').toLowerCase(), b.replace(rex,'').toLowerCase()]
            prefix = []

            if rex.test(a)
                prefix.push(modes.indexOf(a[0]))
            else
                prefix.push(modes.length+1)

            if rex.test(b)
                prefix.push(modes.indexOf(b[0]))
            else
                prefix.push(modes.length+1)

            if prefix[0] < prefix[1]
                return -1
            if prefix[0] > prefix[1]
                return 1
            if nicks[0] > nicks[1]
                return 1
            if nicks[0] < nicks[1]
                return -1
            return 0
        return names

    addAll: (participants) =>
        $(this.el).html ""

        nicksSorted = []
        nicks2 = []
        self = this

        participants.each (p) ->
            nicksSorted.push p.get('opStatus') + p.get('nick')

        nicksSorted = this.sortNamesArray(nicksSorted)

        nicksSorted.forEach (e) ->
            opstat = if self.opNickRegex.test(e) then e.substring(0, 1) else null
            nickn = if self.opNickRegex.test(e) then e.substring(1) else e
            prefixname = self.getPrefixName opstat
            context = {nickname: nickn, prefixname: prefixname, grpfix: prefixname.toLowerCase(), opstat: opstat}
            $(self.el).append self.tmpl context

        ops = this.WhoisOp(nicksSorted)
        $('#usercounti').text nicksSorted.length
        $('#usercounto').text '('+ops.length+')'

    changeNick: ->
        if this.bound
            this.update(this.bound.participants)

nickList = new NickListView

class FrameView extends Backbone.View
    el: $('#messageView'),
    position: {},

    initialize: ->
        # idk

    addMessage: (message, single) ->
        # Only do this on single message additions
        if single
            position = $(this.el).scrollTop()
            atBottom = $(this.el)[0].scrollHeight - position == $(this.el).innerHeight()

        view = new MessageView {model: message}
        $(this.el).append(view.el)
        # Scroll to bottom on new message if already at bottom
        if atBottom
           $(this.el).scrollTop position + 100

    updateTopic: (channel) ->
        $('#topicView').html channel.get('topic').linkify()
        $('#chatArea').addClass "displaytopic"

    # Switch focus to a different frame
    focus: (frame) =>
        # Save scroll position for frame before switching
        if @focused
            this.position[@focused.get('name')] = $(@el).scrollTop()

        self = this
        @focused = frame
        frames.setActive(@focused)

        $(@el).empty()

        frame.stream.each (message) ->
            self.addMessage(message, false)

        nickList.addAll(frame.participants)

        if frame.get('type') == 'channel'
            $('#chatArea').addClass "displaynicklist"
            if frame.get 'topic' then this.updateTopic frame
            $('#usercount').show()
        else
            $('#chatArea').removeClass "displaynicklist"
            $('#chatArea').removeClass "displaytopic"
            $('#usercount').hide()
        $(@el).removeClass().addClass frame.get 'type'
        position = this.position[frame.get 'name']
        
        $('#messageView').scrollTop(if position then position else 0)
        
        # Only the selected frame should send messages
        frames.each (frm) ->
            frm.stream.unbind 'add'
            frm.participants.unbind()
            frm.unbind()

        frame.bind('change:topic', this.updateTopic, this)
        frame.stream.bind('add', this.addMessage, this)
        nickList.switchChannel frame

class FrameTabView extends Backbone.View
    tagName: 'div',
    tmpl: require('template/tab.tmpl.mustache'),

    initialize: ->
        this.model.bind('destroy', this.close, this)
        this.isClosing = false
        this.render()
        this.presInput = null

    events:
        'click .close-frame': 'close'
        'click': 'setActive'

    # Send PART command to server
    part: ->
        mframe = frames.getByName(this.model.get('name'))
        if mframe
            if mframe.get("type") == "channel"
                clientToServerSend {type: "part", channel: mframe.get("name"), server: mframe.get("server"), reason: "Tab closed"}
            frames.remove(mframe)
            mframe.destroy()
            this.model.destroy()

    # Close frame
    close: ->
        if $(this.el).hasClass('active')
            if $(this.el).prev().text() != ''
                tabFrame = frames.getByName($(this.el).prev().data('frame'))
                if tabFrame != null
                    if this.model.get('type') != 'status'
                        $(this.el).prev().click()
                    else
                        $(this.el).next().click()

        d = frames.getByName $(this.el).data('frame')
        if d != null && d.get('type') != "status"
            this.isClosing = true
            this.part()
            $(this.el).remove()

    setActive: ->
        if this.isClosing
            return
        
        irc.app.focusChanged this

        $(this.el).addClass('active').siblings().removeClass('active')
        irc.frameWindow.focus this.model

    render: ->
        context =
            name: this.model.get 'name'
            type: this.model.get 'type'
        $(this.el).html(this.tmpl(context)).data('frame', context.name)
        $(this.el).addClass context.type
        return this

    isStatus: ->
        return this.model.get('type') == 'status'

class AppView extends Backbone.View
    el: $('#chatView'),
    frameList: $('#tabsArea #tabList'),
    activeTab: null

    initialize: ->
        frames.bind('add', this.addTab, this)
        this.input = this.$('#ircMessage')

    events:
        'keydown #ircMessage': 'sendInput'
        'click #ircNicknameChange': 'changeNick'

    updateNick: (nick) ->
        $('#ircNickname').text nick
        $('#ircNN').val nick

    addTab: (frame) ->
        tab = new FrameTabView {model: frame}
        this.frameList.append(tab.el)
        if frame.get('type') == 'channel' || frame.get('type') == 'status'
            tab.setActive()

    focusChanged: (tab) ->
        if this.activeTab
            this.activeTab.presInput = this.input.val()
        this.input.val ''
        this.activeTab = tab
        if tab.presInput
            this.input.val tab.presInput

    sendInput: (e) ->
        frame = irc.frameWindow.focused
        if e.keyCode != 13
            return
        input = this.input.val()
        if input == null || input.trim() == ""
            return

        if input.indexOf('/') == 0
            crdarg = input.trim().split(' ')
            cmd = crdarg[0].substring(1)
            switch cmd
                when "join"
                    if crdarg[1] == undefined
                        return errorToFrame(frame, 'Please specify channel.')
                    if crdarg[1].indexOf('#') == -1
                        return errorToFrame(frame, 'Invalid channel name.')
                    clientToServerSend {type: 'join', channel: crdarg[1], server: frame.get("server")}
                when "me"
                    if crdarg[1] == undefined
                        return errorToFrame(frame, 'Can\'t send blank message to server')
                    clientToServerSend {type: 'rawinput', message: crdarg.slice(1).join(' '), target: frame.get("name"), server: frame.get("server"), appendAction: 1}
                when "part"
                    if crdarg[1] == undefined && frame.get("type") != "channel"
                        return errorToFrame(frame, 'Please specify channel.')
                    if crdarg[1]
                        if crdarg[1].indexOf('#') != -1
                            return errorToFrame(frame, 'Invalid channel.')
                        message = "Leaving..."
                        if crdarg[2]
                            message = crdarg.slice(2).join(' ')
                        clientToServerSend {type: 'part', channel: crdarg[1], server: frame.get("server"), reason: message}
                    else
                        clientToServerSend {type: 'part', channel: frame.get("name"), server: frame.get("server"), reason: "Leaving..."}
                when "quit"
                    message = null
                    if crdarg[1]
                        message = crdarg.slice(1).join(' ')
                    clientToServerSend {type: 'quit', server: frame.get("server"), reason: message}
                when "nick"
                    if crdarg[1] == undefined
                        clientToServerSend {type: 'nick', newNick: crdarg[1], server: frame.get("server")}
                when "msg"
                    if crdarg[1] == undefined || crdarg[2] == undefined
                        return errorToFrame(frame, 'Usage: /msg <target> <message>')
                    clientToServerSend {type: 'rawinput', message: crdarg.slice(2).join(' '), target: crdarg[1], server: frame.get("server")}
        else
            clientToServerSend {type: 'rawinput', message: input, target: frame.get("name"), server: frame.get("server")}
        this.input.val ''

    changeNick: (e) ->
        e && e.preventDefault()
        nickn = $('#ircNN').val()
        if nickn == null
            return
        clientToServerSend {type: 'nick', newNick: nickn, server: irc.frameWindow.focused.get("server")}
        $('#nicknamebox').addClass 'invisible'

    render: ->
        $('#chatView').show()
        $('#ircNickname').click (e) ->
            $('#nicknamebox').toggleClass 'invisible'
            $('#ircNN').val irc.me.get 'nick'

        this.updateNick(irc.me.get 'nick')

        $('#startView').hide()
        $(this.el).show()

class ConnectView extends Backbone.View
    el: $('#startView')

    events:
        'click #irInit': 'connect'
        'keypress': 'connectOnEnter'

    initialize: ->
        this.render()
    
    render: ->
        $('#irNick').focus()
        $('#showMore').click ->
            $('#server-and-port-options').toggleClass("shown")
        
        server = window.getURLParam('server')
        port = window.getURLParam('port')
        nickname = window.getURLParam('nick')
        ssl = window.getURLParam('ssl')
        channel = window.location.hash

        if location.pathname.match(/\./g) != null
            server = location.pathname.replace(/\//g, '')

        if server != undefined
            if server.contains ':'
                reminder = server.split ':'
                port = reminder[1]
                server = reminder[0]
            if server.startsWith '+'
                server = server.substring 1
                ssl = 1
            $('#irServer').val server

        if nickname != undefined
            nickname = nickname.replace('?', Math.floor(Math.random() * 1000) + 1)
            $('#irNickname').val nickname

        if port != undefined
            if parseInt port
                port = parseInt port
            else
                port = 6667
            $('#irPort').val port
        
        if channel != undefined
            if !channel.startsWith '#'
                channel = '#' + channel
            $('#irChannel').val channel

        if ssl != undefined
            if parseInt ssl
                if parseInt ssl == 0
                    $('#irSSL').prop 'checked', false
                else
                    $('#irSSL').prop 'checked', true
            else
                $('#irSSL').prop 'checked', true

    connectOnEnter: (e) =>
        if (e.keyCode != 13)
        	return
        @connect()

    connect: (e) ->
        e && e.preventDefault()

        if(irc.alreadyConnected)
            return

        channelInput = $('#irChannel').val().trim()
        channels = if channelInput then channelInput.split(',') else []
        channels.forEach (obj, index) ->
            if obj.indexOf("#") == -1 and obj.indexOf("&") == -1
                channels[index] = "#"+obj

        connectInfo =
            nick: $('#irNickname').val()
            server: $('#irServer').val()
            port: $('#irPort').val() || 6667
            secure: $('#irSSL').is ':checked'
            channels: channels

        if connectInfo.server == ''
            $('#feedback').text "Server is required."
            return

        if connectInfo.nick == ''
            $('#feedback').text "Nickname is required."
            return

        socket.emit 'initirc', connectInfo

        irc.me = new Person {nick: connectInfo.nick}
        
        $('#feedback').text "Connecting.."
        irc.alreadyConnected = true
            
        irc.frameWindow = new FrameView
        irc.app = new AppView
        # Create the status "frame"
        frames.add {name: connectInfo.server, type: 'status', server:connectInfo.server}

connect = new ConnectView

clientToServerSend = (main) ->
    socket.emit 'clientevent', main

errorToFrame = (frame, message) ->
    frame.stream.add new Message {type: 'error', text: message, sender:'***'}

socket.on 'ircconnect', (stuff) ->
    if stuff.error
        frames.getByName(stuff.host).stream.add {sender: '*', raw: stuff.error, type: 'error'}
        $('#feedback').text stuff.error
        irc.alreadyConnected = false
        return

    irc.app.render()
    frames.getByName(stuff.host).stream.add {sender: '*', raw: "Connected to server"}

socket.on 'ircdisconnect', (stuff) ->
    frames.each (ch) ->
        if ch.get('server') == stuff.host
            mess = new Message {type: 'error', raw: "Connection to server closed"}
            mess.setText()
            ch.stream.add mess

socket.on 'echoback', (message) ->
    frames.getActive().stream.add({sender: irc.me.get('nick'), raw: message})

socket.on 'join', (data) ->
    channel = frames.getByName(data.channel)

    if data.nick == irc.me.get('nick')
        if !channel
            channel = frames.add {name: data.channel, type:"channel", server:data.server}
    else
        channel.participants.add {nick: data.nick}

    joinMessage = new Message {type: 'join', nick: data.nick, sender:'-->', channel: data.channel}
    joinMessage.setText()
    channel.stream.add joinMessage

socket.on 'privmsg', (data) ->
    if data.target == irc.me.get('nick')
        target = frames.getByName(data.nick)
        if !target
            target = frames.add {name: data.nick, type:"private", server: data.server}
    else
        target = frames.getByName(data.target)

    if data.message.indexOf('\u0001ACTION') == 0
        data.message = data.message.substring(8)
        nmesg = new Message {type: 'action', nick:data.nick, raw: data.message, sender: '*'}
        nmesg.setText()
        target.stream.add nmesg
    else
        target.stream.add new Message {sender:data.nick, raw: data.message}

socket.on 'notice', (data) ->
    if data.target == irc.me.get('nick')
        target = frames.getByName(data.nick)
        if !target
            target = frames.add {name: data.nick, type:"private", server: data.server}
    else
        target = frames.getByName(data.target)

    notice = new Message {sender:data.nick, raw: data.message, type: 'notice'}
    notice.setText()
    target.stream.add notice

socket.on 'motd', (data) ->
    target = frames.getByName(data.server)
    target.stream.add {sender:'', text: data.message, type: 'motd'}

socket.on 'nick', (data) ->
    if data.oldNick == irc.me.get 'nick'
        irc.me.set {nick: data.nick}
        irc.app.updateNick data.nick

    frames.each (ch) ->
        if ch.get 'name' == data.oldNick
            ch.set {name: data.nick}
            return

        if ch.get 'type' != 'channel'
            return
        
        channel = frames.getByName ch.get 'name'
        if channel
            if channel.participants.getByNick(data.oldNick)
                channel.participants.getByNick(data.oldNick).set {nick: data.nick}
                nickMessage = new Message {type: 'nick', sender: ' ', oldNick: data.oldNick, newNick: data.nick}
                nickMessage.setText()
                channel.stream.add nickMessage

socket.on 'part', (data) ->
    channel = frames.getByName(data.channel)
    if data.nick == irc.me.get('nick')
        if channel
            channel.stream.add new Message {type: 'error', raw: "You are no longer talking in "+channel.get("name")}
            channel.participants.reset()
    else
        channel.participants.getByNick(data.nick).destroy()
        if channel.get("active") == channel
            nickList.update channel.participants
    if channel
        partMessage = new Message {type: 'part', nick: data.nick, raw: data.reason, sender: '<--', channel: data.channel}
        partMessage.setText()
        channel.stream.add partMessage

socket.on 'kick', (data) ->
    channel = frames.getByName(data.channel)
    if data.kickee == irc.me.get('nick')
        if channel
            channel.stream.add new Message {type: 'error', raw: "You are no longer talking in "+channel.get("name")}
            channel.participants.reset()
    else
        channel.participants.getByNick(data.kickee).destroy()
        if channel.get("active") == channel
            nickList.update channel.participants
    if channel
        partMessage = new Message {type: 'kick', nick: data.kicker, raw: data.reason, kickee: data.kickee, channel: data.channel}
        partMessage.setText()
        channel.stream.add partMessage

socket.on 'quit', (data) ->
    frames.each (ch) ->
        if ch.get 'type' != 'channel'
            return
        
        channel = frames.getByName ch.get 'name'
        if channel
            if channel.participants.getByNick(data.nick)
                channel.participants.remove(channel.participants.getByNick(data.nick))
                nickMessage = new Message {type: 'quit', sender: '<--', nick: data.nick, text: data.reason}
                nickMessage.setText()
                channel.stream.add nickMessage

socket.on 'names', (data) ->
    frame = frames.getByName data.channel
    if data['part'] == null
        frame.participants.reset()
    for nick, mode of data.nicks
        frame.participants.add {nick: nick, opStatus: mode}

socket.on 'topic', (data) ->
    channel = frames.getByName data.channel
    if channel
        if data['triggerType'] == 0
            channel.set {topic: data.topic}
            topicmsg = new Message {type: 'topic', nick: data.nick, raw: data.channel+" to \""+data.topic+"\""}
            topicmsg.setText()
            channel.stream.add topicmsg
        else if data['triggerType'] == 1
            channel.set {topic: data.topic}
            topicmsg = new Message {type: 'topic_now', raw: "of "+data.channel+" is \""+data.topic+"\""}
            topicmsg.setText()
            channel.stream.add topicmsg
        else if data['triggerType'] == 2
            topicmsg = new Message {type: 'topic_set_by', text: data.hostmask+" set the topic on "+new Date(parseInt(data.timestamp)*1000)}
            channel.stream.add topicmsg

socket.on 'disconnect', (data) ->
    alert('Connection to IcyIRC server was lost!')
    window.location.reload()