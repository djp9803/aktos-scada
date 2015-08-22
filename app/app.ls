
require! {
  './prelude': {
    flatten,
    initial,
    drop,
    join,
    concat,
    tail,
    head,
    map,
    zip,
    split,
    union
  }
}


# -----------------------------------------------------
# aktos-dcs livescript
# -----------------------------------------------------
envelp = (msg, msg-id) ->
  msg-raw = do
    sender: []
    timestamp: Date.now! / 1000
    msg_id: msg-id  # {{.actor_id}}.{{serial}}
    payload: msg
  return msg-raw

get-msg-body = (msg) ->
  subject = [subj for subj of msg.payload][0]
  #console.log "subject, ", subject
  return msg.payload[subject]



class ActorBase
  ~>
    @actor-id = uuid4!

  receive: (msg) ->
    #console.log @name, " received: ", msg.text

  recv: (msg) ->
    @receive msg
    try
      subjects = [subj for subj of msg.payload]
      for subject in subjects
        this['handle_' + subject] msg
    catch
      #console.log "problem in handler: ", e



# make a singleton
class ActorManager
  instance = null
  ~>
    instance ?:= SingletonClass!
    return instance

  class SingletonClass extends ActorBase
    ~>
      super ...
      @actor-list = []
      #console.log "Manager created with id:", @actor-id

    register: (actor) ->
      @actor-list = @actor-list ++ [actor]

    inbox-put: (msg) ->
      msg.sender ++= [@actor-id]
      for actor in @actor-list
        if actor.actor-id not in msg.sender
          #console.log "forwarding msg: ", msg
          actor.recv msg


class Actor extends ActorBase
  (name) ~>
    super ...
    @mgr = ActorManager!
    @mgr.register this
    @actor-name = name
    #console.log "actor \'", @name, "\' created with id: ", @actor-id
    @msg-serial-number = 0

  send: (msg) ->
    msg = envelp msg, @get-msg-id!
    @send_raw msg

  send_raw: (msg_raw) ->
    msg_raw.sender ++= [@actor-id]
    @mgr.inbox-put msg_raw


  get-msg-id: ->
    msg-id = @actor-id + '.' + String @msg-serial-number
    @msg-serial-number += 1
    return msg-id

class ProxyActor
  instance = null
  ~>
    instance ?:= SingletonClass!
    return instance

  class SingletonClass extends Actor
    ~>
      super ...
      #console.log "Proxy actor is created with id: ", @actor-id

      @socket = socket
      # send to server via socket.io
      @socket.on 'aktos-message', (msg) ~>
        try
          @network-rx msg
        catch
          console.log "Problem with receiving message: ", e

      @connected = false 
      @socket.on "connect", !~>
        #console.log "proxy actor says: connected"
        # update io on init
        @connected = true
        @network-tx envelp UpdateIoMessage: {}, @get-msg-id!
        @send ConnectionStatus: {connected: @connected}

      @socket.on "disconnect", !~>
        #console.log "proxy actor says: disconnected"
        @connected = false 
        @send ConnectionStatus: {connected: @connected}
        
    handle_UpdateConnectionStatus: (msg) -> 
      @send ConnectionStatus: {connected: @connected}
      
    network-rx: (msg) ->
      # receive from server via socket.io
      # forward message to inner actors
      #console.log "proxy actor got network message: ", msg
      @send_raw msg

    receive: (msg) ->
      @network-tx msg

    network-tx: (msg) ->
      # receive from inner actors, forward to server
      msg.sender ++= [@actor-id]
      #console.log "emitting message: ", msg
      @socket.emit 'aktos-message', msg

# -----------------------------------------------------
# end of aktos-dcs livescript
# -----------------------------------------------------
/*

# aktos widget library

## basic types:

toggle-switch: toggles on every tap or click
push-button : toggles while clicking or tapping
status-led : readonly of toggle-switch or push-button

*/



get-ractive-variable = (jquery-elem, ractive-variable) ->
  ractive-node = Ractive.get-node-info jquery-elem.get 0
  value = (app.get ractive-node.\keypath)[ractive-variable]
  #console.log "ractive value: ", value
  return value

set-ractive-variable = (jquery-elem, ractive-variable, value) ->
  ractive-node = Ractive.get-node-info jquery-elem.get 0
  if not ractive-node.\keypath
    console.log "ERROR: NO KEYPATH FOUND FOR RACTIVE NODE: ", jquery-elem
    
  app.set ractive-node.\keypath + '.' + ractive-variable, value



class SwitchActor extends Actor
  (pin-name)~>
    super ...
    @callback-functions = []
    @pin-name = String pin-name
    if pin-name
      @actor-name = @pin-name
    else
      @actor-name = @actor-id
      console.log "actor is created with this random name: ", @actor-name
    @ractive-node = null  # the jQuery element
    @connected = false

  add-callback: (func) ->
      @callback-functions ++= [func]

  handle_IoMessage: (msg) ->
    msg-body = get-msg-body msg
    if msg-body.pin_name is @pin-name
      #console.log "switch actor got IoMessage: ", msg
      @fire-callbacks msg-body

  handle_ConnectionStatus: (msg) ->
    # TODO: TEST THIS CIRCULAR REFERENCE IF IT COUSES
    # MEMORY LEAK OR NOT
    @connected = get-msg-body msg .connected
    #console.log "connection status changed: ", @connected
    @refresh-connected-variable! 
    
  refresh-connected-variable: -> 
    if @ractive-node
      #console.log "setting {{connected}}: ", @connected
      set-ractive-variable @ractive-node, 'connected', @connected
    else
      console.log "ractive node is empty! actor: ", this 
    
  set-node: (node) -> 
    #console.log "setting #{this.actor-name} -> ", node
    @ractive-node = node
    
    @send UpdateConnectionStatus: {}

  fire-callbacks: (msg) ->
    #console.log "fire-callbacks called!", msg
    for func in @callback-functions
      func msg

  gui-event: (val) ->
    #console.log "gui event called!", val
    @fire-callbacks do
      pin_name: @pin-name
      val: val

    @send IoMessage: do
      pin_name: @pin-name
      val: val
# ---------------------------------------------------
# END OF LIBRARY FUNCTIONS
# ---------------------------------------------------


# Set Ractive.DEBUG to false when minified:
Ractive.DEBUG = /unminified/.test !->
  /*unminified*/

app = new Ractive do
  el: 'container'
  template: '#app'

/* initialize socket.io connections */
url = window.location.href
arr = url.split "/"
addr_port = arr.0 + "//" + arr.2
socketio-path = [''] ++ (initial (drop 3, arr)) ++ ['socket.io']
socketio-path = join '/' socketio-path
socket = io.connect do 
  'port': addr_port
  'path': socketio-path
  
## debug
#console.log 'socket.io path: ', addr_port,  socketio-path
#console.log "socket.io socket: ", socket

# Create the actor which will connect to the server
ProxyActor!


set-switch-actors = !->
  $ '.switch-actor' .each !->
    elem = $ this
    pin-name = get-ractive-variable elem, 'pin_name'
    actor = SwitchActor pin-name
    actor.set-node elem
    elem.data \actor, actor

# basic widgets 
set-switch-buttons = !->
  $ '.switch-button' .each !->
    elem = $ this
    actor = elem.data \actor

    # make it work without toggle-switch
    # visualisation
    elem.change ->
      actor.gui-event this.checked
    actor.add-callback (msg) ->
      elem.prop 'checked', msg.val

set-push-buttons = ->
  #
  # TODO: tapping works as doubleclick (two press and release)
  #       fix this.
  #
  $ '.push-button' .each ->
    elem = $ this
    actor = elem.data \actor

    # desktop support
    elem.on 'mousedown' ->
      actor.gui-event on
      elem.on 'mouseleave', ->
        actor.gui-event off
    elem.on 'mouseup' ->
      actor.gui-event off
      elem.off 'mouseleave'

    # touch support
    elem.on 'touchstart' (e) ->
      actor.gui-event on
      elem.touchleave ->
        actor.gui-event off
      e.stop-propagation!
    elem.on 'touchend' (e) ->
      actor.gui-event off

    actor.add-callback (msg) ->
      #console.log "push button got message: ", msg
      if msg.val
        elem.add-class 'button-active-state'
      else
        elem.remove-class 'button-active-state'

set-status-leds = ->
  $ '.status-led' .each ->
    elem = $ this
    actor = elem.data \actor
    actor.add-callback (msg) ->
      #console.log "status led: ", actor.pin-name, msg.val
      set-ractive-variable elem, 'val', msg.val

set-analog-displays = ->
  $ \.analog-display .each ->
    elem = $ this
    channel-name = get-ractive-variable elem, 'pin_name'
    #console.log "this is channel name: ", channel-name
    actor = SwitchActor channel-name
    actor.add-callback (msg) ->
      set-ractive-variable elem, 'val', msg.val

make-basic-widgets = -> 
  set-switch-buttons!
  set-push-buttons!
  set-status-leds!
  set-analog-displays!

# create jq mobile widgets 
make-jq-mobile-widgets = !->
  console.log "mobile connections being done..."
  $ document .ready ->
    #console.log "document ready!"

    # jq-flipswitch-v2
    make-jq-flipswitch-v2 = -> 
      $ \.switch-button .each ->
        #console.log "switch-button created"
        elem = $ this
        actor = elem.data \actor

        send-gui-event = (event) -> 
          #console.log "jq-flipswitch-2 sending msg: ", elem.val!        
          actor.gui-event (elem.val! == \on)

        elem.on \change, send-gui-event
        
        actor.add-callback (msg) ->
          #console.log "switch-button got message", msg
          elem.unbind \change
          
          if msg.val
            elem.val \on .slider \refresh
          else
            elem.val \off .slider \refresh
          
          elem.bind \change, send-gui-event 
          
    make-jq-flipswitch-v2!
        
    # jq-push-button
    make-jq-push-button = -> 
      set-push-buttons!  # inherit basic button settings
      $ \.push-button .each ->
        #console.log "found push-button!"
        elem = $ this
        actor = elem.data \actor
        
        actor.add-callback (msg) ->
          #console.log "jq-push-button got message: ", msg.val
          if msg.val
            elem.add-class 'ui-btn-active'
          else
            elem.remove-class 'ui-btn-active'
          
        # while long pressing on touch devices, 
        # no "select text" dialog should be fired: 
        elem.disable-selection!
        elem.onselectstart = ->
          false
        elem.unselectable = "on"
        elem.css '-moz-user-select', 'none'
        elem.css '-webkit-user-select', 'none'
    
    make-jq-push-button!

    # slider
    make-slider = !->
      $ '.slider' .each !->
        elem = $ this 
        actor = elem.data \actor
        
        #console.log "this slider actor found: ", actor 
        #debugger 
        
        slider = elem.find \.jq-slider 
        slider.slider!
        #console.log "slider created!", slider
        
        curr_val = slider.attr \value
        slider.val curr_val .slider \refresh 
        #console.log "current value: ", curr_val
        
        input = elem.find \.jq-slider-input
        
        input.on \change -> 
          val = get-ractive-variable elem, \val
          actor.gui-event val
          
        
        slider.on \change ->
          #console.log "slider val: ", slider.val!
          actor.gui-event slider.val!
          
        actor.add-callback (msg)->
          #console.log "slider changed: ", msg.val 
          slider.val msg.val .slider \refresh
          set-ractive-variable elem, \val, msg.val 
        
        
    make-slider!
    
    # inherit status leds
    set-status-leds!
    
    # inherit analog displays
    set-analog-displays!


make-jq-page-settings = ->
  navnext = (page) ->
    $.mobile.navigate page

  navprev = (page) ->
    $.mobile.navigate page

  $ window .on \swipe, (event) ->
    navnext \#foo
    #$.mobile.change-page \#foo

make-toggle-switch-visualisation = ->
  $ \.toggle-switch .each !->
    elem = $ this
    actor = elem.data \actor

    s = new ToggleSwitch elem.get 0, 'on', 'off'
    actor.add-callback (msg) ->
      # prevent switch callback call on
      # external events. only change visual status.
      tmp = s.f-callback
      s.f-callback = null
      if msg.val
        s.on!
      else
        s.off!
      s.f-callback = tmp
      tmp = null

    s.add-listener (state) !->
      actor.send-event state
      
jquery-mobile-specific = -> 

  set-project-buttons-height = (height) -> 
    $ \.project-buttons .each -> 
      $ this .height height

  make-windows-size-work = ->
    window-width = $ window .width!
    console.log "window width: #window-width"
    set-project-buttons-height window-width/3.1

  $ window .resize -> 
    make-windows-size-work!
  
  make-windows-size-work!

app.on 'complete', !->
  #$ '#debug' .append '<p>app.complete started...</p>'
  $ document .ready ->
    #console.log "ractive completed, post processing other widgets..."

    # create actors for every widget
    set-switch-actors!

    # create basic widgets
    #make-basic-widgets!

    # create jquery mobile widgets 
    make-jq-mobile-widgets!
    jquery-mobile-specific!
    
    #$ \#debug .append '<p>app.complete ended...</p>'

    # set jquery mobile page behaviour
    #make-jq-page-settings!
    
    #console.log "app.complete ended..."
    


