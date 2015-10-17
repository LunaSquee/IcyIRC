
# nickname!username@hostmask command arg umen ts :trailing
module.exports.parse = (rawInput) ->
    starter = if rawInput.indexOf(':') == 0 then rawInput.substring(1) else rawInput
    pieces = starter.split(' ')
    host = pieces[0]
    hostmask = {nickname: null, username: '', host: '', mask: ''}
    
    # Host

    if host.indexOf("!") != -1
        nickandhost = host.split('!')
        hostmask.nickname = nickandhost[0]
        host = nickandhost[1]

    hostanduser = host.split('@')
    hostmask.username = hostanduser[0]
    hostmask.host = hostanduser[1]
    hostmask.mask = host

    # Command, Trailing and arguments

    prefixless = starter.substring(pieces[0].length+1)
    beforeTrailing = if prefixless.indexOf(' :') != -1 then prefixless.substring(0, prefixless.indexOf(' :')) else prefixless
    argsandcommand = beforeTrailing.split(' ')
    
    command = argsandcommand[0]
    args = argsandcommand.slice(1)

    trailing = if prefixless.indexOf(' :') != -1 then prefixless.substring(prefixless.indexOf(' :')+2) else null

    return {user: hostmask, command: command, arguments: args, trailing: trailing, raw: starter}

# Strip IRC color codes from string
module.exports.stripColors = (str) ->
    return str.replace(/(\x03\d{0,2}(,\d{0,2})?)/g, '')

# Strip IRC style codes from string
module.exports.stripStyle = (str) ->
    return str.replace(/[\x0F\x02\x16\x1F]/g, '')

# Strip IRC formatting from string
module.exports.stripColorsAndStyle = (str) ->
    return stripColors(stripStyle(str))

module.exports.generalizeUsername = (str) ->
    return if str.length > 10 then str.substring 0, 10 else str