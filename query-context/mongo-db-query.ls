config = require \./../config
{compile} = require \LiveScript
{MongoClient, ObjectID, Server} = require \mongodb
{id, concat-map, dasherize, difference, each, filter, find, find-index, foldr1, Obj, keys, map, obj-to-pairs, pairs-to-obj, Str, unique, any} = require \prelude-ls
{compile-and-execute-livescript, get-all-keys-recursively} = require \./../utils

# internal utility
objectify = (a) -> JSON.parse <| JSON.stringify a

poll = {}

# delegate
kill = (db, client, query, start-time, callback) ->
    return if 'connected' != db.serverConfig?._serverState
    db.collection '$cmd.sys.inprog' .findOne (err, data) ->
        try
            return callback err, null

            queries = data.inprog #|> map (-> [it.opid, it.microsecs_running, it.query])

            # first try by matching query objects
            oquery = objectify query
            the-query = queries |> find (-> !!it.query?.pipeline and objectify it.query.pipeline === oquery)
        
            # second try by matching time
            if !the-query
                now = new Date!.value-of!
                #TODO...
            

            if !!the-query
                console.log "^^^ Canceling op #{the-query.opid}"

                err, data <- db.collection '$cmd.sys.killop' .findOne { 'op': the-query.opid }
                return callback err, null if !!err
                db.close!
                client.close!
                callback null, \killed
        catch error
            callback error, null

# utility function for executing a single mongpdb query
export execute-mongo-query = (query-id, type, server-name, database, collection, query, timeout, callback) !-->

    # retrieve the connection string from config
    connection-string = config.connection-strings |> find (.name == server-name)
    return callback (new Error "server name not found"), null if typeof connection-string == \undefined

    # connect to mongo server
    server = new Server connection-string.host, connection-string.port
    mongo-client = new MongoClient server, {native_parser: true}
    err, mongo-client <- mongo-client.open 
    return callback err, null if !!err

    # perform query & close db connection
    f = switch type
            | \aggregation => execute-mongo-aggregation-pipeline
            | \map-reduce => execute-mongo-map-reduce
            | _ => (..., callback) -> 
                callback (new Error "Unexpected query type '#type' \nExpected either 'aggregation' or 'map-reduce'."), null

    db = mongo-client.db database


    start-time = new Date!.value-of!



    poll[query-id] = {
        kill: (kill-callback) ->
                kill db, mongo-client, query, start-time, kill-callback
                delete poll[query-id]
    }

    set-timeout do 
        kill (kill-error, kill-result) -> 
            return console.log \kill-error, kill-error if !!kill-error
            console.log \kill-result, kill-result
        timeout

    #(require \./ops).cancel-long-running-query 1200000, db, mongo-client, query

    err, result <- f (db.collection collection), query
    mongo-client.close!
    return callback (new Error "mongodb error: #{err.to-string!}"), null if !!err

    callback null, result

# private utility
convert-query-to-valid-livescript = (query)->

    lines = query.split (new RegExp "\\r|\\n")
        |> filter -> 
            line = it.trim!
            !(line.length == 0 || line.0 == \#)

    lines = [0 til lines.length] 
        |> map (i)-> 
            line = lines[i]
            line = (if i > 0 then "},{" else "") + line if line.0 == \$
            line

    "[{#{lines.join '\n'}}]"

# private utility
execute-mongo-aggregation-pipeline = (collection, query, callback) !-->
    err, result <-  collection.aggregate query, {allow-disk-use: config.allow-disk-use}
    callback err, result

# private utility
execute-mongo-map-reduce = (collection, query, callback) !-->
    err, result <- collection.map-reduce do
        query.$map
        query.$reduce
        query.$options <<< {finalize: query.$finalize}

    callback err, result

# used in server.ls for formatting parameters
export get-query-context = ->
    bucketize = (bucket-size, field) --> $divide: [$subtract: [field, $mod: [field, bucket-size]], bucket-size]
    {object-id-from-date, date-from-object-id} = require \./../public/scripts/utils.ls
    {} <<< (require \./default-query-context.ls)! <<< {

        # dependent on mongo operations
        day-to-timestamp: (field) -> $multiply: [field, 86400000]
        timestamp-to-day: bucketize 86400000
        bucketize: bucketize
        object-id: ObjectID
        object-id-from-date: ObjectID . object-id-from-date 

        # independent of any mongo operations
        date-from-object-id
    }

# query-id is generated at the client
export query = ({server-name, database, collection}:connection, query, parameters, query-id, callback) ->
    
    query-context = get-query-context! <<< (require \prelude-ls) <<< parameters

    [err, transpiled-code] = compile-and-execute-livescript (convert-query-to-valid-livescript query), query-context
    return callback err, null if !!err
    
    if '$map' in (transpiled-code |> concat-map Obj.keys)
        [err, transpiled-code] = compile-and-execute-livescript ("{\n#{query}\n}"), query-context
        return callback err, null if !!err
        type = \map-reduce
    else
        type = \aggregation

    #TODO: get timeout from config
    execute-mongo-query query-id, type, server-name, database, collection, transpiled-code, 60000, callback

    
export cancel = (query-id, callback) ->
    query = poll[query-id]
    return callback (new Error "Query not found #{query-id}") if !query
    query.kill callback


export keywords = ({server-name, database, collection}:connection, callback) !-->

    err, results <- execute-mongo-query new Date!.value-of!, \aggregation, server-name, database, collection,
        [
            {
                $sort: _id: -1
            }
            {
                $limit: 10
            }
        ]
        , 10000
    callback err, null if !!err

    collection-keywords = 
        results 
            |> concat-map (-> get-all-keys-recursively it, (k, v)-> typeof v != \function)
            |> unique

    callback null, do -> 
        collection-keywords ++ (collection-keywords |> map -> "$#{it}") ++
        config.test-ips ++ 
        ((get-all-keys-recursively get-query-context!, -> true) |> map dasherize) ++
        <[$add $add-to-set $all-elements-true $and $any-element-true $avg $cmp $concat $cond $day-of-month $day-of-week $day-of-year $divide 
            $eq $first $geo-near $group $gt $gte $hour $if-null $last $let $limit $literal $lt $lte $map $match $max $meta $millisecond $min $minute $mod $month 
            $multiply $ne $not $or $out $project $push $redact $second $set-difference $set-equals $set-intersection $set-is-subset $set-union $size $skip $sort 
            $strcasecmp $substr $subtract $sum $to-lower $to-upper $unwind $week $year]>