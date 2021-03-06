require! {
  '../../modules/aktos-dcs': {
    RactivePartial,
    IoActor,
    formatter,
    act-get-range,
  }
}


/* usage example

  {{>circular-progress {pin_name: ..., color: 'blue green'} }}

  color: '#2345 #88776'
  color: 'red'

*/

RactivePartial! .register ->
  $ \.circular-progress .each ->

    actor = IoActor $ this
    color = actor.get-ractive-var \color

    elem = actor.node.find \.circular-progress__inner

    format = (actor.get-ractive-var 'format') ? '% ###'
    widget-formatter = formatter format

    if (actor.get-ractive-var \wid)?
      actor.node.add-class \draggable

    val = actor.get-ractive-var \val
    display-format = widget-formatter val

    cp-value = (input) ->
      if input/1 then input/100
      else 0

    actor.set-ractive-var \val, display-format.value
    actor.set-ractive-var \unit, display-format.unit

    params =
      value: cp-value val
      animation: false
      thickness: 15

    if not color or color is ''
      color = '#ff1e41 #ff5f43'

    colors = color.split ' '

    params = $.extend params, do
      fill: gradient: colors

    elem.circle-progress params

    actor.add-callback (msg) ->
      val = widget-formatter msg.val .value
      elem.circle-progress \value, cp-value val
      actor.set-ractive-var \val, val
