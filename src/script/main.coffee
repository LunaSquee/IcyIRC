socket = io()

window.irc = window.irc || {}

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
                when 'join' then text = this.get('nick') + ' has joined the channel'
                when 'part' then text = this.get('nick') + ' has left the channel ('+this.get("text")+')'
                when 'quit' then text = this.get('nick') + ' has quit ('+this.get("text")+')'
                when 'action' then text = '* '+ this.get('nick') + ' '+this.get("text")
                when 'nick' then text = this.get('oldNick') + ' is now known as ' + this.get('newNick')
                when 'notice' then text = "["+this.get("nick")+"] " + this.get('text')
                when 'mode' then text = this.get("nick")+' sets mode '+this.get('text')
                when 'topic' then text = this.get("nick")+' set the topic of '+this.get('text')
                when 'raw' then text = this.get("nick")+': '+this.get('text')
                when 'kick' then text = (this.get("kickee")!=irc.me.get("nick")?this.get("kickee")+' has been':'You have been')+ ' kicked by '+this.get("nick")+' (Reason: '+this.get('text')+')'
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
            p = person.get('nick') == nick
            if(p)
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

    linkify: (text) ->
        # see http://daringfireball.net/2010/07/improved_regex_for_matching_urls
        re = /\b((?:https?:\/\/|www\d{0,3}[.]|[a-z0-9.\-]+[.][a-z]{2,4}\/)(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{}:'".,<>?«»“”‘’]))/gi
        parsed = text.replace re, (url) ->
            # turn into a link
            href = url
            if url.indexOf('http') != 0
                href = 'http://' + url
            return '<a href="' + href + '" target="_blank">' + url + '</a>'
        return parsed

    render: =>
        context =
            sender: this.model.get('sender')
            text: this.model.get('text')

        $(@el).addClass(@model.get('type')).html(this.linkify(this.tmpl(context)))
        
        if context.sender && context.sender.toLowerCase() != irc.me.get("nick").toLowerCase()
            if context.text && context.text.indexOf(irc.me.get("nick")) != -1
                $(this.el).addClass("mentioned")
        
        return this

class NickListView extends Backbone.View
    el: $('#userList')
    bound: null
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
        $(this.el).html("")
        this.addAll(participants)

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

    addAll: (participants) ->
        nicksSorted = []
        nicks2 = []
        self = this

        participants.each (p) ->
            nicksSorted.push(p.get('opStatus') + p.get('nick'))

        nicksSorted = this.sortNamesArray(nicksSorted)

        nicksSorted.forEach (e) ->
            opstat = if self.opNickRegex.test(e) then e.substring(0, 1) else ""
            nickn = if self.opNickRegex.test(e) then e.substring(1) else e
            opstatsz = if opstat == '' then "" else '<span class="opstat" title="'+self.getPrefixName(opstat)+'">'+opstat+'</span>'
            nicks2.push('<div class="listednick" id="'+nickn+'">'+opstatsz+' <span class="nickname">'+nickn+'</span></div>')

        $(this.el).html(nicks2.join('\n'))
        ops = this.WhoisOp(nicksSorted)

        #$('#nickcount').text(nicksSorted.length+" User"+ if nicksSorted.length != 1 then "s" else "" +" ("+ops.length+" op"+if ops.length != 1 then "s" else ""+")")

    changeNick: ->
        if this.bound
            this.update(this.bound.participants)

nickList = new NickListView

class FrameView extends Backbone.View
    el: $('#messageView')
    # to track scroll position
    position: {}

    initialize: ->
        console.log 'tab init'

    addMessage: (message, single) ->
        # Only do this on single message additions
        if single
            position = $(this.el).scrollTop()
            atBottom = $(this.el)[0].scrollHeight - position == $(this.el).innerHeight()

        view = new MessageView({model: message})
        $(this.el).append(view.el)
        # Scroll to bottom on new message if already at bottom
        if atBottom
           $(this.el).scrollTop(position + 100)

    updateTopic: (channel) ->
        $('#topicView').text(channel.get('topic'))
        $('#chatArea').addClass("displaytopic")

    # Switch focus to a different frame
    focus: (frame) =>
        # Save scroll position for frame before switching
        if this.focused
            this.position[this.focused.get('name')] = $(this.el).scrollTop()

        self = this
        this.focused = frame
        frames.setActive(this.focused)

        $(this.el).empty()

        frame.stream.each (message) ->
            self.addMessage(message, false)

        nickList.addAll(frame.participants)

        if frame.get('type') == 'channel'
            $('#chatArea').addClass("displaynicklist")
            if frame.get('topic') then this.updateTopic(frame)
        else
            $('#chatArea').removeClass("displaynicklist")
            $('#chatArea').removeClass("displaytopic")
        $(this.el).removeClass().addClass(frame.get('type'))
        position = this.position[frame.get('name')]
        
        $('#messageView').scrollTop((position ? position : 0))
        
        # Only the selected frame should send messages
        frames.each (frm) ->
            frm.stream.unbind('add')
            frm.participants.unbind()
            frm.unbind()

        frame.bind('change:topic', this.updateTopic, this)
        frame.stream.bind('add', this.addMessage, this)
        nickList.switchChannel(frame)

    updateNicks: (model, nicks) ->
        console.log('Nicks rendered')

class FrameTabView extends Backbone.View
    tagName: 'div',
    tmpl: require('template/tab.tmpl.mustache'),

    initialize: ->
        this.model.bind('destroy', this.close, this)
        this.isClosing = false
        this.render()

    events:
        'click .close-frame': 'close'
        'click': 'setActive'

    # Send PART command to server
    part: ->
        #if this.model.get('type') == 'channel'
            #todo: emit part to this.model.get('name')

        mframe = frames.getByName(this.model.get('name'))
        if mframe
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

        d = frames.getByName($(this.el).data('frame'))
        if d != null && d.get('type') != "status"
            this.isClosing = true
            this.part()
            $(this.el).remove()

    setActive: ->
        if this.isClosing
            return
        $(this.el).addClass('active').siblings().removeClass('active')
        irc.frameWindow.focus(this.model)

    render: ->
        context =
            name: this.model.get('name')
            type: this.model.get('type')
        $(this.el).html(this.tmpl(context)).data('frame', context.name)
        return this

    isStatus: ->
        return this.model.get('type') == 'status'

class AppView extends Backbone.View
    el: $('#chatView')
    frameList: $('#tabsArea #tabList')

    initialize: ->
        frames.bind('add', this.addTab, this)
        this.input = this.$('#ircMessage')
        this.render()

    events:
        'keypress #ircMessage': 'sendInput'

    updateNick: ->
        $('#ircNickname').text(irc.me.get('nick'))

    addTab: (frame) ->
        tab = new FrameTabView({model: frame})
        this.frameList.append(tab.el)
        tab.setActive()

    sendInput: (e) ->
        if e.keyCode != 13
            return
        frame = irc.frameWindow.focused
        input = this.input.val()

        if input == null || input == ""
            return

        socket.emit 'rawinput', input

        this.input.val('')

    render: ->
        $('#chatView').show()
        this.updateNick()


class ConnectView extends Backbone.View
    el: $('#startView')

    events:
        'click #irInit': 'connect'
        'keypress': 'connectOnEnter'

    initialize: ->
        this.render()
    
    render: ->
        #this.el.modal({backdrop: true, show: true})
        $('#irNick').focus()
        $('#showMore').click ->
            $('#server-and-port-options').toggleClass("shown")
        
    connectOnEnter: (e) =>
        if (e.keyCode != 13)
        	return
        @connect()

    connect: (e) ->
        e && e.preventDefault()

        if(irc.alreadyConnected)
            return

        irc.alreadyConnected = true
        channelInput = $('#irChannel').val().trim()
        channels = if channelInput then channelInput.split(',') else []
        channels.forEach (obj, index) ->
            if obj.indexOf("#") == -1 and obj.indexOf("&") == -1
                channels[index] = "#"+obj

        connectInfo =
            nick: $('#irNickname').val()
            server: $('#irServer').val()
            port: $('#irPort').val() || 6667
            secure: $('#irSSL').is(':checked')
            channels: channels

        if connectInfo.server == ''
            alert("Server is required.")
            return

        if connectInfo.nick == ''
            alert("Nickname is required.")
            return

        socket.emit 'initirc', connectInfo

        irc.me = new Person({nick: connectInfo.nick})
        
        alert("Connecting..")
            
        irc.frameWindow = new FrameView
        irc.app = new AppView
        # Create the status "frame"
        frames.add({name: connectInfo.server, type: 'status', server:connectInfo.server})

connect = new ConnectView

socket.on 'ircconnect', (stuff) ->
    $('#startView').hide()
    frames.getByName(stuff.server).stream.add({sender: '*', raw: "Connected to server"})

socket.on 'echoback', (message) ->
    frames.getActive().stream.add({sender: irc.me.get('nick'), raw: message})

socket.on 'join', (data) ->
    if data.nick == irc.me.get('nick')
        if !frames.getByName(data.channel)
            frames.add({name: data.channel})
    else
        channel = frames.getByName(data.channel)
        channel.participants.add({nick: data.nick})
        joinMessage = new Message({type: 'join', nick: data.nick})
        joinMessage.setText()
        channel.stream.add(joinMessage)

socket.on 'part', (data) ->
    if data.nick == irc.me.get('nick')
        channel = frames.getByName(data.channel)
        if channel
            partMessage = new Message({type: 'part', nick: data.nick, raw: data.reason})
            partMessage.setText()
            channel.stream.add(partMessage)
            channel.stream.add({type: 'error', raw: "You are no longer talking in "+channel.get("name")})
            channel.participants.reset()
    else
        channel = frames.getByName(data.channel)
        channel.participants.getByNick(data.nick).destroy()
        partMessage = new Message({type: 'part', nick: data.nick, raw: data.reason})
        partMessage.setText()
        channel.stream.add(partMessage)
        if(channel.get("active") == channel)
            nickList.update(channel.participants)

socket.on 'names', (data) ->
    frame = frames.getByName(data.channel)
    for nick, mode of data.nicks
        frame.participants.add({nick: nick, opStatus: mode})