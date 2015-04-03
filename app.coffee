require('colors')
config = require('./config.coffee')
Slack = require('slack-client')
slack = new Slack(require('./authToken.coffee'), true, true)


# static config
{
    defaultGridSize
    defaultMatchSize
    allowedChannel
    signoffMessage
    winningEmote
} = config

# bot state
columnHeaders = ''
gameInProgress = false
playerTwoTurn = false
winner = ''
players =
    one: ''
    two: ''
gameGrid = []
pendingRequests = {}
gridSize = 0
matchSize = 0
tileCount = 0
ownedTileCount = 0

# utility variables
trigger =
    startGame: /^slack off with (\S+)( size ([1-9]([0-9])?) match ([1-9]([0-9])?))?$/i
    acceptWord: 'yes'
    abortWord: 'quit'
tiles =
    empty: ':black_medium_small_square:'
    winning: ':sunny:'
    player1: ':red_circle:'
    player2: ':large_blue_circle:'
    numbers: [
        ':one:'
        ':two:'
        ':three:'
        ':four:'
        ':five:'
        ':six:'
        ':seven:'
        ':eight:'
        ':nine:'
        ':keycap_ten:'
    ]

# utility functions
generateColumnNumbers = ->
    columnHeaders = ''
    i = 0
    while (i <= gridSize - 1)
        columnHeaders += tiles.numbers[i]
        i++

getCurrentPlayerName = ->
    if playerTwoTurn then players.two else players.one

getCurrentPlayerTile = ->
    if playerTwoTurn then tiles.player2 else tiles.player1

addRequest = (opponentName, userName, grid, match) ->
    pendingRequests[opponentName] =
        userName: userName
        gridSize: grid
        matchSize: match

resetRequests = ->
    pendingRequests = {}

startGame = (channel, player1, player2) ->
    gameInProgress = true
    players.one = player1
    players.two = player2
    resetGameGrid()
    generateColumnNumbers()
    resetRequests()
    printGameGrid(channel)

endGame = ->
    gameInProgress = false
    playerTwoTurn = false
    players.one = ''
    players.two = ''
    winner = ''
    gridSize = 0
    matchSize = 0
    tileCount = 0
    ownedTileCount = 0

resetGameGrid = =>
    gameGrid = []
    tileCount = 0
    x = 0
    y = 0
    while y < gridSize
        gameGrid[y] = []
        x = 0
        while x < gridSize
            gameGrid[y][x] =
                owner: ''
                winningTile: false
            tileCount++
            x++
        y++

printGameGrid = (channel) ->
    if winner isnt ''
        loser = if winner is players.one then players.two else players.one
        response = "
            Game over!\n
            @#{winner} is a bigger slacker than @#{loser}! #{winningEmote}\n
        "
    else if ownedTileCount is tileCount
        response = "
            It's a draw! Game over!\n
            Maybe @#{players.one} and @#{players.two} are really the same person.\n
        "
    else
        response = "
                    #{getCurrentPlayerTile()}
                    It's @#{getCurrentPlayerName()}'s turn.\n
                   "

    response += "#{columnHeaders}\n"
    for y, row of gameGrid
        for x, tile of row
            if tile.winningTile
                response += tiles.winning
            else if tile.owner is players.one
                response += tiles.player1
            else if tile.owner is players.two
                response += tiles.player2
            else
                response += tiles.empty
        response += '\n'
    channel.send(response)
updateGame = (channel, userName, text) ->

    if text is trigger.abortWord
        channel.send("
            Game over!\n
            @#{userName} was too much of a slacker to finish the game and gave up! #{winningEmote}
        ")
        endGame()
        return

    if userName? and text? and userName is getCurrentPlayerName()

        column = parseInt(text, 10) - 1
        if parseInt(text, 10).toString() is text and column >= 0 and column <= gridSize - 1

            lastCoords = null
            i = 0

            checkForWinner = (x, y) ->
                x = parseInt(x, 10)
                y = parseInt(y, 10)
                owner = userName

                # mod[0] is the x modifier, mod[1] is the y modifier
                # each mod makes the algorithm check a different direction
                for mod in [[1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1]]#
                    xx = x + ((matchSize - 1) * mod[0])
                    minX = Math.min(x, xx)
                    maxX = Math.max(x, xx)

                    yy = y + ((matchSize - 1) * mod[1])
                    minY = Math.min(y, yy)
                    maxY = Math.max(y, yy)

                    # if we're not going to fall over the edge
                    if (
                        maxX <= gridSize - 1 and
                        minX >= 0 and
                        maxY <= gridSize - 1 and
                        minY >= 0
                    )
                        # check if we've got a winner
                        _x = x
                        _y = y
                        targetIterations = matchSize
                        count = 0
                        tileRefs = []
                        while (targetIterations > 0)
                            if gameGrid[_y][_x].owner is owner
                                count++
                                tileRefs.push(gameGrid[_y][_x])
                            _x += mod[0]
                            _y += mod[1]
                            targetIterations--

                        # if we've got a winner
                        if count is matchSize
                            winner = owner
                            for tile in tileRefs
                                tile.winningTile = true;

            endTurn = ->
                checkForWinner(lastCoords.x, lastCoords.y)
                playerTwoTurn = !playerTwoTurn
                printGameGrid(channel)
                channel.send signoffMessage

                if winner isnt '' or ownedTileCount is tileCount
                    endGame()

            addPiece = ->
                ownedTileCount++
                i = gameGrid.length + 1
                if lastCoords? # don't do anything if the column is full
                    gameGrid[lastCoords.y][lastCoords.x].owner = userName
                    endTurn()

            while i <= gameGrid.length
                row = gameGrid[i]

                if row?
                    item = row[column]
                    if item.owner isnt ''
                        addPiece()
                    else
                        lastCoords =
                            x: column
                            y: i

                else # we've fallen off the bottom
                    addPiece()
                i++



slack.on 'open', ->
    console.log "@#{slack.self.name}".magenta.bold, "is all logged in at".cyan.bold, "#{slack.team.name}.slack.com".magenta.bold

slack.on 'message', (message) ->
    channel = slack.getChannelGroupOrDMByID(message.channel)
    user = slack.getUserByID(message.user)

    {type, ts, text} = message

    channelName = if channel?.is_channel then '#' else ''
    channelName = channelName + if channel then channel.name else 'UNKNOWN_CHANNEL'

    userName = if user?.name? then "#{user.name}" else "UNKNOWN_USER"

    if userName isnt slack.self.name

        console.log "Received:".cyan.bold,
            "#{type} #{channelName} @#{userName} #{ts} \"#{text}\"".magenta.bold

        if channelName isnt allowedChannel then return

        # if it's a useful message
        if type is 'message' and text? and channel?

            # if it's a trigger to start a game
            if text is trigger.acceptWord and pendingRequests[userName]?

                request = pendingRequests[userName]
                opponentName = request.userName
                gridSize = request.gridSize
                matchSize = request.matchSize

                channel.send("
                    @#{userName} and @#{opponentName} are now slacking off!\n
                    When it's your turn just type the number of the column you want a ball dropped down.\n
                    Type in \"#{trigger.abortWord} to leave the game at any time.\n
                    First to get #{matchSize} in a row is ze winzor.\n
                ")
                channel.send signoffMessage
                startGame(channel, opponentName, userName)

            else if gameInProgress
                if userName is players.one or userName is players.two
                    updateGame(channel, userName, text)
                else if text.match(trigger.startGame)
                    channel.send("
                        Sorry @#{userName}, @#{players.one} and @#{players.two} are already in a game.\n
                        You could ask one of them really nicely to type in \"#{trigger.abortWord}\" if they're taking too long.
                    ")
                    channel.send signoffMessage

            else if text.match(trigger.startGame) and !gameInProgress


                options = trigger.startGame.exec(text)
                opponentName = options[1]
                _gridSize = parseInt(options[3], 10)
                _matchSize = parseInt(options[5], 10)

                # decode user IDs
                encodedUsernameMatch = opponentName.match(/^<@(\S+)>$/)
                if encodedUsernameMatch
                    opponentName = slack.getUserByID(encodedUsernameMatch[1]).name

                # handle game options and natural language error handling
                if (
                    !options[3]? or
                    !options[5]?
                )
                    _gridSize = defaultGridSize
                    _matchSize = defaultMatchSize

                else
                    gridSizeError = ''
                    matchSizeError = ''

                    if _gridSize < 4
                        gridSizeError = 'smaller than 4'
                    else if _gridSize > 10
                        gridSizeError = 'bigger than 10'


                    if _matchSize < 2
                        matchSizeError = 'greater than 1'
                    else if _matchSize >= _gridSize
                        matchSizeError = 'less than the grid size'

                    error = "Hold up! "

                    if gridSizeError isnt ''
                        error += "We can't have a grid #{gridSizeError}"

                    if matchSizeError isnt ''
                        if gridSizeError
                            error += ". Also, the match size must be #{matchSizeError}."
                        else
                            error += "The match size must be #{matchSizeError}."

                    else
                        error += '.'

                    if gridSizeError or matchSizeError
                        channel.send(error)
                        channel.send(signoffMessage)
                        return

                # if we have can find the opponent
                if opponentName? and opponentName isnt userName
                    opponent = slack.getUserByName(opponentName)

                    if opponent?
                        addRequest(opponentName, userName, _gridSize, _matchSize)
                        channel.send("
                            OK! Just waiting for @#{opponentName} to accept @#{userName}'s
                            offer to slack off.\n
                            Size #{_gridSize}, match #{_matchSize}.\n
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