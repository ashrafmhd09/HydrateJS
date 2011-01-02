class Spike  
  class Util
    @d2h = (d) ->
      d.toString 16
    @h2d = (h) ->
      parseInt h, 16
      
    @supportsProto = ({}).__proto__?
    @supportsFunctionNames = typeof (->).name == "string"
    
    @functionName = (func) ->
      if Util.supportsFunctionNames
        # func.name isn't writable, so this is reliable
        func.name
      else
        # for IE
        func.toString().match(/function ([^(]*)/)?[1]
  @Util = Util
  
  class NonPrototypeFunctionError extends Error
    constructor: (@object, @name) ->
    toString: ->
      "Couldn't serialize object; had non-prototype function '#{@name}'"
  class PrototypeNotFoundError extends Error
    constructor: (@object, @cons_id) ->
    toString: ->
      "Prototype not found for object; looked for #{@cons_id}"
    
  constructor: (@resolvers=[]) ->
    if @resolvers.length == 0 && typeof window != "undefined"
      @resolvers.push new ContextResolver(window)      
    @errorHandler = (e) ->
      throw e
    @serialize_key = "_freeze"
    @unserialize_key = "_thaw"
    
  stringify: (input) ->
    @processed_inputs = []
    @counter = 0
    result = switch typeof input
      when "number", "string" then JSON.stringify(input)
      when "function" then throw new Error("can't serialize functions")
      else
        if input instanceof Array
          arr = []
          arr.push @analyze i for i in input
          
          JSON.stringify(arr)
        else
          # is an object...
          JSON.stringify @analyze input
    @cleanAfterStringify()
    result
  cleanAfterStringify: ->
    for input in @processed_inputs
      delete input.__spike_id
    true
    
  analyze: (input, name) ->
    switch typeof input
      when "number", "string" then input
      when "function"
        # skip, should probably check to see if the function is attached to the prototype
        @errorHandler new NonPrototypeFunctionError(input, name)
      else
        if input instanceof Array
          output = []
          for v, i in input
            output[i] = @analyze v, i
          output
        else
          if(input.__spike_id)
            "__spike_ref_#{input.__spike_id}"
          else
            input.__spike_id = Util.d2h(@counter++)
            @processed_inputs.push input
            # is an object...
            output = new Object
            for k, v of input
              if input.hasOwnProperty k
                output[k] = @analyze v, k
            output.__spike_cons = Util.functionName(input.constructor)
            output
            
  setErrorHandler: (@errorHandler) ->
  
  @_refMatcher = /__spike_ref_(.*)/
  
  parse: (input) ->
    @identified_objects = []
    @references_to_resolve = []
    o = JSON.parse(input)
    l = o.length
    o = @fixTree o
    for reference in @references_to_resolve
      [obj, obj_key, ref_id] = reference
      obj[obj_key] = @identified_objects[ref_id]
    @clean o
    o
  fixTree: (obj) ->
    obj[@unserialize_key]() if typeof obj[@unserialize_key] == "function"
    
    # TODO reduce duplication between following two branches
    
    if obj instanceof Array
      for v, k in obj
        v = @fixTree v
        if typeof v == "string" && m = v.match Spike._refMatcher
          k2 = Util.h2d(m[1])
          @references_to_resolve.push([obj, k, k2])
        else
          obj[k] = v
    else if typeof obj == "object"
      if obj.__spike_cons?
        proto = @resolvePrototype obj.__spike_cons
        if proto?
          if Util.supportsProto
            obj.__proto__ = proto
          else
            tmp = (->)
            tmp.prototype = proto
            t = new tmp
            for k, v of obj
              if obj.hasOwnProperty k
                t[k] = v
            obj = t
        else
          @errorHandler new PrototypeNotFoundError(obj, obj.__spike_cons)
          
      for k, v of obj
        v = @fixTree v
        if k == "__spike_id"
          v2 = Util.h2d(v)
          @identified_objects[v2] = obj
        else if typeof v == "string" && m = v.match Spike._refMatcher
          k2 = Util.h2d(m[1])
          @references_to_resolve.push([obj, k, k2])
        else
          obj[k] = v
    obj
  resolvePrototype: (cons_id) ->
    if @resolvers.length == 0
      throw new Error("No Spike resolvers found -- you should add one!")
    for res in @resolvers
      cons = res.resolve(cons_id)
      return cons if cons?
    null
  clean: (o, cleaned=[]) ->
    cleaned.push o
    if typeof o == "object" && !(o instanceof Array)
      for k, v of o
        if k == "__spike_id" || k == "__spike_cons"
          delete o[k]
        else if typeof v == "object" && !(o instanceof Array) && cleaned.indexOf(v) < 0
          @clean(v, cleaned)
          
    true

class Resolver
  resolve: ->
    throw new Error("abstract")

class ContextResolver
  constructor: (@contexts=[]) ->
    if typeof @contexts != Array
      @contexts = [@contexts]
  addContext: (ctx) ->
    @contexts.push ctx
  resolve: (cons_id) ->
    for ctx in @contexts
      v = ctx[cons_id]
      return v.prototype if v?
    null
        
this.Spike = Spike;
