# This program is distributed under the terms of the MIT license.
# Copyright 2012 (c) Markus Kohlhase <mail@markus-kohlhase.de>

JOAP_NS = "jabber:iq:joap"

# Private static members

conn = null

onError = (cb=->) -> (iq) ->
  err = iq.getElementsByTagName("error")[0]
  if err?
    code = err.getAttribute("code") * 1
    msg  = err.textContent
    msg = "JOAP server is unavailable" if code is 503
    cb iq, new JOAPError msg, code
  else
    cb iq, new JOAPError "Unknown error"

addXMLAttributes = (iq, attrs) ->
  if typeof attrs is "object"
    for k,v of attrs
      iq.c("attribute")
        .c("name").t(k).up()
        .cnode(conn.rpc._convertToXML v).up().up()

parseAttributes = (iq) ->
  attrs = iq.getElementsByTagName("attribute")
  data = {}
  for a in attrs
    key   = a.getElementsByTagName("name")[0].textContent
    data[key] = conn.rpc._convertFromXML a.getElementsByTagName("value")[0]
  data

parseNewAddress = (iq) ->
  address = iq.getElementsByTagName("newAddress")[0].textContent

parseSearch = (iq) ->
  items = iq.getElementsByTagName("item")
  (i.textContent for i in items)

parseAttributeDescription = (d) ->
  name: d.getElementsByTagName("name")[0]?.textContent
  type: d.getElementsByTagName("type")[0]?.textContent
  desc: parseDesc d.getElementsByTagName("desc")

parseMethodDescription = (d) ->
  name: d.getElementsByTagName("name")[0]?.textContent
  returnType: d.getElementsByTagName("returnType")[0]?.textContent
  desc: parseDesc d.getElementsByTagName("desc")

parseDesc = (desc) ->
  res = {}
  if desc instanceof NodeList
    for c in desc
      res[c.getAttribute "xml:lang"] = c.textContent
  else
    res.desc[desc.getAttribute "xml:lang"] = desc.textContent
  res

parseDescription = (iq) ->
  result = desc: {}, attributes: {}, methods: {}, classes: []
  describe = iq.getElementsByTagName("describe")[0]
  for c in describe.childNodes
    switch c.tagName.toLowerCase()
      when "desc"
        result.desc[c.getAttribute "xml:lang"] = c.textContent
      when "attributedescription"
        ad = parseAttributeDescription c
        result.attributes[ad.name] = ad
      when "methoddescription"
        md = parseMethodDescription c
        result.methods[md.name] = md
      when "superclass"
        result.superclass = c.textContent
      when "timestamp"
        result.timestamp = c.textContent
      when "class"
        classes.push = c.textContent
  result

getAddress = (clazz, service, instance) ->
  addr = ""
  addr += "#{clazz}@" if clazz if typeof clazz is "string"
  addr += service
  addr += "/#{instance}" if (typeof(instance) in ["string", "number"])
  addr

createIq = (type, to) ->
  iqType = "set"
  iqType = "get" if (type in ["read", "search", "describe"])
  $iq(to: to, type: iqType)
    .c(type, xmlns: JOAP_NS)

sendRequest = (type, to, cb, opt={}) ->
  iq = createIq type, to
  opt.beforeSend? iq
  success = (res) -> cb? res, null, opt.onResult?(res)
  conn.sendIQ iq, success, onError(cb)

describe = (id, cb) ->
  sendRequest "describe", id, cb,
    onResult: parseDescription

read = (instance, limits, cb) ->
  cb = limits if typeof limits is "function"
  sendRequest "read", instance, cb,
    beforeSend: (iq) -> if limits instanceof Array
      iq.c("name").t(l).up() for l in limits
    onResult: parseAttributes

add = (clazz, attrs, cb) ->
  cb = attrs if typeof attrs is "function"
  sendRequest "add", clazz, cb,
    beforeSend: (iq) -> addXMLAttributes iq, attrs
    onResult: parseNewAddress

edit = (instance, attrs, cb) ->
  sendRequest "edit", instance, cb,
    beforeSend: (iq) -> addXMLAttributes iq, attrs
    onResult: parseAttributes

search = (clazz, attrs, cb) ->
  cb = attrs if typeof attrs is "function"
  sendRequest "search", clazz, cb,
    beforeSend: (iq) -> addXMLAttributes iq, attrs
    onResult: parseSearch

del = (instance, cb) ->
  sendRequest "delete", instance, cb

class JOAPError extends Error

  constructor: (@message, @code)->
    @name = "JOAPError"

class Server

  constructor: (@service) ->

  describe: (clazz, instance, cb) ->
    if typeof clazz is "function"
      cb = clazz
      clazz = instance = null
    else if typeof instance is "function"
      cb = instance
      instance = null
    describe getAddress(clazz, @service, instance), cb

  add: (clazz, attrs, cb) ->
    add getAddress(clazz, @service), attrs, cb

  read: (clazz, instance, limits, cb) ->
    read getAddress(clazz, @service, instance), limits, cb

  edit: (clazz, instance, attrs, cb) ->
    edit getAddress(clazz, @service, instance), attrs, cb

  delete: (clazz, instance, cb) ->
    del getAddress(clazz, @service, instance), cb

  search: (clazz, attrs, cb) ->
    search getAddress(clazz, @service), attrs, cb

Strophe.addConnectionPlugin 'joap', do ->

  getObjectServer = (service) -> new Server service
  init = (c) ->
    conn = c
    Strophe.addNamespace "JOAP", JOAP_NS

    if not conn.hasOwnProperty "disco"
      Strophe.warn "You need the discovery plugin to have JOAP fully implemented."
    else
      conn.disco.addIdentity "automation", "joap"
      conn.disco.addFeature Strophe.NS.JOAP

  # public API
  init: init
  getObjectServer: getObjectServer
  describe: describe
  add: add
  read: read
  edit: edit
  delete: del
  search: search
  JOAPError: JOAPError
