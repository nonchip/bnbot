ffi = require "ffi"
socket = require 'socket'
https = require 'ssl.https'
cjson = require 'cjson'

ffi.cdef "unsigned int sleep(unsigned int seconds);"

class Api
  new: (@baseURL='https://api.binance.com')=>
    @cooldown_t=0
    @getExchangeInfo!
  getExchangeInfo: =>
    @exchange_info = @request '/api/v1/exchangeInfo'
    @heatup 1
  time: =>
    ret,err=@request '/api/v1/time'
    @heatup 1
    return nil,(err or 'time missing') unless ret and ret.serverTime
    return ret.serverTime
  heatup: (m,t='REQUESTS') =>
    seconds=0
    for l in *@exchange_info.rateLimits
      if l.rateLimitType==t
        is=switch l.interval
          when 'SECOND' then 1
          when 'MINUTE' then 60
          when 'HOUR' then 60*60
          when 'DAY' then 60*60*24
        seconds += is/l.limit
    @cooldown_t += math.max m*seconds, 1
  do_cooldowns: (max=nil)=>
    max or=@cooldown_t
    wait = math.ceil math.min(@cooldown_t, max)
    if wait<1
      return nil, 'nothing to do'
    for i=1,wait
      ffi.C.sleep(1)
      @cooldown 1
    return wait
  cooldown: (seconds)=>
    @cooldown_t -= seconds
    if @cooldown_t <0
      @cooldown_t=0
  mayRequest: (endpoint)=>
    if @cooldown_t > 0
      return nil, 'cooldown'
    return true
  request: (endpoint,params=nil)=>
    ok,e=@mayRequest endpoint
    return nil,e unless ok
    url = @baseURL..endpoint
    if type(params)=='table'
      url ..= '?' .. table.concat [k..'='..v for k,v in pairs params], '&'
    elseif type(params)=='string'
      url ..= '?' .. params
    body, code, headers, status = https.request url
    if code == 429 or code == 418
      @cooldown_t=180
      return nil, 'limited'
    return cjson.decode body
