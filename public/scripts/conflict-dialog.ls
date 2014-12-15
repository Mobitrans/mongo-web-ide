{filter, find, fold, map, sort-by} = require \prelude-ls
React = require \react
{$button, $circle, $div, $g, $h1, $line, $path, $svg} = require \./react-ls.ls

module.exports.conflict-dialog = React.create-class do 

    render: ->

        console.log "render conflict-dialog"

        {queries} = @.props
        {forked-node-position, forked-line-p2, line-length,  origin, radius, resolution, svg-size} = @.state

        nodes = [0 til queries.length]
            |> map (i)-> {x: ((i + 1) * line-length), y: 0}

        links = [0 til nodes.length - 1]
            |> map (i)-> {source: nodes[i], target: nodes[i + 1]}

        circles = [$circle {r: radius, transform: "translate(0, 0)"}] ++ (nodes |> map ({x, y})-> $circle {r: radius, transform: "translate(#x, #y)"})

        last-node = nodes[nodes.length - 1]

        extra-circles = [
            {
                class-name: if resolution == \new-commit then \highlight else \dim
                transform: "translate(#{last-node.x + line-length} #{last-node.y})"
            }
            {
                class-name: if resolution == \fork then \highlight else \dim
                transform: "translate(#{forked-node-position.x} #{forked-node-position.y})"
            }
        ] |> map -> $circle (it <<< {r:radius})

        lines = [$line {x1: 0, y1: 0, x2: line-length, y2: 0}] ++ (links
            |> filter ({source, target})-> !!source and !!target
            |> map ({source, target})-> $line {x1: source.x, y1: source.y, x2: target.x, y2: target.y})

        extra-lines = [
            {
                class-name: if resolution == \new-commit then \highlight else \dim
                x1: last-node.x
                y1: last-node.y
                x2: last-node.x + line-length - radius
                y2: last-node.y
            }
            {
                class-name: if resolution == \fork then \highlight else \dim
                x1: 0
                y1: 0
                x2: forked-line-p2.x
                y2: forked-line-p2.y
            }
        ] |> map -> $line it

        $div {class-name: \conflict-dialog}, # transparency
            $div null, # absolute
                $div null, #relative
                    $h1 null, "Unable to save, you are #{@.props.queries.length} queries behind"
                    $svg {style: {width: svg-size.width, height: svg-size.height}},
                        $g {transform: "translate(#{origin.x} #{origin.y})"}, (lines ++ extra-lines ++ circles ++ extra-circles)
                    $div {class-name: \buttons},
                        $button {on-click: @.on-click, on-mouse-over: (@.on-mouseover \reset), on-mouseout: @.on-mouseout}, "Reset"
                        $button {on-click: @.on-click, on-mouse-over: (@.on-mouseover \fork), on-mouse-out: @.on-mouseout}, "Fork Query"
                        $button {on-click: @.on-click, on-mouse-over: (@.on-mouseover \new-commit), on-mouse-out: @.on-mouseout}, "New Query"
                        $button {on-click: @.close}, "Cancel"

    close: ->
        React.unmount-component-at-node this.get-DOM-node!.parent-element

    get-initial-state: ->
        line-length = 100
        radius = 10
        origin = {x: 2 * radius, y: 2 * radius}
        forked-node-position = radial-to-cartesian line-length, 45
        forked-line-p2 = radial-to-cartesian (line-length - radius), 45        
        svg-size = {width: origin.x + ((@.props.queries.length + 1) * line-length) + 2 * radius, height: origin.y + forked-node-position.y + 2 * radius}
        {forked-node-position, forked-line-p2, line-length,  origin, radius, resolution: \reset, svg-size}

    on-click: ->
        @.props.on-resolved @.state.resolution
        @.close!

    on-mouseover: (resolution)->
        self = @
        -> self.set-state {resolution}
        
    on-mouseout: ->
        @.set-state {resolution: \none}

    radial-to-cartesian = (magnitude, angle)-> 
        angle = angle * Math.PI / 180
        {x: magnitude * (Math.cos angle), y: magnitude * Math.sin angle}



