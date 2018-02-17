class Klines
  new: (@api,@symbol,@interval='1m',@startTime=nil)=>
    @tbl={}
    @item={}
  next: =>
    @item=table.remove @tbl, 1
    if not @item
      ok,e=@request_next!
      return nil, e unless ok
      return @next!
    return nil unless @item
    {
      @openTime
      @open
      @high
      @low
      @close
      @volume
      @closeTime
      @quoteAssetVolume
      @numberOfTrades
      @takerBuyBaseAssetVolume
      @takerBuyQuoteAssetVolume
    }=@item
    @startTime =@openTime
    @
  request_next: =>
    ok,e=@api\mayRequest endpoint
    return nil,e unless ok
    @tbl = @api\request '/api/v1/klines', {symbol:@symbol, interval:@interval, startTime:@startTime, limit: 500}
    @api\heatup 1
    return true
