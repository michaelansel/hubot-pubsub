# Description:
#   Pub-Sub notification system for Hubot.
#   Subscribe rooms to various event notifications and publish them
#   via HTTP requests or chat messages.
#
# Dependencies:
#   None
#
# Configuration:
#   HUBOT_SUBSCRIPTIONS_PASSWORD (optional)
#
# Commands:
#   hubot subscribe <event> - subscribes current room (or user if PM) to event. To debug, subscribe to 'unsubscribed.event'
#   hubot unsubscribe <event> - unsubscribes current room (or user if PM) from event
#   hubot unsubscribe all events - unsubscribes current room (or user if PM) from all events
#   hubot subscriptions - show subscriptions of current room (or user if PM)
#   hubot all subscriptions - show all existing subscriptions
#   hubot publish <event> <data> - triggers event
#
# URLS:
#   GET /publish?event=<event>&data=<text>[&password=<password>]
#   POST /publish (Content-Type: application/json, {"password": "optional", "event": "event", "data": "text" })
#
# Events:
#   pubsub:publish <event> <data> - publishes an event from another script
#
# Author:
#   spajus, michaelansel

module.exports = (robot) ->

  url = require('url')
  querystring = require('querystring')

  sendMessageToTarget = (target, message) ->
    robot.logger.debug "Sending message to #{JSON.stringify target}: #{message}"
    if typeof target is 'string'
      # deprecated
      envelope = {}
      envelope.room = target
    else
      envelope = {user: target}
      envelope.room = envelope.user.room
    robot.send envelope, message

  printableTarget = (target) ->
    if typeof target is 'string'
      # deprecated
      return '#' + (target.replace /@.*$/,'')
    else if target.room?
      return '#' + (target.room.replace /^#/,'')
    else
      return '@' + target.name

  targetFromMessage = (msg) ->
    target = msg.message.user
    return target

  subscriptions = (ev, partial = false) ->
    subs = robot.brain.data.subscriptions ||= {}
    if ev
      if '.' in ev and partial
        matched = []
        ev_parts = ev.split('.')
        while ev_parts.length > 0
          sub_ev = ev_parts.join('.')
          if subs[sub_ev]
            for e in subs[sub_ev]
              matched.push e unless e in matched
          ev_parts.pop()
        matched
      else
        subs[ev] ||= []
    else
      subs

  notify = (event, data) ->
    count = 0
    subs = subscriptions(event, true)
    if event && subs
      for target in subs
        count += 1
        sendMessageToTarget target, "#{event}: #{data}"
    unless count > 0
      console.log "hubot-pubsub: unsubscribed.event: #{event}: #{data}"
      for target in subscriptions('unsubscribed.event')
        sendMessageToTarget target, "unsubscribed.event: #{event}: #{data}"
    count

  persist = (subscriptions) ->
    robot.brain.data.subscriptions = subscriptions
    robot.brain.save()

  robot.respond /subscribe ([a-z0-9\-\.\:]+)$/i, (msg) ->
    ev = msg.match[1]
    target = targetFromMessage msg
    subscriptions(ev).push target
    persist subscriptions()
    msg.send "Subscribed #{printableTarget target} to #{ev} events"

  robot.respond /unsubscribe ([a-z0-9\-\.\:]+)$/i, (msg) ->
    ev = msg.match[1]
    subs = subscriptions()
    subs[ev] ||= []
    target = targetFromMessage msg
    if target in subs[ev] or
       # deprecated
       (target.room? and target.room in subs[ev])
      if target in subs[ev]
        index = subs[ev].indexOf target
      else
        # deprecated
        index = subs[ev].indexOf target.room
      subs[ev].splice(index, 1)
      persist subs
      msg.send "Unsubscribed #{printableTarget target} from #{ev} events"
    else
      msg.send "#{printableTarget target} was not subscribed to #{ev} events"

  robot.respond /unsubscribe all events$/i, (msg) ->
    count = 0
    subs = subscriptions()
    target = targetFromMessage msg
    for ev of subs
      if target in subs[ev] or
         # deprecated
         (target.room? and target.room in subs[ev])
        if target in subs[ev]
          index = subs[ev].indexOf target
        else
          # deprecated
          index = subs[ev].indexOf target.room
        subs[ev].splice(index, 1)
        count += 1
    persist subs
    msg.send "Unsubscribed #{printableTarget target} from #{count} events"

  robot.respond /subscriptions$/i, (msg) ->
    count = 0
    target = targetFromMessage msg
    for ev of subscriptions()
      if target in subscriptions(ev) or
         # deprecated
         (target.room? and target.room in subscriptions(ev))
        count += 1
        msg.send "#{ev} -> #{printableTarget target}"
    msg.send "Total subscriptions for #{printableTarget target}: #{count}"

  robot.respond /all subscriptions$/i, (msg) ->
    count = 0
    for ev of subscriptions()
      for target in subscriptions(ev)
        count += 1
        msg.send "#{ev} -> #{printableTarget target}"
    msg.send "Total subscriptions: #{count}"

  robot.respond /publish ([a-z0-9\-\.\:]+) (.*)$/i, (msg) ->
    ev = msg.match[1]
    data = msg.match[2]
    count = notify(ev, data)
    msg.send "Notified #{count} targets about #{ev}"

  robot.router.get "/publish", (req, res) ->
    query = querystring.parse(url.parse(req.url).query)
    res.end('')
    return unless query.password == process.env.HUBOT_SUBSCRIPTIONS_PASSWORD
    notify(query.event, query.data)

  robot.router.post "/publish", (req, res) ->
    res.end('')
    data = req.body
    return unless data.password == process.env.HUBOT_SUBSCRIPTIONS_PASSWORD
    notify(data.event, data.data)

  robot.on "pubsub:publish", (event, data) ->
    unless event or data
      console.log "Received incomplete pubsub:publish event. Event type: #{event}, data: #{data}"
    notify(event, data)

