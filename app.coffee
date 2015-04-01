require('colors')
Slack = require('slack-client')
slack = new Slack(require('./authToken.coffee'), true, true)


# bot config
channelWhitelist = ['#slackerbots-crib']
signoffMessage = ':parkingduck:'
trigger =
    startGame: /^(slack off with )(\S+)$/
    acceptWord: 'yes'
    abortWord: 'slackerbot abort'
tiles =
    empty: ':black_medium_small_square:'
    player1: ':red_circle:'
    player2: ':large_blue_circle:'

# bot state
gameInProgress = false
playerTwoTurn = false
winner = ''
players =
    one: 'wgodfrey'
    two: '2'
gameGrid = []
pendingRequests = {}

# utility functions
getCurrentPlayerName = ->
    if playerTwoTurn then players.two else players.one
getCurrentPlayerTile = ->
    if playerTwoTurn then tiles.player2 else tiles.player1
addRequest = (opponentName, userName) ->
    pendingRequests[opponentName] = userName
resetRequests = ->
    pendingRequests = {}
gridSize = 8
matchSize = 4
resetGameGrid = ->
    gameGrid = []
    x = 0
    y = 0
    while y < gridSize
        gameGrid[y] ?= []
        x = 0
        while x < gridSize
            gameGrid[y][x] ?=
                owner: ''
            x++
        y++
printGameGrid = (channel) ->
    if winner isnt ''
        loser = if winner is players.one then players.two else players.one
        response = "
            Game over!\n
            @#{winner} slacks better than @#{loser}! :awesomebatman:\n
        "
    else
        response = "#{getCurrentPlayerTile()}
                    It's @#{getCurrentPlayerName()}'s turn\n"

    response += ':one::two::three::four::five::six::seven::eight:\n'
    for y, row of gameGrid
        for x, tile of row
            if tile.owner is players.one
                response += tiles.player1
            else if tile.owner is players.two
                response += tiles.player2
            else
                response += tiles.empty
        response += '\n'
    channel.send(response)
updateGame = (channel, userName, col) ->

    if userName? and col? and userName is getCurrentPlayerName()

        column = parseInt(col)
        if column.toString() is col and column >= 1 and column <= gridSize

            lastRow = null
            i = 0

            checkForWinner = ->

                for y, row of gameGrid
                    for x, item of row
                        if item.owner isnt ''
                            x = parseInt(x, 10)
                            y = parseInt(y, 10)
                            owner = item.owner

                            # mod[0] is the x modifier, mod[1] is the y modifier
                            # this checks only 4 of the 8 possible angles for max efficiency
                            for mod in [[1, -1]]
                                xx = x + (matchSize - 1) * mod[0]
                                minX = Math.min(x, xx)
                                maxX = Math.max(x, xx)
                                yy = y + (matchSize - 1) * mod[1]
                                minY = Math.min(y, yy)
                                maxY = Math.max(y, yy)



#                                if (
#                                    lastX <= gridSize - 1 and
#                                    lastX >= 0 and
#                                    lastY <= gridSize - 1 and
#                                    lastY >= 0
#                                )
#                                    (y - matchSize + 1) >= 0
#                                    count = 0
#                                    ii = 1
#                                    while ii <= matchSize - 1
#                                        if gameGrid[y - ii][x + ii].owner is owner
#                                            count++
#                                        ii++
#                                    console.log count
#                                    if count is matchSize - 1
#                                        winner = owner

            endTurn = ->
                playerTwoTurn = !playerTwoTurn

                checkForWinner()

                cache = players.one
                players.one = players.two
                players.two = cache


                printGameGrid(channel)
                channel.send signoffMessage


            addPiece = ->
                i = gameGrid.length + 1
                if lastRow? # don't do anything if the column is full
                    lastRow[column - 1].owner = userName
                    endTurn()

            while i <= gameGrid.length
                row = gameGrid[i]

                if row?
                    item = row[column - 1]
                    if item.owner isnt '' #
                        addPiece()
                    else
                        lastRow = row

                else # we've fallen off the bottom
                    addPiece()

                i++



slack.on 'open', ->
    resetGameGrid()
    console.log "@#{slack.self.name}".magenta.bold, "is all logged in at".cyan.bold, "#{slack.team.name}.slack.com".magenta.bold

slack.on 'message', (message) ->
    channel = slack.getChannelGroupOrDMByID(message.channel)
    user = slack.getUserByID(message.user)

    {type, ts, text} = message

    channelName = if channel?.is_channel then '#' else ''
    channelName = channelName + if channel then channel.name else 'UNKNOWN_CHANNEL'

    userName = if user?.name? then "#{user.name}" else "UNKNOWN_USER"


    console.log "Received:".cyan.bold,
        "#{type} #{channelName} @#{userName} #{ts} \"#{text}\"".magenta.bold

    if channelName not in channelWhitelist then return

    # if it's a useful message
    if type is 'message' and text? and channel?

        # TODO remove this after dev
        updateGame(channel, userName, text)

        # if it's a trigger to start a game
        if text is trigger.acceptWord and pendingRequests[userName]?

            opponentName = pendingRequests[userName]

            channel.send("
                @#{userName} and @#{opponentName} are now slacking off!\n
                When it's your turn just type the number of the column you want a ball dropped down.
            ")
            channel.send signoffMessage
            gameInProgress = true
            players.one = opponentName
            players.two = userName
            resetRequests()
            printGameGrid(channel)

        else if gameInProgress
            if userName is players.one or userName is players.two
                updateGame(channel, userName, text)
            else
                channel.send("
                    sorry @#{userName}, @#{players.one} and @#{players.two} are already in a game.\n
                    You could politely ask them to type in \"#{trigger.abortWord}\" and end the game early.
                ")
                channel.send signoffMessage

        else if text.match(trigger.startGame) and !gameInProgress

            opponentName = trigger.startGame.exec(text)[2]

            # if we have can find the opponent
            if opponentName? and opponentName isnt userName
                opponent = slack.getUserByName(opponentName)

                if opponent?
                    addRequest(opponentName, userName)
                    channel.send("
                        OK! Just waiting for @#{opponentName} to accept @#{userName}'s
                        offer to slack off.\n
                        @#{opponentName}, just type \"#{trigger.acceptWord}\" to accept.
                    ")
                    channel.send signoffMessage
                else
                    channel.send("I couldn't find @#{opponentName} in this channel.")
                    channel.send signoffMessage

                # over and out


    else
        #this one should probably be impossible, since we're in slack.on 'message'
        typeError = if type isnt 'message' then "unexpected type #{type}." else null
        #Can happen on delete/edit/a few other events
        textError = if not text? then 'text was undefined.' else null
        #In theory some events could happen with no channel
        channelError = if not channel? then 'channel was undefined.' else null

        #Space delimited string of my errors
        errors = [typeError, textError, channelError].filter((element) -> element isnt null).join ' '

        console.log """
      @#{slack.self.name} could not respond. #{errors}
    """


slack.on 'error', (error) ->
    console.error "Error:", error


slack.login()