{fold, keys, map} = require \prelude-ls
{compile} = require \LiveScript

# all functions defined here are accessibly by the transformation code
transformation-context = {}
chart = null

# all functions defined here are accessibly by the presentation code
presentation-context = {

    json: (result)-> $ \#result .html JSON.stringify result, null, 4

    plot-histogram: (result)->

        <- nv.add-graph

        chart := nv.models.multi-bar-chart!
            .x (.label)
            .y (.value)

        d3.select \svg .datum result .call chart

    plot-timeseries: (result)->

        <- nv.add-graph 

        chart := nv.models.line-chart!
            .x (.0)
            .y (.1)
        chart.x-axis.tick-format (timestamp)-> (d3.time.format \%x) new Date timestamp
            
        d3.select \svg .datum result .call chart

    plot-stacked-area: (result) ->
        <- nv.add-graph 

        chart := nv.models.stacked-area-chart!
            .x (.0)
            .y (.1)
            .useInteractiveGuideline true
            .show-controls true
            .clip-edge true

        chart.x-axis.tick-format (timestamp)-> (d3.time.format \%x) new Date timestamp
            
        d3.select \svg .datum result .call chart        

    plot-scatter: (result, {tooltip, x-axis-format = d3.format('.02f'), y-axis-format = d3.format('.02f')}) ->
        <- nv.add-graph

        chart := nv.models.scatter-chart!
            .showDistX true
            .showDistY true
            .transitionDuration 350
            .color d3.scale.category10!.range!

        chart.tooltipContent (key, , , {point}) -> 
            (tooltip or (key) -> '<h3>' + key + '</h3>') key, point

        
        chart.x-axis.tick-format x-axis-format
        chart.y-axis.tick-format y-axis-format



        d3.select \svg .datum result .call chart
}

# resize the chart on window resize
nv.utils.windowResize -> 
    if !!chart
        chart.update!

# creates, configures & returns a new instance of ace-editor
create-livescript-editor = (element-id)->
    ace.edit element-id
        ..set-options {enable-basic-autocompletion: true}
        ..set-theme \ace/theme/monokai
        ..set-show-print-margin false
        ..get-session!.set-mode \ace/mode/livescript

# makes a POST request the server and returns the result of the mongo query
execute-query = (->

    previous-request = {}

    (query, callback)->

        return callback previous-request.err, previous-request.response if query == previous-request.query
            

        lines = query.split \\n

        lines = [0 til lines.length] 
            |> map (i)-> 
                line = lines[i]
                line = (if i > 0 then "}," else "") + \{ + line if line.0 == \$
                line += \} if i == lines.length - 1
                line

        query-result-promise = $.post \/query, "[#{lines.join '\n'}]"
            ..done (response)-> 
                previous-request <<< {err: null, response}
                callback null, response

            ..fail ({response-text}) -> 
                previous-request <<< {err: response-text, response: null}
                callback response-text, null

        previous-request <<< {query}


)!

# compiles & executes livescript
run-livescript = (context, result, livescript)-> 
    livescript = "window <<< require 'prelude-ls' \nwindow <<< context \n" + livescript       
    try 
        return [null, eval compile livescript, {bare: true}]
    catch error 
        return [error, null]

# makes a POST request to the server to save the current document-object
save = (document-object, callback)->
    save-request-promise = $.post \/save, JSON.stringify document-object, null, 4
        ..done (response)-> 
            [err, query-id] = JSON.parse response
            return callback err, null if !!err
            callback null, query-id
        ..fail ({response-text})-> callback response-text, null
            
# on dom ready
$ ->

    # create the editors
    query-editor = create-livescript-editor \query-editor
    transformer = create-livescript-editor \transformer
    presenter = create-livescript-editor \presenter

    # setup auto-complete
    lang-tools = ace.require \ace/ext/language_tools
    
    # (ace.require \ace/ext/language_tools).addCompleter {
    #     getCompletions: (editor, session, pos, prefix, callback)->
    #         return callback null, [] if prefix.length === 0
    #         callback null, [{name: "", value: "", score: 0, meta: ""}]
    # }

    execute-query-and-display-results = ->

        # clean existing results
        $ \#preloader .remove-class \hide
        $ \#result .html ""
        $ "svg" .empty!

        # query, transform & plot 
        {query, transformation-code, presentation-code} = get-document!

        (err, result) <- execute-query query
        $ \#preloader .add-class \hide
        return $ \#result .html "query-editor error #{err}" if !!err

        [err, result] = run-livescript transformation-context, (JSON.parse result), transformation-code
        return $ \#result .html "transformer error #{err}" if !!err

        [err, result] = run-livescript presentation-context, result, presentation-code
        return $ \#result .html "presenter error #{err}" if !!err

    get-document = -> {query-id: window.document-properties.query-id, query: query-editor.get-value!, transformation-code: transformer.get-value!, presentation-code: presenter.get-value!}

    # returns noop if the document hasn't changed since the last save
    get-save-function = (->        
        last-saved-document = if document-properties.query-id is null then {} else get-document!
        -> 

            # if there are no changes to the document return noop as the save function
            current-document = get-document!
            return [false, $.noop] if current-document `is-equal-to-object` last-saved-document

            # if the document has changed since the last save then 
            # return a function that will POST the new document to the server
            [
                true
                ->        
                    (err, query-id) <- save current-document
                    return console.log err if !!err

                    last-saved-document := current-document

                    if window.document-properties.query-id is null
                        window.onbeforeunload = $.noop!
                        window.location.href += "#{query-id}"
            ]
    )!

    # two objects are equal if they have the same keys & values
    is-equal-to-object = (o1, o2)-> (keys o1) |> fold ((memo, key)-> memo && (o2[key] == o1[key])), true
        
    # execute the query on button click or hot key (command + enter)
    KeyboardJS.on "command + enter", execute-query-and-display-results
    $ \#execute-mongo-query .on \click, execute-query-and-display-results

    # save the document
    KeyboardJS.on "command + s", (e)->

        [,save-function] = get-save-function!
        save-function!

        # prevent default behavious of displaying the save-dialog
        e.prevent-default!
        e.stop-propagation!
        return false

    # prevent loss of work, does not guarantee the completion of async functions    
    window.onbeforeunload = -> 
        [should-save] = get-save-function!
        return "You have NOT saved your query. Stop and save if your want to keep your query." if should-save
        





