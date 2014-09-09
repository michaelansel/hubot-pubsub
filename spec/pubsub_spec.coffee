path = require 'path'
Robot = require 'hubot/src/robot'
messages = require 'hubot/src/message'

describe 'pubsub', ->

  robot = null
  adapter = null
  user = null
  userDirect = null

  say = (msg) ->
    adapter.receive new messages.TextMessage(user, msg)

  sayDirect = (msg) ->
    adapter.receive new messages.TextMessage(userDirect, msg)

  expectHubotToSay = (msg, done) ->
    adapter.on 'send', (envelope, strings) ->
      (expect strings[0]).toMatch msg
      done()

  captureHubotOutput = (captured, done) ->
    adapter.on 'send', (envelope, strings) ->
      unless strings[0] in captured
        captured.push strings[0]
        done()

  beforeEach ->
    ready = false

    runs ->
      robot = new Robot(null, 'mock-adapter', false, 'Hubot')

      robot.adapter.on 'connected', ->
        (require '../src/pubsub')(robot)

        user = robot.brain.userForId('1', name: 'jasmine', room: '#jasmine')
        userDirect = robot.brain.userForId('2', name: 'jasmineDirect')
        adapter = robot.adapter
        ready = true

      robot.run()

    waitsFor -> ready

  afterEach ->
    robot.shutdown()

  it 'lists current room subscriptions when none are present', (done) ->
    expectHubotToSay 'Total subscriptions for #jasmine: 0', done
    say 'hubot subscriptions'

  it 'lists current room subscriptions (old style)', (done) ->
    robot.brain.data.subscriptions =
      'foo.bar': [ '#jasmine', '#other' ]
      'baz': [ '#foo', '#jasmine' ]

    count = 0
    captured = []

    doneLatch = ->
      count += 1
      if count == 3
        (expect 'foo.bar -> #jasmine' in captured).toBeTruthy()
        (expect 'baz -> #jasmine' in captured).toBeTruthy()
        (expect 'Total subscriptions for #jasmine: 2' in captured).toBeTruthy()
        done()

    captureHubotOutput captured, doneLatch
    captureHubotOutput captured, doneLatch
    captureHubotOutput captured, doneLatch

    say 'hubot subscriptions'

  it 'lists current room subscriptions (new style)', (done) ->
    robot.brain.data.subscriptions =
      'foo.bar': [ {room:'#jasmine'}, {room:'#other'} ]
      'baz': [ {room:'#foo'}, {room:'#jasmine'} ]

    count = 0
    captured = []

    doneLatch = ->
      count += 1
      if count == 3
        (expect 'foo.bar -> #jasmine' in captured).toBeTruthy()
        (expect 'baz -> #jasmine' in captured).toBeTruthy()
        (expect 'Total subscriptions for #jasmine: 2' in captured).toBeTruthy()
        done()

    captureHubotOutput captured, doneLatch
    captureHubotOutput captured, doneLatch
    captureHubotOutput captured, doneLatch

    say 'hubot subscriptions'

  it 'lists current user subscriptions', (done) ->
    robot.brain.data.subscriptions =
      'foo.bar': [ robot.brain.userForId('2'), {room: '#other'} ]
      'baz': [ {room: '#foo'}, robot.brain.userForId('2') ]

    count = 0
    captured = []

    doneLatch = ->
      count += 1
      if count == 3
        (expect 'foo.bar -> @jasmineDirect' in captured).toBeTruthy()
        (expect 'baz -> @jasmineDirect' in captured).toBeTruthy()
        (expect 'Total subscriptions for @jasmineDirect: 2' in captured).toBeTruthy()
        done()

    captureHubotOutput captured, doneLatch
    captureHubotOutput captured, doneLatch
    captureHubotOutput captured, doneLatch

    sayDirect 'hubot subscriptions'

  it 'lists all subscriptions', (done) ->
    expectHubotToSay 'Total subscriptions: 0', done
    say 'hubot all subscriptions'

  it 'subscribes a room', (done) ->
    expectHubotToSay 'Subscribed #jasmine to foo.bar events', ->
      (expect robot.brain.data.subscriptions['foo.bar']).toEqual [ { room: '#jasmine' } ]
      done()

    say 'hubot subscribe foo.bar'

  it 'subscribes a user', (done) ->
    expectHubotToSay 'Subscribed @jasmineDirect to foo.bar events', ->
      (expect robot.brain.data.subscriptions['foo.bar']).toEqual [ robot.brain.userForId('2') ]
      done()

    sayDirect 'hubot subscribe foo.bar'

  it 'cannot unsubscribe a room which was not subscribed', (done) ->
    expectHubotToSay '#jasmine was not subscribed to foo.bar events', done
    say 'hubot unsubscribe foo.bar'

  it 'unsubscribes a room (old style)', (done) ->
    robot.brain.data.subscriptions = 'foo.bar': [ '#jasmine' ]

    expectHubotToSay 'Unsubscribed #jasmine from foo.bar events', ->
      (expect robot.brain.data.subscriptions['foo.bar']).toEqual [ ]
      done()

    say 'hubot unsubscribe foo.bar'

  it 'unsubscribes a room (new style)', (done) ->
    robot.brain.data.subscriptions = 'foo.bar': [ {room: '#jasmine'} ]

    expectHubotToSay 'Unsubscribed #jasmine from foo.bar events', ->
      (expect robot.brain.data.subscriptions['foo.bar']).toEqual [ ]
      done()

    say 'hubot unsubscribe foo.bar'

  it 'unsubscribes a user', (done) ->
    robot.brain.data.subscriptions = 'foo.bar': [ robot.brain.userForId('2') ]

    expectHubotToSay 'Unsubscribed @jasmineDirect from foo.bar events', ->
      (expect robot.brain.data.subscriptions['foo.bar']).toEqual [ ]
      done()

    sayDirect 'hubot unsubscribe foo.bar'

  it 'allows subscribing all unsubscribed events for debugging', (done) ->
    robot.brain.data.subscriptions = 'unsubscribed.event': [ '#jasmine' ]

    count = 0
    captured = []

    doneLatch = ->
      count += 1
      if count == 2
        (expect 'unsubscribed.event: unrouted: no one should receive it' in captured).toBeTruthy()
        (expect 'Notified 0 targets about unrouted' in captured).toBeTruthy()
        done()

    captureHubotOutput captured, doneLatch

    say 'hubot publish unrouted no one should receive it'

  it 'allows subscribing to namespaces', (done) ->
    robot.brain.data.subscriptions = 'errors.critical': [ '#jasmine' ]

    count = 0
    captured = []

    doneLatch = ->
      (expect 'errors.critical.subsystem: blew up!' in captured).toBeTruthy()
      done()

    captureHubotOutput captured, doneLatch

    say 'hubot publish errors.critical.subsystem blew up!'

  it 'handles pubsub:publish event', (done) ->
    robot.brain.data.subscriptions = 'alien.event': [ '#jasmine' ]

    count = 0
    captured = []

    doneLatch = ->
      (expect 'alien.event: hi from other script' in captured).toBeTruthy()
      done()

    captureHubotOutput captured, doneLatch

    robot.emit 'pubsub:publish', 'alien.event', 'hi from other script'


