async = require 'async'
_ = require 'underscore'
Promise = require 'bluebird'

REQUEST_CHUNK_SIZE = 100

module.exports =
class RestfulModelCollection

  constructor: (@modelClass, @connection, @namespaceId) ->
    throw new Error("Connection object not provided") unless @connection instanceof require '../nilas-connection'
    throw new Error("Model class not provided") unless @modelClass
    @

  forEach: (params = {}, eachCallback, completeCallback = null) ->
    offset = 0
    finished = false

    async.until ->
      finished
    , (callback) =>
      @getModelCollection(params, offset, REQUEST_CHUNK_SIZE).then (models) ->
        eachCallback(model) for model in models
        offset += models.length
        finished = models.length < REQUEST_CHUNK_SIZE
        callback()
    , (err) ->
      completeCallback() if completeCallback

  count: (params = {}, callback = null) ->
    @connection.request
      method: 'GET'
      path: @path()
      qs: _.extend {view: 'count'}, params
    .then (json) ->
      callback(null, json.count) if callback
      Promise.resolve(json.count)
    .catch (err) ->
      callback(err) if callback
      Promise.reject(err)

  first: (params = {}, callback = null) ->
    @getModelCollection(params).then (items) ->
      callback(null, items[0]) if callback
      Promise.resolve(items[0])
    .catch (err) ->
      callback(err) if callback
      Promise.reject(err)

  list: (params = {}, callback = null) ->
    @range(params, 0, Infinity, callback)

  find: (id, callback = null) ->
    if not id
      err = new Error("find() must be called with an item id")
      callback(err) if callback
      Promise.reject(err)
      return

    @getModel(id).then (model) ->
      callback(null, model) if callback
      Promise.resolve(model)
    .catch (err) ->
      callback(err) if callback
      Promise.reject(err)

  range: (params = {}, offset = 0, limit = 100, callback = null) ->
    new Promise (resolve, reject) =>
      accumulated = []
      finished = false

      async.until ->
        finished
      , (chunkCallback) =>
        chunkOffset = offset + accumulated.length
        chunkLimit = Math.min(REQUEST_CHUNK_SIZE, limit - accumulated.length)
        @getModelCollection(params, chunkOffset, chunkLimit).then (models) ->
          accumulated = accumulated.concat(models)
          finished = models.length < REQUEST_CHUNK_SIZE or accumulated.length >= limit
          chunkCallback()
      , (err) ->
        if err
          callback(err) if callback
          reject(err)
        else
          callback(null, accumulated) if callback
          resolve(accumulated)

  delete: (itemOrId, callback) ->
    id = if itemOrId?.id? then itemOrId.id else itemOrId
    @connection.request("DELETE", "#{@path()}/#{id}").then ->
      callback(null) if callback
      Promise.resolve()
    .catch (err) ->
      callback(err) if callback
      Promise.reject(err)

  build: (args) ->
    model = new @modelClass(@connection, @namespaceId)
    model[key] = val for key, val of args
    model

  path: ->
    if @namespaceId
      "/n/#{@namespaceId}/#{@modelClass.collectionName}"
    else
      "/#{@modelClass.collectionName}"

  # Internal

  getModel: (id) ->
    @connection.request
      method: 'GET'
      path: "#{@path()}/#{id}"
    .then (json) =>
      model = new @modelClass(@connection, @namespaceId, json)
      Promise.resolve(model)

  getModelCollection: (params, offset, limit) ->
    @connection.request
      method: 'GET'
      path: @path()
      qs: _.extend {}, params, {offset, limit}
    .then (jsonArray) =>
      models = jsonArray.map (json) =>
        new @modelClass(@connection, @namespaceId, json)
      Promise.resolve(models)

  